import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_app/src/screens/dance_detail/calling_history_section.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// Tests for the app's first reactive read (issue #768).
///
/// The load-bearing one is "a program-side write with NO refresh scope mounted
/// updates the section": before this conversion the calling history was correct
/// only when a mutation site remembered to bump `ProgramsRefreshScope`, and
/// seven places did not. These tests mount the section with no scope at all, so
/// the only thing that can make them pass is the database telling the widget.
void main() {
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final now = DateTime.utc(2026, 1, 1);

  Dance dance(String id, String title) =>
      Dance(id: id, title: title, createdAt: now, updatedAt: now);

  Program program({
    required String id,
    required String title,
    List<ProgramSlot> slots = const [],
    String? venue,
    String? venueId,
    DateTime? updatedAt,
  }) => Program(
    id: id,
    title: title,
    venue: venue,
    venueId: venueId,
    slots: slots,
    createdAt: now,
    updatedAt: updatedAt ?? now,
  );

  Future<void> pumpSection(
    WidgetTester tester,
    CompendiumRepositories repos, {
    bool performedOnly = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        // Deliberately no CollectionRefreshScope / ProgramsRefreshScope: the
        // section must stay correct without any broadcast channel at all.
        home: Scaffold(
          body: SingleChildScrollView(
            child: CallingHistorySection(
              repositories: repos,
              danceId: 'd1',
              performedOnly: performedOnly,
              trackAllCallers: true,
              onOpenProgram: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder historyRows() => find.byWidgetPredicate(
    (w) =>
        w is CallingHistoryRow ||
        (w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('calling-history-') &&
            (w.key! as ValueKey<String>).value != 'calling-history-empty'),
  );

  testWidgets('renders the empty state for a dance never called', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(dance('d1', 'Petronella'));

    await pumpSection(tester, repos);

    expect(find.byKey(const ValueKey('calling-history-empty')), findsOne);
  });

  testWidgets('renders the programs that include the dance', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(dance('d1', 'Petronella'));
    await repos.programs.create(
      program(
        id: 'p1',
        title: 'Autumn Ball',
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      ),
    );

    await pumpSection(tester, repos);

    expect(find.byKey(const ValueKey('calling-history-s1')), findsOne);
    expect(find.text('Autumn Ball'), findsOne);
    expect(find.byKey(const ValueKey('calling-history-empty')), findsNothing);
  });

  testWidgets(
    'a program-side write with NO refresh scope mounted updates the section',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(dance('d1', 'Petronella'));

      await pumpSection(tester, repos);
      expect(find.byKey(const ValueKey('calling-history-empty')), findsOne);

      // The write the seven gaps in #768 were all shaped like: made somewhere
      // else entirely, with nothing telling this widget about it.
      await repos.programs.create(
        program(
          id: 'p1',
          title: 'Autumn Ball',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      await tester.pumpAndSettle();

      expect(historyRows(), findsOne);
      expect(find.text('Autumn Ball'), findsOne);
      expect(find.byKey(const ValueKey('calling-history-empty')), findsNothing);
    },
  );

  testWidgets('deleting the program removes its row from the section', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(dance('d1', 'Petronella'));
    await repos.programs.create(
      program(
        id: 'p1',
        title: 'Autumn Ball',
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      ),
    );
    await pumpSection(tester, repos);
    expect(historyRows(), findsOne);

    // A soft delete writes only the `programs` row — the case a `readsFrom`
    // set missing that table drops silently.
    await repos.programs.softDelete('p1', at: DateTime.utc(2026, 2));
    await tester.pumpAndSettle();

    expect(historyRows(), findsNothing);
    expect(find.byKey(const ValueKey('calling-history-empty')), findsOne);
  });

  testWidgets('renaming the program updates its row', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(dance('d1', 'Petronella'));
    await repos.programs.create(
      program(
        id: 'p1',
        title: 'Autumn Ball',
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      ),
    );
    await pumpSection(tester, repos);
    expect(find.text('Autumn Ball'), findsOne);

    await repos.programs.update(
      program(
        id: 'p1',
        title: 'Autumn Ball (rescheduled)',
        updatedAt: DateTime.utc(2026, 2),
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Autumn Ball (rescheduled)'), findsOne);
    expect(find.text('Autumn Ball'), findsNothing);
  });

  testWidgets('performedOnly restricts the section to performed slots', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(dance('d1', 'Petronella'));
    await repos.programs.create(
      program(
        id: 'p1',
        title: 'Autumn Ball',
        slots: [
          ProgramSlot(
            id: 's-performed',
            position: 0,
            danceId: 'd1',
            performedAt: DateTime.utc(2026, 10, 3, 20),
          ),
        ],
      ),
    );
    await repos.programs.create(
      program(
        id: 'p2',
        title: 'Spring Fling',
        slots: [ProgramSlot(id: 's-planned', position: 0, danceId: 'd1')],
      ),
    );

    await pumpSection(tester, repos, performedOnly: true);

    expect(find.byKey(const ValueKey('calling-history-s-performed')), findsOne);
    expect(
      find.byKey(const ValueKey('calling-history-s-planned')),
      findsNothing,
    );
  });

  testWidgets(
    'resolves venue labels per program (linked name, else free text)',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(dance('d1', 'Petronella'));
      final grange = Venue(
        id: 'grange-hall',
        name: 'Grange Hall',
        city: 'Nelson',
      );
      await repos.venues.upsert(grange);
      await repos.programs.create(
        program(
          id: 'p-linked',
          title: 'Autumn Ball',
          venueId: 'grange-hall',
          slots: [ProgramSlot(id: 's-linked', position: 0, danceId: 'd1')],
        ),
      );
      await repos.programs.create(
        program(
          id: 'p-freetext',
          title: 'Spring Fling',
          venue: 'Town Hall',
          slots: [ProgramSlot(id: 's-freetext', position: 0, danceId: 'd1')],
        ),
      );

      await pumpSection(tester, repos);

      final linked = tester.widget<CallingHistoryRow>(
        find.byKey(const ValueKey('calling-history-s-linked')),
      );
      final freeText = tester.widget<CallingHistoryRow>(
        find.byKey(const ValueKey('calling-history-s-freetext')),
      );
      expect(linked.venueLabel, grange.displayName);
      expect(freeText.venueLabel, 'Town Hall');
    },
  );

  testWidgets(
    'does not read the venue catalogue for a history that links no venue',
    (tester) async {
      // Regression guard for a perf regression this section nearly shipped: the
      // one-shot load it replaced paid for `venues.listAll()` only when some
      // record carried a venueId, and loading it unconditionally would add that
      // query to opening any dance — including the common case of a dance with
      // no calling history at all.
      final counter = _VenueSelectCounter();
      final db = openWidgetTestDatabase(
        NativeDatabase.memory().interceptWith(counter),
      );
      addTearDown(db.close);
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.dances.create(dance('d1', 'Petronella'));
      await repos.venues.upsert(
        Venue(id: 'grange-hall', name: 'Grange Hall', city: 'Nelson'),
      );
      // A program with a free-text venue only: rendered from the record itself,
      // so the catalogue is not needed to label it.
      await repos.programs.create(
        program(
          id: 'p1',
          title: 'Autumn Ball',
          venue: 'Town Hall',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      counter.reset();

      await pumpSection(tester, repos);
      expect(historyRows(), findsOne);

      expect(
        counter.count,
        0,
        reason: 'no record links a venue, so the catalogue is not needed',
      );
    },
  );

  testWidgets('reads the venue catalogue once a record links a venue', (
    tester,
  ) async {
    final counter = _VenueSelectCounter();
    final db = openWidgetTestDatabase(
      NativeDatabase.memory().interceptWith(counter),
    );
    addTearDown(db.close);
    final repos = CompendiumRepositories(db, contraTaxonomy);
    final grange = Venue(
      id: 'grange-hall',
      name: 'Grange Hall',
      city: 'Nelson',
    );
    await repos.dances.create(dance('d1', 'Petronella'));
    await repos.venues.upsert(grange);
    await repos.programs.create(
      program(
        id: 'p1',
        title: 'Autumn Ball',
        venueId: 'grange-hall',
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      ),
    );
    counter.reset();

    await pumpSection(tester, repos);

    final row = tester.widget<CallingHistoryRow>(
      find.byKey(const ValueKey('calling-history-s1')),
    );
    expect(row.venueLabel, grange.displayName);
    expect(counter.count, 1, reason: 'read once, then cached');
  });

  testWidgets('does not carry the venue cache across a database swap', (
    tester,
  ) async {
    // Two databases that use the SAME venue id for different venues — which
    // is what makes the cache dangerous rather than merely stale: the id
    // resolves, so the "already resolved" check would skip the reload and the
    // row would keep rendering the first database's name.
    Future<CompendiumRepositories> build(String venueName) async {
      final repos = openTestRepositories();
      await repos.dances.create(dance('d1', 'Petronella'));
      await repos.venues.upsert(
        Venue(id: 'shared-id', name: venueName, city: 'Nelson'),
      );
      await repos.programs.create(
        program(
          id: 'p1',
          title: 'Autumn Ball',
          venueId: 'shared-id',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      return repos;
    }

    final first = await build('Grange Hall');
    final second = await build('Town Hall');

    Widget sectionFor(CompendiumRepositories repos) => MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: CallingHistorySection(
            repositories: repos,
            danceId: 'd1',
            performedOnly: false,
            trackAllCallers: true,
            onOpenProgram: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpWidget(sectionFor(first));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CallingHistoryRow>(
            find.byKey(const ValueKey('calling-history-s1')),
          )
          .venueLabel,
      contains('Grange Hall'),
    );

    // Same widget position, different database: the State is reused, so the
    // cache would survive unless it is cleared.
    await tester.pumpWidget(sectionFor(second));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<CallingHistoryRow>(
            find.byKey(const ValueKey('calling-history-s1')),
          )
          .venueLabel,
      contains('Town Hall'),
      reason:
          'the venue id is only meaningful within one database, so the cache '
          'must not answer for the new one',
    );
  });

  testWidgets('says so when the query fails, rather than "never called"', (
    tester,
  ) async {
    // A failed read used to render the empty state, which is a claim about the
    // data: it tells the caller this dance has never been called.
    final failing = _FailingSelects();
    final db = openWidgetTestDatabase(
      NativeDatabase.memory().interceptWith(failing),
    );
    addTearDown(db.close);
    final repos = CompendiumRepositories(db, contraTaxonomy);
    await repos.dances.create(dance('d1', 'Petronella'));
    await repos.programs.create(
      program(
        id: 'p1',
        title: 'Autumn Ball',
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      ),
    );
    failing.failCallingHistory = true;

    await pumpSection(tester, repos);

    expect(find.byKey(const ValueKey('calling-history-error')), findsOne);
    expect(
      find.byKey(const ValueKey('calling-history-empty')),
      findsNothing,
      reason: 'the dance HAS been called; the read is what failed',
    );
  });

  testWidgets('half-calling stats appear with the history, not a beat later', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(dance('d1', 'Petronella'));
    await repos.dances.create(dance('d2', 'Chase the Squirrel'));

    await pumpSection(tester, repos);
    expect(find.byKey(const ValueKey('half-calling-stats')), findsNothing);

    await repos.programs.create(
      program(
        id: 'p1',
        title: 'Autumn Ball',
        slots: [
          ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
          ProgramSlot(id: 'b1', position: 1, text: Program.breakSlotText),
          ProgramSlot(id: 's2', position: 2, danceId: 'd2'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(historyRows(), findsOne);
    expect(
      find.byKey(const ValueKey('half-calling-stats')),
      findsOne,
      reason:
          'the stats ride the history stream, so they must land in the same '
          'rebuild rather than one emit behind it',
    );
  });
}

/// Counts reads of the venue catalogue, so a test can assert the section pays
/// for it only when a calling-history record actually links a venue.
class _VenueSelectCounter extends drift.QueryInterceptor {
  int count = 0;

  void reset() => count = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('FROM "venues"')) count++;
    return executor.runSelect(statement, args);
  }
}

/// Fails the calling-history query on demand, so the section can be observed
/// with a broken read rather than an empty one.
class _FailingSelects extends drift.QueryInterceptor {
  bool failCallingHistory = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (failCallingHistory && statement.contains('AS slot_id')) {
      return Future.error(StateError('injected calling-history read failure'));
    }
    return executor.runSelect(statement, args);
  }
}
