import 'package:compendium_app/src/widgets/app_closing_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

void main() {
  Future<void> pumpClosing(
    WidgetTester tester, {
    required bool disableAnimations,
  }) async {
    final closing = ValueNotifier(true);
    addTearDown(closing.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: AppClosingOverlay(closing: closing, child: child!),
        ),
        home: const SizedBox.shrink(),
      ),
    );
    // Not pumpAndSettle: the spinner never settles.
    await tester.pump();
  }

  testWidgets('shows a spinner while closing', (tester) async {
    await pumpClosing(tester, disableAnimations: false);

    expect(find.text('Closing…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets(
    'with Reduce motion on, shows a still icon instead of the spinner',
    (tester) async {
      await pumpClosing(tester, disableAnimations: true);

      expect(find.text('Closing…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
    },
  );
}
