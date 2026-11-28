import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/module_registry.dart';
import '../../core/nav.dart';
import '../../core/privacy.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/school_logo.dart';
import '../../core/widgets.dart';
import '../materials/materials_controller.dart';
import '../staff/staff_api.dart';
import '../staff/staff_screen.dart';
import '../transport/location_tracker.dart';
import '../transport/today_screen.dart';
import '../transport/transport_api.dart';
import '../transport/trip_screen.dart';
import 'class_attendance_screen.dart';
import 'school_catalog.dart';
import 'today_api.dart';
import 'today_cards.dart';

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
  TodaySummary? _summary;
  bool _classBusy = false;

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
      _loadSummary(),
      if (_hasTransport) _loadTrips(),
      if (_hasStaff) _loadStaff(),
    ]);
  }

  /// My class, duties, assessments and the admin glance. Optional: an older
  /// school server without this endpoint leaves Today as it was.
  Future<void> _loadSummary() async {
    try {
      final summary = await TodayApi(context.read<ApiClient>()).load();
      if (mounted) setState(() => _summary = summary);
    } on ApiException {
      if (mounted) setState(() => _summary = null);
    }
  }

  Future<void> _markRestPresent() async {
    if (_classBusy) return;
    setState(() => _classBusy = true);
    try {
      final next = await TodayApi(context.read<ApiClient>()).markRestPresent();
      if (!mounted) return;
      setState(() => _summary = next ?? _summary);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Attendance saved.')));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _classBusy = false);
    }
  }

  Future<void> _openClass() async {
    final summary = _summary;
    if (summary == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClassAttendanceScreen(initial: summary),
      ),
    );
    if (mounted) await _loadSummary();
  }

  Future<void> _openWeb(String url, String label) async {
    if (url.isEmpty) return;
    await openWebUrl(context, url, label);
    if (mounted) await _loadSummary();
  }

  List<Widget> _summaryCards(TodaySummary s) {
    final myClass = s.myClass;
    return [
      if (myClass != null && myClass.hasClass)
        MyClassCard(
          myClass: myClass,
          busy: _classBusy,
          onRestPresent: _markRestPresent,
          onChange: _openClass,
        )
      else if (myClass != null && myClass.canCover)
        CoverClassCard(
          onOpen: () => _openWeb(s.links.attendance, 'Class attendance'),
        ),
      if (s.dutiesPending > 0 || s.assessmentsPending > 0)
        TodoCard(
          dutiesPending: s.dutiesPending,
          assessmentsPending: s.assessmentsPending,
          onDuties: () => _openWeb(s.links.duties, 'My duties'),
          onAssessments: () => _openWeb(s.links.assessment, 'Assessment'),
        ),
      if (s.admin != null)
        AdminGlanceCard(
          glance: s.admin!,
          onStaff: () => _hasStaff
              ? LgNav.maybeOf(context)?.go('staff')
              : _openWeb(s.links.staffToday, 'Staff today'),
          onLeave: () => _openWeb(s.links.leaveReview, 'Leave'),
        ),
    ];
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
    final shortcuts = dailyShortcuts(session.modules);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const SchoolLogo(size: 44),
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
            Text(
              user == null
                  ? greetingFor(now)
                  : '${greetingFor(now)}, ${firstName(user.name)}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              formatLongDate(now),
              style: const TextStyle(color: LgColors.muted),
            ),
            const SizedBox(height: 16),
            if (tracker.active) ...[
              _LiveTripBanner(
                routeName: tracker.routeName,
                onOpen: _openRunningTrip,
              ),
              const SizedBox(height: 16),
            ],
            if (session.modules.any((m) => m.key == 'materials'))
              _MaterialsUploadBanner(pending: materialsPending),
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
            if (_summary != null) ..._summaryCards(_summary!),
            if (shortcuts.isNotEmpty)
              LgSectionTitle(
                'Daily work',
                trailing: TextButton(
                  onPressed: () => LgNav.maybeOf(context)?.go('more'),
                  child: const Text('All tools'),
                ),
              ),
            for (final module in shortcuts) ...[
              ModuleRow(module: module),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
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
                      ? 'An admin can add cabs and routes in Transport tools.'
                      : 'Open Transport if you need to review a finished run.',
                )
              else
                for (final t in upcoming.take(1)) ...[
                  TripRunCard(
                    trip: t,
                    onTap: () => openTripSummary(context, t),
                  ),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 8),
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
                        ? '1 saved check waiting to sync'
                        : '$pending saved checks waiting to sync',
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
      appBar: AppBar(title: const Text('School tools')),
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
          else if (_search.text.trim().isNotEmpty)
            for (final m in modules) ...[
              ModuleRow(module: m),
              const SizedBox(height: 8),
            ]
          else
            for (final group in groupSchoolModules(modules).entries)
              ExpansionTile(
                key: PageStorageKey('school-${group.key}'),
                initiallyExpanded: group.key == 'Daily work',
                tilePadding: EdgeInsets.zero,
                title: Text(
                  group.key,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${group.value.length} ${group.value.length == 1 ? 'tool' : 'tools'}',
                ),
                children: [
                  for (final module in group.value) ...[
                    ModuleRow(module: module),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
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
  'wacrm' => 'WhatsApp conversations & leads',
  'n8n' => 'School automations & workflows',
  'my_day' => 'Class attendance, assessments & daily work',
  'duties' => 'Assigned checklists & daily responsibilities',
  'my_leave' => 'Your leave balance, applications & history',
  'notifications' => 'Alerts, reminders & notification preferences',
  'money' => 'Collections, dues & school spending',
  'duties_admin' => 'Assign duties & review completion',
  'feedback' => 'Review parent feedback',
  'surveys' => 'Create surveys & review responses',
  'grades' => 'Manage grade levels',
  'mcp_admin' => 'Manage API access & integrations',
  'admin' => 'Users, permissions & school settings',
  _ => inApp ? 'Open school tool' : 'Open school tool',
};
