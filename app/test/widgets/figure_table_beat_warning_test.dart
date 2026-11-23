import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/widgets/figure_table.dart';
import 'package:compendium_app/src/widgets/warnings_card.dart';
import '../support/l10n_harness.dart';

/// The dance detail view shows the editor's beat-mismatch warning, in the
/// editor's words (AUTH-12, October behaviour audit): without it the A1/A2/
/// B1/B2 labels silently shift when the beats do not add up.
Future<void> _pump(
  WidgetTester tester,
  List<Figure> figures, {
  bool checkPhraseFill = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: FigureTable(
            figures: figures,
            phraseStructure: PhraseStructure.standard,
            renderer: FigureRenderer(contraTaxonomy),
            dialect: Dialect.larksRobins,
            checkPhraseFill: checkPhraseFill,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Figure _swing(int beats) =>
    testFigure(move: 'swing', params: {'who': 'partners', 'beats': beats});

void main() {
  testWidgets('a dance whose beats fall short shows the warning', (
    tester,
  ) async {
    // 60 of 64: one figure is 4 beats short.
    await _pump(tester, [for (var i = 0; i < 7; i++) _swing(8), _swing(4)]);
    expect(find.byType(WarningsCard), findsOneWidget);
    expect(find.text('Warnings'), findsOneWidget);
    expect(find.textContaining('60'), findsOneWidget);
  });

  testWidgets('a dance whose beats run over shows the warning', (tester) async {
    await _pump(tester, [for (var i = 0; i < 9; i++) _swing(8)]);
    expect(find.byType(WarningsCard), findsOneWidget);
  });

  testWidgets('a dance whose beats add up shows none', (tester) async {
    await _pump(tester, [for (var i = 0; i < 8; i++) _swing(8)]);
    expect(find.byType(WarningsCard), findsNothing);
  });

  testWidgets('an empty dance shows none', (tester) async {
    await _pump(tester, const []);
    expect(find.byType(WarningsCard), findsNothing);
  });

  // ADR-007 §5.3: the dance page shows a square dance's phrase-crossing
  // warning, as the editor does (review N1 on #2405). 12 + 8 + 4 + 5×8 = 64,
  // so the beats add up; the second figure runs from beat 12 past A1's end at
  // 16, and it is the only one flagged.
  final crossing = [
    _swing(12),
    _swing(8),
    _swing(4),
    for (var i = 0; i < 5; i++) _swing(8),
  ];

  testWidgets('a square dance names a figure that runs past a phrase', (
    tester,
  ) async {
    await _pump(tester, crossing, checkPhraseFill: true);
    expect(find.byType(WarningsCard), findsOneWidget);
    expect(
      find.textContaining('Figure 2 runs past the end of A1'),
      findsOneWidget,
    );
  });

  testWidgets('without the check the crossing is not flagged', (tester) async {
    await _pump(tester, crossing);
    expect(find.byType(WarningsCard), findsNothing);
  });
}
