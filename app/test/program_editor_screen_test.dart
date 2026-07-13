import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';

import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  String? programId,
  void Function(String)? onSaved,
  VoidCallback? onDeleted,
  void Function(String)? onNavigateTo,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      home: ProgramEditorScreen(
        programId: programId,
        onSaved: onSaved,
        onDeleted: onDeleted,
        onNavigateTo: onNavigateTo,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Program _program({
  required String id,
  String title = 'Existing',
  DateTime? eventDate,
  String? venue,
  String notes = '',
  ProgramStatus status = ProgramStatus.draft,
}) => Program(
  id: id,
  title: title,
  eventDate: eventDate,
  venue: venue,
  notes: notes,
  status: status,
  createdAt: _now,
  updatedAt: _now,
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('create requires a title', (tester) async {
    final repos = openTestRepositories();
    String? savedId;
    await _pump(tester, repos, onSaved: (id) => savedId = id);

    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    expect(find.text('A title is required.'), findsOneWidget);
    expect(savedId, isNull);
    expect(await repos.programs.listAll(), isEmpty);
  });

  testWidgets('create persists a new program', (tester) async {
    final repos = openTestRepositories();
    String? savedId;
    await _pump(tester, repos, onSaved: (id) => savedId = id);

    await tester.enterText(
      find.byKey(const ValueKey('program-title')),
      'Barn Dance',
    );
    await tester.enterText(
      find.byKey(const ValueKey('program-venue')),
      'The Grange',
    );
    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    expect(savedId, isNotNull);
    final saved = await repos.programs.getById(savedId!);
    expect(saved!.title, 'Barn Dance');
    expect(saved.venue, 'The Grange');
    expect(saved.status, ProgramStatus.draft);
  });

  testWidgets('edit updates existing metadata', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      _program(id: 'p1', title: 'Before', venue: 'Old Hall'),
    );
    await _pump(tester, repos, programId: 'p1', onSaved: (_) {});

    await tester.enterText(
      find.byKey(const ValueKey('program-title')),
      'After',
    );
    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    final updated = await repos.programs.getById('p1');
    expect(updated!.title, 'After');
    expect(updated.venue, 'Old Hall');
  });

  testWidgets('clearing venue and event date persists as null', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      _program(
        id: 'p1',
        title: 'Has Meta',
        eventDate: DateTime.utc(2026, 4, 4),
        venue: 'Somewhere',
      ),
    );
    await _pump(tester, repos, programId: 'p1', onSaved: (_) {});

    // Clear event date via the clear button.
    await tester.tap(find.byKey(const ValueKey('clear-event-date')));
    await tester.pumpAndSettle();
    // Clear venue text.
    await tester.enterText(find.byKey(const ValueKey('program-venue')), '');
    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    final updated = await repos.programs.getById('p1');
    expect(updated!.eventDate, isNull);
    expect(updated.venue, isNull);
  });

  testWidgets('duplicate creates a copy', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(id: 'p1', title: 'Original'));
    String? navigatedTo;
    await _pump(
      tester,
      repos,
      programId: 'p1',
      onNavigateTo: (id) => navigatedTo = id,
    );

    await tester.tap(find.byKey(const ValueKey('duplicate-program')));
    await tester.pumpAndSettle();

    expect(navigatedTo, isNotNull);
    expect(navigatedTo, isNot('p1'));
    final all = await repos.programs.listAll();
    expect(all, hasLength(2));
    expect(all.map((p) => p.title), contains('Original (copy)'));
  });

  testWidgets('delete soft-deletes and calls onDeleted', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(id: 'p1', title: 'Doomed'));
    var deleted = false;
    await _pump(
      tester,
      repos,
      programId: 'p1',
      onDeleted: () => deleted = true,
    );

    await tester.tap(find.byKey(const ValueKey('delete-program')));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(await repos.programs.listAll(), isEmpty);
    expect(await repos.programs.getById('p1', includeDeleted: true), isNotNull);
  });
}
