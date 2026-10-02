import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_graduates/core/privacy.dart';

void main() {
  for (final accept in [false, true]) {
    testWidgets('location consent returns $accept for the chosen action', (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () async { result = await requestTripLocationConsent(context); },
        child: const Text('Start trip'),
      )))));
      await tester.tap(find.text('Start trip'));
      await tester.pumpAndSettle();
      expect(find.textContaining('even when the app is in the background'), findsOneWidget);
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(result, isNull);
      await tester.tap(find.text(accept ? 'Agree and continue' : 'Not now'));
      await tester.pumpAndSettle();
      expect(result, accept);
    });
  }
}
