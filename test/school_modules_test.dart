import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_graduates/core/api_client.dart';
import 'package:little_graduates/core/module_registry.dart';
import 'package:little_graduates/core/session.dart';
import 'package:little_graduates/features/home/home_screen.dart';
import 'package:little_graduates/features/home/school_catalog.dart';
import 'package:provider/provider.dart';

const additions = {
  'my_day': ('My Day', '/today.php'),
  'duties': ('My duties', '/duties/index.php'),
  'my_leave': ('My leave', '/staff/leave.php'),
  'notifications': ('Notifications', '/notifications.php'),
  'money': ('Money overview', '/money.php'),
  'duties_admin': ('Duty lists', '/duties/admin.php'),
  'feedback': ('Feedback', '/feedback/index.php'),
  'surveys': ('Surveys', '/surveys/index.php'),
  'grades': ('Grades', '/grades.php'),
  'mcp_admin': ('MCP API', '/mcp_admin.php'),
  'admin': ('Admin', '/admin.php'),
  'wacrm': ('WhatsApp CRM', '/wacrm/index.php'),
  'n8n': ('Automations', '/n8n/index.php'),
};

void main() {
  final modules = [
    for (final entry in additions.entries)
      AppModule(
        key: entry.key,
        label: entry.value.$1,
        native: false,
        webUrl: 'https://mtt.thelittlegraduates.in${entry.value.$2}',
      ),
  ];

  test(
    'grouping preserves every permitted module and contains unknown tools',
    () {
      final future = AppModule(
        key: 'new_module',
        label: 'New tool',
        native: false,
        webUrl: 'https://mtt.thelittlegraduates.in/new.php',
      );
      final input = [...modules, future];
      final grouped = groupSchoolModules(input);
      expect(
        grouped.values.expand((items) => items).map((module) => module.key),
        unorderedEquals(input.map((module) => module.key)),
      );
      expect(grouped['Other tools']!.single, future);
      expect(groupSchoolModules([]), isEmpty);
      expect(dailyShortcuts(input).length, lessThanOrEqualTo(4));
      expect(
        dailyShortcuts(
          input,
        ).any((module) => ['admin', 'mcp_admin', 'n8n'].contains(module.key)),
        isFalse,
      );
    },
  );

  test(
    'all additional tools use supported embedded routes and have descriptions',
    () {
      for (final module in modules) {
        expect(moduleOpensInApp(module), isTrue, reason: module.key);
        expect(nativeModuleScreens.containsKey(module.key), isFalse);
        expect(moduleIcons[module.key], isNotNull);
        expect(moduleDescription(module.key, true), isNot('Open school tool'));
      }
      expect(nativeModuleScreens.containsKey('my_leave'), isFalse);
      expect(nativeModuleScreens.containsKey('staff'), isTrue);
    },
  );

  testWidgets('all supplied school tools can be found through menu search', (
    tester,
  ) async {
    final session = Session(ApiClient())..modules = modules;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: const MaterialApp(home: MoreScreen()),
      ),
    );
    for (final module in modules) {
      await tester.enterText(find.byType(TextField), module.label);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ModuleRow),
          matching: find.text(module.label),
        ),
        findsOneWidget,
      );
    }
    session.modules = [
      modules.firstWhere((module) => module.key == 'my_leave'),
    ];
    await tester.enterText(find.byType(TextField), 'Admin');
    await tester.pumpAndSettle();
    expect(find.byType(ModuleRow), findsNothing);
    await tester.enterText(find.byType(TextField), 'leave');
    await tester.pumpAndSettle();
    expect(find.byType(ModuleRow), findsOneWidget);
  });
}
