import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/privacy.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class _LoginUser {
  _LoginUser(this.id, this.name, this.role);

  final int id;
  final String name;
  final String role;

  String get roleLabel => role == 'admin' ? 'Admin' : 'Staff';
}

/// Same flow as the website: tap your name, enter your PIN.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _search = TextEditingController();
  List<_LoginUser>? _users;
  String? _error;
  String _school = 'Little Graduates';

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await context.read<ApiClient>().get('login_users.php');
      if (!mounted) return;
      setState(() {
        _school = (d['school'] as String?) ?? _school;
        _users = [
          for (final u in d['users'] as List)
            _LoginUser(u['id'] as int, u['name'] as String, u['role'] as String),
        ];
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final users = [
      for (final u in _users ?? const <_LoginUser>[])
        if (query.isEmpty || u.name.toLowerCase().contains(query)) u,
    ];
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            children: [
              Text(
                _school,
                style: const TextStyle(color: LgColors.accent, fontWeight: FontWeight.w700, letterSpacing: 0.2),
              ),
              const SizedBox(height: 8),
              Text('Who’s here?', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              const Text('Tap your name, then enter your PIN.', style: TextStyle(color: LgColors.muted, height: 1.4)),
              const SizedBox(height: 8),
              const Align(alignment: Alignment.centerLeft, child: PrivacyPolicyButton()),
              const SizedBox(height: 8),
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
                const SizedBox(height: 8),
                FilledButton(onPressed: _load, child: const Text('Try again')),
              ] else if (_users == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (_users!.length > 6) ...[
                  TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Find your name',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (users.isEmpty)
                  const LgEmptyState(
                    icon: Icons.person_search_rounded,
                    title: 'No one matches that name',
                    message: 'Check the spelling, or clear the search.',
                  )
                else
                  for (final u in users) ...[
                    _PersonTile(user: u),
                    const SizedBox(height: 8),
                  ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.user});

  final _LoginUser user;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LgColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: LgColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _PinScreen(user: user))),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                LgAvatar(name: user.name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(user.roleLabel, style: const TextStyle(color: LgColors.muted, fontSize: 13)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: LgColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PinScreen extends StatefulWidget {
  const _PinScreen({required this.user});

  final _LoginUser user;

  @override
  State<_PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<_PinScreen> {
  String _pin = '';
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    if (_pin.length < 4 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final device = Theme.of(context).platform == TargetPlatform.iOS ? 'iOS app' : 'Android app';
    try {
      await context.read<Session>().signIn(widget.user.id, _pin, device);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _pin = '';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _tap(String k) {
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      if (k == 'back') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 6) {
        _pin += k;
      }
    });
    if (_pin.length == 6) _submit();
  }

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'back', '0', 'ok'];
    return Scaffold(
      appBar: AppBar(title: Text(firstName(widget.user.name))),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 16),
                child: Column(
                  children: [
                    LgAvatar(name: widget.user.name, radius: 28),
                    const SizedBox(height: 12),
                    const Text('Enter your PIN', style: TextStyle(color: LgColors.muted)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < (_pin.length > 4 ? _pin.length : 4); i++)
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < _pin.length ? LgColors.accent : LgColors.line,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(
                      height: 48,
                      child: Center(
                        child: _busy
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                            : Semantics(
                                liveRegion: true,
                                child: Text(
                                  _error ?? '',
                                  style: const TextStyle(color: LgColors.danger, fontWeight: FontWeight.w600),
                                ),
                              ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: GridView.count(
                          shrinkWrap: true,
                          crossAxisCount: 3,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.35,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [for (final k in keys) _key(k)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _key(String k) {
    if (k == 'ok') {
      return FilledButton(
        onPressed: _pin.length >= 4 && !_busy ? _submit : null,
        child: const Text('OK'),
      );
    }
    if (k == 'back') {
      return OutlinedButton(
        onPressed: _busy ? null : () => _tap('back'),
        child: const Icon(Icons.backspace_outlined, semanticLabel: 'Delete'),
      );
    }
    return OutlinedButton(
      onPressed: _busy ? null : () => _tap(k),
      child: Text(k, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
    );
  }
}
