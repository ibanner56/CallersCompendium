import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

/// Audit GIG-2: which date a call carries.
///
/// The maintainer's decision (2026-10-29): calling history uses the program's
/// event date when it has one. A slot's performed stamp says the dance was
/// called; its time dates the call only for an undated program. Re-dating a
/// program therefore moves its history, with no data migration.
///
/// Every surface that dates a call is pinned here against the same fixture, so
/// a surface that kept preferring the stamp would disagree with the others:
/// the history order and [DanceCallingRecord.effectiveDate], last-called, and
/// the Last-called sort. The counts, venue repeats and half stats carry no
/// date; the last test pins that re-dating leaves them alone.
void main() {
  final now = DateTime.utc(2026, 1, 1);
  final saturday = DateTime.utc(2026, 10, 24);
  final sunday = DateTime.utc(2026, 10, 25);
  // Mark all performed, tapped the Monday after Saturday's dance.
  final mondayTap = DateTime.utc(2026, 10, 26, 13);
  // Marked on the night, at an undated program on Saturday afternoon. With no
  // event date this stamp is the call's date, so it sorts after Saturday
  // midnight and before Sunday.
  final undatedTap = DateTime.utc(2026, 10, 24, 15);

  late CompendiumDatabase db;
  late ProgramRepository programs;
  late DanceRepository dances;

  Program program(
    String id, {
    DateTime? eventDate,
    required List<ProgramSlot> slots,
  }) => Program(
    id: id,
    title: id,
    eventDate: eventDate,
    venue: 'Grange Hall',
    slots: [
      ...slots,
      ProgramSlot(
        id: '$id-break',
        position: slots.length,
        text: Program.breakSlotText,
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );

  ProgramSlot slot(String id, String danceId, {DateTime? performedAt}) =>
      ProgramSlot(
        id: id,
        position: 0,
        danceId: danceId,
        performedAt: performedAt,
      );

  setUp(() async {
    db = openTestDatabase();
    programs = ProgramRepository(db);
    dances = DanceRepository(db, contraTaxonomy);
    for (final (id, title) in [
      ('chorus-jig', 'Chorus Jig'),
      ('petronella', 'Petronella'),
    ]) {
      await dances.create(
        Dance(id: id, title: title, createdAt: now, updatedAt: now),
      );
    }
    // Chorus Jig: called Saturday, marked Monday; and called at an undated
    // program, marked on the night.
    await programs.create(
      program(
        'saturday',
        eventDate: saturday,
        slots: [slot('sat-cj', 'chorus-jig', performedAt: mondayTap)],
      ),
    );
    await programs.create(
      program(
        'undated',
        slots: [slot('und-cj', 'chorus-jig', performedAt: undatedTap)],
      ),
    );
    // Petronella: called Sunday, marked on the night (21:00 New York).
    await programs.create(
      program(
        'sunday',
        eventDate: sunday,
        slots: [
          slot(
            'sun-pe',
            'petronella',
            performedAt: DateTime.utc(2026, 10, 26, 1),
          ),
        ],
      ),
    );
  });

  tearDown(() => db.close());

  Future<List<String>> lastCalledOrder({
    bool performedOnly = false,
    bool requireEventDate = false,
  }) => dances.search(
    const AndFilter([]),
    sort: SearchSort.lastCalled,
    performedOnly: performedOnly,
    requireEventDate: requireEventDate,
  );

  test('history rows are dated and ordered by the event date', () async {
    final rows = await programs.callingHistoryForDance('chorus-jig');
    // Saturday's tap came on Monday, which would put it first; the undated
    // program's call that afternoon is the later one.
    expect(rows.map((r) => r.programId), ['undated', 'saturday']);
    expect(rows.map((r) => r.effectiveDate), [undatedTap, saturday]);
    // The stamp is kept as recorded; only the date it gives the call changed.
    expect(rows.last.performedAt, mondayTap);

    final watched = await programs
        .watchCallingHistoryForDance('chorus-jig')
        .first;
    expect(watched.records, rows);
  });

  test('last-called takes the event date of a performed slot', () async {
    final lastCalled = await programs.lastCalledByDance();
    expect(lastCalled, {'chorus-jig': undatedTap, 'petronella': sunday});
    expect(await programs.lastCalledByDance(requireEventDate: true), {
      'chorus-jig': saturday,
      'petronella': sunday,
    });
    expect(
      (await programs.watchProgramDerivedCounts().first).lastCalled,
      lastCalled,
    );
    expect((await programs.programDerivedCounts()).lastCalled, lastCalled);
  });

  test('the Last-called sort follows the same date in every mode', () async {
    // Petronella's Sunday beats Chorus Jig's Saturday afternoon. Had the
    // Monday tap dated Saturday's call, Chorus Jig would come first.
    for (final performedOnly in [false, true]) {
      for (final requireEventDate in [false, true]) {
        expect(
          await lastCalledOrder(
            performedOnly: performedOnly,
            requireEventDate: requireEventDate,
          ),
          ['petronella', 'chorus-jig'],
          reason:
              'performedOnly: $performedOnly, '
              'requireEventDate: $requireEventDate',
        );
      }
    }
  });

  test('every surface agrees on each dance\'s latest date', () async {
    for (final performedOnly in [false, true]) {
      for (final requireEventDate in [false, true]) {
        final latest = <String, DateTime>{};
        for (final danceId in ['chorus-jig', 'petronella']) {
          final rows = await programs.callingHistoryForDance(
            danceId,
            performedOnly: performedOnly,
            requireEventDate: requireEventDate,
          );
          latest[danceId] = rows.first.effectiveDate;
        }
        final mode =
            'performedOnly: $performedOnly, '
            'requireEventDate: $requireEventDate';
        // Every slot in the fixture is performed, so last-called (performed
        // slots only) covers the same slots as the history in each mode.
        expect(
          await programs.lastCalledByDance(requireEventDate: requireEventDate),
          latest,
          reason: mode,
        );
        final byLatest = latest.keys.toList()
          ..sort((a, b) => latest[b]!.compareTo(latest[a]!));
        expect(
          await lastCalledOrder(
            performedOnly: performedOnly,
            requireEventDate: requireEventDate,
          ),
          byLatest,
          reason: mode,
        );
      }
    }
  });

  test('re-dating a program moves its history and nothing else', () async {
    final countsBefore = await programs.countByDance();
    final historyBefore = await programs
        .watchCallingHistoryForDance('chorus-jig')
        .first;

    final stored = (await programs.getById('saturday'))!;
    final halloween = DateTime.utc(2026, 10, 31);
    await programs.update(stored.copyWith(eventDate: halloween));

    final rows = await programs.callingHistoryForDance('chorus-jig');
    expect(rows.map((r) => r.programId), ['saturday', 'undated']);
    expect(rows.first.effectiveDate, halloween);
    expect(
      rows.first.performedAt,
      mondayTap,
      reason: 'stamps are not rewritten',
    );
    expect((await programs.lastCalledByDance())['chorus-jig'], halloween);
    expect(await lastCalledOrder(), ['chorus-jig', 'petronella']);

    // Counts, venue repeats and half stats carry no date.
    expect(await programs.countByDance(), countsBefore);
    final historyAfter = await programs
        .watchCallingHistoryForDance('chorus-jig')
        .first;
    expect(historyAfter.venueCounts, historyBefore.venueCounts);
    expect(historyAfter.halfStats, historyBefore.halfStats);
  });
}
