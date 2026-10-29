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
Future<void> _pump(WidgetTester tester, List<Figure> figures) async {
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
}
