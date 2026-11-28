import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_graduates/core/api_client.dart';
import 'package:little_graduates/core/session.dart';
import 'package:little_graduates/core/theme.dart';
import 'package:little_graduates/features/home/class_attendance_screen.dart';
import 'package:little_graduates/features/home/home_screen.dart';
import 'package:little_graduates/features/materials/materials_controller.dart';
import 'package:little_graduates/features/transport/location_tracker.dart';
import 'package:provider/provider.dart';

class _Materials extends ChangeNotifier implements MaterialsController {
  @override
  int get pendingCount => 0;
  @override
  Future<void> kick() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _links = {
  'my_day': 'https://mtt.thelittlegraduates.in/today.php',
  'attendance': 'https://mtt.thelittlegraduates.in/students/attendance.php',
  'duties': 'https://mtt.thelittlegraduates.in/duties/index.php',
  'assessment': 'https://mtt.thelittlegraduates.in/assessment/index.php',
  'leave_review': 'https://mtt.thelittlegraduates.in/staff/leave.php',
  'staff_today': 'https://mtt.thelittlegraduates.in/staff/attendance.php',
};

Map<String, dynamic> _classOf(List<String?> statuses) {
  final kids = [
    for (var i = 0; i < statuses.length; i++)
      {
        'id': i + 1,
        'name': 'Child ${i + 1}',
        'grade': 'LKG',
        'status': statuses[i],
      },
  ];
  final unsaved = statuses.where((s) => s == null).length;
  return {
    'counts': {
      'total': statuses.length,
      'unsaved': unsaved,
      'present': statuses.where((s) => s == 'present' || s == 'late').length,
      'absent': statuses.where((s) => s == 'absent').length,
      'other': 0,
    },
    'students': kids,
    'statuses': ['present', 'absent', 'late', 'excused', 'holiday'],
    'can_cover': false,
  };
}

class _Server {
  _Server(this.today);

  Map<String, dynamic> today;
  final posts = <Map<String, dynamic>>[];

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    Map<String, dynamic> data;
    if (path.endsWith('class/attendance.php')) {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      posts.add(body);
      final kids = (today['class']['students'] as List).cast<Map>();
      final statuses = [
        for (final k in kids)
          body['op'] == 'rest_present'
              ? (k['status'] ?? 'present') as String?
              : (k['id'] == body['student_id'] ? body['status'] : k['status'])
                    as String?,
      ];
      today = {...today, 'class': _classOf(statuses)};
      data = {'today': today};
    } else if (path.endsWith('/v1/today.php')) {
      data = {'today': today};
    } else if (path.endsWith('me.php')) {
      data = {
        'user': {'id': 2, 'name': 'Priya Nair', 'role': 'teacher'},
        'school': 'Little Graduates',
        'modules': <Object>[],
      };
    } else {
      data = {};
    }
    return http.Response(jsonEncode({'ok': true, ...data}), 200);
  }
}

Widget _app(_Server server, {String role = 'teacher'}) {
  final api = ApiClient(client: MockClient(server.handle));
  final session = Session(api)
    ..user = AppUser(id: 2, name: 'Priya Nair', role: role)
    ..modules = [];
  return MultiProvider(
    providers: [
      Provider.value(value: api),
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider(create: (_) => LocationTracker(api)),
      ChangeNotifierProvider<MaterialsController>(create: (_) => _Materials()),
    ],
    child: MaterialApp(theme: buildTheme(), home: const TodayScreen()),
  );
}

Map<String, dynamic> _summary({
  Map<String, dynamic>? myClass,
  int duties = 0,
  int assessments = 0,
  Map<String, dynamic>? admin,
}) => {
  'class': myClass,
  'duties_pending': duties,
  'assessments_pending': assessments,
  'admin': admin,
  'links': _links,
};

void main() {
  testWidgets('teacher marks the whole class present from Today', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final server = _Server(
      _summary(
        myClass: _classOf([null, null, null]),
        duties: 2,
        assessments: 3,
      ),
    );
    await tester.pumpWidget(_app(server));
    await tester.pumpAndSettle();
    expect(find.text('My class · 3 children'), findsOneWidget);
    expect(find.text('Attendance not taken yet'), findsOneWidget);
    expect(find.text('2 duties to tick'), findsOneWidget);
    expect(find.text('3 children to assess this month'), findsOneWidget);

    await tester.tap(find.text('Everyone is present'));
    await tester.pumpAndSettle();
    expect(server.posts.single['op'], 'rest_present');
    expect(find.text('Attendance saved'), findsOneWidget);
    expect(find.text('Change attendance'), findsOneWidget);
  });

  testWidgets('class register saves each tap and keeps earlier marks', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final server = _Server(_summary(myClass: _classOf([null, null])));
    await tester.pumpWidget(_app(server));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark absent or late'));
    await tester.pumpAndSettle();
    expect(find.byType(ClassAttendanceScreen), findsOneWidget);
    expect(find.text('Not marked'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(ChoiceChip, 'Absent').first);
    await tester.pumpAndSettle();
    expect(server.posts.single, {
      'op': 'set',
      'student_id': 1,
      'status': 'absent',
    });
    expect(find.text('Not marked'), findsOneWidget);

    await tester.tap(find.text('Mark the rest present'));
    await tester.pumpAndSettle();
    expect(server.posts.last['op'], 'rest_present');
    expect(find.text('Not marked'), findsNothing);
    expect(find.textContaining('1 absent'), findsOneWidget);
  });

  testWidgets('subteacher without a class is offered to cover one', (
    tester,
  ) async {
    final server = _Server(
      _summary(myClass: {..._classOf([]), 'can_cover': true}),
    );
    await tester.pumpWidget(_app(server));
    await tester.pumpAndSettle();
    expect(find.text('Mark class attendance'), findsOneWidget);
    expect(find.textContaining('My class'), findsNothing);
  });

  testWidgets('support staff see duties but no class card', (tester) async {
    final server = _Server(_summary(duties: 1));
    await tester.pumpWidget(_app(server, role: 'non_teaching'));
    await tester.pumpAndSettle();
    expect(find.text('1 duty to tick'), findsOneWidget);
    expect(find.textContaining('class'), findsNothing);
  });

  testWidgets('admin sees who is in and leave to approve', (tester) async {
    final server = _Server(
      _summary(admin: {'staff_total': 9, 'staff_in': 7, 'leave_to_review': 2}),
    );
    await tester.pumpWidget(_app(server, role: 'admin'));
    await tester.pumpAndSettle();
    expect(find.text('7 of 9 staff checked in'), findsOneWidget);
    expect(find.text('2 leave requests to approve'), findsOneWidget);
  });

  testWidgets(
    'an older school server without the endpoint leaves Today as it was',
    (tester) async {
      final api = ApiClient(
        client: MockClient((req) async {
          if (req.url.path.endsWith('/v1/today.php')) {
            return http.Response('Not found', 404);
          }
          return _Server(_summary()).handle(req);
        }),
      );
      final session = Session(api)
        ..user = AppUser(id: 2, name: 'Priya Nair', role: 'teacher')
        ..modules = [];
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider.value(value: api),
            ChangeNotifierProvider.value(value: session),
            ChangeNotifierProvider(create: (_) => LocationTracker(api)),
            ChangeNotifierProvider<MaterialsController>(
              create: (_) => _Materials(),
            ),
          ],
          child: MaterialApp(theme: buildTheme(), home: const TodayScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('My class'), findsNothing);
    },
  );
}
