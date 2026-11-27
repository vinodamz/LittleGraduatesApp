import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_graduates/core/api_client.dart';
import 'package:little_graduates/core/session.dart';
import 'package:little_graduates/features/materials/materials_api.dart';
import 'package:little_graduates/features/materials/materials_controller.dart';
import 'package:little_graduates/features/materials/materials_queue.dart';
import 'package:little_graduates/features/materials/materials_screen.dart';
import 'package:little_graduates/features/materials/materials_sqlite.dart';
import 'package:little_graduates/features/transport/location_tracker.dart';
import 'package:little_graduates/main.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'offline restore without a matching complete profile stays signed out',
    () async {
      for (final profile in <String?>[
        null,
        jsonEncode({..._identity(1), 'token': 'another-token'}),
        jsonEncode({
          'token': 'token-1',
          'user': _identity(1)['user'],
          'modules': 'invalid',
        }),
      ]) {
        FlutterSecureStorage.setMockInitialValues({
          'lg_api_token': 'token-1',
          'lg_profile': ?profile,
        });
        final session = Session(_offlineApi());
        await session.restore();
        expect(session.state, SessionState.signedOut);
        expect(session.user, isNull);
        expect(session.modules, isEmpty);
        session.dispose();
      }
    },
  );

  test('sign out hides identity before the logout response arrives', () async {
    final logout = Completer<http.Response>();
    final started = Completer<void>();
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('logout.php')) {
          expect(request.headers['authorization'], 'Bearer token-1');
          started.complete();
          return logout.future;
        }
        return _ok(_identity(1));
      }),
    );
    final session = Session(api);
    await session.signIn(1, '1234', 'test');
    final signingOut = session.signOut();
    await started.future;
    final stateWhilePending = session.state;
    final userWhilePending = session.user;
    logout.complete(_ok({}));
    await signingOut;
    expect(stateWhilePending, SessionState.signedOut);
    expect(userWhilePending, isNull);
    expect(
      await const FlutterSecureStorage().read(key: 'lg_api_token'),
      isNull,
    );
    expect(await const FlutterSecureStorage().read(key: 'lg_profile'), isNull);
  });

  test(
    'old refresh cannot restore an account after logout and another login',
    () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.url.path.endsWith('me.php')) {
            started.complete();
            return response.future;
          }
          if (request.url.path.endsWith('login.php')) {
            return _ok(_identity(jsonDecode(request.body)['user_id'] as int));
          }
          return _ok({});
        }),
      );
      final session = Session(api);
      await session.signIn(1, '1234', 'test');
      final refreshing = session.refresh();
      await started.future;
      await session.signOut();
      await session.signIn(2, '1234', 'test');
      response.complete(_ok(_identity(1)));
      await refreshing;
      expect(session.user?.id, 2);
      expect(api.token, 'token-2');
      final cached = jsonDecode(
        (await const FlutterSecureStorage().read(key: 'lg_profile'))!,
      );
      expect(cached['user']['id'], 2);
    },
  );

  for (final kind in ['get', 'post', 'multipart-file', 'multipart-bytes']) {
    test(
      'delayed 401 from $kind preserves the newer account and credentials',
      () async {
        final response = Completer<http.Response>();
        final started = Completer<http.Request>();
        final root = await Directory.systemTemp.createTemp('lg-stale-auth-');
        addTearDown(() => root.delete(recursive: true));
        final file = File('${root.path}/photo.jpg')
          ..writeAsBytesSync([1, 2, 3]);
        final api = ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('login.php')) {
              return _ok(_identity(jsonDecode(request.body)['user_id'] as int));
            }
            if (request.url.path.endsWith('logout.php')) return _ok({});
            started.complete(request);
            return response.future;
          }),
        );
        final session = Session(api);
        addTearDown(session.dispose);
        await session.signIn(1, '1234', 'test');
        final pending = switch (kind) {
          'get' => session.refresh(),
          'post' => api.post('materials/mark.php', {'notes': 'Old account'}),
          'multipart-file' => api.postMultipart(
            'materials/media.php',
            fields: {'client_key': 'old-photo'},
            filePath: file.path,
            filename: 'photo.jpg',
          ),
          _ => api.postMultipartBytes(
            'materials/media.php',
            fields: {'client_key': 'old-photo'},
            bytes: [1, 2, 3],
            filename: 'photo.jpg',
          ),
        };
        final rejected = expectLater(
          pending,
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
        );
        expect(
          (await started.future).headers['authorization'],
          'Bearer token-1',
        );
        await session.signOut();
        await session.signIn(2, '1234', 'test');
        response.complete(
          http.Response(
            '{"ok":false,"code":"unauthenticated","error":"Expired"}',
            401,
          ),
        );
        await rejected;
        expect(session.state, SessionState.signedIn);
        expect(session.user?.id, 2);
        expect(api.token, 'token-2');
        expect(
          await const FlutterSecureStorage().read(key: 'lg_api_token'),
          'token-2',
        );
        final cached = jsonDecode(
          (await const FlutterSecureStorage().read(key: 'lg_profile'))!,
        );
        expect(cached['token'], 'token-2');
        expect(cached['user']['id'], 2);
      },
    );
  }

  test(
    'delayed 401 cannot invalidate a later session reusing the same token',
    () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      var invalidations = 0;
      final api =
          ApiClient(
              client: MockClient((_) async {
                started.complete();
                return response.future;
              }),
            )
            ..token = 'same-token'
            ..onUnauthenticated = () => invalidations++;
      final rejected = expectLater(
        api.get('me.php'),
        throwsA(isA<ApiException>()),
      );
      await started.future;
      api.token = null;
      api.token = 'same-token';
      response.complete(
        http.Response('{"ok":false,"code":"unauthenticated"}', 401),
      );
      await rejected;
      expect(invalidations, 0);
      expect(api.token, 'same-token');
    },
  );

  test(
    'delayed anonymous 401 cannot invalidate a newly signed-in session',
    () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      var invalidations = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          expect(request.headers['authorization'], isNull);
          started.complete();
          return response.future;
        }),
      )..onUnauthenticated = () => invalidations++;
      final rejected = expectLater(
        api.get('login_users.php'),
        throwsA(isA<ApiException>()),
      );
      await started.future;
      api.token = 'new-token';
      response.complete(
        http.Response('{"ok":false,"code":"unauthenticated"}', 401),
      );
      await rejected;
      expect(invalidations, 0);
      expect(api.token, 'new-token');
    },
  );

  test(
    'login completing after sign out cannot sign the user back in',
    () async {
      final login = Completer<http.Response>();
      final started = Completer<void>();
      final session = Session(
        ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('login.php')) {
              started.complete();
              return login.future;
            }
            return _ok({});
          }),
        ),
      );
      final signingIn = session.signIn(1, '1234', 'test');
      await started.future;
      await session.signOut();
      login.complete(_ok(_identity(1)));
      await signingIn;
      expect(session.state, SessionState.signedOut);
      expect(session.api.token, isNull);
      expect(
        await const FlutterSecureStorage().read(key: 'lg_api_token'),
        isNull,
      );
    },
  );

  test(
    'yesterday queued checks and photos do not mark today checked',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      await harness.queue.enqueueMark(
        materialId: 4,
        checkDate: '2026-11-26',
        location: 'Sensorial',
        conditionCode: 'broken',
        notes: 'Yesterday only',
      );
      final source = File('${harness.root.path}/photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      await harness.queue.enqueueMedia(
        materialId: 4,
        checkDate: '2026-11-26',
        location: 'Sensorial',
        source: source,
        filename: 'photo.jpg',
        mediaKind: 'photo',
        hasCondition: true,
      );
      await harness.controller.reloadLocal();
      final view = harness.controller.viewFor(
        harness.controller.day!.materials.first,
      )!;
      expect(view.checked, isFalse);
      expect(view.notes, isEmpty);
      expect(view.localMedia, isEmpty);
      expect(harness.controller.pendingCount, 2);
      expect((await harness.store.all()).length, 2);
    },
  );

  test(
    'pause during queue read prevents a new upload without deleting the row',
    () async {
      final store = _DelayedStore();
      final harness = _Harness(store: store);
      addTearDown(harness.close);
      harness.queue.onChanged = null;
      await harness.queue.enqueueMark(
        materialId: 4,
        checkDate: '2026-11-27',
        location: 'Sensorial',
        conditionCode: 'good',
        notes: 'Keep this',
      );
      // Recovery reads once; the second read selects the next upload.
      harness.queue.onChanged = null;
      store.readsUntilPause = 2;
      final draining = harness.queue.drain();
      await store.blocked.future;
      harness.queue.paused = true;
      store.release.complete();
      await draining;
      expect(harness.transport.sent, isEmpty);
      expect((await store.all()).single.status, OutboxStatus.pending);
    },
  );

  test(
    'offline save survives SQLite reopen then retries with its original client key',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final root = await Directory.systemTemp.createTemp('lg-native-reopen-');
      addTearDown(() => root.delete(recursive: true));
      final path = '${root.path}/queue.db';
      var store = await SqliteMaterialsStore.open(path: path);
      final transport = _Transport()..failure = ApiException('Offline');
      var controller = _controller(store, root, transport);
      await store.setMeta('materials_day', jsonEncode(_day().toJson()));
      await controller.setCondition(4, 'broken', 'Small chip');
      final saved = (await store.all()).single;
      expect(saved.status, OutboxStatus.pending);
      controller.dispose();
      await store.close();
      store = await SqliteMaterialsStore.open(path: path);
      controller = _controller(
        store,
        root,
        transport,
        day: MaterialsDay.fromJson(
          jsonDecode((await store.getMeta('materials_day'))!),
        ),
      );
      await controller.reloadLocal();
      expect(
        controller.viewFor(controller.day!.materials.first)!.notes,
        'Small chip',
      );
      transport.failure = null;
      await controller.retryItem(saved.id!);
      final uploaded = (await store.all()).single;
      expect(uploaded.status, OutboxStatus.uploaded);
      expect(transport.sent.map((item) => item.clientKey).toSet(), {
        saved.clientKey,
      });
      expect(uploaded.notes, 'Small chip');
      controller.dispose();
      await store.close();
    },
  );

  test(
    'account switching reloads only its own SQLite queue and clears logout credentials',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final root = await Directory.systemTemp.createTemp('lg-native-accounts-');
      await databaseFactory.setDatabasesPath(root.path);
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, (_) async => root.path);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathChannel, null);
      });
      final first = await SqliteMaterialsStore.open(userId: 101);
      final second = await SqliteMaterialsStore.open(userId: 202);
      final registry = await SqliteMaterialsStore.open();
      await first.setMeta('materials_day', jsonEncode(_day().toJson()));
      final dayTwo = _day().toJson();
      dayTwo['materials'] = [
        {'id': 9, 'name': 'Second account shelf', 'location': 'Practical'},
      ];
      await second.setMeta('materials_day', jsonEncode(dayTwo));
      final seed = _controller(
        first,
        root,
        _Transport()..failure = ApiException('Offline'),
      );
      await seed.setCondition(4, 'broken', 'First account private note');
      seed.dispose();
      final controller = await MaterialsController.open(_offlineApi());
      final sent = <http.Request>[];
      await http.runWithClient(
        () async {
          await controller.rememberToken('token-101', userId: 101);
          expect(controller.error, isNot(contains('Could not open')));
          expect(controller.outbox.single.notes, 'First account private note');
          await controller.rememberToken('token-202', userId: 202);
          expect(controller.day!.materials.single.name, 'Second account shelf');
          expect(controller.outbox, isEmpty);
          expect(await first.getMeta('token'), isEmpty);
          expect(await second.getMeta('token'), 'token-202');
          expect(await registry.getMeta('active_user'), '202');
          final signingOut = controller.rememberToken(null);
          expect(controller.day, isNull);
          expect(controller.outbox, isEmpty);
          await signingOut;
          expect(await registry.getMeta('active_user'), isEmpty);
          expect(await second.getMeta('token'), isEmpty);
          expect(
            (await first.all()).single.notes,
            'First account private note',
          );
          await controller.rememberToken('new-token-101', userId: 101);
          expect(controller.outbox.single.notes, 'First account private note');
          expect(controller.day!.materials.single.name, 'Pink Tower');
          final marks = sent.where(
            (request) => request.url.path.endsWith('mark.php'),
          );
          expect(marks, hasLength(2));
          expect(marks.map((request) => request.headers['authorization']), [
            'Bearer token-101',
            'Bearer new-token-101',
          ]);
          expect(
            marks
                .map((request) => jsonDecode(request.body)['client_key'])
                .toSet(),
            hasLength(1),
          );
          await controller.rememberToken(null);
        },
        () => MockClient((request) async {
          sent.add(request);
          throw http.ClientException('offline');
        }),
      );
      controller.dispose();
      await first.close();
      await second.close();
      await registry.close();
      await root.delete(recursive: true);
    },
  );

  test(
    'concurrent local note edits keep one queue record and the final text',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      harness.transport.failure = ApiException('Offline');
      await harness.controller.setCondition(4, 'good', '');
      final original = (await harness.store.all()).single;
      await Future.wait([
        harness.controller.setNotes(4, 'a', sync: false),
        harness.controller.setNotes(4, 'ab', sync: false),
        harness.controller.setNotes(4, '', sync: false),
      ]);
      final rows = await harness.store.all();
      expect(rows, hasLength(1));
      expect(rows.single.clientKey, original.clientKey);
      expect(rows.single.notes, isEmpty);
      expect(rows.single.generation, original.generation + 3);
    },
  );

  testWidgets(
    'materials selection, failed save and Retry save use the real controller',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harness = _Harness();
      addTearDown(harness.close);
      harness.transport.failure = ApiException('Check rejected', status: 400);
      await tester.pumpWidget(_materialsApp(harness.controller));
      await tester.tap(find.text('Condition').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Broken').last);
      await tester.pumpAndSettle();
      expect(find.text('Retry save'), findsOneWidget);
      final key = (await harness.store.all()).single.clientKey;
      harness.transport.failure = null;
      await tester.tap(find.text('Retry save'));
      await tester.pumpAndSettle();
      expect(find.text('Retry save'), findsNothing);
      expect((await harness.store.all()).single.status, OutboxStatus.uploaded);
      expect(harness.transport.sent.map((item) => item.clientKey).toSet(), {
        key,
      });
    },
  );

  testWidgets(
    'comment survives leaving the sheet before the debounce expires',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harness = _Harness();
      addTearDown(harness.close);
      harness.transport.failure = ApiException('Offline');
      await harness.controller.setCondition(4, 'good', '');
      await tester.pumpWidget(_materialsApp(harness.controller));
      await tester.enterText(
        find.widgetWithText(TextField, 'Comment (optional)').first,
        'Do not lose this',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      expect((await harness.store.all()).single.notes, 'Do not lose this');
    },
  );

  testWidgets(
    'login wrong PIN, valid login and logout discard pushed account routes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.url.path.endsWith('login_users.php')) {
            return _ok({
              'users': [_identity(1)['user'], _identity(2)['user']],
            });
          }
          if (request.url.path.endsWith('me.php')) {
            return _ok(
              _identity(
                request.headers['authorization'] == 'Bearer token-2' ? 2 : 1,
              ),
            );
          }
          if (request.url.path.endsWith('login.php')) {
            final body = jsonDecode(request.body);
            if (body['pin'] != '1234') {
              return http.Response(
                jsonEncode({
                  'ok': false,
                  'code': 'wrong_pin',
                  'error': 'Wrong PIN.',
                }),
                401,
              );
            }
            return _ok(_identity(body['user_id'] as int));
          }
          return _ok({'trips': [], 'day': {}});
        }),
      );
      final session = Session(api);
      await session.restore();
      final harness = _Harness();
      addTearDown(harness.close);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider.value(value: api),
            ChangeNotifierProvider.value(value: session),
            ChangeNotifierProvider.value(value: harness.controller),
            ChangeNotifierProvider(create: (_) => LocationTracker(api)),
          ],
          child: const LittleGraduatesApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Teacher One'));
      await tester.pumpAndSettle();
      for (final digit in ['0', '0', '0', '0']) {
        await tester.tap(find.text(digit));
      }
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Wrong PIN.'), findsOneWidget);
      expect(session.state, SessionState.signedOut);
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit));
      }
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(session.user?.id, 1);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Private account page')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private account page'), findsOneWidget);
      await session.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Private account page'), findsNothing);
      expect(find.text('Who’s here?'), findsOneWidget);
      await session.signIn(2, '1234', 'test');
      await tester.pumpAndSettle();
      expect(session.user?.id, 2);
      expect(find.text('Private account page'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

http.Response _ok(Map<String, dynamic> data) =>
    http.Response(jsonEncode({'ok': true, ...data}), 200);

Map<String, dynamic> _identity(int id) => {
  'token': 'token-$id',
  'user': {
    'id': id,
    'name': id == 1 ? 'Teacher One' : 'Teacher Two',
    'role': 'staff',
  },
  'modules': <Object>[],
};

ApiClient _offlineApi() => ApiClient(
  client: MockClient((_) async => throw http.ClientException('offline')),
);

MaterialsDay _day() => MaterialsDay.fromJson({
  'date': '2026-11-27',
  'date_label': 'Friday 27 Nov',
  'summary': {'total': 1, 'pending': 1},
  'conditions': [
    {'code': 'good', 'label': 'Good', 'tone': 'ok'},
    {'code': 'broken', 'label': 'Broken', 'tone': 'bad'},
  ],
  'locations': ['Sensorial'],
  'materials': [
    {'id': 4, 'name': 'Pink Tower', 'location': 'Sensorial'},
  ],
});

MaterialsController _controller(
  MaterialsStore store,
  Directory root,
  _Transport transport, {
  MaterialsDay? day,
}) => MaterialsController(
  api: MaterialsApi(_offlineApi()),
  queue: MaterialsQueue(
    store: store,
    root: root,
    transport: transport,
    bridge: _Bridge(),
    scheduler: const NoopScheduler(),
    compressPhotoBytes: (bytes) async => bytes,
  ),
  initial: day ?? _day(),
);

Widget _materialsApp(MaterialsController controller) => MultiProvider(
  providers: [
    Provider.value(value: controller.api.api),
    ChangeNotifierProvider.value(value: controller),
  ],
  child: const MaterialApp(home: MaterialsScreen()),
);

class _Harness {
  _Harness({MaterialsStore? store}) : store = store ?? MemoryMaterialsStore() {
    controller = _controller(this.store, root, transport);
  }
  final MaterialsStore store;
  final Directory root = Directory.systemTemp.createTempSync(
    'lg-native-memory-',
  );
  final _Transport transport = _Transport();
  late final MaterialsController controller;
  MaterialsQueue get queue => controller.queue;
  void close() {
    controller.dispose();
    root.deleteSync(recursive: true);
  }
}

class _Transport implements MaterialsTransport {
  final sent = <OutboxItem>[];
  ApiException? failure;
  Future<void> _send(OutboxItem item) async {
    sent.add(item);
    if (failure != null) throw failure!;
  }

  @override
  Future<void> mark(OutboxItem item) => _send(item);
  @override
  Future<void> bulkGood(OutboxItem item) => _send(item);
  @override
  Future<void> uploadMedia(OutboxItem item) => _send(item);
  @override
  Future<void> uploadMediaBackground(OutboxItem item, MaterialsBridge bridge) =>
      _send(item);
}

class _DelayedStore extends MemoryMaterialsStore {
  int readsUntilPause = 0;
  final blocked = Completer<void>();
  final release = Completer<void>();
  @override
  Future<List<OutboxItem>> all() async {
    final result = await super.all();
    if (readsUntilPause > 0 && --readsUntilPause == 0) {
      blocked.complete();
      await release.future;
    }
    return result;
  }
}

class _Bridge implements MaterialsBridge {
  @override
  bool get supportsBackgroundUpload => false;
  @override
  bool get canTranscode => false;
  @override
  Future<List<BackgroundUploadResult>> takeUploadResults() async => [];
  @override
  Future<Set<String>> inFlightUploads() async => {};
  @override
  Future<VideoInfo?> videoInfo(String path) async => null;
  @override
  Future<void> transcodeVideo(String source, String dest) async {}
  @override
  Future<void> compressImageNative(String source, String dest) async {}
  @override
  Future<void> enqueueBackgroundUpload(BackgroundUploadRequest request) async {}
}
