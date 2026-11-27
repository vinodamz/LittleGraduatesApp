import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_graduates/core/api_client.dart';
import 'package:little_graduates/core/session.dart';
import 'package:little_graduates/features/materials/materials_sqlite.dart';
import 'package:little_graduates/features/materials/materials_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'offline restart restores modules only for the matching token',
    () async {
      final profile = {
        'token': 'owner-token',
        'user': {'id': 42, 'name': 'Teacher', 'role': 'staff'},
        'modules': [
          {
            'key': 'materials',
            'label': 'Materials',
            'native': true,
            'web_url': 'https://mtt.thelittlegraduates.in/materials/daily.php',
          },
        ],
      };
      FlutterSecureStorage.setMockInitialValues({
        'lg_api_token': 'owner-token',
        'lg_profile': jsonEncode(profile),
      });
      final api = ApiClient(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      final session = Session(api);
      await session.restore();
      expect(session.user?.id, 42);
      expect(session.modules.single.key, 'materials');
      FlutterSecureStorage.setMockInitialValues({
        'lg_api_token': 'different-token',
        'lg_profile': jsonEncode(profile),
      });
      final different = Session(api);
      await different.restore();
      expect(different.user, isNull);
      expect(different.modules, isEmpty);
    },
  );

  test('revoked credentials immediately clear the restored identity', () async {
    FlutterSecureStorage.setMockInitialValues({'lg_api_token': 'revoked'});
    final api = ApiClient(
      client: MockClient(
        (_) async => http.Response(
          '{"ok":false,"code":"unauthenticated","error":"Sign in again"}',
          401,
        ),
      ),
    );
    final session = Session(api);
    await session.restore();
    expect(session.state, SessionState.signedOut);
    expect(api.token, isNull);
    expect(session.modules, isEmpty);
  });

  test(
    'staff queues and cached sheets survive separately across reopen',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final root = await Directory.systemTemp.createTemp('lg-account-test');
      await databaseFactory.setDatabasesPath(root.path);
      final first = await SqliteMaterialsStore.open(userId: 41);
      final second = await SqliteMaterialsStore.open(userId: 42);
      await first.setMeta('materials_day', 'first staff sheet');
      await first.setMeta('token', 'first-token');
      await first.insert(
        OutboxItem(
          clientKey: 'first-user-check',
          kind: OutboxKind.mark,
          checkDate: '2026-11-27',
          materialId: 7,
          conditionCode: 'good',
          status: OutboxStatus.pending,
          createdAt: DateTime(2026, 11, 27),
          updatedAt: DateTime(2026, 11, 27),
        ),
      );
      expect(await second.all(), isEmpty);
      expect(await second.getMeta('materials_day'), isNull);
      expect(await second.getMeta('token'), isNull);
      await second.setMeta('token', 'second-token');
      await first.close();
      final reopened = await SqliteMaterialsStore.open(userId: 41);
      expect(await reopened.getMeta('materials_day'), 'first staff sheet');
      expect(await reopened.getMeta('token'), 'first-token');
      expect((await reopened.all()).single.materialId, 7);
      await reopened.close();
      await second.close();
      await root.delete(recursive: true);
    },
  );
}
