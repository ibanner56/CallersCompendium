import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/plaintext_program_import_screen.dart';

import '../support/test_repositories.dart';

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

Future<void> _pump(WidgetTester tester, CompendiumRepositories repos) async {
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
                  builder: (_) => const PlaintextProgramImportScreen(),
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
}
