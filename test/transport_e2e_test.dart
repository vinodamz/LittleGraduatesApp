// Native widget flows with in-memory HTTP responses; no school server writes.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:little_graduates/core/api_client.dart';
import 'package:little_graduates/core/session.dart';
import 'package:little_graduates/core/theme.dart';
import 'package:little_graduates/features/transport/hub_screen.dart';
import 'package:little_graduates/features/transport/location_tracker.dart';
import 'package:little_graduates/features/transport/live_screen.dart';
import 'package:little_graduates/features/transport/messages_screen.dart';
import 'package:little_graduates/features/transport/new_trip_screen.dart';
import 'package:little_graduates/features/transport/overview_screen.dart';
import 'package:little_graduates/features/transport/reports_screen.dart';
import 'package:little_graduates/features/transport/roster_screen.dart';
import 'package:little_graduates/features/transport/settings_screen.dart';
import 'package:little_graduates/features/transport/today_screen.dart';
import 'package:little_graduates/features/transport/transport_api.dart';
import 'package:little_graduates/features/transport/trip_screen.dart';

http.Response reply(Map<String, dynamic> data) =>
    http.Response(jsonEncode({'ok': true, ...data}), 200);
http.Response failure() =>
    http.Response('{"ok":false,"error":"Test connection interrupted"}', 503);

Map<String, dynamic> tripJson({
  String status = 'scheduled',
  String stop = 'pending',
}) => {
  'id': 7,
  'route_id': 2,
  'route_name': 'Test route',
  'direction': 'pickup',
  'direction_label': 'Pickup',
  'status': status,
  'status_label': status,
  'cab': {'name': 'Test cab', 'vehicle_no': 'TEST'},
  'signature': '$status:$stop',
  'stops': [
    {
      'id': 11,
      'order': 1,
      'name': 'Asha Test',
      'grade': 'KG',
      'note': '',
      'location': {'lat': 12.0, 'lng': 77.0},
      'status': stop,
      'eta_alert_sent': false,
      'reached_alert_sent': false,
      'eta_alert_due': false,
      'parents': [],
    },
  ],
};

final settings = {
  'school': 'Test school',
  'contact': '1234',
  'notify_pickup': true,
  'speed_alerts': false,
  'delete_coordinates': true,
};

http.Response fixture(http.Request request) {
  switch (request.url.path.split('/').last) {
    case 'today.php':
      return reply({'trips': []});
    case 'calendar.php':
      return reply({'days': []});
    case 'routes.php':
      return reply({
        'routes': [
          {
            'id': 2,
            'name': 'Test route',
            'cab_name': 'Test cab',
            'children': 1,
            'directions': ['pickup', 'drop'],
          },
        ],
      });
    case 'children.php':
      return reply({
        'children': [
          {'id': 11, 'name': 'Asha Test', 'grade': 'KG'},
        ],
      });
    case 'trip.php':
      return reply({'trip': tripJson()});
    case 'overview.php':
      return reply({
        'school': 'Test school',
        'kpis': {
          'vehicles_active': 0,
          'vehicles_total': 0,
          'aboard': 0,
          'on_time_pct': 0,
          'alerts': 0,
        },
        'alerts': [],
        'routes': [],
        'live': [],
      });
    case 'roster.php':
      return reply({'children': [], 'counts': {}});
    case 'messages.php':
      return reply({'messages': []});
    case 'settings.php':
      return reply({'settings': settings});
    case 'reports.php':
      return reply({
        'from': '2026-11-23',
        'to': '2026-11-29',
        'trips': 0,
        'completed': 0,
        'stops_done': 0,
        'stops_absent': 0,
        'sos': 0,
        'routes': [],
      });
    default:
      throw StateError('Unexpected test request: ${request.url}');
  }
}

class TestTracker extends LocationTracker {
  TestTracker(super.api);
  int stops = 0;
  int starts = 0;
  String? startError;

  @override
  Future<String?> start(int id, String name) async {
    starts++;
    problem = startError;
    if (startError == null) tripId = id;
    notifyListeners();
    return startError;
  }

  @override
  Future<void> stop({bool flush = true}) async {
    stops++;
    tripId = null;
    notifyListeners();
  }
}

class DeniedLocations extends GeolocatorPlatform {
  bool service = true;
  LocationPermission permission = LocationPermission.denied;
  int requests = 0;
  @override
  Future<bool> isLocationServiceEnabled() async => service;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return permission;
  }
}

Future<TestTracker> mount(
  WidgetTester tester,
  Widget screen, {
  FutureOr<http.Response> Function(http.Request)? respond,
  String role = 'admin',
  TestTracker? tracker,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final api =
      tracker?.api ??
      ApiClient(client: MockClient((r) async => (respond ?? fixture)(r)));
  final session = Session(api)
    ..user = AppUser(id: 1, name: 'Test user', role: role);
  final tracking = tracker ?? TestTracker(api);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tracking.dispose();
    session.dispose();
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<Session>.value(value: session),
        ChangeNotifierProvider<LocationTracker>.value(value: tracking),
      ],
      child: MaterialApp(
        theme: buildTheme().copyWith(platform: TargetPlatform.android),
        home: screen,
      ),
    ),
  );
  await tester.pump();
  return tracking;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  for (final role in ['admin', 'staff']) {
    testWidgets(
      '$role keeps three tabs and reaches each permitted native tool',
      (tester) async {
        await mount(tester, const TransportHubScreen(), role: role);
        await tester.pumpAndSettle();
        expect(find.byType(Tab), findsNWidgets(3));
        expect(
          find.text(role == 'admin' ? 'Trips' : 'My trip'),
          findsOneWidget,
        );
        await tester.tap(find.text('Live map'));
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.tap(find.text('Tools'));
        await tester.pumpAndSettle();
        for (final restricted in ['Overview', 'Reports', 'Settings']) {
          expect(
            find.text(restricted),
            role == 'admin' ? findsOneWidget : findsNothing,
          );
        }
        final destinations = [
          if (role == 'admin') ('Overview', 'Test school'),
          ('Passengers', 'No children match'),
          ('Messages', 'No messages yet'),
          ('Arrivals', 'No children match'),
          if (role == 'admin') ('Reports', 'Trips this week'),
          if (role == 'admin') ('Settings', 'Transport contact'),
        ];
        for (final (label, marker) in destinations) {
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(find.text(marker), findsOneWidget);
          if (label == 'Messages') {
            expect(
              find.byTooltip('Broadcast'),
              role == 'admin' ? findsOneWidget : findsNothing,
            );
          }
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
      },
    );
  }

  testWidgets('route failure stops loading and Retry opens a saved trip', (
    tester,
  ) async {
    var attempts = 0;
    Map<String, dynamic>? created;
    await mount(
      tester,
      const NewTripScreen(date: '2026-11-28'),
      respond: (r) {
        if (r.url.path.endsWith('routes.php') && attempts++ == 0) {
          return failure();
        }
        if (r.url.path.endsWith('create.php')) {
          created = jsonDecode(r.body) as Map<String, dynamic>;
          return reply({'trip': tripJson()});
        }
        return fixture(r);
      },
    );
    expect(find.text('Test connection interrupted'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test route'));
    await tester.pumpAndSettle();
    expect(created, {'route_id': 2, 'direction': 'drop', 'date': '2026-11-28'});
    expect(find.byType(TripScreen), findsOneWidget);
  });

  testWidgets('custom child search ignores a late older response', (
    tester,
  ) async {
    final old = Completer<http.Response>();
    await mount(
      tester,
      const CustomTripScreen(direction: 'pickup'),
      respond: (r) {
        if (r.url.queryParameters['q'] == 'a') return old.future;
        if (r.url.queryParameters['q'] == 'bea') {
          return reply({
            'children': [
              {'id': 12, 'name': 'Bea Test', 'grade': 'KG'},
            ],
          });
        }
        return fixture(r);
      },
    );
    await tester.enterText(find.byType(TextField).at(1), 'a');
    await tester.pump(const Duration(milliseconds: 301));
    await tester.enterText(find.byType(TextField).at(1), 'bea');
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pump();
    expect(find.text('Bea Test'), findsOneWidget);
    old.complete(
      reply({
        'children': [
          {'id': 11, 'name': 'Asha Test', 'grade': 'KG'},
        ],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bea Test'), findsOneWidget);
    expect(find.text('Asha Test'), findsNothing);
  });

  testWidgets(
    'custom trip validates input and keeps selections after failed create',
    (tester) async {
      Map<String, dynamic>? created;
      await mount(
        tester,
        const CustomTripScreen(direction: 'pickup'),
        respond: (r) {
          if (r.url.path.endsWith('create.php')) {
            created = jsonDecode(r.body) as Map<String, dynamic>;
            return failure();
          }
          return fixture(r);
        },
      );
      await tester.tap(find.text('Create trip'));
      await tester.pump();
      expect(find.text('Give this trip a name.'), findsOneWidget);
      expect(created, isNull);
      await tester.enterText(find.byType(TextField).first, ' Late pickup ');
      await tester.tap(find.text('Asha Test'));
      await tester.pump();
      await tester.tap(find.text('Create trip'));
      await tester.pumpAndSettle();
      expect(created, {
        'direction': 'pickup',
        'name': 'Late pickup',
        'student_ids': [11],
      });
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create trip'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('failed settings toggle restores the saved switch', (
    tester,
  ) async {
    await mount(
      tester,
      const Scaffold(body: TransportSettingsScreen()),
      respond: (r) {
        return r.method == 'POST' ? failure() : fixture(r);
      },
    );
    await tester.tap(find.text('Notify parents at pickup'));
    await tester.pumpAndSettle();
    expect(find.text('Test connection interrupted'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile).first).value,
      isTrue,
    );
  });

  testWidgets('message response after leaving does not touch disposed input', (
    tester,
  ) async {
    final sent = Completer<http.Response>();
    await mount(
      tester,
      const Scaffold(body: MessagesScreen()),
      respond: (r) {
        return r.method == 'POST' ? sent.future : fixture(r);
      },
    );
    await tester.enterText(find.byType(TextField), 'Test note');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    sent.complete(
      reply({
        'message': {
          'id': 1,
          'name': 'Test user',
          'kind': 'message',
          'label': 'Message',
          'body': 'Test note',
          'at': 'now',
        },
      }),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('declining trip consent sends no start request', (tester) async {
    var posts = 0;
    final tracker = await mount(
      tester,
      TripScreen(initial: Trip.fromJson(tripJson())),
      respond: (r) {
        if (r.method == 'POST') posts++;
        return fixture(r);
      },
    );
    await tester.tap(find.text('Start trip'));
    await tester.pumpAndSettle();
    expect(find.text('Share location during this trip?'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(posts, 0);
    expect(tracker.starts, 0);
  });

  testWidgets('running trip exposes permission failure and allows retry', (
    tester,
  ) async {
    final api = ApiClient(client: MockClient((r) async => fixture(r)));
    final tracker = TestTracker(api)
      ..startError = 'Location permission denied for test';
    await mount(
      tester,
      TripScreen(initial: Trip.fromJson(tripJson(status: 'running'))),
      tracker: tracker,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agree and continue'));
    await tester.pumpAndSettle();
    expect(tracker.starts, 1);
    expect(find.text('Location permission denied for test'), findsWidgets);
    tracker.startError = null;
    await tester.ensureVisible(find.text('Share location'));
    await tester.tap(find.text('Share location'));
    await tester.pumpAndSettle();
    expect(tracker.tripId, 7);
    expect(tracker.starts, 2);
  });

  testWidgets('cancelling a different trip leaves the active tracker running', (
    tester,
  ) async {
    final api = ApiClient(
      client: MockClient(
        (r) async => r.method == 'POST'
            ? reply({'trip': tripJson(status: 'cancelled')})
            : fixture(r),
      ),
    );
    final tracker = TestTracker(api)..tripId = 99;
    await mount(
      tester,
      TripScreen(initial: Trip.fromJson(tripJson())),
      tracker: tracker,
    );
    await tester.tap(find.text('Cancel trip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(tracker.tripId, 99);
    expect(tracker.stops, 0);
  });

  testWidgets(
    'scheduled trip starts with consent, marks a pickup and finishes tracking',
    (tester) async {
      final operations = <String>[];
      final api = ApiClient(
        client: MockClient((r) async {
          if (r.method == 'POST') {
            final op = (jsonDecode(r.body) as Map)['op'] as String;
            operations.add(op);
            return reply({
              'trip': tripJson(
                status: op == 'finish' ? 'completed' : 'running',
                stop: op == 'start' ? 'pending' : 'done',
              ),
            });
          }
          return fixture(r);
        }),
      );
      final tracker = TestTracker(api);
      await mount(
        tester,
        TripScreen(initial: Trip.fromJson(tripJson())),
        tracker: tracker,
      );
      await tester.tap(find.text('Start trip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agree and continue'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Picked up'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Picked up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish trip'));
      await tester.pumpAndSettle();
      expect(operations, ['start', 'done', 'finish']);
      expect(tracker.starts, 1);
      expect(tracker.tripId, isNull);
      expect(tracker.stops, 1);
      expect(find.text('Finish trip'), findsNothing);
    },
  );

  testWidgets('an empty Today can be pulled to refresh after failure', (
    tester,
  ) async {
    var loads = 0;
    await mount(
      tester,
      const TransportTodayScreen(),
      respond: (r) {
        if (r.url.path.endsWith('today.php') && loads++ == 0) return failure();
        return fixture(r);
      },
    );
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.text('No active routes'), findsOneWidget);
  });

  test(
    'disabled GPS and denied permissions never start location sharing',
    () async {
      final original = GeolocatorPlatform.instance;
      final locations = DeniedLocations();
      GeolocatorPlatform.instance = locations;
      final tracker = LocationTracker(
        ApiClient(
          client: MockClient((_) => throw StateError('No HTTP expected')),
        ),
      );
      try {
        locations.service = false;
        expect(await tracker.start(7, 'Test'), contains('Turn on Location'));
        expect(locations.requests, 0);
        locations.service = true;
        expect(await tracker.start(7, 'Test'), contains('Location permission'));
        expect(locations.requests, 1);
        locations.permission = LocationPermission.deniedForever;
        expect(await tracker.start(7, 'Test'), contains('Location permission'));
        expect(locations.requests, 1);
        expect(tracker.active, isFalse);
      } finally {
        tracker.dispose();
        GeolocatorPlatform.instance = original;
      }
    },
  );

  testWidgets(
    'in-trip child picker ignores old results and recovers from search failure',
    (tester) async {
      final old = Completer<http.Response>();
      var failed = false;
      await mount(
        tester,
        TripScreen(initial: Trip.fromJson(tripJson())),
        respond: (r) {
          if (r.url.queryParameters['q'] == 'a') return old.future;
          if (r.url.queryParameters['q'] == 'bea') {
            if (!failed) {
              failed = true;
              return failure();
            }
            return reply({
              'children': [
                {'id': 12, 'name': 'Bea Test', 'grade': 'KG'},
              ],
            });
          }
          return fixture(r);
        },
      );
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a child'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump(const Duration(milliseconds: 301));
      await tester.enterText(find.byType(TextField), 'bea');
      await tester.pump(const Duration(milliseconds: 301));
      await tester.pump();
      expect(find.text('Test connection interrupted'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      old.complete(failure());
      await tester.pumpAndSettle();
      expect(find.text('Bea Test'), findsOneWidget);
      expect(find.text('Test connection interrupted'), findsNothing);
    },
  );

  testWidgets(
    'completed trip opens once without writes and refreshes Today on return',
    (tester) async {
      var todayLoads = 0;
      var opens = 0;
      var posts = 0;
      final opened = Completer<http.Response>();
      await mount(
        tester,
        const TransportTodayScreen(),
        respond: (r) {
          if (r.method == 'POST') posts++;
          if (r.url.path.endsWith('today.php')) {
            todayLoads++;
            return reply({
              'trips': [
                {
                  'route_id': 2,
                  'route_name': 'Test route',
                  'direction': 'pickup',
                  'direction_label': 'Pickup',
                  'cab_name': 'Test cab',
                  'children': 1,
                  'trip_id': 7,
                  'status': 'completed',
                  'status_label': 'Completed',
                  'finished': 1,
                  'total': 1,
                },
              ],
            });
          }
          if (r.url.path.endsWith('trip.php')) {
            opens++;
            return opened.future;
          }
          return fixture(r);
        },
      );
      await tester.tap(find.text('Test route'));
      await tester.pump();
      await tester.tap(find.text('Test route'));
      await tester.pump();
      expect(opens, 1);
      opened.complete(
        reply({'trip': tripJson(status: 'completed', stop: 'done')}),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TripScreen), findsOneWidget);
      expect(find.text('Start trip'), findsNothing);
      expect(find.text('Cancel trip'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(todayLoads, 2);
      expect(posts, 0);
    },
  );

  testWidgets('hub calendar opens a day and returns to Trips', (tester) async {
    String? requestedDate;
    await mount(
      tester,
      const TransportHubScreen(),
      respond: (r) {
        if (r.url.path.endsWith('today.php') &&
            r.url.queryParameters['date'] != null) {
          requestedDate = r.url.queryParameters['date'];
        }
        return fixture(r);
      },
    );
    await tester.tap(find.byTooltip('Calendar'));
    await tester.pumpAndSettle();
    expect(find.text('Trip calendar'), findsOneWidget);
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(requestedDate, endsWith('-01'));
    expect(find.text('No active routes'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Transport desk'), findsOneWidget);
  });

  testWidgets(
    'server access denial leaves a readable Transport error without a spinner',
    (tester) async {
      await mount(
        tester,
        const TransportTodayScreen(),
        respond: (_) => http.Response(
          '{"ok":false,"error":"Transport access denied","code":"forbidden"}',
          403,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Transport access denied'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(TripScreen), findsNothing);
    },
  );

  testWidgets('custom child search offers Retry then an empty result message', (
    tester,
  ) async {
    var tries = 0;
    await mount(
      tester,
      const CustomTripScreen(direction: 'pickup'),
      respond: (r) {
        if (tries++ == 0) return failure();
        return reply({'children': []});
      },
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No children match'), findsOneWidget);
  });

  testWidgets(
    'settings initial error can retry and persist an acknowledged change',
    (tester) async {
      var loads = 0;
      Map<String, dynamic>? saved;
      await mount(
        tester,
        const Scaffold(body: TransportSettingsScreen()),
        respond: (r) {
          if (r.method == 'POST') {
            saved = jsonDecode(r.body) as Map<String, dynamic>;
            return reply({
              'settings': {...settings, ...saved!},
            });
          }
          if (loads++ == 0) return failure();
          return fixture(r);
        },
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notify parents at pickup'));
      await tester.pumpAndSettle();
      expect(saved?['notify_pickup'], isFalse);
      expect(find.text('Saved.'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile).first).value,
        isFalse,
      );
    },
  );

  testWidgets(
    'message in flight preserves a newly typed draft and prevents duplicate send',
    (tester) async {
      final sent = Completer<http.Response>();
      var posts = 0;
      await mount(
        tester,
        const Scaffold(body: MessagesScreen()),
        respond: (r) {
          if (r.method == 'POST') {
            posts++;
            return sent.future;
          }
          return fixture(r);
        },
      );
      await tester.enterText(find.byType(TextField), 'First note');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Next draft');
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.send_rounded),
            )
            .onPressed,
        isNull,
      );
      sent.complete(
        reply({
          'message': {
            'id': 1,
            'name': 'Test user',
            'kind': 'message',
            'label': 'Message',
            'body': 'First note',
            'at': 'now',
          },
        }),
      );
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(find.text('Next draft'), findsOneWidget);
    },
  );

  for (final (label, screen, marker) in <(String, Widget, String)>[
    ('Live map', const LiveScreen(), 'No cab is on the road'),
    ('Overview', const OverviewScreen(), 'Test school'),
    ('Reports', const ReportsScreen(), 'Trips this week'),
    ('Passengers', const RosterScreen(), 'No children match'),
    ('Messages', const MessagesScreen(), 'No messages yet'),
  ]) {
    testWidgets(
      '$label recovers from initial failure by pulling a short list',
      (tester) async {
        var loads = 0;
        await mount(
          tester,
          Scaffold(body: screen),
          respond: (r) {
            if (loads++ == 0) return failure();
            return fixture(r);
          },
        );
        expect(find.text('Test connection interrupted'), findsOneWidget);
        await tester.drag(find.byType(ListView), const Offset(0, 350));
        await tester.pumpAndSettle();
        expect(loads, 2);
        expect(find.text(marker), findsOneWidget);
      },
    );
  }
}
