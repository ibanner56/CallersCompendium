import 'package:compendium_app/src/utils/undo_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a minimal Scaffold whose button shows an undo prompt via
/// [showUndoSnackBar], so we can exercise the helper's dismissal behavior in
/// isolation (issue #463).
Widget _harness({
  required bool accessibleNavigation,
  required VoidCallback onUndo,
  Duration duration = const Duration(seconds: 6),
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            key: const ValueKey('show'),
            onPressed: () => showUndoSnackBar(
              ScaffoldMessenger.of(context),
              key: const ValueKey('undo-snackbar'),
              message: 'Item deleted.',
              undoLabel: 'Undo',
              accessibleNavigation: accessibleNavigation,
              duration: duration,
              onUndo: onUndo,
            ),
            child: const Text('show'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _showAndAwaitEntrance(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('show')));
  await tester.pump(); // enqueue the snackbar
  await tester.pump(const Duration(milliseconds: 300)); // finish entrance
}

void main() {
  group('showUndoSnackBar', () {
    testWidgets('default path auto-dismisses after its duration', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          accessibleNavigation: false,
          onUndo: () {},
          duration: const Duration(seconds: 3),
        ),
      );
      await _showAndAwaitEntrance(tester);
      expect(find.text('Item deleted.'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      // Advance past the duration: the auto-dismiss timer fires and the exit
      // animation removes the prompt.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
      expect(find.text('Item deleted.'), findsNothing);
    });

    testWidgets('Undo remains tappable before the timeout and fires onUndo', (
      tester,
    ) async {
      var undone = 0;
      await tester.pumpWidget(
        _harness(
          accessibleNavigation: false,
          onUndo: () => undone++,
          duration: const Duration(seconds: 3),
        ),
      );
      await _showAndAwaitEntrance(tester);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(undone, 1);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('assistive path persists past its duration', (tester) async {
      await tester.pumpWidget(
        _harness(
          accessibleNavigation: true,
          onUndo: () {},
          duration: const Duration(seconds: 2),
        ),
      );
      await _showAndAwaitEntrance(tester);
      expect(find.text('Undo'), findsOneWidget);

      // Well beyond the duration: the timer fires but persist keeps the prompt
      // visible so assistive-tech users retain time to reach the action.
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('Undo'), findsOneWidget);

      // Dismiss it explicitly so the persisting prompt doesn't linger.
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('clears the current prompt so successive prompts do not stack', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          accessibleNavigation: false,
          onUndo: () {},
          duration: const Duration(seconds: 3),
        ),
      );
      await _showAndAwaitEntrance(tester);
      // Fire a second undoable action while the first prompt is still on screen.
      await tester.tap(find.byKey(const ValueKey('show')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
    });
  });
}
