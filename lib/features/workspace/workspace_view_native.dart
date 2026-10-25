import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'LGWorkspace',
        onMessageReceived: (message) {
          try {
            final data = jsonDecode(message.message) as Map<String, dynamic>;
            if (mounted && data['type'] == 'lg-workspace') widget.onEvent(data);
          } on FormatException {
            /* Ignore malformed page messages. */
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (isSchoolUrl(request.url) || request.url == 'about:blank') {
              return NavigationDecision.navigate;
            }
            final uri = Uri.tryParse(request.url);
            if (uri != null &&
                ['https', 'http', 'tel', 'mailto'].contains(uri.scheme)) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
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
    widget.actions.back = () => _controller.runJavaScript('history.back()');
    _controller.loadHtmlString(
      workspaceBootstrap(widget.token, widget.path),
      baseUrl: AppConfig.baseUrl,
    );
  }

  @override
  void dispose() {
    widget.actions.back = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
