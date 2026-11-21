import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

/// Audit batch F6: "Require an event date" for calling history.
///
/// The maintainer's decision (2026-10-28): a duplicated or received program
/// arrives undated and still counts by default (#583: any program counts).
/// With the setting on, a program with no event date counts nowhere history is
/// read. Every read below goes through `callingHistoryEventDateClause`, so the
/// surfaces stay in lockstep; each test pins one of them.
void main() {
  final now = DateTime.utc(2026, 1, 1);
  final dated = DateTime.utc(2026, 3, 14, 20);
  final undatedCall = DateTime.utc(2026, 5, 2, 20);

  late CompendiumDatabase db;
  late ProgramRepository programs;
  late DanceRepository dances;

  Future<void> dance(String id, String title) => dances.create(
    Dance(id: id, title: title, createdAt: now, updatedAt: now),
  );

  /// One program opening its first half with [danceId], at a named venue,
  /// with that slot marked performed at [performedAt].
  Program program(
    String id,
    String danceId, {
    DateTime? eventDate,
    DateTime? performedAt,
    String venue = 'Grange Hall',
  }) => Program(
    id: id,
    title: id,
    eventDate: eventDate,
    venue: venue,
    slots: [
      ProgramSlot(
        id: '$id-slot',
        position: 0,
        danceId: danceId,
        performedAt: performedAt,
      ),
      ProgramSlot(id: '$id-break', position: 1, text: Program.breakSlotText),
    ],
    createdAt: now,
    updatedAt: now,
  );

  setUp(() async {
    db = openTestDatabase();
    programs = ProgramRepository(db);
    dances = DanceRepository(db, contraTaxonomy);
    await dance('chorus-jig', 'Chorus Jig');
    await dance('petronella', 'Petronella');
    // Chorus Jig: one dated program and one undated one, both performed. The
    // undated call is the later one, so it would win last-called.
    await programs.create(
      program('dated', 'chorus-jig', eventDate: dated, performedAt: dated),
    );
    await programs.create(
      program(
        'undated',
        'chorus-jig',
        performedAt: undatedCall,
        venue: 'Town Hall',
      ),
    );
    // Petronella: only in an undated, unperformed program (a fresh duplicate).
    await programs.create(program('copy', 'petronella', venue: 'Town Hall'));
  });

  tearDown(() => db.close());

  test('off by default: an undated program counts everywhere', () async {
    final counts = await programs.countByDance();
    expect(counts['chorus-jig']!.countFor(false), 2);
    expect(counts['petronella']!.countFor(false), 1);
    expect(await programs.callingHistoryForDance('chorus-jig'), hasLength(2));
    expect(await dances.search(const CalledFilter(called: true)), [
      'chorus-jig',
      'petronella',
    ]);
  });

  test('Called ×N: the dated tallies leave undated programs out', () async {
    final counts = await programs.countByDance();
    expect(
      counts['chorus-jig'],
      const DanceCallCounts(all: 2, performed: 2, dated: 1, performedDated: 1),
    );
    expect(counts['chorus-jig']!.countFor(false, requireEventDate: true), 1);
    expect(counts['chorus-jig']!.countFor(true, requireEventDate: true), 1);
    expect(counts['petronella']!.countFor(false, requireEventDate: true), 0);
    // The stream carries the same tallies.
    final watched = await programs.watchProgramDerivedCounts().first;
    expect(watched.callCounts, counts);
  });

  test('history rows, venue counts and half stats', () async {
    final rows = await programs.callingHistoryForDance(
      'chorus-jig',
      requireEventDate: true,
    );
    expect(rows.map((r) => r.programId), ['dated']);

    final history = await programs
        .watchCallingHistoryForDance('chorus-jig', requireEventDate: true)
        .first;
    expect(history.records.map((r) => r.programId), ['dated']);
    expect(history.venueCounts.map((v) => v.venue), ['Grange Hall']);
    final halfStats = await programs.halfCallingStatsForDance(
      'chorus-jig',
      requireEventDate: true,
    );
    expect(halfStats, history.halfStats);
    expect(
      halfStats,
      isNot(await programs.halfCallingStatsForDance('chorus-jig')),
      reason: 'the undated program must drop out of the stats too',
    );

    expect(
      await programs.callingHistoryForDance(
        'petronella',
        requireEventDate: true,
      ),
      isEmpty,
    );
  });

  test('the Called filter', () async {
    expect(
      await dances.search(
        const CalledFilter(called: true, requireEventDate: true),
      ),
      ['chorus-jig'],
    );
    expect(
      await dances.search(
        const CalledFilter(called: false, requireEventDate: true),
      ),
      ['petronella'],
    );
  });

  test('last-called and the Last-called sort', () async {
    expect((await programs.lastCalledByDance())['chorus-jig'], undatedCall);
    expect(
      (await programs.lastCalledByDance(requireEventDate: true))['chorus-jig'],
      dated,
    );

    // A dance called only in an undated program sorts as never called.
    await dance('rory', "Rory O'More");
    await programs.create(
      program(
        'rory-dated',
        'rory',
        eventDate: DateTime.utc(2026, 4, 1),
        performedAt: DateTime.utc(2026, 4, 1, 20),
      ),
    );
    final defaultOrder = await dances.search(
      const AndFilter([]),
      sort: SearchSort.lastCalled,
    );
    expect(defaultOrder, ['chorus-jig', 'rory', 'petronella']);
    final requiredOrder = await dances.search(
      const AndFilter([]),
      sort: SearchSort.lastCalled,
      requireEventDate: true,
    );
    expect(requiredOrder, ['rory', 'chorus-jig', 'petronella']);
  });
}
