import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/widgets/figure_table.dart';
import '../support/l10n_harness.dart';

/// Dance-detail display of a `meanwhile` container figure (#594, layered on
/// the #590 core model): both concurrent sides render together on **one**
/// row, joined with "while", with a **single** beat label — never split into
/// two rows and never double-counted.
Future<void> _pump(WidgetTester tester, List<Figure> figures) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: FigureTable(
          figures: figures,
          phraseStructure: PhraseStructure.parse(''),
          renderer: FigureRenderer(contraTaxonomy),
          dialect: Dialect.larksRobins,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final renderer = FigureRenderer(contraTaxonomy);
  final sideA = Figure(
    move: 'allemande',
    params: const {'who': 'role1', 'hand': 'left', 'turn': 1.5},
  );
  final sideB = Figure(
    move: 'orbit',
    params: const {'who': 'role2', 'turn': 'clockwise', 'amount': 0.5},
  );

  testWidgets('renders both sides joined by "while" on a single row', (
    tester,
  ) async {
    final container = Figure.meanwhile(figures: [sideA, sideB], beats: 8);
    await _pump(tester, [container]);

    final expected = renderer.renderSummary(container, Dialect.larksRobins);
    expect(expected, contains(' while '));
    expect(find.text(expected), findsOneWidget);
  });

  testWidgets('shows exactly one beat label for the whole container (no '
      'double-count of the sub-figures\' own beats)', (tester) async {
    final container = Figure.meanwhile(figures: [sideA, sideB], beats: 8);
    await _pump(tester, [container]);

    // The container's shared 8-beat count appears once; nothing derived from
    // the sub-figures' own (display-only, unused-for-counting) beats leaks in
    // as a second row or a second beat label.
    expect(find.textContaining('8 beats'), findsOneWidget);
    expect(find.textContaining('16 beats'), findsNothing);
  });

  testWidgets('a 3-side meanwhile chains "A while B while C" on one row', (
    tester,
  ) async {
    final sideC = Figure(
      move: 'custom',
      params: const {'text': 'gentlespoons balance'},
    );
    final container = Figure.meanwhile(
      figures: [sideA, sideB, sideC],
      beats: 8,
    );
    await _pump(tester, [container]);

    final expected = renderer.renderSummary(container, Dialect.larksRobins);
    expect(' while '.allMatches(expected).length, 2);
    expect(find.text(expected), findsOneWidget);
  });
}
