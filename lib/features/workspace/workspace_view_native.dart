import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/config.dart';
import 'workspace_contract.dart';
import 'workspace_file_selector.dart';

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
  final _fileSelector = WorkspaceFileSelector();
  int _pageGeneration = 0;

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
            _pageGeneration++;
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
    _openWorkspace();
  }

  Future<void> _openWorkspace() async {
    try {
      final platform = _controller.platform;
      if (platform is AndroidWebViewController) {
        // Register before loading so even the first form can select files.
        // Keep the plugin's default denial of camera/microphone permissions.
        await platform.setOnShowFileSelector(_selectFiles);
      }
      if (!mounted) return;
      await _controller.loadRequest(
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
    } catch (_) {
      if (mounted) {
        widget.onEvent({
          'event': 'error',
          'message': 'Could not open this school tool. Please try again.',
        });
      }
    }
  }

  Future<List<String>> _selectFiles(FileSelectorParams params) async {
    if (!mounted) return [];
    final generation = _pageGeneration;
    try {
      final files = await _fileSelector.select(params);
      // A selection must not reach a replacement document or account.
      return mounted && generation == _pageGeneration ? files : [];
    } catch (_) {
      if (mounted && generation == _pageGeneration) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open that file. Please choose it again.'),
          ),
        );
      }
      return [];
    }
  }

  @override
  void dispose() {
    if (identical(widget.actions.back, _back)) widget.actions.back = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
