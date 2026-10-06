import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import 'live_screen.dart';
import 'messages_screen.dart';
import 'overview_screen.dart';
import 'reports_screen.dart';
import 'roster_screen.dart';
import 'settings_screen.dart';
import 'today_screen.dart';

/// Transport desk. Admins see the operations overview; drivers see their runs,
/// the live map, passengers, class arrivals and messages.
class TransportHubScreen extends StatelessWidget {
  const TransportHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<Session>().user?.isAdmin ?? false;
    final tabs = admin
        ? const [
            ('Overview', OverviewScreen()),
            ('Live', LiveScreen()),
            ('Trips', TransportTodayScreen(embedded: true)),
            ('Students', RosterScreen()),
            ('More', _TransportMore()),
          ]
        : const [
            ('My trip', TransportTodayScreen(embedded: true)),
            ('Live', LiveScreen()),
            ('Passengers', RosterScreen()),
            ('Arrivals', RosterScreen(arrivals: true)),
            ('Messages', MessagesScreen()),
          ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(admin ? 'Transport desk' : 'Transport'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final t in tabs) Tab(text: t.$1)],
          ),
        ),
        body: TabBarView(children: [for (final t in tabs) t.$2]),
      ),
    );
  }
}

class _TransportMore extends StatelessWidget {
  const _TransportMore();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.forum_rounded),
          title: const Text('Messages'),
          subtitle: const Text('Route notes, broadcasts and SOS'),
          onTap: () => _open(context, 'Messages', const MessagesScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.school_rounded),
          title: const Text('Arrivals'),
          subtitle: const Text('Handover from the cab to class'),
          onTap: () => _open(context, 'Arrivals', const RosterScreen(arrivals: true)),
        ),
        ListTile(
          leading: const Icon(Icons.insights_rounded),
          title: const Text('Reports'),
          subtitle: const Text('This week’s trips'),
          onTap: () => _open(context, 'Reports', const ReportsScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.tune_rounded),
          title: const Text('Settings'),
          subtitle: const Text('Parent alerts, speed and trip history'),
          onTap: () => _open(context, 'Settings', const TransportSettingsScreen()),
        ),
      ],
    );
  }

  void _open(BuildContext context, String title, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text(title)), body: page)));
  }
}
