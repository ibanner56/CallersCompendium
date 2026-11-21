import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

/// Audit batch F5: one "called" rule across every calling-history surface.
///
/// The maintainer's ruling (2026-10-28): an alternate slot counts toward its
/// dance only once that slot is marked performed; a primary slot keeps the
/// documented default (#583: any program counts unless "Require mark
/// performed" is on). The worked example is the one used here — Hull's Victory
/// listed as the alternate to Chorus Jig, and only Chorus Jig marked performed.
///
/// FIND-2: the Last-called sort reads the same caller-scoped, performed-aware
/// history as the count, ordered by the history list's
/// `COALESCE(event_date, performed_at, updated_at)` (GIG-2).
void main() {
  final now = DateTime.utc(2026, 1, 1);
  final gig = DateTime.utc(2026, 3, 14);

  late CompendiumDatabase db;
  late ProgramRepository programs;
  late DanceRepository dances;

  Future<void> dance(String id, String title) => dances.create(
    Dance(id: id, title: title, createdAt: now, updatedAt: now),
  );

  setUp(() async {
    db = openTestDatabase();
    programs = ProgramRepository(db);
    dances = DanceRepository(db, contraTaxonomy);
    await dance('chorus-jig', 'Chorus Jig');
    await dance('hulls-victory', "Hull's Victory");
  });

  tearDown(() => db.close());

  /// Chorus Jig with Hull's Victory as its alternate, at a named venue.
  Program saturday({
    DateTime? chorusPerformedAt,
    DateTime? hullsPerformedAt,
    String id = 'p1',
    String? caller,
    DateTime? eventDate,
  }) => Program(
    id: id,
    title: 'Saturday',
    caller: caller,
    eventDate: eventDate,
    venue: 'Grange Hall',
    slots: [
      ProgramSlot(
        id: '$id-chorus',
        position: 0,
        danceId: 'chorus-jig',
        performedAt: chorusPerformedAt,
      ),
      ProgramSlot(
        id: '$id-hulls',
        position: 1,
        danceId: 'hulls-victory',
        isAlt: true,
        performedAt: hullsPerformedAt,
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );

  group('an unperformed alternate is not called', () {
    setUp(() async {
      await programs.create(saturday(chorusPerformedAt: gig));
      await programs.create(saturday(id: 'p2', chorusPerformedAt: gig));
    });

    test('Called ×N counts only the performed primary', () async {
      final counts = await programs.countByDance();
      expect(
        counts['chorus-jig'],
        const DanceCallCounts(
          all: 2,
          performed: 2,
          dated: 0,
          performedDated: 0,
        ),
      );
      expect(counts, isNot(contains('hulls-victory')));
    });

    test('the watched counts agree', () async {
      final derived = await programs.watchProgramDerivedCounts().first;
      expect(derived.callCounts, isNot(contains('hulls-victory')));
      expect(derived.lastCalled, isNot(contains('hulls-victory')));
    });

    test('history rows, venue repeats and half stats are empty', () async {
      for (final performedOnly in [false, true]) {
        expect(
          await programs.callingHistoryForDance(
            'hulls-victory',
            performedOnly: performedOnly,
          ),
          isEmpty,
        );
        final history = await programs
            .watchCallingHistoryForDance(
              'hulls-victory',
              performedOnly: performedOnly,
            )
            .first;
        expect(history.records, isEmpty);
        expect(history.venueCounts, isEmpty);
        expect(history.halfStats, HalfCallingStats.empty);
        expect(
          await programs.halfCallingStatsForDance(
            'hulls-victory',
            performedOnly: performedOnly,
          ),
          HalfCallingStats.empty,
        );
      }
      final chorus = await programs
          .watchCallingHistoryForDance('chorus-jig')
          .first;
      expect(chorus.records, hasLength(2));
      expect(chorus.venueCounts.single.count, 2);
    });

    test('the Called filter leaves it out, in both modes', () async {
      for (final performedOnly in [false, true]) {
        expect(
          await dances.search(
            CalledFilter(called: true, performedOnly: performedOnly),
          ),
          ['chorus-jig'],
        );
        expect(
          await dances.search(
            CalledFilter(called: false, performedOnly: performedOnly),
          ),
          ['hulls-victory'],
        );
      }
    });

    test('the Last-called sort treats it as never called', () async {
      // Abbey Reel is never programmed and sorts before Hull's Victory by
      // title, so Hull's Victory lands after it only if the sort agrees that
      // it was never called. Dated by its program instead, it would lead the
      // never-called tail.
      await dance('abbey-reel', 'Abbey Reel');
      expect(
        await dances.search(const AndFilter([]), sort: SearchSort.lastCalled),
        ['chorus-jig', 'abbey-reel', 'hulls-victory'],
      );
    });
  });

  test('an alternate marked performed counts everywhere', () async {
    await programs.create(
      saturday(chorusPerformedAt: gig, hullsPerformedAt: gig),
    );
    expect(
      (await programs.countByDance())['hulls-victory'],
      const DanceCallCounts(all: 1, performed: 1, dated: 0, performedDated: 0),
    );
    final history = await programs
        .watchCallingHistoryForDance('hulls-victory', performedOnly: true)
        .first;
    expect(history.records.single.performedAt, gig);
    expect(await dances.search(const CalledFilter(called: true)), [
      'chorus-jig',
      'hulls-victory',
    ]);
  });

  test('an unmarked primary still counts by default (#583)', () async {
    await programs.create(saturday());
    expect(
      (await programs.countByDance())['chorus-jig'],
      const DanceCallCounts(all: 1, performed: 0, dated: 0, performedDated: 0),
    );
    expect(await programs.callingHistoryForDance('chorus-jig'), hasLength(1));
  });

  group('Status → Performed stamps primaries only', () {
    test('the transition leaves the alternate unmarked', () async {
      await programs.create(saturday(eventDate: gig));
      final draft = (await programs.getById('p1'))!;
      await programs.update(
        draft.copyWith(status: ProgramStatus.performed, updatedAt: gig),
      );
      final stored = (await programs.getById('p1'))!;
      expect(stored.slots.map((s) => s.performedAt), [gig, null]);
      expect(await programs.countByDance(), isNot(contains('hulls-victory')));
    });

    test('a primary cleared by hand stays cleared (#390)', () async {
      await programs.create(saturday(eventDate: gig));
      final draft = (await programs.getById('p1'))!;
      await programs.update(
        draft.copyWith(status: ProgramStatus.performed, updatedAt: gig),
      );
      final performed = (await programs.getById('p1'))!;
      final cleared = performed.copyWith(
        slots: [
          performed.slots[0].copyWith(clearPerformedAt: true),
          performed.slots[1],
        ],
        updatedAt: gig.add(const Duration(days: 1)),
      );
      await programs.update(cleared);
      expect((await programs.getById('p1'))!.slots.map((s) => s.performedAt), [
        null,
        null,
      ]);
    });
  });

  group('the Last-called sort follows the history settings (FIND-2)', () {
    setUp(() async {
      await dance('mine', 'Mine');
      await dance('guest', 'Guest');
    });

    Program unmarked(
      String id,
      String danceId, {
      String? caller,
      DateTime? eventDate,
      DateTime? updatedAt,
    }) => Program(
      id: id,
      title: id,
      caller: caller,
      eventDate: eventDate,
      slots: [ProgramSlot(id: '$id-s', position: 0, danceId: danceId)],
      createdAt: now,
      updatedAt: updatedAt ?? now,
    );

    test('by default, an unmarked program dates the dance', () async {
      // Neither slot is marked, so before FIND-2 both dances fell into the
      // never-called tail in title order (Guest, Mine).
      await programs.create(
        unmarked('older', 'guest', eventDate: DateTime.utc(2026, 2)),
      );
      await programs.create(
        unmarked('newer', 'mine', eventDate: DateTime.utc(2026, 5)),
      );
      final sorted = await dances.search(
        const AndFilter([]),
        sort: SearchSort.lastCalled,
      );
      expect(sorted.take(2), ['mine', 'guest']);
    });

    test('with no event date, the program update time dates it', () async {
      await programs.create(
        unmarked('older', 'mine', updatedAt: DateTime.utc(2026, 2)),
      );
      await programs.create(
        unmarked('newer', 'guest', updatedAt: DateTime.utc(2026, 5)),
      );
      final sorted = await dances.search(
        const AndFilter([]),
        sort: SearchSort.lastCalled,
      );
      expect(sorted.take(2), ['guest', 'mine']);
    });

    test('performedOnly ignores unmarked programs', () async {
      await programs.create(
        unmarked('unmarked', 'guest', eventDate: DateTime.utc(2026, 5)),
      );
      await programs.create(
        Program(
          id: 'marked',
          title: 'marked',
          slots: [
            ProgramSlot(
              id: 'marked-s',
              position: 0,
              danceId: 'mine',
              performedAt: DateTime.utc(2026, 2),
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );
      final sorted = await dances.search(
        const AndFilter([]),
        sort: SearchSort.lastCalled,
        performedOnly: true,
      );
      // Mine first; the rest never called, in title order.
      expect(sorted, ['mine', 'chorus-jig', 'guest', 'hulls-victory']);
    });

    test('a caller filter ignores other callers\' programs', () async {
      await programs.create(
        unmarked(
          'theirs',
          'guest',
          caller: 'Someone Else',
          eventDate: DateTime.utc(2026, 5),
        ),
      );
      await programs.create(
        unmarked(
          'ours',
          'mine',
          caller: ' grace hopper ',
          eventDate: DateTime.utc(2026, 2),
        ),
      );
      final sorted = await dances.search(
        const AndFilter([]),
        sort: SearchSort.lastCalled,
        callerFilter: 'Grace Hopper',
      );
      expect(sorted, ['mine', 'chorus-jig', 'guest', 'hulls-victory']);
      // Without the filter, the other caller's later program leads.
      expect(
        (await dances.search(
          const AndFilter([]),
          sort: SearchSort.lastCalled,
        )).take(2),
        ['guest', 'mine'],
      );
    });
  });
}
