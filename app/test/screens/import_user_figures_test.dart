import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/show_custom_figures_scope.dart';
import 'package:compendium_app/src/data/show_glossary_scope.dart';
import 'package:compendium_app/src/glossary/user_figure_import.dart';
import 'package:compendium_app/src/screens/import_review_screen.dart';
import 'package:compendium_app/src/screens/import_user_figures_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// Adding a shared file's figures (#1023, maintainer decision 3; plan C12):
/// the step that offers them after the dances are in, what applying a
/// choice does, and its Undo.
void main() {
  final created = DateTime.utc(2026, 10, 16, 9);
  final now = DateTime.utc(2026, 10, 16, 10);

  UserGlossaryEntry figure(
    String id, {
    String kind = 'customFigure',
    String name = 'zoom',
    String template = '{move}',
    String? notes,
    DateTime? at,
  }) => UserGlossaryEntry(
    id: id,
    kindName: kind,
    name: name,
    definition: 'A figure called $name.',
    description: 'Of your own.',
    notes: notes,
    payload: {
      'form': 'contra',
      'template': template,
      'defaultBeats': 8,
      'params': <Object?>[],
    },
    createdAt: at ?? created,
  );

  Figure use(String id) =>
      userFigureUseFigure(id: id, args: const {}, text: 'figure $id');

  List<Figure> figuresOf(Dance d) =>
      (d.figuresSource as DecodedFigures).figures;

  group('ImportUserFiguresScreen', () {
    Future<UserFigureImportChoices? Function()> pumpScreen(
      WidgetTester tester,
      List<UserFigureImportItem> items, {
      Set<String> nameTaken = const {},
    }) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      UserFigureImportChoices? popped;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => popped = await Navigator.of(context)
                  .push<UserFigureImportChoices>(
                    MaterialPageRoute(
                      builder: (_) => ImportUserFiguresScreen(
                        items: items,
                        nameTaken: nameTaken,
                      ),
                    ),
                  ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return () => popped;
    }

    final items = [
      UserFigureImportItem(
        incoming: figure('new', name: 'whizz'),
        kind: UserFigureImportKind.add,
      ),
      UserFigureImportItem(
        incoming: figure('diff', template: '{move}!'),
        mine: figure('diff'),
        kind: UserFigureImportKind.differs,
      ),
      UserFigureImportItem(
        incoming: figure('taken', name: 'swoosh'),
        kind: UserFigureImportKind.copy,
      ),
      UserFigureImportItem(
        incoming: figure('same', name: 'twirl'),
        mine: figure('same', name: 'twirl'),
        kind: UserFigureImportKind.same,
      ),
    ];

    testWidgets('new figures and copies are ticked, yours are kept, and the '
        'same ones are only listed', (tester) async {
      final popped = await pumpScreen(tester, items, nameTaken: {'new'});
      expect(find.text('New to you'), findsOneWidget);
      expect(find.text('Different from yours'), findsOneWidget);
      expect(find.text('Added as a copy'), findsOneWidget);
      expect(find.text('Already in your Glossary'), findsOneWidget);
      expect(
        find.textContaining('your Glossary will mark it Rename needed'),
        findsOneWidget,
      );
      expect(find.text('Apply 2 changes'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('user-figure-import-confirm')),
      );
      await tester.pumpAndSettle();
      expect(popped()!.add, {'new', 'taken'});
      expect(popped()!.useTheirs, isEmpty);
    });

    testWidgets('choices follow the user', (tester) async {
      final popped = await pumpScreen(tester, items);
      await tester.tap(
        find.byKey(const ValueKey('user-figure-import-add-new')),
      );
      await tester.tap(find.text('Use theirs'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('user-figure-import-confirm')),
      );
      await tester.pumpAndSettle();
      expect(popped()!.add, {'taken'});
      expect(popped()!.useTheirs, {'diff'});
    });

    testWidgets('Skip adds nothing', (tester) async {
      final popped = await pumpScreen(tester, items);
      await tester.tap(find.byKey(const ValueKey('user-figure-import-skip')));
      await tester.pumpAndSettle();
      expect(popped()!.isEmpty, isTrue);
    });
  });

  group('applyUserFigureImport', () {
    test('adds, copies, replaces and undoes', () async {
      final repos = openTestRepositories();
      await repos.userGlossary.upsert(
        figure('diff', notes: 'my notes', at: created),
      );
      await repos.userGlossary.upsert(figure('taken', kind: 'compound'));
      await repos.dances.create(
        Dance(
          id: 'imported',
          title: 'Imported',
          figures: [use('copied')],
          createdAt: created,
          updatedAt: created,
        ),
      );
      await repos.dances.create(
        Dance(
          id: 'mine',
          title: 'Mine',
          figures: [use('copied')],
          createdAt: created,
          updatedAt: created,
        ),
      );
      final items = planUserFigureImport(
        [
          figure('new', name: 'whizz'),
          figure('diff', name: 'zoom again', at: now),
          figure('copied', name: 'swoosh'),
        ],
        entries: await repos.userGlossary.listAll(),
        deletedIds: {'copied'},
      );

      final applied = await applyUserFigureImport(
        repos,
        items,
        const UserFigureImportChoices(
          add: {'new', 'copied'},
          useTheirs: {'diff'},
        ),
        importedDanceIds: ['imported'],
        newId: () => 'copy-id',
        now: now,
      );

      expect(applied.addedIds, ['new', 'copy-id']);
      expect(applied.count, 3);
      expect(applied.failed, 0);
      expect((await repos.userGlossary.getById('new'))?.name, 'whizz');
      expect((await repos.userGlossary.getById('copy-id'))?.name, 'swoosh');
      final replaced = (await repos.userGlossary.getById('diff'))!;
      expect(replaced.name, 'zoom again');
      expect(replaced.notes, 'my notes', reason: 'your notes are kept');
      expect(replaced.createdAt, created);
      expect(
        userFigureUseOf(
          figuresOf((await repos.dances.getById('imported'))!).single,
        )?.id,
        'copy-id',
      );
      expect(
        userFigureUseOf(
          figuresOf((await repos.dances.getById('mine'))!).single,
        )?.id,
        'copied',
        reason: 'only the dances the import wrote point at the copy',
      );

      await applied.undo(repos);
      expect(await repos.userGlossary.getById('new'), isNull);
      expect(await repos.userGlossary.getById('copy-id'), isNull);
      final restored = (await repos.userGlossary.getById('diff'))!;
      expect(restored.name, 'zoom');
      expect(restored.notes, 'my notes');
    });

    test('a figure the glossary refuses is counted, never thrown', () async {
      final repos = openTestRepositories();
      final items = planUserFigureImport([
        figure('é-not-normal'),
      ], entries: const []);
      final applied = await applyUserFigureImport(
        repos,
        items,
        const UserFigureImportChoices(add: {'é-not-normal'}),
        importedDanceIds: const [],
        newId: () => 'unused',
        now: now,
      );
      expect(applied.failed, 1);
      expect(applied.addedIds, isEmpty);
    });
  });

  group('importing a shared file', () {
    CompendiumArchive archive() => CompendiumArchive(
      exportedAt: now,
      dances: [
        Dance(
          id: 'd1',
          title: 'Zoom Reel',
          figures: [use('zoom-id')],
          createdAt: created,
          updatedAt: created,
        ),
      ],
      userFigures: [figure('zoom-id')],
    );

    Future<void> pumpShared(
      WidgetTester tester,
      CompendiumRepositories repos, {
      bool customFigures = true,
      bool picked = false,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final glossary = ValueNotifier(true);
      final custom = ValueNotifier(customFigures);
      addTearDown(glossary.dispose);
      addTearDown(custom.dispose);
      final json = encodeArchive(archive());
      final decoded = decodeArchive(json).archive;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) => RepositoriesScope(
            repositories: repos,
            child: ShowGlossaryScope(
              notifier: glossary,
              child: ShowCustomFiguresScope(notifier: custom, child: child!),
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('open-review'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ImportReviewScreen(
                        sources: [
                          ImportSource(
                            kind: ImportSourceKind.genericJson,
                            adapterFactory: GenericJsonAdapter.new,
                          ),
                        ],
                        sharedBundle: picked
                            ? null
                            : SharedBundleImport(
                                json: json,
                                archive: decoded,
                                entityCount: compendiumArchiveEntityCount(
                                  decoded,
                                ),
                              ),
                        picker: picked ? () async => json : null,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-review')));
      await tester.pumpAndSettle();
      if (picked) {
        await tester.tap(find.byKey(const ValueKey('import-choose-file')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('import-continue')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('import-commit-button')));
      await tester.pumpAndSettle();
    }

    testWidgets('offers the file\'s figures once its dances are in; Undo '
        'takes both back', (tester) async {
      final repos = openTestRepositories();
      await pumpShared(tester, repos);

      expect(find.byType(ImportUserFiguresScreen), findsOneWidget);
      expect(await repos.dances.listAll(), hasLength(1));
      await tester.tap(
        find.byKey(const ValueKey('user-figure-import-confirm')),
      );
      await tester.pumpAndSettle();

      expect((await repos.userGlossary.getById('zoom-id'))?.name, 'zoom');
      expect(find.text('Imported 2 items.'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(await repos.dances.listAll(), isEmpty);
      expect(await repos.userGlossary.getById('zoom-id'), isNull);
    });

    testWidgets('nothing is offered while Custom Figures is off', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await pumpShared(tester, repos, customFigures: false);

      expect(find.byType(ImportUserFiguresScreen), findsNothing);
      expect(await repos.dances.listAll(), hasLength(1));
      expect(await repos.userGlossary.getById('zoom-id'), isNull);
      expect(
        find.byKey(const ValueKey('shared-import-undo-snackbar')),
        findsOneWidget,
      );
    });

    testWidgets('a picked file whose only other content is figures is '
        'imported as a shared file, so they are offered', (tester) async {
      final repos = openTestRepositories();
      await pumpShared(tester, repos, picked: true);
      expect(find.byType(ImportUserFiguresScreen), findsOneWidget);
    });

    testWidgets('nothing is offered when every figure is already here', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.userGlossary.upsert(figure('zoom-id'));
      await pumpShared(tester, repos);
      expect(find.byType(ImportUserFiguresScreen), findsNothing);
    });
  });
}
