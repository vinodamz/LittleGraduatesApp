import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import 'workspace_contract.dart';
import 'workspace_view.dart';

/// Shared in-app home for MTT's complete forms, reports, and management tools.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({required this.url, required this.label, super.key});
  final String url;
  final String label;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final _actions = WorkspaceActions();
  Timer? _timeout;
  bool _loading = true;
  bool _canGoBack = false;
  String? _error;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _startTimeout();
  }

  void _startTimeout() {
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 30), () {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'This tool is taking too long. Check your connection and try again.';
        });
      }
    });
  }

  void _event(Map<String, dynamic> data) {
    if (!mounted) return;
    final session = context.read<Session>();
    if (data['event'] == 'ready' && data['userId'] != session.user?.id) {
      _fail('Your school account changed. Reopen this tool to continue.');
      return;
    }
    switch (data['event']) {
      case 'ready':
        _timeout?.cancel();
        setState(() {
          _loading = false;
          _error = null;
          _canGoBack = data['canGoBack'] == true;
        });
      case 'loading':
        setState(() => _loading = true);
        _startTimeout();
      case 'error':
        _fail(
          data['message'] as String? ?? 'Could not open this tool. Try again.',
        );
      case 'external':
        final uri = Uri.tryParse(data['url'] as String? ?? '');
        if (uri != null &&
            ['https', 'http', 'tel', 'mailto'].contains(uri.scheme)) {
          launchUrl(uri, mode: LaunchMode.externalApplication);
        }
    }
  }

  void _fail(String message) {
    _timeout?.cancel();
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  void _retry() {
    setState(() {
      _attempt++;
      _loading = true;
      _error = null;
      _canGoBack = false;
    });
    _startTimeout();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final valid = isSchoolUrl(widget.url) && session.api.token != null;
    final uri = Uri.tryParse(widget.url);
    final path = uri == null
        ? ''
        : '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
    final message = !valid ? 'Sign in again to open this school tool.' : _error;
    return PopScope(
      canPop: !_canGoBack || message != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _actions.back?.call();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close tool',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(widget.label),
          actions: [
            IconButton(
              tooltip: 'Previous page',
              onPressed: _canGoBack && message == null
                  ? () => _actions.back?.call()
                  : null,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            IconButton(
              tooltip: 'Reopen tool',
              onPressed: _retry,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (_loading && message == null)
                const LinearProgressIndicator(
                  semanticsLabel: 'Loading school tool',
                ),
              Expanded(
                child: message != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.cloud_off_rounded,
                                color: LgColors.muted,
                                size: 40,
                              ),
                              const SizedBox(height: 16),
                              Text(message, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: valid ? _retry : null,
                                child: const Text('Try again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : WorkspaceView(
                        key: ValueKey(_attempt),
                        token: session.api.token!,
                        path: path,
                        actions: _actions,
                        onEvent: _event,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
