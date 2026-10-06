import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'calendar_screen.dart';
import 'new_trip_screen.dart';
import 'transport_api.dart';
import 'trip_screen.dart';

class TripGroup {
  const TripGroup(this.direction, this.label, this.trips);

  final String direction;
  final String label;
  final List<TripSummary> trips;
}

/// Pickup runs first, then drops. Order inside a group stays as the server sent it.
List<TripGroup> groupTrips(List<TripSummary> trips) {
  final buckets = <String, List<TripSummary>>{};
  final labels = <String, String>{};
  final order = <String>[];
  for (final t in trips) {
    buckets.putIfAbsent(t.direction, () {
      order.add(t.direction);
      labels[t.direction] = t.directionLabel;
      return [];
    }).add(t);
  }
  order.sort((a, b) {
    int rank(String d) => d == 'drop' ? 1 : 0;
    return rank(a).compareTo(rank(b));
  });
  return [for (final d in order) TripGroup(d, labels[d] ?? d, buckets[d]!)];
}

String tripCta(TripSummary t) => switch (t.status) {
      'running' => 'Continue trip',
      'completed' => 'Review trip',
      'cancelled' => 'Review trip',
      _ => 'Open trip',
    };

(Color, Color) tripStatusColors(String status) => switch (status) {
      'running' => (LgColors.warn, LgColors.warnBg),
      'completed' => (LgColors.ok, LgColors.okBg),
      'cancelled' => (LgColors.danger, LgColors.dangerBg),
      _ => (LgColors.muted, const Color(0xFFF3EEE8)),
    };

Future<void> openTripSummary(BuildContext context, TripSummary t, {String? date}) async {
  try {
    final api = TransportApi(context.read<ApiClient>());
    final trip = t.tripId != null
        ? await api.trip(t.tripId!)
        : await api.open(t.routeId, t.direction, date: date);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripScreen(initial: trip)));
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class TransportTodayScreen extends StatefulWidget {
  const TransportTodayScreen({this.day, this.embedded = false, super.key});

  /// When set, this is that day's runs. Null is today.
  final DateTime? day;

  /// Inside the transport desk the hub already has an app bar.
  final bool embedded;

  @override
  State<TransportTodayScreen> createState() => _TransportTodayScreenState();
}

class _TransportTodayScreenState extends State<TransportTodayScreen> {
  late final TransportApi _api = TransportApi(context.read<ApiClient>());
  List<TripSummary>? _trips;
  String? _error;
  String? _opening;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? get _date => widget.day == null ? null : ymd(widget.day!);

  bool get _isToday {
    final day = widget.day;
    if (day == null) return true;
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  Future<void> _load() async {
    try {
      final t = await _api.today(_date);
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
    final key = '${t.routeId}:${t.direction}:${t.tripId ?? 0}';
    if (_opening != null) return;
    setState(() => _opening = key);
    await openTripSummary(context, t, date: _date);
    if (mounted) {
      setState(() => _opening = null);
      await _load();
    }
  }

  Future<void> _again(TripSummary t) async {
    final key = 'again:${t.routeId}:${t.direction}';
    if (_opening != null) return;
    setState(() => _opening = key);
    try {
      final trip = await _api.create(routeId: t.routeId, direction: t.direction, date: _date);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripScreen(initial: trip)));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
    if (mounted) {
      setState(() => _opening = null);
      await _load();
    }
  }

  Future<void> _openCalendar() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TripCalendarScreen(
        onOpenDay: (day) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TransportTodayScreen(day: day)),
        ),
      ),
    ));
    if (mounted) await _load();
  }

  Future<void> _newTrip() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NewTripScreen(date: _date)),
    );
    if (created == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final trips = _trips;
    final groups = trips == null ? const <TripGroup>[] : groupTrips(trips);
    final running = trips?.where((t) => t.status == 'running').length ?? 0;
    final shown = widget.day ?? DateTime.now();
    final countLabel = trips == null
        ? ''
        : running == 0
            ? '${trips.length} ${trips.length == 1 ? 'run' : 'runs'}${_isToday ? ' today' : ''}'
            : '$running running · ${trips.length} ${_isToday ? 'today' : 'runs'}';
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(_isToday ? 'Transport' : formatShortDate(ymd(shown))),
              actions: [
                if (_isToday && widget.day == null)
                  IconButton(tooltip: 'Calendar', onPressed: _openCalendar, icon: const Icon(Icons.calendar_month_rounded)),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _opening != null ? null : _newTrip,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New trip'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            Row(
              children: [
                Expanded(child: Text(formatLongDate(shown), style: const TextStyle(color: LgColors.muted))),
                if (widget.embedded && _isToday)
                  IconButton(tooltip: 'Calendar', onPressed: _openCalendar, icon: const Icon(Icons.calendar_month_rounded)),
              ],
            ),
            if (trips != null && trips.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(countLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 12),
            if (_error != null)
              LgNotice(
                message: _error!,
                foreground: LgColors.danger,
                background: LgColors.dangerBg,
                icon: Icons.error_outline_rounded,
              ),
            if (trips == null && _error == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (trips != null && trips.isEmpty)
              const LgEmptyState(
                icon: Icons.directions_bus_rounded,
                title: 'No active routes',
                message: 'Tap New trip to build a run, or ask an admin to add a route on the website.',
              ),
            for (final g in groups) ...[
              LgSectionTitle(g.label),
              for (final t in g.trips) ...[
                TripRunCard(
                  trip: t,
                  busy: _opening == '${t.routeId}:${t.direction}:${t.tripId ?? 0}' ||
                      _opening == 'again:${t.routeId}:${t.direction}',
                  onAgain: t.canStartAnother && t.tripId != null && _opening == null ? () => _again(t) : null,
                  onTap: _opening != null ? null : () => _open(t),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class TripRunCard extends StatelessWidget {
  const TripRunCard({required this.trip, required this.onTap, this.onAgain, this.busy = false, super.key});

  final TripSummary trip;
  final VoidCallback? onTap;
  final VoidCallback? onAgain;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = trip;
    final (fg, bg) = tripStatusColors(t.status);
    final progress = t.total > 0 && t.status != 'scheduled' ? t.finished / t.total : null;
    final meta = [
      if (t.runNo > 1) 'Run ${t.runNo}',
      if (t.time != null) t.time!,
      if (t.cabName.isNotEmpty) t.cabName,
      '${t.children} ${t.children == 1 ? 'child' : 'children'}',
    ].join(' · ');
    final statusText = t.tripId != null && t.total > 0 && t.status != 'scheduled'
        ? '${t.statusLabel} ${t.finished}/${t.total}'
        : t.statusLabel;
    return Material(
      color: LgColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: t.status == 'running' ? LgColors.warn : LgColors.line, width: t.status == 'running' ? 2 : 1),
      ),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                    child: Icon(
                      t.direction == 'drop' ? Icons.home_rounded : Icons.school_rounded,
                      color: fg,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.routeName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                        ),
                        const SizedBox(height: 2),
                        Text(meta, style: const TextStyle(color: LgColors.muted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  LgStatusPill(label: statusText, foreground: fg, background: bg),
                ],
              ),
              if (progress != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0, 1),
                    minHeight: 8,
                    backgroundColor: const Color(0xFFF3EEE8),
                    color: fg,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(tripCta(t), style: const TextStyle(color: LgColors.accent, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (onAgain != null)
                    TextButton(onPressed: busy ? null : onAgain, child: const Text('Run again')),
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.chevron_right_rounded, color: LgColors.accent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
