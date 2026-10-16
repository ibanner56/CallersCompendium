import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/dialect_library_controller.dart';
import 'package:compendium_app/src/data/dialect_library_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/shorthand_mappings_controller.dart';
import 'package:compendium_app/src/data/shorthand_mappings_scope.dart';
import 'package:compendium_app/src/data/show_custom_figures_scope.dart';
import 'package:compendium_app/src/data/show_glossary_scope.dart';
import 'package:compendium_app/src/screens/glossary/glossary_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// A later version of the app ships a figure with the name of one of the
/// user's own (#1023, maintainer decision 5): the user renames theirs, or
/// maps it onto the app's and switches every use to it.
void main() {
  final created = DateTime.utc(2026, 10, 16);

  // "swing", made before the app shipped one: restored, so no name check
  // stands in the way, as when the app's figure arrives later.
  UserGlossaryEntry mine({
    String name = 'swing',
    List<Map<String, Object?>>? params,
    String template = '{who} [{prefix}] {move}',
  }) => UserGlossaryEntry(
    id: 'mine',
    kindName: UserGlossaryEntryKind.customFigure.name,
    name: name,
    definition: 'Mine.',
    description: 'Of my own.',
    payload: {
      'template': template,
      'defaultBeats': 8,
      'params':
          params ??
          [
            {'key': 'who', 'kind': 'dancerSet', 'default': 'neighbors'},
            {
              'key': 'prefix',
              'kind': 'choice',
              'choices': [
                {'id': 'bal', 'label': 'Balance'},
                {'id': 'melt', 'label': 'meltdown'},
              ],
            },
          ],
    },
    createdAt: created,
  );

  Figure use(Map<String, Object?> args) =>
      userFigureUseFigure(id: 'mine', args: args, text: 'a stored line');

  Future<
    ({
      CompendiumRepositories repos,
      ShorthandMappingsController shorthands,
      DialectLibraryController dialects,
    })
  >
  pump(
    WidgetTester tester, {
    Size size = const Size(500, 900),
    UserGlossaryEntry? entry,
    Future<void> Function(CompendiumRepositories repos)? seed,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    final shorthands = ShorthandMappingsController(repos.settings);
    final dialects = DialectLibraryController(repos.settings);
    addTearDown(shorthands.dispose);
    addTearDown(dialects.dispose);
    await tester.runAsync(() async {
      await repos.userGlossary.upsertFromRestore(entry ?? mine());
      await seed?.call(repos);
      await shorthands.load();
      await dialects.load();
    });
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    final glossary = ValueNotifier(true);
    final custom = ValueNotifier(true);
    for (final n in <ChangeNotifier>[dialect, glossary, custom]) {
      addTearDown(n.dispose);
    }
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(
            notifier: dialect,
            child: DialectLibraryScope(
              controller: dialects,
              child: ShorthandMappingsScope(
                controller: shorthands,
                child: ShowGlossaryScope(
                  notifier: glossary,
                  child: ShowCustomFiguresScope(
                    notifier: custom,
                    child: child!,
                  ),
                ),
              ),
            ),
          ),
        ),
        home: const GlossaryScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('glossary-search')),
      (entry ?? mine()).name,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glossary-entry-custom:mine')));
    await tester.pumpAndSettle();
    return (repos: repos, shorthands: shorthands, dialects: dialects);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  Future<List<Figure>> figuresOf(
    WidgetTester tester,
    CompendiumRepositories repos,
  ) async {
    final dance = await tester.runAsync(() => repos.dances.getById('d1'));
    return switch (dance!.figuresSource) {
      DecodedFigures(:final figures) => figures,
      UnreadableFigures() => throw StateError('unreadable'),
    };
  }

  Future<void> seedUses(CompendiumRepositories repos) async {
    await repos.dances.create(
      Dance(
        id: 'd1',
        title: 'Uses mine',
        figures: [
          use(const {'who': 'partners', 'prefix': 'bal'}),
        ],
        createdAt: created,
        updatedAt: created,
      ),
    );
  }

  testWidgets('a figure the app now has is offered a rename or a switch; '
      'another is not', (tester) async {
    await pump(tester);
    expect(
      find.byKey(const ValueKey('glossary-custom-shipped-name')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('glossary-custom-rename-needed')),
      findsNothing,
      reason: 'the one notice says why',
    );
    expect(
      find.byKey(const ValueKey('glossary-custom-switch-to-shipped')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('glossary-custom-rename-mine')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('compound-editor')), findsOneWidget);
  });

  testWidgets('a figure no shipped figure is named is offered no switch', (
    tester,
  ) async {
    await pump(tester, entry: mine(name: 'zoom'));
    expect(
      find.byKey(const ValueKey('glossary-custom-switch-to-shipped')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('glossary-custom-shipped-name')),
      findsNothing,
    );
  });

  for (final (layout, size) in [
    ('narrow', const Size(500, 900)),
    ('wide', const Size(1400, 900)),
  ]) {
    testWidgets('switching rewrites the dances, the defaults and the '
        'shorthands, drops the dialect entries, and retires the figure '
        '($layout)', (tester) async {
      final key = userFigureKeyFor('mine');
      final (:repos, :shorthands, :dialects) = await pump(
        tester,
        size: size,
        seed: (repos) async {
          await seedUses(repos);
          await repos.settings.set(
            kDefaultDanceFiguresTemplateKey,
            encodeFigures([
              use(const {'prefix': 'melt'}),
              Figure(move: 'allemande'),
            ]),
          );
          await repos.settings.set(
            kUserFigureShorthandsKey,
            UserFigureShorthands([
              UserFigureShorthand(
                token: 'bs',
                figureId: 'mine',
                figureName: 'swing',
                args: const {'prefix': 'bal'},
              ),
            ]).toJson(),
          );
          await repos.settings.set(kCustomDialectsKey, [
            Dialect.larksRobins
                .copyWith(name: 'Mine', moves: {key: 'whirl'})
                .toJson(),
          ]);
        },
      );

      await tester.tap(
        find.byKey(const ValueKey('glossary-custom-switch-to-shipped')),
      );
      await tester.pumpAndSettle();
      // Every parameter and value has a namesake in swing, so all are
      // chosen: the label "Balance" is swing's "balance".
      final save = find.byKey(const ValueKey('user-figure-switch-save'));
      expect(tester.widget<TextButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await settle(tester);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('user-figure-switch-confirm-body')),
            )
            .data,
        '1 dance uses your figure, and will use swing instead. Yours is '
        'removed from your Glossary. Your default figures use it too, and '
        'switch the same way. Its shorthand will insert swing.',
      );
      await tester.tap(
        find.byKey(const ValueKey('user-figure-switch-confirm')),
      );
      await settle(tester);

      final figure = (await figuresOf(tester, repos)).single;
      expect(figure.move, 'swing');
      expect(figure.params, {
        'who': 'partners',
        'prefix': 'balance',
        'beats': 8,
      });
      expect(
        await tester.runAsync(() => repos.userGlossary.getById('mine')),
        isNull,
      );

      final template = danceFiguresTemplateFromStored(
        await tester.runAsync<Object?>(
          () => repos.settings.get(kDefaultDanceFiguresTemplateKey),
        ),
      );
      expect(template.first.move, 'swing');
      expect(template.first.params, {
        'who': 'neighbors',
        'prefix': 'meltdown',
        'beats': 8,
      });
      expect(template.last.move, 'allemande');

      expect(shorthands.userFigureShorthands, isEmpty);
      final mapping = shorthands.mappings.single;
      expect(mapping.token, 'bs');
      expect(mapping.figures.single.move, 'swing');
      expect(mapping.figures.single.params, {
        'who': 'neighbors',
        'prefix': 'balance',
        'beats': 8,
      });

      expect(dialects.customByName('Mine')!.moves, isEmpty);

      if (layout == 'narrow') {
        expect(
          find.byKey(const ValueKey('glossary-custom-gone')),
          findsNothing,
          reason: 'the page of a retired figure closes',
        );
        expect(find.byKey(const ValueKey('glossary-search')), findsOneWidget);
      }
    });
  }

  testWidgets('a parameter the app\'s figure has nothing for can\'t be '
      'switched', (tester) async {
    await pump(
      tester,
      entry: mine(
        template: '{who} {move} {hand}',
        params: [
          {'key': 'who', 'kind': 'dancerSet'},
          {'key': 'hand', 'kind': 'handedness'},
        ],
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('glossary-custom-switch-to-shipped')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('user-figure-switch-none-hand')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('user-figure-switch-save')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('a choice value with no namesake must be chosen first', (
    tester,
  ) async {
    await pump(
      tester,
      entry: mine(
        params: [
          {'key': 'who', 'kind': 'dancerSet'},
          {
            'key': 'prefix',
            'kind': 'choice',
            'choices': [
              {'id': 'bal', 'label': 'balance'},
              {'id': 'drop', 'label': 'drop'},
            ],
          },
        ],
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('glossary-custom-switch-to-shipped')),
    );
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('user-figure-switch-save'));
    expect(tester.widget<TextButton>(save).onPressed, isNull);

    await tester.tap(
      find.byKey(
        const ValueKey('user-figure-switch-choice-prefix-drop-prefix'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('meltdown').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(save).onPressed, isNotNull);
  });

  testWidgets('two parameters can\'t become the same one, and the screen '
      'says why', (tester) async {
    await pump(
      tester,
      entry: mine(
        template: '{lead} and {follow} {move}',
        params: [
          {'key': 'lead', 'kind': 'dancerSet'},
          {'key': 'follow', 'kind': 'dancerSet'},
        ],
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('glossary-custom-switch-to-shipped')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('user-figure-switch-none-follow')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('user-figure-switch-param-lead')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .byWidgetPredicate(
            (w) => w is DropdownMenuItem<String> && w.value == 'who',
          )
          .last,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('user-figure-switch-none-follow')),
          )
          .data,
      contains('already chosen for another of yours'),
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('user-figure-switch-save')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('a shorthand whose token an ordinary shorthand has is kept '
      'as it is, and not counted', (tester) async {
    final (:repos, :shorthands, dialects: _) = await pump(
      tester,
      seed: (repos) async {
        await repos.settings.set(
          kShorthandMappingsKey,
          ShorthandMappings([
            ShorthandMapping(
              token: 'bs',
              figures: [Figure(move: 'balance')],
            ),
          ]).toJson(),
        );
        await repos.settings.set(
          kUserFigureShorthandsKey,
          UserFigureShorthands([
            UserFigureShorthand(
              token: 'BS',
              figureId: 'mine',
              figureName: 'swing',
              args: const {'prefix': 'bal'},
            ),
          ]).toJson(),
        );
      },
    );
    await tester.tap(
      find.byKey(const ValueKey('glossary-custom-switch-to-shipped')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('user-figure-switch-save')));
    await settle(tester);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('user-figure-switch-confirm-body')),
          )
          .data,
      isNot(contains('shorthand')),
    );
    await tester.tap(find.byKey(const ValueKey('user-figure-switch-confirm')));
    await settle(tester);
    expect(shorthands.mappings.single.figures.single.move, 'balance');
    expect(shorthands.userFigureShorthands.single.token, 'BS');
  });

  testWidgets('the app\'s values read as words, in the dialect', (
    tester,
  ) async {
    await pump(
      tester,
      entry: mine(
        template: '{side} {move}',
        params: [
          {
            'key': 'side',
            'kind': 'choice',
            'choices': [
              {'id': 'l', 'label': 'the larks'},
            ],
          },
        ],
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('glossary-custom-switch-to-shipped')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('user-figure-switch-param-side')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .byWidgetPredicate(
            (w) => w is DropdownMenuItem<String> && w.value == 'who',
          )
          .last,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('user-figure-switch-choice-side-l-who')),
    );
    await tester.pumpAndSettle();
    expect(find.text('role1s'), findsNothing);
    expect(find.text('larks'), findsWidgets);
  });

  testWidgets('cancelling at the confirmation writes nothing', (tester) async {
    final (:repos, shorthands: _, dialects: _) = await pump(
      tester,
      seed: seedUses,
    );
    await tester.tap(
      find.byKey(const ValueKey('glossary-custom-switch-to-shipped')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('user-figure-switch-save')));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect((await figuresOf(tester, repos)).single.move, customMoveId);
    expect(
      await tester.runAsync(() => repos.userGlossary.getById('mine')),
      isNotNull,
    );
  });

  testWidgets('a figure changed since it was mapped is not switched', (
    tester,
  ) async {
    final (:repos, shorthands: _, dialects: _) = await pump(
      tester,
      seed: seedUses,
    );
    await tester.tap(
      find.byKey(const ValueKey('glossary-custom-switch-to-shipped')),
    );
    await tester.pumpAndSettle();
    // An edit arrives (by sync, say) adding a parameter the mapping lacks.
    await tester.runAsync(
      () => repos.userGlossary.upsertFromRestore(
        mine(
          template: '{who} [{prefix}] {move} {hand}',
          params: [
            {'key': 'who', 'kind': 'dancerSet', 'default': 'neighbors'},
            {
              'key': 'prefix',
              'kind': 'choice',
              'choices': [
                {'id': 'bal', 'label': 'Balance'},
                {'id': 'melt', 'label': 'meltdown'},
              ],
            },
            {'key': 'hand', 'kind': 'handedness'},
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('user-figure-switch-save')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('user-figure-switch-confirm')));
    await settle(tester);
    expect(
      find.text(
        'Nothing was switched: your figure changed or is gone. Open it '
        'again to switch.',
      ),
      findsOneWidget,
    );
    expect((await figuresOf(tester, repos)).single.move, customMoveId);
    expect(
      await tester.runAsync(() => repos.userGlossary.getById('mine')),
      isNotNull,
    );
  });
}
