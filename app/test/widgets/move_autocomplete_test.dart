import 'package:compendium_app/src/editor/pending_move_text_controller.dart';
import 'package:compendium_app/src/widgets/move_autocomplete.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/screen_size.dart';

/// A dialect that renames the canonical `swing` move to "buzz", exercising the
/// editor's requirement that the move picker both displays and matches dialect
/// vocabulary (not just canonical taxonomy names).
final _buzzDialect = Dialect(name: 'Custom', moves: const {'swing': 'buzz'});

Future<void> _pump(
  WidgetTester tester, {
  Dialect? dialect,
  ValueChanged<MoveOption>? onSelected,
  ValueChanged<String>? onCustomSubmitted,
  bool Function(String text)? submitsAsText,
  List<MoveOption> compoundOptions = const [],
  bool includeModifier = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MoveAutocomplete(
          taxonomy: contraTaxonomy,
          dialect: dialect,
          initialText: '',
          fieldKey: 'move',
          onSelected: onSelected ?? (_) {},
          onCustomSubmitted: onCustomSubmitted,
          submitsAsText: submitsAsText,
          compoundOptions: compoundOptions,
          includeModifier: includeModifier,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('matches and displays a dialect move substitution', (
    tester,
  ) async {
    await _pump(tester, dialect: _buzzDialect);
    // Typing the dialect term surfaces the underlying move as "buzz".
    await tester.enterText(find.byKey(const ValueKey('move-input')), 'buzz');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('move-option-swing')), findsOneWidget);
    expect(find.text('buzz'), findsWidgets);
    expect(find.text('swing'), findsNothing);
  });

  testWidgets('shows canonical names under the canonical dialect', (
    tester,
  ) async {
    await _pump(tester, dialect: Dialect.canonical);
    await tester.enterText(find.byKey(const ValueKey('move-input')), 'swing');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('move-option-swing')), findsOneWidget);
    expect(find.text('swing'), findsWidgets);
    // The dialect term isn't shown when the active dialect is canonical.
    expect(find.text('buzz'), findsNothing);
  });

  group('indistinguishable aliases', () {
    testWidgets('offers a single "pull by" for the move and its v34 aliases', (
      tester,
    ) async {
      await _pump(tester);
      await tester.enterText(find.byKey(const ValueKey('move-input')), 'pull');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('move-option-pull_by')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('move-option-pull_by_dancers')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('move-option-pull_by_direction')),
        findsNothing,
      );
      expect(find.text('pull by'), findsOneWidget);
    });

    testWidgets('submitting "pull by" still selects the canonical move', (
      tester,
    ) async {
      MoveOption? picked;
      await _pump(tester, onSelected: (o) => picked = o);
      await tester.enterText(
        find.byKey(const ValueKey('move-input')),
        'pull by',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(picked?.id, 'pull_by');
    });

    testWidgets('still offers an alias whose label differs from its move', (
      tester,
    ) async {
      await _pump(tester);
      await tester.enterText(
        find.byKey(const ValueKey('move-input')),
        'seesaw',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('move-option-see_saw')), findsOneWidget);
    });

    testWidgets('never hides a move that shares a dialect term with another', (
      tester,
    ) async {
      final dialect = Dialect(
        name: 'Custom',
        moves: const {'swing': 'buzz', 'balance': 'buzz'},
      );
      await _pump(tester, dialect: dialect);
      await tester.enterText(find.byKey(const ValueKey('move-input')), 'buzz');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('move-option-swing')), findsOneWidget);
      expect(find.byKey(const ValueKey('move-option-balance')), findsOneWidget);
    });
  });

  testWidgets('offers a structural modifier option when enabled', (
    tester,
  ) async {
    MoveOption? picked;
    await _pump(
      tester,
      includeModifier: true,
      onSelected: (option) => picked = option,
    );

    await tester.enterText(
      find.byKey(const ValueKey('move-input')),
      'modifier',
    );
    await tester.pumpAndSettle();

    final option = find.byKey(const ValueKey('move-option-modifier'));
    expect(option, findsOneWidget);
    await tester.tap(option);
    await tester.pumpAndSettle();

    expect(picked?.id, modifierMove);
    expect(picked?.kind, MoveOptionKind.modifier);
  });

  group('narrow layout (issue #716)', () {
    testWidgets('tapping the field opens a sheet and picking an option above a '
        'simulated keyboard still selects the move', (tester) async {
      MoveOption? picked;
      await setScreenSize(tester, const Size(360, 720));
      await _pump(tester, onSelected: (o) => picked = o);

      await tester.tap(
        find.byKey(const ValueKey('move-input')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);

      // Simulate a software keyboard inset, as issue #716 describes.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('move-input')), 'swing');
      await tester.pumpAndSettle();

      final optionFinder = find.byKey(const ValueKey('move-option-swing'));
      expect(optionFinder, findsOneWidget);
      // The option sits above the simulated keyboard inset, not hidden
      // underneath it.
      final optionRect = tester.getRect(optionFinder);
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(optionRect.bottom, lessThanOrEqualTo(screenHeight - 300));

      await tester.tap(optionFinder);
      await tester.pumpAndSettle();

      expect(picked?.id, 'swing');
      // The sheet closes after the pick.
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('free-text submission of an unmatched move still fires '
        'onCustomSubmitted from inside the sheet', (tester) async {
      String? custom;
      await setScreenSize(tester, const Size(360, 720));
      await _pump(tester, onCustomSubmitted: (v) => custom = v);

      await tester.tap(
        find.byKey(const ValueKey('move-input')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('move-input')),
        'a brand new move',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(custom, 'a brand new move');
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  // October behaviour audit, AUTH-8: Enter used to take the first option whose
  // name merely contained the text.
  group('Enter chooses', () {
    Future<(MoveOption?, String?)> submit(
      WidgetTester tester,
      String text, {
      bool Function(String text)? submitsAsText,
      List<MoveOption> compoundOptions = const [],
    }) async {
      MoveOption? picked;
      String? custom;
      await _pump(
        tester,
        onSelected: (o) => picked = o,
        onCustomSubmitted: (v) => custom = v,
        submitsAsText: submitsAsText,
        compoundOptions: compoundOptions,
      );
      await tester.enterText(find.byKey(const ValueKey('move-input')), text);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      return (picked, custom);
    }

    testWidgets('the move named exactly, not the first containing it', (
      tester,
    ) async {
      final (picked, custom) = await submit(tester, 'star');
      expect(picked?.id, 'star');
      expect(custom, isNull);
    });

    testWidgets('the app\'s move over your figure that contains its name', (
      tester,
    ) async {
      final (picked, _) = await submit(
        tester,
        'Hey',
        compoundOptions: const [
          MoveOption(
            id: 'twist',
            displayName: 'Hey with a twist',
            kind: MoveOptionKind.compound,
          ),
        ],
      );
      expect(picked?.id, 'hey');
    });

    testWidgets('your figure when you name it exactly', (tester) async {
      final (picked, _) = await submit(
        tester,
        'hey with a twist',
        compoundOptions: const [
          MoveOption(
            id: 'twist',
            displayName: 'Hey with a twist',
            kind: MoveOptionKind.compound,
          ),
        ],
      );
      expect(picked?.id, 'twist');
    });

    testWidgets('a shorthand as typed, not the move containing it', (
      tester,
    ) async {
      final (picked, custom) = await submit(
        tester,
        'rl',
        submitsAsText: (text) => text == 'rl',
      );
      expect(picked, isNull);
      expect(custom, 'rl');
    });

    testWidgets('an exact name over a shorthand with the same token', (
      tester,
    ) async {
      final (picked, custom) = await submit(
        tester,
        'swing',
        submitsAsText: (_) => true,
      );
      expect(picked?.id, 'swing');
      expect(custom, isNull);
    });

    testWidgets('otherwise the first option, as before', (tester) async {
      final (picked, _) = await submit(tester, 'sw');
      expect(picked?.id, 'swing');
    });
  });

  // October behaviour audit, AUTH-1, maintainer decision AUTH-1-move-blur =
  // (a): leaving a row's Move box without Enter applies an exact move name or
  // shorthand, as Enter would, and puts anything else back.
  group('leaving the box (AUTH-1)', () {
    /// A Move box over a row that holds [rowMove], with a second field to move
    /// focus to. The row takes what the box applies, as a figure row does, so
    /// the box is rebuilt with it.
    Future<
      ({
        List<MoveOption> picked,
        List<String> custom,
        PendingMoveTextController pending,
      })
    >
    pumpRow(
      WidgetTester tester, {
      String rowMove = 'balance',
      bool commitOnBlur = true,
      bool Function(String text)? submitsAsText,
    }) async {
      final picked = <MoveOption>[];
      final custom = <String>[];
      final pending = PendingMoveTextController();
      addTearDown(pending.dispose);
      var current = rowMove;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendingMoveTextScope(
              controller: pending,
              child: StatefulBuilder(
                builder: (context, setState) => Column(
                  children: [
                    MoveAutocomplete(
                      taxonomy: contraTaxonomy,
                      initialText: current,
                      fieldKey: 'move',
                      commitOnBlur: commitOnBlur,
                      submitsAsText: submitsAsText,
                      onSelected: (o) {
                        picked.add(o);
                        setState(() => current = o.displayName);
                      },
                      onCustomSubmitted: (text) {
                        custom.add(text);
                        setState(() => current = text);
                      },
                    ),
                    const TextField(key: ValueKey('elsewhere')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return (picked: picked, custom: custom, pending: pending);
    }

    Finder box() => find.byKey(const ValueKey('move-input'));

    String boxText(WidgetTester tester) =>
        tester.widget<TextField>(box()).controller!.text;

    Future<void> typeThenLeave(WidgetTester tester, String text) async {
      await tester.enterText(box(), text);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('elsewhere')));
      await tester.pumpAndSettle();
    }

    testWidgets('applies the move named exactly', (tester) async {
      final row = await pumpRow(tester);
      await typeThenLeave(tester, 'star');
      expect([for (final o in row.picked) o.id], ['star']);
      expect(boxText(tester), 'star');
    });

    testWidgets('puts back text that only part of a name matches', (
      tester,
    ) async {
      final row = await pumpRow(tester);
      await typeThenLeave(tester, 'sw');
      expect(row.picked, isEmpty);
      expect(row.custom, isEmpty);
      expect(boxText(tester), 'balance');
    });

    testWidgets('puts back text that matches nothing, rather than making a '
        'custom figure', (tester) async {
      final row = await pumpRow(tester);
      await typeThenLeave(tester, 'scoop them up');
      expect(row.custom, isEmpty);
      expect(boxText(tester), 'balance');
    });

    testWidgets('applies a shorthand', (tester) async {
      final row = await pumpRow(tester, submitsAsText: (t) => t == 'rl');
      await typeThenLeave(tester, 'rl');
      expect(row.picked, isEmpty);
      expect(row.custom, ['rl']);
    });

    testWidgets('does nothing when the box is not set to', (tester) async {
      final row = await pumpRow(tester, commitOnBlur: false);
      await typeThenLeave(tester, 'star');
      expect(row.picked, isEmpty);
      expect(boxText(tester), 'star');
    });

    testWidgets('after Enter, applies nothing a second time', (tester) async {
      final row = await pumpRow(tester);
      await tester.enterText(box(), 'star');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final afterEnter = row.picked.length;
      expect(row.picked.last.id, 'star');

      await tester.tap(find.byKey(const ValueKey('elsewhere')));
      await tester.pumpAndSettle();
      expect(row.picked, hasLength(afterEnter));
    });

    testWidgets('after Enter on a shorthand, applies it only once', (
      tester,
    ) async {
      final row = await pumpRow(tester, submitsAsText: (t) => t == 'rl');
      await tester.enterText(box(), 'rl');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('elsewhere')));
      await tester.pumpAndSettle();
      expect(row.custom, ['rl']);
    });

    testWidgets('a choice from the options wins over the exact name typed', (
      tester,
    ) async {
      final row = await pumpRow(tester);
      await tester.enterText(box(), 'star');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('move-option-star_through')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('elsewhere')));
      await tester.pumpAndSettle();
      expect([for (final o in row.picked) o.id], ['star_through']);
    });

    testWidgets('tells the scope while text would apply, and the scope can '
        'settle it', (tester) async {
      final row = await pumpRow(tester);
      await tester.tap(box());
      await tester.enterText(box(), 'sw');
      await tester.pumpAndSettle();
      expect(row.pending.hasPendingText, isFalse);
      await tester.enterText(box(), 'star');
      await tester.pumpAndSettle();
      expect(row.pending.hasPendingText, isTrue);

      row.pending.settle();
      await tester.pumpAndSettle();
      expect([for (final o in row.picked) o.id], ['star']);
      expect(row.pending.hasPendingText, isFalse);
    });

    group('on a phone', () {
      Future<void> openSheet(WidgetTester tester) async {
        await tester.tap(box(), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
      }

      Future<void> closeSheet(WidgetTester tester) async {
        // The barrier above the sheet, as a tap outside it.
        await tester.tapAt(const Offset(180, 20));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
      }

      testWidgets('opening the sheet changes nothing', (tester) async {
        await setScreenSize(tester, const Size(360, 720));
        final row = await pumpRow(tester);
        await openSheet(tester);
        await closeSheet(tester);
        expect(row.picked, isEmpty);
        expect(boxText(tester), 'balance');
      });

      testWidgets('closing the sheet applies the move named exactly', (
        tester,
      ) async {
        await setScreenSize(tester, const Size(360, 720));
        final row = await pumpRow(tester);
        await openSheet(tester);
        await tester.enterText(box(), 'star');
        await tester.pumpAndSettle();
        await closeSheet(tester);
        expect([for (final o in row.picked) o.id], ['star']);
      });

      testWidgets('closing the sheet drops text that only part of a name '
          'matches', (tester) async {
        await setScreenSize(tester, const Size(360, 720));
        final row = await pumpRow(tester);
        await openSheet(tester);
        await tester.enterText(box(), 'sw');
        await tester.pumpAndSettle();
        await closeSheet(tester);
        expect(row.picked, isEmpty);
        expect(boxText(tester), 'balance');
      });

      testWidgets('Enter in the sheet applies once', (tester) async {
        await setScreenSize(tester, const Size(360, 720));
        final row = await pumpRow(tester);
        await openSheet(tester);
        await tester.enterText(box(), 'star');
        await tester.pumpAndSettle();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect([for (final o in row.picked) o.id], ['star']);
      });
    });
  });
}
