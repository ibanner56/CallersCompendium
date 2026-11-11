import 'package:compendium_app/src/widgets/app_closing_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('keystrokes no longer reach a field that had focus (A11Y-6)', (
    tester,
  ) async {
    final closing = ValueNotifier(false);
    addTearDown(closing.dispose);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        builder: (context, child) =>
            AppClosingOverlay(closing: closing, child: child!),
        home: Scaffold(
          body: TextField(controller: controller, focusNode: focus),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'before');
    expect(focus.hasFocus, isTrue);

    closing.value = true;
    await tester.pump();

    // What was typed before the overlay stays in the controller, where the
    // draft flush reads it.
    expect(controller.text, 'before');
    expect(focus.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(controller.text, 'before');
    // Nothing behind the barrier can take focus back, by Tab either.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focus.hasFocus, isFalse);
  });
}
