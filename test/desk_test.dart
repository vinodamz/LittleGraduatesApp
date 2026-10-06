import 'package:flutter_test/flutter_test.dart';
import 'package:little_graduates/features/transport/desk.dart';

void main() {
  test('distance and the approach line', () {
    final meters = metersBetween(12.9716, 77.5946, 12.9816, 77.5946);
    expect(meters, closeTo(1112, 20));
    expect(approachPhrase(12), 'You are at the next stop');
    expect(approachPhrase(600), 'Next stop is about 600 m ahead');
    expect(approachPhrase(2400), 'Next stop is about 2.4 km ahead');
  });

  test('roster export quotes commas', () {
    final csv = rosterCsv([
      RosterChild.fromJson({
        'id': 1,
        'name': 'Shah, Riya',
        'grade': 'Casa',
        'route_name': 'HSR',
        'status': 'waiting',
        'status_label': 'Waiting',
        'guardian': 'Asha',
        'pin': null,
        'track_url': 'https://example/t',
      }),
    ]);
    expect(csv.split('\n').first, 'Name,Grade,Route,Status,Guardian');
    expect(csv, contains('"Shah, Riya"'));
  });

  test('overview parses live cabs and kpis', () {
    final desk = TransportOverview.fromJson({
      'school': 'Little Graduates',
      'contact': '',
      'kpis': {'vehicles_active': 1, 'vehicles_total': 2, 'aboard': 3, 'on_time_pct': 100, 'alerts': 0},
      'alerts': <Map<String, dynamic>>[],
      'routes': <Map<String, dynamic>>[],
      'live': [
        {
          'trip_id': 4,
          'route_name': 'HSR',
          'direction_label': 'Morning pickup',
          'cab_name': 'Cab 1',
          'vehicle_no': 'KA01',
          'driver_name': 'Ravi',
          'lat': 12.9,
          'lng': 77.6,
          'speed_kmh': 28,
          'stops': [
            {'name': 'Riya', 'lat': 12.91, 'lng': 77.61, 'status': 'pending', 'order': 1},
            {'name': 'Arjun', 'lat': null, 'lng': null, 'status': 'pending', 'order': 2},
          ],
        },
      ],
    });
    expect(desk.kpis.aboard, 3);
    expect(desk.live.single.hasFix, isTrue);
    expect(desk.live.single.stops.first.name, 'Riya');
    expect(desk.live.single.stops.first.hasPin, isTrue);
    expect(desk.live.single.stops.last.hasPin, isFalse);
  });
}