import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/module_registry.dart';
import '../../core/nav.dart';
import '../../core/privacy.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../staff/staff_api.dart';
import '../staff/staff_screen.dart';
import '../transport/location_tracker.dart';
import '../transport/today_screen.dart';
import '../transport/transport_api.dart';
import '../transport/trip_screen.dart';

/// The signed-in landing tab: greeting, a live trip, attendance, and the
/// next runs. Other modules live under More.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  List<TripSummary>? _trips;
  StaffDay? _staff;
  bool _staffBusy = false;
  String? _tripError;

  bool get _hasTransport => context.read<Session>().modules.any((m) => m.key == 'transport');
  bool get _hasStaff => context.read<Session>().modules.any((m) => m.key == 'staff');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = context.read<Session>();
    try {
      await session.refresh();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
    if (!mounted) return;
    await Future.wait([
      if (_hasTransport) _loadTrips(),
      if (_hasStaff) _loadStaff(),
    ]);
  }

  Future<void> _loadTrips() async {
    try {
      final trips = await TransportApi(context.read<ApiClient>()).today();
      if (mounted) {
        setState(() {
          _trips = trips;
          _tripError = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _tripError = e.message);
    }
  }

  Future<void> _loadStaff() async {
    try {
      final day = await StaffApi(context.read<ApiClient>()).today();
      if (mounted) setState(() => _staff = day);
    } on ApiException {
      // Today still works if staff records are unavailable.
    }
  }

  Future<void> _check(String op) async {
    if (_staffBusy) return;
    setState(() => _staffBusy = true);
    try {
      final day = await StaffApi(context.read<ApiClient>()).check(op);
      if (!mounted) return;
      setState(() => _staff = day);
      final at = op == 'self_in' ? day.attendance.checkIn : day.attendance.checkOut;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(op == 'self_in' ? 'Checked in at $at.' : 'Checked out at $at.')),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _staffBusy = false);
    }
  }

  Future<void> _openRunningTrip() async {
    final id = context.read<LocationTracker>().tripId;
    if (id == null) {
      LgNav.maybeOf(context)?.go('transport');
      return;
    }
    try {
      final trip = await TransportApi(context.read<ApiClient>()).trip(id);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripScreen(initial: trip)));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final tracker = context.watch<LocationTracker>();
    final user = session.user;
    final now = DateTime.now();
    final upcoming = [
      for (final t in _trips ?? const <TripSummary>[])
        if (t.status != 'completed' && t.status != 'cancelled') t,
    ];
    final others = [
      for (final m in session.modules)
        if (m.key != 'transport' && m.key != 'staff') m,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(session.school)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Text(
              user == null ? greetingFor(now) : '${greetingFor(now)}, ${firstName(user.name)}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(formatLongDate(now), style: const TextStyle(color: LgColors.muted)),
            const SizedBox(height: 16),
            if (tracker.active) ...[
              _LiveTripBanner(routeName: tracker.routeName, onOpen: _openRunningTrip),
              const SizedBox(height: 16),
            ],
            if (_hasStaff && _staff != null) ...[
              StaffAttendanceCard(
                day: _staff!,
                busy: _staffBusy,
                onCheckIn: () => _check('self_in'),
                onCheckOut: () => _check('self_out'),
                onOpen: () => LgNav.maybeOf(context)?.go('staff'),
              ),
              const SizedBox(height: 20),
            ],
            if (_hasTransport) ...[
              LgSectionTitle(
                'Transport',
                trailing: TextButton(
                  onPressed: () => LgNav.maybeOf(context)?.go('transport'),
                  child: const Text('All trips'),
                ),
              ),
              if (_tripError != null)
                LgNotice(
                  message: _tripError!,
                  foreground: LgColors.danger,
                  background: LgColors.dangerBg,
                  icon: Icons.error_outline_rounded,
                )
              else if (_trips == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (upcoming.isEmpty)
                LgEmptyState(
                  icon: Icons.directions_bus_rounded,
                  title: _trips!.isEmpty ? 'No trips today' : 'Trips are finished',
                  message: _trips!.isEmpty
                      ? 'An admin can add cabs and routes on the website under Transport.'
                      : 'Open Transport if you need to review a finished run.',
                )
              else
                for (final t in upcoming.take(3)) ...[
                  TripRunCard(trip: t, onTap: () => openTripSummary(context, t)),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 8),
            ],
            if (others.isNotEmpty) ...[
              const LgSectionTitle('Also on your desk'),
              for (final m in others) ...[
                ModuleRow(module: m),
                const SizedBox(height: 8),
              ],
            ],
            if (session.modules.isEmpty)
              const LgEmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Nothing is turned on yet',
                message: 'Ask the school admin to give this login its modules.',
              ),
          ],
        ),
      ),
    );
  }
}

class _LiveTripBanner extends StatelessWidget {
  const _LiveTripBanner({required this.routeName, required this.onOpen});

  final String routeName;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LgColors.warnBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFF0C8A8)),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.my_location_rounded, color: LgColors.warn),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Trip running', style: TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      routeName.isEmpty ? 'Sharing the cab location' : '$routeName · sharing location',
                      style: const TextStyle(color: LgColors.warn),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: LgColors.warn),
            ],
          ),
        ),
      ),
    );
  }
}

class ModuleRow extends StatelessWidget {
  const ModuleRow({required this.module, super.key});

  final AppModule module;

  @override
  Widget build(BuildContext context) {
    final inApp = moduleOpensInApp(module);
    return Material(
      color: LgColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: LgColors.line),
      ),
      child: InkWell(
        onTap: () => openModule(context, module),
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(color: LgColors.accentSoft, shape: BoxShape.circle),
                  child: Icon(moduleIcons[module.key] ?? Icons.apps_rounded, color: LgColors.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(module.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(
                        inApp ? 'Opens in the app' : 'Opens the website',
                        style: const TextStyle(color: LgColors.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(
                  inApp ? Icons.chevron_right_rounded : Icons.open_in_new_rounded,
                  color: LgColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final modules = [
      for (final m in session.modules)
        if (m.key != 'transport' && m.key != 'staff') m,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (session.user != null) ...[
            Row(
              children: [
                LgAvatar(name: session.user!.name, radius: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.user!.name, style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        session.user!.isAdmin ? 'Admin' : 'Staff',
                        style: const TextStyle(color: LgColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          if (modules.isEmpty)
            const LgEmptyState(
              icon: Icons.grid_view_rounded,
              title: 'Transport and Staff are in the tabs',
              message: 'Other school tools show up here when your login has them.',
            )
          else
            for (final m in modules) ...[
              ModuleRow(module: m),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => openPrivacyPolicy(context),
            icon: const Icon(Icons.privacy_tip_outlined),
            label: const Text('Privacy policy'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Sign out?'),
                  content: const Text('This phone will stop sharing a trip location, if one is running.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Stay signed in')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sign out')),
                  ],
                ),
              );
              if (ok != true || !context.mounted) return;
              await context.read<LocationTracker>().stop();
              if (context.mounted) await context.read<Session>().signOut();
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
