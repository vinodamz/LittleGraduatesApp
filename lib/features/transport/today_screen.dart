import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import 'transport_api.dart';
import 'trip_screen.dart';

class TransportTodayScreen extends StatefulWidget {
  const TransportTodayScreen({super.key});

  @override
  State<TransportTodayScreen> createState() => _TransportTodayScreenState();
}

class _TransportTodayScreenState extends State<TransportTodayScreen> {
  late final TransportApi _api = TransportApi(context.read<ApiClient>());
  List<TripSummary>? _trips;
  String? _error;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await _api.today();
      if (mounted) {
        setState(() {
          _trips = t;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _open(TripSummary t) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final trip = await _api.open(t.routeId, t.direction);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripScreen(initial: trip)));
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trips = _trips;
    return Scaffold(
      appBar: AppBar(title: const Text('Today’s trips')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 24),
          children: [
            if (_error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: Colors.red))),
            if (trips == null && _error == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            if (trips != null && trips.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No active routes. An admin can add cabs and routes on the website under Transport.',
                    style: TextStyle(color: LgColors.muted)),
              ),
            for (final t in trips ?? <TripSummary>[])
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  title: Text(t.routeName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([
                    t.directionLabel,
                    if (t.time != null) t.time!,
                    if (t.cabName.isNotEmpty) t.cabName,
                    '${t.children} children',
                  ].join(' · ')),
                  trailing: _StatusChip(t),
                  onTap: _opening ? null : () => _open(t),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.t);

  final TripSummary t;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (t.status) {
      'running' => (LgColors.warnBg, LgColors.warn),
      'completed' => (const Color(0xFFE7F6E1), LgColors.ok),
      _ => (const Color(0xFFF1EEE9), LgColors.muted),
    };
    final progress = t.tripId != null && t.total > 0 && t.status != 'scheduled' ? ' ${t.finished}/${t.total}' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text('${t.statusLabel}$progress', style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
