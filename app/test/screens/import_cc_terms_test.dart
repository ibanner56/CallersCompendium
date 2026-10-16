import 'dart:typed_data';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/shorthand_mappings_controller.dart';
import 'package:compendium_app/src/data/shorthand_mappings_scope.dart';
import 'package:compendium_app/src/data/show_glossary_scope.dart';
import 'package:compendium_app/src/glossary/cc_term_import.dart';
import 'package:compendium_app/src/screens/import_cc_terms_screen.dart';
import 'package:compendium_app/src/screens/import_review_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fmp_fixture_builder.dart';
import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// A Caller's Companion file's own glossary terms, offered after its import
/// (#1023, maintainer decision 7, and the maintainer's calls of 2026-10-16).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final twirl = CcTerm(
    name: 'Dixie Twirl',
    definition: 'The left pair go under an arch.',
    source: 'Give and Take - Larry Jennings',
  );
  final corners = CcTerm(
    name: 'Contra Corners',
    notes: 'Free your right hand first.',
  );
  final noDefinition = CcTerm(name: 'Whirligig', notes: 'Ask the band.');

  Future<List<CcTermDraft>?> openScreen(
    WidgetTester tester,
    List<CcTerm> terms, {
    bool Function(String name)? nameTaken,
  }) async {
    List<CcTermDraft>? popped;
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('launch'),
            onPressed: () async {
              popped = await Navigator.of(context).push<List<CcTermDraft>>(
                MaterialPageRoute(
                  builder: (_) => ImportCcTermsScreen(
                    terms: terms,
                    nameTaken: nameTaken ?? (_) => false,
                  ),
                ),
              );
              done = true;
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('launch')));
    await tester.pumpAndSettle();
    addTearDown(() => expect(done || popped == null, isTrue));
    return null;
  }

  bool ticked(WidgetTester tester, int index) =>
      tester
          .widget<CheckboxListTile>(
            find.byKey(ValueKey('cc-term-import-$index')),
          )
          .value ??
      false;

  bool enabled(WidgetTester tester, int index) =>
      tester
          .widget<CheckboxListTile>(
            find.byKey(ValueKey('cc-term-import-$index')),
          )
          .onChanged !=
      null;

  testWidgets('a complete, free term is ticked, with its source; its '
      'description starts as its definition', (tester) async {
    await openScreen(tester, [twirl]);
    expect(ticked(tester, 0), isTrue);
    expect(find.text('Source: Give and Take - Larry Jennings'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cc-term-import-edit-0')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('cc-term-edit-description')),
          )
          .controller!
          .text,
      'The left pair go under an arch.',
    );
  });

  testWidgets('a term with no definition is offered unticked until it has '
      'one', (tester) async {
    await openScreen(tester, [noDefinition]);
    expect(ticked(tester, 0), isFalse);
    expect(enabled(tester, 0), isFalse);
    expect(
      find.byKey(const ValueKey('cc-term-import-needs-definition-0')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('cc-term-import-confirm')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('cc-term-import-edit-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('cc-term-edit-definition')),
      'A spinning figure.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('cc-term-edit-description')),
      'Spin in place.',
    );
    await tester.tap(find.byKey(const ValueKey('cc-term-edit-save')));
    await tester.pumpAndSettle();
    expect(ticked(tester, 0), isTrue);
    expect(
      find.byKey(const ValueKey('cc-term-import-needs-definition-0')),
      findsNothing,
    );
  });

  testWidgets('a term whose name is taken can only be left out, or renamed', (
    tester,
  ) async {
    await openScreen(tester, [
      twirl,
    ], nameTaken: (name) => name.toLowerCase() == 'dixie twirl');
    expect(ticked(tester, 0), isFalse);
    expect(enabled(tester, 0), isFalse);
    expect(
      find.text(
        'A figure, shorthand or term already has this name. Rename it to add '
        'it, or leave it out.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('cc-term-import-edit-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('cc-term-edit-name')),
      'Dixie Twirl (CC)',
    );
    await tester.tap(find.byKey(const ValueKey('cc-term-edit-save')));
    await tester.pumpAndSettle();
    expect(ticked(tester, 0), isTrue);
  });

  testWidgets('a second term of the same name in the file is taken too, and '
      'renaming the first onto another unticks that one and frees the second', (
    tester,
  ) async {
    await openScreen(tester, [
      twirl,
      CcTerm(name: 'dixie  twirl', definition: 'Again.'),
      CcTerm(name: 'Spin', definition: 'Turn.'),
    ]);
    expect(ticked(tester, 0), isTrue);
    expect(ticked(tester, 1), isFalse);
    expect(enabled(tester, 1), isFalse);
    expect(ticked(tester, 2), isTrue);

    await tester.tap(find.byKey(const ValueKey('cc-term-import-edit-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('cc-term-edit-name')),
      'spin',
    );
    await tester.tap(find.byKey(const ValueKey('cc-term-edit-save')));
    await tester.pumpAndSettle();
    expect(ticked(tester, 0), isTrue);
    expect(
      enabled(tester, 1),
      isTrue,
      reason: 'its name is free again: it can be ticked',
    );
    expect(
      ticked(tester, 1),
      isFalse,
      reason: 'only the term edited is ticked for the user',
    );
    expect(ticked(tester, 2), isFalse, reason: 'the first now has its name');
  });

  group('applyCcTermImport', () {
    final now = DateTime.utc(2026, 10, 16, 12);
    var n = 0;
    String newId() => 'term-${n++}';

    test('adds each as a term, stored as the editor stores it, with its '
        'source and notes; undo erases them', () async {
      final repos = openTestRepositories();
      addTearDown(repos.db.close);
      final applied = await applyCcTermImport(
        repos.userGlossary,
        [
          CcTermDraft.of(twirl),
          CcTermDraft.of(corners).copyWith(
            definition: 'Each corner in turn.',
            description: 'Turn your corners.',
          ),
        ],
        dialect: Dialect.larksRobins,
        newId: newId,
        now: now,
      );
      expect(applied.addedIds, hasLength(2));
      expect(applied.failed, 0);
      final added = await repos.userGlossary.getById(applied.addedIds.first);
      expect(added!.kind, UserGlossaryEntryKind.term);
      expect(added.name, 'Dixie Twirl');
      expect(added.description, 'The left pair go under an arch.');
      expect(
        glossaryTermSource(added.payload),
        'Give and Take - Larry Jennings',
      );
      final second = await repos.userGlossary.getById(applied.addedIds.last);
      expect(second!.notes, 'Free your right hand first.');
      expect(glossaryTermSource(second.payload), isNull);

      await applied.undo();
      expect(await repos.userGlossary.listAll(includeDeleted: true), isEmpty);
    });

    test(
      'a term the glossary refuses is counted, and the rest added',
      () async {
        final repos = openTestRepositories();
        addTearDown(repos.db.close);
        final applied = await applyCcTermImport(
          repos.userGlossary,
          [
            CcTermDraft.of(twirl).copyWith(name: 'x' * 201),
            CcTermDraft.of(twirl),
          ],
          dialect: Dialect.larksRobins,
          newId: newId,
          now: now,
        );
        expect(applied.failed, 1);
        expect(applied.addedIds, hasLength(1));
      },
    );
  });

  group('after a Caller\'s Companion import', () {
    Uint8List usr() => buildFmp12Fixture([
      FmpFixtureTable(
        index: 1,
        name: 'Dance',
        columnNames: ['zk_Dance_ID', 'Name', 'Author1'],
        rows: [
          MapEntry(10, {1: '4', 2: 'Simplicity Swing', 3: 'Becky Hill'}),
        ],
      ),
      FmpFixtureTable(
        index: 2,
        name: 'Term',
        columnNames: ['Term', 'Definition', 'Source', 'zk_Constant', 'Notes'],
        rows: [
          MapEntry(20, {
            1: 'Dixie Twirl',
            2: 'The left pair go under an arch.',
            3: 'Give and Take - Larry Jennings',
            4: '1',
          }),
          MapEntry(21, {1: 'Contra Corners', 4: '1', 5: 'A teaching note.'}),
        ],
      ),
      // A call button, so the shorthand step comes first and is answered
      // after Done has closed the review (#1819), as with a real file.
      FmpFixtureTable(
        index: 3,
        name: 'InsertCall',
        columnNames: [
          'InsertButtonLabel',
          'InsertButtonText',
          'zk_Constant',
          'InsertButtonBeats',
        ],
        rows: [
          MapEntry(900, {
            1: 'B&S-N',
            2: 'neighbor balance and swing',
            3: '1',
            4: '16',
          }),
        ],
      ),
    ]);

    Future<CompendiumRepositories> runImport(
      WidgetTester tester, {
      required bool glossary,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repos = openTestRepositories();
      final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
      final shown = ValueNotifier(glossary);
      addTearDown(dialect.dispose);
      addTearDown(shown.dispose);
      final shorthands = ShorthandMappingsController(repos.settings);
      addTearDown(shorthands.dispose);
      await tester.runAsync(shorthands.load);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) => RepositoriesScope(
            repositories: repos,
            child: ActiveDialectScope(
              notifier: dialect,
              child: ShorthandMappingsScope(
                controller: shorthands,
                child: ShowGlossaryScope(notifier: shown, child: child!),
              ),
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const ValueKey('launch'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ImportReviewScreen(
                      sources: [
                        ImportSource(
                          kind: ImportSourceKind.callersCompanionUsr,
                          adapterFactory: CallersCompanionUsrAdapter.new,
                          bytePicker: () async => usr(),
                        ),
                      ],
                      picker: () async => '',
                      bytePicker: () async => usr(),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-choose-usr-file')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-commit-button')));
      await tester.pumpAndSettle();
      // Done closes the review screen before the terms are offered (#1819).
      await tester.tap(find.byKey(const ValueKey('import-done-button')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      // The shorthand step comes first.
      expect(find.byKey(const ValueKey('seed-skip')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('seed-skip')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      return repos;
    }

    testWidgets('the file\'s terms are offered, and the chosen added with '
        'their source; Undo takes them back', (tester) async {
      final repos = await runImport(tester, glossary: true);
      expect(find.byType(ImportCcTermsScreen), findsOneWidget);
      // Contra Corners has no definition, and is a shipped figure's name.
      await tester.tap(find.byKey(const ValueKey('cc-term-import-confirm')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      final terms = await tester.runAsync(() => repos.userGlossary.listAll());
      expect(terms!.map((t) => t.name), ['Dixie Twirl']);
      expect(
        glossaryTermSource(terms.single.payload),
        'Give and Take - Larry Jennings',
      );
      expect(
        find.byKey(const ValueKey('cc-term-import-complete')),
        findsOneWidget,
      );
      await tester.tap(find.text('Undo'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(() => repos.userGlossary.listAll()),
        isEmpty,
      );
    });

    testWidgets('with the Glossary hidden, no terms are offered', (
      tester,
    ) async {
      final repos = await runImport(tester, glossary: false);
      expect(find.byType(ImportCcTermsScreen), findsNothing);
      expect(
        await tester.runAsync(() => repos.userGlossary.listAll()),
        isEmpty,
      );
    });
  });
}
