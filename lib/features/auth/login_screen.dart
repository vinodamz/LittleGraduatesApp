import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/privacy.dart';

class _LoginUser {
  _LoginUser(this.id, this.name, this.role);

  final int id;
  final String name;
  final String role;

  String get initials => name
      .trim()
      .split(RegExp(r'\s+'))
      .take(2)
      .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
      .join();
}

/// Same flow as the website: tap your name, enter your PIN.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  List<_LoginUser>? _users;
  String? _error;
  String _school = 'Little Graduates';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await context.read<ApiClient>().get('login_users.php');
      setState(() {
        _school = (d['school'] as String?) ?? _school;
        _users = [
          for (final u in d['users'] as List)
            _LoginUser(
              u['id'] as int,
              u['name'] as String,
              u['role'] as String,
            ),
        ];
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
            children: [
              Text(
                _school,
                style: const TextStyle(
                  color: LgColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Who’s here?',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Text(
                'Tap your name to sign in.',
                style: TextStyle(color: LgColors.muted),
              ),
              const PrivacyPolicyButton(),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.red)),
                TextButton(onPressed: _load, child: const Text('Try again')),
              ] else if (_users == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                for (final u in _users!)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: LgColors.warnBg,
                        child: Text(
                          u.initials,
                          style: const TextStyle(color: LgColors.warn),
                        ),
                      ),
                      title: Text(u.name),
                      subtitle: Text(u.role == 'admin' ? 'Admin' : 'Staff'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => _PinScreen(user: u)),
                      ),
                    ),
                  ),
            ],
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
    try {
      await context.read<Session>().signIn(widget.user.id, _pin, 'Android app');
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
    setState(() {
      _error = null;
      if (k == '⌫') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 6) {
        _pin += k;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '⌫', '0', 'OK'];
    return Scaffold(
      appBar: AppBar(title: Text('Hi ${widget.user.name.split(' ').first}')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text(
                'Enter your PIN',
                style: TextStyle(color: LgColors.muted),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 4 || i < _pin.length; i++)
                    Container(
                      margin: const EdgeInsets.all(6),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _pin.length
                            ? LgColors.accent
                            : LgColors.line,
                      ),
                    ),
                ],
              ),
              SizedBox(
                height: 40,
                child: Center(
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _error ?? '',
                          style: const TextStyle(color: Colors.red),
                        ),
                ),
              ),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final k in keys)
                      k == 'OK'
                          ? FilledButton(
                              onPressed: _pin.length >= 4 ? _submit : null,
                              child: const Text('OK'),
                            )
                          : OutlinedButton(
                              onPressed: () => _tap(k),
                              child: Text(
                                k,
                                style: const TextStyle(fontSize: 22),
                              ),
                            ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
