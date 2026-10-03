import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/staff/staff_screen.dart';
import '../features/transport/today_screen.dart';
import 'nav.dart';
import 'session.dart';

/// Native screens by module key. To bring another MTT module into the app,
/// add its screen here and mark it `native` in the server's api_app_modules().
final Map<String, WidgetBuilder> nativeModuleScreens = {
  'transport': (_) => const TransportTodayScreen(),
  'staff': (_) => const StaffScreen(),
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

/// Transport and Staff have screens in this build even if an older server
/// still marks them as website links.
bool moduleOpensInApp(AppModule m) =>
    m.native || m.key == 'transport' || m.key == 'staff';

Future<void> openModule(BuildContext context, AppModule m) async {
  if (m.key == 'transport' || m.key == 'staff') {
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
  final ok = await launchUrl(Uri.parse(m.webUrl), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open ${m.label}.')));
  }
}

Future<void> openWebUrl(BuildContext context, String url, String label) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open $label.')));
  }
}
