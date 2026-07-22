import 'package:compendium_app/src/data/formation_colors_controller.dart';
import 'package:compendium_app/src/data/formation_colors_scope.dart';
import 'package:compendium_app/src/screens/perform_card.dart';
import 'package:compendium_app/src/theme/set_list_accents.dart';
import 'package:compendium_app/src/widgets/formation_color_badge.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_repositories.dart';

final _renderer = FigureRenderer(contraTaxonomy);
final _now = DateTime.utc(2026, 1, 1);

Dance _dance() => Dance(
  id: 'd1',
  title: 'Test Dance',
  form: DanceForm.contra,
  formation: const Formation(FormationShape.becketCw),
  createdAt: _now,
  updatedAt: _now,
);

Future<FormationColorsController> _controllerWith(Color? override) async {
  final repos = openTestRepositories();
  await repos.ensureMigrated();
  final controller = FormationColorsController(repos.settings);
  await controller.load();
  if (override != null) {
    await controller.setColor(FormationShape.becketCw, override);
  }
  return controller;
}

Future<void> _pump(WidgetTester tester, FormationColorsController c) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FormationColorsScope(
          controller: c,
          child: PerformCard(
            dance: _dance(),
            renderer: _renderer,
            dialect: Dialect.larksRobins,
            textScale: 1.0,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('formation label uses the contrast-safe foreground when '
      'overridden (issue #367, ruling 1)', (tester) async {
    const yellow = Color(0xFFFFEB3B); // light ⇒ expects a dark foreground
    final c = await _controllerWith(yellow);
    await _pump(tester, c);

    final label = tester.widget<Text>(find.text('Becket (CW)'));
    // The badge's readable foreground wins over the themed onSurface colour.
    expect(label.style?.color, readableForegroundOn(yellow));
    expect(label.style?.color, const Color(0xFF000000));
    // And the label is actually wrapped in the highlight badge.
    expect(
      find.ancestor(
        of: find.text('Becket (CW)'),
        matching: find.byType(FormationColorBadge),
      ),
      findsOneWidget,
    );
  });

  testWidgets('formation label is not badged when not overridden', (
    tester,
  ) async {
    final c = await _controllerWith(null);
    await _pump(tester, c);

    // No override ⇒ no highlight badge around the formation label.
    expect(
      find.ancestor(
        of: find.text('Becket (CW)'),
        matching: find.byType(FormationColorBadge),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'auto-size re-measures the fit when the system text scale changes '
    '(no stale converged scale / overflow)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final c = await _controllerWith(null);
      // A dance tall enough that the auto-fit converges to an *interior* scale
      // (strictly between min and max) that fills the viewport at text scale
      // 1.0 — so a text-scale change forces a real re-measure.
      final dance = Dance(
        id: 'd1',
        title: 'A Dance With Many Figures',
        figures: [
          for (var i = 0; i < 12; i++)
            Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16}),
        ],
        status: DanceStatus.active,
        createdAt: _now,
        updatedAt: _now,
      );

      var systemScale = 1.0;
      late StateSetter setScale;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setScale = setState;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(systemScale)),
                child: Scaffold(
                  body: FormationColorsScope(
                    controller: c,
                    child: PerformCard(
                      dance: dance,
                      renderer: _renderer,
                      dialect: Dialect.larksRobins,
                      textScale: 1.0,
                      autoSize: true,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      Size titleSize() =>
          tester.getSize(find.byKey(const ValueKey('perform-title')));

      expect(tester.takeException(), isNull);
      final before = titleSize();

      // Enlarge the OS text scale with the viewport dimensions unchanged. A
      // stale cache would keep the old (now too large) converged scale and skip
      // measurement, so the composed text would roughly double and overflow.
      // The fix invalidates the cached scale on a text-scale change and
      // re-measures to the largest scale that still fits, so the rendered
      // title stays about the same height.
      setScale(() => systemScale = 2.0);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final after = titleSize();
      // The re-measured fit keeps the title about the same height. Without the
      // fix the stale converged scale would leave it ~2x larger (and overflow),
      // so a generous 25% tolerance still catches the regression.
      expect(after.height, closeTo(before.height, before.height * 0.25));
    },
  );
}
