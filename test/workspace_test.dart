import 'package:flutter_test/flutter_test.dart';
import 'package:little_graduates/core/module_registry.dart';
import 'package:little_graduates/core/session.dart';
import 'package:little_graduates/features/workspace/workspace_contract.dart';

void main() {
  test('all existing MTT modules open inside the app', () {
    for (final key in [
      'students',
      'montessori',
      'tasks',
      'crm',
      'fees',
      'expenses',
      'logbook',
      'inventory',
      'plans',
      'daycare',
      'recruitment',
    ]) {
      expect(
        moduleOpensInApp(
          AppModule(
            key: key,
            label: key,
            native: false,
            webUrl: 'https://mtt.thelittlegraduates.in/$key/index.php',
          ),
        ),
        isTrue,
      );
    }
  });
  test(
    'workspace rejects foreign and non-web destinations without throwing',
    () {
      for (final url in [
        '',
        '/fees/index.php',
        'javascript:alert(1)',
        'https://mtt.thelittlegraduates.in.attacker.test/fees/index.php',
        'http://mtt.thelittlegraduates.in/fees/index.php',
        'https://user@mtt.thelittlegraduates.in/fees/index.php',
        'https://mtt.thelittlegraduates.in:444/fees/index.php',
      ]) {
        expect(isSchoolUrl(url), isFalse, reason: url);
      }
    },
  );
  test('bridge uses a form POST and escapes values instead of token URLs', () {
    final html = workspaceBootstrap(
      'test-token',
      '/students/view.php?id=4&name="<script>',
    );
    expect(html, contains('method="post"'));
    expect(
      html,
      contains('action="https://mtt.thelittlegraduates.in/app/open.php"'),
    );
    expect(html, contains('name="token" value="test-token"'));
    expect(html, contains('&amp;name=&quot;&lt;script&gt;'));
    expect(html, isNot(contains('?token=')));
  });
}
