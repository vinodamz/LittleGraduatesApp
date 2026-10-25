import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_graduates/core/api_client.dart';
import 'package:little_graduates/core/session.dart';
import 'package:little_graduates/core/theme.dart';
import 'package:little_graduates/features/materials/materials_api.dart';
import 'package:little_graduates/features/materials/materials_controller.dart';
import 'package:little_graduates/features/shell/app_shell.dart';
import 'package:little_graduates/features/transport/location_tracker.dart';
import 'package:provider/provider.dart';

// Fixture data is isolated to tests. No preview data enters production screens.
const _modules = [
  {'key': 'transport', 'label': 'Transport', 'native': true, 'web_url': ''},
  {'key': 'staff', 'label': 'Staff', 'native': true, 'web_url': ''},
  {'key': 'materials', 'label': 'Materials', 'native': true, 'web_url': ''},
  {
    'key': 'students',
    'label': 'Students',
    'native': false,
    'web_url': 'https://example.test/students',
  },
  {
    'key': 'fees',
    'label': 'Fees',
    'native': false,
    'web_url': 'https://example.test/fees',
  },
  {
    'key': 'tasks',
    'label': 'Tasks',
    'native': false,
    'web_url': 'https://example.test/tasks',
  },
];

class _Materials extends ChangeNotifier implements MaterialsController {
  @override
  MaterialsDay? get day => MaterialsDay.fromJson({
    'summary': {'checked': 18, 'total': 24, 'pending': 6},
  });
  @override
  int get pendingCount => 0;
  @override
  Future<void> kick() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app({double scale = 1, bool failStaff = false}) {
  final api = ApiClient(
    client: MockClient((req) async {
      final path = req.url.path;
      if (path.endsWith('staff/today.php') && failStaff) {
        return http.Response(
          jsonEncode({
            'ok': false,
            'error': 'Attendance unavailable. Try again.',
          }),
          503,
        );
      }
      final data = path.endsWith('me.php')
          ? {
              'user': {'id': 1, 'name': 'Priya Nair', 'role': 'admin'},
              'school': 'Little Graduates',
              'modules': _modules,
            }
          : path.endsWith('staff/today.php')
          ? {
              'day': {
                'attendance': {
                  'status_label': 'Not checked in',
                  'shift_label': '9:00 AM - 5:00 PM',
                },
              },
            }
          : {'trips': <Object>[]};
      return http.Response(jsonEncode({'ok': true, ...data}), 200);
    }),
  );
  final session = Session(api)
    ..user = AppUser(id: 1, name: 'Priya Nair', role: 'admin')
    ..modules = _modules.map(AppModule.fromJson).toList();
  return MultiProvider(
    providers: [
      Provider.value(value: api),
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider(create: (_) => LocationTracker(api)),
      ChangeNotifierProvider<MaterialsController>(create: (_) => _Materials()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: const AppShell(),
    ),
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('LG_DESIGN_PREVIEWS')) return;
  final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
    find.byKey(const Key('preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('docs/previews/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    for (final family in ['Nunito', 'Baloo2']) {
      final font = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/$family.ttf'));
      await font.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  testWidgets('school search finds tools by task and survives tab switches', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      RepaintBoundary(key: const Key('preview'), child: _app()),
    );
    await tester.pumpAndSettle();
    await _capture(tester, 'today-phone');
    await tester.tap(find.widgetWithText(NavigationDestination, 'School'));
    await tester.pumpAndSettle();
    await _capture(tester, 'school-phone');
    await tester.enterText(find.byType(TextField), 'attendance');
    await tester.pumpAndSettle();
    expect(find.text('Attendance, leave & your team'), findsOneWidget);
    expect(find.text('Fee records & collections'), findsNothing);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Today'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, 'School'));
    await tester.pumpAndSettle();
    expect(find.text('attendance'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Fee records & collections'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(375, 812),
    const Size(812, 375),
    const Size(1024, 768),
    const Size(1440, 900),
  ]) {
    testWidgets('operations layout fits $size at 2x text with reduced motion', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(scale: 2));
      await tester.pumpAndSettle();
      if (size.width >= 840) {
        expect(find.byType(NavigationRail), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
      } else {
        expect(find.byType(NavigationBar), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('attendance failure exposes a retry without blocking the desk', (
    tester,
  ) async {
    await tester.pumpWidget(_app(failStaff: true));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Retry attendance'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Attendance unavailable. Try again.'), findsOneWidget);
    expect(find.text('Retry attendance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet preview uses the expanded school workspace', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      RepaintBoundary(key: const Key('preview'), child: _app()),
    );
    await tester.pumpAndSettle();
    await _capture(tester, 'today-tablet');
    await tester.tap(find.text('School').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
