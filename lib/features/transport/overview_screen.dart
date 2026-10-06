import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'desk.dart';
import 'new_trip_screen.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  late final DeskApi _api = DeskApi(context.read<ApiClient>());
  TransportOverview? _desk;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _api.overview();
      if (mounted) {
        setState(() {
          _desk = d;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _export() async {
    try {
      final roster = await _api.roster();
      await Clipboard.setData(ClipboardData(text: rosterCsv(roster.children)));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Student list copied. Paste it into a spreadsheet.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final desk = _desk;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (_error != null)
            LgNotice(message: _error!, foreground: LgColors.danger, background: LgColors.dangerBg, icon: Icons.error_outline_rounded),
          if (desk == null && _error == null)
            const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator())),
          if (desk != null) ...[
            Text(desk.school, style: Theme.of(context).textTheme.titleMedium),
            if (desk.contact.isNotEmpty)
              Text('Transport ${desk.contact}', style: const TextStyle(color: LgColors.muted)),
            const SizedBox(height: 12),
            _KpiGrid(kpis: desk.kpis),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: OutlinedButton.icon(onPressed: _export, icon: const Icon(Icons.ios_share_rounded), label: const Text('Export'))),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewTripScreen())),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New trip'),
                  ),
                ),
              ],
            ),
            const LgSectionTitle('Needs attention'),
            if (desk.alerts.isEmpty)
              const Text('Nothing waiting on you.', style: TextStyle(color: LgColors.muted)),
            for (final a in desk.alerts) ...[
              _AlertCard(alert: a),
              const SizedBox(height: 8),
            ],
            const LgSectionTitle('Route progress'),
            if (desk.routes.isEmpty)
              const LgEmptyState(icon: Icons.directions_bus_rounded, title: 'No routes today'),
            for (final r in desk.routes) ...[
              _RouteProgress(route: r),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.kpis});

  final DeskKpis kpis;

  @override
  Widget build(BuildContext context) {
    final cells = [
      ('${kpis.vehiclesActive} of ${kpis.vehiclesTotal}', 'Vehicles on the road'),
      ('${kpis.aboard}', 'Children aboard'),
      ('${kpis.onTimePct}%', 'On time'),
      ('${kpis.alerts}', 'Open alerts'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.7,
      children: [
        for (final c in cells)
          DecoratedBox(
            decoration: BoxDecoration(
              color: LgColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: LgColors.line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(c.$1, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  Text(c.$2, style: const TextStyle(color: LgColors.muted, fontSize: 13)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final DeskAlert alert;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (alert.tone) {
      'danger' => (LgColors.danger, LgColors.dangerBg),
      'info' => (LgColors.info, LgColors.infoBg),
      _ => (LgColors.warn, LgColors.warnBg),
    };
    return LgNotice(message: '${alert.title}. ${alert.detail}', foreground: fg, background: bg, icon: Icons.notification_important_rounded);
  }
}

class _RouteProgress extends StatelessWidget {
  const _RouteProgress({required this.route});

  final DeskRoute route;

  @override
  Widget build(BuildContext context) {
    final value = route.total == 0 ? 0.0 : route.finished / route.total;
    final who = [
      route.directionLabel,
      if (route.runNo > 1) 'Run ${route.runNo}',
      if (route.driverName.isNotEmpty) route.driverName,
      if (route.cabName.isNotEmpty) route.cabName,
    ].join(' · ');
    return Material(
      color: LgColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: LgColors.line)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(route.routeName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text(who, style: const TextStyle(color: LgColors.muted)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: value.clamp(0, 1), minHeight: 8, backgroundColor: const Color(0xFFF3EEE8)),
            ),
            const SizedBox(height: 6),
            Text(
              route.nextStop == null
                  ? '${route.statusLabel} · ${route.finished}/${route.total}'
                  : 'Next ${route.nextStop}${route.nextEta != null ? ' · about ${route.nextEta} min' : ''}',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
