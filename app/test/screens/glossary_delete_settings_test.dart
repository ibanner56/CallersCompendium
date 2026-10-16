import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/dialect_library_controller.dart';
import 'package:compendium_app/src/data/dialect_library_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/program_matrix_column_config_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/settings_keys.dart';
import 'package:compendium_app/src/data/show_custom_figures_scope.dart';
import 'package:compendium_app/src/data/show_glossary_scope.dart';
import 'package:compendium_app/src/screens/glossary/glossary_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// Deleting one of the user's own new figures (#1023, plan C9) also drops what
/// the settings keep for it: each dialect's name and wording for it, and its
/// matrix column's place, hiding and rename.
void main() {
  final created = DateTime.utc(2026, 10, 16);
  final key = userFigureKeyFor('zoom-id');

  UserGlossaryEntry figure(String id, String name) => UserGlossaryEntry(
    id: id,
    kindName: UserGlossaryEntryKind.customFigure.name,
    name: name,
    definition: 'A figure.',
    description: 'Of your own.',
    payload: const {
      'template': '{move}',
      'defaultBeats': 8,
      'params': <Object?>[],
    },
    createdAt: created,
  );

  // Narrow, the detail is a pushed page; wide, it is a pane the delete
  // unmounts as soon as the list no longer holds the entry.
  for (final (layout, size) in [
    ('narrow', const Size(500, 900)),
    ('wide', const Size(1400, 900)),
  ]) {
    testWidgets('deleting a figure drops its dialect entries and its matrix '
        'column, and leaves the others ($layout)', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repos = openTestRepositories();
      final other = userFigureKeyFor('other-id');
      final mine = Dialect.larksRobins.copyWith(
        name: 'Mine',
        moves: {key: 'whizz', other: 'swoosh', 'swing': 'twirl'},
        moveWordings: {key: '{move}!'},
      );
      final matrixConfig = MatrixColumnConfig(
        order: [key, other, 'swing:partner'],
        hidden: {key},
        renames: {key: 'Z', other: 'O'},
      );
      final dialects = DialectLibraryController(repos.settings);
      addTearDown(dialects.dispose);
      await tester.runAsync(() async {
        await repos.userGlossary.upsert(figure('zoom-id', 'zoom'));
        await repos.userGlossary.upsert(figure('other-id', 'other'));
        await repos.settings.set(
          kProgramMatrixColumnsKey,
          matrixConfig.toJson(),
        );
        await dialects.load();
        await dialects.upsert(mine);
        // The active dialect is the custom one, whose copy is kept apart too.
        await dialects.setActive('Mine');
      });
      final matrix = ValueNotifier(matrixConfig);
      final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
      final glossary = ValueNotifier(true);
      final custom = ValueNotifier(true);
      for (final n in <ChangeNotifier>[matrix, dialect, glossary, custom]) {
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
                child: ProgramMatrixColumnConfigScope(
                  notifier: matrix,
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
        'zoom',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('glossary-entry-custom:zoom-id')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('glossary-custom-delete')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('glossary-custom-delete-confirm')),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      final kept = dialects.customByName('Mine')!;
      expect(kept.moves, {other: 'swoosh', 'swing': 'twirl'});
      expect(kept.moveWordings, isEmpty);
      final storedDialects = await tester.runAsync<Object?>(
        () => repos.settings.get(kCustomDialectsKey),
      );
      expect(
        Dialect.fromJson(
          ((storedDialects! as List).single as Map).cast<String, Object?>(),
        ).moves,
        {other: 'swoosh', 'swing': 'twirl'},
      );

      final activeCopy = await tester.runAsync<Object?>(
        () => repos.settings.get(kActiveDialectKey),
      );
      expect(
        Dialect.fromJson((activeCopy! as Map).cast<String, Object?>()).moves,
        {other: 'swoosh', 'swing': 'twirl'},
      );

      final expected = MatrixColumnConfig(
        order: [other, 'swing:partner'],
        renames: {other: 'O'},
      );
      expect(matrix.value, expected);
      expect(
        MatrixColumnConfig.tryDecode(
          await tester.runAsync<Object?>(
            () => repos.settings.get(kProgramMatrixColumnsKey),
          ),
        ),
        expected,
      );
    });
  }

  testWidgets('deleting a figure freezes its uses in the default figure '
      'lists, and the dialog counts the Trash and the defaults', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    Figure use() => userFigureUseFigure(
      id: 'zoom-id',
      args: const {},
      text: 'a stale line',
      beats: 8,
    );
    final created = DateTime.utc(2026, 10, 16);
    await tester.runAsync(() async {
      await repos.userGlossary.upsert(figure('zoom-id', 'zoom'));
      await repos.settings.set(
        kDefaultDanceFiguresTemplateKey,
        encodeFigures([use(), Figure(move: 'swing')]),
      );
      await repos.settings.set(
        kDefaultModifierFiguresKey,
        encodeModifierFigures([use()]),
      );
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'Binned',
          figures: [use()],
          createdAt: created,
          updatedAt: created,
        ),
      );
      await repos.dances.softDelete('d1', at: created);
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
            child: ShowGlossaryScope(
              notifier: glossary,
              child: ShowCustomFiguresScope(notifier: custom, child: child!),
            ),
          ),
        ),
        home: const GlossaryScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('glossary-search')),
      'zoom',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('glossary-entry-custom:zoom-id')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glossary-custom-delete')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('glossary-custom-delete-body')),
          )
          .data,
      "No dance uses it. It's removed from your Glossary. 1 dance in the "
      'Trash uses it too, and keeps the line it last stored. Your default '
      'figures in Settings use it too, and keep its current wording as plain '
      'text.',
    );
    await tester.tap(
      find.byKey(const ValueKey('glossary-custom-delete-confirm')),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final template = danceFiguresTemplateFromStored(
      await tester.runAsync<Object?>(
        () => repos.settings.get(kDefaultDanceFiguresTemplateKey),
      ),
    );
    expect(template.first.params, {'text': 'zoom', 'beats': 8});
    expect(template.last.move, 'swing');
    final modifiers = modifierFiguresFromStored(
      await tester.runAsync<Object?>(
        () => repos.settings.get(kDefaultModifierFiguresKey),
      ),
    );
    expect(userFigureUseOf(modifiers.single), isNull);
    expect(modifiers.single.params['text'], 'zoom');
  });
}
