import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/decimal_turns_scope.dart';
import 'package:compendium_app/src/widgets/figure_table.dart';
import '../support/l10n_harness.dart';

Future<void> _pump(
  WidgetTester tester, {
  required List<Figure> figures,
  required FigureRenderer renderer,
  required bool decimals,
}) async {
  final notifier = ValueNotifier<bool>(decimals);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: DecimalTurnsScope(
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
  // A three-quarter allemande renders the glyph ¾ by default and 0.75 when the
  // decimals toggle is on.
  final figure = Figure(move: 'allemande', params: {'turn': 0.75});
  final fraction = renderer.renderSummary(figure, Dialect.larksRobins);
  final decimal = renderer.renderSummary(
    figure,
    Dialect.larksRobins,
    decimals: true,
  );

  test('precondition: fraction and decimal renderings differ', () {
    expect(fraction, endsWith('¾'));
    expect(decimal, endsWith('0.75'));
    expect(fraction, isNot(decimal));
  });

  testWidgets('shows fraction glyphs when the scope is off', (tester) async {
    await _pump(tester, figures: [figure], renderer: renderer, decimals: false);
    expect(find.text(fraction), findsOneWidget);
    expect(find.text(decimal), findsNothing);
  });

  testWidgets('shows decimals when the scope is on', (tester) async {
    await _pump(tester, figures: [figure], renderer: renderer, decimals: true);
    expect(find.text(decimal), findsOneWidget);
    expect(find.text(fraction), findsNothing);
  });
}
