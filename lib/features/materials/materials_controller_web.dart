import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import 'browser_store.dart';
import 'image_codec.dart';
import 'materials_api.dart';

/// Web storage is partitioned by the authenticated MTT user. The durable outbox
/// retries while the page is open; the native implementation owns mobile jobs.
class MaterialsController extends ChangeNotifier {
  MaterialsController._(this.client) {
    _retry = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_pending.isNotEmpty && _owner != null && !busy) unawaited(kick());
    });
  }
  Timer? _retry;
  static Future<MaterialsController> open(ApiClient client) async =>
      MaterialsController._(client);
  final ApiClient client;
  final _store = BrowserStore();
  MaterialsDay? day;
  String? error;
  String query = '';
  String location = '';
  bool loading = false;
  bool busy = false;
  bool _disposed = false;
  String? _owner;
  List<Map<String, dynamic>> _pending = [];
  int get pendingCount => _pending.length;
  int get failedCount => _pending.where((item) => item['error'] != null).length;
  List<Map<String, dynamic>> get pending => List.unmodifiable(_pending);
  List<MaterialItem> get visible => [
    for (final item in day?.materials ?? <MaterialItem>[])
      if ((location.isEmpty || item.location == location) &&
          item.name.toLowerCase().contains(query.toLowerCase()))
        item,
  ];

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> rememberToken(String? token) async {
    if (token == null) {
      if (_owner != null) _store.release(_owner!);
      _owner = null;
      day = null;
      _pending = [];
      error = null;
      _notify();
      return;
    }
    try {
      final me = await client.get('me.php');
      if (client.token != token) return;
      final owner = '${me['user']['id']}';
      if (!await _store.lock(owner)) {
        error =
            'Materials are open in another tab, or this browser cannot safely save checks. Close the other tab and reload in a current browser.';
        _notify();
        return;
      }
      if (client.token != token) {
        _store.release(owner);
        return;
      }
      if (_owner != null && _owner != owner) _store.release(_owner!);
      _owner = owner;
      final saved = await _store.read('materials:$owner');
      if (_owner != owner) return;
      if (saved.isNotEmpty) {
        final data = jsonDecode(saved) as Map<String, dynamic>;
        day = data['day'] == null
            ? null
            : MaterialsDay.fromJson(data['day'] as Map<String, dynamic>);
        _pending = [
          for (final item in data['pending'] as List? ?? [])
            Map<String, dynamic>.from(item),
        ];
      }
      _notify();
      if ((me['modules'] as List).any((m) => m['key'] == 'materials')) {
        await kick();
      }
    } catch (_) {
      error = 'Could not open your saved checks. Reconnect and sign in again.';
      _notify();
    }
  }

  Future<void> _save() async {
    final owner = _owner;
    if (owner == null) {
      throw ApiException('Sign in again before saving a check.');
    }
    await _store.write(
      'materials:$owner',
      jsonEncode({'day': day?.toJson(), 'pending': _pending}),
    );
  }

  Future<void> kick() async {
    if (busy || _owner == null) return;
    busy = true;
    loading = day == null;
    _notify();
    final owner = _owner;
    try {
      // Do not skip a failed item: later marks and media depend on its order.
      while (_pending.isNotEmpty && _owner == owner) {
        final item = _pending.first;
        final fields = Map<String, dynamic>.from(item['fields'] as Map);
        try {
          if (item['op'] == 'media') {
            await client.postMultipartBytes(
              'materials/media.php',
              fields: fields.map((key, value) => MapEntry(key, '$value')),
              bytes: base64Decode(item['bytes'] as String),
              filename: item['filename'] as String,
            );
          } else {
            await client.post('materials/${item['op']}.php', fields);
          }
          if (_owner != owner) return;
          _pending.removeAt(0);
          await _save();
        } on ApiException catch (e) {
          if (_owner != owner) return;
          item['error'] = e.message;
          await _save();
          break;
        }
      }
      final fresh = await MaterialsApi(client).today();
      if (_owner != owner) return;
      day = fresh;
      error = null;
      await _save();
    } catch (_) {
      if (_owner == owner) {
        error =
            'You’re offline or the server is unavailable. Saved checks will retry when you reconnect.';
      }
    } finally {
      busy = false;
      loading = false;
      _notify();
    }
  }

  Future<void> _enqueue(
    String op,
    Map<String, dynamic> fields, {
    Uint8List? bytes,
    String? filename,
    List<int>? materialIds,
  }) async {
    if (_owner == null) {
      throw ApiException('Wait for your school workspace to finish loading.');
    }
    final id = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final item = <String, dynamic>{
      'op': op,
      'material_ids': ?materialIds,
      'fields': {...fields, 'client_key': id},
      if (bytes != null) 'bytes': base64Encode(bytes),
      'filename': ?filename,
    };
    _pending.add(item);
    try {
      await _save();
    } catch (_) {
      _pending.remove(item);
      throw ApiException(
        'Browser storage is full or unavailable. Nothing was saved. Free space and try again.',
      );
    }
    _notify();
    await kick();
  }

  String? conditionFor(MaterialItem item) {
    for (final entry in _pending.reversed) {
      final fields = entry['fields'] as Map;
      if (entry['op'] == 'mark' && fields['material_id'] == item.id) {
        return fields['condition_code'] as String;
      }
      if (entry['op'] == 'bulk_good' &&
          (entry['material_ids'] as List? ?? []).contains(item.id)) {
        return 'good';
      }
    }
    return item.check?.conditionCode;
  }

  String notesFor(MaterialItem item) {
    for (final entry in _pending.reversed) {
      final fields = entry['fields'] as Map;
      if (entry['op'] == 'mark' && fields['material_id'] == item.id) {
        return fields['notes'] as String? ?? '';
      }
    }
    return item.check?.notes ?? '';
  }

  Future<void> setCondition(int id, String code, String notes) =>
      _enqueue('mark', {
        'material_id': id,
        'date': day!.date,
        'condition_code': code,
        'notes': notes,
      });
  Future<void> markRestGood(String shelf) => _enqueue(
    'bulk_good',
    {'date': day!.date, 'scope': shelf},
    materialIds: [
      for (final item in day!.materials)
        if (item.location == shelf && conditionFor(item) == null) item.id,
    ],
  );
  Future<void> addMedia(
    MaterialItem item,
    Uint8List bytes,
    String filename,
    bool video,
  ) async {
    if (conditionFor(item) == null) {
      throw ApiException('Choose a condition before attaching a file.');
    }
    if (bytes.length > (day?.uploadLimit ?? 40 * 1024 * 1024)) {
      throw ApiException(
        'This file is too large for the school server. Choose a smaller file.',
      );
    }
    if (!video) {
      try {
        bytes = compressMaterialsPhoto(bytes);
        filename = '${filename.split('.').first}.jpg';
      } on FormatException {
        throw ApiException(
          'Choose a JPEG or PNG photo. This photo format is not supported.',
        );
      }
    }
    await _enqueue(
      'media',
      {'material_id': item.id, 'date': day!.date},
      bytes: bytes,
      filename: filename,
    );
  }

  void setQuery(String value) {
    query = value;
    _notify();
  }

  void setLocation(String value) {
    location = value;
    _notify();
  }

  @override
  void dispose() {
    _retry?.cancel();
    _disposed = true;
    super.dispose();
  }
}
