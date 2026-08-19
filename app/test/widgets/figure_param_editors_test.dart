import 'package:compendium_app/src/widgets/figure_param_editors.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

/// Pumps a single [FigureParamEditor] and returns a getter for the last value
/// reported through `onChanged`.
Future<Object? Function()> _pumpEditor(
  WidgetTester tester, {
  required String paramKey,
  required ParamSpec spec,
  required Object? value,
  Dialect? dialect,
}) async {
  Object? captured;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: Center(
          child: FigureParamEditor(
            keyPrefix: 'p',
            paramKey: paramKey,
            spec: spec,
            value: value,
            dialect: dialect ?? Dialect.canonical,
            onChanged: (v) => captured = v,
          ),
        ),
      ),
    ),
  );
  return () => captured;
}

Future<void> _selectFromDropdown(
  WidgetTester tester,
  String fieldKey,
  String label,
) async {
  await tester.tap(find.byKey(ValueKey(fieldKey)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dropdown reconciles an invalid value to the spec default', (
    tester,
  ) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'who',
      spec: const ParamSpec(ParamKind.dancerSet, defaultValue: 'partners'),
      value: 'not_a_dancer_set',
    );
    await tester.pumpAndSettle();
    // The invalid value is pushed back to the model as the spec default.
    expect(read(), 'partners');
    expect(find.text('partners'), findsOneWidget);
  });

  testWidgets('text field syncs when the parent reseeds the value', (
    tester,
  ) async {
    Object? captured;
    Widget host(String value) => MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: FigureParamEditor(
          keyPrefix: 'p',
          paramKey: 'text',
          spec: const ParamSpec(ParamKind.text, defaultValue: ''),
          value: value,
          dialect: Dialect.canonical,
          onChanged: (v) => captured = v,
        ),
      ),
    );
    await tester.pumpWidget(host('first'));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('p-text')))
          .controller
          ?.text,
      'first',
    );
    // A programmatic reseed (e.g. move change) updates the displayed text.
    await tester.pumpWidget(host('reseeded'));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('p-text')))
          .controller
          ?.text,
      'reseeded',
    );
    expect(captured, isNull);
  });

  testWidgets('beats field syncs when the parent reseeds the value', (
    tester,
  ) async {
    Widget host(int value) => MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: FigureParamEditor(
          keyPrefix: 'p',
          paramKey: 'beats',
          spec: const ParamSpec(ParamKind.beats, defaultValue: 8),
          value: value,
          dialect: Dialect.canonical,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(host(8));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('p-beats')))
          .controller
          ?.text,
      '8',
    );
    await tester.pumpWidget(host(4));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('p-beats')))
          .controller
          ?.text,
      '4',
    );
  });

  testWidgets('dancerSet dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'who',
      spec: const ParamSpec(ParamKind.dancerSet, defaultValue: 'partners'),
      value: 'partners',
    );
    await _selectFromDropdown(tester, 'p-who', 'neighbors');
    expect(read(), 'neighbors');
  });

  testWidgets('dancerPair dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'who',
      spec: const ParamSpec(
        ParamKind.dancerPair,
        defaultValue: 'partners',
        choices: ['partners', 'neighbors'],
      ),
      value: 'partners',
    );
    await _selectFromDropdown(tester, 'p-who', 'neighbors');
    expect(read(), 'neighbors');
  });

  testWidgets('handedness dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'hand',
      spec: const ParamSpec(ParamKind.handedness, defaultValue: 'right'),
      value: 'right',
    );
    // No `choices` on the spec: the sentinel must not appear (issue #726
    // regression guard — a spec without an explicit sentinel keeps behaving
    // exactly as it did before the fix).
    await tester.tap(find.byKey(const ValueKey('p-hand')));
    await tester.pumpAndSettle();
    // A spec without `choices` has no unstated state at all, so it gets no
    // Clear affordance. Deliberately assert THAT and not the absence of a
    // "not stated" label: with a concrete value set the hint is never
    // mounted either way, so such an assertion could not fail — the same
    // defect as the `find.text('unspecified')` check it replaced.
    expect(find.byKey(const ValueKey('p-hand-clear')), findsNothing);
    await tester.tap(find.text('left').last);
    await tester.pumpAndSettle();
    expect(read(), 'left');
  });

  testWidgets('shoulder dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'shoulder',
      spec: const ParamSpec(ParamKind.shoulder, defaultValue: 'right'),
      value: 'right',
    );
    await tester.tap(find.byKey(const ValueKey('p-shoulder')));
    await tester.pumpAndSettle();
    // A spec without `choices` has no unstated state at all, so it gets no
    // Clear affordance. Deliberately assert THAT and not the absence of a
    // "not stated" label: with a concrete value set the hint is never
    // mounted either way, so such an assertion could not fail — the same
    // defect as the `find.text('unspecified')` check it replaced.
    expect(find.byKey(const ValueKey('p-shoulder-clear')), findsNothing);
    await tester.tap(find.text('left').last);
    await tester.pumpAndSettle();
    expect(read(), 'left');
  });

  testWidgets('spinDirection dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'spin',
      spec: const ParamSpec(ParamKind.spinDirection, defaultValue: 'clockwise'),
      value: 'clockwise',
    );
    await tester.tap(find.byKey(const ValueKey('p-spin')));
    await tester.pumpAndSettle();
    // A spec without `choices` has no unstated state at all, so it gets no
    // Clear affordance. Deliberately assert THAT and not the absence of a
    // "not stated" label: with a concrete value set the hint is never
    // mounted either way, so such an assertion could not fail — the same
    // defect as the `find.text('unspecified')` check it replaced.
    expect(find.byKey(const ValueKey('p-spin-clear')), findsNothing);
    await tester.tap(find.text('counterclockwise').last);
    await tester.pumpAndSettle();
    expect(read(), 'counterclockwise');
  });

  testWidgets('fraction dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'amount',
      spec: const ParamSpec(ParamKind.fraction, defaultValue: 'quarter'),
      value: 'quarter',
    );
    await tester.tap(find.byKey(const ValueKey('p-amount')));
    await tester.pumpAndSettle();
    // A spec without `choices` has no unstated state at all, so it gets no
    // Clear affordance. Deliberately assert THAT and not the absence of a
    // "not stated" label: with a concrete value set the hint is never
    // mounted either way, so such an assertion could not fail — the same
    // defect as the `find.text('unspecified')` check it replaced.
    expect(find.byKey(const ValueKey('p-amount-clear')), findsNothing);
    await tester.tap(find.text('half').last);
    await tester.pumpAndSettle();
    expect(read(), 'half');
  });

  testWidgets('direction dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'dir',
      spec: const ParamSpec(ParamKind.direction, defaultValue: 'along'),
      value: 'along',
    );
    await tester.tap(find.byKey(const ValueKey('p-dir')));
    await tester.pumpAndSettle();
    // A spec without `choices` has no unstated state at all, so it gets no
    // Clear affordance. Deliberately assert THAT and not the absence of a
    // "not stated" label: with a concrete value set the hint is never
    // mounted either way, so such an assertion could not fail — the same
    // defect as the `find.text('unspecified')` check it replaced.
    expect(find.byKey(const ValueKey('p-dir-clear')), findsNothing);
    await tester.tap(find.text('across').last);
    await tester.pumpAndSettle();
    expect(read(), 'across');
  });

  // --- Sentinel-in-choices honoured by the five dropdown kinds (issue #726) -
  //
  // Before the #726 fix, `handedness`/`shoulder`/`spinDirection`/`fraction`/
  // `direction` ignored `spec.choices` entirely and always rendered a fixed
  // vocabulary, so a spec that opted into `ParamVocab.unspecified` (the "the
  // source stated nothing" sentinel) got a dropdown silently missing it — the
  // user could never express, or return to, "not stated".
  //
  // Issue #741 then changed HOW that state is reached, not whether it is
  // reachable: the sentinel is no longer offered as a menu item anywhere,
  // because it is a fact about provenance rather than a value a transcriber
  // picks off a list. Each pair of tests below asserts (a) the menu carries
  // real values only, and the Clear affordance reaches the unstated state and
  // stores exactly `ParamVocab.unspecified`, and (b) opening the editor already
  // ON the sentinel does not fabricate a write-back — the real hazard here is
  // silent data fabrication, not merely a missing dropdown item (mirrors the
  // dancerSet/dancerPair sentinel guards above).
  group('the five dropdown kinds honour a sentinel in spec.choices', () {
    testWidgets('handedness', (tester) async {
      const spec = ParamSpec(
        ParamKind.handedness,
        defaultValue: 'right',
        choices: [...ParamVocab.sides, ParamVocab.unspecified],
      );
      final read = await _pumpEditor(
        tester,
        paramKey: 'hand',
        spec: spec,
        value: 'right',
      );
      // Issue #741: the sentinel is NOT an offered option. "The source
      // stated nothing" is a fact about provenance, not a value a
      // transcriber picks off a list — so the menu carries real values only.
      await tester.tap(find.byKey(const ValueKey('p-hand')));
      await tester.pumpAndSettle();
      expect(find.text('unspecified'), findsNothing);
      expect(find.text('not stated'), findsNothing);
      // Dismiss without choosing: opening the menu must not write either.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(read(), isNull);
      // The unstated state is reachable through the Clear affordance, and
      // still stores exactly the canonical sentinel.
      await tester.tap(find.byKey(const ValueKey('p-hand-clear')));
      await tester.pumpAndSettle();
      expect(read(), ParamVocab.unspecified);
    });

    testWidgets('handedness does not fabricate when opened unspecified', (
      tester,
    ) async {
      const spec = ParamSpec(
        ParamKind.handedness,
        defaultValue: 'right',
        choices: [...ParamVocab.sides, ParamVocab.unspecified],
      );
      final read = await _pumpEditor(
        tester,
        paramKey: 'hand',
        spec: spec,
        value: ParamVocab.unspecified,
      );
      await tester.pumpAndSettle();
      expect(read(), isNull);
      expect(find.text('not stated'), findsOneWidget);
      expect(find.text('unspecified'), findsNothing);
    });

    testWidgets('shoulder', (tester) async {
      const spec = ParamSpec(
        ParamKind.shoulder,
        defaultValue: 'right',
        choices: [...ParamVocab.sides, ParamVocab.unspecified],
      );
      final read = await _pumpEditor(
        tester,
        paramKey: 'shoulder',
        spec: spec,
        value: 'right',
      );
      // Issue #741: the sentinel is NOT an offered option. "The source
      // stated nothing" is a fact about provenance, not a value a
      // transcriber picks off a list — so the menu carries real values only.
      await tester.tap(find.byKey(const ValueKey('p-shoulder')));
      await tester.pumpAndSettle();
      expect(find.text('unspecified'), findsNothing);
      expect(find.text('not stated'), findsNothing);
      // Dismiss without choosing: opening the menu must not write either.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(read(), isNull);
      // The unstated state is reachable through the Clear affordance, and
      // still stores exactly the canonical sentinel.
      await tester.tap(find.byKey(const ValueKey('p-shoulder-clear')));
      await tester.pumpAndSettle();
      expect(read(), ParamVocab.unspecified);
    });

    testWidgets('shoulder does not fabricate when opened unspecified', (
      tester,
    ) async {
      const spec = ParamSpec(
        ParamKind.shoulder,
        defaultValue: 'right',
        choices: [...ParamVocab.sides, ParamVocab.unspecified],
      );
      final read = await _pumpEditor(
        tester,
        paramKey: 'shoulder',
        spec: spec,
        value: ParamVocab.unspecified,
      );
      await tester.pumpAndSettle();
      expect(read(), isNull);
      expect(find.text('not stated'), findsOneWidget);
      expect(find.text('unspecified'), findsNothing);
    });

    testWidgets('spinDirection', (tester) async {
      const spec = ParamSpec(
        ParamKind.spinDirection,
        defaultValue: 'clockwise',
        choices: [...ParamVocab.spins, ParamVocab.unspecified],
      );
      final read = await _pumpEditor(
        tester,
        paramKey: 'spin',
        spec: spec,
        value: 'clockwise',
      );
      // Issue #741: the sentinel is NOT an offered option. "The source
      // stated nothing" is a fact about provenance, not a value a
      // transcriber picks off a list — so the menu carries real values only.
      await tester.tap(find.byKey(const ValueKey('p-spin')));
      await tester.pumpAndSettle();
      expect(find.text('unspecified'), findsNothing);
      expect(find.text('not stated'), findsNothing);
      // Dismiss without choosing: opening the menu must not write either.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(read(), isNull);
      // The unstated state is reachable through the Clear affordance, and
      // still stores exactly the canonical sentinel.
      await tester.tap(find.byKey(const ValueKey('p-spin-clear')));
      await tester.pumpAndSettle();
      expect(read(), ParamVocab.unspecified);
    });

    testWidgets('spinDirection does not fabricate when opened unspecified', (
      tester,
    ) async {
      const spec = ParamSpec(
        ParamKind.spinDirection,
        defaultValue: 'clockwise',
        choices: [...ParamVocab.spins, ParamVocab.unspecified],
      );
      final read = await _pumpEditor(
        tester,
        paramKey: 'spin',
        spec: spec,
        value: ParamVocab.unspecified,
      );
      await tester.pumpAndSettle();
      expect(read(), isNull);
      expect(find.text('not stated'), findsOneWidget);
      expect(find.text('unspecified'), findsNothing);
    });

    testWidgets('fraction', (tester) async {
      const spec = ParamSpec(
        ParamKind.fraction,
        defaultValue: 'quarter',
        choices: [...ParamVocab.fractions, ParamVocab.unspecified],
      );
      final read = await _pumpEditor(
        tester,
        paramKey: 'amount',
        spec: spec,
        value: 'quarter',
      );
      // Issue #741: the sentinel is NOT an offered option. "The source
      // stated nothing" is a fact about provenance, not a value a
      // transcriber picks off a list — so the menu carries real values only.
      await tester.tap(find.byKey(const ValueKey('p-amount')));
      await tester.pumpAndSettle();
      expect(find.text('unspecified'), findsNothing);
      expect(find.text('not stated'), findsNothing);
      // Dismiss without choosing: opening the menu must not write either.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(read(), isNull);
      // The unstated state is reachable through the Clear affordance, and
      // still stores exactly the canonical sentinel.
      await tester.tap(find.byKey(const ValueKey('p-amount-clear')));
      await tester.pumpAndSettle();
      expect(read(), ParamVocab.unspecified);
    });

    testWidgets('fraction does not fabricate when opened unspecified', (
      tester,
    ) async {
      const spec = ParamSpec(
        ParamKind.fraction,
        defaultValue: 'quarter',
        choices: [...ParamVocab.fractions, ParamVocab.unspecified],
      );
      final read = await _pumpEditor(
        tester,
        paramKey: 'amount',
        spec: spec,
        value: ParamVocab.unspecified,
      );
      await tester.pumpAndSettle();
      expect(read(), isNull);
      expect(find.text('not stated'), findsOneWidget);
      expect(find.text('unspecified'), findsNothing);
    });

    testWidgets('direction', (tester) async {
      const spec = ParamSpec(
        ParamKind.direction,
        defaultValue: 'along',
        choices: [...ParamVocab.directions, ParamVocab.unspecified],
      );
      final read = await _pumpEditor(
        tester,
        paramKey: 'dir',
        spec: spec,
        value: 'along',
      );
      // Issue #741: the sentinel is NOT an offered option. "The source
      // stated nothing" is a fact about provenance, not a value a
      // transcriber picks off a list — so the menu carries real values only.
      await tester.tap(find.byKey(const ValueKey('p-dir')));
      await tester.pumpAndSettle();
      expect(find.text('unspecified'), findsNothing);
      expect(find.text('not stated'), findsNothing);
      // Dismiss without choosing: opening the menu must not write either.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(read(), isNull);
      // The unstated state is reachable through the Clear affordance, and
      // still stores exactly the canonical sentinel.
      await tester.tap(find.byKey(const ValueKey('p-dir-clear')));
      await tester.pumpAndSettle();
      expect(read(), ParamVocab.unspecified);
    });

    testWidgets('direction does not fabricate when opened unspecified', (
      tester,
    ) async {
      const spec = ParamSpec(
        ParamKind.direction,
        defaultValue: 'along',
        choices: [...ParamVocab.directions, ParamVocab.unspecified],
      );
      final read = await _pumpEditor(
        tester,
        paramKey: 'dir',
        spec: spec,
        value: ParamVocab.unspecified,
      );
      await tester.pumpAndSettle();
      expect(read(), isNull);
      expect(find.text('not stated'), findsOneWidget);
      expect(find.text('unspecified'), findsNothing);
    });
  });

  group('ParamSpec.allowManualClear (v30, #989)', () {
    testWidgets(
      'allowManualClear: false suppresses the Clear affordance even with a '
      'value set',
      (tester) async {
        // Mirrors `promenade.turn`'s real shape: a concrete default plus
        // sentinel-admitting choices, with the manual escape hatch turned
        // off. This is the actual regression guard for F16/W5b — the
        // synthetic specs in the group above are `allowManualClear: true`
        // (the default) and must keep showing Clear; this one must not.
        const spec = ParamSpec(
          ParamKind.spinDirection,
          defaultValue: 'counterclockwise',
          choices: [...ParamVocab.spins, ParamVocab.unspecified],
          allowManualClear: false,
        );
        await _pumpEditor(
          tester,
          paramKey: 'turn',
          spec: spec,
          value: 'clockwise',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('p-turn-clear')),
          findsNothing,
          reason:
              'allowManualClear: false must suppress Clear regardless of '
              'whether a value is set',
        );
      },
    );

    testWidgets('allowManualClear: true (the default) still shows Clear for a '
        'sentinel-admitting spec with a concrete default', (tester) async {
      // The zero-blast-radius companion to the test above: a spec shaped
      // exactly like `promenade.turn` except for the flag must behave
      // exactly like every pre-v30 sentinel-admitting spec.
      const spec = ParamSpec(
        ParamKind.spinDirection,
        defaultValue: 'counterclockwise',
        choices: [...ParamVocab.spins, ParamVocab.unspecified],
      );
      await _pumpEditor(
        tester,
        paramKey: 'turn',
        spec: spec,
        value: 'clockwise',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('p-turn-clear')), findsOneWidget);
    });
  });

  testWidgets('choice dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'prefix',
      spec: const ParamSpec(
        ParamKind.choice,
        defaultValue: 'none',
        choices: ['none', 'balance', 'meltdown'],
      ),
      value: 'none',
    );
    await _selectFromDropdown(tester, 'p-prefix', 'balance');
    expect(read(), 'balance');
  });

  testWidgets('rotation stepper increments in quarter turns', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'turn',
      spec: const ParamSpec(ParamKind.rotation, defaultValue: 1.0),
      value: 1.0,
    );
    await tester.tap(find.byKey(const ValueKey('p-turn-inc')));
    await tester.pumpAndSettle();
    expect(read(), 1.25);
  });

  // Taxonomy v22's `gate.turn` opts a ROTATION param into the `unspecified`
  // sentinel, because ContraDB's gate states no turn amount at all. Before this
  // the stepper coerced any non-numeric value to 1.0, so an unstated turn read
  // as "1 turn" — a number the source never gave — and the first nudge would
  // have promoted that fabrication into stored data.
  const gateTurnSpec = ParamSpec(
    ParamKind.rotation,
    defaultValue: ParamVocab.unspecified,
    choices: [ParamVocab.unspecified],
  );

  testWidgets('an unset sentinel rotation shows "not stated", never a number', (
    tester,
  ) async {
    await _pumpEditor(
      tester,
      paramKey: 'turn',
      spec: gateTurnSpec,
      value: ParamVocab.unspecified,
    );
    await tester.pumpAndSettle();

    final label = tester.widget<Text>(
      find.byKey(const ValueKey('p-turn-value')),
    );
    expect(label.data, 'not stated');
    expect(label.data, isNot(contains('1')));
    // Nothing to decrement from an unset value.
    final dec = tester.widget<IconButton>(
      find.byKey(const ValueKey('p-turn-dec')),
    );
    expect(dec.onPressed, isNull);
    // No clear button until there is something to clear.
    expect(find.byKey(const ValueKey('p-turn-clear')), findsNothing);
  });

  testWidgets('the first nudge ADOPTS a value explicitly, from the floor', (
    tester,
  ) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'turn',
      spec: gateTurnSpec,
      value: ParamVocab.unspecified,
    );
    // Merely rendering the editor must not write anything.
    await tester.pumpAndSettle();
    expect(read(), isNull);

    await tester.tap(find.byKey(const ValueKey('p-turn-inc')));
    await tester.pumpAndSettle();
    // The domain minimum — stepping up from the floor is unambiguous, whereas
    // seeding a "typical" value would be the app guessing choreography.
    expect(read(), 0.25);
  });

  testWidgets('a set sentinel rotation can be cleared back to unspecified', (
    tester,
  ) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'turn',
      spec: gateTurnSpec,
      value: 0.75,
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('p-turn-value'))).data,
      contains('turn'),
    );

    await tester.tap(find.byKey(const ValueKey('p-turn-clear')));
    await tester.pumpAndSettle();
    expect(read(), ParamVocab.unspecified);
  });

  testWidgets('a rotation WITHOUT the sentinel keeps the numeric fallback', (
    tester,
  ) async {
    // Unchanged behaviour for every other rotation param (mad_robin.turn, …):
    // the sentinel is opt-in per spec, so a stray non-numeric value still
    // reconciles to 1.0 rather than showing an unset state it cannot store.
    await _pumpEditor(
      tester,
      paramKey: 'turn',
      spec: const ParamSpec(ParamKind.rotation, defaultValue: 1.0),
      value: 'garbage',
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('p-turn-value'))).data,
      isNot('not stated'),
    );
    expect(find.byKey(const ValueKey('p-turn-clear')), findsNothing);
  });

  testWidgets('rotation stepper decrements and clamps at the minimum', (
    tester,
  ) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'turn',
      spec: const ParamSpec(ParamKind.rotation, defaultValue: 0.25),
      value: 0.25,
    );
    // At the minimum the decrement button is disabled.
    final decButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('p-turn-dec')),
    );
    expect(decButton.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('p-turn-inc')));
    await tester.pumpAndSettle();
    expect(read(), 0.5);
  });

  testWidgets('beats field round-trips an integer', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'beats',
      spec: const ParamSpec(ParamKind.beats, defaultValue: 8),
      value: 8,
    );
    await tester.enterText(find.byKey(const ValueKey('p-beats')), '16');
    expect(read(), 16);
  });

  testWidgets('beats field ignores out-of-range input', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'beats',
      spec: const ParamSpec(ParamKind.beats, defaultValue: 8),
      value: 8,
    );
    await tester.enterText(find.byKey(const ValueKey('p-beats')), '99');
    expect(read(), isNull);
  });

  testWidgets('text field round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'text',
      spec: const ParamSpec(ParamKind.text, defaultValue: ''),
      value: '',
    );
    await tester.enterText(find.byKey(const ValueKey('p-text')), 'scoop it up');
    expect(read(), 'scoop it up');
  });

  testWidgets('flag switch round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'balance',
      spec: const ParamSpec(ParamKind.flag, defaultValue: false),
      value: false,
    );
    await tester.tap(find.byKey(const ValueKey('p-balance')));
    await tester.pumpAndSettle();
    expect(read(), true);
  });

  testWidgets('dancerSet dropdown labels role tokens in the active dialect', (
    tester,
  ) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'who',
      spec: const ParamSpec(
        ParamKind.dancerSet,
        defaultValue: 'role1s',
        choices: ['role1s', 'role2s'],
      ),
      value: 'role1s',
      dialect: Dialect.larksRobins,
    );
    await tester.pumpAndSettle();
    // Displayed labels use the dialect's role terms, not the canonical tokens.
    expect(find.text('larks'), findsOneWidget);
    expect(find.text('role1s'), findsNothing);
    // Selecting still stores the canonical token (storage stays canonical).
    await _selectFromDropdown(tester, 'p-who', 'robins');
    expect(read(), 'role2s');
  });

  testWidgets('dancerSet dropdown shows canonical tokens under Canonical', (
    tester,
  ) async {
    await _pumpEditor(
      tester,
      paramKey: 'who',
      spec: const ParamSpec(
        ParamKind.dancerSet,
        defaultValue: 'role1s',
        choices: ['role1s', 'role2s'],
      ),
      value: 'role1s',
      dialect: Dialect.canonical,
    );
    await tester.pumpAndSettle();
    expect(find.text('role1s'), findsOneWidget);
    expect(find.text('larks'), findsNothing);
  });

  testWidgets('dancerSet dropdown applies dialect dancer substitutions', (
    tester,
  ) async {
    final dialect = Dialect(
      name: 'Custom',
      dancers: const {'neighbors': 'countras'},
    );
    await _pumpEditor(
      tester,
      paramKey: 'who',
      spec: const ParamSpec(
        ParamKind.dancerSet,
        defaultValue: 'neighbors',
        choices: ['neighbors', 'partners'],
      ),
      value: 'neighbors',
      dialect: dialect,
    );
    await tester.pumpAndSettle();
    expect(find.text('countras'), findsOneWidget);
    expect(find.text('neighbors'), findsNothing);
  });

  test('humanizeToken spaces camelCase and lowercases', () {
    expect(humanizeToken('rightDiagonal'), 'right diagonal');
    expect(humanizeToken('threeQuarter'), 'three quarter');
    expect(humanizeToken('who'), 'who');
  });

  // --- Sentinel write-back protection (issue #726) --------------------------
  //
  // The hazard these guard is DATA FABRICATION, not a cosmetic dropdown gap.
  // `_dropdown` reconciles its selection against the list it RENDERS, and when
  // the current value is absent from that list it pushes a substitute back to
  // the draft via `addPostFrameCallback`. So for a param whose stored value may
  // be the `unspecified` sentinel, merely OPENING the editor can silently
  // rewrite "the source stated nothing" into a fabricated dancer.
  //
  // A dropdown-CONTENTS assertion would pass while the write-back still fired,
  // so these assert the write-back itself: `read()` must stay null.
  group('sentinel-bearing dancerSet params never write back on open', () {
    // Bound to the SHIPPED taxonomy specs, not hand-built ones, so a future
    // edit that drops `choices` from either param fails here.
    for (final paramKey in ['whom', 'endFacing']) {
      testWidgets('courtesy_turn.$paramKey (taxonomy v23)', (tester) async {
        final spec = contraTaxonomy.resolve('courtesy_turn')!.params[paramKey]!;
        final read = await _pumpEditor(
          tester,
          paramKey: paramKey,
          spec: spec,
          value: ParamVocab.unspecified,
        );
        await tester.pumpAndSettle();
        // THE load-bearing assertion, and it is deliberately FIRST. A
        // taxonomy-level check that `choices` contains the sentinel would pass
        // even if `_dropdown`'s reconciliation later changed and started
        // fabricating again; only this one exercises the widget. Asserting it
        // before the diagnostic below means a reconciliation regression fails
        // HERE rather than being masked by an earlier precondition.
        expect(
          read(),
          isNull,
          reason: 'opening the editor must not write a value into $paramKey',
        );
        // Diagnostic, not the guarantee: if the assertion above ever fails,
        // this is the first thing to check — the sentinel must be in the list
        // the editor RENDERS. `ParamSpec.validate` accepting it is NOT
        // sufficient, because the validator and the widget consult different
        // domains and only `choices` is shared with the widget.
        expect(spec.choices, contains(ParamVocab.unspecified));
      });
    }

    testWidgets('the same is true for every other sentinel dancerSet', (
      tester,
    ) async {
      // Every sentinel-bearing dancerSet on the taxonomy, checked in one
      // sweep so a newly-added one cannot quietly skip the guard.
      final offenders = <String>[];
      for (final move in contraTaxonomy.moves.values) {
        move.params.forEach((name, spec) {
          final isDancer =
              spec.kind == ParamKind.dancerSet ||
              spec.kind == ParamKind.dancerPair;
          if (isDancer && spec.defaultValue == ParamVocab.unspecified) {
            if (!(spec.choices?.contains(ParamVocab.unspecified) ?? false)) {
              offenders.add('${move.id}.$name');
            }
          }
        });
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'a dancerSet defaulting to the sentinel MUST list it in `choices`; '
            'without it the editor renders ParamVocab.dancerSets (which has no '
            'sentinel) and writes `choices.first` back into the draft',
      );
    });

    testWidgets('a sentinel default WITHOUT explicit choices DOES fabricate', (
      tester,
    ) async {
      // The failure mode the guard above exists to prevent, pinned so the
      // reason for that rule cannot be lost. `choices: null` makes the editor
      // fall back to `ParamVocab.dancerSets`, which has no sentinel — so the
      // selection reconciles to `choices.first` and is written back.
      final read = await _pumpEditor(
        tester,
        paramKey: 'endFacing',
        spec: const ParamSpec(
          ParamKind.dancerSet,
          defaultValue: ParamVocab.unspecified,
        ),
        value: ParamVocab.unspecified,
      );
      await tester.pumpAndSettle();
      expect(read(), isNotNull);
      expect(read(), ParamVocab.dancerSets.first);
    });

    testWidgets('courtesy_turn.direction needs no sentinel and writes back '
        'nothing', (tester) async {
      // `ParamKind.spinDirection` renders from a HARDCODED `ParamVocab.spins`,
      // ignoring `spec.choices` entirely — so a sentinel there could not be
      // made safe by declaring choices. The move avoids the problem by having a
      // real default (a courtesy turn wheels clockwise by construction).
      final spec = contraTaxonomy
          .resolve('courtesy_turn')!
          .params['direction']!;
      expect(spec.kind, ParamKind.spinDirection);
      expect(spec.choices, isNull);

      final read = await _pumpEditor(
        tester,
        paramKey: 'direction',
        spec: spec,
        value: 'clockwise',
      );
      await tester.pumpAndSettle();
      expect(read(), isNull);
    });
  });

  // --- The unstated state is shown, never picked (issue #741) ---------------
  //
  // The owner's ruling: `unspecified` must not be a drop-down option in search
  // OR in dance entry — "it's meaningless to a user in basically every
  // scenario" — though it may be the populated default. So the editor must
  // still SHOW the unstated state (dropping it silently would fabricate over
  // it, which is what the write-back group above guards) while offering only
  // real values, and must provide a way back to it.
  group('the unstated state is displayed and clearable, never selectable', () {
    // The shipped spec, not a hand-built one, so this tracks real data.
    ParamSpec heyMeetTarget() =>
        contraTaxonomy.resolve('hey')!.params['meetTarget']!;

    testWidgets('a dancerSet on its sentinel default reads "not stated"', (
      tester,
    ) async {
      final spec = heyMeetTarget();
      // Exactly how `figure_list_editor` seeds the editor for a hey whose
      // source never stated a target: `draft.params[key] ?? spec.defaultValue`,
      // and this param's `defaultValue` IS the sentinel. So this is the common
      // path, not an edge case.
      expect(spec.defaultValue, ParamVocab.unspecified);
      final read = await _pumpEditor(
        tester,
        paramKey: 'meetTarget',
        spec: spec,
        value: spec.defaultValue,
        dialect: Dialect.larksRobins,
      );
      await tester.pumpAndSettle();
      expect(
        read(),
        isNull,
        reason: 'opening the editor must not invent a meeting target',
      );
      expect(find.text('not stated'), findsOneWidget);
      expect(find.text('unspecified'), findsNothing);
      // Nothing to clear while already unstated.
      expect(
        find.byKey(const ValueKey('p-meetTarget-clear')),
        findsNothing,
        reason: 'the Clear affordance is pointless when nothing is set',
      );
    });

    testWidgets('the menu offers real values only, labelled by dialect', (
      tester,
    ) async {
      await _pumpEditor(
        tester,
        paramKey: 'meetTarget',
        spec: heyMeetTarget(),
        value: 'role1s',
        dialect: Dialect.larksRobins,
      );
      await tester.tap(find.byKey(const ValueKey('p-meetTarget')));
      await tester.pumpAndSettle();
      expect(find.text('unspecified'), findsNothing);
      expect(find.text('not stated'), findsNothing);
      // Still dialect-labelled — #741 changed which values are offered, not how
      // the remaining ones read.
      expect(find.text('larks'), findsWidgets);
    });

    testWidgets('Clear returns a set dancerSet to the sentinel', (
      tester,
    ) async {
      final read = await _pumpEditor(
        tester,
        paramKey: 'meetTarget',
        spec: heyMeetTarget(),
        value: 'role1s',
        dialect: Dialect.larksRobins,
      );
      await tester.pumpAndSettle();
      expect(read(), isNull, reason: 'a valid value must not be rewritten');
      await tester.tap(find.byKey(const ValueKey('p-meetTarget-clear')));
      await tester.pumpAndSettle();
      // The canonical sentinel, not a blank or a dropped write — the draft has
      // to be able to say "the source stated nothing" explicitly.
      expect(read(), ParamVocab.unspecified);
    });

    testWidgets('Clear also updates what the field DISPLAYS', (tester) async {
      // Raised in review on PR #764: the concern was that
      // `DropdownButtonFormField` ignores a later `initialValue` and leaves the
      // field stuck on the cleared selection, since Clear updates the model
      // from OUTSIDE the dropdown and the field's key is stable.
      //
      // The test above cannot answer that — `_pumpEditor` records `onChanged`
      // without feeding the new value back, so the editor is never rebuilt and
      // the display path is never exercised. That was a real gap regardless of
      // the diagnosis, so this drives a host that re-seeds from the model the
      // way `figure_list_editor` does.
      //
      // Measured result: the display DOES follow, because
      // `_DropdownButtonFormFieldState.didUpdateWidget` calls `setValue` when
      // `initialValue` changes (Flutter 3.44.6, `material/dropdown.dart`). It is
      // plain `FormField` that does not — it syncs only `forceErrorText` — which
      // is the likely source of the confusion. No value-based key is needed.
      Object? current = 'role1s';
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            home: Scaffold(
              body: Center(
                child: FigureParamEditor(
                  keyPrefix: 'p',
                  paramKey: 'meetTarget',
                  spec: heyMeetTarget(),
                  value: current,
                  dialect: Dialect.larksRobins,
                  onChanged: (v) => setState(() => current = v),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('larks'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('p-meetTarget-clear')));
      await tester.pumpAndSettle();

      expect(
        find.text('larks'),
        findsNothing,
        reason: 'the field must not stay stuck on the cleared selection',
      );
      expect(find.text('not stated'), findsOneWidget);
      expect(current, ParamVocab.unspecified);
    });

    testWidgets('a spec without the sentinel offers no Clear affordance', (
      tester,
    ) async {
      await _pumpEditor(
        tester,
        paramKey: 'who',
        spec: const ParamSpec(ParamKind.dancerSet, defaultValue: 'partners'),
        value: 'partners',
      );
      await tester.pumpAndSettle();
      // "Not stated" is not a representable state for this param, so offering a
      // way to reach it would produce a value `ParamSpec.validate` rejects.
      expect(find.byKey(const ValueKey('p-who-clear')), findsNothing);
      expect(find.text('not stated'), findsNothing);
    });

    testWidgets('an out-of-domain value is normalised to the sentinel', (
      tester,
    ) async {
      // The one case where the field DOES write on open. Every
      // sentinel-admitting spec defaults TO the sentinel, so a value outside
      // the domain misses both the value rung and the default rung and the
      // field falls to "not stated" — which would otherwise leave the draft
      // still holding the bad token while displaying the opposite, with Clear
      // hidden (nothing is selected) so the user could not reconcile them in
      // one step. Storing the sentinel corrects invalid data to exactly what is
      // displayed; it does not invent a dancer, which is what the guard above
      // prevents.
      final read = await _pumpEditor(
        tester,
        paramKey: 'meetTarget',
        spec: heyMeetTarget(),
        value:
            'everyone', // a real dancer token, but not in this param's domain
      );
      await tester.pumpAndSettle();
      expect(read(), ParamVocab.unspecified);
      expect(find.text('not stated'), findsOneWidget);
      expect(find.text('everyone'), findsNothing);
    });
  });
}
