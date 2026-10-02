import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';

class AppUser {
  AppUser({required this.id, required this.name, required this.role});

  factory AppUser.fromJson(Map<String, dynamic> j) =>
      AppUser(id: j['id'] as int, name: j['name'] as String, role: j['role'] as String);

  final int id;
  final String name;
  final String role;

  bool get isAdmin => role == 'admin';
}

/// One tile on the home screen. `native` modules have screens in the app;
/// the rest open the matching MTT web page.
class AppModule {
  AppModule({required this.key, required this.label, required this.native, required this.webUrl});

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
    api.onUnauthenticated = _forget;
  }

  static const _tokenKey = 'lg_api_token';
  final ApiClient api;
  final _storage = const FlutterSecureStorage();

  SessionState state = SessionState.loading;
  AppUser? user;
  String school = 'Little Graduates';
  List<AppModule> modules = [];

  Future<void> restore() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null) {
      state = SessionState.signedOut;
      notifyListeners();
      return;
    }
    api.token = token;
    try {
      await refresh();
    } on ApiException catch (e) {
      if (e.isUnauthenticated) return;
      // Offline at launch: stay signed in, retry from the home screen.
      state = SessionState.signedIn;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    final d = await api.get('me.php');
    user = AppUser.fromJson(d['user'] as Map<String, dynamic>);
    school = (d['school'] as String?) ?? school;
    modules = [for (final m in d['modules'] as List) AppModule.fromJson(m as Map<String, dynamic>)];
    state = SessionState.signedIn;
    notifyListeners();
  }

  Future<void> signIn(int userId, String pin, String deviceName) async {
    final d = await api.post('login.php', {'user_id': userId, 'pin': pin, 'device_name': deviceName});
    final token = d['token'] as String;
    await _storage.write(key: _tokenKey, value: token);
    api.token = token;
    user = AppUser.fromJson(d['user'] as Map<String, dynamic>);
    modules = [for (final m in d['modules'] as List) AppModule.fromJson(m as Map<String, dynamic>)];
    state = SessionState.signedIn;
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await api.post('logout.php');
    } on ApiException {
      // Signing out locally still works offline.
    }
    await _forget();
  }

  Future<void> _forget() async {
    await _storage.delete(key: _tokenKey);
    api.token = null;
    user = null;
    modules = [];
    state = SessionState.signedOut;
    notifyListeners();
  }
}
