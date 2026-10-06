import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
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

  Future<void> _act(String op, {int? stopId, int? routeId, int? studentId}) async {
    if (op == 'start' && !await _requestLocationConsent()) return;
    if (!mounted) return;
    setState(() => stopId == null ? _busy = true : _busyStop = stopId);
    try {
      final t = await _api.action(_trip.id, op, stopId: stopId, routeId: routeId, studentId: studentId);
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

  Future<void> _sos() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Send SOS?'),
        content: const Text('The school desk gets this alert, with the cab’s live location when the phone has a fix.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Send SOS')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.sos(_trip.id);
      if (mounted) _snack('SOS sent to the school desk.');
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markReached(TripStop s) async {
    await _act('reached', stopId: s.id);
    if (!mounted) return;
    final now = _trip.stops.where((x) => x.id == s.id).firstOrNull;
    if (now == null || !now.reached || now.hasLocation) return;
    final save = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Save this pickup?'),
        content: Text('${s.firstName} has no location yet. Save where the cab is now, and the route times update.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save location')),
        ],
      ),
    );
    if (save == true) await _saveLocation(s);
  }

  Future<void> _saveLocation(TripStop s) async {
    if (!await _requestLocationConsent()) return;
    if (!mounted) return;
    setState(() => _busyStop = s.id);
    try {
      final last = _tracker.lastFix;
      final fresh = last != null && DateTime.now().difference(last.timestamp).inSeconds < 90;
      final pos = fresh
          ? last
          : await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
            );
      final t = await _api.action(_trip.id, 'set_location', stopId: s.id, lat: pos.latitude, lng: pos.longitude);
      if (!mounted) return;
      setState(() => _trip = t);
      _snack('Location saved. Route times updated.');
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } on TimeoutException {
      if (mounted) _snack('No GPS fix yet. Step outside and try again.');
    } on LocationServiceDisabledException {
      if (mounted) _snack('Turn on Location in the phone settings, then try again.');
    } on PermissionDeniedException {
      if (mounted) _snack('Location permission is needed to save this stop.');
    } finally {
      if (mounted) setState(() => _busyStop = null);
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

  bool get _editable => _trip.scheduled || _trip.running;

  Future<void> _changeRoute() async {
    List<RouteOption> routes;
    try {
      routes = (await _api.routes()).where((r) => r.runs(_trip.direction) && r.id != _trip.routeId).toList();
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
      return;
    }
    if (!mounted) return;
    if (routes.isEmpty) {
      _snack('No other route runs this way.');
      return;
    }
    final picked = await showModalBottomSheet<RouteOption>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Change route', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Children already marked stay. Everyone still waiting comes from the route you pick.',
                style: TextStyle(color: LgColors.muted),
              ),
            ),
            for (final r in routes)
              ListTile(
                title: Text(r.name),
                subtitle: Text('${r.children} ${r.children == 1 ? 'child' : 'children'}'),
                onTap: () => Navigator.pop(c, r),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (!await _confirm('Use ${picked.name} for the rest of this trip?')) return;
    await _act('set_route', routeId: picked.id);
  }

  Future<void> _addChild() async {
    final picked = await showModalBottomSheet<ChildOption>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _ChildPicker(api: _api),
    );
    if (picked == null || !mounted) return;
    await _act('add', studentId: picked.id);
  }

  Widget _stopCard(int i, int? nextId) {
    final s = _trip.stops[i];
    final prev = i > 0 ? _trip.stops[i - 1] : null;
    final nextStop = i + 1 < _trip.stops.length ? _trip.stops[i + 1] : null;
    return _StopCard(
      stop: s,
      trip: _trip,
      next: s.id == nextId,
      busy: _busyStop == s.id,
      canUp: _editable && s.pending && prev != null && (_trip.scheduled || prev.pending),
      canDown: _editable && s.pending && nextStop != null && (_trip.scheduled || nextStop.pending),
      onAction: (op) => op == 'reached' && !s.hasLocation ? _markReached(s) : _act(op, stopId: s.id),
      onWhatsApp: (kind, p) => _whatsApp(s, kind, p),
      onSetLocation: () => _saveLocation(s),
      onRemove: !_editable || !s.pending
          ? null
          : () async {
              if (await _confirm('Take ${s.firstName} off this trip?')) await _act('remove', stopId: s.id);
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tracker = context.watch<LocationTracker>();
    final dueCount = _trip.stops.where((s) => s.etaAlertDue && s.parents.isNotEmpty).length;
    final nextId = _trip.stops.where((s) => s.pending).map((s) => s.id).firstOrNull;
    final done = _trip.stops.where((s) => !s.pending).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(_trip.runNo > 1 ? '${_trip.routeName} · Run ${_trip.runNo}' : _trip.routeName),
        actions: [
          if (_editable)
            PopupMenuButton<String>(
              onSelected: (op) {
                if (op == 'route') _changeRoute();
                if (op == 'add') _addChild();
              },
              itemBuilder: (c) => const [
                PopupMenuItem(value: 'route', child: Text('Change route')),
                PopupMenuItem(value: 'add', child: Text('Add a child')),
              ],
            ),
        ],
      ),
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
            if (_trip.running) ...[
              const SizedBox(height: 12),
              _RideStats(trip: _trip),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _sos,
                  style: OutlinedButton.styleFrom(foregroundColor: LgColors.danger),
                  icon: const Icon(Icons.sos_rounded),
                  label: const Text('SOS — alert the school'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _TrackingBanner(trip: _trip, tracker: tracker, onRetry: _startTracking),
            if (_editable) ...[
              const SizedBox(height: 8),
              const Text(
                'Change the route or add a child from the menu. Move a waiting child with the arrows, or mark them absent.',
                style: TextStyle(color: LgColors.muted, height: 1.4),
              ),
            ],
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
            for (var i = 0; i < _trip.stops.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _stopCard(i, nextId),
              ),
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

class _RideStats extends StatelessWidget {
  const _RideStats({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final aboard = trip.direction == 'drop' ? trip.pendingCount : trip.stops.where((s) => s.status == 'done').length;
    final done = trip.stops.where((s) => !s.pending).length;
    final next = trip.stops.where((s) => s.pending && s.etaMinutes != null).map((s) => s.etaMinutes!).firstOrNull;
    final started = trip.startedAt;
    final minutes = started == null ? null : DateTime.now().difference(started).inMinutes;
    final gps = trip.lastLocationAt != null && DateTime.now().difference(trip.lastLocationAt!).inSeconds < 180;
    final cells = [
      ('$aboard', 'Aboard'),
      ('$done/${trip.stops.length}', 'Stops'),
      (next == null ? '—' : '$next min', 'Next'),
      (minutes == null ? '—' : '$minutes min', 'On road'),
      (gps ? 'On' : 'Waiting', 'GPS'),
    ];
    return Row(
      children: [
        for (final c in cells)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: LgColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: LgColors.line),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Column(
                    children: [
                      Text(c.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(c.$2, style: const TextStyle(color: LgColors.muted, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
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
    required this.canUp,
    required this.canDown,
    required this.onAction,
    required this.onWhatsApp,
    required this.onSetLocation,
    required this.onRemove,
  });

  final TripStop stop;
  final Trip trip;
  final bool next;
  final bool busy;
  final bool canUp;
  final bool canDown;
  final void Function(String op) onAction;
  final void Function(String kind, StopParent p) onWhatsApp;
  final VoidCallback onSetLocation;
  final VoidCallback? onRemove;

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
            if ((trip.scheduled || trip.running) && s.pending) ...[
              Row(
                children: [
                  IconButton(
                    tooltip: 'Earlier',
                    onPressed: busy || !canUp ? null : () => onAction('up'),
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                  IconButton(
                    tooltip: 'Later',
                    onPressed: busy || !canDown ? null : () => onAction('down'),
                    icon: const Icon(Icons.arrow_downward_rounded),
                  ),
                  const Spacer(),
                  if (onRemove != null)
                    TextButton(onPressed: busy ? null : onRemove, child: const Text('Remove')),
                ],
              ),
            ],
            if (trip.running && s.pending) ...[
              const SizedBox(height: 12),
              if (!s.hasLocation)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'No location saved. Reach the stop, then save where you are so the route times update.',
                    style: TextStyle(color: LgColors.muted, fontSize: 13, height: 1.3),
                  ),
                ),
              if (!s.hasLocation && s.reached) ...[
                FilledButton.icon(
                  onPressed: busy ? null : onSetLocation,
                  icon: const Icon(Icons.my_location_rounded),
                  label: const Text('Save location here'),
                ),
                const SizedBox(height: 8),
              ],
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
              if (s.parents.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: due || (s.reached && !s.reachedAlertSent)
                      ? FilledButton(onPressed: busy ? null : () => _openMore(context), child: const Text('More'))
                      : TextButton(onPressed: busy ? null : () => _openMore(context), child: const Text('More')),
                ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!s.hasLocation && s.reached)
                      FilledButton.icon(
                        onPressed: busy ? null : onSetLocation,
                        icon: const Icon(Icons.my_location_rounded),
                        label: const Text('Save location here'),
                      ),
                    TextButton(
                      onPressed: busy ? null : () => onAction('undo'),
                      child: const Text('Undo'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openMore(BuildContext context) {
    final s = stop;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Message family', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              const SizedBox(height: 12),
              if (s.parents.isEmpty)
                const Text('No parent phone on file.', style: TextStyle(color: LgColors.muted))
              else
                for (final p in s.parents) ...[
                  if (!s.reached) ...[
                    _waButton('${_parentLabel(p)}: 5 min away', highlight: s.etaAlertDue, onTap: () {
                      Navigator.pop(c);
                      onWhatsApp('eta', p);
                    }),
                    const SizedBox(height: 8),
                  ],
                  _waButton(
                    '${_parentLabel(p)}: cab reached',
                    highlight: s.reached && !s.reachedAlertSent,
                    onTap: () {
                      Navigator.pop(c);
                      onWhatsApp('reached', p);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
            ],
          ),
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

class _ChildPicker extends StatefulWidget {
  const _ChildPicker({required this.api});

  final TransportApi api;

  @override
  State<_ChildPicker> createState() => _ChildPickerState();
}

class _ChildPickerState extends State<_ChildPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<ChildOption> _children = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () => _load(_search.text));
    });
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    try {
      final children = await widget.api.children(q);
      if (mounted) {
        setState(() {
          _children = children;
          _loading = false;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.75;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Add a child', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search by name',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: LgColors.danger)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      for (final c in _children)
                        ListTile(
                          title: Text(c.name),
                          subtitle: c.grade.isEmpty ? null : Text(c.grade),
                          onTap: () => Navigator.pop(context, c),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
