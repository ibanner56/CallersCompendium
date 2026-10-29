import 'dart:async';

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
import 'package:compendium_app/src/data/user_figures_scope.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';
import 'package:compendium_app/src/screens/glossary/compound_editor_screen.dart';
import 'package:compendium_app/src/screens/shorthand_mappings_screen.dart';

import 'figures_support.dart';
import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

/// Shorthands for the user's own new figures (#1023): typing one inserts a
/// use of the figure with the values it was saved with.
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

  CompoundShorthand compoundShorthand(String token) =>
      CompoundShorthand(token: token, compoundId: 'gone', compoundName: 'gone');

  Figure swing() =>
      Figure(move: 'swing', params: const {'who': 'neighbors', 'beats': 16});

  group('the controller', () {
    test('keeps tokens unique across all three kinds, ignoring case', () async {
      final repos = openTestRepositories();
      final controller = ShorthandMappingsController(repos.settings);
      addTearDown(controller.dispose);
      await controller.upsert(
        ShorthandMapping(token: 'ns', figures: [swing()]),
      );
      await controller.upsertCompound(compoundShorthand('grl'));
      for (final taken in ['NS', 'GRL']) {
        await expectLater(
          controller.upsertUserFigure(shorthand(token: taken)),
          throwsArgumentError,
        );
      }
      await controller.upsertUserFigure(shorthand());
      await expectLater(
        controller.upsertCompound(compoundShorthand('zm')),
        throwsArgumentError,
      );
      expect(controller.hasToken('Zm'), isTrue);
      expect(controller.hasToken('zm', exceptUserFigureIndex: 0), isFalse);
      expect(controller.takenTokens, {'ns', 'grl', 'zm'});
    });

    test('refuses one the next load would drop', () async {
      final repos = openTestRepositories();
      final controller = ShorthandMappingsController(repos.settings);
      addTearDown(controller.dispose);
      await expectLater(
        controller.upsertUserFigure(
          shorthand(args: {'who': 'x' * (maxUserFigureTextArgLength + 1)}),
        ),
        throwsArgumentError,
      );
      expect(controller.userFigureShorthands, isEmpty);
    });

    test('a change of kind is checked before either key is written', () async {
      final repos = openTestRepositories();
      final controller = ShorthandMappingsController(repos.settings);
      addTearDown(controller.dispose);
      await controller.upsertCompound(compoundShorthand('grl'));
      // One the next load would drop is refused, and the compound stays.
      await expectLater(
        controller.replaceCompoundWithUserFigure(
          0,
          shorthand(
            token: 'grl',
            args: {'who': 'x' * (maxUserFigureTextArgLength + 1)},
          ),
        ),
        throwsArgumentError,
      );
      expect(controller.compoundShorthands, hasLength(1));
      expect(await repos.settings.get(kCompoundShorthandsKey), hasLength(1));
      expect(controller.userFigureShorthands, isEmpty);

      // It may keep its own token; both keys are then written.
      await controller.replaceCompoundWithUserFigure(
        0,
        shorthand(token: 'grl'),
      );
      expect(controller.compoundShorthands, isEmpty);
      expect(await repos.settings.get(kCompoundShorthandsKey), isEmpty);
      expect(await repos.settings.get(kUserFigureShorthandsKey), [
        shorthand(token: 'grl').toJson(),
      ]);

      // And back again.
      await controller.replaceUserFigureWithCompound(
        0,
        compoundShorthand('grl'),
      );
      expect(controller.userFigureShorthands, isEmpty);
      expect(controller.compoundShorthands.single.token, 'grl');
    });

    test('a change of kind writes the new entry first, so a failed second '
        'write loses nothing', () async {
      final db = openWidgetTestDatabase();
      final settings = _FailingWrites(db);
      final controller = ShorthandMappingsController(settings);
      addTearDown(controller.dispose);
      await controller.upsertCompound(compoundShorthand('grl'));

      settings.failingKey = kCompoundShorthandsKey;
      await expectLater(
        controller.replaceCompoundWithUserFigure(0, shorthand(token: 'grl')),
        throwsStateError,
      );
      settings.failingKey = null;
      final reloaded = ShorthandMappingsController(settings);
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.compoundShorthands.single.token, 'grl');
      expect(reloaded.userFigureShorthands.single.token, 'grl');
      // What the controller holds is what is stored.
      expect(controller.compoundShorthands, reloaded.compoundShorthands);
      expect(controller.userFigureShorthands, reloaded.userFigureShorthands);
    });

    test('stores them under their own key, and reads all three back', () async {
      final repos = openTestRepositories();
      final controller = ShorthandMappingsController(repos.settings);
      addTearDown(controller.dispose);
      await controller.upsert(
        ShorthandMapping(token: 'ns', figures: [swing()]),
      );
      await controller.upsertCompound(compoundShorthand('grl'));
      await controller.upsertUserFigure(shorthand());
      expect(await repos.settings.get(kUserFigureShorthandsKey), [
        shorthand().toJson(),
      ]);

      final reloaded = ShorthandMappingsController(repos.settings);
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.mappings, hasLength(1));
      expect(reloaded.compoundShorthands, hasLength(1));
      expect(reloaded.userFigureShorthands, [shorthand()]);

      await reloaded.removeUserFigureAt(0);
      expect(await repos.settings.get(kUserFigureShorthandsKey), isEmpty);
    });
  });

  group('typing one in the dance editor', () {
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

    /// Seeds three plain rows, then types [line] into the Move box of the
    /// middle one and presses Enter (#1847).
    Future<void> typeInExistingRow(WidgetTester tester, String line) async {
      await typeLine(tester, 'neighbors swing');
      for (final seed in ['partners swing', 'turn alone']) {
        await tester.enterText(
          find.byKey(const ValueKey('figure-free-text-field')),
          seed,
        );
        await tester.tap(find.byKey(const ValueKey('figure-free-text-submit')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('figure-1-summary')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('figure-1-move-input')),
        line,
      );
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    testWidgets('inserts a use of the figure with its values and beats', (
      tester,
    ) async {
      final repos = await pump(tester, shorthands: [shorthand()]);
      await typeLine(tester, 'zm');
      final figure = (await saved(tester, repos)).single;
      final use = userFigureUseOf(figure);
      expect(use, isNotNull);
      expect(use!.attached, isTrue);
      expect(use.id, 'zoom-id');
      expect(use.args, {'who': 'role2s', 'pace': 'c2'});
      expect(figure.params['beats'], 4);
      expect(figure.params['text'], 'role2s zoom briskly');
    });

    testWidgets('one saved without beats takes the figure\'s default', (
      tester,
    ) async {
      final repos = await pump(tester, shorthands: [shorthand(beats: null)]);
      await typeLine(tester, 'zm');
      expect((await saved(tester, repos)).single.params['beats'], 6);
    });

    testWidgets('one whose figure is gone is read as an ordinary line', (
      tester,
    ) async {
      final repos = await pump(
        tester,
        shorthands: [shorthand()],
        storeFigure: false,
      );
      await typeLine(tester, 'zm');
      final figure = (await saved(tester, repos)).single;
      expect(userFigureUseOf(figure), isNull);
      expect(figure.params['text'], 'zm');
    });

    testWidgets('one with a value the figure no longer takes is read as an '
        'ordinary line', (tester) async {
      final repos = await pump(
        tester,
        shorthands: [
          shorthand(args: const {'who': 'role2s', 'pace': 'removed'}),
        ],
      );
      await typeLine(tester, 'zm');
      final figure = (await saved(tester, repos)).single;
      expect(userFigureUseOf(figure), isNull);
      expect(figure.params['text'], 'zm');
    });

    testWidgets('is ignored while Custom Figures is off', (tester) async {
      final repos = await pump(
        tester,
        shorthands: [shorthand()],
        customFigures: false,
      );
      await typeLine(tester, 'zm');
      final figure = (await saved(tester, repos)).single;
      expect(userFigureUseOf(figure), isNull);
    });

    testWidgets('a figure shorthand with the same token wins', (tester) async {
      final repos = await pump(tester, shorthands: [shorthand()]);
      final controller = ShorthandMappingsScope.controllerOf(
        tester.element(find.byType(DanceEditorScreen)),
      );
      // Past the controller's uniqueness check, as two devices could each
      // add one before they sync.
      await tester.runAsync(
        () => repos.settings.set(kShorthandMappingsKey, [
          ShorthandMapping(token: 'ZM', figures: [swing()]).toJson(),
        ]),
      );
      await tester.runAsync(controller.load);
      await tester.pumpAndSettle();
      await typeLine(tester, 'zm');
      expect((await saved(tester, repos)).single.move, 'swing');
    });

    testWidgets('typed into an existing row\'s Move box, replaces the row in '
        'place (#1847)', (tester) async {
      final repos = await pump(tester, shorthands: [shorthand()]);
      await typeInExistingRow(tester, 'zm');
      final figures = await saved(tester, repos);
      expect(figures, hasLength(3));
      expect(figures[0].move, 'swing');
      expect(figures[2].move, 'turn_alone');
      final use = userFigureUseOf(figures[1]);
      expect(use, isNotNull);
      expect(use!.id, 'zoom-id');
      expect(figures[1].params['text'], 'role2s zoom briskly');
    });

    // A count on a shorthand for one of the user's own figures is that use's
    // beats (#1861), as it is for a one-figure plain shorthand (#1827).
    for (final line in ['16 zm', 'zm (16)', 'ZM 16 beats']) {
      testWidgets('"$line" inserts the use with that count as its beats', (
        tester,
      ) async {
        final repos = await pump(tester, shorthands: [shorthand()]);
        await typeLine(tester, line);
        final figure = (await saved(tester, repos)).single;
        final use = userFigureUseOf(figure);
        expect(use, isNotNull);
        expect(use!.id, 'zoom-id');
        expect(use.args, {'who': 'role2s', 'pace': 'c2'});
        expect(figure.params['beats'], 16);
      });

      testWidgets('"$line" typed into an existing row\'s Move box replaces '
          'the row in place with that count', (tester) async {
        final repos = await pump(tester, shorthands: [shorthand()]);
        await typeInExistingRow(tester, line);
        final figures = await saved(tester, repos);
        expect(figures, hasLength(3));
        expect(figures[0].move, 'swing');
        expect(figures[2].move, 'turn_alone');
        expect(userFigureUseOf(figures[1])?.id, 'zoom-id');
        expect(figures[1].params['beats'], 16);
      });
    }

    // A count the beats range (0..64) refuses is not the use's beats (#1879),
    // as it is not a plain shorthand's: the line is kept as one custom figure
    // with its text as typed, as `circle left (100)` is.
    for (final line in [
      'zm (100)',
      '100 zm',
      'zm (65)',
      'zm; zm (100)',
      'zm (100); turn alone',
    ]) {
      testWidgets('"$line" is kept as one custom figure, as typed', (
        tester,
      ) async {
        final repos = await pump(tester, shorthands: [shorthand()]);
        await typeLine(tester, line);
        final figure = (await saved(tester, repos)).single;
        expect(userFigureUseOf(figure), isNull);
        expect(figure.isCustom, isTrue);
        expect(figure.params['text'], line);
      });

      testWidgets('"$line" typed into an existing row\'s Move box makes that '
          'row a custom figure as typed', (tester) async {
        final repos = await pump(tester, shorthands: [shorthand()]);
        await typeInExistingRow(tester, line);
        final figures = await saved(tester, repos);
        expect(figures, hasLength(3));
        expect(figures.map(userFigureUseOf), everyElement(isNull));
        expect(figures[1].params['text'], line);
      });
    }

    testWidgets('64 is the last count the use takes', (tester) async {
      final repos = await pump(tester, shorthands: [shorthand()]);
      await typeLine(tester, 'zm (64)');
      final figure = (await saved(tester, repos)).single;
      expect(userFigureUseOf(figure)?.id, 'zoom-id');
      expect(figure.params['beats'], 64);
    });

    testWidgets('a count too long to be beats leaves the use its beats and '
        'rides in its note (#1863)', (tester) async {
      final repos = await pump(tester, shorthands: [shorthand()]);
      await typeLine(tester, 'zm (10000)');
      final figure = (await saved(tester, repos)).single;
      expect(userFigureUseOf(figure)?.id, 'zoom-id');
      expect(figure.params['beats'], 4);
      expect(figure.note, '10000');
    });

    // A `;` clause may be one of these shorthands, with its own count (#1866),
    // as it may be a plain shorthand (#1827). Rows come out in typed order.
    final clauseLines = <String, List<String?>>{
      'zm; ladies chain': ['zoom-id:4', 'chain'],
      'ladies chain; zm': ['chain', 'zoom-id:4'],
      '16 zm; ladies chain': ['zoom-id:16', 'chain'],
      'ladies chain; zm (16)': ['chain', 'zoom-id:16'],
      'zm; 8 zm; ladies chain': ['zoom-id:4', 'zoom-id:8', 'chain'],
    };

    /// `zoom-id:<beats>` for a use of the figure, else the move.
    String describe(Figure f) {
      final use = userFigureUseOf(f);
      return use == null ? f.move : '${use.id}:${f.params['beats']}';
    }

    for (final MapEntry(key: line, value: want) in clauseLines.entries) {
      testWidgets('"$line" inserts a row per clause', (tester) async {
        final repos = await pump(tester, shorthands: [shorthand()]);
        await typeLine(tester, line);
        expect([for (final f in await saved(tester, repos)) describe(f)], want);
      });

      testWidgets('"$line" typed into an existing row\'s Move box replaces '
          'the row in place with the clauses', (tester) async {
        final repos = await pump(tester, shorthands: [shorthand()]);
        await typeInExistingRow(tester, line);
        final figures = await saved(tester, repos);
        expect(
          [for (final f in figures) describe(f)],
          ['swing', ...want, 'turn_alone'],
        );
      });
    }

    testWidgets('a clause that is not a figure leaves the whole line '
        'unexpanded (all or nothing)', (tester) async {
      final repos = await pump(tester, shorthands: [shorthand()]);
      await typeLine(tester, 'zm; flibbertigibbet');
      final figures = await saved(tester, repos);
      expect(figures.any((f) => userFigureUseOf(f) != null), isFalse);
    });

    testWidgets('a plain shorthand with the same token wins in a clause', (
      tester,
    ) async {
      final repos = await pump(tester, shorthands: [shorthand()]);
      final controller = ShorthandMappingsScope.controllerOf(
        tester.element(find.byType(DanceEditorScreen)),
      );
      await tester.runAsync(
        () => repos.settings.set(kShorthandMappingsKey, [
          ShorthandMapping(token: 'ZM', figures: [swing()]).toJson(),
        ]),
      );
      await tester.runAsync(controller.load);
      await tester.pumpAndSettle();
      await typeLine(tester, 'zm; ladies chain');
      expect(
        [for (final f in await saved(tester, repos)) f.move],
        ['swing', 'chain'],
      );
    });

    testWidgets('a plain shorthand clause whose count is refused keeps the '
        'whole line custom (#1879)', (tester) async {
      final repos = await pump(tester, shorthands: [shorthand()]);
      final controller = ShorthandMappingsScope.controllerOf(
        tester.element(find.byType(DanceEditorScreen)),
      );
      await tester.runAsync(
        () => repos.settings.set(kShorthandMappingsKey, [
          ShorthandMapping(token: 'ns', figures: [swing()]).toJson(),
        ]),
      );
      await tester.runAsync(controller.load);
      await tester.pumpAndSettle();
      await typeLine(tester, 'zm; ns (100)');
      final figure = (await saved(tester, repos)).single;
      expect(figure.isCustom, isTrue);
      expect(figure.params['text'], 'zm; ns (100)');
    });

    testWidgets('a count over 64 on a plain shorthand of several figures is '
        'ignored, a custom figure among them included (#1879)', (tester) async {
      final repos = await pump(tester, shorthands: [shorthand()]);
      final controller = ShorthandMappingsScope.controllerOf(
        tester.element(find.byType(DanceEditorScreen)),
      );
      await tester.runAsync(
        () => repos.settings.set(kShorthandMappingsKey, [
          ShorthandMapping(
            token: 'cb',
            figures: [swing(), customFigure('my own thing')],
          ).toJson(),
        ]),
      );
      await tester.runAsync(controller.load);
      await tester.pumpAndSettle();
      await typeLine(tester, 'zm; cb (100)');
      final figures = await saved(tester, repos);
      expect(figures, hasLength(3));
      expect(userFigureUseOf(figures[0]), isNotNull);
      expect(figures[1].move, 'swing');
      expect(figures[2].params['text'], 'my own thing');
    });

    testWidgets('65 clauses are not expanded', (tester) async {
      final repos = await pump(tester, shorthands: [shorthand()]);
      await typeLine(tester, List.filled(65, 'zm').join('; '));
      expect(
        (await saved(tester, repos)).any((f) => userFigureUseOf(f) != null),
        isFalse,
      );
    });

    testWidgets('64 clauses expand to 64 rows', (tester) async {
      final repos = await pump(tester, shorthands: [shorthand()]);
      await typeLine(tester, List.filled(64, 'zm').join('; '));
      final figures = await saved(tester, repos);
      expect(figures.where((f) => userFigureUseOf(f) != null), hasLength(64));
    });

    testWidgets('a count replaces a shorthand\'s saved beats and the '
        'figure\'s default', (tester) async {
      final repos = await pump(tester, shorthands: [shorthand(beats: null)]);
      await typeLine(tester, '16 zm');
      expect((await saved(tester, repos)).single.params['beats'], 16);
    });

    testWidgets('a figure shorthand with the same token wins over a counted '
        'use', (tester) async {
      final repos = await pump(tester, shorthands: [shorthand()]);
      final controller = ShorthandMappingsScope.controllerOf(
        tester.element(find.byType(DanceEditorScreen)),
      );
      await tester.runAsync(
        () => repos.settings.set(kShorthandMappingsKey, [
          ShorthandMapping(token: 'ZM', figures: [swing()]).toJson(),
        ]),
      );
      await tester.runAsync(controller.load);
      await tester.pumpAndSettle();
      await typeLine(tester, '16 zm');
      expect((await saved(tester, repos)).single.move, 'swing');
    });
  });

  group('the shorthands screen', () {
    Future<ShorthandMappingsController> pump(
      WidgetTester tester, {
      bool customFigures = true,
      List<UserFigureShorthand> shorthands = const [],
      List<CompoundShorthand> compounds = const [],
      bool storeFigure = true,
    }) async {
      await tester.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repos = openTestRepositories();
      final controller = ShorthandMappingsController(repos.settings);
      addTearDown(controller.dispose);
      await tester.runAsync(() async {
        if (storeFigure) await repos.userGlossary.upsert(zoom());
        for (final s in shorthands) {
          await controller.upsertUserFigure(s);
        }
        for (final c in compounds) {
          await controller.upsertCompound(c);
        }
      });
      final userFigures = UserFiguresController(repos.userGlossary);
      addTearDown(userFigures.dispose);
      unawaited(userFigures.start());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
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
                  child: UserFiguresScope(
                    controller: userFigures,
                    child: ShorthandMappingsScope(
                      controller: controller,
                      child: child!,
                    ),
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

    Finder tile(String token) =>
        find.byKey(ValueKey('user-figure-shorthand-tile-$token'));

    testWidgets('lists one with the line it inserts, in the dialect', (
      tester,
    ) async {
      await pump(tester, shorthands: [shorthand()]);
      expect(tile('zm'), findsOneWidget);
      expect(
        find.descendant(
          of: tile('zm'),
          matching: find.text('robins zoom briskly · 4 beats'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('user-figure-shorthand-problem-zm')),
        findsNothing,
      );
    });

    testWidgets('hides it, kept, while Custom Figures is off', (tester) async {
      final controller = await pump(
        tester,
        shorthands: [shorthand()],
        customFigures: false,
      );
      expect(tile('zm'), findsNothing);
      expect(controller.userFigureShorthands, hasLength(1));
    });

    testWidgets('says when one can no longer be used', (tester) async {
      await pump(tester, shorthands: [shorthand()], storeFigure: false);
      expect(
        find.byKey(const ValueKey('user-figure-shorthand-problem-zm')),
        findsOneWidget,
      );
    });

    Future<void> openNew(WidgetTester tester, String token) async {
      await tester.tap(find.byKey(const ValueKey('new-compound-shorthand')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('compound-shorthand-token')),
        token,
      );
      await tester.tap(
        find.byKey(const ValueKey('compound-shorthand-compound')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byKey(
              const ValueKey('compound-shorthand-choice-userFigure:zoom-id'),
            )
            .last,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a new one is made from a new figure, keeping its default '
        'beats as none', (tester) async {
      final controller = await pump(tester);
      await openNew(tester, 'zz');
      expect(
        find.byKey(const ValueKey('user-figure-shorthand-reads-as')),
        findsOneWidget,
      );
      expect(find.text('Reads as: larks zoom slowly'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('compound-shorthand-save')));
      await tester.pumpAndSettle();
      expect(controller.userFigureShorthands, [
        UserFigureShorthand(
          token: 'zz',
          figureId: 'zoom-id',
          figureName: 'zoom',
          args: const {'who': 'role1s', 'pace': 'c1'},
        ),
      ]);
      expect(controller.compoundShorthands, isEmpty);
    });

    testWidgets('a token another shorthand has is refused', (tester) async {
      final controller = await pump(tester, shorthands: [shorthand()]);
      await openNew(tester, 'Zm');
      await tester.tap(find.byKey(const ValueKey('compound-shorthand-save')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('compound-shorthand-error')),
        findsOneWidget,
      );
      expect(controller.userFigureShorthands, hasLength(1));
    });

    testWidgets('editing one opens with its values, and keeps its beats', (
      tester,
    ) async {
      final controller = await pump(tester, shorthands: [shorthand()]);
      await tester.tap(tile('zm'));
      await tester.pumpAndSettle();
      expect(find.text('Reads as: robins zoom briskly'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('compound-shorthand-token')),
        'zoomy',
      );
      await tester.tap(find.byKey(const ValueKey('compound-shorthand-save')));
      await tester.pumpAndSettle();
      expect(controller.userFigureShorthands, [shorthand(token: 'zoomy')]);
    });

    // UX2-1b: the values are read in after the editor opens, and must not
    // count as an edit.
    testWidgets('opening one and leaving it untouched does not ask', (
      tester,
    ) async {
      await pump(tester, shorthands: [shorthand()]);
      await tester.tap(tile('zm'));
      await tester.pumpAndSettle();
      expect(find.text('Reads as: robins zoom briskly'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(tile('zm'), findsOneWidget);
    });

    testWidgets('a compound shorthand given a new figure moves to the new '
        'figures\' key', (tester) async {
      final controller = await pump(
        tester,
        compounds: [compoundShorthand('grl')],
      );
      await tester.tap(
        find.byKey(const ValueKey('compound-shorthand-tile-grl')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('compound-shorthand-compound')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byKey(
              const ValueKey('compound-shorthand-choice-userFigure:zoom-id'),
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('compound-shorthand-save')));
      await tester.pumpAndSettle();
      expect(controller.compoundShorthands, isEmpty);
      expect(
        [for (final s in controller.userFigureShorthands) s.token],
        ['grl'],
      );
    });

    testWidgets('says when a compound shorthand has the same token', (
      tester,
    ) async {
      final controller = await pump(tester, shorthands: [shorthand()]);
      // Past the controller's uniqueness check, as two devices could each
      // add one before they sync.
      await tester.runAsync(() async {
        await controller.removeUserFigureAt(0);
        await controller.upsertCompound(compoundShorthand('zm'));
        await controller.upsertUserFigure(shorthand(token: 'other'));
      });
      final repos = RepositoriesScope.of(
        tester.element(find.byType(ShorthandMappingsScreen)),
      );
      await tester.runAsync(() async {
        await repos.settings.set(kUserFigureShorthandsKey, [
          shorthand().toJson(),
        ]);
        await controller.load();
      });
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('user-figure-shorthand-problem-zm')),
            )
            .data,
        'Not used: a shorthand for one of your combinations has the same '
        'text.',
      );
    });

    testWidgets('editing one is titled as an edit', (tester) async {
      await pump(tester, shorthands: [shorthand()]);
      await tester.tap(tile('zm'));
      await tester.pumpAndSettle();
      expect(find.text('Edit shorthand'), findsOneWidget);
      expect(find.text('New shorthand'), findsNothing);
    });

    testWidgets('one given a compound instead moves to the compounds\' key', (
      tester,
    ) async {
      final controller = await pump(tester, shorthands: [shorthand()]);
      final repos = RepositoriesScope.of(
        tester.element(find.byType(ShorthandMappingsScreen)),
      );
      await tester.runAsync(
        () => repos.userGlossary.upsert(
          UserGlossaryEntry(
            id: 'circle-id',
            kindName: UserGlossaryEntryKind.compound.name,
            name: 'circle twice',
            definition: 'Two circles.',
            description: 'Round.',
            payload: CompoundDefinition(
              params: const [],
              figures: [
                for (var i = 0; i < 2; i++)
                  Figure(
                    move: 'pull_by',
                    params: const {
                      'who': 'neighbors',
                      'hand': 'right',
                      'beats': 2,
                    },
                  ),
              ],
              bindings: const [],
            ).toJson(),
            createdAt: created,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(tile('zm'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('compound-shorthand-compound')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byKey(
              const ValueKey('compound-shorthand-choice-compound:circle-id'),
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('compound-shorthand-save')));
      await tester.pumpAndSettle();
      expect(controller.userFigureShorthands, isEmpty);
      expect(
        [
          for (final c in controller.compoundShorthands)
            (c.token, c.compoundId),
        ],
        [('ZM', 'circle-id')],
      );
    });

    Future<void> newFigureShorthand(WidgetTester tester, String token) async {
      await tester.tap(find.byKey(const ValueKey('new-shorthand')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('shorthand-token-field')),
        token,
      );
      await tester.tap(find.byKey(const ValueKey('shorthand-editor-save')));
      await tester.pumpAndSettle();
    }

    testWidgets('a figure shorthand cannot take its token', (tester) async {
      await pump(tester, shorthands: [shorthand()]);
      await newFigureShorthand(tester, 'zm');
      expect(
        find.text(
          'Another shorthand already uses "zm" (shorthands are matched '
          'case-insensitively).',
        ),
        findsOneWidget,
      );
    });

    testWidgets('while it is hidden, a clash with it says what it is', (
      tester,
    ) async {
      await pump(tester, shorthands: [shorthand()], customFigures: false);
      await newFigureShorthand(tester, 'zm');
      expect(
        find.text(
          '"zm" is already a shorthand for one of your own figures. Those '
          'are listed here while Custom Figures is on.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('one is deleted', (tester) async {
      final controller = await pump(tester, shorthands: [shorthand()]);
      await tester.tap(
        find.byKey(const ValueKey('user-figure-shorthand-menu-zm')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('user-figure-shorthand-delete')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('compound-shorthand-delete-confirm')),
      );
      await tester.pumpAndSettle();
      expect(controller.userFigureShorthands, isEmpty);
    });
  });

  testWidgets('a figure of your own cannot be named like one of these '
      'shorthands', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);
    await tester.runAsync(() => controller.upsertUserFigure(shorthand()));
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(dialect.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(
            notifier: dialect,
            child: ShorthandMappingsScope(
              controller: controller,
              child: child!,
            ),
          ),
        ),
        home: CompoundEditorScreen(initial: zoom()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('compound-name')), 'ZM');
    await tester.tap(find.byKey(const ValueKey('compound-editor-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('is already the name'), findsOneWidget);
  });
}

/// A [SettingsRepository] whose `set` throws for [failingKey], as if that one
/// write failed.
class _FailingWrites extends SettingsRepository {
  _FailingWrites(super.db);

  String? failingKey;

  @override
  Future<void> set(String key, Object? value, {DateTime? at}) async {
    if (key == failingKey) throw StateError('injected write failure: $key');
    return super.set(key, value, at: at);
  }
}
