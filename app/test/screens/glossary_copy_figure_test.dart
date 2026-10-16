import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/show_custom_figures_scope.dart';
import 'package:compendium_app/src/data/show_glossary_scope.dart';
import 'package:compendium_app/src/screens/glossary/compound_editor_screen.dart';
import 'package:compendium_app/src/screens/glossary/glossary_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// Copying a built-in figure as one of the user's own (#1023, maintainer
/// decision 6): an independent copy, saved only when the user saves it.
void main() {
  Future<CompendiumRepositories> pump(
    WidgetTester tester, {
    bool customFigures = true,
    CompendiumRepositories? repositories,
    Size size = const Size(500, 1400),
    Dialect? dialect,
    String search = 'swing',
    String entryId = 'swing',
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = repositories ?? openTestRepositories();
    final active = ValueNotifier<Dialect>(dialect ?? Dialect.canonical);
    final glossary = ValueNotifier(true);
    final custom = ValueNotifier(customFigures);
    for (final n in <ChangeNotifier>[active, glossary, custom]) {
      addTearDown(n.dispose);
    }
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(
            notifier: active,
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
      search,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('glossary-entry-$entryId')));
    await tester.pumpAndSettle();
    return repos;
  }

  Future<void> copyAndSave(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(const ValueKey('glossary-copy-figure')),
    );
    await tester.tap(find.byKey(const ValueKey('glossary-copy-figure')));
    await tester.pumpAndSettle();
    expect(find.byType(CompoundEditorScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('compound-editor-save')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  testWidgets('copies a built-in figure as a new one of your own, with its '
      'parameters, beats, wording and definition, and leaves the built-in '
      'alone', (tester) async {
    final repos = await pump(tester);
    await copyAndSave(tester);

    final entries = await tester.runAsync(repos.userGlossary.listAll);
    final copy = entries!.single;
    expect(copy.kind, UserGlossaryEntryKind.customFigure);
    expect(copy.id, isNot(''), reason: 'saved under a new id of its own');
    expect(copy.name, 'swing (copy)');
    expect(copy.definition, isNotEmpty);
    final definition = decodeUserFigureDefinition(copy.payload)!;
    expect(definition.copiedFrom, 'swing');
    expect(definition.params.map((p) => p.key), ['who', 'prefix']);
    expect(definition.defaultBeats, 8);
  });

  testWidgets('narrow, the copy\'s page takes the built-in\'s place once it '
      'is saved', (tester) async {
    await pump(tester);
    await copyAndSave(tester);
    expect(
      find.byKey(const ValueKey('glossary-custom-detail')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('glossary-copy-figure')), findsNothing);
  });

  testWidgets('backing out of the editor stores nothing', (tester) async {
    final repos = await pump(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('glossary-copy-figure')),
    );
    await tester.tap(find.byKey(const ValueKey('glossary-copy-figure')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(await tester.runAsync(repos.userGlossary.listAll), isEmpty);
  });

  testWidgets('a second copy is numbered', (tester) async {
    final repos = openTestRepositories();
    await tester.runAsync(
      () => repos.userGlossary.upsert(
        UserGlossaryEntry(
          id: 'first',
          kindName: UserGlossaryEntryKind.customFigure.name,
          name: 'swing (copy)',
          definition: 'A copy.',
          description: 'Mine.',
          payload: userFigureSeedFromMove(contraTaxonomy, 'swing')!.toJson(),
          createdAt: DateTime.utc(2026, 10, 16),
        ),
      ),
    );
    await pump(tester, repositories: repos);
    await copyAndSave(tester);
    final names = [
      for (final e in (await tester.runAsync(repos.userGlossary.listAll))!)
        e.name,
    ];
    expect(names, containsAll(['swing (copy)', 'swing (copy) 2']));
  });

  testWidgets('a name is numbered in the form names are stored in', (
    tester,
  ) async {
    // A dialect that names a figure with a role word: the copy's name is
    // stored with the role's canonical token, and compared so.
    final repos = openTestRepositories();
    await tester.runAsync(
      () => repos.userGlossary.upsert(
        UserGlossaryEntry(
          id: 'first',
          kindName: UserGlossaryEntryKind.customFigure.name,
          name: 'role1s chain (copy)',
          definition: 'A copy.',
          description: 'Mine.',
          payload: userFigureSeedFromMove(contraTaxonomy, 'chain')!.toJson(),
          createdAt: DateTime.utc(2026, 10, 16),
        ),
      ),
    );
    await pump(
      tester,
      repositories: repos,
      dialect: Dialect.larksRobins.copyWith(
        name: 'Mine',
        moves: {'chain': 'larks chain'},
      ),
      search: 'chain',
      entryId: 'chain',
    );
    await copyAndSave(tester);
    final names = [
      for (final e in (await tester.runAsync(repos.userGlossary.listAll))!)
        e.name,
    ];
    expect(names, contains('role1s chain (copy) 2'));
  });

  testWidgets('a copy says what it was copied from', (tester) async {
    // Wide: the saved copy is selected beside the list.
    await pump(tester, size: const Size(1400, 1400));
    await copyAndSave(tester);
    expect(
      find.byKey(const ValueKey('glossary-custom-copied-from')),
      findsOneWidget,
    );
    expect(find.text('Copied from swing'), findsOneWidget);
  });

  testWidgets('nothing is offered while Custom Figures is off', (tester) async {
    await pump(tester, customFigures: false);
    expect(find.byKey(const ValueKey('glossary-copy-figure')), findsNothing);
  });
}
