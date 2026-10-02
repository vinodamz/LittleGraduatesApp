import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_graduates/core/api_client.dart';
import 'package:little_graduates/features/transport/transport_api.dart';

Map<String, dynamic> tripJson({String status = 'running'}) => {
      'id': 7,
      'route_id': 1,
      'route_name': 'HSR',
      'direction': 'drop',
      'direction_label': 'Afternoon drop',
      'date': '2026-10-02',
      'status': status,
      'status_label': 'On the road',
      'cab': {'name': 'Cab 1', 'vehicle_no': 'KA01', 'driver_name': 'Ravi'},
      'started_at': '2026-10-02T13:30:00+05:30',
      'last_location_at': null,
      'reached_radius_m': 80,
      'signature': 'abc',
      'stops': [
        {
          'id': 11,
          'order': 1,
          'student_id': 3,
          'name': 'Riya Shah',
          'grade': 'Casa',
          'note': 'Gate 2',
          'location': {'lat': 12.9, 'lng': 77.6},
          'status': 'pending',
          'reached_at': null,
          'done_at': null,
          'eta_minutes': 4,
          'eta_alert_sent': false,
          'reached_alert_sent': false,
          'eta_alert_due': true,
          'parents': [
            {'id': 5, 'label': 'mother', 'name': 'Asha'},
          ],
        },
        {
          'id': 12,
          'order': 2,
          'student_id': 4,
          'name': 'Arjun Rao',
          'grade': 'Casa',
          'note': '',
          'location': null,
          'status': 'done',
          'reached_at': '2026-10-02T13:40:00+05:30',
          'done_at': '2026-10-02T13:41:00+05:30',
          'eta_minutes': null,
          'eta_alert_sent': true,
          'reached_alert_sent': false,
          'eta_alert_due': false,
          'parents': <Map<String, dynamic>>[],
        },
      ],
    };

void main() {
  test('Trip parses the server payload', () {
    final t = Trip.fromJson(tripJson());
    expect(t.running, isTrue);
    expect(t.doneVerb, 'Dropped');
    expect(t.pendingCount, 1);
    expect(t.stops.first.firstName, 'Riya');
    expect(t.stops.first.hasLocation, isTrue);
    expect(t.stops.first.parents.single.label, 'mother');
    expect(t.stops.last.reached, isTrue);
  });

  test('ApiClient sends the bearer token and JSON body', () async {
    late http.Request seen;
    final api = ApiClient(
      client: MockClient((req) async {
        seen = req;
        return http.Response(jsonEncode({'ok': true, 'trip': tripJson()}), 200);
      }),
    )..token = 'a' * 64;
    final trip = await TransportApi(api).action(7, 'done', stopId: 11);
    expect(trip.id, 7);
    expect(seen.headers['Authorization'], 'Bearer ${'a' * 64}');
    expect(seen.url.path, '/api/v1/transport/action.php');
    expect(jsonDecode(seen.body), {'trip_id': 7, 'op': 'done', 'stop_id': 11});
  });

  test('401 signs the device out, wrong PIN does not', () async {
    var signedOut = 0;
    var reply = {'ok': false, 'error': 'Sign in again.', 'code': 'unauthenticated'};
    final api = ApiClient(client: MockClient((_) async => http.Response(jsonEncode(reply), 401)))
      ..onUnauthenticated = () => signedOut++;
    await expectLater(api.get('me.php'), throwsA(isA<ApiException>()));
    expect(signedOut, 1);

    reply = {'ok': false, 'error': 'Wrong PIN.', 'code': 'wrong_pin'};
    await expectLater(
      api.post('login.php', {'user_id': 1, 'pin': '0000'}),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Wrong PIN.')),
    );
    expect(signedOut, 1);
  });

  test('Non-JSON replies (e.g. a host firewall page) give a clear error', () async {
    final api = ApiClient(client: MockClient((_) async => http.Response('<html>403</html>', 403)));
    await expectLater(
      api.get('me.php'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
    );
  });
}
