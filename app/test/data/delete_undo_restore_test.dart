// Undo of the deletes whose data lives in settings values: each controller's
// restore puts back exactly what the delete removed, where it was, and refuses
// rather than overwrite something made in between.
import 'package:compendium_app/src/data/custom_theme.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/dialect_library_controller.dart';
import 'package:compendium_app/src/data/shorthand_mappings_controller.dart';
import 'package:compendium_app/src/data/walkthrough_snippet_library_controller.dart';
import 'package:compendium_app/src/screens/settings/matrix_column_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

Figure _swing() =>
    testFigure(move: 'swing', params: {'who': 'neighbors', 'beats': 16});

CustomTheme _theme(String id, String name) => CustomTheme(
  id: id,
  name: name,
  brightness: Brightness.light,
  roles: const {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShorthandMappingsController.restoreAt', () {
    test(
      'puts a deleted shorthand back where it was, and persists it',
      () async {
        final repos = openTestRepositories();
        final controller = ShorthandMappingsController(repos.settings);
        for (final token in ['a', 'b', 'c']) {
          await controller.upsert(
            ShorthandMapping(token: token, figures: [_swing()]),
          );
        }
        final removed = controller.mappings[1];
        await controller.removeAt(1);

        await controller.restoreAt(1, removed);

        expect([for (final m in controller.mappings) m.token], ['a', 'b', 'c']);
        final reloaded = ShorthandMappingsController(repos.settings);
        await reloaded.load();
        expect([for (final m in reloaded.mappings) m.token], ['a', 'b', 'c']);
      },
    );

    test('refuses when the token has been taken since', () async {
      final repos = openTestRepositories();
      final controller = ShorthandMappingsController(repos.settings);
      await controller.upsert(
        ShorthandMapping(token: 'a', figures: [_swing()]),
      );
      final removed = controller.mappings.single;
      await controller.removeAt(0);
      await controller.upsert(
        ShorthandMapping(token: 'A', figures: [_swing()]),
      );

      await expectLater(
        controller.restoreAt(0, removed),
        throwsA(isA<ArgumentError>()),
      );
      expect(controller.mappings, hasLength(1));
    });
  });

  group('DialectLibraryController.restoreDeleted', () {
    test(
      'puts the dialect back at its place and makes it active again',
      () async {
        final repos = openTestRepositories();
        final controller = DialectLibraryController(repos.settings);
        await controller.upsert(Dialect.leadsFollows.copyWith(name: 'One'));
        await controller.upsert(Dialect.leadsFollows.copyWith(name: 'Two'));
        await controller.setActive('One');
        final removed = controller.customByName('One')!;
        await controller.delete('One');
        expect(controller.activeName, isNot('One'));

        await controller.restoreDeleted(removed, index: 0, wasActive: true);

        expect(
          [for (final d in controller.customDialects) d.name],
          ['One', 'Two'],
        );
        expect(controller.activeName, 'One');
        final reloaded = DialectLibraryController(repos.settings);
        await reloaded.load();
        expect(reloaded.activeName, 'One');
        expect(reloaded.customByName('One'), isNotNull);
      },
    );

    test('keeps a dialect the user chose after the delete', () async {
      final repos = openTestRepositories();
      final controller = DialectLibraryController(repos.settings);
      await controller.upsert(Dialect.leadsFollows.copyWith(name: 'One'));
      await controller.setActive('One');
      final removed = controller.customByName('One')!;
      await controller.delete('One');
      await controller.setActive(Dialect.leadsFollows.name);

      await controller.restoreDeleted(removed, index: 0, wasActive: true);

      expect(controller.activeName, Dialect.leadsFollows.name);
      expect(controller.customByName('One'), isNotNull);
    });

    test('refuses when a dialect has taken the name since', () async {
      final repos = openTestRepositories();
      final controller = DialectLibraryController(repos.settings);
      await controller.upsert(Dialect.leadsFollows.copyWith(name: 'One'));
      final removed = controller.customByName('One')!;
      await controller.delete('One');
      await controller.upsert(Dialect.canonical.copyWith(name: 'One'));

      await expectLater(
        controller.restoreDeleted(removed, index: 0, wasActive: false),
        throwsA(isA<ArgumentError>()),
      );
      expect(controller.customDialects, hasLength(1));
    });
  });

  group('CustomThemesController.restoreDeleted', () {
    test(
      'puts the theme back at its place and makes it active again',
      () async {
        final repos = openTestRepositories();
        final controller = CustomThemesController(repos.settings);
        await controller.upsert(_theme('t1', 'Dawn'));
        await controller.upsert(_theme('t2', 'Dusk'));
        await controller.setActive('t1');
        final removed = controller.byId('t1')!;
        await controller.delete('t1');
        expect(controller.activeId, isNull);

        await controller.restoreDeleted(removed, index: 0, wasActive: true);

        expect([for (final t in controller.themes) t.id], ['t1', 't2']);
        expect(controller.activeId, 't1');
        final reloaded = CustomThemesController(repos.settings);
        await reloaded.load();
        expect(reloaded.activeId, 't1');
      },
    );

    test('leaves a theme made active since alone', () async {
      final repos = openTestRepositories();
      final controller = CustomThemesController(repos.settings);
      await controller.upsert(_theme('t1', 'Dawn'));
      await controller.upsert(_theme('t2', 'Dusk'));
      await controller.setActive('t1');
      final removed = controller.byId('t1')!;
      await controller.delete('t1');
      await controller.setActive('t2');

      await controller.restoreDeleted(removed, index: 0, wasActive: true);

      expect(controller.activeId, 't2');
    });

    // Sync can bring the theme back (same id) before Undo is tapped; Undo
    // must not then insert a second theme with that id.
    test('refuses when a theme with its id exists again', () async {
      final repos = openTestRepositories();
      final controller = CustomThemesController(repos.settings);
      await controller.upsert(_theme('t1', 'Dawn'));
      final removed = controller.byId('t1')!;
      await controller.delete('t1');
      await controller.upsert(_theme('t1', 'Dawn, synced'));

      await expectLater(
        controller.restoreDeleted(removed, index: 0, wasActive: false),
        throwsA(isA<ArgumentError>()),
      );
      expect([for (final t in controller.themes) t.name], ['Dawn, synced']);
    });
  });

  group('ShorthandMappingsController.restoreUserFigureAt', () {
    UserFigureShorthand shorthand({int? beats}) => UserFigureShorthand(
      token: 'ZM',
      figureId: 'zoom-id',
      figureName: 'zoom',
      beats: beats,
    );

    test('puts a deleted shorthand back, and persists it', () async {
      final repos = openTestRepositories();
      final controller = ShorthandMappingsController(repos.settings);
      await controller.upsertUserFigure(shorthand(beats: 4));
      final removed = controller.userFigureShorthands.single;
      await controller.removeUserFigureAt(0);

      await controller.restoreUserFigureAt(0, removed);

      final reloaded = ShorthandMappingsController(repos.settings);
      await reloaded.load();
      expect([for (final s in reloaded.userFigureShorthands) s.token], ['ZM']);
    });

    test('refuses a shorthand the next load would drop', () async {
      final repos = openTestRepositories();
      final controller = ShorthandMappingsController(repos.settings);
      // More beats than a figure of the user's may default to: decode drops
      // it, so putting it back would "succeed" and then vanish on reload.
      final unkeepable = shorthand(beats: maxUserFigureDefaultBeats + 1);
      expect(UserFigureShorthands.keeps(unkeepable), isFalse);

      await expectLater(
        controller.restoreUserFigureAt(0, unkeepable),
        throwsA(isA<ArgumentError>()),
      );
      expect(controller.userFigureShorthands, isEmpty);
    });
  });

  group('WalkthroughSnippetLibraryController.restoreSnippet', () {
    test('puts the stored text back', () async {
      final repos = openTestRepositories();
      final controller = WalkthroughSnippetLibraryController(repos.settings);
      await controller.setSnippet('sig', 'Swing your neighbour.');
      await controller.removeSnippet('sig');

      await controller.restoreSnippet('sig', 'Swing your neighbour.');

      expect(controller.library.snippets['sig'], 'Swing your neighbour.');
      final reloaded = WalkthroughSnippetLibraryController(repos.settings);
      await reloaded.load();
      expect(reloaded.library.snippets['sig'], 'Swing your neighbour.');
    });

    test('refuses to overwrite a snippet written since', () async {
      final repos = openTestRepositories();
      final controller = WalkthroughSnippetLibraryController(repos.settings);
      await controller.setSnippet('sig', 'Old.');
      await controller.removeSnippet('sig');
      await controller.setSnippet('sig', 'New.');

      await expectLater(
        controller.restoreSnippet('sig', 'Old.'),
        throwsA(isA<StateError>()),
      );
      expect(controller.library.snippets['sig'], 'New.');
    });
  });

  group('restoreDeletedMatrixColumn', () {
    const id = 'compound:seq';
    const column = CompoundColumn(
      id: id,
      steps: [
        StepMatcher(move: 'do_si_do'),
        StepMatcher(move: 'balance'),
      ],
    );
    const other = ParameterizedColumn(id: 'param:z', baseMove: 'swing');
    final before = MatrixColumnConfig(
      order: const ['swing', id, 'circle'],
      hidden: const {id},
      renames: const {id: 'Sequence'},
      compound: const [column],
    );
    final afterDelete = MatrixColumnConfig(order: const ['swing', 'circle']);

    test('puts every piece of the column back', () {
      final restored = restoreDeletedMatrixColumn(
        afterDelete,
        before: before,
        id: id,
      );
      expect(restored.compound, [column]);
      expect(restored.order, ['swing', id, 'circle']);
      expect(restored.hidden, {id});
      expect(restored.renames, {id: 'Sequence'});
    });

    test('keeps an edit made after the delete', () {
      final edited = afterDelete.copyWith(
        parameterized: const [other],
        renames: const {'swing': 'Swing!'},
      );
      final restored = restoreDeletedMatrixColumn(
        edited,
        before: before,
        id: id,
      );
      expect(restored.parameterized, [other]);
      expect(restored.renames, {'swing': 'Swing!', id: 'Sequence'});
      expect(restored.compound, [column]);
    });

    test('refuses when the column is back already', () {
      expect(
        () => restoreDeletedMatrixColumn(before, before: before, id: id),
        throwsStateError,
      );
    });
  });
}
