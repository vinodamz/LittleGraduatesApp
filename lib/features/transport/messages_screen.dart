import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'desk.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  late final DeskApi _api = DeskApi(context.read<ApiClient>());
  final _body = TextEditingController();
  List<DeskMessage>? _messages;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await _api.messages();
      if (mounted) {
        setState(() {
          _messages = m;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _send({required String kind}) async {
    final text = _body.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await _api.send(text, kind: kind);
      _body.clear();
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<Session>().user?.isAdmin ?? false;
    final messages = _messages;
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              children: [
                if (_error != null)
                  LgNotice(message: _error!, foreground: LgColors.danger, background: LgColors.dangerBg, icon: Icons.error_outline_rounded),
                if (messages == null && _error == null)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator())),
                if (messages != null && messages.isEmpty)
                  const LgEmptyState(icon: Icons.forum_rounded, title: 'No messages yet', message: 'Notes here reach everyone on transport.'),
                for (final m in messages ?? const <DeskMessage>[]) ...[
                  _Bubble(message: m),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _body,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(hintText: 'Message the transport desk'),
                  ),
                ),
                IconButton(onPressed: _busy ? null : () => _send(kind: 'message'), icon: const Icon(Icons.send_rounded)),
                if (admin)
                  IconButton(
                    tooltip: 'Broadcast',
                    onPressed: _busy ? null : () => _send(kind: 'broadcast'),
                    icon: const Icon(Icons.campaign_rounded),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final DeskMessage message;

  @override
  Widget build(BuildContext context) {
    final danger = message.kind == 'sos';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: danger ? LgColors.dangerBg : message.kind == 'broadcast' ? LgColors.infoBg : LgColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: danger ? LgColors.danger : LgColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${message.name} · ${message.label} · ${message.at}', style: const TextStyle(color: LgColors.muted, fontSize: 12)),
            const SizedBox(height: 4),
            Text(message.body),
          ],
        ),
      ),
    );
  }
}
