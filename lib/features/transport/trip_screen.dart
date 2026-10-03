import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/notifications.dart';
import '../../core/privacy.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
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
  bool _locationConsent = false;

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

  Future<bool> _requestLocationConsent() async {
    if (_locationConsent || _tracker.tripId == _trip.id) return true;
    if (!mounted) return false;
    final accepted = await requestTripLocationConsent(context);
    if (!mounted) return false;
    _locationConsent = accepted;
    return accepted;
  }

  Future<void> _startTracking() async {
    if (!await _requestLocationConsent()) return;
    final err = await _tracker.start(_trip.id, _trip.routeName);
    if (err != null && mounted) _snack(err);
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _act(String op, {int? stopId}) async {
    if (op == 'start' && !await _requestLocationConsent()) return;
    if (!mounted) return;
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
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
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
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Yes'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _finish() async {
    final n = _trip.pendingCount;
    if (n == 0 || await _confirm('$n ${n == 1 ? 'child is' : 'children are'} not marked yet. Finish anyway?')) {
      await _act('finish');
    }
  }

  Future<void> _cancel() async {
    if (await _confirm('Cancel this trip for today?')) await _act('cancel');
  }

  @override
  Widget build(BuildContext context) {
    final tracker = context.watch<LocationTracker>();
    final dueCount = _trip.stops.where((s) => s.etaAlertDue && s.parents.isNotEmpty).length;
    final nextId = _trip.stops.where((s) => s.pending).map((s) => s.id).firstOrNull;
    final done = _trip.stops.where((s) => !s.pending).length;
    return Scaffold(
      appBar: AppBar(title: Text(_trip.routeName)),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              [
                _trip.directionLabel,
                if (_trip.cabName.isNotEmpty) _trip.cabName,
                if (_trip.vehicleNo.isNotEmpty) _trip.vehicleNo,
              ].join(' · '),
              style: const TextStyle(color: LgColors.muted),
            ),
            const SizedBox(height: 12),
            _ProgressCard(trip: _trip, done: done),
            const SizedBox(height: 12),
            _TrackingBanner(trip: _trip, tracker: tracker, onRetry: _startTracking),
            if (_trip.scheduled) ...[
              const SizedBox(height: 12),
              Text(
                '${_trip.stops.length} ${_trip.stops.length == 1 ? 'child' : 'children'} in this order. Start when the cab leaves.',
                style: const TextStyle(height: 1.4),
              ),
            ],
            if (_trip.running && dueCount > 0) ...[
              const SizedBox(height: 12),
              LgNotice(
                message: dueCount == 1
                    ? 'A family is about 5 minutes away. Send the highlighted WhatsApp message.'
                    : '$dueCount families are about 5 minutes away. Send the highlighted WhatsApp messages.',
                foreground: LgColors.warn,
                background: LgColors.warnBg,
                icon: Icons.schedule_rounded,
              ),
            ],
            const SizedBox(height: 8),
            for (final s in _trip.stops) ...[
              const SizedBox(height: 10),
              _StopCard(
                stop: s,
                trip: _trip,
                next: s.id == nextId,
                busy: _busyStop == s.id,
                onAction: (op) => _act(op, stopId: s.id),
                onWhatsApp: (kind, p) => _whatsApp(s, kind, p),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _trip.running || _trip.scheduled
          ? _TripActions(
              trip: _trip,
              busy: _busy,
              onStart: () => _act('start'),
              onFinish: _finish,
              onCancel: _cancel,
            )
          : null,
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.trip, required this.done});

  final Trip trip;
  final int done;

  @override
  Widget build(BuildContext context) {
    final total = trip.stops.length;
    final value = total == 0 ? 0.0 : done / total;
    final verb = trip.direction == 'drop' ? 'dropped' : 'picked up';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              total == 0 ? 'No children on this run' : '$done of $total $verb',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: const Color(0xFFF3EEE8),
                color: trip.running ? LgColors.warn : LgColors.ok,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripActions extends StatelessWidget {
  const _TripActions({
    required this.trip,
    required this.busy,
    required this.onStart,
    required this.onFinish,
    required this.onCancel,
  });

  final Trip trip;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onFinish;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: LgColors.surface,
        border: Border(top: BorderSide(color: LgColors.line)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (trip.scheduled)
                FilledButton.icon(
                  onPressed: busy || trip.stops.isEmpty ? null : onStart,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start trip'),
                ),
              if (trip.running)
                FilledButton(
                  onPressed: busy ? null : onFinish,
                  child: const Text('Finish trip'),
                ),
              TextButton(
                onPressed: busy ? null : onCancel,
                child: const Text('Cancel trip'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackingBanner extends StatelessWidget {
  const _TrackingBanner({
    required this.trip,
    required this.tracker,
    required this.onRetry,
  });

  final Trip trip;
  final LocationTracker tracker;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (!trip.running) return const SizedBox.shrink();
    final mine = tracker.tripId == trip.id;
    final String text;
    final Color color;
    final Color background;
    final IconData icon;
    if (!mine) {
      text = tracker.problem ?? 'Location is not being shared from this phone.';
      color = LgColors.danger;
      background = LgColors.dangerBg;
      icon = Icons.location_off_rounded;
    } else if (tracker.problem != null) {
      text = tracker.problem!;
      color = LgColors.warn;
      background = LgColors.warnBg;
      icon = Icons.my_location_rounded;
    } else if (tracker.lastUploadAt != null) {
      final t = TimeOfDay.fromDateTime(tracker.lastUploadAt!).format(context);
      text = 'Sharing cab location · last sent $t';
      color = LgColors.ok;
      background = LgColors.okBg;
      icon = Icons.my_location_rounded;
    } else {
      text = 'Finding location…';
      color = LgColors.muted;
      background = const Color(0xFFF3EEE8);
      icon = Icons.my_location_rounded;
    }
    return Column(
      children: [
        LgNotice(message: text, foreground: color, background: background, icon: icon),
        if (!mine) ...[
          const SizedBox(height: 8),
          FilledButton(onPressed: onRetry, child: const Text('Share location')),
        ],
        if (mine && !tracker.alwaysAllowed) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: tracker.openLocationSettings,
            child: const Text('Allow location all the time'),
          ),
          const SizedBox(height: 4),
          const Text(
            'That keeps the cab on the map when the screen is off.',
            style: TextStyle(color: LgColors.muted, fontSize: 13),
          ),
        ],
      ],
    );
  }
}

class _StopCard extends StatelessWidget {
  const _StopCard({
    required this.stop,
    required this.trip,
    required this.next,
    required this.busy,
    required this.onAction,
    required this.onWhatsApp,
  });

  final TripStop stop;
  final Trip trip;
  final bool next;
  final bool busy;
  final void Function(String op) onAction;
  final void Function(String kind, StopParent p) onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final s = stop;
    final due = s.etaAlertDue && s.parents.isNotEmpty;
    final border = due || next ? LgColors.warn : LgColors.line;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border, width: due || next ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                      if (next)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 4),
                          child: Text('Next stop', style: TextStyle(color: LgColors.warn, fontWeight: FontWeight.w700, fontSize: 12)),
                        ),
                      Text(
                        '${s.order}. ${s.name}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: s.pending ? LgColors.ink : LgColors.muted,
                        ),
                      ),
                      Text(
                        [s.grade, if (s.note.isNotEmpty) s.note].where((part) => part.isNotEmpty).join(' · '),
                        style: const TextStyle(color: LgColors.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                _stateChip(context),
              ],
            ),
            if (trip.running && s.pending) ...[
              const SizedBox(height: 12),
              if (!s.reached)
                OutlinedButton(
                  onPressed: busy ? null : () => onAction('reached'),
                  child: const Text('Reached stop'),
                ),
              if (!s.reached) const SizedBox(height: 8),
              FilledButton(
                onPressed: busy ? null : () => onAction('done'),
                child: Text(trip.doneVerb),
              ),
              TextButton(
                onPressed: busy ? null : () => onAction('absent'),
                child: const Text('Mark absent'),
              ),
              if (s.parents.isEmpty)
                const Text('No parent phone on file.', style: TextStyle(color: LgColors.muted, fontSize: 13))
              else ...[
                const Text('Message family', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final p in s.parents) ...[
                  if (!s.reached) ...[
                    _waButton('${_parentLabel(p)}: 5 min away', highlight: due, onTap: () => onWhatsApp('eta', p)),
                    const SizedBox(height: 8),
                  ],
                  _waButton(
                    '${_parentLabel(p)}: cab reached',
                    highlight: s.reached && !s.reachedAlertSent,
                    onTap: () => onWhatsApp('reached', p),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              if (s.etaAlertSent || s.reachedAlertSent)
                Text(
                  [
                    if (s.etaAlertSent) '5-min alert opened',
                    if (s.reachedAlertSent) 'Reached alert opened',
                  ].join(' · '),
                  style: const TextStyle(color: LgColors.muted, fontSize: 12),
                ),
            ] else if (trip.running)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: busy ? null : () => onAction('undo'),
                  child: const Text('Undo'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _parentLabel(StopParent p) {
    final label = p.label.isEmpty ? p.name : p.label;
    if (label.isEmpty) return 'Parent';
    return label[0].toUpperCase() + label.substring(1);
  }

  Widget _waButton(
    String label, {
    required bool highlight,
    required VoidCallback onTap,
  }) {
    final icon = const Icon(Icons.chat_rounded, size: 20);
    final button = highlight
        ? FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF128C7E), foregroundColor: Colors.white),
            onPressed: onTap,
            icon: icon,
            label: Text(label),
          )
        : OutlinedButton.icon(onPressed: onTap, icon: icon, label: Text(label));
    return SizedBox(width: double.infinity, child: button);
  }

  Widget _stateChip(BuildContext context) {
    final s = stop;
    String? text;
    var color = LgColors.muted;
    if (s.status == 'done' && s.doneAt != null) {
      text =
          '${trip.doneVerb} ${TimeOfDay.fromDateTime(s.doneAt!).format(context)}';
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
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
