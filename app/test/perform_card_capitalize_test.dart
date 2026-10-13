import 'package:compendium_app/src/data/capitalize_figures_scope.dart';
import 'package:compendium_app/src/data/formation_colors_controller.dart';
import 'package:compendium_app/src/data/formation_colors_scope.dart';
import 'package:compendium_app/src/screens/perform_card.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _renderer = FigureRenderer(contraTaxonomy);
final _now = DateTime.utc(2026, 1, 1);

Dance _danceWith(List<Figure> figures) => Dance(
  id: 'd1',
  title: 'Test Dance',
  form: DanceForm.contra,
  formation: const Formation(FormationShape.becketCw),
  figures: figures,
  createdAt: _now,
  updatedAt: _now,
);

Future<void> _pump(
  WidgetTester tester,
  Dance dance, {
  required bool capitalize,
}) async {
  final repos = openTestRepositories();
  await repos.ensureMigrated();
  final colors = FormationColorsController(repos.settings);
  await colors.load();
  final notifier = ValueNotifier<bool>(capitalize);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: FormationColorsScope(
          controller: colors,
          child: CapitalizeFiguresScope(
            notifier: notifier,
            child: PerformCard(
              dance: dance,
              renderer: _renderer,
              dialect: Dialect.larksRobins,
              textScale: 1.0,
            ),
          ),
        ),
      ),
    ),
  );
}

String _capitalized(String s) => '${s[0].toUpperCase()}${s.substring(1)}';

void main() {
  final figure = Figure(move: 'allemande', params: {'travel': 0.75});
  final rendered = _renderer.renderSummary(figure, Dialect.larksRobins);

  testWidgets('leaves canonical figure text alone when off', (tester) async {
    await _pump(tester, _danceWith([figure]), capitalize: false);
    expect(find.text(rendered), findsOneWidget);
  });

  testWidgets('capitalizes canonical figure text when on', (tester) async {
    await _pump(tester, _danceWith([figure]), capitalize: true);
    expect(find.text(_capitalized(rendered)), findsOneWidget);
    expect(find.text(rendered), findsNothing);
  });

  testWidgets('capitalizes the lead span of a custom figure when on', (
    tester,
  ) async {
    final custom = testFigure(
      move: customMove,
      params: const {'text': '*role1s* cross the set', 'beats': 8},
    );
    await _pump(tester, _danceWith([custom]), capitalize: true);
    final plain = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.textSpan?.toPlainText())
        .whereType<String>();
    expect(plain, contains('Larks cross the set'));
  });

  testWidgets('leaves a custom figure alone when off', (tester) async {
    final custom = testFigure(
      move: customMove,
      params: const {'text': '*role1s* cross the set', 'beats': 8},
    );
    await _pump(tester, _danceWith([custom]), capitalize: false);
    final plain = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.textSpan?.toPlainText())
        .whereType<String>();
    expect(plain, contains('larks cross the set'));
  });
}
