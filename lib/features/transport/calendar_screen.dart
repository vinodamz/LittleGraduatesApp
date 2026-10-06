import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import 'transport_api.dart';

const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Monday-first cells for [month]. Days outside the month are null.
List<DateTime?> monthGrid(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final lead = first.weekday - 1;
  final count = DateTime(month.year, month.month + 1, 0).day;
  final cells = <DateTime?>[
    for (var i = 0; i < lead; i++) null,
    for (var day = 1; day <= count; day++) DateTime(month.year, month.month, day),
  ];
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  return cells;
}

class TripCalendarScreen extends StatefulWidget {
  const TripCalendarScreen({required this.onOpenDay, super.key});

  final Future<void> Function(DateTime day) onOpenDay;

  @override
  State<TripCalendarScreen> createState() => _TripCalendarScreenState();
}

class _TripCalendarScreenState extends State<TripCalendarScreen> {
  late final TransportApi _api = TransportApi(context.read<ApiClient>());
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, DayMark> _marks = {};
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final days = await _api.month(_month);
      if (!mounted) return;
      setState(() {
        _marks = {for (final d in days) d.date: d};
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  void _shift(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  void _jumpToday() {
    final now = DateTime.now();
    setState(() => _month = DateTime(now.year, now.month));
    _load();
  }

  Future<void> _openDay(DateTime day) async {
    await widget.onOpenDay(day);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final cells = monthGrid(_month);
    final title = '${_monthsName(_month.month)} ${_month.year}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip calendar'),
        actions: [
          TextButton(onPressed: _jumpToday, child: const Text('Today')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: () => _shift(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final label in _weekdayLabels)
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: LgColors.muted, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: LgColors.danger)),
            ),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.82,
            children: [
              for (final day in cells)
                _DayCell(
                  day: day,
                  mark: day == null ? null : _marks[ymd(day)],
                  today: day != null && day.year == now.year && day.month == now.month && day.day == now.day,
                  onTap: day == null || _loading ? null : () => _openDay(day),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _LegendDot(color: LgColors.warn, label: 'On the road'),
              _LegendDot(color: LgColors.ok, label: 'Finished'),
              _LegendDot(color: LgColors.muted, label: 'Not started'),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'A dot means a trip was already created. Tap any day to open that day’s runs.',
            style: TextStyle(color: LgColors.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

String _monthsName(int month) =>
    const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][month - 1];

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.mark, required this.today, required this.onTap});

  final DateTime? day;
  final DayMark? mark;
  final bool today;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final date = day;
    if (date == null) return const SizedBox.shrink();
    final dots = <Color>[
      if (mark != null && mark!.running > 0) LgColors.warn,
      if (mark != null && mark!.completed > 0) LgColors.ok,
      if (mark != null && mark!.scheduled > 0) LgColors.muted,
      if (mark != null && mark!.cancelled > 0 && mark!.running + mark!.completed + mark!.scheduled == 0) LgColors.danger,
    ];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: today
                  ? const BoxDecoration(color: LgColors.accent, shape: BoxShape.circle)
                  : null,
              child: Text(
                '${date.day}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: today ? Colors.white : LgColors.ink,
                ),
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final color in dots) ...[
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 2),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: LgColors.muted, fontSize: 13)),
      ],
    );
  }
}
