import 'package:compendium_app/src/widgets/bar_timing.dart';
import 'package:compendium_app/src/widgets/figure_table.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

/// The dance detail view times an English dance's figures in bars, and every
/// other dance's in beats (ADR-006 §5.5).
Future<void> _pump(
  WidgetTester tester,
  DanceForm form,
  String phrase, {
  List<int> beats = const [6, 3],
  String meter = '',
}) async {
  final dance = Dance(
    id: 'd',
    title: 'Dance',
    form: form,
    meter: meter,
    phraseStructure: phrase,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: BarTimingScope.forDance(
            dance,
            child: FigureTable(
              figures: [
                for (final (i, b) in beats.indexed)
                  testFigure(
                    move: i.isEven ? 'ecd_lead' : 'ecd_set',
                    params: {'beats': b},
                  ),
              ],
              phraseStructure: dance.phraseStructure,
              renderer: FigureRenderer(shippedTaxonomies.anyForm),
              dialect: Dialect.larksRobins,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an English dance shows bars', (tester) async {
    await _pump(tester, DanceForm.ecd, '4*8*3');
    expect(find.text('2 bars'), findsOneWidget);
    expect(find.text('1 bar'), findsOneWidget);
  });

  testWidgets('a count that is no whole number of half bars shows beats', (
    tester,
  ) async {
    await _pump(tester, DanceForm.ecd, '4*8*4');
    expect(find.text('1½ bars'), findsOneWidget);
    expect(find.text('3 beats'), findsOneWidget);
  });

  testWidgets('a contra dance shows beats', (tester) async {
    await _pump(tester, DanceForm.contra, '4*8*3');
    expect(find.text('6 beats'), findsOneWidget);
    expect(find.text('3 beats'), findsOneWidget);
  });

  group('a tune whose phrases differ in beats per bar (#2303)', () {
    // A1 and A2 are 4 bars of 3 beats (0-24), B is 8 bars of 2 (24-40).
    const mixed = 'A:2*4*3 + B:1*8*2';

    testWidgets('shows each figure in the bars of its own phrase', (
      tester,
    ) async {
      await _pump(tester, DanceForm.ecd, mixed, beats: [12, 12, 8, 4]);
      expect(find.text('4 bars'), findsNWidgets(3));
      expect(find.text('2 bars'), findsOneWidget);
      expect(find.textContaining('beats'), findsNothing);
    });

    testWidgets('a figure across the change counts each bar by its own '
        'phrase', (tester) async {
      // 6 bars of 3 beats, then 3 + 3 + 2 + 2 from beat 18.
      await _pump(tester, DanceForm.ecd, mixed, beats: [18, 10]);
      expect(find.text('6 bars'), findsOneWidget);
      expect(find.text('4 bars'), findsOneWidget);
    });

    testWidgets('a count that is no whole number of bars where it falls '
        'shows beats', (tester) async {
      // 4 beats from the start of A is a bar of 3 and a beat over.
      await _pump(tester, DanceForm.ecd, mixed, beats: [4, 8]);
      expect(find.text('4 beats'), findsOneWidget);
    });

    testWidgets('a Meter that states one meter does not override the '
        'phrases', (tester) async {
      await _pump(
        tester,
        DanceForm.ecd,
        mixed,
        beats: [12, 12, 8],
        meter: '3/4',
      );
      expect(find.text('4 bars'), findsNWidgets(3));
    });

    testWidgets('the warnings read in bars from where each count starts', (
      tester,
    ) async {
      // 28 beats of a structure of 40: 8 bars of 3 and 2 bars of 2 are 10
      // bars; 40 beats are 8 bars of 3 and 8 of 2.
      await _pump(tester, DanceForm.ecd, mixed, beats: [18, 10]);
      expect(find.textContaining('10 bars'), findsOneWidget);
      expect(find.textContaining('16 bars'), findsOneWidget);
    });
  });
}
