import 'package:flutter/material.dart';
import '../features/workspace/workspace_screen.dart';
import '../features/workspace/workspace_contract.dart';

import '../features/materials/materials_screen.dart';
import '../features/staff/staff_screen.dart';
import '../features/transport/hub_screen.dart';
import 'nav.dart';
import 'session.dart';

/// Native screens by module key. To bring another MTT module into the app,
/// add its screen here. Other school tools use the shared workspace.
final Map<String, WidgetBuilder> nativeModuleScreens = {
  'transport': (_) => const TransportHubScreen(),
  'staff': (_) => const StaffScreen(),
  'materials': (_) => const MaterialsScreen(),
};

const Map<String, IconData> moduleIcons = {
  'transport': Icons.directions_bus_rounded,
  'students': Icons.child_care_rounded,
  'montessori': Icons.auto_stories_rounded,
  'tasks': Icons.checklist_rounded,
  'staff': Icons.badge_rounded,
  'crm': Icons.how_to_reg_rounded,
  'fees': Icons.receipt_long_rounded,
  'expenses': Icons.account_balance_wallet_rounded,
  'logbook': Icons.menu_book_rounded,
  'inventory': Icons.inventory_2_rounded,
  'materials': Icons.category_rounded,
  'plans': Icons.event_note_rounded,
  'daycare': Icons.bedtime_rounded,
  'recruitment': Icons.work_rounded,
};

/// All trusted school tools stay inside the app, including legacy modules.
bool moduleOpensInApp(AppModule m) =>
    nativeModuleScreens.containsKey(m.key) || isSchoolUrl(m.webUrl);

Future<void> openModule(BuildContext context, AppModule m) async {
  if (m.key == 'transport' || m.key == 'staff' || m.key == 'materials') {
    final nav = LgNav.maybeOf(context);
    if (nav != null) {
      nav.go(m.key);
      return;
    }
  }
  final builder = moduleOpensInApp(m) ? nativeModuleScreens[m.key] : null;
  if (builder != null) {
    await Navigator.of(context).push(MaterialPageRoute(builder: builder));
    return;
  }
  await openWebUrl(context, m.webUrl, m.label);
}

Future<void> openWebUrl(BuildContext context, String url, String label) async {
  if (!isSchoolUrl(url)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This is not a supported school link.')),
    );
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => WorkspaceScreen(url: url, label: label),
    ),
  );
}
