import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'desk.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final DeskApi _api = DeskApi(context.read<ApiClient>());
  TransportReport? _report;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.report();
      if (mounted) {
        setState(() {
          _report = r;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (_error != null)
            LgNotice(message: _error!, foreground: LgColors.danger, background: LgColors.dangerBg, icon: Icons.error_outline_rounded),
          if (report == null && _error == null)
            const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator())),
          if (report != null) ...[
            Text('${report.from} to ${report.to}', style: const TextStyle(color: LgColors.muted)),
            const SizedBox(height: 12),
            _Stat('Trips this week', '${report.completed} finished of ${report.trips}'),
            _Stat('Children handled', '${report.stopsDone} pickups or drops'),
            _Stat('Not riding', '${report.stopsAbsent}'),
            _Stat('SOS alerts', '${report.sos}'),
            const LgSectionTitle('By route'),
            if (report.routes.isEmpty) const Text('No trips this week.', style: TextStyle(color: LgColors.muted)),
            for (final r in report.routes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${r.trips} trips · ${r.done} done · ${r.absent} not riding'),
              ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: LgColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: LgColors.line)),
        child: ListTile(title: Text(label), trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w700))),
      ),
    );
  }
}
