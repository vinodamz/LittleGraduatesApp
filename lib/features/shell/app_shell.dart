import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/nav.dart';
import '../../core/notifications.dart';
import '../../core/api_client.dart';
import '../../core/module_registry.dart';
import '../transport/transport_api.dart';
import '../transport/trip_screen.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/school_logo.dart';
import '../home/home_screen.dart';
import '../materials/materials_controller.dart';

class _Tab {
  const _Tab(this.key, this.label, this.icon, this.page);

  final String key;
  final String label;
  final IconData icon;
  final Widget page;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  String _selectedKey = 'today';
  int _todayRevision = 0;
  final Set<String> _visited = {'today'};
  StreamSubscription<String>? _notificationTaps;

  Future<void> _openNotification(String payload) async {
    final parts = payload.split(':');
    if (parts.length != 2) return;
    final tripId = int.tryParse(parts[0]);
    final stopId = int.tryParse(parts[1]);
    if (tripId == null || stopId == null) return;
    Notifications.pending = null;
    try {
      final trip = await TransportApi(context.read<ApiClient>()).trip(tripId);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TripScreen(initial: trip, focusStopId: stopId),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationTaps = Notifications.taps.listen(_openNotification);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Notifications.pending != null) {
        _openNotification(Notifications.pending!);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationTaps?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(context.read<MaterialsController>().kick());
    }
  }

  List<_Tab> _tabs(Session session) {
    return [
      _Tab(
        'today',
        'Today',
        Icons.wb_sunny_rounded,
        TodayScreen(
          key: ValueKey(_todayRevision),
          active: _selectedKey == 'today',
        ),
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
    } else {
      final allowed = context.read<Session>().modules.any(
        (module) => module.key == key,
      );
      final builder = nativeModuleScreens[key];
      if (allowed && builder != null) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: builder)).then((_) {
          if (mounted) setState(() => _todayRevision++);
        });
      }
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
                          child: SchoolLogo(size: 56),
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
