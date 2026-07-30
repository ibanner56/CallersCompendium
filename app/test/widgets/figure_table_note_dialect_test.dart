import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/widgets/figure_table.dart';
import '../support/l10n_harness.dart';

// Regression for issue #619: figure notes are the only free-text field not
// passed through `renderFreeText`, so canonical role tokens leaked verbatim
// into the note instead of following the reader's active dialect.

Future<void> _pump(
  WidgetTester tester, {
  required List<Figure> figures,
  required Dialect dialect,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: FigureTable(
          figures: figures,
          phraseStructure: PhraseStructure.parse(''),
          renderer: FigureRenderer(contraTaxonomy),
          dialect: dialect,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('figure note with a role token renders in the active dialect', (
    tester,
  ) async {
    final figure = Figure(
      move: 'allemande',
      params: {'who': 'role2s', 'turn': 1.0},
      note: 'role2s scoop them up',
    );

    await _pump(tester, figures: [figure], dialect: Dialect.larksRobins);

    expect(find.text('robins scoop them up'), findsOneWidget);
    expect(find.text('role2s scoop them up'), findsNothing);
  });

  testWidgets('figure note with a role token stays canonical under the '
      'canonical dialect', (tester) async {
    final figure = Figure(
      move: 'allemande',
      params: {'who': 'role2s', 'turn': 1.0},
      note: 'role2s scoop them up',
    );

    await _pump(tester, figures: [figure], dialect: Dialect.canonical);

    expect(find.text('role2s scoop them up'), findsOneWidget);
  });

  testWidgets('a plain note with no role tokens renders unchanged', (
    tester,
  ) async {
    final figure = Figure(
      move: 'allemande',
      params: {'who': 'role2s', 'turn': 1.0},
      note: 'watch your spacing here',
    );

    await _pump(tester, figures: [figure], dialect: Dialect.larksRobins);

    expect(find.text('watch your spacing here'), findsOneWidget);
  });
}
