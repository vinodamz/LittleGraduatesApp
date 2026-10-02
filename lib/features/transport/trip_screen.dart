import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/notifications.dart';
import '../../core/theme.dart';
import 'location_tracker.dart';
import 'transport_api.dart';

class TripScreen extends StatefulWidget {
  const TripScreen({super.key, required this.initial});

  final Trip initial;

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  late Trip _trip = widget.initial;
  late final TransportApi _api = TransportApi(context.read<ApiClient>());
  late final LocationTracker _tracker = context.read<LocationTracker>();
  Timer? _timer;
  StreamSubscription<String>? _taps;
  String? _lastSignature;
  int? _busyStop;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(AppConfig.tripRefreshInterval, (_) => _reload());
    _taps = Notifications.taps.listen((_) => _reload());
    _tracker.addListener(_onTracker);
    if (_trip.running && _tracker.tripId != _trip.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startTracking());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _taps?.cancel();
    _tracker.removeListener(_onTracker);
    super.dispose();
  }

  void _onTracker() {
    final sig = _tracker.serverSignature;
    if (sig != null && sig != _lastSignature && sig != _trip.signature) {
      _lastSignature = sig;
      _reload();
    }
  }

  Future<void> _reload() async {
    try {
      final t = await _api.trip(_trip.id);
      if (mounted) setState(() => _trip = t);
      if (!t.running && _tracker.tripId == t.id) await _tracker.stop();
    } on ApiException {
      // Keep showing the last state; the next refresh retries.
    }
  }

  Future<void> _startTracking() async {
    final err = await _tracker.start(_trip.id, _trip.routeName);
    if (err != null && mounted) _snack(err);
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _act(String op, {int? stopId}) async {
    setState(() => stopId == null ? _busy = true : _busyStop = stopId);
    try {
      final t = await _api.action(_trip.id, op, stopId: stopId);
      if (!mounted) return;
      setState(() => _trip = t);
      if (op == 'start') await _startTracking();
      if (!t.running) await _tracker.stop();
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyStop = null;
        });
      }
    }
  }

  Future<void> _whatsApp(TripStop s, String kind, StopParent p) async {
    try {
      final url = await _api.alertUrl(s.id, kind, p.id);
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) _snack('WhatsApp is not installed on this phone.');
      unawaited(_reload());
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    }
  }

  Future<bool> _confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yes')),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final tracker = context.watch<LocationTracker>();
    final dueCount = _trip.stops.where((s) => s.etaAlertDue && s.parents.isNotEmpty).length;
    return Scaffold(
      appBar: AppBar(title: Text(_trip.routeName)),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                [_trip.directionLabel, if (_trip.cabName.isNotEmpty) _trip.cabName, if (_trip.vehicleNo.isNotEmpty) _trip.vehicleNo]
                    .join(' · '),
                style: const TextStyle(color: LgColors.muted),
              ),
            ),
            _TrackingBanner(trip: _trip, tracker: tracker, onRetry: _startTracking),
            if (_trip.scheduled)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('${_trip.stops.length} children in this order. Start when the cab leaves.'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _busy || _trip.stops.isEmpty ? null : () => _act('start'),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Start trip'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_trip.running && dueCount > 0)
              Card(
                color: LgColors.warnBg,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    '${dueCount == 1 ? 'A family is' : '$dueCount families are'} about 5 minutes away — '
                    'tap the highlighted WhatsApp button.',
                    style: const TextStyle(color: LgColors.warn),
                  ),
                ),
              ),
            for (final s in _trip.stops)
              _StopCard(
                stop: s,
                trip: _trip,
                busy: _busyStop == s.id,
                onAction: (op) => _act(op, stopId: s.id),
                onWhatsApp: (kind, p) => _whatsApp(s, kind, p),
              ),
            if (_trip.running || _trip.scheduled)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    if (_trip.running)
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  final n = _trip.pendingCount;
                                  if (n == 0 || await _confirm('$n children are not marked yet. Finish anyway?')) {
                                    await _act('finish');
                                  }
                                },
                          child: const Text('Finish trip'),
                        ),
                      ),
                    if (_trip.running) const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                if (await _confirm('Cancel this trip for today?')) await _act('cancel');
                              },
                        child: const Text('Cancel trip'),
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

class _TrackingBanner extends StatelessWidget {
  const _TrackingBanner({required this.trip, required this.tracker, required this.onRetry});

  final Trip trip;
  final LocationTracker tracker;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (!trip.running) return const SizedBox.shrink();
    final mine = tracker.tripId == trip.id;
    final String text;
    final Color color;
    if (!mine) {
      text = tracker.problem ?? 'Location is not being shared from this phone.';
      color = Colors.red;
    } else if (tracker.problem != null) {
      text = tracker.problem!;
      color = LgColors.warn;
    } else if (tracker.lastUploadAt != null) {
      final t = TimeOfDay.fromDateTime(tracker.lastUploadAt!).format(context);
      text = 'Sharing cab location · last sent $t';
      color = LgColors.ok;
    } else {
      text = 'Finding location…';
      color = LgColors.muted;
    }
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(mine ? Icons.my_location : Icons.location_disabled, color: color),
            title: Text(text, style: TextStyle(color: color, fontSize: 14)),
            trailing: mine ? null : TextButton(onPressed: onRetry, child: const Text('Share')),
          ),
          if (mine && !tracker.alwaysAllowed)
            ListTile(
              dense: true,
              title: const Text('For screen-off tracking, set Location to “Allow all the time”.',
                  style: TextStyle(fontSize: 13, color: LgColors.muted)),
              trailing: TextButton(onPressed: tracker.openLocationSettings, child: const Text('Settings')),
            ),
        ],
      ),
    );
  }
}

class _StopCard extends StatelessWidget {
  const _StopCard({
    required this.stop,
    required this.trip,
    required this.busy,
    required this.onAction,
    required this.onWhatsApp,
  });

  final TripStop stop;
  final Trip trip;
  final bool busy;
  final void Function(String op) onAction;
  final void Function(String kind, StopParent p) onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final s = stop;
    final due = s.etaAlertDue && s.parents.isNotEmpty;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: due ? LgColors.warn : LgColors.line, width: due ? 2 : 1),
      ),
      child: Opacity(
        opacity: s.pending ? 1 : 0.7,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${s.order}. ${s.name}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        Text([s.grade, if (s.note.isNotEmpty) s.note].join(' · '),
                            style: const TextStyle(color: LgColors.muted, fontSize: 13)),
                      ],
                    ),
                  ),
                  _stateChip(context),
                ],
              ),
              if (trip.running && s.pending) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!s.reached)
                      OutlinedButton(onPressed: busy ? null : () => onAction('reached'), child: const Text('Reached stop')),
                    FilledButton(onPressed: busy ? null : () => onAction('done'), child: Text(trip.doneVerb)),
                    OutlinedButton(onPressed: busy ? null : () => onAction('absent'), child: const Text('Absent')),
                  ],
                ),
                const SizedBox(height: 8),
                if (s.parents.isEmpty)
                  const Text('No parent phone on file.', style: TextStyle(color: LgColors.muted, fontSize: 13))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in s.parents) ...[
                        if (!s.reached)
                          _waButton('${p.label}: 5 min', highlight: due, onTap: () => onWhatsApp('eta', p)),
                        _waButton('${p.label}: cab reached',
                            highlight: s.reached && !s.reachedAlertSent, onTap: () => onWhatsApp('reached', p)),
                      ],
                    ],
                  ),
                if (s.etaAlertSent || s.reachedAlertSent)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      [if (s.etaAlertSent) '5-min alert opened', if (s.reachedAlertSent) 'reached alert opened'].join(' · '),
                      style: const TextStyle(color: LgColors.muted, fontSize: 12),
                    ),
                  ),
              ] else if (trip.running)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: busy ? null : () => onAction('undo'), child: const Text('Undo')),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _waButton(String label, {required bool highlight, required VoidCallback onTap}) {
    final icon = const Icon(Icons.chat_rounded, size: 18);
    return highlight
        ? FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
            onPressed: onTap,
            icon: icon,
            label: Text(label),
          )
        : OutlinedButton.icon(onPressed: onTap, icon: icon, label: Text(label));
  }

  Widget _stateChip(BuildContext context) {
    final s = stop;
    String? text;
    var color = LgColors.muted;
    if (s.status == 'done' && s.doneAt != null) {
      text = '${trip.doneVerb} ${TimeOfDay.fromDateTime(s.doneAt!).format(context)}';
      color = LgColors.ok;
    } else if (s.status == 'absent') {
      text = 'Absent';
    } else if (s.reached) {
      text = 'At stop';
      color = LgColors.warn;
    } else if (s.etaMinutes != null) {
      text = '~${s.etaMinutes} min';
    }
    if (text == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
