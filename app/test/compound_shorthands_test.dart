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
import 'package:compendium_app/src/screens/shorthand_mappings_screen.dart';

import 'figures_support.dart';
import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

/// Shorthands for the user's own compound figures (#709).
void main() {
  final created = DateTime.utc(2026, 10, 14, 9);

  /// Four pull-bys alternating hands, from the hand given.
  CompoundDefinition grandRightAndLeft() {
    Figure pullBy() => Figure(
      move: 'pull_by',
      params: const {'who': 'neighbors', 'hand': 'right', 'beats': 2},
    );
    return CompoundDefinition(
      params: const [
        CompoundParam(key: 'who', kind: ParamKind.dancerSet),
        CompoundParam(key: 'hand', kind: ParamKind.handedness),
      ],
      figures: [pullBy(), pullBy(), pullBy(), pullBy()],
      bindings: [
        for (var i = 0; i < 4; i++) ...[
          CompoundSlotBinding(figureIndex: i, slotKey: 'who', paramKey: 'who'),
          CompoundSlotBinding(
            figureIndex: i,
            slotKey: 'hand',
            paramKey: 'hand',
            source: i.isEven
                ? CompoundBindingSource.declared
                : CompoundBindingSource.opposite,
          ),
        ],
      ],
    );
  }

  final entry = UserGlossaryEntry(
    id: 'grl',
    kindName: UserGlossaryEntryKind.compound.name,
    name: 'grand pull',
    definition: 'Pull by alternating hands.',
    description: 'Four pull-bys.',
    payload: grandRightAndLeft().toJson(),
    createdAt: created,
  );

  CompoundShorthand shorthand({
    String token = 'GRL',
    String compound = 'grl',
    Map<String, Object?> args = const {'who': 'partners', 'hand': 'left'},
  }) => CompoundShorthand(
    token: token,
    compoundId: compound,
    compoundName: 'grand pull',
    args: args,
  );

  Figure swing() =>
      Figure(move: 'swing', params: const {'who': 'neighbors', 'beats': 16});

  group('the controller', () {
    test('keeps tokens unique across both kinds, ignoring case', () async {
      final repos = openTestRepositories();
      final controller = ShorthandMappingsController(repos.settings);
      addTearDown(controller.dispose);
      await controller.upsert(
        ShorthandMapping(token: 'ns', figures: [swing()]),
      );
      expect(
        () => controller.upsertCompound(shorthand(token: 'NS')),
        throwsArgumentError,
      );
      await controller.upsertCompound(shorthand());
      expect(
        () => controller.upsert(
          ShorthandMapping(token: 'grl', figures: [swing()]),
        ),
        throwsArgumentError,
      );
      expect(controller.hasToken('Grl'), isTrue);
      expect(controller.hasToken('grl', exceptCompoundIndex: 0), isFalse);
    });

    test('stores compound shorthands under their own key, and reads both '
        'back', () async {
      final repos = openTestRepositories();
      final controller = ShorthandMappingsController(repos.settings);
      addTearDown(controller.dispose);
      await controller.upsert(
        ShorthandMapping(token: 'ns', figures: [swing()]),
      );
      await controller.upsertCompound(shorthand());
      expect(
        (await repos.settings.get(kShorthandMappingsKey))! as List,
        hasLength(1),
      );
      expect(await repos.settings.get(kCompoundShorthandsKey), [
        shorthand().toJson(),
      ]);

      final reloaded = ShorthandMappingsController(repos.settings);
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.mappings, hasLength(1));
      expect(reloaded.compoundShorthands, [shorthand()]);

      await reloaded.removeCompoundAt(0);
      expect(await repos.settings.get(kCompoundShorthandsKey), isEmpty);
    });
  });

  group('typing a compound shorthand in the dance editor', () {
    Future<CompendiumRepositories> pump(
      WidgetTester tester, {
      bool customFigures = true,
      List<CompoundShorthand> compounds = const [],
      List<ShorthandMapping> figureShorthands = const [],
      bool storeEntry = true,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repos = openTestRepositories();
      final controller = ShorthandMappingsController(repos.settings);
      addTearDown(controller.dispose);
      await tester.runAsync(() async {
        await repos.settings.set(kFreeTextEntryKey, true);
        await repos.settings.set(kDefaultDanceFiguresTemplateKey, '[]');
        if (storeEntry) await repos.userGlossary.upsert(entry);
        for (final m in figureShorthands) {
          await controller.upsert(m);
        }
        for (final c in compounds) {
          await controller.upsertCompound(c);
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
                    builder: (_) => const DanceEditorScreen(danceId: null),
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
      await tester.enterText(find.byKey(const ValueKey('title-field')), 'T');
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

    testWidgets('inserts the figure it stands for, expanded on save', (
      tester,
    ) async {
      final repos = await pump(tester, compounds: [shorthand()]);
      await typeLine(tester, 'grl');
      expect(find.text('grand pull: partners, left'), findsOneWidget);
      final figures = await saved(tester, repos);
      expect(
        [for (final f in figures) (f.move, f.params['who'], f.params['hand'])],
        [
          ('pull_by', 'partners', 'left'),
          ('pull_by', 'partners', 'right'),
          ('pull_by', 'partners', 'left'),
          ('pull_by', 'partners', 'right'),
        ],
      );
    });

    testWidgets('one whose figure is gone is read as an ordinary line', (
      tester,
    ) async {
      final repos = await pump(
        tester,
        compounds: [shorthand()],
        storeEntry: false,
      );
      await typeLine(tester, 'grl');
      final figures = await saved(tester, repos);
      expect(figures.single.move, customMove);
      expect(figures.single.params['text'], 'grl');
    });

    testWidgets('is ignored while Custom Figures is off', (tester) async {
      final repos = await pump(
        tester,
        compounds: [shorthand()],
        customFigures: false,
      );
      await typeLine(tester, 'grl');
      final figures = await saved(tester, repos);
      expect(figures.single.move, customMove);
    });

    testWidgets('a figure shorthand with the same token wins', (tester) async {
      final repos = await pump(tester, compounds: [shorthand()]);
      // Added past the controller's uniqueness check, as two devices could
      // each add one before they sync.
      final controller = ShorthandMappingsScope.controllerOf(
        tester.element(find.byType(DanceEditorScreen)),
      );
      await tester.runAsync(
        () => repos.settings.set(kShorthandMappingsKey, [
          ShorthandMapping(token: 'GRL', figures: [swing()]).toJson(),
        ]),
      );
      await tester.runAsync(controller.load);
      await tester.pumpAndSettle();
      await typeLine(tester, 'grl');
      final figures = await saved(tester, repos);
      expect(figures.single.move, 'swing');
    });
  });

  group('the shorthands screen', () {
    Future<ShorthandMappingsController> pump(
      WidgetTester tester, {
      bool customFigures = true,
      List<CompoundShorthand> compounds = const [],
    }) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repos = openTestRepositories();
      final controller = ShorthandMappingsController(repos.settings);
      addTearDown(controller.dispose);
      await tester.runAsync(() async {
        await repos.userGlossary.upsert(entry);
        for (final c in compounds) {
          await controller.upsertCompound(c);
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
          home: const ShorthandMappingsScreen(),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    testWidgets('lists them while Custom Figures is on, and hides them, '
        'kept, while it is off', (tester) async {
      final controller = await pump(
        tester,
        customFigures: false,
        compounds: [shorthand()],
      );
      expect(
        find.byKey(const ValueKey('new-compound-shorthand')),
        findsNothing,
      );
      expect(find.text('GRL'), findsNothing);
      expect(controller.compoundShorthands, hasLength(1));

      await pump(tester, compounds: [shorthand()]);
      expect(find.text('GRL'), findsOneWidget);
      expect(find.text('grand pull: partners, left'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('compound-shorthand-problem-grl')),
        findsNothing,
      );
    });

    testWidgets('says when one can no longer be used', (tester) async {
      await pump(
        tester,
        compounds: [
          shorthand(token: 'gone', compound: 'missing'),
          shorthand(token: 'odd', args: const {'who': 'partners'}),
        ],
      );
      expect(
        find.byKey(const ValueKey('compound-shorthand-problem-gone')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('compound-shorthand-problem-odd')),
        findsOneWidget,
      );
    });

    testWidgets('a new one is made from a figure and its values', (
      tester,
    ) async {
      final controller = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('new-compound-shorthand')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('compound-shorthand-token')),
        'grl',
      );
      await tester.tap(
        find.byKey(const ValueKey('compound-shorthand-compound')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('grand pull').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Becomes 4 figures (8 beats) when the dance is saved.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('compound-shorthand-save')));
      await tester.pumpAndSettle();
      expect(controller.compoundShorthands.single.token, 'grl');
      expect(controller.compoundShorthands.single.compoundId, 'grl');
      expect(controller.compoundShorthands.single.args, {
        'who': 'neighbors',
        'hand': 'right',
      });
    });

    testWidgets('a token another shorthand has is refused', (tester) async {
      final controller = await pump(tester, compounds: [shorthand()]);
      await tester.tap(find.byKey(const ValueKey('new-compound-shorthand')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('compound-shorthand-token')),
        'Grl',
      );
      await tester.tap(find.byKey(const ValueKey('compound-shorthand-save')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('compound-shorthand-error')),
        findsOneWidget,
      );
      expect(controller.compoundShorthands, hasLength(1));
    });
  });
}
