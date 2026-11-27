import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';

class AppUser {
  AppUser({required this.id, required this.name, required this.role});

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
    id: j['id'] as int,
    name: j['name'] as String,
    role: j['role'] as String,
  );

  final int id;
  final String name;
  final String role;

  bool get isAdmin => role == 'admin';
}

/// One tile on the home screen. `native` modules have screens in the app;
/// the rest use the authenticated in-app school workspace.
class AppModule {
  AppModule({
    required this.key,
    required this.label,
    required this.native,
    required this.webUrl,
  });

  factory AppModule.fromJson(Map<String, dynamic> j) => AppModule(
    key: j['key'] as String,
    label: j['label'] as String,
    native: j['native'] as bool,
    webUrl: j['web_url'] as String,
  );

  final String key;
  final String label;
  final bool native;
  final String webUrl;
}

enum SessionState { loading, signedOut, signedIn }

class Session extends ChangeNotifier {
  Session(this.api) {
    api.onUnauthenticated = () {
      if (api.token != null) _forget();
    };
  }

  static const _tokenKey = 'lg_api_token';
  static const _profileKey = 'lg_profile';
  final ApiClient api;
  final _storage = const FlutterSecureStorage();
  int _revision = 0;
  Future<void> _storageWork = Future.value();
  Future<void> _logout = Future.value();
  bool _disposed = false;

  SessionState state = SessionState.loading;
  AppUser? user;
  String school = 'Little Graduates';
  List<AppModule> modules = [];

  Future<void> restore() async {
    final revision = ++_revision;
    user = null;
    modules = [];
    school = 'Little Graduates';
    final token = await _storage.read(key: _tokenKey);
    if (revision != _revision) return;
    if (token == null || token.isEmpty) {
      await _forget();
      return;
    }
    api.token = token;
    final cached = await _storage.read(key: _profileKey);
    if (revision != _revision) return;
    if (cached != null) {
      try {
        final data = jsonDecode(cached) as Map<String, dynamic>;
        if (data['token'] == token) {
          final cachedUser = AppUser.fromJson(
            data['user'] as Map<String, dynamic>,
          );
          final cachedModules = [
            for (final module in data['modules'] as List)
              AppModule.fromJson(module as Map<String, dynamic>),
          ];
          user = cachedUser;
          modules = cachedModules;
          school = data['school'] as String? ?? school;
        }
      } catch (_) {
        user = null;
        modules = [];
      }
    }
    try {
      await refresh();
    } on ApiException catch (e) {
      if (revision != _revision) return;
      if (e.isUnauthenticated) return;
      // Offline access needs a complete profile belonging to this token.
      if (user == null) {
        await _forget();
      } else {
        state = SessionState.signedIn;
        _notify();
      }
    }
  }

  Future<void> refresh() async {
    final revision = _revision;
    final token = api.token;
    final d = await api.get('me.php');
    if (revision != _revision || token != api.token) return;
    final freshUser = AppUser.fromJson(d['user'] as Map<String, dynamic>);
    final freshModules = [
      for (final m in d['modules'] as List)
        AppModule.fromJson(m as Map<String, dynamic>),
    ];
    user = freshUser;
    modules = freshModules;
    school = (d['school'] as String?) ?? school;
    state = SessionState.signedIn;
    await _cacheProfile();
    if (revision == _revision) _notify();
  }

  Future<void> signIn(int userId, String pin, String deviceName) async {
    final revision = ++_revision;
    // An old logout response must finish before new credentials are installed.
    await _logout;
    if (revision != _revision) return;
    final d = await api.post('login.php', {
      'user_id': userId,
      'pin': pin,
      'device_name': deviceName,
    });
    if (revision != _revision) return;
    final token = d['token'] as String;
    final signedInUser = AppUser.fromJson(d['user'] as Map<String, dynamic>);
    final signedInModules = [
      for (final m in d['modules'] as List)
        AppModule.fromJson(m as Map<String, dynamic>),
    ];
    api.token = token;
    user = signedInUser;
    modules = signedInModules;
    school = (d['school'] as String?) ?? 'Little Graduates';
    state = SessionState.signedIn;
    await _cacheProfile();
    if (revision == _revision) _notify();
  }

  Future<void> _cacheProfile() async {
    if (api.token == null || user == null) return;
    final revision = _revision;
    final token = api.token!;
    final profile = jsonEncode({
      'token': token,
      'school': school,
      'user': {'id': user!.id, 'name': user!.name, 'role': user!.role},
      'modules': [
        for (final module in modules)
          {
            'key': module.key,
            'label': module.label,
            'native': module.native,
            'web_url': module.webUrl,
          },
      ],
    });
    await _persist(() async {
      if (revision != _revision) return;
      await _storage.write(key: _tokenKey, value: token);
      await _storage.write(key: _profileKey, value: profile);
    });
  }

  Future<void> signOut() async {
    // ApiClient captures the bearer header when the request starts.
    _logout = _revoke();
    await _forget();
    await _logout;
  }

  Future<void> _revoke() async {
    try {
      await api.post('logout.php');
    } on ApiException {
      // Signing out locally still works offline.
    }
  }

  Future<void> _forget() async {
    ++_revision;
    api.token = null;
    user = null;
    modules = [];
    school = 'Little Graduates';
    state = SessionState.signedOut;
    _notify();
    await _persist(() async {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _profileKey);
    });
  }

  Future<void> _persist(Future<void> Function() action) {
    final next = _storageWork.catchError((Object _) {}).then((_) => action());
    _storageWork = next;
    return next;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_revision;
    api.onUnauthenticated = null;
    super.dispose();
  }
}
