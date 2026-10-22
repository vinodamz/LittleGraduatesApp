import 'dart:io';
import 'dart:math';

import '../../core/api_client.dart';
import 'image_codec.dart';
import 'materials_api.dart';

const _keep = Object();

/// Idempotency id sent with every upload. The server stores it on the media
/// row so a retry cannot attach the same photo twice.
final materialsClientKeyPattern = RegExp(r'^[A-Za-z0-9-]{8,80}$');

String newMaterialsClientKey() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final key = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  return key;
}

enum OutboxKind { mark, bulkGood, media }

enum OutboxStatus { pending, compressing, ready, uploading, waiting, failed, uploaded }

class OutboxItem {
  OutboxItem({
    this.id,
    required this.clientKey,
    required this.kind,
    required this.checkDate,
    this.materialId,
    this.location = '',
    this.scope = '',
    this.conditionCode,
    this.notes = '',
    this.originalPath,
    this.uploadPath,
    this.mediaKind = '',
    this.filename = '',
    this.mime = '',
    required this.status,
    this.attempts = 0,
    this.generation = 1,
    this.sentGeneration,
    this.errorCode,
    this.lastError,
    this.uploadChannel = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String clientKey;
  final OutboxKind kind;
  final String checkDate;
  final int? materialId;
  final String location;
  final String scope;
  final String? conditionCode;
  final String notes;
  final String? originalPath;
  final String? uploadPath;
  final String mediaKind;
  final String filename;
  final String mime;
  final OutboxStatus status;
  final int attempts;
  final int generation;
  final int? sentGeneration;
  final String? errorCode;
  final String? lastError;
  final String uploadChannel;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get open => status != OutboxStatus.uploaded;

  OutboxItem copyWith({
    int? id,
    OutboxStatus? status,
    int? attempts,
    int? generation,
    Object? sentGeneration = _keep,
    Object? conditionCode = _keep,
    Object? notes = _keep,
    Object? originalPath = _keep,
    Object? uploadPath = _keep,
    Object? filename = _keep,
    Object? mime = _keep,
    Object? errorCode = _keep,
    Object? lastError = _keep,
    Object? uploadChannel = _keep,
    DateTime? updatedAt,
  }) {
    return OutboxItem(
      id: id ?? this.id,
      clientKey: clientKey,
      kind: kind,
      checkDate: checkDate,
      materialId: materialId,
      location: location,
      scope: scope,
      conditionCode: conditionCode == _keep ? this.conditionCode : conditionCode as String?,
      notes: notes == _keep ? this.notes : notes as String,
      originalPath: originalPath == _keep ? this.originalPath : originalPath as String?,
      uploadPath: uploadPath == _keep ? this.uploadPath : uploadPath as String?,
      mediaKind: mediaKind,
      filename: filename == _keep ? this.filename : filename as String,
      mime: mime == _keep ? this.mime : mime as String,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      generation: generation ?? this.generation,
      sentGeneration: sentGeneration == _keep ? this.sentGeneration : sentGeneration as int?,
      errorCode: errorCode == _keep ? this.errorCode : errorCode as String?,
      lastError: lastError == _keep ? this.lastError : lastError as String?,
      uploadChannel: uploadChannel == _keep ? this.uploadChannel : uploadChannel as String,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

abstract class MaterialsStore {
  Future<List<OutboxItem>> all();
  Future<OutboxItem?> get(int id);
  Future<OutboxItem> insert(OutboxItem item);
  Future<void> update(OutboxItem item);
  Future<bool> claim(int id, {required OutboxStatus from, required OutboxStatus to, required DateTime updatedAt});
  Future<void> setMeta(String key, String value);
  Future<String?> getMeta(String key);
  Future<void> requeueAuthFailures(DateTime updatedAt);
  Future<void> purgeUploaded();
}

class MemoryMaterialsStore implements MaterialsStore {
  final items = <OutboxItem>[];
  final meta = <String, String>{};
  int _next = 1;

  @override
  Future<List<OutboxItem>> all() async => List<OutboxItem>.from(items);

  @override
  Future<OutboxItem?> get(int id) async {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<OutboxItem> insert(OutboxItem item) async {
    final saved = item.copyWith(id: _next++);
    items.add(saved);
    return saved;
  }

  @override
  Future<void> update(OutboxItem item) async {
    final index = items.indexWhere((e) => e.id == item.id);
    if (index >= 0) items[index] = item;
  }

  @override
  Future<bool> claim(int id, {required OutboxStatus from, required OutboxStatus to, required DateTime updatedAt}) async {
    final index = items.indexWhere((e) => e.id == id && e.status == from);
    if (index < 0) return false;
    items[index] = items[index].copyWith(status: to, updatedAt: updatedAt);
    return true;
  }

  @override
  Future<void> setMeta(String key, String value) async => meta[key] = value;

  @override
  Future<String?> getMeta(String key) async => meta[key];

  @override
  Future<void> requeueAuthFailures(DateTime updatedAt) async {
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.status == OutboxStatus.failed && item.errorCode == 'auth') {
        items[i] = item.copyWith(status: OutboxStatus.pending, attempts: 0, errorCode: null, lastError: null, updatedAt: updatedAt);
      }
    }
  }

  @override
  Future<void> purgeUploaded() async {
    items.removeWhere((item) => item.status == OutboxStatus.uploaded);
  }
}

class VideoInfo {
  const VideoInfo(this.width, this.height);

  final int width;
  final int height;
}

class BackgroundUploadRequest {
  BackgroundUploadRequest({
    required this.clientKey,
    required this.url,
    required this.headers,
    required this.fields,
    required this.filePath,
    required this.filename,
    required this.mime,
  });

  final String clientKey;
  final String url;
  final Map<String, String> headers;
  final Map<String, String> fields;
  final String filePath;
  final String filename;
  final String mime;
}

class BackgroundUploadResult {
  BackgroundUploadResult({required this.clientKey, required this.status, this.body = '', this.error});

  final String clientKey;
  final int status;
  final String body;
  final String? error;

  bool get ok {
    if (error != null && error!.isNotEmpty) return false;
    return status == 200 && body.contains('"ok":true');
  }
}

/// Thrown when a photo or video needs the phone's encoder and this process
/// does not have it (the Android background worker).
class NeedsDeviceCompressor implements Exception {}

abstract class MaterialsBridge {
  bool get supportsBackgroundUpload;
  bool get canTranscode;

  Future<VideoInfo?> videoInfo(String path);
  Future<void> transcodeVideo(String source, String dest);
  Future<void> compressImageNative(String source, String dest);
  Future<void> enqueueBackgroundUpload(BackgroundUploadRequest request);
  Future<List<BackgroundUploadResult>> takeUploadResults();
  Future<Set<String>> inFlightUploads();
}

class UnavailableBridge implements MaterialsBridge {
  const UnavailableBridge();

  @override
  bool get supportsBackgroundUpload => false;

  @override
  bool get canTranscode => false;

  @override
  Future<VideoInfo?> videoInfo(String path) async => null;

  @override
  Future<void> transcodeVideo(String source, String dest) async => throw NeedsDeviceCompressor();

  @override
  Future<void> compressImageNative(String source, String dest) async => throw NeedsDeviceCompressor();

  @override
  Future<void> enqueueBackgroundUpload(BackgroundUploadRequest request) async {}

  @override
  Future<List<BackgroundUploadResult>> takeUploadResults() async => const [];

  @override
  Future<Set<String>> inFlightUploads() async => const {};
}

abstract class UploadScheduler {
  Future<void> schedule();
}

class NoopScheduler implements UploadScheduler {
  const NoopScheduler();

  @override
  Future<void> schedule() async {}
}

abstract class MaterialsTransport {
  Future<void> mark(OutboxItem item);
  Future<void> bulkGood(OutboxItem item);
  Future<void> uploadMedia(OutboxItem item);
  Future<void> uploadMediaBackground(OutboxItem item, MaterialsBridge bridge);
}

class ApiMaterialsTransport implements MaterialsTransport {
  ApiMaterialsTransport(this.materials, {required this.baseUrl, required this.token});

  final MaterialsApi materials;
  final String baseUrl;
  final String? Function() token;

  @override
  Future<void> mark(OutboxItem item) {
    return materials.mark(
      materialId: item.materialId ?? 0,
      date: item.checkDate,
      conditionCode: item.conditionCode ?? '',
      notes: item.notes,
      clientKey: item.clientKey,
    );
  }

  @override
  Future<void> bulkGood(OutboxItem item) {
    return materials.bulkGood(date: item.checkDate, scope: item.scope, clientKey: item.clientKey);
  }

  @override
  Future<void> uploadMedia(OutboxItem item) {
    final path = item.uploadPath ?? item.originalPath;
    if (path == null) throw ApiException('The photo is missing on this phone.');
    return materials.uploadFile(
      materialId: item.materialId ?? 0,
      date: item.checkDate,
      clientKey: item.clientKey,
      filePath: path,
      filename: item.filename.isEmpty ? 'upload.bin' : item.filename,
    );
  }

  @override
  Future<void> uploadMediaBackground(OutboxItem item, MaterialsBridge bridge) {
    final path = item.uploadPath ?? item.originalPath;
    if (path == null) throw ApiException('The photo is missing on this phone.');
    final auth = token();
    return bridge.enqueueBackgroundUpload(BackgroundUploadRequest(
      clientKey: item.clientKey,
      url: '$baseUrl/api/v1/materials/media.php',
      headers: {
        'Accept': 'application/json',
        'User-Agent': ApiClient.userAgent,
        if (auth != null && auth.isNotEmpty) 'Authorization': 'Bearer $auth',
      },
      fields: {
        'material_id': '${item.materialId ?? 0}',
        'date': item.checkDate,
        'client_key': item.clientKey,
      },
      filePath: path,
      filename: item.filename.isEmpty ? 'upload.bin' : item.filename,
      mime: item.mime.isEmpty ? 'application/octet-stream' : item.mime,
    ));
  }
}

class DrainOutcome {
  bool retry = false;
  bool uploadedAny = false;
}

enum _Step { progress, retry, skip, uploaded }

/// Local queue. A mark or a photo is on disk before this returns, and a later
/// [drain] uploads it. Closing the app does not drop the row.
class MaterialsQueue {
  MaterialsQueue({
    required this.store,
    required this.root,
    required this.transport,
    required this.bridge,
    required this.scheduler,
    required this.compressPhotoBytes,
    this.uploadLimitBytes,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final MaterialsStore store;
  final Directory root;
  final MaterialsTransport transport;
  final MaterialsBridge bridge;
  final UploadScheduler scheduler;
  final Future<List<int>> Function(List<int> bytes) compressPhotoBytes;
  int Function()? uploadLimitBytes;
  final DateTime Function() now;
  void Function()? onChanged;

  bool _draining = false;
  bool _again = false;

  int get _limit => uploadLimitBytes?.call() ?? 40 * 1024 * 1024;

  Future<OutboxItem> enqueueMark({
    required int materialId,
    required String checkDate,
    required String location,
    required String conditionCode,
    required String notes,
  }) async {
    final existing = (await store.all()).where((item) {
      return item.kind == OutboxKind.mark &&
          item.materialId == materialId &&
          item.checkDate == checkDate &&
          item.status != OutboxStatus.uploaded;
    }).toList();
    final OutboxItem saved;
    if (existing.isEmpty) {
      saved = await store.insert(OutboxItem(
        clientKey: newMaterialsClientKey(),
        kind: OutboxKind.mark,
        checkDate: checkDate,
        materialId: materialId,
        location: location,
        conditionCode: conditionCode,
        notes: notes,
        status: OutboxStatus.pending,
        createdAt: now(),
        updatedAt: now(),
      ));
    } else {
      final current = existing.first;
      saved = current.copyWith(
        conditionCode: conditionCode,
        notes: notes,
        generation: current.generation + 1,
        status: current.status == OutboxStatus.uploading ? OutboxStatus.uploading : OutboxStatus.pending,
        errorCode: null,
        lastError: null,
        updatedAt: now(),
      );
      await store.update(saved);
    }
    await _releaseWaiting(date: checkDate, materialId: materialId);
    await scheduler.schedule();
    _changed();
    return saved;
  }

  Future<OutboxItem> enqueueBulkGood({required String checkDate, required String scope}) async {
    final open = (await store.all()).where((item) {
      return item.kind == OutboxKind.bulkGood &&
          item.checkDate == checkDate &&
          item.scope == scope &&
          item.status != OutboxStatus.uploaded &&
          item.status != OutboxStatus.failed;
    });
    if (open.isNotEmpty) return open.first;
    final saved = await store.insert(OutboxItem(
      clientKey: newMaterialsClientKey(),
      kind: OutboxKind.bulkGood,
      checkDate: checkDate,
      scope: scope,
      conditionCode: 'good',
      status: OutboxStatus.pending,
      createdAt: now(),
      updatedAt: now(),
    ));
    await _releaseWaiting(date: checkDate, scope: scope);
    await scheduler.schedule();
    _changed();
    return saved;
  }

  /// Copies [source] into app storage before returning. The gallery file can
  /// disappear; this copy cannot, until the upload is confirmed.
  Future<OutboxItem> enqueueMedia({
    required int materialId,
    required String checkDate,
    required String location,
    required File source,
    required String filename,
    required String mediaKind,
    required bool hasCondition,
  }) async {
    final key = newMaterialsClientKey();
    final ext = _safeExt(filename, mediaKind);
    final destDir = Directory('${root.path}/originals');
    await destDir.create(recursive: true);
    final dest = File('${destDir.path}/$key$ext');
    await source.copy(dest.path);
    final saved = await store.insert(OutboxItem(
      clientKey: key,
      kind: OutboxKind.media,
      checkDate: checkDate,
      materialId: materialId,
      location: location,
      originalPath: dest.path,
      mediaKind: mediaKind,
      filename: filename.isEmpty ? '$mediaKind$ext' : filename,
      mime: _mimeFor(filename, mediaKind),
      status: hasCondition ? OutboxStatus.pending : OutboxStatus.waiting,
      createdAt: now(),
      updatedAt: now(),
    ));
    await scheduler.schedule();
    _changed();
    return saved;
  }

  Future<void> retry(int id) async {
    final item = await store.get(id);
    if (item == null) return;
    final status = item.kind == OutboxKind.media && item.uploadPath != null ? OutboxStatus.ready : OutboxStatus.pending;
    await store.update(item.copyWith(
      status: item.status == OutboxStatus.waiting ? OutboxStatus.waiting : status,
      attempts: 0,
      errorCode: null,
      lastError: null,
      updatedAt: now(),
    ));
    await scheduler.schedule();
    _changed();
  }

  Future<void> rememberToken(String? token) async {
    await store.setMeta('token', token ?? '');
    if (token != null && token.isNotEmpty) {
      await store.requeueAuthFailures(now());
      _changed();
    }
  }

  Future<DrainOutcome> drain() async {
    if (_draining) {
      _again = true;
      return DrainOutcome();
    }
    _draining = true;
    final outcome = DrainOutcome();
    try {
      do {
        _again = false;
        if (await _recover()) outcome.uploadedAny = true;
        final skipped = <int>{};
        while (true) {
          final all = await store.all();
          final next = _next(all, skipped);
          if (next == null) break;
          final step = await _process(next);
          if (step == _Step.uploaded) outcome.uploadedAny = true;
          if (step == _Step.retry) {
            outcome.retry = true;
            break;
          }
          if (step == _Step.skip && next.id != null) skipped.add(next.id!);
        }
      } while (_again);
    } finally {
      _draining = false;
    }
    if (outcome.retry) await scheduler.schedule();
    return outcome;
  }

  Future<bool> _recover() async {
    var uploaded = false;
    // A headless Android engine has no materials channel. Probing it must not
    // fail the whole drain; there are simply no background-session results.
    final List<BackgroundUploadResult> results;
    try {
      results = await bridge.takeUploadResults();
    } on NeedsDeviceCompressor {
      return false;
    }
    for (final result in results) {
      final all = await store.all();
      OutboxItem? item;
      for (final candidate in all) {
        if (candidate.clientKey == result.clientKey) item = candidate;
      }
      if (item?.id == null) continue;
      if (result.ok) {
        if (await _finishSuccess(item!.id!, item.sentGeneration ?? item.generation)) uploaded = true;
      } else if (result.body.contains('condition_required')) {
        await store.update(item!.copyWith(status: OutboxStatus.waiting, lastError: 'Pick a condition to send this.', updatedAt: now()));
      } else if (result.status == 401) {
        await store.update(item!.copyWith(
          status: OutboxStatus.failed,
          errorCode: 'auth',
          lastError: 'Sign in again to finish uploading.',
          updatedAt: now(),
        ));
      } else if (result.status >= 400 && result.status < 500) {
        await store.update(item!.copyWith(
          status: OutboxStatus.failed,
          errorCode: 'permanent',
          lastError: 'The school server rejected this file.',
          updatedAt: now(),
        ));
      } else {
        final back = item!.uploadPath != null ? OutboxStatus.ready : OutboxStatus.pending;
        await store.update(item.copyWith(
          status: back,
          attempts: item.attempts + 1,
          errorCode: 'network',
          lastError: result.error ?? 'Upload did not finish.',
          uploadChannel: '',
          updatedAt: now(),
        ));
      }
    }

    final Set<String> inflight;
    try {
      inflight = await bridge.inFlightUploads();
    } on NeedsDeviceCompressor {
      return uploaded;
    }
    final fresh = await store.all();
    for (final item in fresh) {
      if (item.id == null) continue;
      if (item.status == OutboxStatus.compressing) {
        await store.update(item.copyWith(status: OutboxStatus.pending, updatedAt: now()));
        continue;
      }
      if (item.status != OutboxStatus.uploading) continue;
      if (item.uploadChannel == 'urlsession') {
        final reported = results.any((r) => r.clientKey == item.clientKey);
        if (!reported && !inflight.contains(item.clientKey)) {
          await store.update(item.copyWith(status: OutboxStatus.ready, uploadChannel: '', updatedAt: now()));
        }
        continue;
      }
      if (now().difference(item.updatedAt) > const Duration(minutes: 10)) {
        final back = item.kind == OutboxKind.media && item.uploadPath != null ? OutboxStatus.ready : OutboxStatus.pending;
        await store.update(item.copyWith(status: back, uploadChannel: '', updatedAt: now()));
      }
    }
    return uploaded;
  }

  OutboxItem? _next(List<OutboxItem> all, Set<int> skipped) {
    final candidates = <OutboxItem>[];
    for (final item in all) {
      if (item.id == null || skipped.contains(item.id)) continue;
      if (item.status != OutboxStatus.pending && item.status != OutboxStatus.ready) continue;
      if (item.kind == OutboxKind.media && _blocked(item, all)) continue;
      candidates.add(item);
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final rank = _rank(a.kind).compareTo(_rank(b.kind));
      if (rank != 0) return rank;
      return a.createdAt.compareTo(b.createdAt);
    });
    return candidates.first;
  }

  Future<_Step> _process(OutboxItem item) async {
    if (item.kind == OutboxKind.media && (item.uploadPath == null || item.uploadPath!.isEmpty)) {
      final claimed = await store.claim(item.id!, from: OutboxStatus.pending, to: OutboxStatus.compressing, updatedAt: now());
      if (!claimed) return _Step.skip;
      try {
        final prepared = await _prepareMedia(item);
        final current = await store.get(item.id!);
        if (current == null) return _Step.skip;
        if (prepared.tooLarge) {
          await store.update(current.copyWith(
            status: OutboxStatus.failed,
            errorCode: 'permanent',
            lastError: 'Still too large after compression. Record a shorter video.',
            updatedAt: now(),
          ));
          _changed();
          return _Step.progress;
        }
        await store.update(current.copyWith(
          status: OutboxStatus.ready,
          uploadPath: prepared.path,
          filename: prepared.filename,
          mime: prepared.mime,
          updatedAt: now(),
        ));
        _changed();
        return _Step.progress;
      } on NeedsDeviceCompressor {
        final current = await store.get(item.id!);
        if (current != null) {
          await store.update(current.copyWith(status: OutboxStatus.pending, updatedAt: now()));
        }
        return _Step.skip;
      } catch (e) {
        final current = await store.get(item.id!);
        if (current != null) {
          final attempts = current.attempts + 1;
          await store.update(current.copyWith(
            status: attempts >= 4 ? OutboxStatus.failed : OutboxStatus.pending,
            attempts: attempts,
            errorCode: 'permanent',
            lastError: 'Could not prepare this file.',
            updatedAt: now(),
          ));
          _changed();
        }
        return _Step.progress;
      }
    }

    final from = item.status == OutboxStatus.ready ? OutboxStatus.ready : OutboxStatus.pending;
    final claimed = await store.claim(item.id!, from: from, to: OutboxStatus.uploading, updatedAt: now());
    if (!claimed) return _Step.skip;
    final sending = await store.get(item.id!);
    if (sending == null) return _Step.skip;
    final channel = sending.kind == OutboxKind.media && bridge.supportsBackgroundUpload ? 'urlsession' : 'dart';
    await store.update(sending.copyWith(sentGeneration: sending.generation, uploadChannel: channel, updatedAt: now()));
    final queued = (await store.get(item.id!))!;
    try {
      if (queued.kind == OutboxKind.mark) {
        await transport.mark(queued);
      } else if (queued.kind == OutboxKind.bulkGood) {
        await transport.bulkGood(queued);
      } else if (channel == 'urlsession') {
        await transport.uploadMediaBackground(queued, bridge);
        _changed();
        return _Step.progress;
      } else {
        await transport.uploadMedia(queued);
      }
      final uploaded = await _finishSuccess(queued.id!, queued.generation);
      return uploaded ? _Step.uploaded : _Step.progress;
    } on ApiException catch (e) {
      return _finishError(queued, e);
    }
  }

  Future<bool> _finishSuccess(int id, int sentGeneration) async {
    final current = await store.get(id);
    if (current == null) return false;
    if (current.kind == OutboxKind.mark && current.generation != sentGeneration) {
      await store.update(current.copyWith(status: OutboxStatus.pending, uploadChannel: '', updatedAt: now()));
      _changed();
      return false;
    }
    await _deleteFiles(current);
    await store.update(current.copyWith(
      status: OutboxStatus.uploaded,
      originalPath: null,
      uploadPath: null,
      errorCode: null,
      lastError: null,
      uploadChannel: '',
      updatedAt: now(),
    ));
    _changed();
    return true;
  }

  Future<_Step> _finishError(OutboxItem item, ApiException error) async {
    final current = await store.get(item.id!);
    if (current == null) return _Step.skip;
    if (error.code == 'condition_required') {
      await store.update(current.copyWith(
        status: OutboxStatus.waiting,
        uploadChannel: '',
        lastError: 'Pick a condition and this will upload.',
        updatedAt: now(),
      ));
      _changed();
      return _Step.progress;
    }
    if (error.isUnauthenticated) {
      await store.update(current.copyWith(
        status: OutboxStatus.failed,
        errorCode: 'auth',
        uploadChannel: '',
        lastError: 'Sign in again to finish uploading.',
        updatedAt: now(),
      ));
      _changed();
      return _Step.progress;
    }
    if (_permanent(error)) {
      await store.update(current.copyWith(
        status: OutboxStatus.failed,
        errorCode: 'permanent',
        uploadChannel: '',
        lastError: error.message,
        updatedAt: now(),
      ));
      _changed();
      return _Step.progress;
    }
    final back = current.kind == OutboxKind.media && current.uploadPath != null ? OutboxStatus.ready : OutboxStatus.pending;
    await store.update(current.copyWith(
      status: back,
      attempts: current.attempts + 1,
      errorCode: 'network',
      uploadChannel: '',
      lastError: error.message,
      updatedAt: now(),
    ));
    _changed();
    return _Step.retry;
  }

  Future<_Prepared> _prepareMedia(OutboxItem item) async {
    final original = File(item.originalPath ?? '');
    if (!await original.exists()) {
      throw ApiException('The photo is missing on this phone.');
    }
    final dir = Directory('${root.path}/compressed');
    await dir.create(recursive: true);
    if (item.mediaKind == 'photo') {
      final dest = File('${dir.path}/${item.clientKey}.jpg');
      try {
        final bytes = await compressPhotoBytes(await original.readAsBytes());
        await dest.writeAsBytes(bytes, flush: true);
      } catch (e) {
        if (!bridge.canTranscode) throw NeedsDeviceCompressor();
        await bridge.compressImageNative(original.path, dest.path);
      }
      return _Prepared(
        path: dest.path,
        filename: 'photo.jpg',
        mime: 'image/jpeg',
        tooLarge: await dest.length() > _limit,
      );
    }

    VideoInfo? info;
    try {
      info = await bridge.videoInfo(original.path);
    } on NeedsDeviceCompressor {
      info = null;
    }
    final bytes = await original.length();
    final needs = videoNeedsTranscode(width: info?.width, height: info?.height, bytes: bytes);
    if (!needs) {
      final ext = _safeExt(item.filename, 'video');
      final dest = File('${dir.path}/${item.clientKey}$ext');
      await original.copy(dest.path);
      return _Prepared(
        path: dest.path,
        filename: item.filename.isEmpty ? 'video$ext' : item.filename,
        mime: item.mime.isEmpty ? 'video/mp4' : item.mime,
        tooLarge: await dest.length() > _limit,
      );
    }
    if (!bridge.canTranscode) throw NeedsDeviceCompressor();
    final dest = File('${dir.path}/${item.clientKey}.mp4');
    if (await dest.exists()) await dest.delete();
    await bridge.transcodeVideo(original.path, dest.path);
    return _Prepared(
      path: dest.path,
      filename: 'video.mp4',
      mime: 'video/mp4',
      tooLarge: await dest.length() > _limit,
    );
  }

  Future<void> _releaseWaiting({required String date, int? materialId, String scope = ''}) async {
    for (final item in await store.all()) {
      if (item.kind != OutboxKind.media || item.status != OutboxStatus.waiting || item.checkDate != date) continue;
      final match = materialId != null ? item.materialId == materialId : (scope.isEmpty || scope == item.location);
      if (!match || item.id == null) continue;
      await store.update(item.copyWith(status: OutboxStatus.pending, updatedAt: now()));
    }
  }

  bool _blocked(OutboxItem media, List<OutboxItem> all) {
    for (final other in all) {
      if (other.id == media.id) continue;
      if (other.status == OutboxStatus.failed || other.status == OutboxStatus.uploaded) continue;
      if (other.checkDate != media.checkDate) continue;
      if (other.kind == OutboxKind.mark && other.materialId == media.materialId) return true;
      if (other.kind == OutboxKind.bulkGood && (other.scope.isEmpty || other.scope == media.location)) return true;
    }
    return false;
  }

  int _rank(OutboxKind kind) => switch (kind) {
        OutboxKind.mark => 0,
        OutboxKind.bulkGood => 1,
        OutboxKind.media => 2,
      };

  bool _permanent(ApiException error) {
    if (error.status == 408 || error.status == 429) return false;
    return error.status >= 400 && error.status < 500;
  }

  Future<void> _deleteFiles(OutboxItem item) async {
    final paths = <String>{if (item.originalPath != null) item.originalPath!, if (item.uploadPath != null) item.uploadPath!};
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  void _changed() => onChanged?.call();
}

class _Prepared {
  _Prepared({required this.path, required this.filename, required this.mime, required this.tooLarge});

  final String path;
  final String filename;
  final String mime;
  final bool tooLarge;
}

String _safeExt(String filename, String mediaKind) {
  final dot = filename.lastIndexOf('.');
  final ext = dot >= 0 ? filename.substring(dot).toLowerCase() : '';
  if (RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(ext)) return ext;
  return mediaKind == 'photo' ? '.jpg' : '.mp4';
}

String _mimeFor(String filename, String mediaKind) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.heic')) return 'image/heic';
  if (lower.endsWith('.mov')) return 'video/quicktime';
  if (lower.endsWith('.webm')) return 'video/webm';
  if (lower.endsWith('.3gp')) return 'video/3gpp';
  if (mediaKind == 'photo') return 'image/jpeg';
  return 'video/mp4';
}
