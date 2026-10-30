import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/storage/calling_history_scope.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:test/test.dart';

import 'test_database.dart';

/// Audit FIND-1, design note N1 (`docs/design/history-filters.md`), branch H1:
/// the venue, recency and current-program scopes on [CalledFilter].
///
/// A scope narrows the slots the calling-history rules select before the
/// polarity applies; it never builds a second definition of "called". Each
/// group below pins one of the maintainer's answers (N1-1, N1-3, N1-6, N1-9,
/// 2026-10-30) against the naive version a later edit could slide back to.
void main() {
  final now = DateTime.utc(2026, 10, 30, 12);
  // "Within 3 months" of 2026-10-30.
  final cutoff = DateTime.utc(2026, 7, 30);

  late CompendiumDatabase db;
  late ProgramRepository programs;
  late DanceRepository dances;
  late VenueRepository venues;

  setUp(() async {
    db = openTestDatabase();
    programs = ProgramRepository(db);
    dances = DanceRepository(db, contraTaxonomy);
    venues = VenueRepository(db);
  });

  tearDown(() => db.close());

  Future<void> dance(String id) =>
      dances.create(Dance(id: id, title: id, createdAt: now, updatedAt: now));

  Future<void> program(
    String id, {
    String? venue,
    String? venueId,
    String? caller,
    DateTime? eventDate,
    DateTime? updatedAt,
    required List<ProgramSlot> slots,
  }) => programs.create(
    Program(
      id: id,
      title: id,
      venue: venue,
      venueId: venueId,
      caller: caller,
      eventDate: eventDate,
      slots: slots,
      createdAt: DateTime.utc(2020),
      updatedAt: updatedAt ?? DateTime.utc(2020),
    ),
  );

  ProgramSlot slot(
    String id,
    String danceId, {
    int position = 0,
    DateTime? performedAt,
    bool isAlt = false,
  }) => ProgramSlot(
    id: id,
    position: position,
    danceId: danceId,
    performedAt: performedAt,
    isAlt: isAlt,
  );

  Future<Set<String>> search(CalledFilter filter) async =>
      (await dances.search(filter)).toSet();

  group('venue scope (N1-1: the venue key)', () {
    test('matches every key the repeated-venues summary groups by', () async {
      // One dance per spelling. The summary folds whitespace runs and
      // lower-cases every script, so all three typed spellings are one key;
      // SQLite's ASCII-only LOWER and lack of a whitespace fold would split
      // them.
      for (final id in ['a', 'b', 'c', 'd', 'e']) {
        await dance(id);
      }
      await venues.upsert(Venue(id: 'grange-record', name: 'Grange'));
      await program('p1', venue: 'Salle  Église', slots: [slot('s1', 'a')]);
      await program('p2', venue: ' salle église ', slots: [slot('s2', 'b')]);
      await program('p3', venue: 'SALLE\tÉGLISE', slots: [slot('s3', 'c')]);
      await program('p4', venue: 'Grange', slots: [slot('s4', 'd')]);
      await program(
        'p5',
        venue: 'Grange',
        venueId: 'grange-record',
        slots: [slot('s5', 'e')],
      );

      final byKey = <VenueKey, Set<String>>{};
      for (final id in ['a', 'b', 'c', 'd', 'e']) {
        final history = await programs.watchCallingHistoryForDance(id).first;
        for (final count in history.venueCounts) {
          (byKey[count.key] ??= {}).add(id);
        }
      }
      expect(byKey.keys, hasLength(3));
      expect(byKey[VenueKey.typed('salle église')], {'a', 'b', 'c'});

      for (final MapEntry(:key, value: summaryDances) in byKey.entries) {
        expect(
          await search(CalledFilter(called: true, venue: key)),
          summaryDances,
          reason: '$key',
        );
        expect(
          await search(CalledFilter(called: false, venue: key)),
          {'a', 'b', 'c', 'd', 'e'}.difference(summaryDances),
          reason: '$key',
        );
      }

      // The listing for the chooser keys venues the same way.
      final listed = await programs.calledVenues();
      expect(listed.map((v) => v.key).toSet(), byKey.keys.toSet());
    });

    test('a typed "Grange" does not match the record "Grange"', () async {
      await dance('typed');
      await dance('linked');
      await venues.upsert(Venue(id: 'grange-record', name: 'Grange'));
      await program('t', venue: 'Grange', slots: [slot('t1', 'typed')]);
      // A linked program's own typed text is ignored: the record is its key.
      await program(
        'l',
        venue: 'Grange',
        venueId: 'grange-record',
        slots: [slot('l1', 'linked')],
      );

      expect(
        await search(
          CalledFilter(called: true, venue: VenueKey.typed('grange')),
        ),
        {'typed'},
      );
      expect(
        await search(
          const CalledFilter(
            called: true,
            venue: VenueKey.record('grange-record'),
          ),
        ),
        {'linked'},
      );
    });

    test('a guest caller\'s program at the venue does not count when '
        'history is scoped to the default caller', () async {
      await dance('guest-only');
      await program(
        'guest',
        venue: 'Grange',
        caller: 'Someone Else',
        slots: [slot('g1', 'guest-only')],
      );

      final grange = VenueKey.typed('Grange');
      expect(await search(CalledFilter(called: true, venue: grange)), {
        'guest-only',
      });
      expect(
        await search(
          CalledFilter(called: true, venue: grange, callerFilter: 'Me'),
        ),
        isEmpty,
      );
    });
  });

  group('composition', () {
    test('"not called at V within 3 months" is NOT EXISTS a counted slot at V '
        'in the window', () async {
      for (final id in [
        'here-and-away',
        'away-only',
        'never',
        'here-long-ago',
      ]) {
        await dance(id);
      }
      await program(
        'grange-recent',
        venue: 'Grange',
        eventDate: DateTime.utc(2026, 10, 1),
        slots: [slot('r1', 'here-and-away')],
      );
      await program(
        'grange-old',
        venue: 'Grange',
        eventDate: DateTime.utc(2025, 1, 1),
        slots: [slot('o1', 'here-long-ago')],
      );
      await program(
        'hall',
        venue: 'Town Hall',
        eventDate: DateTime.utc(2026, 10, 2),
        slots: [
          slot('h1', 'here-and-away'),
          slot('h2', 'away-only', position: 1),
        ],
      );

      final notHere = await search(
        CalledFilter(
          called: false,
          venue: VenueKey.typed('Grange'),
          since: cutoff,
        ),
      );
      // A dance with a slot elsewhere is still "called at the Grange" when it
      // has one there too, and an old Grange call is outside the window.
      expect(notHere, {'away-only', 'never', 'here-long-ago'});
    });

    test('every scope and the caller clause bind in order', () async {
      await dance('x');
      await dance('y');
      await program(
        'mine',
        venue: 'Grange',
        caller: 'Me',
        eventDate: DateTime.utc(2026, 9, 1),
        slots: [slot('m1', 'x')],
      );
      await program(
        'editing',
        venue: 'Grange',
        caller: 'Me',
        eventDate: DateTime.utc(2026, 9, 2),
        slots: [slot('e1', 'y')],
      );

      expect(
        await search(
          CalledFilter(
            called: true,
            callerFilter: 'me',
            venue: VenueKey.typed('grange'),
            since: cutoff,
            currentProgramId: 'editing',
          ),
        ),
        {'x'},
      );
    });
  });

  group('recency scope (N1-3, N1-9)', () {
    test(
      'an undated, unperformed slot is called but in no recency window',
      () async {
        await dance('draft-only');
        // Edited today, so B1's full date expression would date it today.
        await program(
          'draft',
          updatedAt: now,
          slots: [slot('d1', 'draft-only')],
        );

        expect(await search(const CalledFilter(called: true)), {'draft-only'});
        expect(
          await search(CalledFilter(called: true, since: cutoff)),
          isEmpty,
        );
        expect(await search(CalledFilter(called: false, since: cutoff)), {
          'draft-only',
        });
      },
    );

    test('an undated slot marked performed is dated by its stamp', () async {
      await dance('tapped');
      await program(
        'undated',
        slots: [
          slot('u1', 'tapped', performedAt: DateTime.utc(2026, 10, 1, 21)),
        ],
      );
      expect(await search(CalledFilter(called: true, since: cutoff)), {
        'tapped',
      });
    });

    test(
      'a program dated next month counts inside "within 3 months"',
      () async {
        await dance('planned');
        await program(
          'next-month',
          eventDate: DateTime.utc(2026, 11, 28),
          slots: [slot('n1', 'planned')],
        );
        expect(await search(CalledFilter(called: true, since: cutoff)), {
          'planned',
        });
        expect(
          await search(CalledFilter(called: false, since: cutoff)),
          isEmpty,
        );
      },
    );

    test(
      'the cutoff day is inside the window, the day before is not',
      () async {
        await dance('on-cutoff');
        await dance('day-before');
        await program(
          'on',
          eventDate: cutoff,
          slots: [slot('c1', 'on-cutoff')],
        );
        await program(
          'before',
          eventDate: cutoff.subtract(const Duration(days: 1)),
          slots: [slot('c2', 'day-before')],
        );
        expect(await search(CalledFilter(called: true, since: cutoff)), {
          'on-cutoff',
        });
      },
    );

    test('rejects a cutoff that is not a UTC calendar date', () {
      for (final bad in [DateTime(2026, 7, 30), DateTime.utc(2026, 7, 30, 1)]) {
        expect(
          () => FilterCompiler(
            null,
            null,
            contraTaxonomy,
          ).compile(CalledFilter(called: true, since: bad)),
          throwsArgumentError,
          reason: '$bad',
        );
      }
    });
  });

  group('current program (N1-6: the whole program)', () {
    test('hides a performed slot of the program being edited', () async {
      await dance('tonight-only');
      await program(
        'tonight',
        venue: 'Grange',
        eventDate: DateTime.utc(2026, 10, 30),
        slots: [
          slot(
            't1',
            'tonight-only',
            performedAt: DateTime.utc(2026, 10, 30, 20),
          ),
        ],
      );

      expect(await search(const CalledFilter(called: true)), {'tonight-only'});
      expect(
        await search(
          const CalledFilter(called: true, currentProgramId: 'tonight'),
        ),
        isEmpty,
      );
      expect(
        await search(
          CalledFilter(
            called: false,
            venue: VenueKey.typed('Grange'),
            currentProgramId: 'tonight',
          ),
        ),
        {'tonight-only'},
      );
    });
  });

  group('calledVenues', () {
    test('lists each venue with a counted call, its program count and its '
        'latest typed text, newest first', () async {
      await dance('a');
      await dance('b');
      await venues.upsert(Venue(id: 'grange-record', name: 'Grange'));
      await program(
        'hall-1',
        venue: 'town  hall',
        eventDate: DateTime.utc(2026, 1, 1),
        slots: [slot('h1', 'a'), slot('h2', 'b', position: 1)],
      );
      await program(
        'hall-2',
        venue: 'Town Hall',
        eventDate: DateTime.utc(2026, 3, 1),
        slots: [slot('h3', 'a')],
      );
      await program(
        'grange',
        venueId: 'grange-record',
        eventDate: DateTime.utc(2026, 5, 1),
        slots: [slot('g1', 'a')],
      );
      // Only an unperformed alternate: no counted call, so not listed.
      await program(
        'barn',
        venue: 'Barn',
        eventDate: DateTime.utc(2026, 6, 1),
        slots: [slot('b1', 'a', isAlt: true)],
      );
      // Deleted programs never count.
      await program(
        'deleted',
        venue: 'Chapel',
        eventDate: DateTime.utc(2026, 6, 1),
        slots: [slot('c1', 'a')],
      );
      await programs.softDelete('deleted', at: now);
      // No venue at all.
      await program('nowhere', slots: [slot('n1', 'a')]);

      final expected = [
        const CalledVenue(
          key: VenueKey.record('grange-record'),
          programCount: 1,
        ),
        CalledVenue(
          key: VenueKey.typed('town hall'),
          programCount: 2,
          latestVenueText: 'Town Hall',
        ),
      ];
      expect(await programs.calledVenues(), expected);
      expect(await programs.watchCalledVenues().first, expected);
    });

    test('honours the calling-history settings', () async {
      await dance('a');
      await program(
        'undated-unperformed',
        venue: 'Barn',
        slots: [slot('u1', 'a')],
      );
      await program(
        'guest',
        venue: 'Chapel',
        caller: 'Someone Else',
        eventDate: DateTime.utc(2026, 1, 1),
        slots: [slot('g1', 'a', performedAt: DateTime.utc(2026, 1, 1, 21))],
      );

      Future<Set<VenueKey>> keys({
        bool performedOnly = false,
        bool requireEventDate = false,
        String? callerFilter,
      }) async => {
        for (final v in await programs.calledVenues(
          performedOnly: performedOnly,
          requireEventDate: requireEventDate,
          callerFilter: callerFilter,
        ))
          v.key,
      };

      expect(await keys(), {VenueKey.typed('barn'), VenueKey.typed('chapel')});
      expect(await keys(performedOnly: true), {VenueKey.typed('chapel')});
      expect(await keys(requireEventDate: true), {VenueKey.typed('chapel')});
      expect(await keys(callerFilter: 'Me'), {VenueKey.typed('barn')});
    });
  });

  group('one date expression', () {
    test('SQL picks the same date as effectiveDate and recencyDate for every '
        'combination of dates', () async {
      await dance('d');
      final event = DateTime.utc(2026, 9, 5);
      final performed = DateTime.utc(2026, 9, 7, 21, 30);
      final edited = DateTime.utc(2026, 10, 1, 9);
      var n = 0;
      for (final eventDate in [event, null]) {
        for (final performedAt in [performed, null]) {
          n++;
          await program(
            'p$n',
            eventDate: eventDate,
            updatedAt: edited,
            slots: [slot('s$n', 'd', performedAt: performedAt)],
          );
        }
      }
      final records = {
        for (final r in await programs.callingHistoryForDance('d')) r.slotId: r,
      };
      expect(records, hasLength(4));

      final rows = await db
          .customSelect(
            'SELECT ps.id AS slot_id, '
            '${callingHistoryDateSql(slotTable: 'ps', programTable: 'p')} '
            'AS history_date, '
            '${callingHistoryRecencyDateSql(slotTable: 'ps', programTable: 'p')} '
            'AS recency_date '
            'FROM program_slots ps JOIN programs p ON p.id = ps.program_id',
          )
          .get();
      expect(rows, hasLength(4));
      for (final row in rows) {
        final record = records[row.read<String>('slot_id')]!;
        expect(
          row.read<DateTime>('history_date').toUtc(),
          record.effectiveDate,
          reason: record.slotId,
        );
        expect(
          row.read<DateTime?>('recency_date')?.toUtc(),
          record.recencyDate,
          reason: record.slotId,
        );
      }
      // The undated, unperformed slot is the one with no recency date.
      expect(
        [
          for (final r in records.values)
            if (r.recencyDate == null) r.slotId,
        ],
        ['s4'],
      );
    });
  });

  group('VenueKey', () {
    test(
      'a linked record wins over the typed text; a blank venue has no key',
      () {
        expect(
          VenueKey.forProgram(venueId: 'v', venue: 'Grange'),
          const VenueKey.record('v'),
        );
        expect(
          VenueKey.forProgram(venue: '  Grange   Hall '),
          VenueKey.typed('grange hall'),
        );
        expect(VenueKey.forProgram(venue: ' \t '), isNull);
        expect(VenueKey.forProgram(), isNull);
        expect(() => VenueKey.typed('  '), throwsArgumentError);
        expect(VenueKey.typed('Grange').storageKey, 'text:grange');
        expect(const VenueKey.record('v').storageKey, 'id:v');
      },
    );
  });

  test('the test database registers the venue-key function', () async {
    final row = await db
        .customSelect(
          'SELECT $callingHistoryVenueKeySqlFunction(?) AS k',
          variables: [Variable<String>('  Salle  Église ')],
        )
        .getSingle();
    expect(row.read<String>('k'), 'salle église');
  });
}
