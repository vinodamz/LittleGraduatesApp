import 'dart:convert';

import '../../core/config.dart';

class WorkspaceActions {
  void Function()? back;
}

bool isSchoolUrl(String value) {
  final uri = Uri.tryParse(value);
  final base = Uri.parse(AppConfig.baseUrl);
  return uri != null &&
      uri.hasScheme &&
      uri.hasAuthority &&
      ['https', 'http'].contains(uri.scheme) &&
      uri.origin == base.origin &&
      uri.userInfo.isEmpty &&
      uri.path.startsWith('/') &&
      !uri.path.startsWith('//');
}

/// HTTPS form POST: no token in URLs, browser history, or referrers.
String workspaceBootstrap(String token, String path) {
  const escape = HtmlEscape(HtmlEscapeMode.attribute);
  final endpoint = escape.convert('${AppConfig.baseUrl}/app/open.php');
  return '''<!doctype html><html lang="en"><head><meta name="referrer" content="strict-origin"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body>
<form method="post" action="$endpoint"><input type="hidden" name="token" value="${escape.convert(token)}"><input type="hidden" name="path" value="${escape.convert(path)}"></form>
<script>document.forms[0].submit();</script></body></html>''';
}
