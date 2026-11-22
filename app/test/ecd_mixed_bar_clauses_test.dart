import 'package:compendium_core/compendium_core.dart';
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

/// A `;` line that mixes an own-figure shorthand with a bar range, typed in an
/// English dance whose phrases differ in beats per bar (#2303).
void main() {
  final created = DateTime.utc(2026, 10, 16, 9);

  UserGlossaryEntry zoom({String template = '{who} {move} {pace}'}) =>
      UserGlossaryEntry(
        id: 'zoom-id',
        kindName: UserGlossaryEntryKind.customFigure.name,
        name: 'zoom',
        definition: 'A zoom.',
        description: 'Fast.',
        payload: {
          'template': template,
          'defaultBeats': 6,
          'params': [
            {'key': 'who', 'kind': 'dancerSet', 'default': 'role1s'},
            {
              'key': 'pace',
              'kind': 'choice',
              'choices': [
                {'id': 'c1', 'label': 'slowly'},
                {'id': 'c2', 'label': 'briskly'},
              ],
              'default': 'c1',
            },
          ],
        },
        createdAt: created,
      );

  UserFigureShorthand shorthand({
    String token = 'ZM',
    String figure = 'zoom-id',
    Map<String, Object?> args = const {'who': 'role2s', 'pace': 'c2'},
    int? beats = 4,
  }) => UserFigureShorthand(
    token: token,
    figureId: figure,
    figureName: 'zoom',
    args: args,
    beats: beats,
  );

  group('typing a `;` line in a mixed-meter English dance', () {
    Future<CompendiumRepositories> pump(
      WidgetTester tester, {
      bool customFigures = true,
      List<UserFigureShorthand> shorthands = const [],
      UserGlossaryEntry? figure,
      bool storeFigure = true,
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
            figures: [customFigure('stand', beats: 18)],
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
        if (storeFigure) await repos.userGlossary.upsert(figure ?? zoom());
        for (final s in shorthands) {
          await controller.upsertUserFigure(s);
        }
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

    Future<void> typeLine(WidgetTester tester, String line) async {
      await tester.tap(find.byKey(const ValueKey('figure-add')));
      await tester.pumpAndSettle();
      final figureItem = find.byKey(const ValueKey('figure-add-figure'));
      if (figureItem.evaluate().isNotEmpty) {
        await tester.tap(figureItem);
        await tester.pumpAndSettle();
      }
      await tester.enterText(
        find.byKey(const ValueKey('figure-free-text-field')),
        line,
      );
      await tester.tap(find.byKey(const ValueKey('figure-free-text-submit')));
      await tester.pumpAndSettle();
    }

    Future<List<Figure>> saved(
      WidgetTester tester,
      CompendiumRepositories repos,
    ) async {
      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();
      final dance = (await tester.runAsync(repos.dances.listAll))!.single;
      return figuresOf(dance);
    }

    // The dance is A:2*4*3 + B:1*8*2 (A1 and A2 of 4 bars of 3 beats, 0-24,
    // then 8 bars of 2) with one 18-beat figure in it, so a line typed now
    // starts at beat 18. The shorthand `zm` is a 4-beat figure of the user's.
    testWidgets('a `;` clause counts its bars from where the line and the '
        'clauses before it put it', (tester) async {
      final repos = await pump(tester, shorthands: [shorthand()]);
      await typeLine(tester, 'zm; 3-4 circle left');
      final figures = await saved(tester, repos);
      expect(figures, hasLength(3));
      expect(userFigureUseOf(figures[1])?.id, 'zoom-id');
      expect(figures[1].params['beats'], 4);
      // The clause starts at 18 + 4 = 22: a bar of 3 (22-25, in A2) and a bar
      // of 2 (25-27, in B) are 5 beats. From 18 or from 4 it would be 6.
      expect(figures[2].move, 'ecd_circle');
      expect(figures[2].params['beats'], 5);
    });

    testWidgets('a `;` line typed in a row\'s Move box starts after the rows '
        'before that row', (tester) async {
      final repos = await pump(tester, shorthands: [shorthand()]);
      await typeLine(tester, '3-4 circle left');
      await tester.tap(find.byKey(const ValueKey('figure-1-summary')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('figure-1-move-input')),
        'zm; 3-4 circle left',
      );
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final figures = await saved(tester, repos);
      // The replaced row (counted from 18 as 3 + 3 = 6) does not move the
      // start: 18 + 4 = 22, so 5 beats, not from 18 + 6 + 4 = 28 (4 beats).
      expect([for (final f in figures) f.params['beats']], [18, 4, 5]);
    });
  });
}
