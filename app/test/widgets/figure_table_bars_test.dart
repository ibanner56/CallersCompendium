import 'package:compendium_app/src/widgets/bar_timing.dart';
import 'package:compendium_app/src/widgets/figure_table.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

/// The dance detail view times an English dance's figures in bars, and every
/// other dance's in beats (ADR-006 §5.5).
Future<void> _pump(WidgetTester tester, DanceForm form, String phrase) async {
  final dance = Dance(
    id: 'd',
    title: 'Dance',
    form: form,
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
                testFigure(move: 'ecd_lead', params: {'beats': 6}),
                testFigure(move: 'ecd_set', params: {'beats': 3}),
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
}
