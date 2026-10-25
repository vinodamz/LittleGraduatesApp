import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../home/home_screen.dart';
import '../materials/materials_controller.dart';
import '../materials/materials_screen.dart';
import '../staff/staff_screen.dart';
import '../transport/hub_screen.dart';

class _Tab {
  const _Tab(this.key, this.label, this.icon, this.page);

  final String key;
  final String label;
  final IconData icon;
  final Widget page;
}

/// Signed-in frame. Today, Transport, Staff and Materials stay one tap apart.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  String _selectedKey = 'today';
  final Set<String> _visited = {'today'};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(context.read<MaterialsController>().kick());
    }
  }

  List<_Tab> _tabs(Session session) {
    final keys = session.modules.map((m) => m.key).toSet();
    return [
      _Tab(
        'today',
        'Today',
        Icons.wb_sunny_rounded,
        TodayScreen(active: _selectedKey == 'today'),
      ),
      if (keys.contains('transport'))
        const _Tab(
          'transport',
          'Transport',
          Icons.directions_bus_rounded,
          TransportHubScreen(),
        ),
      if (keys.contains('staff'))
        const _Tab('staff', 'Staff', Icons.badge_rounded, StaffScreen()),
      if (keys.contains('materials'))
        const _Tab(
          'materials',
          'Materials',
          Icons.category_rounded,
          MaterialsScreen(),
        ),
      const _Tab('more', 'School', Icons.grid_view_rounded, MoreScreen()),
    ];
  }

  void _go(List<_Tab> tabs, String key) {
    final next = tabs.indexWhere((t) => t.key == key);
    if (next >= 0) {
      setState(() {
        _selectedKey = key;
        _visited.add(key);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final tabs = _tabs(session);
    final selected = tabs.indexWhere((tab) => tab.key == _selectedKey);
    final index = selected < 0 ? 0 : selected;
    return LgNav(
      go: (key) => _go(tabs, key),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 840;
          return Scaffold(
            body: Row(
              children: [
                if (wide)
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      color: LgColors.surface,
                      border: Border(right: BorderSide(color: LgColors.line)),
                    ),
                    child: SafeArea(
                      child: NavigationRail(
                        extended: constraints.maxWidth >= 1200,
                        backgroundColor: LgColors.surface,
                        indicatorColor: LgColors.accentSoft,
                        selectedIndex: index,
                        onDestinationSelected: (i) => _go(tabs, tabs[i].key),
                        leading: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Icon(
                            Icons.school_outlined,
                            color: LgColors.accent,
                            size: 32,
                          ),
                        ),
                        destinations: [
                          for (final t in tabs)
                            NavigationRailDestination(
                              icon: Icon(t.icon),
                              label: Text(t.label),
                            ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: IndexedStack(
                        index: index,
                        children: [
                          for (final tab in tabs)
                            _visited.contains(tab.key)
                                ? tab.page
                                : const SizedBox.shrink(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: wide
                ? null
                : DecoratedBox(
                    decoration: const BoxDecoration(
                      color: LgColors.surface,
                      border: Border(top: BorderSide(color: LgColors.line)),
                    ),
                    child: NavigationBar(
                      selectedIndex: index,
                      onDestinationSelected: (i) => _go(tabs, tabs[i].key),
                      destinations: [
                        for (final t in tabs)
                          NavigationDestination(
                            icon: Icon(t.icon),
                            label: t.label,
                          ),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }
}
