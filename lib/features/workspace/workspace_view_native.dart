import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/config.dart';
import 'workspace_contract.dart';

class WorkspaceView extends StatefulWidget {
  const WorkspaceView({
    required this.token,
    required this.path,
    required this.actions,
    required this.onEvent,
    super.key,
  });
  final String token;
  final String path;
  final WorkspaceActions actions;
  final void Function(Map<String, dynamic>) onEvent;

  @override
  State<WorkspaceView> createState() => _WorkspaceViewState();
}

class _WorkspaceViewState extends State<WorkspaceView> {
  late final WebViewController _controller;
  late final void Function() _back;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'LGWorkspace',
        onMessageReceived: (message) {
          try {
            final decoded = jsonDecode(message.message);
            if (decoded is! Map<String, dynamic>) return;
            final data = decoded;
            if (mounted && data['type'] == 'lg-workspace') widget.onEvent(data);
          } on FormatException {
            /* Ignore malformed page messages. */
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (isSchoolUrl(request.url) &&
                request.isMainFrame &&
                [
                  '/login.php',
                  '/logout.php',
                ].contains(Uri.parse(request.url).path)) {
              if (mounted) {
                widget.onEvent({
                  'event': 'error',
                  'message':
                      'Your session ended. Close this tool and sign in again.',
                });
              }
              return NavigationDecision.prevent;
            }
            if (isSchoolUrl(request.url) || request.url == 'about:blank') {
              return NavigationDecision.navigate;
            }
            final uri = Uri.tryParse(request.url);
            if (mounted &&
                request.isMainFrame &&
                uri != null &&
                ['https', 'http', 'tel', 'mailto'].contains(uri.scheme)) {
              widget.onEvent({'event': 'external', 'url': request.url});
            }
            return NavigationDecision.prevent;
          },
          onPageStarted: (_) {
            if (mounted) widget.onEvent({'event': 'loading'});
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              widget.onEvent({
                'event': 'error',
                'message':
                    'Could not reach this school tool. Check your connection and try again.',
              });
            }
          },
        ),
      );
    _back = () => _controller.runJavaScript('history.back()');
    widget.actions.back = _back;
    _controller.loadRequest(
      Uri.parse('${AppConfig.baseUrl}/app/open.php'),
      method: LoadRequestMethod.post,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: Uint8List.fromList(
        utf8.encode(
          Uri(
            queryParameters: {'token': widget.token, 'path': widget.path},
          ).query,
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (identical(widget.actions.back, _back)) widget.actions.back = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
