import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_graduates/core/api_client.dart';
import 'package:little_graduates/core/session.dart';
import 'package:little_graduates/features/workspace/workspace_screen.dart';
import 'package:provider/provider.dart';
// The platform fake exercises the real workspace widget without a device.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class TestSession extends Session {
  TestSession() : super(ApiClient()) {
    changeAccount(7, 'first-token');
  }
  void changeAccount(int id, String token) {
    api.token = token;
    user = AppUser(id: id, name: 'Fixture', role: 'teacher');
    state = SessionState.signedIn;
    notifyListeners();
  }
}

class TestPlatform extends WebViewPlatform {
  final controllers = <TestController>[];
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = TestController(params);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => TestDelegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => TestView(params);
}

class TestController extends PlatformWebViewController {
  TestController(super.params) : super.implementation();
  JavaScriptChannelParams? channel;
  TestDelegate? delegate;
  LoadRequestParams? request;
  final scripts = <String>[];
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channel = params;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    delegate = handler as TestDelegate;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    request = params;
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    scripts.add(javaScript);
  }

  void message(Map<String, dynamic> data) {
    channel!.onMessageReceived(
      JavaScriptMessage(message: jsonEncode({'type': 'lg-workspace', ...data})),
    );
  }

  void ready({int userId = 7, bool canGoBack = false}) =>
      message({'event': 'ready', 'userId': userId, 'canGoBack': canGoBack});
}

class TestDelegate extends PlatformNavigationDelegate {
  TestDelegate(super.params) : super.implementation();
  NavigationRequestCallback? navigate;
  PageEventCallback? started;
  WebResourceErrorCallback? failed;
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {
    navigate = callback;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {
    started = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {
    failed = callback;
  }
}

class TestView extends PlatformWebViewWidget {
  TestView(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) =>
      const SizedBox(key: Key('fixture-webview'));
}

void main() {
  late TestPlatform platform;
  late TestSession session;
  setUp(() {
    platform = TestPlatform();
    WebViewPlatform.instance = platform;
    session = TestSession();
  });
  Future<void> open(
    WidgetTester tester, {
    String path = '/fees/index.php',
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          home: WorkspaceScreen(
            url: 'https://mtt.thelittlegraduates.in$path',
            label: 'Fees',
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('POST bridge, loading, internal back, and timeout retry', (
    tester,
  ) async {
    await open(tester);
    final first = platform.controllers.single;
    expect(first.request!.method, LoadRequestMethod.post);
    expect(first.request!.uri.query, isEmpty);
    expect(Uri.splitQueryString(utf8.decode(first.request!.body!)), {
      'token': 'first-token',
      'path': '/fees/index.php',
    });
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    first.ready(canGoBack: true);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.byTooltip('Previous page'));
    expect(first.scripts, contains('history.back()'));
    first.delegate!.started!(
      'https://mtt.thelittlegraduates.in/fees/student.php',
    );
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(platform.controllers, hasLength(2));
    platform.controllers.last.ready();
    await tester.pump();
    expect(find.text('Try again'), findsNothing);
    await close(tester);
  });

  testWidgets('account change discards old webview and posts new credentials', (
    tester,
  ) async {
    await open(tester);
    platform.controllers.single.ready(canGoBack: true);
    await tester.pump();
    session.changeAccount(8, 'second-token');
    await tester.pump();
    expect(platform.controllers, hasLength(2));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      Uri.splitQueryString(
        utf8.decode(platform.controllers.last.request!.body!),
      )['token'],
      'second-token',
    );
    platform.controllers.first
        .ready(); // An old frame must not affect the new one.
    platform.controllers.last.ready(userId: 8);
    await tester.pump();
    expect(find.textContaining('account changed'), findsNothing);
    await close(tester);
  });

  testWidgets('a changed destination replaces the embedded page', (
    tester,
  ) async {
    await open(tester);
    platform.controllers.single.ready();
    await tester.pump();
    await open(tester, path: '/students/index.php');
    expect(platform.controllers, hasLength(2));
    expect(
      Uri.splitQueryString(
        utf8.decode(platform.controllers.last.request!.body!),
      )['path'],
      '/students/index.php',
    );
    await close(tester);
  });

  testWidgets('malformed bridge payloads cannot crash the tool', (
    tester,
  ) async {
    await open(tester);
    final controller = platform.controllers.single;
    expect(
      () => controller.message({'event': 'external', 'url': 12}),
      returnsNormally,
    );
    expect(
      () => controller.message({
        'event': 'error',
        'message': {'bad': true},
      }),
      returnsNormally,
    );
    await tester.pump();
    expect(find.text('Could not open this tool. Try again.'), findsOneWidget);
    await close(tester);
  });

  testWidgets(
    'wrong account is rejected and resource errors remain retryable',
    (tester) async {
      await open(tester);
      platform.controllers.single.ready(userId: 99);
      await tester.pump();
      expect(find.textContaining('account changed'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      final controller = platform.controllers.last;
      controller.delegate!.failed!(
        const WebResourceError(
          errorCode: -2,
          description: 'offline',
          isForMainFrame: false,
        ),
      );
      await tester.pump();
      expect(find.text('Try again'), findsNothing);
      controller.delegate!.failed!(
        const WebResourceError(
          errorCode: -2,
          description: 'offline',
          isForMainFrame: true,
        ),
      );
      await tester.pump();
      expect(find.textContaining('Could not reach'), findsOneWidget);
      await close(tester);
    },
  );
  testWidgets(
    'replacement preserves back action and Close returns to the app',
    (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const WorkspaceScreen(
                        url: 'https://mtt.thelittlegraduates.in/fees/index.php',
                        label: 'Fees',
                      ),
                    ),
                  ),
                  child: const Text('Open fixture'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open fixture'));
      await tester.pump();
      platform.controllers.single.ready(canGoBack: true);
      await tester.pumpAndSettle();
      session.changeAccount(8, 'second-token');
      await tester.pump();
      final replacement = platform.controllers.last;
      replacement.ready(userId: 8, canGoBack: true);
      await tester.pump();
      await tester.tap(find.byTooltip('Previous page'));
      expect(replacement.scripts, contains('history.back()'));
      await tester.tap(find.byTooltip('Close tool'));
      await tester.pumpAndSettle();
      expect(find.text('Open fixture'), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets('external launch failures keep the form and show an error', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final launched = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      launched.add((call.arguments as Map)['url'] as String);
      return false;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await open(tester);
    final controller = platform.controllers.single;
    controller.ready();
    await tester.pump();
    controller.message({
      'event': 'external',
      'url': 'mailto:fixture@example.test',
    });
    await tester.pump();
    expect(launched, ['mailto:fixture@example.test']);
    expect(
      find.text('Could not open this link on your device.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('fixture-webview')), findsOneWidget);
    launched.clear();
    expect(
      await controller.delegate!.navigate!(
        const NavigationRequest(
          url: 'https://outside.test/frame',
          isMainFrame: false,
        ),
      ),
      NavigationDecision.prevent,
    );
    await tester.pump();
    expect(launched, isEmpty, reason: 'Subframes must not open external apps');
    expect(
      await controller.delegate!.navigate!(
        const NavigationRequest(
          url: 'https://mtt.thelittlegraduates.in/login.php',
          isMainFrame: true,
        ),
      ),
      NavigationDecision.prevent,
    );
    await tester.pump();
    expect(find.textContaining('Your session ended'), findsOneWidget);
    await close(tester);
  });
  testWidgets(
    'integration handoff preserves the tool, Back, and loading state',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final launches = <Map>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        launches.add(call.arguments as Map);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await open(tester, path: '/wacrm/index.php');
      final controller = platform.controllers.single;
      controller.ready(canGoBack: true);
      await tester.pump();
      controller.message({
        'event': 'external',
        'userId': 7,
        'url': 'https://fixture-crm.test/api/sso/mtt?token=fixture-sso',
      });
      await tester.pump();
      expect(launches, hasLength(1));
      expect(
        launches.single['url'],
        'https://fixture-crm.test/api/sso/mtt?token=fixture-sso',
      );
      expect(launches.single['headers'], isEmpty);
      expect(jsonEncode(launches), isNot(contains('first-token')));
      expect(find.byKey(const Key('fixture-webview')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.byTooltip('Previous page'));
      expect(controller.scripts, contains('history.back()'));
      await tester.pump(const Duration(seconds: 31));
      expect(find.text('Try again'), findsNothing);
      expect(platform.controllers, hasLength(1));
      await close(tester);
    },
  );
}
