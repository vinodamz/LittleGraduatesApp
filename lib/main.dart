import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/notifications.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
import 'features/transport/location_tracker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifications.init();
  final api = ApiClient();
  final session = Session(api);
  final tracker = LocationTracker(api);
  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: api),
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: tracker),
      ],
      child: const LittleGraduatesApp(),
    ),
  );
  await session.restore();
}

class LittleGraduatesApp extends StatelessWidget {
  const LittleGraduatesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.select<Session, SessionState>((s) => s.state);
    return MaterialApp(
      title: 'Little Graduates',
      theme: buildTheme(),
      debugShowCheckedModeBanner: false,
      home: switch (state) {
        SessionState.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
        SessionState.signedOut => const LoginScreen(),
        SessionState.signedIn => const HomeScreen(),
      },
    );
  }
}
