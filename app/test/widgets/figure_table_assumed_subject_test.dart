import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/verbose_figure_rendering_scope.dart';
import 'package:compendium_app/src/widgets/figure_table.dart';
import '../support/l10n_harness.dart';

// Issue #460 — the on-screen figure table must surface a parser-assumed subject
// as a non-authoritative "(assumed)" marker, and must NOT add it to a figure
// whose subject the source actually stated.
Future<void> _pump(
  WidgetTester tester, {
  required List<Figure> figures,
  required FigureRenderer renderer,
}) async {
  final notifier = ValueNotifier<bool>(false);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: VerboseFigureRenderingScope(
          notifier: notifier,
          child: FigureTable(
            figures: figures,
            phraseStructure: PhraseStructure.parse(''),
            renderer: renderer,
            dialect: Dialect.larksRobins,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final renderer = FigureRenderer(contraTaxonomy);

  testWidgets('renders the (assumed) marker for a defaulted subject', (
    tester,
  ) async {
    final assumed = Figure(
      move: 'allemande',
      params: const {'who': 'neighbors', 'hand': 'left', 'beats': 8},
      assumedSubject: true,
    );
    await _pump(tester, figures: [assumed], renderer: renderer);
    expect(find.textContaining('(assumed)'), findsOneWidget);
    expect(find.textContaining('neighbor (assumed) allemande'), findsOneWidget);
  });

  testWidgets('omits the marker for a source-stated subject', (tester) async {
    final stated = Figure(
      move: 'allemande',
      params: const {'who': 'neighbors', 'hand': 'left', 'beats': 8},
    );
    await _pump(tester, figures: [stated], renderer: renderer);
    expect(find.textContaining('(assumed)'), findsNothing);
  });
}
