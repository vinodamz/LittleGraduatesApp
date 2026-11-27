import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_graduates/core/api_client.dart';
import 'package:little_graduates/features/transport/location_tracker.dart';

class TestLocations extends GeolocatorPlatform {
  final positions = StreamController<Position>();

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async => LocationPermission.always;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) => positions.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an offline backlog uploads every point in server-sized batches', () async {
    final original = GeolocatorPlatform.instance;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    FlutterLocalNotificationsPlatform.instance = MacOSFlutterLocalNotificationsPlugin();
    final locations = TestLocations();
    GeolocatorPlatform.instance = locations;
    final batches = <List<dynamic>>[];
    final api = ApiClient(client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      batches.add(body['points'] as List);
      return http.Response('{"ok":true,"status":"running","signature":"test","reached":[],"due":[]}', 200);
    }));
    final tracker = LocationTracker(api);
    try {
      expect(await tracker.start(7, 'Test route').timeout(const Duration(seconds: 3)), isNull);
      for (var index = 0; index < 601; index++) {
        locations.positions.add(Position(
          latitude: 12, longitude: 77, timestamp: DateTime.fromMillisecondsSinceEpoch(index * 5000),
          accuracy: 1, altitude: 0, altitudeAccuracy: 1, heading: 0,
          headingAccuracy: 1, speed: 0, speedAccuracy: 1,
        ));
      }
      await Future<void>.delayed(Duration.zero);
      await tracker.upload().timeout(const Duration(seconds: 3));
      await tracker.upload().timeout(const Duration(seconds: 3));
      expect(batches.map((batch) => batch.length).toList(), [500, 101]);
      expect(batches.expand((batch) => batch).map((point) => point['t']).toSet().length, 601);
      await tracker.stop(flush: false);
      expect(tracker.active, isFalse);
    } finally {
      tracker.dispose();
      unawaited(locations.positions.close());
      GeolocatorPlatform.instance = original;
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
