import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/settings_keys.dart';
import 'package:compendium_app/src/data/shorthand_mappings_controller.dart';
import 'package:compendium_app/src/data/shorthand_mappings_scope.dart';
import 'package:compendium_app/src/data/show_custom_figures_scope.dart';
import 'package:compendium_app/src/data/show_glossary_scope.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';

import 'figures_support.dart';
import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

/// The dance editor times an English dance in bars even where its phrases
/// differ in beats per bar (#2303): each figure's Bars field and summary read
/// and take bars by the phrase the figure starts in.
void main() {
  final created = DateTime.utc(2026, 10, 16, 9);

  group('a mixed-meter English dance in the editor', () {
    Future<CompendiumRepositories> pump(
      WidgetTester tester, {
      bool customFigures = true,
      List<Figure>? figures,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repos = openTestRepositories();
      await tester.runAsync(
        () => repos.dances.create(
          Dance(
            id: 'mixed',
            title: 'Mixed',
            form: DanceForm.ecd,
            formation: const Formation(FormationShape.dupleMinor),
            phraseStructure: 'A:2*4*3 + B:1*8*2',
            figures:
                figures ??
                [
                  for (final beats in [12, 12, 8])
                    testFigure(move: 'ecd_siding', params: {'beats': beats}),
                ],
            createdAt: created,
            updatedAt: created,
          ),
        ),
      );
      final controller = ShorthandMappingsController(repos.settings);
      addTearDown(controller.dispose);
      await tester.runAsync(() async {
        await repos.settings.set(kFreeTextEntryKey, true);
        await repos.settings.set(kDefaultDanceFiguresTemplateKey, '[]');
      });
      final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
      final glossary = ValueNotifier<bool>(true);
      final custom = ValueNotifier<bool>(customFigures);
      for (final n in [glossary, custom]) {
        addTearDown(n.dispose);
      }
      addTearDown(dialect.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) => RepositoriesScope(
            repositories: repos,
            child: ActiveDialectScope(
              notifier: dialect,
              child: ShowGlossaryScope(
                notifier: glossary,
                child: ShowCustomFiguresScope(
                  notifier: custom,
                  child: ShorthandMappingsScope(
                    controller: controller,
                    child: child!,
                  ),
                ),
              ),
            ),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const ValueKey('open-editor'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<String>(
                    builder: (_) => const DanceEditorScreen(danceId: 'mixed'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-editor')));
      await tester.pumpAndSettle();
      return repos;
    }

    String fieldText(WidgetTester tester, String key) =>
        tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

    Future<void> open(WidgetTester tester, int index) async {
      await tester.tap(find.byKey(ValueKey('figure-$index-summary')));
      await tester.pumpAndSettle();
      final more = find.byKey(ValueKey('figure-$index-more-options'));
      if (more.evaluate().isNotEmpty) {
        await tester.tap(more);
        await tester.pumpAndSettle();
      }
    }

    Future<List<int?>> savedBeats(
      WidgetTester tester,
      CompendiumRepositories repos,
    ) async {
      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();
      final dance = (await tester.runAsync(repos.dances.listAll))!.single;
      return [for (final f in figuresOf(dance)) f.params['beats'] as int?];
    }

    // A1 and A2 are 4 bars of 3 beats (0-24), B is 8 bars of 2 (24-40); the
    // dance has a figure for each of A1, A2 and the first half of B.
    testWidgets('each figure shows its count in the bars of its phrase', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('4 bars'), findsNWidgets(3));
      await open(tester, 2);
      expect(fieldText(tester, 'figure-2-beats'), '4');
    });

    testWidgets('a count typed in bars is stored in the beats of the phrase '
        'it starts in', (tester) async {
      final repos = await pump(tester);
      await open(tester, 2);
      await tester.enterText(find.byKey(const ValueKey('figure-2-beats')), '5');
      await tester.pumpAndSettle();
      // Five bars of 2 from beat 24.
      expect(await savedBeats(tester, repos), [12, 12, 10]);
    });

    testWidgets('the first figure takes its bars at 3 beats', (tester) async {
      final repos = await pump(tester);
      await open(tester, 0);
      await tester.enterText(find.byKey(const ValueKey('figure-0-beats')), '2');
      await tester.pumpAndSettle();
      expect((await savedBeats(tester, repos)).first, 6);
    });

    testWidgets('a sequence whose steps do not add up to its span is warned '
        'of in the bars of its own phrases', (tester) async {
      // The sequence starts at 18 and its steps (12 beats: 5 bars, 3 + 3 + 2
      // + 2 + 2) do not add up to its span (10 beats: 4 bars).
      await pump(
        tester,
        figures: [
          Figure(move: 'ecd_siding', params: const {'beats': 18}),
          Figure.sequence(
            figures: [
              Figure(move: 'ecd_lead', params: const {'beats': 6}),
              Figure(move: 'ecd_set', params: const {'beats': 6}),
            ],
            beats: 10,
          ),
        ],
      );
      expect(
        find.textContaining(
          'The steps of the sequence in figure 2 take 5 bars; the sequence '
          'takes 4 bars.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('half a bar is refused where the bar is 3 beats and taken '
        'where it is 2', (tester) async {
      final repos = await pump(tester);
      await open(tester, 0);
      await tester.enterText(
        find.byKey(const ValueKey('figure-0-beats')),
        '1.5',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Whole bars only, with 3 beats to the bar'),
        findsOneWidget,
      );
      await open(tester, 2);
      await tester.enterText(
        find.byKey(const ValueKey('figure-2-beats')),
        '1.5',
      );
      await tester.pumpAndSettle();
      expect((await savedBeats(tester, repos)).last, 3);
    });
  });
}
