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
  MaterialsController({required this.api, required this.queue, MaterialsDay? initial}) : day = initial {
    queue.onChanged = _onQueueChanged;
    queue.uploadLimitBytes = () => day?.uploadLimit ?? 40 * 1024 * 1024;
  }

  static Future<MaterialsController> open(ApiClient client) async {
    final store = await SqliteMaterialsStore.open();
    final docs = await getApplicationDocumentsDirectory();
    final api = MaterialsApi(client);
    final queue = MaterialsQueue(
      store: store,
      root: Directory('${docs.path}/materials_outbox'),
      transport: ApiMaterialsTransport(api, baseUrl: AppConfig.baseUrl, token: () => client.token),
      bridge: ChannelMaterialsBridge(),
      scheduler: WorkmanagerMaterialsScheduler(),
      compressPhotoBytes: (bytes) => compute(
        compressMaterialsPhotoBytes,
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      ),
    );
    final controller = MaterialsController(api: api, queue: queue);
    await controller._loadCache();
    await controller.reloadLocal();
    return controller;
  }

  final MaterialsApi api;
  final MaterialsQueue queue;

  MaterialsDay? day;
  List<OutboxItem> outbox = [];
  String? error;
  bool loading = false;
  String query = '';
  String location = '';
  bool _disposed = false;

  int get pendingCount => outbox.where((item) => item.open).length;

  int get failedCount => outbox.where((item) => item.status == OutboxStatus.failed).length;

  Future<void> rememberToken(String? token) async {
    await queue.rememberToken(token);
    if (token != null && token.isNotEmpty) {
      await kick();
    } else {
      await reloadLocal();
    }
  }

  Future<void> kick() async {
    await refresh();
    final outcome = await queue.drain();
    if (outcome.uploadedAny) await refresh();
    await reloadLocal();
  }

  Future<void> refresh() async {
    if (day == null) {
      loading = true;
      _notify();
    }
    try {
      day = await api.today();
      queue.uploadLimitBytes = () => day?.uploadLimit ?? 40 * 1024 * 1024;
      await queue.store.setMeta('materials_day', jsonEncode(day!.toJson()));
      await queue.store.purgeUploaded();
      error = null;
    } on ApiException catch (e) {
      error = e.message;
      await _loadCache();
    } finally {
      loading = false;
      await reloadLocal();
    }
  }

  Future<void> setCondition(int materialId, String conditionCode, String notes) async {
    final item = _item(materialId);
    if (item == null || conditionCode.isEmpty) return;
    await queue.enqueueMark(
      materialId: materialId,
      checkDate: _date,
      location: item.location,
      conditionCode: conditionCode,
      notes: notes,
    );
    await reloadLocal();
    await queue.drain();
    await refresh();
  }

  Future<void> setNotes(int materialId, String notes) async {
    final view = viewFor(_item(materialId));
    if (view == null || view.conditionCode == null || view.conditionCode!.isEmpty) return;
    if (view.notes == notes && view.mark == null) return;
    if (view.mark != null && view.mark!.notes == notes && view.mark!.conditionCode == view.conditionCode) return;
    await queue.enqueueMark(
      materialId: materialId,
      checkDate: _date,
      location: view.item.location,
      conditionCode: view.conditionCode!,
      notes: notes,
    );
    await reloadLocal();
    final outcome = await queue.drain();
    if (outcome.uploadedAny) await refresh();
  }

  Future<void> addMedia(int materialId, {required File source, required String filename, required String mediaKind}) async {
    final item = _item(materialId);
    if (item == null) return;
    final view = viewFor(item);
    await queue.enqueueMedia(
      materialId: materialId,
      checkDate: _date,
      location: item.location,
      source: source,
      filename: filename,
      mediaKind: mediaKind,
      hasCondition: view?.checked ?? false,
    );
    await reloadLocal();
    final outcome = await queue.drain();
    if (outcome.uploadedAny) await refresh();
  }

  Future<void> markRestGood(String shelf) async {
    await queue.enqueueBulkGood(checkDate: _date, scope: shelf);
    await reloadLocal();
    final outcome = await queue.drain();
    if (outcome.uploadedAny) await refresh();
  }

  Future<void> retryItem(int id) async {
    await queue.retry(id);
    await reloadLocal();
    final outcome = await queue.drain();
    if (outcome.uploadedAny) await refresh();
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
    final condition = (mark != null && mark.conditionCode != null && mark.conditionCode!.isNotEmpty)
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
          if (entry.kind == OutboxKind.media && entry.materialId == item.id && entry.open) entry,
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
    outbox = await queue.store.all();
    _notify();
  }

  Future<void> _loadCache() async {
    if (day != null) return;
    final raw = await queue.store.getMeta('materials_day');
    if (raw == null || raw.isEmpty) return;
    try {
      day = MaterialsDay.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
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
      if (item.kind == OutboxKind.mark && item.materialId == materialId && item.open) return item;
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
      if (mark.status == OutboxStatus.failed) return mark.lastError ?? 'Not saved';
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

  @override
  void dispose() {
    _disposed = true;
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
