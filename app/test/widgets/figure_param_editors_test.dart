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
    await _selectFromDropdown(tester, 'p-hand', 'left');
    expect(read(), 'left');
  });

  testWidgets('shoulder dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'shoulder',
      spec: const ParamSpec(ParamKind.shoulder, defaultValue: 'right'),
      value: 'right',
    );
    await _selectFromDropdown(tester, 'p-shoulder', 'left');
    expect(read(), 'left');
  });

  testWidgets('spinDirection dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'spin',
      spec: const ParamSpec(ParamKind.spinDirection, defaultValue: 'clockwise'),
      value: 'clockwise',
    );
    await _selectFromDropdown(tester, 'p-spin', 'counterclockwise');
    expect(read(), 'counterclockwise');
  });

  testWidgets('fraction dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'amount',
      spec: const ParamSpec(ParamKind.fraction, defaultValue: 'quarter'),
      value: 'quarter',
    );
    await _selectFromDropdown(tester, 'p-amount', 'half');
    expect(read(), 'half');
  });

  testWidgets('direction dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'dir',
      spec: const ParamSpec(ParamKind.direction, defaultValue: 'along'),
      value: 'along',
    );
    await _selectFromDropdown(tester, 'p-dir', 'across');
    expect(read(), 'across');
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
        // Precondition: the sentinel must be in the list the editor RENDERS.
        // `ParamSpec.validate` accepting it is NOT sufficient — the editor and
        // the validator consult different domains, and only `choices` is
        // shared with the widget.
        expect(spec.choices, contains(ParamVocab.unspecified));

        final read = await _pumpEditor(
          tester,
          paramKey: paramKey,
          spec: spec,
          value: ParamVocab.unspecified,
        );
        await tester.pumpAndSettle();
        expect(
          read(),
          isNull,
          reason: 'opening the editor must not write a value into $paramKey',
        );
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
}
