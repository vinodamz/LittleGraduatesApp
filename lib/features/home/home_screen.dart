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
import '../materials/materials_controller.dart';
import '../staff/staff_api.dart';
import '../staff/staff_screen.dart';
import '../transport/location_tracker.dart';
import '../transport/today_screen.dart';
import '../transport/transport_api.dart';
import '../transport/trip_screen.dart';

/// The signed-in landing tab: greeting, a live trip, attendance, and the
/// next runs. Other modules live under More.
class TodayScreen extends StatefulWidget {
  const TodayScreen({this.active = true, super.key});

  final bool active;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  List<TripSummary>? _trips;
  StaffDay? _staff;
  bool _staffBusy = false;
  String? _tripError;
  String? _staffError;

  bool get _hasTransport =>
      context.read<Session>().modules.any((m) => m.key == 'transport');
  bool get _hasStaff =>
      context.read<Session>().modules.any((m) => m.key == 'staff');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TodayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load();
  }

  Future<void> _load() async {
    final session = context.read<Session>();
    try {
      await session.refresh();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
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
      if (mounted) {
        setState(() {
          _staff = day;
          _staffError = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _staffError = e.message);
    }
  }

  Future<void> _check(String op) async {
    if (_staffBusy) return;
    setState(() => _staffBusy = true);
    try {
      final day = await StaffApi(context.read<ApiClient>()).check(op);
      if (!mounted) return;
      setState(() => _staff = day);
      final at = op == 'self_in'
          ? day.attendance.checkIn
          : day.attendance.checkOut;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            op == 'self_in' ? 'Checked in at $at.' : 'Checked out at $at.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
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
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => TripScreen(initial: trip)));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final tracker = context.watch<LocationTracker>();
    final materials = context.watch<MaterialsController>();
    final materialsPending = materials.pendingCount;
    final user = session.user;
    final now = DateTime.now();
    final upcoming = [
      for (final t in _trips ?? const <TripSummary>[])
        if (t.status != 'completed' && t.status != 'cancelled') t,
    ];
    final others = [
      for (final m in session.modules)
        if (m.key != 'transport' && m.key != 'staff' && m.key != 'materials') m,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.school_outlined, color: LgColors.accent),
            const SizedBox(width: 10),
            Flexible(child: Text(session.school)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'School tools and account',
            onPressed: () => LgNav.maybeOf(context)?.go('more'),
            icon: LgAvatar(name: user?.name ?? 'LG', radius: 18),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: LgColors.ink,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatLongDate(now),
                    style: const TextStyle(color: Color(0xFFE2DBE8)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user == null
                        ? greetingFor(now)
                        : '${greetingFor(now)}, ${firstName(user.name)}',
                    style: Theme.of(
                      context,
                    ).textTheme.headlineMedium?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your attendance, school checks, and trips in one place.',
                    style: TextStyle(color: Color(0xFFE2DBE8), height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (tracker.active) ...[
              _LiveTripBanner(
                routeName: tracker.routeName,
                onOpen: _openRunningTrip,
              ),
              const SizedBox(height: 16),
            ],
            if (session.modules.any((m) => m.key == 'materials'))
              _MaterialsUploadBanner(pending: materialsPending),
            if (session.modules.isNotEmpty) ...[
              const LgSectionTitle('Your day at a glance'),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      MediaQuery.textScalerOf(context).scale(16) > 24 &&
                          constraints.maxWidth < 600
                      ? 2
                      : 3;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (_hasTransport)
                        SizedBox(
                          width: width,
                          child: _OverviewTile(
                            icon: Icons.directions_bus_outlined,
                            value: _tripError != null
                                ? 'Unavailable'
                                : _trips == null
                                ? 'Loading…'
                                : '${upcoming.length}',
                            label: 'Trips ahead',
                            onTap: () =>
                                LgNav.maybeOf(context)?.go('transport'),
                          ),
                        ),
                      if (_hasStaff)
                        SizedBox(
                          width: width,
                          child: _OverviewTile(
                            icon: Icons.badge_outlined,
                            value: _staffError != null
                                ? 'Unavailable'
                                : _staff == null
                                ? 'Loading…'
                                : _staff!.attendance.checkedOut
                                ? 'Done'
                                : _staff!.attendance.checkedIn
                                ? 'Present'
                                : 'Not in',
                            label: 'Attendance',
                            onTap: () => LgNav.maybeOf(context)?.go('staff'),
                          ),
                        ),
                      if (session.modules.any((m) => m.key == 'materials'))
                        SizedBox(
                          width: width,
                          child: _OverviewTile(
                            icon: Icons.fact_check_outlined,
                            value: materials.day == null
                                ? 'Not loaded'
                                : '${materials.day!.summary.checked}/${materials.day!.summary.total}',
                            label: 'Shelf checks',
                            onTap: () =>
                                LgNav.maybeOf(context)?.go('materials'),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
            if (_staffError != null) ...[
              LgNotice(
                message: _staffError!,
                foreground: LgColors.danger,
                background: LgColors.dangerBg,
                icon: Icons.error_outline_rounded,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _loadStaff,
                  child: const Text('Retry attendance'),
                ),
              ),
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
            if (session.modules.any(
              (m) => nativeModuleScreens.containsKey(m.key),
            )) ...[
              LgSectionTitle(
                'Quick access',
                trailing: TextButton(
                  onPressed: () => LgNav.maybeOf(context)?.go('more'),
                  child: const Text('All tools'),
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth >= 600
                      ? (constraints.maxWidth - 24) / 3
                      : (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final m in session.modules.where(
                        (m) =>
                            m.key == 'transport' ||
                            m.key == 'staff' ||
                            m.key == 'materials',
                      ))
                        SizedBox(
                          width: width,
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => openModule(context, m),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Icon(
                                      moduleIcons[m.key],
                                      color: LgColors.accent,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        m.label,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
            if (_hasTransport) ...[
              LgSectionTitle(
                'Transport',
                trailing: TextButton(
                  onPressed: () => LgNav.maybeOf(context)?.go('transport'),
                  child: const Text('All trips'),
                ),
              ),
              if (_tripError != null) ...[
                LgNotice(
                  message: _tripError!,
                  foreground: LgColors.danger,
                  background: LgColors.dangerBg,
                  icon: Icons.error_outline_rounded,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _loadTrips,
                    child: const Text('Retry trips'),
                  ),
                ),
              ] else if (_trips == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (upcoming.isEmpty)
                LgEmptyState(
                  icon: Icons.directions_bus_rounded,
                  title: _trips!.isEmpty
                      ? 'No trips today'
                      : 'Trips are finished',
                  message: _trips!.isEmpty
                      ? 'An admin can add cabs and routes on the website under Transport.'
                      : 'Open Transport if you need to review a finished run.',
                )
              else
                for (final t in upcoming.take(3)) ...[
                  TripRunCard(
                    trip: t,
                    onTap: () => openTripSummary(context, t),
                  ),
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
                    const Text(
                      'Trip running',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      routeName.isEmpty
                          ? 'Sharing the cab location'
                          : '$routeName · sharing location',
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

class _MaterialsUploadBanner extends StatelessWidget {
  const _MaterialsUploadBanner({required this.pending});

  final int pending;

  @override
  Widget build(BuildContext context) {
    if (pending <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: LgColors.infoBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFC5D7EE)),
        ),
        child: InkWell(
          onTap: () => LgNav.maybeOf(context)?.go('materials'),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.cloud_upload_rounded, color: LgColors.info),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    pending == 1
                        ? '1 material check is still uploading'
                        : '$pending material checks are still uploading',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: LgColors.info,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: LgColors.info),
              ],
            ),
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
                  decoration: BoxDecoration(
                    color: LgColors.accentSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    moduleIcons[module.key] ?? Icons.apps_rounded,
                    color: LgColors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        module.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        moduleDescription(module.key, inApp),
                        style: const TextStyle(
                          color: LgColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  inApp
                      ? Icons.chevron_right_rounded
                      : Icons.open_in_new_rounded,
                  color: LgColors.muted,
                  semanticLabel: inApp ? 'Open tool' : 'Opens school website',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final modules = [
      for (final m in session.modules)
        if (('${m.label} ${moduleDescription(m.key, moduleOpensInApp(m))}')
            .toLowerCase()
            .contains(_search.text.trim().toLowerCase()))
          m,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('School workspace')),
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
                      Text(
                        session.user!.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
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
          Text(
            'Everything in one place',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Find the tools you need to keep school running.',
            style: TextStyle(color: LgColors.muted),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Search school tools',
              hintText: 'Try attendance, fees, or materials',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () => setState(() => _search.clear()),
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          if (modules.isEmpty)
            const LgEmptyState(
              icon: Icons.grid_view_rounded,
              title: 'No school tools found',
              message:
                  'Try another search. Your admin controls which tools you can access.',
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
                  content: const Text(
                    'This phone will stop sharing a trip location, if one is running. Material photos already saved on the phone stay here and upload after the next sign-in.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Stay signed in'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Sign out'),
                    ),
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

String moduleDescription(String key, bool inApp) => switch (key) {
  'transport' => 'Trips, routes & safe arrivals',
  'staff' => 'Attendance, leave & your team',
  'materials' => 'Daily shelf checks & uploads',
  'students' => 'Student records & class details',
  'montessori' => 'Learning & student progress',
  'tasks' => 'Tasks, follow-ups & daily work',
  'fees' => 'Fee records & collections',
  'expenses' => 'School spending & payments',
  'crm' => 'Enquiries & admissions',
  'logbook' => 'Daily notes & school records',
  'inventory' => 'Supplies & stock',
  'plans' => 'Planning & class schedules',
  'daycare' => 'Daycare routines & records',
  'recruitment' => 'Candidates & hiring',
  _ => inApp ? 'Open school tool' : 'Continue on the school website',
};

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: LgColors.accent, size: 24),
            const SizedBox(height: 16),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: LgColors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    ),
  );
}
