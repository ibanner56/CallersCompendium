import 'package:compendium_app/src/data/formation_colors_controller.dart';
import 'package:compendium_app/src/data/formation_colors_scope.dart';
import 'package:compendium_app/src/screens/perform_card.dart';
import 'package:compendium_app/src/widgets/import_gap_badge.dart';
import 'package:compendium_app/src/widgets/settings_action_row.dart';
import 'package:compendium_app/src/widgets/tap_tempo_metronome.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/screen_size.dart';
import '../support/test_repositories.dart';

/// Sets the system text scale for the test and restores it afterwards.
void _systemTextScale(WidgetTester tester, double scale) {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: testLocalizationsDelegates,
  supportedLocales: testSupportedLocales,
  home: Scaffold(body: home),
);

void main() {
  group('Perform beats label (UX4-2)', () {
    final now = DateTime.utc(2026, 1, 1);

    Future<double> beatsLabelScale(WidgetTester tester, double system) async {
      _systemTextScale(tester, system);
      await setScreenSize(tester, const Size(360, 800));
      final repos = openTestRepositories();
      await repos.ensureMigrated();
      final colors = FormationColorsController(repos.settings);
      await colors.load();
      await tester.pumpWidget(
        _app(
          FormationColorsScope(
            controller: colors,
            child: PerformCard(
              dance: Dance(
                id: 'd1',
                title: 'Test Dance',
                form: DanceForm.contra,
                formation: const Formation(FormationShape.dupleImproper),
                figures: [
                  Figure(move: 'swing', params: const {'beats': 8}),
                ],
                createdAt: now,
                updatedAt: now,
              ),
              renderer: FigureRenderer(contraTaxonomy),
              dialect: Dialect.larksRobins,
              textScale: 1.0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return MediaQuery.textScalerOf(
        tester.element(find.text('8 beats')),
      ).scale(1);
    }

    testWidgets('is capped at kBeatsLabelMaxTextScale under 2x text', (
      tester,
    ) async {
      expect(await beatsLabelScale(tester, 2.0), kBeatsLabelMaxTextScale);
    });

    testWidgets('is left alone at default text', (tester) async {
      expect(await beatsLabelScale(tester, 1.0), 1.0);
    });
  });

  testWidgets('the import-gap badge has a target of at least 24px (UX4-6a)', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const Center(child: ImportGapBadge())));
    final size = tester.getSize(find.byType(InkResponse));
    expect(size.width, greaterThanOrEqualTo(24));
    expect(size.height, greaterThanOrEqualTo(24));
  });

  group('SettingsActionRow (UX4-3a)', () {
    Future<void> pump(WidgetTester tester, double width, double scale) async {
      _systemTextScale(tester, scale);
      await setScreenSize(tester, Size(width, 800));
      await tester.pumpWidget(
        _app(
          SettingsActionRow(
            title: const Text('Re-check custom figures', key: ValueKey('t')),
            subtitle: const Text('Parses figures that were kept verbatim.'),
            button: OutlinedButton.icon(
              key: const ValueKey('b'),
              onPressed: () {},
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: const Text('Re-check now'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a phone at 2x text stacks the button under the text', (
      tester,
    ) async {
      await pump(tester, 360, 2.0);
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byKey(const ValueKey('b'))).top,
        greaterThanOrEqualTo(tester.getRect(find.byType(ListTile)).bottom),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('t'))).width,
        greaterThan(150),
        reason: 'the title keeps most of the row',
      );
    });

    testWidgets('a wide surface keeps the button trailing', (tester) async {
      await pump(tester, 800, 1.0);
      expect(
        tester.widget<ListTile>(find.byType(ListTile)).trailing,
        isNotNull,
      );
    });
  });

  group('TapTempoMetronome in a short sheet (UX4-3d)', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('scrolls instead of overflowing, ${scale}x text', (
        tester,
      ) async {
        _systemTextScale(tester, scale);
        await setScreenSize(tester, const Size(360, 800));
        // A landscape phone's bottom sheet is capped at ~200px.
        await tester.pumpWidget(
          _app(
            const Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(height: 200, child: TapTempoMetronome()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // The reset button, last in the column, is reachable by scrolling.
        await tester.ensureVisible(
          find.byKey(const ValueKey('tap-tempo-reset')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
