import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';

import 'core/api_client.dart';
import 'core/notifications.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/materials/materials_background.dart';
import 'features/materials/materials_controller.dart';
import 'features/shell/app_shell.dart';
import 'features/transport/location_tracker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifications.init();
  try {
    await Workmanager().initialize(materialsCallbackDispatcher);
    await WorkmanagerMaterialsScheduler().ensurePeriodic();
  } catch (_) {
    // Desktop and tests have no WorkManager. The in-process queue still runs.
  }
  final api = ApiClient();
  final session = Session(api);
  final tracker = LocationTracker(api);
  final materials = await MaterialsController.open(api);
  String? seenToken;
  var haveToken = false;
  session.addListener(() {
    final token = session.state == SessionState.signedIn ? api.token : null;
    if (haveToken && token == seenToken) return;
    haveToken = true;
    seenToken = token;
    unawaited(materials.rememberToken(token));
  });
  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: api),
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: tracker),
        ChangeNotifierProvider.value(value: materials),
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
        SessionState.loading => const _BootScreen(),
        SessionState.signedOut => const LoginScreen(),
        SessionState.signedIn => const AppShell(),
      },
    );
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Little Graduates',
                style: TextStyle(color: LgColors.accent, fontSize: 22, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 16),
              CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
