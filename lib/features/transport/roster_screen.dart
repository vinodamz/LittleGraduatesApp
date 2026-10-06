import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'desk.dart';

/// Students on routes. [arrivals] is the class-teacher handover list.
class RosterScreen extends StatefulWidget {
  const RosterScreen({this.arrivals = false, super.key});

  final bool arrivals;

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  late final DeskApi _api = DeskApi(context.read<ApiClient>());
  final _search = TextEditingController();
  Roster? _roster;
  String _filter = 'all';
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.roster(_search.text);
      if (mounted) {
        setState(() {
          _roster = r;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final roster = _roster;
    final children = roster?.children.where((c) => _filter == 'all' || c.status == _filter).toList() ?? const <RosterChild>[];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _search,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search children or routes'),
            onSubmitted: (_) => _load(),
          ),
          const SizedBox(height: 8),
          if (roster != null)
            Wrap(
              spacing: 6,
              children: [
                _chip('all', widget.arrivals ? 'All' : 'All ${roster.children.length}'),
                _chip('waiting', widget.arrivals ? 'Expected ${roster.waiting}' : 'Waiting ${roster.waiting}'),
                _chip('en_route', 'On the way ${roster.enRoute}'),
                _chip('arrived', widget.arrivals ? 'Arrived ${roster.arrived}' : 'At school ${roster.arrived}'),
                _chip('absent', 'Not riding ${roster.absent}'),
              ],
            ),
          if (!widget.arrivals)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: roster == null ? null : () => _copy(rosterCsv(roster.children), 'Student list copied.'),
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Export'),
              ),
            ),
          if (_error != null)
            LgNotice(message: _error!, foreground: LgColors.danger, background: LgColors.dangerBg, icon: Icons.error_outline_rounded),
          if (roster == null && _error == null)
            const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator())),
          if (roster != null && children.isEmpty)
            const LgEmptyState(icon: Icons.child_care_rounded, title: 'No children match'),
          for (final c in children) ...[
            _ChildRow(
              child: c,
              showPin: widget.arrivals,
              onShare: () => _copy(c.trackUrl, 'Private link for ${c.name.split(' ').first} copied.'),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _chip(String value, String label) {
    return FilterChip(
      label: Text(label),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
    );
  }
}

class _ChildRow extends StatelessWidget {
  const _ChildRow({required this.child, required this.showPin, required this.onShare});

  final RosterChild child;
  final bool showPin;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (child.status) {
      'arrived' => (LgColors.ok, LgColors.okBg),
      'en_route' => (LgColors.warn, LgColors.warnBg),
      'absent' => (LgColors.danger, LgColors.dangerBg),
      _ => (LgColors.muted, const Color(0xFFF3EEE8)),
    };
    return Material(
      color: LgColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: LgColors.line)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            LgAvatar(name: child.name),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(child.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    [child.grade, child.routeName, if (child.guardian.isNotEmpty) child.guardian].join(' · '),
                    style: const TextStyle(color: LgColors.muted, fontSize: 13),
                  ),
                  if (showPin && child.pin != null)
                    Text('Handover PIN ${child.pin}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            LgStatusPill(label: child.statusLabel, foreground: fg, background: bg),
            IconButton(tooltip: 'Copy family link', onPressed: onShare, icon: const Icon(Icons.link_rounded)),
          ],
        ),
      ),
    );
  }
}
