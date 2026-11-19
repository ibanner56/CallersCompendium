import 'dart:async';

import 'package:compendium_app/src/data/undo_prompt_duration_scope.dart';
import 'package:compendium_app/src/utils/undo_snack_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a minimal Scaffold whose button shows an undo prompt via
/// [showUndoSnackBar], so we can exercise the helper's dismissal behavior in
/// isolation (issue #463).
Widget _harness({
  required bool accessibleNavigation,
  required FutureOr<void> Function() onUndo,
  Duration? duration = const Duration(seconds: 6),
  ValueNotifier<int>? undoSeconds,
}) {
  final app = MaterialApp(
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
              undoFailedMessage: 'Undo failed.',
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
  // Above MaterialApp, where the app mounts it: the prompt reads it from the
  // ScaffoldMessenger's context.
  return undoSeconds == null
      ? app
      : UndoPromptDurationScope(notifier: undoSeconds, child: app);
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
      // Settled, so a prompt that had started to leave would be gone.
      await tester.pumpAndSettle();
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

    testWidgets('an Undo that throws asynchronously says it failed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          accessibleNavigation: false,
          onUndo: () async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            throw StateError('disk full');
          },
        ),
      );
      await _showAndAwaitEntrance(tester);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      // Reported, not escaped to the zone: the test would fail on an uncaught
      // async error.
      expect(
        find.byKey(const ValueKey('undo-failed-snackbar')),
        findsOneWidget,
      );
      expect(find.text('Undo failed.'), findsOneWidget);
      expect(find.text('Item deleted.'), findsNothing);
    });

    testWidgets('an Undo that throws synchronously says it failed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          accessibleNavigation: false,
          onUndo: () => throw StateError('locked'),
        ),
      );
      await _showAndAwaitEntrance(tester);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Undo failed.'), findsOneWidget);
    });

    testWidgets('an Undo that succeeds shows no failure message', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(accessibleNavigation: false, onUndo: () async {}),
      );
      await _showAndAwaitEntrance(tester);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Undo failed.'), findsNothing);
    });
  });

  group('showUndoSnackBar timing', () {
    testWidgets('takes its duration from the Undo prompt setting', (
      tester,
    ) async {
      final seconds = ValueNotifier<int>(15);
      addTearDown(seconds.dispose);
      await tester.pumpWidget(
        _harness(
          accessibleNavigation: false,
          onUndo: () {},
          duration: null,
          undoSeconds: seconds,
        ),
      );
      await _showAndAwaitEntrance(tester);

      // Past the 10-second default, inside the chosen 15.
      await tester.pump(const Duration(seconds: 12));
      // Settled, so a prompt that had started to leave would be gone.
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('the shortest choice counts from when the prompt is fully in', (
      tester,
    ) async {
      final seconds = ValueNotifier<int>(2);
      addTearDown(seconds.dispose);
      await tester.pumpWidget(
        _harness(
          accessibleNavigation: false,
          onUndo: () {},
          duration: null,
          undoSeconds: seconds,
        ),
      );
      await _showAndAwaitEntrance(tester);

      // 1.8 s after the entrance ended, 2.1 s after it began: a timer that
      // started with the entrance would have sent it out by now.
      await tester.pump(const Duration(milliseconds: 1800));
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).animation!.status,
        AnimationStatus.completed,
        reason: 'still fully in, not on its way out',
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets(
      '"Until I close it" never times out and offers a close button',
      (tester) async {
        final seconds = ValueNotifier<int>(kUndoPromptUntilDismissed);
        addTearDown(seconds.dispose);
        await tester.pumpWidget(
          _harness(
            accessibleNavigation: false,
            onUndo: () {},
            duration: null,
            undoSeconds: seconds,
          ),
        );
        await _showAndAwaitEntrance(tester);

        await tester.pump(const Duration(minutes: 10));
        // Settled, so a prompt that had started to leave would be gone.
        await tester.pumpAndSettle();
        expect(find.text('Undo'), findsOneWidget);

        final close = find.descendant(
          of: find.byType(SnackBar),
          matching: find.byIcon(Icons.close),
        );
        expect(close, findsOneWidget);
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(find.text('Undo'), findsNothing);
      },
    );

    testWidgets('a timed prompt shows no close button', (tester) async {
      await tester.pumpWidget(
        _harness(accessibleNavigation: false, onUndo: () {}),
      );
      await _showAndAwaitEntrance(tester);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byIcon(Icons.close),
        ),
        findsNothing,
      );
      await tester.pumpAndSettle(const Duration(seconds: 7));
    });

    testWidgets(
      'stays while a mouse hovers it, and times out after it leaves',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            accessibleNavigation: false,
            onUndo: () {},
            duration: const Duration(seconds: 3),
          ),
        );
        await _showAndAwaitEntrance(tester);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.text('Item deleted.')));
        await tester.pump();

        // Far past its time while the pointer rests on it.
        await tester.pump(const Duration(seconds: 30));
        // Settled, so a prompt that had started to leave would be gone.
        await tester.pumpAndSettle();
        expect(find.text('Undo'), findsOneWidget);

        // Off the prompt: its full time starts again, then it goes.
        await mouse.moveTo(Offset.zero);
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Undo'), findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(find.text('Undo'), findsNothing);
      },
    );

    testWidgets('hovering the Undo button itself also holds it', (
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

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Undo')));
      await tester.pump(const Duration(seconds: 30));
      // Settled, so a prompt that had started to leave would be gone.
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsOneWidget);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('stays while keyboard focus is on Undo, and times out after', (
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

      final undoText = tester.element(find.text('Undo'));
      final undoFocus = Focus.of(undoText);
      undoFocus.requestFocus();
      await tester.pump();
      expect(undoFocus.hasPrimaryFocus, isTrue);

      await tester.pump(const Duration(seconds: 30));
      // Settled, so a prompt that had started to leave would be gone.
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsOneWidget);

      // Focus moves elsewhere: the full time starts again, then it goes.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Undo'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('a touch on the prompt does not hold it', (tester) async {
      await tester.pumpWidget(
        _harness(
          accessibleNavigation: false,
          onUndo: () {},
          duration: const Duration(seconds: 3),
        ),
      );
      await _showAndAwaitEntrance(tester);

      final finger = await tester.startGesture(
        tester.getCenter(find.text('Item deleted.')),
      );
      await finger.moveBy(const Offset(1, 0));
      await tester.pump(const Duration(seconds: 4));
      await finger.up();
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
    });
  });

  group('showUndoSnackBar across prompts and routes', () {
    testWidgets('a second prompt with the same key gets its own full time', (
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
      await tester.pump(const Duration(seconds: 2));

      // The second prompt, same key, two seconds into the first one's three.
      await tester.tap(find.byKey(const ValueKey('show')));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsOneWidget);

      // Past where the first prompt's time would have run out.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
    });

    Future<void> pumpPushed(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              // A Scaffold under the route, with a bar that lifts its copy
              // of the prompt above where the visible copy sits.
              bottomNavigationBar: NavigationBar(
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.home), label: 'a'),
                  NavigationDestination(icon: Icon(Icons.star), label: 'b'),
                ],
              ),
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => Scaffold(
                      body: Center(
                        child: ElevatedButton(
                          key: const ValueKey('show'),
                          onPressed: () => showUndoSnackBar(
                            ScaffoldMessenger.of(context),
                            message: 'Item deleted.',
                            undoLabel: 'Undo',
                            undoFailedMessage: 'Undo failed.',
                            accessibleNavigation: false,
                            duration: const Duration(seconds: 3),
                            onUndo: () {},
                          ),
                          child: const Text('show'),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _showAndAwaitEntrance(tester);
    }

    testWidgets('focus holds it with another Scaffold under the route', (
      tester,
    ) async {
      await pumpPushed(tester);
      final undoFocus = Focus.of(tester.element(find.text('Undo').last));
      undoFocus.requestFocus();
      await tester.pump();

      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsWidgets);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('hover holds it with another Scaffold under the route', (
      tester,
    ) async {
      await pumpPushed(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      // The visible copy: the last one built is on the top route.
      await mouse.moveTo(tester.getCenter(find.text('Item deleted.').last));
      await tester.pump();

      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsWidgets);

      // Onto where the copy under the route sits: unseen, so it holds nothing.
      final hidden = tester.getCenter(
        find.text('Item deleted.', skipOffstage: false).first,
      );
      final shown = tester.getRect(find.text('Item deleted.').last);
      expect(shown.contains(hidden), isFalse);
      await mouse.moveTo(hidden);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
    });
  });
}
