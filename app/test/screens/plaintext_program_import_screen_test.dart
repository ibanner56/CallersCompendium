import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/callersbox_online.dart';
import 'package:compendium_app/src/data/contradb_online.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/plaintext_program_import_screen.dart';
import 'package:compendium_app/src/widgets/app_bar_text_action.dart';

import '../support/test_repositories.dart';
import '../support/l10n_harness.dart';

/// A trimmed Caller's Box results page with a single "Money Musk" row, modelled
/// on the live HTML the parser expects.
const String _moneyMuskResultsHtml = '''
<html><head><meta charset='windows-1252'></head><body>
<p>Of 16874 dances in the database, your query matches 1.</p>
<table>
<tr>
  <td>&#x24bb;</td><td></td><td></td>
  <td><a href='dance.php?id=10600' target='_blank'>Money Musk</a></td>
  <td>Traditional</td>
  <td>Triple Minor - Proper</td>
</tr>
</table>
</body></html>
''';

/// A results page that matches nothing.
const String _emptyResultsHtml = '''
<html><head><meta charset='windows-1252'></head><body>
<p>Of 16874 dances in the database, your query matches 0.</p>
<table></table>
</body></html>
''';

/// A results page with two dances both titled exactly "Money Musk".
const String _twoMoneyMusksResultsHtml = '''
<html><head><meta charset='windows-1252'></head><body>
<p>Of 16874 dances in the database, your query matches 2.</p>
<table>
<tr>
  <td>&#x24bb;</td><td></td><td></td>
  <td><a href='dance.php?id=10600' target='_blank'>Money Musk</a></td>
  <td>Traditional</td>
  <td>Triple Minor - Proper</td>
</tr>
<tr>
  <td>&#x24bb;</td><td></td><td></td>
  <td><a href='dance.php?id=10601' target='_blank'>Money Musk</a></td>
  <td>Someone Else</td>
  <td>Duple Minor - Improper</td>
</tr>
</table>
</body></html>
''';

String _moneyMuskJson({String id = '10600'}) =>
    '{"ID":"$id","Name":"Money Musk","Authors":["Traditional"],'
    '"InterpretedBy":[],"Permission":"full",'
    '"FormationBase":"Triple Minor - Proper","FormationDetail":"",'
    '"Progression":"Single","PhraseStructure":"","CallingNotes":[],'
    '"OtherNames":[],"Music":[],"Tunes":[],"Appearances":[],'
    '"phrases":[{"name":"A1","figures":["Actives balance and swing"]}]}';

Dance _dance({required String id, required String title}) => Dance(
  id: id,
  title: title,
  authorIds: const [],
  tagIds: const [],
  form: DanceForm.contra,
  formation: const Formation(FormationShape.dupleImproper),
  status: DanceStatus.active,
  figures: const [],
  customFields: const [],
  hook: '',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  CallersBoxOnline? online,
  ContraDbOnline? contraDb,
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push<String>(
                MaterialPageRoute<String>(
                  builder: (_) => PlaintextProgramImportScreen(
                    callersBoxOnline: online,
                    contraDbOnline: contraDb,
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
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('preview reflects matched, note, and ambiguous resolutions', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Rockin\' Robin'));
    await repos.dances.create(_dance(id: 'd2', title: 'Broken Sixpence'));
    await repos.dances.create(_dance(id: 'd3', title: 'broken sixpence'));

    await _pump(tester, repos);

    await tester.enterText(
      find.byKey(const ValueKey('plaintext-import-paste')),
      'rockin\' robin\nSome Announcement\nBroken Sixpence',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plaintext-import-preview')), findsOne);
    expect(find.text('Linked to dance'), findsOneWidget);
    expect(find.text('No match — added as note'), findsOneWidget);
    expect(find.text('Multiple matches — added as note'), findsOneWidget);
    expect(find.text('3 slots'), findsOneWidget);
  });

  testWidgets(
    'commit creates a program with ordered slots and undo removes it',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Rockin\' Robin'));

      await _pump(tester, repos);

      await tester.enterText(
        find.byKey(const ValueKey('plaintext-import-title')),
        'Friday Night',
      );
      await tester.enterText(
        find.byKey(const ValueKey('plaintext-import-paste')),
        'Rockin\' Robin\nBreak\nUnknown Dance',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('plaintext-import-commit')));
      await tester.pumpAndSettle();

      final programs = await repos.programs.listAll();
      expect(programs, hasLength(1));
      final program = programs.single;
      expect(program.title, 'Friday Night');
      expect(program.slots.map((s) => s.position).toList(), [0, 1, 2]);
      expect(program.slots[0].danceId, 'd1');
      expect(program.slots[0].text, isNull);
      expect(program.slots[1].danceId, isNull);
      expect(program.slots[1].text, 'Break');
      expect(program.slots[2].text, 'Unknown Dance');

      expect(
        find.byKey(const ValueKey('plaintext-import-committed-snackbar')),
        findsOneWidget,
      );

      // Undo hard-deletes the just-created program.
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(await repos.programs.listAll(), isEmpty);
    },
  );

  testWidgets('Import action is disabled until title and titles are present', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Rockin\' Robin'));

    await _pump(tester, repos);

    AppBarTextAction commitButton() => tester.widget<AppBarTextAction>(
      find.byKey(const ValueKey('plaintext-import-commit')),
    );
    expect(commitButton().onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('plaintext-import-title')),
      'Friday Night',
    );
    await tester.pumpAndSettle();
    // Still disabled — no titles pasted yet.
    expect(commitButton().onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('plaintext-import-paste')),
      'Rockin\' Robin',
    );
    await tester.pumpAndSettle();
    expect(commitButton().onPressed, isNotNull);
  });

  testWidgets(
    'resolve online imports a confident TCB match and links it to the slot',
    (tester) async {
      final repos = openTestRepositories();
      final online = CallersBoxOnline(
        searchFetcher: (_) async => _moneyMuskResultsHtml,
        jsonFetcher: (_) async => _moneyMuskJson(),
      );

      await _pump(tester, repos, online: online);

      await tester.enterText(
        find.byKey(const ValueKey('plaintext-import-title')),
        'Friday Night',
      );
      await tester.enterText(
        find.byKey(const ValueKey('plaintext-import-paste')),
        'Money Musk',
      );
      await tester.pumpAndSettle();

      // Starts as an unmatched note; the resolve action is offered.
      expect(find.text('No match — added as note'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('plaintext-import-resolve-online')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('plaintext-import-resolve-online')),
      );
      await tester.pumpAndSettle();

      // The line is now linked via Caller's Box, and the dance was imported.
      expect(find.text("Imported online"), findsOneWidget);
      final saved = await repos.dances.listAll();
      expect(saved.map((d) => d.title), contains('Money Musk'));

      // Committing writes a dance-linked slot, not a note.
      await tester.tap(find.byKey(const ValueKey('plaintext-import-commit')));
      await tester.pumpAndSettle();

      final program = (await repos.programs.listAll()).single;
      expect(program.slots.single.danceId, saved.single.id);
      expect(program.slots.single.text, isNull);
    },
  );

  testWidgets(
    'issue #340: resolving online imports a dance and its author into the '
    'collection database',
    (tester) async {
      final repos = openTestRepositories();
      final online = CallersBoxOnline(
        searchFetcher: (_) async => _moneyMuskResultsHtml,
        jsonFetcher: (_) async => _moneyMuskJson(),
      );
      await _pump(tester, repos, online: online);

      await tester.enterText(
        find.byKey(const ValueKey('plaintext-import-paste')),
        'Money Musk',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('plaintext-import-resolve-online')),
      );
      await tester.pumpAndSettle();

      // The dance was imported into the collection.
      expect(
        (await repos.dances.listAll()).map((d) => d.title),
        contains('Money Musk'),
      );
      // Its author ("Traditional", per the fixture JSON's "Authors" field) was
      // imported alongside it, not left as a dangling reference.
      expect(
        (await repos.choreographers.listAll()).map((c) => c.name),
        contains('Traditional'),
      );
    },
  );

  testWidgets(
    'after online import, editing the paste recognizes the dance locally',
    (tester) async {
      final repos = openTestRepositories();
      var jsonFetches = 0;
      final online = CallersBoxOnline(
        searchFetcher: (_) async => _moneyMuskResultsHtml,
        jsonFetcher: (_) async {
          jsonFetches++;
          return _moneyMuskJson();
        },
      );

      await _pump(tester, repos, online: online);

      await tester.enterText(
        find.byKey(const ValueKey('plaintext-import-title')),
        'Friday Night',
      );
      await tester.enterText(
        find.byKey(const ValueKey('plaintext-import-paste')),
        'Money Musk',
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('plaintext-import-resolve-online')),
      );
      await tester.pumpAndSettle();
      expect(jsonFetches, 1);
      expect(find.text("Imported online"), findsOneWidget);

      // Editing the paste clears the override and re-parses against the now
      // refreshed collection: the imported dance is a plain local match, and no
      // second online import is attempted. (A trailing space changes the text
      // so the override is invalidated, but trims back to the same title.)
      await tester.enterText(
        find.byKey(const ValueKey('plaintext-import-paste')),
        'Money Musk ',
      );
      await tester.pumpAndSettle();

      expect(find.text('Linked to dance'), findsOneWidget);
      expect(find.text("Imported online"), findsNothing);
      expect(
        find.byKey(const ValueKey('plaintext-import-resolve-online')),
        findsNothing,
      );
      expect(jsonFetches, 1);
      expect((await repos.dances.listAll()), hasLength(1));
    },
  );

  testWidgets('resolve online leaves a no-match title as a note', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final online = CallersBoxOnline(
      searchFetcher: (_) async => _emptyResultsHtml,
      jsonFetcher: (_) async => throw StateError('should not fetch json'),
    );

    await _pump(tester, repos, online: online);

    await tester.enterText(
      find.byKey(const ValueKey('plaintext-import-title')),
      'Friday Night',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plaintext-import-paste')),
      'Totally Unknown Dance',
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('plaintext-import-resolve-online')),
    );
    await tester.pumpAndSettle();

    // No dance imported; the line stays a note.
    expect(await repos.dances.listAll(), isEmpty);
    expect(find.text('No match — added as note'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plaintext-import-commit')));
    await tester.pumpAndSettle();

    final program = (await repos.programs.listAll()).single;
    expect(program.slots.single.danceId, isNull);
    expect(program.slots.single.text, 'Totally Unknown Dance');
  });

  // ── 2026-10 audit, batch F12 (INTAKE-4, FAIL-2) ──────────────────────────

  /// A ContraDB fallback that never finds anything, so these tests exercise
  /// The Caller's Box alone and never reach the network.
  ContraDbOnline emptyContraDb() => ContraDbOnline(
    searchFetcher: (_) async => '{"dances":[]}',
    htmlFetcher: (_) async => throw StateError('should not fetch a dance'),
  );

  Future<void> resolveMoneyMusk(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('plaintext-import-title')),
      'Friday Night',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plaintext-import-paste')),
      'Money Musk',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('plaintext-import-resolve-online')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Imported online'), findsOneWidget);
  }

  testWidgets('offline, resolve says it stopped, not that nothing matched, '
      'and asks each source once at most', (tester) async {
    final repos = openTestRepositories();
    var searches = 0;
    var contraDbSearches = 0;
    final online = CallersBoxOnline(
      searchFetcher: (_) async {
        searches++;
        throw const UrlFetchException(
          UrlFetchFailureReason.callersBoxUnreachable,
        );
      },
      jsonFetcher: (_) async => throw StateError('should not fetch json'),
    );
    final contraDb = ContraDbOnline(
      searchFetcher: (_) async {
        contraDbSearches++;
        return '{"dances":[]}';
      },
    );
    await _pump(tester, repos, online: online, contraDb: contraDb);

    await tester.enterText(
      find.byKey(const ValueKey('plaintext-import-paste')),
      'First Unknown\nSecond Unknown\nThird Unknown',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('plaintext-import-resolve-online')),
    );
    await tester.pumpAndSettle();

    // Stopped at the first connection failure: one search, no fallback.
    expect(searches, 1);
    expect(contraDbSearches, 0);
    expect(find.textContaining('No confident online matches'), findsNothing);
    expect(
      find.text(
        'Stopped looking up titles after a connection failure. Try the rest '
        "again once you're online.",
      ),
      findsOneWidget,
    );
    // Nothing was looked up, so all three stay notes and can be retried.
    expect(find.text('No match — added as note'), findsNWidgets(3));
    expect(
      find.byKey(const ValueKey('plaintext-import-resolve-online')),
      findsOneWidget,
    );
  });

  testWidgets('resolve shows progress and Cancel stops before the next title', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final searched = <String>[];
    final gate = Completer<String>();
    final online = CallersBoxOnline(
      searchFetcher: (url) {
        searched.add(url);
        return gate.future;
      },
      jsonFetcher: (_) async => _moneyMuskJson(),
    );
    await _pump(tester, repos, online: online, contraDb: emptyContraDb());

    await tester.enterText(
      find.byKey(const ValueKey('plaintext-import-paste')),
      'Money Musk\nSecond Unknown',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('plaintext-import-resolve-online')),
    );
    await tester.pump();

    expect(find.text('Searching 0 of 2…'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('plaintext-import-resolve-cancel')),
    );
    await tester.pump();
    gate.complete(_moneyMuskResultsHtml);
    await tester.pumpAndSettle();

    // The title in flight finished; the second was never asked for.
    expect(searched, hasLength(1));
    expect(find.text('Imported online'), findsOneWidget);
    expect(
      find.text('Stopped looking up titles — 1 title linked online.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('plaintext-import-resolve-cancel')),
      findsNothing,
    );
  });

  testWidgets('Undo removes the dances the online pass imported, not just '
      'the program', (tester) async {
    final repos = openTestRepositories();
    final online = CallersBoxOnline(
      searchFetcher: (_) async => _moneyMuskResultsHtml,
      jsonFetcher: (_) async => _moneyMuskJson(),
    );
    await _pump(tester, repos, online: online, contraDb: emptyContraDb());
    await resolveMoneyMusk(tester);
    expect(await repos.dances.listAll(), hasLength(1));

    await tester.tap(find.byKey(const ValueKey('plaintext-import-commit')));
    await tester.pumpAndSettle();
    expect(await repos.programs.listAll(), hasLength(1));

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(await repos.programs.listAll(), isEmpty);
    expect(await repos.dances.listAll(), isEmpty);
    // Its author came in with it, and goes with it.
    expect(await repos.choreographers.listAll(), isEmpty);
  });

  testWidgets('an Undo whose rollback fails says so', (tester) async {
    final repos = openTestRepositories();
    final online = CallersBoxOnline(
      searchFetcher: (_) async => _moneyMuskResultsHtml,
      jsonFetcher: (_) async => _moneyMuskJson(),
    );
    await _pump(tester, repos, online: online, contraDb: emptyContraDb());
    await resolveMoneyMusk(tester);
    await tester.tap(find.byKey(const ValueKey('plaintext-import-commit')));
    await tester.pumpAndSettle();
    // Taking the imported dances back fails (a full disk, a locked database).
    for (final event in const ['UPDATE', 'DELETE']) {
      await repos.db.customStatement(
        'CREATE TRIGGER fail_dance_$event BEFORE $event ON dances '
        "BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END",
      );
    }

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(
      find.text('Couldn’t undo that. Please check the result and try again.'),
      findsOneWidget,
    );
    expect(await repos.dances.listAll(), hasLength(1));
  });

  testWidgets('Undo leaves a dance that was already in the collection', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Rockin\' Robin'));
    final online = CallersBoxOnline(
      searchFetcher: (_) async => _moneyMuskResultsHtml,
      jsonFetcher: (_) async => _moneyMuskJson(),
    );
    await _pump(tester, repos, online: online, contraDb: emptyContraDb());
    await tester.enterText(
      find.byKey(const ValueKey('plaintext-import-title')),
      'Friday Night',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plaintext-import-paste')),
      'Rockin\' Robin\nMoney Musk',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('plaintext-import-resolve-online')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plaintext-import-commit')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect((await repos.dances.listAll()).map((d) => d.id), ['d1']);
  });

  testWidgets('backing out without creating the program removes the dances '
      'the online pass imported', (tester) async {
    final repos = openTestRepositories();
    final online = CallersBoxOnline(
      searchFetcher: (_) async => _moneyMuskResultsHtml,
      jsonFetcher: (_) async => _moneyMuskJson(),
    );
    await _pump(tester, repos, online: online, contraDb: emptyContraDb());
    await resolveMoneyMusk(tester);
    expect(await repos.dances.listAll(), hasLength(1));

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
    expect(await repos.programs.listAll(), isEmpty);
    expect(await repos.dances.listAll(), isEmpty);
  });

  testWidgets('leaving mid-lookup stops it and keeps nothing it imported', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final searched = <String>[];
    final gate = Completer<String>();
    final online = CallersBoxOnline(
      searchFetcher: (url) {
        searched.add(url);
        return searched.length == 1 ? gate.future : Future.value('');
      },
      jsonFetcher: (_) async => _moneyMuskJson(),
    );
    await _pump(tester, repos, online: online, contraDb: emptyContraDb());
    await tester.enterText(
      find.byKey(const ValueKey('plaintext-import-paste')),
      'Money Musk\nSecond Unknown\nThird Unknown',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('plaintext-import-resolve-online')),
    );
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);

    // The lookup in flight completes after the screen is gone: its dance is
    // imported, then taken back out, and no further title is looked up.
    gate.complete(_moneyMuskResultsHtml);
    await tester.pumpAndSettle();

    expect(searched, hasLength(1));
    expect(await repos.dances.listAll(), isEmpty);
    expect(await repos.programs.listAll(), isEmpty);
  });

  testWidgets('Undo also removes a dance picked on the review screen for an '
      'ambiguous title', (tester) async {
    final repos = openTestRepositories();
    final online = CallersBoxOnline(
      searchFetcher: (_) async => _twoMoneyMusksResultsHtml,
      jsonFetcher: (url) async => _moneyMuskJson(
        id: RegExp(r'id=(\d+)').firstMatch(url)?.group(1) ?? '10600',
      ),
    );
    await _pump(tester, repos, online: online, contraDb: emptyContraDb());
    await tester.enterText(
      find.byKey(const ValueKey('plaintext-import-title')),
      'Friday Night',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plaintext-import-paste')),
      'Money Musk',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('plaintext-import-resolve-online')),
    );
    await tester.pumpAndSettle();

    // Two exact hits: the review screen asks which one was meant.
    await tester.tap(find.byKey(const ValueKey('import-row-0-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-done-button')));
    await tester.pumpAndSettle();
    expect(find.text('Imported online'), findsOneWidget);
    expect(await repos.dances.listAll(), hasLength(1));

    await tester.tap(find.byKey(const ValueKey('plaintext-import-commit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(await repos.programs.listAll(), isEmpty);
    expect(await repos.dances.listAll(), isEmpty);
  });

  testWidgets('offline while previewing an ambiguous title says so, rather '
      'than "no matches", and opens no review', (tester) async {
    final repos = openTestRepositories();
    final online = CallersBoxOnline(
      searchFetcher: (_) async => _twoMoneyMusksResultsHtml,
      jsonFetcher: (_) async => throw const UrlFetchException(
        UrlFetchFailureReason.callersBoxUnreachable,
      ),
    );
    await _pump(tester, repos, online: online, contraDb: emptyContraDb());
    await tester.enterText(
      find.byKey(const ValueKey('plaintext-import-paste')),
      'Money Musk',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('plaintext-import-resolve-online')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('import-review-list')), findsNothing);
    expect(find.textContaining('No confident online matches'), findsNothing);
    expect(
      find.text(
        'Stopped looking up titles after a connection failure. Try the rest '
        "again once you're online.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('Cancel while previewing an ambiguous title opens no review', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final gate = Completer<String>();
    var jsonFetches = 0;
    final online = CallersBoxOnline(
      searchFetcher: (_) async => _twoMoneyMusksResultsHtml,
      jsonFetcher: (_) {
        jsonFetches++;
        return gate.future;
      },
    );
    await _pump(tester, repos, online: online, contraDb: emptyContraDb());
    await tester.enterText(
      find.byKey(const ValueKey('plaintext-import-paste')),
      'Money Musk',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('plaintext-import-resolve-online')),
    );
    await tester.pump();
    await tester.pump();
    expect(jsonFetches, 1);

    await tester.tap(
      find.byKey(const ValueKey('plaintext-import-resolve-cancel')),
    );
    await tester.pump();
    gate.complete(_moneyMuskJson());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('import-review-list')), findsNothing);
    expect(find.text('Stopped looking up titles.'), findsOneWidget);
    expect(await repos.dances.listAll(), isEmpty);
  });
}
