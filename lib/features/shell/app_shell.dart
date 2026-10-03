import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../home/home_screen.dart';
import '../staff/staff_screen.dart';
import '../transport/today_screen.dart';

class _Tab {
  const _Tab(this.key, this.label, this.icon, this.page);

  final String key;
  final String label;
  final IconData icon;
  final Widget page;
}

/// Signed-in frame. Today, Transport and Staff stay one tap apart.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  List<_Tab> _tabs(Session session) {
    final keys = session.modules.map((m) => m.key).toSet();
    return [
      const _Tab('today', 'Today', Icons.wb_sunny_rounded, TodayScreen()),
      if (keys.contains('transport'))
        const _Tab('transport', 'Transport', Icons.directions_bus_rounded, TransportTodayScreen()),
      if (keys.contains('staff')) const _Tab('staff', 'Staff', Icons.badge_rounded, StaffScreen()),
      const _Tab('more', 'More', Icons.grid_view_rounded, MoreScreen()),
    ];
  }

  void _go(List<_Tab> tabs, String key) {
    final next = tabs.indexWhere((t) => t.key == key);
    if (next >= 0) setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final tabs = _tabs(session);
    final index = _index.clamp(0, tabs.length - 1);
    return LgNav(
      go: (key) => _go(tabs, key),
      child: Scaffold(
        body: tabs[index].page,
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: LgColors.surface,
            border: Border(top: BorderSide(color: LgColors.line)),
          ),
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final t in tabs)
                NavigationDestination(icon: Icon(t.icon), label: t.label),
            ],
          ),
        ),
      ),
    );
  }
}
