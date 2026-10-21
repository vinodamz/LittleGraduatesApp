import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:little_graduates/core/api_client.dart';
import 'package:little_graduates/core/module_registry.dart';
import 'package:little_graduates/core/session.dart';
import 'package:little_graduates/features/materials/image_codec.dart';
import 'package:little_graduates/features/materials/materials_api.dart';
import 'package:little_graduates/features/materials/materials_controller.dart';
import 'package:little_graduates/features/materials/materials_queue.dart';
import 'package:little_graduates/features/materials/materials_screen.dart';
import 'package:little_graduates/features/materials/materials_sqlite.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('photos are scaled to 1600px and re-encoded as JPEG', () {
    final wide = img.Image(width: 3200, height: 800);
    img.fill(wide, color: img.ColorRgb8(180, 20, 60));
    final jpg = compressMaterialsPhoto(img.encodePng(wide));
    final out = img.decodeJpg(jpg)!;
    expect(out.width, 1600);
    expect(out.height, 400);
    expect(jpg[0], 0xFF);
    expect(jpg[1], 0xD8);

    final small = img.Image(width: 100, height: 80);
    img.fill(small, color: img.ColorRgb8(1, 2, 3));
    final kept = img.decodeJpg(compressMaterialsPhoto(img.encodePng(small)))!;
    expect(kept.width, 100);
    expect(kept.height, 80);
    expect(() => compressMaterialsPhoto(Uint8List.fromList([1, 2, 3, 4])), throwsFormatException);
  });

  test('videos over 720p or 12MB need a transcode', () {
    expect(videoNeedsTranscode(width: null, height: null, bytes: 10), isTrue);
    expect(videoNeedsTranscode(width: 1920, height: 1080, bytes: 1000), isTrue);
    expect(videoNeedsTranscode(width: 1280, height: 720, bytes: materialsVideoSkipBytes + 1), isTrue);
    expect(videoNeedsTranscode(width: 1280, height: 720, bytes: 1000), isFalse);
  });

  test('client keys are uuid-shaped and accepted by the server pattern', () {
    final key = newMaterialsClientKey();
    expect(materialsClientKeyPattern.hasMatch(key), isTrue);
    expect(materialsClientKeyPattern.hasMatch('short'), isFalse);
  });

  test('Materials opens in the app even when an older server says otherwise', () {
    final older = AppModule(key: 'materials', label: 'Materials', native: false, webUrl: 'https://example.test/materials/daily.php');
    expect(moduleOpensInApp(older), isTrue);
    expect(nativeModuleScreens.containsKey('materials'), isTrue);
    expect(moduleOpensInApp(AppModule(key: 'fees', label: 'Fees', native: false, webUrl: 'https://example.test/fees')), isFalse);
  });

  test('the day payload round-trips', () {
    final day = _day();
    final again = MaterialsDay.fromJson(day.toJson());
    expect(again.date, '2026-10-21');
    expect(again.materials.single.name, 'Pink Tower');
    expect(again.materials.single.check, isNull);
    expect(again.summary.pending, 1);
    expect(again.conditions.first.label, 'Good');
  });

  test('multipart upload does not send a JSON content type', () async {
    final file = File('${Directory.systemTemp.path}/lg-media-test.bin')..writeAsBytesSync([1, 2, 3, 4]);
    late http.Request seen;
    final api = ApiClient(
      client: MockClient((req) async {
        seen = req;
        return http.Response(jsonEncode({'ok': true}), 200);
      }),
    )..token = 'tok';
    await MaterialsApi(api).uploadFile(
      materialId: 4,
      date: '2026-10-21',
      clientKey: 'client-key-1234',
      filePath: file.path,
      filename: 'photo.jpg',
    );
    expect(seen.headers['content-type'], contains('multipart/form-data'));
    expect(seen.headers['content-type'], isNot(contains('application/json')));
    expect(seen.headers['authorization'], 'Bearer tok');
    expect(seen.headers['user-agent'], ApiClient.userAgent);
    expect(seen.url.path, endsWith('materials/media.php'));
    expect(seen.body, contains('client-key-1234'));
    expect(seen.body, contains('name="media"'));
  });

  test('a photo is copied onto disk before anything is uploaded', () async {
    final harness = _harness();
    final source = File('${harness.root.path}/camera.jpg')..writeAsBytesSync([9, 9, 9]);
    final saved = await harness.queue.enqueueMedia(
      materialId: 4,
      checkDate: '2026-10-21',
      location: 'Sensorial',
      source: source,
      filename: 'camera.jpg',
      mediaKind: 'photo',
      hasCondition: false,
    );
    source.deleteSync();
    expect(File(saved.originalPath!).readAsBytesSync(), [9, 9, 9]);
    expect(saved.status, OutboxStatus.waiting);
    expect(harness.transport.calls, isEmpty);
    await harness.queue.drain();
    expect(harness.transport.calls, isEmpty);
    expect((await harness.store.get(saved.id!))!.status, OutboxStatus.waiting);
  });

  test('a retry sends the same client key and a 400 is not retried', () async {
    final harness = _harness();
    final saved = await harness.queue.enqueueMark(
      materialId: 4,
      checkDate: '2026-10-21',
      location: 'Sensorial',
      conditionCode: 'good',
      notes: '',
    );
    harness.transport.error = ApiException('No internet connection.', status: 0);
    final first = await harness.queue.drain();
    expect(first.retry, isTrue);
    expect(harness.transport.calls.single.clientKey, saved.clientKey);
    expect((await harness.store.get(saved.id!))!.status, OutboxStatus.pending);

    harness.transport.error = null;
    await harness.queue.drain();
    expect(harness.transport.calls, hasLength(2));
    expect(harness.transport.calls.last.clientKey, saved.clientKey);
    expect((await harness.store.get(saved.id!))!.status, OutboxStatus.uploaded);

    final rejected = await harness.queue.enqueueMark(
      materialId: 5,
      checkDate: '2026-10-21',
      location: 'Sensorial',
      conditionCode: 'broken',
      notes: '',
    );
    harness.transport.error = ApiException('Too big.', status: 400, code: 'bad_request');
    final outcome = await harness.queue.drain();
    expect(outcome.retry, isFalse);
    expect((await harness.store.get(rejected.id!))!.status, OutboxStatus.failed);
    final calls = harness.transport.calls.length;
    await harness.queue.drain();
    expect(harness.transport.calls, hasLength(calls));
  });

  test('media waits for the mark, then uploads once', () async {
    final harness = _harness();
    await harness.queue.enqueueMark(
      materialId: 4,
      checkDate: '2026-10-21',
      location: 'Sensorial',
      conditionCode: 'good',
      notes: '',
    );
    final source = File('${harness.root.path}/shot.jpg')..writeAsBytesSync([1]);
    final media = await harness.queue.enqueueMedia(
      materialId: 4,
      checkDate: '2026-10-21',
      location: 'Sensorial',
      source: source,
      filename: 'shot.jpg',
      mediaKind: 'photo',
      hasCondition: true,
    );
    harness.transport.error = ApiException('offline', status: 503);
    await harness.queue.drain();
    expect(harness.transport.calls.single.kind, OutboxKind.mark);
    expect((await harness.store.get(media.id!))!.uploadPath, isNull);

    harness.transport.error = null;
    await harness.queue.drain();
    expect(harness.transport.calls.map((c) => c.kind), [OutboxKind.mark, OutboxKind.mark, OutboxKind.media]);
    final done = (await harness.store.get(media.id!))!;
    expect(done.status, OutboxStatus.uploaded);
    expect(File(media.originalPath!).existsSync(), isFalse);
    expect(done.uploadPath, isNull);
  });

  test('a newer mark is not overwritten by an in-flight save', () async {
    final harness = _harness();
    harness.transport.onMark = (item) async {
      if (item.notes == 'first') {
        await harness.queue.enqueueMark(
          materialId: 4,
          checkDate: '2026-10-21',
          location: 'Sensorial',
          conditionCode: 'broken',
          notes: 'second',
        );
      }
    };
    await harness.queue.enqueueMark(
      materialId: 4,
      checkDate: '2026-10-21',
      location: 'Sensorial',
      conditionCode: 'good',
      notes: 'first',
    );
    await harness.queue.drain();
    final row = (await harness.store.all()).single;
    expect(row.notes, 'second');
    expect(row.status, OutboxStatus.uploaded);
    expect(harness.transport.calls.map((call) => call.notes), ['first', 'second']);
    expect(harness.transport.calls.map((call) => call.clientKey).toSet(), {row.clientKey});
  });

  test('a missing condition is waiting, not a permanent failure', () async {
    final harness = _harness();
    final saved = await harness.queue.enqueueMark(
      materialId: 4,
      checkDate: '2026-10-21',
      location: 'Sensorial',
      conditionCode: 'good',
      notes: '',
    );
    harness.transport.error = ApiException('Mark a condition first.', status: 409, code: 'condition_required');
    await harness.queue.drain();
    final item = (await harness.store.get(saved.id!))!;
    expect(item.status, OutboxStatus.waiting);
    expect(item.errorCode, isNull);
  });

  test('an iOS background upload finishes when the session reports success', () async {
    final harness = _harness()..bridge.background = true;
    harness.transport.background = ApiMaterialsTransport(
      MaterialsApi(ApiClient()..token = 'tok'),
      baseUrl: 'https://mtt.thelittlegraduates.in',
      token: () => 'tok',
    );
    final source = File('${harness.root.path}/clip.mp4')..writeAsBytesSync(List<int>.filled(32, 7));
    await harness.queue.enqueueMark(
      materialId: 4,
      checkDate: '2026-10-21',
      location: 'Sensorial',
      conditionCode: 'good',
      notes: '',
    );
    final media = await harness.queue.enqueueMedia(
      materialId: 4,
      checkDate: '2026-10-21',
      location: 'Sensorial',
      source: source,
      filename: 'clip.mp4',
      mediaKind: 'video',
      hasCondition: true,
    );
    await harness.queue.drain();
    expect(harness.bridge.uploads, hasLength(1));
    expect(harness.bridge.uploads.single.clientKey, media.clientKey);
    expect(harness.bridge.uploads.single.url, 'https://mtt.thelittlegraduates.in/api/v1/materials/media.php');
    expect(harness.bridge.uploads.single.headers['Authorization'], 'Bearer tok');
    expect(harness.bridge.uploads.single.fields['client_key'], media.clientKey);
    expect((await harness.store.get(media.id!))!.status, OutboxStatus.uploading);

    harness.bridge.pendingResults.add(BackgroundUploadResult(
      clientKey: media.clientKey,
      status: 200,
      body: '{"ok":true,"duplicate":false}',
    ));
    final outcome = await harness.queue.drain();
    expect(outcome.uploadedAny, isTrue);
    final done = (await harness.store.get(media.id!))!;
    expect(done.status, OutboxStatus.uploaded);
    expect(File(media.originalPath!).existsSync(), isFalse);
  });

  test('sqlite keeps the outbox across a new connection', () async {
    final dir = Directory.systemTemp.createTempSync('lg-materials-db');
    final path = '${dir.path}/outbox.db';
    final first = await SqliteMaterialsStore.open(path: path);
    final queue = _queue(first, Directory('${dir.path}/files'));
    await queue.enqueueMark(
      materialId: 4,
      checkDate: '2026-10-21',
      location: 'Sensorial',
      conditionCode: 'minor',
      notes: 'chip',
    );
    await queue.rememberToken('secret');
    await first.close();
    final second = await SqliteMaterialsStore.open(path: path);
    final rows = await second.all();
    expect(rows.single.conditionCode, 'minor');
    expect(rows.single.notes, 'chip');
    expect(await second.getMeta('token'), 'secret');
    await second.close();
  });

  testWidgets('the sheet shows the material and a pending upload', (tester) async {
    final harness = _harness();
    final saved = await harness.queue.enqueueMark(
      materialId: 4,
      checkDate: '2026-10-21',
      location: 'Sensorial',
      conditionCode: 'good',
      notes: '',
    );
    expect(saved.status, OutboxStatus.pending);
    final controller = MaterialsController(api: MaterialsApi(ApiClient()), queue: harness.queue, initial: _day());
    await controller.reloadLocal();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider.value(value: ApiClient()),
          ChangeNotifierProvider.value(value: controller),
        ],
        child: const MaterialApp(home: MaterialsScreen()),
      ),
    );
    expect(find.text('Pink Tower'), findsOneWidget);
    expect(find.text('Sensorial · 1/1'), findsOneWidget);
    expect(find.textContaining('saved on this phone'), findsOneWidget);
    expect(find.text('Good'), findsWidgets);
  });
}

class _Harness {
  _Harness(this.store, this.queue, this.transport, this.bridge, this.root);
  final MemoryMaterialsStore store;
  final MaterialsQueue queue;
  final _ScriptTransport transport;
  final _ScriptBridge bridge;
  final Directory root;
}

class _ScriptTransport implements MaterialsTransport {
  final calls = <OutboxItem>[];
  ApiException? error;
  Future<void> Function(OutboxItem item)? onMark;
  ApiMaterialsTransport? background;

  Future<void> _hit(OutboxItem item) async {
    calls.add(item);
    final err = error;
    if (err != null) throw err;
  }

  @override
  Future<void> mark(OutboxItem item) async {
    if (onMark != null) await onMark!(item);
    await _hit(item);
  }

  @override
  Future<void> bulkGood(OutboxItem item) => _hit(item);

  @override
  Future<void> uploadMedia(OutboxItem item) => _hit(item);

  @override
  Future<void> uploadMediaBackground(OutboxItem item, MaterialsBridge bridge) async {
    final real = background;
    if (real != null) {
      await real.uploadMediaBackground(item, bridge);
      return;
    }
    await bridge.enqueueBackgroundUpload(BackgroundUploadRequest(
      clientKey: item.clientKey,
      url: 'https://mtt.thelittlegraduates.in/api/v1/materials/media.php',
      headers: const {},
      fields: {'client_key': item.clientKey},
      filePath: item.uploadPath ?? item.originalPath ?? '',
      filename: item.filename,
      mime: item.mime,
    ));
  }
}

class _ScriptBridge implements MaterialsBridge {
  bool background = false;
  final uploads = <BackgroundUploadRequest>[];
  final pendingResults = <BackgroundUploadResult>[];
  final flying = <String>{};

  @override
  bool get supportsBackgroundUpload => background;

  @override
  bool get canTranscode => false;

  @override
  Future<VideoInfo?> videoInfo(String path) async => const VideoInfo(640, 360);

  @override
  Future<void> transcodeVideo(String source, String dest) async {}

  @override
  Future<void> compressImageNative(String source, String dest) async {}

  @override
  Future<void> enqueueBackgroundUpload(BackgroundUploadRequest request) async {
    uploads.add(request);
    flying.add(request.clientKey);
  }

  @override
  Future<List<BackgroundUploadResult>> takeUploadResults() async {
    final copy = List<BackgroundUploadResult>.from(pendingResults);
    pendingResults.clear();
    for (final result in copy) {
      flying.remove(result.clientKey);
    }
    return copy;
  }

  @override
  Future<Set<String>> inFlightUploads() async => Set<String>.from(flying);
}

_Harness _harness() {
  final root = Directory.systemTemp.createTempSync('lg-materials');
  final store = MemoryMaterialsStore();
  final transport = _ScriptTransport();
  final bridge = _ScriptBridge();
  return _Harness(store, _queue(store, root, transport: transport, bridge: bridge), transport, bridge, root);
}

MaterialsQueue _queue(
  MaterialsStore store,
  Directory root, {
  MaterialsTransport? transport,
  _ScriptBridge? bridge,
}) {
  return MaterialsQueue(
    store: store,
    root: root,
    transport: transport ?? _ScriptTransport(),
    bridge: bridge ?? _ScriptBridge(),
    scheduler: const NoopScheduler(),
    compressPhotoBytes: (bytes) async => bytes,
    now: () => DateTime(2026, 10, 21, 9),
  );
}

MaterialsDay _day() {
  return MaterialsDay(
    date: '2026-10-21',
    dateLabel: 'Tuesday 21 Oct',
    uploadLimit: 40 * 1024 * 1024,
    isAdmin: false,
    canMonthly: false,
    summary: MaterialsSummary(checked: 0, pending: 1, total: 1, good: 0, attention: 0, damaged: 0, notes: 0),
    conditions: [
      MaterialCondition(code: 'good', label: 'Good', tone: 'ok'),
      MaterialCondition(code: 'broken', label: 'Broken', tone: 'bad'),
    ],
    locations: const ['Sensorial'],
    materials: [
      MaterialItem(id: 4, name: 'Pink Tower', location: 'Sensorial', sortOrder: 1, check: null, media: const []),
    ],
    links: MaterialsLinks(history: '', trends: '', monthly: '', duties: 'https://example.test/duties', assign: ''),
  );
}
