import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import 'image_codec.dart';
import 'materials_api.dart';
import 'materials_background.dart';
import 'materials_platform.dart';
import 'materials_queue.dart';
import 'materials_sqlite.dart';

class MaterialView {
  MaterialView({
    required this.item,
    required this.conditionCode,
    required this.conditionLabel,
    required this.tone,
    required this.notes,
    required this.line,
    required this.mark,
    required this.localMedia,
  });

  final MaterialItem item;
  final String? conditionCode;
  final String conditionLabel;
  final String tone;
  final String notes;
  final String line;
  final OutboxItem? mark;
  final List<OutboxItem> localMedia;

  bool get checked => conditionCode != null && conditionCode!.isNotEmpty;
}

/// The daily sheet plus the phone's upload queue.
class MaterialsController extends ChangeNotifier {
  MaterialsController({
    required this.api,
    required this.queue,
    MaterialsDay? initial,
  }) : day = initial {
    queue.onChanged = _onQueueChanged;
    queue.uploadLimitBytes = () => day?.uploadLimit ?? 40 * 1024 * 1024;
  }

  static Future<MaterialsController> open(
    ApiClient client, {
    int? userId,
  }) async {
    final store = await SqliteMaterialsStore.open(userId: userId);
    final docs = await getApplicationDocumentsDirectory();
    final api = MaterialsApi(client);
    final queue = MaterialsQueue(
      store: store,
      root: Directory(
        '${docs.path}/materials_outbox/${userId ?? 'unassigned'}',
      ),
      transport: ApiMaterialsTransport(
        api,
        baseUrl: AppConfig.baseUrl,
        token: () => client.token,
      ),
      bridge: ChannelMaterialsBridge(),
      scheduler: WorkmanagerMaterialsScheduler(),
      compressPhotoBytes: (bytes) => compute(
        compressMaterialsPhotoBytes,
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      ),
    );
    final controller = MaterialsController(api: api, queue: queue);
    controller._bound = userId != null;
    if (userId != null) {
      await controller._loadCache();
      await controller.reloadLocal();
    }
    return controller;
  }

  MaterialsApi api;
  MaterialsQueue queue;
  Future<void> _binding = Future.value();
  int _bindingVersion = 0;
  bool _bound = true;

  MaterialsDay? day;
  List<OutboxItem> outbox = [];
  String? error;
  bool loading = false;
  String query = '';
  String location = '';
  bool _disposed = false;

  int get pendingCount => outbox.where((item) => item.open).length;

  int get failedCount =>
      outbox.where((item) => item.status == OutboxStatus.failed).length;

  Future<void> rememberToken(String? token, {int? userId}) {
    final version = ++_bindingVersion;
    _bound = false;
    day = null;
    outbox = [];
    error = null;
    loading = false;
    query = '';
    location = '';
    queue.onChanged = null;
    queue.paused = true;
    _notify();
    _binding = _binding
        .catchError((Object error) {})
        .then((_) async {
          final registry = await SqliteMaterialsStore.open();
          await registry.setMeta('token', '');
          await registry.setMeta('active_user', '');
          await queue.rememberToken(null);
          while (queue.draining) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          if (version != _bindingVersion || token == null || userId == null) {
            return;
          }
          final client = ApiClient()..token = token;
          final replacement = await MaterialsController.open(
            client,
            userId: userId,
          );
          if (version != _bindingVersion) return;
          api = replacement.api;
          queue = replacement.queue;
          queue.onChanged = _onQueueChanged;
          day = replacement.day;
          outbox = replacement.outbox;
          _bound = true;
          await queue.rememberToken(token);
          if (!_current(version)) return;
          await registry.setMeta('active_user', '$userId');
          if (!_current(version)) return;
          await kick();
        })
        .catchError((Object failure) {
          if (version == _bindingVersion) {
            _bound = false;
            error = 'Could not open your saved checks. Sign in again to retry.';
            _notify();
          }
        });
    return _binding;
  }

  Future<void> kick() async {
    if (!_bound) return;
    final version = _bindingVersion;
    final targetQueue = queue;
    await refresh();
    if (!_current(version)) return;
    final outcome = await targetQueue.drain();
    if (!_current(version)) return;
    if (outcome.uploadedAny) await refresh();
    await reloadLocal();
  }

  Future<void> refresh() async {
    if (!_bound) return;
    final version = _bindingVersion;
    final targetQueue = queue;
    if (day == null) {
      loading = true;
      _notify();
    }
    try {
      final fresh = await api.today();
      if (!_current(version)) return;
      day = fresh;
      queue.uploadLimitBytes = () => day?.uploadLimit ?? 40 * 1024 * 1024;
      await targetQueue.store.setMeta(
        'materials_day',
        jsonEncode(fresh.toJson()),
      );
      if (!_current(version)) return;
      await targetQueue.store.purgeUploaded();
      if (!_current(version)) return;
      error = null;
    } on ApiException catch (e) {
      if (!_current(version)) return;
      error = e.message;
      await _loadCache();
    } finally {
      if (_current(version)) {
        loading = false;
        await reloadLocal();
      }
    }
  }

  Future<void> setCondition(
    int materialId,
    String conditionCode,
    String notes,
  ) async {
    if (!_bound) return;
    final version = _bindingVersion;
    final targetQueue = queue;
    final item = _item(materialId);
    if (item == null || conditionCode.isEmpty) return;
    await targetQueue.enqueueMark(
      materialId: materialId,
      checkDate: _date,
      location: item.location,
      conditionCode: conditionCode,
      notes: notes,
    );
    if (!_current(version)) return;
    await reloadLocal();
    await targetQueue.drain();
    if (_current(version)) await refresh();
  }

  Future<void> setNotes(
    int materialId,
    String notes, {
    bool sync = true,
  }) async {
    if (!_bound) return;
    final version = _bindingVersion;
    final targetQueue = queue;
    final view = viewFor(_item(materialId));
    if (view == null ||
        view.conditionCode == null ||
        view.conditionCode!.isEmpty) {
      return;
    }
    if (!sync || view.notes != notes) {
      await targetQueue.enqueueMark(
        materialId: materialId,
        checkDate: _date,
        location: view.item.location,
        conditionCode: view.conditionCode!,
        notes: notes,
      );
    }
    if (!_current(version)) return;
    await reloadLocal();
    if (!sync || !_current(version)) return;
    final outcome = await targetQueue.drain();
    if (_current(version) && outcome.uploadedAny) await refresh();
  }

  Future<void> addMedia(
    int materialId, {
    required File source,
    required String filename,
    required String mediaKind,
  }) async {
    if (!_bound) return;
    final version = _bindingVersion;
    final targetQueue = queue;
    final item = _item(materialId);
    if (item == null) return;
    final view = viewFor(item);
    await targetQueue.enqueueMedia(
      materialId: materialId,
      checkDate: _date,
      location: item.location,
      source: source,
      filename: filename,
      mediaKind: mediaKind,
      hasCondition: view?.checked ?? false,
    );
    if (!_current(version)) return;
    await reloadLocal();
    final outcome = await targetQueue.drain();
    if (_current(version) && outcome.uploadedAny) await refresh();
  }

  Future<void> markRestGood(String shelf) async {
    if (!_bound) return;
    final version = _bindingVersion;
    final targetQueue = queue;
    await targetQueue.enqueueBulkGood(checkDate: _date, scope: shelf);
    if (!_current(version)) return;
    await reloadLocal();
    final outcome = await targetQueue.drain();
    if (_current(version) && outcome.uploadedAny) await refresh();
  }

  Future<void> retryItem(int id) async {
    if (!_bound) return;
    final version = _bindingVersion;
    final targetQueue = queue;
    await targetQueue.retry(id);
    if (!_current(version)) return;
    await reloadLocal();
    final outcome = await targetQueue.drain();
    if (_current(version) && outcome.uploadedAny) await refresh();
  }

  void setQuery(String value) {
    query = value;
    _notify();
  }

  void setLocation(String value) {
    location = value;
    _notify();
  }

  MaterialView? viewFor(MaterialItem? item) {
    if (item == null) return null;
    final mark = _openMark(item.id);
    final condition =
        (mark != null &&
            mark.conditionCode != null &&
            mark.conditionCode!.isNotEmpty)
        ? mark.conditionCode
        : item.check?.conditionCode;
    final label = _label(condition) ?? item.check?.label ?? '';
    final tone = _tone(condition) ?? item.check?.tone ?? '';
    final notes = mark?.notes ?? item.check?.notes ?? '';
    return MaterialView(
      item: item,
      conditionCode: condition == null || condition.isEmpty ? null : condition,
      conditionLabel: label,
      tone: tone,
      notes: notes,
      line: _line(item, mark),
      mark: mark,
      localMedia: [
        for (final entry in outbox)
          if (entry.kind == OutboxKind.media &&
              entry.checkDate == _date &&
              entry.materialId == item.id &&
              entry.open)
            entry,
      ],
    );
  }

  List<MaterialItem> get visible {
    final items = day?.materials ?? const <MaterialItem>[];
    return [
      for (final item in items)
        if (_matches(item)) item,
    ];
  }

  Map<String, List<MaterialItem>> get shelves {
    final grouped = <String, List<MaterialItem>>{};
    for (final item in visible) {
      grouped.putIfAbsent(item.location, () => []).add(item);
    }
    return grouped;
  }

  Future<void> reloadLocal() async {
    final version = _bindingVersion;
    if (!_bound) return;
    final entries = await queue.store.all();
    if (!_bound || version != _bindingVersion) return;
    outbox = entries;
    _notify();
  }

  Future<void> _loadCache() async {
    if (day != null) return;
    final version = _bindingVersion;
    final raw = await queue.store.getMeta('materials_day');
    if (!_current(version)) return;
    if (raw == null || raw.isEmpty) return;
    try {
      day = MaterialsDay.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      day = null;
    } on TypeError {
      day = null;
    }
  }

  MaterialItem? _item(int id) {
    for (final item in day?.materials ?? const <MaterialItem>[]) {
      if (item.id == id) return item;
    }
    return null;
  }

  OutboxItem? _openMark(int materialId) {
    for (final item in outbox) {
      if (item.kind == OutboxKind.mark &&
          item.checkDate == _date &&
          item.materialId == materialId &&
          item.open) {
        return item;
      }
    }
    return null;
  }

  String? _label(String? code) {
    if (code == null) return null;
    for (final condition in day?.conditions ?? const <MaterialCondition>[]) {
      if (condition.code == code) return condition.label;
    }
    return null;
  }

  String? _tone(String? code) {
    if (code == null) return null;
    for (final condition in day?.conditions ?? const <MaterialCondition>[]) {
      if (condition.code == code) return condition.tone;
    }
    return null;
  }

  String _line(MaterialItem item, OutboxItem? mark) {
    if (mark != null) {
      if (mark.status == OutboxStatus.failed) {
        return mark.lastError ?? 'Not saved';
      }
      if (mark.status == OutboxStatus.uploading) return 'Saving…';
      return 'Saved on this phone';
    }
    final check = item.check;
    if (check == null) return 'Not checked today';
    final who = check.by.isEmpty ? '' : ' · ${check.by}';
    final at = check.at.isEmpty ? '' : ' · ${check.at}';
    return '${check.label}$who$at';
  }

  bool _matches(MaterialItem item) {
    if (location.isNotEmpty && item.location != location) return false;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return item.name.toLowerCase().contains(q);
  }

  String get _date {
    if (day != null && day!.date.isNotEmpty) return day!.date;
    final n = DateTime.now();
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d';
  }

  void _onQueueChanged() {
    reloadLocal();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int version) =>
      !_disposed && _bound && version == _bindingVersion;

  @override
  void dispose() {
    _disposed = true;
    ++_bindingVersion;
    _bound = false;
    queue.paused = true;
    queue.onChanged = null;
    super.dispose();
  }
}

String mediaStatusLabel(OutboxItem item) {
  switch (item.status) {
    case OutboxStatus.waiting:
      return 'Kept on this phone — pick a condition and it uploads';
    case OutboxStatus.pending:
    case OutboxStatus.ready:
      return 'Waiting to upload';
    case OutboxStatus.compressing:
      return 'Preparing…';
    case OutboxStatus.uploading:
      return 'Uploading…';
    case OutboxStatus.failed:
      return item.lastError ?? 'Not uploaded';
    case OutboxStatus.uploaded:
      return 'Uploaded';
  }
}
