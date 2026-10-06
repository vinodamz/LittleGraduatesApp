import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'desk.dart';

class TransportSettingsScreen extends StatefulWidget {
  const TransportSettingsScreen({super.key});

  @override
  State<TransportSettingsScreen> createState() => _TransportSettingsScreenState();
}

class _TransportSettingsScreenState extends State<TransportSettingsScreen> {
  late final DeskApi _api = DeskApi(context.read<ApiClient>());
  final _contact = TextEditingController();
  TransportSettings? _settings;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _contact.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _api.settings();
      if (!mounted) return;
      _contact.text = s.contact;
      setState(() {
        _settings = s;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _save(TransportSettings next) async {
    setState(() {
      _settings = next;
      _busy = true;
    });
    try {
      final saved = await _api.saveSettings(next, contact: _contact.text.trim());
      if (!mounted) return;
      _contact.text = saved.contact;
      setState(() => _settings = saved);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved.')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (_error != null)
          LgNotice(message: _error!, foreground: LgColors.danger, background: LgColors.dangerBg, icon: Icons.error_outline_rounded),
        if (s == null && _error == null) const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
        if (s != null) ...[
          Text(s.school, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _contact,
            decoration: const InputDecoration(labelText: 'Transport contact'),
            keyboardType: TextInputType.phone,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Notify parents at pickup'),
            subtitle: const Text('The 5-minute WhatsApp reminder stays available.'),
            value: s.notifyPickup,
            onChanged: _busy ? null : (v) => _save(_copy(s, notify: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Speed alerts above 50 km/h'),
            value: s.speedAlerts,
            onChanged: _busy ? null : (v) => _save(_copy(s, speed: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Delete detailed coordinates after 30 days'),
            value: s.deleteCoordinates,
            onChanged: _busy ? null : (v) => _save(_copy(s, keep: v)),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _busy ? null : () => _save(s), child: const Text('Save contact')),
        ],
      ],
    );
  }

  TransportSettings _copy(TransportSettings s, {bool? notify, bool? speed, bool? keep}) {
    return TransportSettings.fromJson({
      'school': s.school,
      'contact': _contact.text,
      'notify_pickup': notify ?? s.notifyPickup,
      'speed_alerts': speed ?? s.speedAlerts,
      'delete_coordinates': keep ?? s.deleteCoordinates,
    });
  }
}
