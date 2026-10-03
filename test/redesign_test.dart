import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_graduates/core/api_client.dart';
import 'package:little_graduates/core/format.dart';
import 'package:little_graduates/core/theme.dart';
import 'package:little_graduates/features/auth/login_screen.dart';
import 'package:little_graduates/features/staff/staff_api.dart';
import 'package:little_graduates/features/transport/today_screen.dart';
import 'package:little_graduates/features/transport/transport_api.dart';
import 'package:provider/provider.dart';

TripSummary summary({
  required int routeId,
  required String direction,
  required String label,
  String status = 'scheduled',
  String routeName = 'HSR',
}) => TripSummary.fromJson({
      'route_id': routeId,
      'route_name': routeName,
      'direction': direction,
      'direction_label': label,
      'time': '07:30',
      'cab_name': 'Cab 1',
      'children': 8,
      'trip_id': null,
      'status': status,
      'status_label': status == 'running' ? 'On the road' : 'Not started',
      'finished': 1,
      'total': 8,
    });

void main() {
  test('trips are grouped with pickups before drops', () {
    final groups = groupTrips([
      summary(routeId: 2, direction: 'drop', label: 'Afternoon drop', routeName: 'Kaloor'),
      summary(routeId: 1, direction: 'pickup', label: 'Morning pickup'),
      summary(routeId: 2, direction: 'pickup', label: 'Morning pickup', routeName: 'Kaloor'),
    ]);
    expect(groups.map((g) => g.direction), ['pickup', 'drop']);
    expect(groups.first.trips.map((t) => t.routeName), ['HSR', 'Kaloor']);
    expect(groups.last.label, 'Afternoon drop');
  });

  test('trip action follows the run status', () {
    expect(tripCta(summary(routeId: 1, direction: 'pickup', label: 'Morning pickup')), 'Open trip');
    expect(
      tripCta(summary(routeId: 1, direction: 'pickup', label: 'Morning pickup', status: 'running')),
      'Continue trip',
    );
    expect(
      tripCta(summary(routeId: 1, direction: 'pickup', label: 'Morning pickup', status: 'completed')),
      'Review trip',
    );
  });

  test('dates and greetings stay readable', () {
    expect(greetingFor(DateTime(2026, 10, 3, 8)), 'Good morning');
    expect(greetingFor(DateTime(2026, 10, 3, 15)), 'Good afternoon');
    expect(greetingFor(DateTime(2026, 10, 3, 20)), 'Good evening');
    expect(formatShortDate('2026-10-03'), '3 Oct');
    expect(formatDateRange('2026-10-03', '2026-10-03'), '3 Oct');
    expect(formatDateRange('2026-10-03', '2026-10-05'), '3 Oct – 5 Oct');
    expect(firstName('Priya Nair'), 'Priya');
  });

  test('staff day parses attendance, leave and roster', () {
    final day = StaffDay.fromJson({
      'date': '2026-10-03',
      'date_label': 'Saturday, 3 Oct',
      'is_admin': true,
      'attendance': {
        'status': 'present',
        'status_label': 'Present',
        'check_in': '09:02',
        'check_out': null,
        'shift_label': '9:00 AM – 5:00 PM',
        'late_after': '9:15 AM',
      },
      'leave': {
        'balance': 4.5,
        'balance_label': '4.5 days',
        'pending': 1,
        'pending_reviews': 2,
        'types': [
          {'key': 'casual', 'label': 'Casual'},
        ],
        'requests': [
          {
            'id': 9,
            'type': 'casual',
            'type_label': 'Casual',
            'start_date': '2026-10-10',
            'end_date': '2026-10-10',
            'half_day': '',
            'days': 1,
            'days_label': '1 day',
            'reason': 'Family',
            'status': 'pending',
            'status_label': 'Pending',
          },
        ],
      },
      'duties_pending': 3,
      'roster': [
        {
          'id': 4,
          'name': 'Anita',
          'role_label': 'Teacher',
          'status': null,
          'status_label': 'Not in yet',
          'check_in': null,
          'check_out': null,
        },
      ],
      'links': {
        'staff': 'https://example.test/staff/index.php',
        'attendance': 'https://example.test/staff/attendance.php',
        'leave': 'https://example.test/staff/leave.php',
        'duties': 'https://example.test/duties/index.php',
      },
    });
    expect(day.attendance.checkedIn, isTrue);
    expect(day.attendance.checkedOut, isFalse);
    expect(day.leave!.balanceLabel, '4.5 days');
    expect(day.leave!.requests.single.pending, isTrue);
    expect(day.roster.single.waiting, isTrue);
    expect(day.dutiesPending, 3);
  });

  testWidgets('a trip card shows the route and the next action', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TripRunCard(
          trip: summary(routeId: 1, direction: 'pickup', label: 'Morning pickup', routeName: 'HSR'),
          onTap: () => taps++,
        ),
      ),
    ));
    expect(find.text('HSR'), findsOneWidget);
    expect(find.text('Open trip'), findsOneWidget);
    expect(find.text('Not started'), findsOneWidget);
    await tester.tap(find.text('HSR'));
    expect(taps, 1);
  });

  testWidgets('name list and PIN pad fit a small phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = ApiClient(
      client: MockClient((_) async => http.Response(jsonEncode({
        'ok': true,
        'school': 'Little Graduates',
        'users': [
          {'id': 1, 'name': 'Priya Nair', 'role': 'teacher'},
          {'id': 2, 'name': 'Ravi Kumar', 'role': 'admin'},
        ],
      }), 200)),
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Provider<ApiClient>.value(value: api, child: const LoginScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Who’s here?'), findsOneWidget);
    expect(find.text('Priya Nair'), findsOneWidget);
    await tester.tap(find.text('Priya Nair'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your PIN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
