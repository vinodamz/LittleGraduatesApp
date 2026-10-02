import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/module_registry.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../transport/location_tracker.dart';

/// One tile per MTT module the user has. Native modules open in the app;
/// the rest open the website until they are rebuilt here.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final tracker = context.watch<LocationTracker>();
    final user = session.user;
    return Scaffold(
      appBar: AppBar(
        title: Text(session.school),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'out') {
                await context.read<LocationTracker>().stop();
                if (context.mounted) await context.read<Session>().signOut();
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'out', child: Text('Sign out'))],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            await session.refresh();
          } on ApiException catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
            }
          }
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(user == null ? '' : 'Hello, ${user.name.split(' ').first}',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            if (tracker.active)
              Card(
                color: LgColors.warnBg,
                child: ListTile(
                  leading: const Icon(Icons.my_location, color: LgColors.warn),
                  title: Text('Trip running · ${tracker.routeName}'),
                  subtitle: const Text('Sharing the cab location'),
                ),
              ),
            if (session.modules.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No modules are turned on for your login yet. Ask the school admin.',
                    style: TextStyle(color: LgColors.muted)),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.35,
                children: [
                  for (final m in session.modules)
                    Card(
                      margin: const EdgeInsets.all(6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => openModule(context, m),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(moduleIcons[m.key] ?? Icons.apps_rounded, color: LgColors.accent, size: 30),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                                  if (!m.native)
                                    const Text('Opens website', style: TextStyle(color: LgColors.muted, fontSize: 12)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
