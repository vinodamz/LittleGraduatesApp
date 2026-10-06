import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'staff_api.dart';

enum _RosterFilter { all, waiting, here }

/// Check-in card shared by Today and the Staff tab.
class StaffAttendanceCard extends StatelessWidget {
  const StaffAttendanceCard({
    required this.day,
    required this.busy,
    required this.onCheckIn,
    required this.onCheckOut,
    this.onOpen,
    super.key,
  });

  final StaffDay day;
  final bool busy;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final a = day.attendance;
    final String headline;
    final String detail;
    if (!a.checkedIn) {
      headline = 'Not checked in';
      detail = a.shiftLabel.isEmpty ? 'Tap once when you arrive.' : 'Shift ${a.shiftLabel}.';
    } else if (!a.checkedOut) {
      headline = 'Checked in at ${a.checkIn}';
      detail = a.statusLabel;
    } else {
      headline = 'Done for today';
      detail = 'In ${a.checkIn} · Out ${a.checkOut}';
    }
    final shiftNote = a.lateAfter == null ? '' : 'Late after ${a.lateAfter}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('My attendance', style: TextStyle(color: LgColors.muted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(headline, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              [detail, if (shiftNote.isNotEmpty) shiftNote].join(' · '),
              style: const TextStyle(color: LgColors.muted),
            ),
            const SizedBox(height: 14),
            if (!a.checkedIn)
              FilledButton(
                onPressed: busy ? null : onCheckIn,
                child: Text(busy ? 'Checking in…' : 'Check in now'),
              )
            else if (!a.checkedOut)
              FilledButton(
                onPressed: busy ? null : onCheckOut,
                child: Text(busy ? 'Checking out…' : 'Check out'),
              )
            else
              const LgStatusPill(label: 'Attendance done', foreground: LgColors.ok, background: LgColors.okBg),
            if (onOpen != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: onOpen, child: const Text('Open staff')),
              ),
          ],
        ),
      ),
    );
  }
}

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  late final StaffApi _api = StaffApi(context.read<ApiClient>());
  StaffDay? _day;
  String? _error;
  bool _busy = false;
  _RosterFilter _filter = _RosterFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final day = await _api.today();
      if (mounted) {
        setState(() {
          _day = day;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _check(String op) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final day = await _api.check(op);
      if (!mounted) return;
      setState(() => _day = day);
      final at = op == 'self_in' ? day.attendance.checkIn : day.attendance.checkOut;
      _snack(op == 'self_in' ? 'Checked in at $at.' : 'Checked out at $at.');
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(String url, String label) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) _snack('Could not open $label.');
  }

  Future<void> _apply() async {
    final day = _day;
    final leave = day?.leave;
    if (day == null || leave == null || leave.types.isEmpty) return;
    final result = await showModalBottomSheet<LeaveResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: LgColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => _ApplyLeaveSheet(api: _api, leave: leave),
    );
    if (result == null || !mounted) return;
    setState(() => _day = result.day);
    _snack(result.message);
    if (result.notice.isEmpty || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Before this is approved'),
        content: Text(result.notice),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _cancel(LeaveRequest request) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: Text('${request.typeLabel} · ${formatDateRange(request.startDate, request.endDate)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cancel request')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await _api.leave({'op': 'cancel', 'id': request.id});
      if (!mounted) return;
      setState(() => _day = result.day);
      _snack(result.message);
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? get _website {
    for (final m in context.read<Session>().modules) {
      if (m.key == 'staff' && m.webUrl.isNotEmpty) return m.webUrl;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final day = _day;
    return Scaffold(
      appBar: AppBar(title: const Text('Staff')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (day != null)
              Text(day.dateLabel, style: const TextStyle(color: LgColors.muted))
            else
              Text(formatLongDate(DateTime.now()), style: const TextStyle(color: LgColors.muted)),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Semantics(
                liveRegion: true,
                child: LgNotice(
                  message: _error!,
                  foreground: LgColors.danger,
                  background: LgColors.dangerBg,
                  icon: Icons.error_outline_rounded,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Try again')),
              if (_website != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => _open(_website!, 'staff'), child: const Text('Open staff website')),
              ],
            ] else if (day == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              StaffAttendanceCard(
                day: day,
                busy: _busy,
                onCheckIn: () => _check('self_in'),
                onCheckOut: () => _check('self_out'),
              ),
              const SizedBox(height: 16),
              if (day.leave != null) _LeaveCard(leave: day.leave!, busy: _busy, onApply: _apply, onCancel: _cancel, onReview: () => _open(day.links.leave, 'leave')),
              const SizedBox(height: 16),
              _DutiesCard(
                pending: day.dutiesPending,
                onOpen: () => _open(day.links.duties, 'duties'),
              ),
              const SizedBox(height: 8),
              _RosterSection(
                people: day.roster,
                filter: _filter,
                onFilter: (f) => setState(() => _filter = f),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Payroll, documents and messages stay on the school website.', style: TextStyle(height: 1.4)),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => _open(day.links.staff, 'staff'),
                        child: const Text('Open staff website'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LeaveCard extends StatelessWidget {
  const _LeaveCard({
    required this.leave,
    required this.busy,
    required this.onApply,
    required this.onCancel,
    required this.onReview,
  });

  final StaffLeave leave;
  final bool busy;
  final VoidCallback onApply;
  final void Function(LeaveRequest request) onCancel;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('My leave', style: TextStyle(color: LgColors.muted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(leave.balanceLabel, style: Theme.of(context).textTheme.titleLarge),
            const Text('available', style: TextStyle(color: LgColors.muted)),
            if (leave.pending > 0) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: LgStatusPill(
                  label: '${leave.pending} awaiting approval',
                  foreground: LgColors.warn,
                  background: LgColors.warnBg,
                ),
              ),
            ],
            if (leave.pendingReviews > 0) ...[
              const SizedBox(height: 12),
              LgNotice(
                message: '${leave.pendingReviews} ${leave.pendingReviews == 1 ? 'request is' : 'requests are'} waiting for a decision.',
                foreground: LgColors.info,
                background: LgColors.infoBg,
                icon: Icons.inbox_rounded,
              ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: onReview, child: const Text('Review on the website')),
            ],
            const SizedBox(height: 12),
            FilledButton(onPressed: busy ? null : onApply, child: const Text('Apply for leave')),
            if (leave.requests.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final r in leave.requests) _LeaveRow(request: r, onCancel: r.pending && !busy ? () => onCancel(r) : null),
            ],
          ],
        ),
      ),
    );
  }
}

class _LeaveRow extends StatelessWidget {
  const _LeaveRow({required this.request, required this.onCancel});

  final LeaveRequest request;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (request.status) {
      'approved' => (LgColors.ok, LgColors.okBg),
      'pending' => (LgColors.warn, LgColors.warnBg),
      'rejected' || 'cancelled' => (LgColors.muted, const Color(0xFFF3EEE8)),
      _ => (LgColors.muted, const Color(0xFFF3EEE8)),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${request.typeLabel} · ${request.daysLabel}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  formatDateRange(request.startDate, request.endDate),
                  style: const TextStyle(color: LgColors.muted),
                ),
              ],
            ),
          ),
          LgStatusPill(label: request.statusLabel, foreground: fg, background: bg),
          if (onCancel != null)
            IconButton(
              tooltip: 'Cancel request',
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
    );
  }
}

class _DutiesCard extends StatelessWidget {
  const _DutiesCard({required this.pending, required this.onOpen});

  final int pending;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final clear = pending == 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('My duties', style: TextStyle(color: LgColors.muted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              clear ? 'Caught up' : '$pending still to tick',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onOpen, child: Text(clear ? 'Open duty list' : 'Tick them')),
          ],
        ),
      ),
    );
  }
}

class _RosterSection extends StatelessWidget {
  const _RosterSection({required this.people, required this.filter, required this.onFilter});

  final List<RosterPerson> people;
  final _RosterFilter filter;
  final ValueChanged<_RosterFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final waiting = people.where((p) => p.waiting).length;
    final here = people.where((p) => p.here).length;
    final shown = [
      for (final p in people)
        if (filter == _RosterFilter.all ||
            (filter == _RosterFilter.waiting && p.waiting) ||
            (filter == _RosterFilter.here && p.here))
          p,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LgSectionTitle('Who is in'),
        Text(
          '$here here · $waiting not in yet · ${people.length} on the roster',
          style: const TextStyle(color: LgColors.muted),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: filter == _RosterFilter.all,
              onSelected: (_) => onFilter(_RosterFilter.all),
            ),
            ChoiceChip(
              label: Text('Not in ($waiting)'),
              selected: filter == _RosterFilter.waiting,
              onSelected: (_) => onFilter(_RosterFilter.waiting),
            ),
            ChoiceChip(
              label: Text('Here ($here)'),
              selected: filter == _RosterFilter.here,
              onSelected: (_) => onFilter(_RosterFilter.here),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (shown.isEmpty)
          const LgEmptyState(icon: Icons.groups_rounded, title: 'No one in this list')
        else
          for (final p in shown) ...[
            _RosterRow(person: p),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _RosterRow extends StatelessWidget {
  const _RosterRow({required this.person});

  final RosterPerson person;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (person.status) {
      'present' || 'wfh' => (LgColors.ok, LgColors.okBg),
      'late' => (LgColors.warn, LgColors.warnBg),
      'absent' => (LgColors.danger, LgColors.dangerBg),
      'leave' || 'holiday' => (LgColors.info, LgColors.infoBg),
      _ => (LgColors.muted, const Color(0xFFF3EEE8)),
    };
    final times = [
      if (person.checkIn != null) 'In ${person.checkIn}',
      if (person.checkOut != null) 'Out ${person.checkOut}',
    ].join(' · ');
    return Material(
      color: LgColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: LgColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            LgAvatar(name: person.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(person.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    [person.roleLabel, if (times.isNotEmpty) times].join(' · '),
                    style: const TextStyle(color: LgColors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            LgStatusPill(label: person.statusLabel, foreground: fg, background: bg),
          ],
        ),
      ),
    );
  }
}

class _ApplyLeaveSheet extends StatefulWidget {
  const _ApplyLeaveSheet({required this.api, required this.leave});

  final StaffApi api;
  final StaffLeave leave;

  @override
  State<_ApplyLeaveSheet> createState() => _ApplyLeaveSheetState();
}

class _ApplyLeaveSheetState extends State<_ApplyLeaveSheet> {
  late String _type = widget.leave.types.first.key;
  DateTime _start = _today();
  DateTime _end = _today();
  String _half = '';
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _pick(bool start) async {
    final initial = start ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = picked;
        if (_end.isBefore(_start)) _start = _end;
      }
      if (ymd(_start) != ymd(_end)) _half = '';
    });
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.api.leave({
        'op': 'apply',
        'leave_type': _type,
        'start_date': ymd(_start),
        'end_date': ymd(_end),
        'half_day': _half,
        'reason': _reason.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context, result);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sameDay = ymd(_start) == ymd(_end);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: LgColors.line, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Apply for leave', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('${widget.leave.balanceLabel} available', style: const TextStyle(color: LgColors.muted)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey(_type),
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final t in widget.leave.types) DropdownMenuItem(value: t.key, child: Text(t.label)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _dateButton('From', _start, () => _pick(true))),
                const SizedBox(width: 12),
                Expanded(child: _dateButton('To', _end, () => _pick(false))),
              ],
            ),
            if (sameDay) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(label: const Text('Full day'), selected: _half == '', onSelected: (_) => setState(() => _half = '')),
                  ChoiceChip(label: const Text('Morning'), selected: _half == 'first', onSelected: (_) => setState(() => _half = 'first')),
                  ChoiceChip(label: const Text('Afternoon'), selected: _half == 'second', onSelected: (_) => setState(() => _half = 'second')),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Reason (optional)', alignLabelWithHint: true),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: LgNotice(
                  message: _error!,
                  foreground: LgColors.danger,
                  background: LgColors.dangerBg,
                  icon: Icons.error_outline_rounded,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Sending…' : 'Submit request')),
          ],
        ),
      ),
    );
  }

  Widget _dateButton(String label, DateTime date, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: _busy ? null : onTap,
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: LgColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          Text(formatShortDate(ymd(date))),
        ],
      ),
    );
  }
}
