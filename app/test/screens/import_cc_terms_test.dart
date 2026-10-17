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

  /// Opens the screen on [terms]; the getter returned reads what it popped.
  Future<List<CcTermDraft>? Function()> openScreen(
    WidgetTester tester,
    List<CcTerm> terms, {
    bool Function(String name)? nameTaken,
  }) async {
    List<CcTermDraft>? popped;
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
                    // As the import stores text, for Larks and Robins.
                    stored: (text) => normalizeShareableText(
                      canonicalizeGlossaryText(
                        text.trim(),
                        Dialect.larksRobins,
                      ),
                    ),
                  ),
                ),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('launch')));
    await tester.pumpAndSettle();
    return () => popped;
  }

  Future<void> editAndSave(
    WidgetTester tester,
    int index, {
    String? name,
    String? definition,
    String? description,
  }) async {
    await tester.tap(find.byKey(ValueKey('cc-term-import-edit-$index')));
    await tester.pumpAndSettle();
    if (name != null) {
      await tester.enterText(
        find.byKey(const ValueKey('cc-term-edit-name')),
        name,
      );
    }
    if (definition != null) {
      await tester.enterText(
        find.byKey(const ValueKey('cc-term-edit-definition')),
        definition,
      );
    }
    if (description != null) {
      await tester.enterText(
        find.byKey(const ValueKey('cc-term-edit-description')),
        description,
      );
    }
    await tester.tap(find.byKey(const ValueKey('cc-term-edit-save')));
    await tester.pumpAndSettle();
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

    // A definition alone is enough: the blank description becomes it.
    await editAndSave(tester, 0, definition: 'A spinning figure.');
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

  testWidgets('names are compared as stored: two that differ only in a '
      'role word are the same name', (tester) async {
    await openScreen(tester, [
      CcTerm(name: 'Ladies wait', definition: 'Stand.'),
      CcTerm(name: 'Robins wait', definition: 'Stand.'),
    ]);
    expect(ticked(tester, 0), isTrue);
    expect(ticked(tester, 1), isFalse);
    expect(
      find.byKey(const ValueKey('cc-term-import-taken-1')),
      findsOneWidget,
    );
  });

  testWidgets('an earlier term that can\'t be added takes no name', (
    tester,
  ) async {
    await openScreen(tester, [
      CcTerm(name: 'Spin'),
      CcTerm(name: 'Spin', definition: 'Turn.'),
    ]);
    expect(ticked(tester, 0), isFalse);
    expect(ticked(tester, 1), isTrue);
  });

  testWidgets('a term with a blank name or description, or too long, says so '
      'and can\'t be ticked', (tester) async {
    await openScreen(tester, [
      twirl,
      CcTerm(name: 'x' * (maxUserGlossaryNameLength + 1), definition: 'Long.'),
    ]);
    expect(enabled(tester, 1), isFalse);
    expect(
      find.byKey(const ValueKey('cc-term-import-too-long-1')),
      findsOneWidget,
    );
    await editAndSave(tester, 0, description: 'x', name: '');
    expect(ticked(tester, 0), isFalse);
    expect(
      find.byKey(const ValueKey('cc-term-import-incomplete-0')),
      findsOneWidget,
    );
  });

  testWidgets('Confirm returns only what is ticked, as edited; an edit keeps '
      'a term the user unticked unticked', (tester) async {
    final result = await openScreen(tester, [
      twirl,
      CcTerm(name: 'Spin', definition: 'Turn.'),
    ]);
    await tester.tap(find.byKey(const ValueKey('cc-term-import-1')));
    await tester.pumpAndSettle();
    await editAndSave(tester, 1, description: 'Turn around.');
    expect(ticked(tester, 1), isFalse);
    await editAndSave(tester, 0, description: 'Under the arch.');
    await tester.tap(find.byKey(const ValueKey('cc-term-import-confirm')));
    await tester.pumpAndSettle();
    final popped = result()!;
    expect(popped.map((d) => d.name), ['Dixie Twirl']);
    expect(popped.single.description, 'Under the arch.');
    expect(popped.single.source, 'Give and Take - Larry Jennings');
  });

  testWidgets('Skip returns nothing', (tester) async {
    final result = await openScreen(tester, [twirl]);
    await tester.tap(find.byKey(const ValueKey('cc-term-import-skip')));
    await tester.pumpAndSettle();
    expect(result(), isEmpty);
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
    Uint8List usr({
      List<MapEntry<int, Map<int, String>>> moreTerms = const [],
    }) => buildFmp12Fixture([
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
          // Defined, but a shipped figure's name.
          MapEntry(22, {1: 'Swing', 2: 'My own swing.', 4: '1'}),
          ...moreTerms,
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
      List<UserGlossaryEntry> existing = const [],
      List<MapEntry<int, Map<int, String>>> moreTerms = const [],
    }) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repos = openTestRepositories();
      await tester.runAsync(() async {
        for (final entry in existing) {
          await repos.userGlossary.upsert(entry);
        }
      });
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
                          bytePicker: () async => usr(moreTerms: moreTerms),
                        ),
                      ],
                      picker: () async => '',
                      bytePicker: () async => usr(moreTerms: moreTerms),
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
      // Swing is a shipped figure's name, as the real check finds it.
      expect(
        find.byKey(const ValueKey('cc-term-import-taken-2')),
        findsOneWidget,
      );
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

    testWidgets('a term already in the Glossary from an earlier import is '
        'not offered again', (tester) async {
      await runImport(
        tester,
        glossary: true,
        existing: [
          UserGlossaryEntry(
            id: 'earlier',
            kindName: UserGlossaryEntryKind.term.name,
            name: 'Dixie Twirl',
            definition: 'The left pair go under an arch.',
            description: 'The left pair go under an arch.',
            payload: glossaryTermPayload(
              'contra',
              source: 'Give and Take - Larry Jennings',
            ),
            createdAt: DateTime.utc(2026, 10, 1),
          ),
        ],
      );
      expect(find.byType(ImportCcTermsScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ImportCcTermsScreen),
          matching: find.text('Dixie Twirl'),
        ),
        findsNothing,
      );
      expect(find.text('Contra Corners'), findsOneWidget);
    });

    testWidgets('a term of the user\'s own with a file term\'s name, and no '
        'source like it, is not taken for that term: the row is offered, as '
        'taken', (tester) async {
      await runImport(
        tester,
        glossary: true,
        existing: [
          UserGlossaryEntry(
            id: 'mine',
            kindName: UserGlossaryEntryKind.term.name,
            name: 'Swing',
            definition: 'Partners turn as a couple.',
            description: 'Partners turn as a couple.',
            payload: glossaryTermPayload('contra'),
            createdAt: DateTime.utc(2026, 10, 1),
          ),
        ],
      );
      expect(find.byType(ImportCcTermsScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ImportCcTermsScreen),
          matching: find.text('Swing'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cc-term-import-taken-2')),
        findsOneWidget,
      );
    });

    testWidgets('a term imported before is known again when the file writes '
        'its name and text decomposed, as stored they are composed (NFC)', (
      tester,
    ) async {
      await runImport(
        tester,
        glossary: true,
        moreTerms: [
          // The file writes its accents decomposed, e + U+0301, which the
          // fixture spells as SCSU does: SQU (0x0E) quoting the code point.
          const MapEntry(23, {
            1: 'Cafe\u000e\u0003\u0001 Turn',
            2: 'Cafe\u000e\u0003\u0001 style.',
            3: 'Le Cafe\u000e\u0003\u0001 - Anon',
            4: '1',
          }),
        ],
        existing: [
          UserGlossaryEntry(
            id: 'earlier',
            kindName: UserGlossaryEntryKind.term.name,
            name: 'Caf\u00e9 Turn',
            definition: 'Caf\u00e9 style.',
            description: 'Caf\u00e9 style.',
            payload: glossaryTermPayload(
              'contra',
              source: 'Le Caf\u00e9 - Anon',
            ),
            createdAt: DateTime.utc(2026, 10, 1),
          ),
        ],
      );
      expect(find.byType(ImportCcTermsScreen), findsOneWidget);
      expect(find.text('Contra Corners'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ImportCcTermsScreen),
          // In either form: the row would show the name as the file has it.
          matching: find.byWidgetPredicate(
            (w) =>
                w is Text &&
                normalizeShareableText(w.data ?? '') == 'Caf\u00e9 Turn',
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('two terms in the file whose names differ only in how an '
        'accent is written are the same name', (tester) async {
      await runImport(
        tester,
        glossary: true,
        moreTerms: [
          const MapEntry(23, {1: 'Caf\u00e9 Turn', 2: 'Turn.', 4: '1'}),
          // e + U+0301, as SCSU quotes it (SQU, 0x0E).
          const MapEntry(24, {
            1: 'Cafe\u000e\u0003\u0001 Turn',
            2: 'Turn.',
            4: '1',
          }),
        ],
      );
      expect(
        find.byKey(const ValueKey('cc-term-import-taken-3')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('cc-term-import-taken-4')),
        findsOneWidget,
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
