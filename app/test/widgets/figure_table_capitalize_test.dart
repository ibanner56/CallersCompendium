import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/capitalize_figures_scope.dart';
import 'package:compendium_app/src/data/verbose_figure_rendering_scope.dart';
import 'package:compendium_app/src/widgets/figure_table.dart';

import '../support/l10n_harness.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Figure figure,
  required FigureRenderer renderer,
  required bool capitalize,
  bool verbose = false,
}) async {
  final capNotifier = ValueNotifier<bool>(capitalize);
  final verboseNotifier = ValueNotifier<bool>(verbose);
  addTearDown(capNotifier.dispose);
  addTearDown(verboseNotifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: VerboseFigureRenderingScope(
          notifier: verboseNotifier,
          child: CapitalizeFiguresScope(
            notifier: capNotifier,
            child: FigureTable(
              figures: [figure],
              phraseStructure: PhraseStructure.parse(''),
              renderer: renderer,
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
  final renderer = FigureRenderer(contraTaxonomy);
  final figure = Figure(move: 'allemande', params: {'travel': 0.75});
  final rendered = renderer.renderSummary(figure, Dialect.larksRobins);
  final verboseRendered = renderer.renderSummary(
    figure,
    Dialect.larksRobins,
    verbose: true,
  );

  test('precondition: the renderer emits a lower-case first letter', () {
    expect(rendered[0], rendered[0].toLowerCase());
    expect(rendered[0], isNot(rendered[0].toUpperCase()));
    expect(verboseRendered[0], isNot(verboseRendered[0].toUpperCase()));
  });

  testWidgets('keeps the renderer wording when the scope is off', (
    tester,
  ) async {
    await _pump(tester, figure: figure, renderer: renderer, capitalize: false);
    expect(find.text(rendered), findsOneWidget);
  });

  testWidgets('capitalizes the first letter when the scope is on', (
    tester,
  ) async {
    await _pump(tester, figure: figure, renderer: renderer, capitalize: true);
    expect(
      find.text('${rendered[0].toUpperCase()}${rendered.substring(1)}'),
      findsOneWidget,
    );
    expect(find.text(rendered), findsNothing);
  });

  testWidgets('capitalizes the verbose text too when it is shown', (
    tester,
  ) async {
    await _pump(
      tester,
      figure: figure,
      renderer: renderer,
      capitalize: true,
      verbose: true,
    );
    expect(
      find.text(
        '${verboseRendered[0].toUpperCase()}${verboseRendered.substring(1)}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('does not change the screen-reader label', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, figure: figure, renderer: renderer, capitalize: true);
    expect(
      find.bySemanticsLabel(RegExp(RegExp.escape(verboseRendered))),
      findsOneWidget,
    );
    handle.dispose();
  });
}
