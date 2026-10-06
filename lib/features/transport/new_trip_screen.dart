import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import 'transport_api.dart';
import 'trip_screen.dart';

/// Start another run of a saved route, or build a trip that was not planned.
class NewTripScreen extends StatefulWidget {
  const NewTripScreen({this.date, super.key});

  /// YYYY-MM-DD. Null means today.
  final String? date;

  @override
  State<NewTripScreen> createState() => _NewTripScreenState();
}

class _NewTripScreenState extends State<NewTripScreen> {
  late final TransportApi _api = TransportApi(context.read<ApiClient>());
  String _direction = 'pickup';
  List<RouteOption>? _routes;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final routes = await _api.routes();
      if (mounted) {
        setState(() {
          _routes = routes;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _startRoute(RouteOption route) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final trip = await _api.create(routeId: route.id, direction: _direction, date: widget.date);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripScreen(initial: trip)));
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _custom() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CustomTripScreen(direction: _direction, date: widget.date)),
    );
    if (created == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final routes = _routes?.where((r) => r.runs(_direction)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('New trip')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text('Pickup or drop?', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'pickup', label: Text('Pickup'), icon: Icon(Icons.school_rounded)),
              ButtonSegment(value: 'drop', label: Text('Drop'), icon: Icon(Icons.home_rounded)),
            ],
            selected: {_direction},
            onSelectionChanged: _busy ? null : (s) => setState(() => _direction = s.first),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _custom,
            icon: const Icon(Icons.edit_road_rounded),
            label: const Text('Build a trip from children'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Or start a saved route. If today’s run is already finished, this starts another one.',
            style: TextStyle(color: LgColors.muted, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: LgColors.danger)),
          if (routes == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (routes != null && routes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No saved route runs this way.', style: TextStyle(color: LgColors.muted)),
            ),
          for (final r in routes ?? const <RouteOption>[]) ...[
            const SizedBox(height: 8),
            Material(
              color: LgColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: LgColors.line),
              ),
              child: ListTile(
                enabled: !_busy,
                title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  [
                    if (r.cabName.isNotEmpty) r.cabName,
                    '${r.children} ${r.children == 1 ? 'child' : 'children'}',
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, color: LgColors.accent),
                onTap: () => _startRoute(r),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class CustomTripScreen extends StatefulWidget {
  const CustomTripScreen({required this.direction, this.date, super.key});

  final String direction;
  final String? date;

  @override
  State<CustomTripScreen> createState() => _CustomTripScreenState();
}

class _CustomTripScreenState extends State<CustomTripScreen> {
  late final TransportApi _api = TransportApi(context.read<ApiClient>());
  final _name = TextEditingController();
  final _search = TextEditingController();
  Timer? _debounce;
  List<ChildOption> _children = [];
  final _picked = <int, ChildOption>{};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearch);
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _load(_search.text));
  }

  Future<void> _load(String q) async {
    try {
      final children = await _api.children(q);
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

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Give this trip a name.')));
      return;
    }
    if (_picked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one child.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final trip = await _api.create(
        direction: widget.direction,
        name: name,
        studentIds: _picked.keys.toList(),
        date: widget.date,
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripScreen(initial: trip)));
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.direction == 'drop' ? 'drop' : 'pickup';
    return Scaffold(
      appBar: AppBar(title: Text('New $label')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Trip name',
                    hintText: 'e.g. Late pickup',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    labelText: 'Find a child',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                if (_picked.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_picked.length} selected',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
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
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    children: [
                      for (final c in _children)
                        CheckboxListTile(
                          value: _picked.containsKey(c.id),
                          title: Text(c.name),
                          subtitle: c.grade.isEmpty ? null : Text(c.grade),
                          onChanged: _busy
                              ? null
                              : (on) {
                                  setState(() {
                                    if (on == true) {
                                      _picked[c.id] = c;
                                    } else {
                                      _picked.remove(c.id);
                                    }
                                  });
                                },
                        ),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: LgColors.surface,
          border: Border(top: BorderSide(color: LgColors.line)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: FilledButton(
              onPressed: _busy ? null : _create,
              child: Text(_busy ? 'Creating…' : 'Create trip'),
            ),
          ),
        ),
      ),
    );
  }
}
