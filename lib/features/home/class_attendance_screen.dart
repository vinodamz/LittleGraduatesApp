import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/module_registry.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'today_api.dart';

/// Today's class register. Each tap saves straight away, so there is no
/// Save button to scroll to and nothing is lost if the teacher walks off.
class ClassAttendanceScreen extends StatefulWidget {
  const ClassAttendanceScreen({required this.initial, super.key});

  final TodaySummary initial;

  @override
  State<ClassAttendanceScreen> createState() => _ClassAttendanceScreenState();
}

class _ClassAttendanceScreenState extends State<ClassAttendanceScreen> {
  late TodaySummary _today = widget.initial;
  final Set<int> _saving = {};
  bool _bulk = false;

  TodayApi get _api => TodayApi(context.read<ApiClient>());

  Future<void> _run(Future<TodaySummary?> Function() call) async {
    try {
      final next = await call();
      if (mounted && next != null) setState(() => _today = next);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _set(ClassChild child, String status) async {
    if (_saving.contains(child.id) || child.status == status) return;
    setState(() => _saving.add(child.id));
    await _run(() => _api.setMark(child.id, status));
    if (mounted) setState(() => _saving.remove(child.id));
  }

  Future<void> _restPresent() async {
    setState(() => _bulk = true);
    await _run(_api.markRestPresent);
    if (mounted) setState(() => _bulk = false);
  }

  @override
  Widget build(BuildContext context) {
    final myClass = _today.myClass;
    final children = myClass?.students ?? const <ClassChild>[];
    final c = myClass?.counts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Class attendance'),
        actions: [
          TextButton(
            onPressed: () => openWebUrl(context, _today.links.myDay, 'My Day'),
            child: const Text('Add notes'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (c != null)
            Text(
              c.unsaved == 0
                  ? 'All saved · ${c.present} present'
                        '${c.absent > 0 ? ' · ${c.absent} absent' : ''}'
                  : '${c.unsaved} not marked yet. Each tap saves.',
              style: const TextStyle(color: LgColors.muted),
            ),
          const SizedBox(height: 12),
          if (c != null && c.unsaved > 0) ...[
            FilledButton(
              onPressed: _bulk ? null : _restPresent,
              child: Text(_bulk ? 'Saving…' : 'Mark the rest present'),
            ),
            const SizedBox(height: 16),
          ],
          for (final child in children) ...[
            _ChildRow(
              child: child,
              statuses: myClass!.statuses,
              saving: _saving.contains(child.id),
              onPick: (s) => _set(child, s),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _ChildRow extends StatelessWidget {
  const _ChildRow({
    required this.child,
    required this.statuses,
    required this.saving,
    required this.onPick,
  });

  final ClassChild child;
  final List<String> statuses;
  final bool saving;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LgColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: child.status == null ? LgColors.warn : LgColors.line,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LgAvatar(name: child.name, radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    child.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (saving)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (child.status == null)
                  const LgStatusPill(
                    label: 'Not marked',
                    foreground: LgColors.warn,
                    background: LgColors.warnBg,
                  ),
              ],
            ),
            if (child.notes != null) ...[
              const SizedBox(height: 4),
              Text(
                child.notes!,
                style: const TextStyle(color: LgColors.muted, fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in statuses)
                  ChoiceChip(
                    label: Text(classStatusLabel(s)),
                    selected: child.status == s,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                    selectedColor: _statusColor(s),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: child.status == s ? Colors.white : LgColors.ink,
                    ),
                    onSelected: saving ? null : (_) => onPick(s),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Same colours as the website's attendance buttons.
Color _statusColor(String status) => switch (status) {
  'present' => const Color(0xFF2E7D32),
  'absent' => const Color(0xFFB42318),
  'late' => const Color(0xFF8A5210),
  'excused' => const Color(0xFF2D6BA0),
  _ => const Color(0xFF6B6863),
};
