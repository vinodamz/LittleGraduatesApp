import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'today_api.dart';

/// Shared frame for the Today cards: icon, title, body, actions.
class TodayCard extends StatelessWidget {
  const TodayCard({
    required this.icon,
    required this.title,
    required this.children,
    this.highlight = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: highlight ? LgColors.accent : LgColors.line,
          width: highlight ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: LgColors.accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: LgColors.accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: LgColors.muted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// "My class": today's attendance at a glance, one tap for the usual case.
class MyClassCard extends StatelessWidget {
  const MyClassCard({
    required this.myClass,
    required this.busy,
    required this.onRestPresent,
    required this.onChange,
    super.key,
  });

  final MyClass myClass;
  final bool busy;
  final VoidCallback onRestPresent;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final c = myClass.counts;
    final done = c.unsaved == 0;
    final headline = done
        ? 'Attendance saved'
        : c.unsaved == c.total
        ? 'Attendance not taken yet'
        : '${c.unsaved} of ${c.total} not marked yet';
    final parts = [
      '${c.present} present',
      if (c.absent > 0) '${c.absent} absent',
      if (c.other > 0) '${c.other} other',
    ];
    return TodayCard(
      icon: Icons.groups_rounded,
      title: 'My class · ${c.total} ${c.total == 1 ? 'child' : 'children'}',
      highlight: !done,
      children: [
        Text(
          headline,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: done ? LgColors.ok : LgColors.indigo,
          ),
        ),
        if (c.total - c.unsaved > 0) ...[
          const SizedBox(height: 4),
          Text(
            parts.join(' · '),
            style: const TextStyle(color: LgColors.muted),
          ),
        ],
        const SizedBox(height: 14),
        if (!done) ...[
          FilledButton(
            onPressed: busy ? null : onRestPresent,
            child: Text(
              busy
                  ? 'Saving…'
                  : c.unsaved == c.total
                  ? 'Everyone is present'
                  : 'Mark the rest present',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: busy ? null : onChange,
            child: const Text('Mark absent or late'),
          ),
        ] else
          OutlinedButton(
            onPressed: busy ? null : onChange,
            child: const Text('Change attendance'),
          ),
      ],
    );
  }
}

/// For staff with no class of their own who can cover one (subteachers).
class CoverClassCard extends StatelessWidget {
  const CoverClassCard({required this.onOpen, super.key});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return TodayCard(
      icon: Icons.groups_rounded,
      title: 'Class attendance',
      children: [
        const Text(
          'No class is assigned to you. Covering one today?',
          style: TextStyle(color: LgColors.muted),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onOpen,
          child: const Text('Mark class attendance'),
        ),
      ],
    );
  }
}

/// What is still to do today: duties to tick and children to assess.
class TodoCard extends StatelessWidget {
  const TodoCard({
    required this.dutiesPending,
    required this.assessmentsPending,
    required this.onDuties,
    required this.onAssessments,
    super.key,
  });

  final int dutiesPending;
  final int assessmentsPending;
  final VoidCallback onDuties;
  final VoidCallback onAssessments;

  @override
  Widget build(BuildContext context) {
    return TodayCard(
      icon: Icons.checklist_rounded,
      title: 'Still to do',
      children: [
        if (dutiesPending > 0)
          _TodoRow(
            label: dutiesPending == 1
                ? '1 duty to tick'
                : '$dutiesPending duties to tick',
            onTap: onDuties,
          ),
        if (assessmentsPending > 0)
          _TodoRow(
            label: assessmentsPending == 1
                ? '1 child to assess this month'
                : '$assessmentsPending children to assess this month',
            onTap: onAssessments,
          ),
      ],
    );
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: LgColors.muted),
          ],
        ),
      ),
    );
  }
}

/// School admins: who is in, and what is waiting for them.
class AdminGlanceCard extends StatelessWidget {
  const AdminGlanceCard({
    required this.glance,
    required this.onStaff,
    required this.onLeave,
    super.key,
  });

  final AdminGlance glance;
  final VoidCallback onStaff;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return TodayCard(
      icon: Icons.admin_panel_settings_rounded,
      title: 'School today',
      children: [
        _TodoRow(
          label: '${glance.staffIn} of ${glance.staffTotal} staff checked in',
          onTap: onStaff,
        ),
        if (glance.leaveToReview > 0)
          _TodoRow(
            label: glance.leaveToReview == 1
                ? '1 leave request to approve'
                : '${glance.leaveToReview} leave requests to approve',
            onTap: onLeave,
          ),
      ],
    );
  }
}
