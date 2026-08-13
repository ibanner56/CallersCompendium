import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/programs_list_screen.dart';
import 'package:compendium_app/src/widgets/program_list_tile.dart';
import 'package:compendium_app/src/widgets/weekday_header_strip.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

final _now = DateTime.utc(2026, 1, 1);

Program _program({
  required String id,
  required String title,
  DateTime? eventDate,
  String? venue,
  ProgramStatus status = ProgramStatus.draft,
  DateTime? updatedAt,
  List<ProgramSlot> slots = const [],
  String? venueId,
}) => Program(
  id: id,
  title: title,
  eventDate: eventDate,
  venue: venue,
  venueId: venueId,
  status: status,
  slots: slots,
  createdAt: _now,
  updatedAt: updatedAt ?? _now,
);

Future<void> _pump(WidgetTester tester, CompendiumRepositories repos) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,

      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      home: const ProgramsListScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('empty state teaches and offers New program', (tester) async {
    final repos = openTestRepositories();
    await _pump(tester, repos);

    expect(find.byKey(const ValueKey('empty-state')), findsOneWidget);
    expect(find.text('No programs yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('empty-new-program')), findsOneWidget);
  });

  testWidgets('lists non-deleted programs with status chip icon+text', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      _program(id: 'p1', title: 'Friday Night', status: ProgramStatus.draft),
    );
    await repos.programs.create(
      _program(id: 'p2', title: 'Gone', status: ProgramStatus.performed),
    );
    await repos.programs.softDelete('p2', at: _now);

    await _pump(tester, repos);

    expect(find.text('Friday Night'), findsOneWidget);
    expect(find.text('Gone'), findsNothing);
    // Status chip pairs an icon with text.
    expect(find.text('Draft'), findsOneWidget);
    expect(find.byType(ProgramListTile), findsOneWidget);
    expect(find.text('1 program'), findsOneWidget);
  });

  testWidgets(
    'shows the "this week" header strip (ROADMAP G.8 first-day-of-week '
    'consumer)',
    (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program(id: 'p1', title: 'Friday Night'));

      await _pump(tester, repos);

      expect(
        find.byKey(const ValueKey('weekday-header-strip')),
        findsOneWidget,
      );
      expect(find.byType(WeekdayHeaderStrip), findsOneWidget);
    },
  );

  testWidgets('sorts by title, recently updated, and event date', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      _program(
        id: 'p1',
        title: 'Zeta',
        eventDate: DateTime.utc(2026, 5, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await repos.programs.create(
      _program(
        id: 'p2',
        title: 'Alpha',
        eventDate: DateTime.utc(2026, 3, 1),
        updatedAt: DateTime.utc(2026, 2, 1),
      ),
    );
    await _pump(tester, repos);

    List<String> titlesInOrder() => tester
        .widgetList<ProgramListTile>(find.byType(ProgramListTile))
        .map((t) => t.program.title)
        .toList();

    // Default: title A→Z.
    expect(titlesInOrder(), ['Alpha', 'Zeta']);

    // Recently updated: p2 (Feb) before p1 (Jan).
    await tester.tap(find.byKey(const ValueKey('programs-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recently updated').last);
    await tester.pumpAndSettle();
    expect(titlesInOrder(), ['Alpha', 'Zeta']);

    // Event date: p2 (Mar) before p1 (May).
    await tester.tap(find.byKey(const ValueKey('programs-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Event date').last);
    await tester.pumpAndSettle();
    expect(titlesInOrder(), ['Alpha', 'Zeta']);
  });

  testWidgets(
    'swiping reveals a Delete button; tapping it soft-deletes with undo',
    (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program(id: 'p1', title: 'Swipe Me'));
      await _pump(tester, repos);

      // Swipe left to reveal the Delete action; the swipe alone must NOT delete.
      await tester.drag(
        find.byKey(const ValueKey('slidable-p1')),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('Swipe Me'), findsOneWidget);
      expect((await repos.programs.listAll()), hasLength(1));

      // Tapping the revealed Delete button confirms the delete.
      await tester.tap(find.byKey(const ValueKey('slide-delete-p1')));
      await tester.pumpAndSettle();

      expect(find.text('Swipe Me'), findsNothing);
      expect(
        find.byKey(const ValueKey('program-deleted-snackbar')),
        findsOneWidget,
      );
      expect((await repos.programs.listAll()), isEmpty);

      // Undo restores it.
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect((await repos.programs.listAll()), hasLength(1));
    },
  );

  testWidgets(
    'row overflow menu Delete soft-deletes with the same undo snackbar as swipe',
    (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program(id: 'p1', title: 'Menu Delete'));
      await repos.programs.create(_program(id: 'p2', title: 'Stay Here'));
      await _pump(tester, repos);

      // Open the row's ⋮ menu (no swipe) and invoke Delete.
      await tester.tap(find.byKey(const ValueKey('program-actions-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('program-action-delete')));
      await tester.pumpAndSettle();

      expect(find.text('Menu Delete'), findsNothing);
      expect(find.text('Stay Here'), findsOneWidget);
      // Identical undo snackbar as the swipe flow.
      expect(
        find.byKey(const ValueKey('program-deleted-snackbar')),
        findsOneWidget,
      );
      expect(find.text('Undo'), findsOneWidget);

      final deleted = await repos.programs.getById('p1', includeDeleted: true);
      expect(deleted, isNotNull);
      expect(deleted!.deletedAt, isNotNull);

      // Undo restores it.
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(await repos.programs.getById('p1'), isNotNull);
    },
  );

  testWidgets('row overflow menu Duplicate creates a "(copy)" program', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(id: 'p1', title: 'Copy Me'));
    await _pump(tester, repos);

    await tester.tap(find.byKey(const ValueKey('program-actions-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('program-action-duplicate')));
    await tester.pumpAndSettle();

    expect(find.text('Copy Me (copy)'), findsOneWidget);
    final all = await repos.programs.listAll();
    expect(all.where((p) => p.title == 'Copy Me (copy)'), isNotEmpty);
  });

  group('issue #768: the list is driven by its data, not by refresh requests', () {
    testWidgets(
      'a program written from OUTSIDE this screen appears without any '
      'refresh request',
      (tester) async {
        // The defect this conversion cures. Program data is written from places
        // that are not the Programs tab — the "add to program" sheet on a
        // Collection row, an import, a share-target bundle — and this list is
        // kept alive in an `IndexedStack`. Every one of those sites had to
        // remember to broadcast, and the ones that forgot left the list showing
        // pre-write data until the app restarted.
        //
        // No scope is mounted here, deliberately: that is what makes this a
        // test of the stream rather than of a broadcast. Before the conversion
        // this screen had no way to learn about the write at all.
        final repos = openTestRepositories();
        await repos.programs.create(_program(id: 'p1', title: 'Existing'));
        await _pump(tester, repos);
        expect(find.text('Existing'), findsOneWidget);

        await repos.programs.create(
          _program(id: 'p2', title: 'Written Elsewhere'),
        );
        await tester.pumpAndSettle();

        expect(find.text('Written Elsewhere'), findsOneWidget);
      },
    );

    testWidgets('a slot added elsewhere updates the row without a rename', (
      tester,
    ) async {
      // Narrower, and the reason the repository declares `program_slots`
      // explicitly: this write changes what the row renders while leaving the
      // `programs` row it belongs to untouched. A read set inferred from the
      // outer query alone would leave the count stale here and nowhere else,
      // which is the kind of partial staleness nobody reports as a bug.
      final repos = openTestRepositories();
      for (final id in ['d1', 'd2']) {
        await repos.dances.create(
          Dance(id: id, title: id, createdAt: _now, updatedAt: _now),
        );
      }
      await repos.programs.create(
        _program(
          id: 'p1',
          title: 'Friday',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      await _pump(tester, repos);

      final before = tester.widget<ProgramListTile>(
        find.byType(ProgramListTile),
      );
      expect(before.program.slots, hasLength(1));

      await repos.programs.update(
        _program(
          id: 'p1',
          title: 'Friday',
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
            ProgramSlot(id: 's2', position: 1, danceId: 'd2'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final after = tester.widget<ProgramListTile>(
        find.byType(ProgramListTile),
      );
      expect(
        after.program.slots,
        hasLength(2),
        reason: 'the added slot must reach the rendered row',
      );
    });

    // NOT TESTED HERE: "an older emit cannot overwrite a newer one".
    //
    // There is nothing left to test. The screen resolves venue labels with
    // `asyncMap`, which holds the subscription until each mapper completes, so
    // two emits cannot be in flight at once. The ordering is a property of the
    // stream rather than a guard in this file.
    //
    // It was a guard first — a sequence number compared after the await. The
    // mutation is what condemned it: deleting the comparison broke nothing in
    // the whole suite. Writing the missing test then proved impossible for a
    // reason worth recording, because it will recur: inverting the order needs
    // the venue read held open, and holding a read open on a
    // single-connection database blocks the very write that would produce the
    // second emit. The test deadlocked rather than failed.
    //
    // So the guard was replaced by a structure that cannot express the defect,
    // rather than kept with a comment apologising for its lack of coverage.

    testWidgets('a delete leaves exactly one row rendered, not zero or two', (
      tester,
    ) async {
      // The optimistic row removal came out with the refresh plumbing: the
      // stream re-emits without the row, so removing it locally as well would
      // render the change twice. Asserting the surviving row rather than the
      // deleted one is what makes this fail in BOTH directions — a list that
      // never updated would show two, and a double-application that dropped the
      // wrong row would show none.
      final repos = openTestRepositories();
      await repos.programs.create(_program(id: 'p1', title: 'Keep Me'));
      await repos.programs.create(_program(id: 'p2', title: 'Delete Me'));
      await _pump(tester, repos);
      expect(find.byType(ProgramListTile), findsNWidgets(2));

      await repos.programs.softDelete('p2', at: DateTime.now().toUtc());
      await tester.pumpAndSettle();

      expect(find.byType(ProgramListTile), findsOneWidget);
      expect(find.text('Keep Me'), findsOneWidget);
    });
  });
}
