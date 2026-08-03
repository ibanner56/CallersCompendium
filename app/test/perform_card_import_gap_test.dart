import 'package:compendium_app/src/data/formation_colors_controller.dart';
import 'package:compendium_app/src/data/formation_colors_scope.dart';
import 'package:compendium_app/src/screens/perform_card.dart';
import 'package:compendium_app/src/widgets/import_gap_badge.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

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

Future<void> _pump(WidgetTester tester, Dance dance) async {
  final repos = openTestRepositories();
  await repos.ensureMigrated();
  final c = FormationColorsController(repos.settings);
  await c.load();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,

      home: Scaffold(
        body: FormationColorsScope(
          controller: c,
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
  testWidgets('flags an importGap custom with the badge + Semantics label', (
    tester,
  ) async {
    await _pump(
      tester,
      _danceWith([
        customFigure(
          'kept verbatim',
          beats: 8,
          origin: CustomOrigin.importGap,
        ), // importGap
        testFigure(move: customMove, params: const {'text': 'hand-written'}),
        Figure(move: 'swing', params: const {'beats': 8}),
      ]),
    );

    expect(find.byType(ImportGapBadge), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('parse this call')), findsOneWidget);
  });

  testWidgets('no badge for userEntered customs or structured figures', (
    tester,
  ) async {
    await _pump(
      tester,
      _danceWith([
        testFigure(move: customMove, params: const {'text': 'hand-written'}),
        Figure(move: 'swing', params: const {'beats': 8}),
      ]),
    );

    expect(find.byType(ImportGapBadge), findsNothing);
  });
}
