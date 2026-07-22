import 'package:compendium_app/src/data/formation_colors_controller.dart';
import 'package:compendium_app/src/data/formation_colors_scope.dart';
import 'package:compendium_app/src/screens/perform_card.dart';
import 'package:compendium_app/src/theme/set_list_accents.dart';
import 'package:compendium_app/src/widgets/formation_color_badge.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

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
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,

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
}
