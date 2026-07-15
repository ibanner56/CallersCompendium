import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/verbose_figure_rendering_scope.dart';
import 'package:compendium_app/src/widgets/figure_table.dart';

Future<void> _pump(
  WidgetTester tester, {
  required List<Figure> figures,
  required FigureRenderer renderer,
  required bool verbose,
}) async {
  final notifier = ValueNotifier<bool>(verbose);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
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
  // A move whose count renders a compressed glyph so the terse and verbose
  // forms differ (verbose spells the glyph out).
  final figure = Figure(move: 'star_promenade');
  final terse = renderer.render(figure, Dialect.larksRobins);
  final verbose = renderer.renderVerbose(figure, Dialect.larksRobins);

  test('precondition: terse and verbose renderings differ', () {
    expect(
      terse,
      isNot(verbose),
      reason: 'test needs a figure whose verbose form differs from terse',
    );
  });

  testWidgets('shows terse figure text when the scope is off', (tester) async {
    await _pump(tester, figures: [figure], renderer: renderer, verbose: false);
    expect(find.text(terse), findsOneWidget);
    expect(find.text(verbose), findsNothing);
  });

  testWidgets('shows verbose figure text when the scope is on', (tester) async {
    await _pump(tester, figures: [figure], renderer: renderer, verbose: true);
    expect(find.text(verbose), findsOneWidget);
    expect(find.text(terse), findsNothing);
  });
}
