import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../core/config.dart';
import 'workspace_contract.dart';

// Dart object equality can inspect cross-origin Window properties. Compare
// the underlying browser objects directly instead.
@JS('Object.is')
external bool _sameWindow(JSAny? a, JSAny? b);

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
  web.HTMLIFrameElement? _frame;
  late final JSFunction _listener;

  @override
  void initState() {
    super.initState();
    _listener = ((web.MessageEvent event) {
      final frame = _frame;
      if (frame == null ||
          event.origin != Uri.parse(AppConfig.baseUrl).origin ||
          !_sameWindow(event.source, frame.contentWindow)) {
        return;
      }
      final raw = event.data.dartify();
      if (raw is Map && raw['type'] == 'lg-workspace') {
        widget.onEvent(Map<String, dynamic>.from(raw));
      }
    }).toJS;
    web.window.addEventListener('message', _listener);
    widget.actions.back = () => _frame?.contentWindow?.postMessage(
      <String, String>{'type': 'lg-workspace-back'}.jsify(),
      Uri.parse(AppConfig.baseUrl).origin.toJS,
    );
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    widget.actions.back = null;
    _frame?.src = 'about:blank';
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (element) {
      final frame = element as web.HTMLIFrameElement;
      _frame = frame;
      frame.title = 'School tool';
      frame.style
        ..border = '0'
        ..width = '100%'
        ..height = '100%';
      // no-referrer makes form POSTs send Origin: null, which MTT rejects.
      // Send only the app origin; credentials remain in the HTTPS POST body.
      frame.setAttribute('referrerpolicy', 'strict-origin');
      // MTT Materials has voice notes; access still requires browser consent.
      frame.setAttribute(
        'allow',
        'microphone ${Uri.parse(AppConfig.baseUrl).origin}',
      );
      frame.setAttribute(
        'sandbox',
        'allow-scripts allow-same-origin allow-forms allow-modals allow-downloads allow-popups allow-popups-to-escape-sandbox',
      );
      frame.srcdoc = workspaceBootstrap(widget.token, widget.path).toJS;
    },
  );
}
