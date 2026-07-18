import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/callersbox_online.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/plaintext_program_import_screen.dart';

import '../support/test_repositories.dart';

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

String _moneyMuskJson() =>
    '{"ID":"10600","Name":"Money Musk","Authors":["Traditional"],'
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
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push<String>(
                MaterialPageRoute<String>(
                  builder: (_) =>
                      PlaintextProgramImportScreen(callersBoxOnline: online),
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
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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

    TextButton commitButton() => tester.widget<TextButton>(
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
      expect(find.text("Imported from Caller's Box"), findsOneWidget);
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
      expect(find.text("Imported from Caller's Box"), findsOneWidget);

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
      expect(find.text("Imported from Caller's Box"), findsNothing);
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
}
