import 'package:compendium_app/src/screens/perform_card.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';

/// Perform counts an English dance in bars, and where its phrases differ in
/// beats per bar each figure's count reads in the bars of the phrase it
/// starts in (#2303).
final _renderer = FigureRenderer(shippedTaxonomies.anyForm);
final _now = DateTime.utc(2026, 1, 1);

Future<void> _pump(WidgetTester tester, String phrase, List<int> beats) async {
  final dance = Dance(
    id: 'd1',
    title: 'Test Dance',
    form: DanceForm.ecd,
    phraseStructure: phrase,
    figures: [
      for (final (i, b) in beats.indexed)
        Figure(move: i.isEven ? 'ecd_lead' : 'ecd_set', params: {'beats': b}),
    ],
    createdAt: _now,
    updatedAt: _now,
  );
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: PerformCard(
            dance: dance,
            renderer: _renderer,
            dialect: Dialect.larksRobins,
            textScale: 1.0,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a tune in one meter shows bars as it did', (tester) async {
    await _pump(tester, '4*8*3', [6, 3]);
    expect(find.text('2 bars'), findsOneWidget);
    expect(find.text('1 bar'), findsOneWidget);
  });

  testWidgets('a tune whose phrases differ shows each count in the bars of '
      'the phrase it starts in', (tester) async {
    // A1 and A2 are 4 bars of 3 beats (0-24), B is 8 bars of 2 (24-40):
    // 12 and 12 beats are 4 bars each, 8 from beat 24 are 4 bars, and 4
    // beats from 32 are 2.
    await _pump(tester, 'A:2*4*3 + B:1*8*2', [12, 12, 8, 4]);
    expect(find.text('4 bars'), findsNWidgets(3));
    expect(find.text('2 bars'), findsOneWidget);
    expect(find.textContaining('beats'), findsNothing);
  });
}
