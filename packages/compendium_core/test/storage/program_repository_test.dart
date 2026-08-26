import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

Program sampleProgram({
  String id = 'p1',
  String title = 'Spring Dance 2026',
  List<ProgramSlot> slots = const [],
  String? caller,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? deletedAt,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Program(
    id: id,
    title: title,
    eventDate: DateTime.utc(2026, 3, 15),
    venue: 'Grange Hall',
    caller: caller,
    slots: slots,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
    deletedAt: deletedAt,
  );
}

void main() {
  late CompendiumDatabase db;
  late ProgramRepository repo;
  late DanceRepository dances;

  setUp(() {
    db = openTestDatabase();
    repo = ProgramRepository(db);
    dances = DanceRepository(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  group('create / getById', () {
    test('bulk validation rejects a tombstoned venue', () async {
      final venues = VenueRepository(db);
      await venues.upsert(Venue(id: 'v1', name: 'Deleted Hall'));
      await venues.delete('v1');
      final liveVenueIds = await venues.listAllIds();

      await expectLater(
        repo.create(
          sampleProgram().copyWith(venueId: 'v1'),
          knownVenueIds: liveVenueIds,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('round-trips a program with no slots', () async {
      final program = sampleProgram();
      await repo.create(program);
      expect(await repo.getById(program.id), program);
    });

    test(
      'round-trips slots in position order, including text-only slots',
      () async {
        await dances.create(
          Dance(
            id: 'd1',
            title: 'Chase the Squirrel',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );
        final program = sampleProgram(
          slots: [
            ProgramSlot(id: 's2', position: 1, text: 'Waltz break'),
            ProgramSlot(id: 's1', position: 0, danceId: 'd1', isAlt: true),
          ],
        );
        await repo.create(program);
        final loaded = await repo.getById(program.id);
        expect(loaded!.slots.map((s) => s.id), ['s1', 's2']);
        expect(loaded.slots.first.danceId, 'd1');
        expect(loaded.slots.first.isAlt, isTrue);
        expect(loaded.slots.last.text, 'Waltz break');
      },
    );

    test('a slot survives its dance being hard-purged (tombstone)', () async {
      await dances.create(
        Dance(
          id: 'd1',
          title: 'Doomed Dance',
          deletedAt: DateTime.utc(2026, 1, 1),
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      final program = sampleProgram(
        slots: [
          ProgramSlot(
            id: 's1',
            position: 0,
            danceId: 'd1',
            text: 'played anyway',
          ),
        ],
      );
      await repo.create(program);
      await dances.purgeDeleted(now: DateTime.utc(2026, 4, 1));

      final loaded = await repo.getById(program.id);
      expect(loaded!.slots.single.danceId, isNull);
      expect(loaded.slots.single.text, 'played anyway');
    });

    test('a DANCE-ONLY slot survives its dance being hard-purged as a title '
        'tombstone (#429)', () async {
      // The regression that #429 exposed and #459 masked: a slot with a
      // dance but NO text. A pre-fix purge nulled its dance_id, leaving
      // (danceId, text) = (null, null) — which ProgramSlot rejects — so
      // loading ANY program threw. The purge now tombstones the slot's text
      // with the dance's title so it stays valid.
      await dances.create(
        Dance(
          id: 'd1',
          title: 'Doomed Dance',
          deletedAt: DateTime.utc(2026, 1, 1),
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      await repo.create(
        sampleProgram(
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );

      await dances.purgeDeleted(now: DateTime.utc(2026, 4, 1));

      // getById must not throw; the slot survives with the title as caption.
      final loaded = await repo.getById('p1');
      expect(loaded, isNotNull);
      expect(loaded!.slots.single.danceId, isNull);
      expect(loaded.slots.single.text, 'Doomed Dance');

      // listAll builds every program's slots in one loop, so it is the path
      // a single corrupt row historically took down. It must also succeed.
      final all = await repo.listAll();
      expect(all, hasLength(1));
      expect(all.single.slots.single.text, 'Doomed Dance');
    });

    test('a purged-dance program exports to plaintext without corruption '
        '(#459 export coverage)', () async {
      // #459 asked for export coverage of the purge case. The fix keeps the
      // throwing ProgramSlot invariant, so a purged dance-only slot becomes a
      // valid title tombstone (danceId null, text = former title). Re-exporting
      // the affected program must therefore render that caption as an ordinary
      // text slot and never throw — even though the dance itself is now gone
      // (so `titleFor` returns null for it).
      await dances.create(
        Dance(
          id: 'd1',
          title: 'Doomed Dance',
          deletedAt: DateTime.utc(2026, 1, 1),
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      await repo.create(
        sampleProgram(
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
            ProgramSlot(id: 's2', position: 1, text: 'Waltz break'),
          ],
        ),
      );

      await dances.purgeDeleted(now: DateTime.utc(2026, 4, 1));

      final loaded = await repo.getById('p1');
      expect(loaded, isNotNull);

      // The dance is purged, so a real exporter's title lookup misses it.
      final text = programToPlainText(loaded!, titleFor: (_) => null);

      // The program header and the surviving text slot render as usual, and the
      // tombstoned slot renders its preserved caption rather than being dropped
      // or degrading to the unknown-dance placeholder.
      expect(text, contains('Spring Dance 2026'));
      expect(text, contains('Doomed Dance'));
      expect(text, contains('Waltz break'));
      expect(text, isNot(contains('Untitled dance')));
    });

    test('loading tolerates a legacy (null,null) corrupt slot rather than '
        'throwing (#429 belt-and-suspenders)', () async {
      // Simulate a row left corrupt by a build that predates the tombstone
      // fix. The mapper must skip it so it cannot block loading the program.
      await repo.create(
        sampleProgram(
          slots: [ProgramSlot(id: 's-ok', position: 0, text: 'Waltz')],
        ),
      );
      await db.customStatement(
        'INSERT INTO program_slots (id, program_id, position, dance_id, '
        'text, is_alt) VALUES (?, ?, ?, NULL, NULL, 0)',
        ['s-bad', 'p1', 1],
      );

      final loaded = await repo.getById('p1');
      expect(loaded, isNotNull);
      expect(loaded!.slots.map((s) => s.id), ['s-ok']);

      final all = await repo.listAll();
      expect(all.single.slots.map((s) => s.id), ['s-ok']);
    });

    test('returns null for a missing id', () async {
      expect(await repo.getById('nope'), isNull);
    });

    test('round-trips event metadata and per-slot fields', () async {
      await dances.create(
        Dance(
          id: 'd1',
          title: 'Petronella',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      final program = Program(
        id: 'pm',
        title: 'Metadata Night',
        eventDate: DateTime.utc(2026, 3, 15),
        venue: 'Grange Hall',
        band: 'The Fiddleheads',
        caller: 'Alice',
        dancerLevel: 'intermediate',
        slots: [
          ProgramSlot(
            id: 's1',
            position: 0,
            danceId: 'd1',
            guestCaller: 'Bob',
            plannedMinutes: 12,
          ),
        ],
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      await repo.create(program);
      final loaded = await repo.getById('pm');
      expect(loaded, program);
      expect(loaded!.band, 'The Fiddleheads');
      expect(loaded.caller, 'Alice');
      expect(loaded.dancerLevel, 'intermediate');
      expect(loaded.slots.single.guestCaller, 'Bob');
      expect(loaded.slots.single.plannedMinutes, 12);
    });

    test('round-trips the hideAlternates flag', () async {
      final program = sampleProgram(
        slots: [
          ProgramSlot(id: 's1', position: 0, text: 'Primary'),
          ProgramSlot(id: 's2', position: 1, text: 'Alternate', isAlt: true),
        ],
      ).copyWith(hideAlternates: true);
      await repo.create(program);
      final loaded = await repo.getById(program.id);
      expect(loaded!.hideAlternates, isTrue);
      // The flag is a view-only setting: the stored slots are untouched.
      expect(loaded.slots, hasLength(2));
      expect(loaded, program);
    });

    test('hideAlternates defaults to false when unset', () async {
      final program = sampleProgram();
      await repo.create(program);
      final loaded = await repo.getById(program.id);
      expect(loaded!.hideAlternates, isFalse);
    });

    test('excludes soft-deleted programs by default', () async {
      final program = sampleProgram(deletedAt: DateTime.utc(2026, 1, 2));
      await repo.create(program);
      expect(await repo.getById(program.id), isNull);
      expect(await repo.getById(program.id, includeDeleted: true), program);
    });
  });

  group('update', () {
    test('replaces slots wholesale', () async {
      final program = sampleProgram(
        slots: [ProgramSlot(id: 's1', position: 0, text: 'Original')],
      );
      await repo.create(program);
      final updated = program.copyWith(
        slots: [ProgramSlot(id: 's2', position: 0, text: 'Replaced')],
        updatedAt: DateTime.utc(2026, 2, 1),
      );
      await repo.update(updated);
      final loaded = await repo.getById(program.id);
      expect(loaded!.slots.map((s) => s.id), ['s2']);
    });
  });

  group('listAll', () {
    test('orders by title and excludes soft-deleted by default', () async {
      await repo.create(sampleProgram(id: 'p2', title: 'Zesty Night'));
      await repo.create(sampleProgram(id: 'p1', title: 'Autumn Ball'));
      expect((await repo.listAll()).map((p) => p.title), [
        'Autumn Ball',
        'Zesty Night',
      ]);
    });

    test('rehydrates slots correctly for a multi-program mix', () async {
      await dances.create(
        Dance(
          id: 'd1',
          title: 'Chase the Squirrel',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      // p-a: two slots (out-of-order ids to prove position ordering);
      // p-b: no slots; p-c: one slot. Titles chosen so listAll order is a,b,c.
      await repo.create(
        sampleProgram(
          id: 'p-a',
          title: 'Alpha',
          slots: [
            ProgramSlot(id: 'a2', position: 1, text: 'Waltz break'),
            ProgramSlot(id: 'a1', position: 0, danceId: 'd1', isAlt: true),
          ],
        ),
      );
      await repo.create(sampleProgram(id: 'p-b', title: 'Bravo'));
      await repo.create(
        sampleProgram(
          id: 'p-c',
          title: 'Charlie',
          slots: [ProgramSlot(id: 'c1', position: 0, text: 'Closer')],
        ),
      );

      final all = await repo.listAll();
      expect(all.map((p) => p.id), ['p-a', 'p-b', 'p-c']);
      // Batched map keys each program to exactly its own slots, in position
      // order.
      expect(all[0].slots.map((s) => s.id), ['a1', 'a2']);
      expect(all[0].slots.first.danceId, 'd1');
      expect(all[0].slots.first.isAlt, isTrue);
      expect(all[0].slots.last.text, 'Waltz break');
      expect(all[1].slots, isEmpty);
      expect(all[2].slots.map((s) => s.id), ['c1']);
    });

    test('issues a constant number of slot queries regardless of program '
        'count (no N+1)', () async {
      final counter = SlotSelectCounter();
      final countingDb = openCountingTestDatabase(counter);
      addTearDown(countingDb.close);
      final countingRepo = ProgramRepository(countingDb);

      for (var i = 0; i < 5; i++) {
        await countingRepo.create(
          sampleProgram(
            id: 'p$i',
            title: 'Program $i',
            slots: [ProgramSlot(id: 's$i', position: 0, text: 'slot $i')],
          ),
        );
      }

      counter.reset();
      final all = await countingRepo.listAll();
      expect(all, hasLength(5));
      // Batched: a single `program_slots WHERE program_id IN (...)` select,
      // not one per program.
      expect(counter.count, 1);
    });

    test('batched load spans an id chunk boundary (#624)', () async {
      // More than one _idChunkSize (500) worth of programs, each with a slot
      // and provenance, so _slotsForMany/_provenanceForMany must stitch
      // results across chunks rather than exceeding SQLite's isIn() bound
      // variable limit in a single query.
      const total = 501;
      for (var i = 0; i < total; i++) {
        final id = 'p${i.toString().padLeft(4, '0')}';
        await repo.create(
          sampleProgram(
            id: id,
            title: 'Program ${i.toString().padLeft(4, '0')}',
            slots: [ProgramSlot(id: '$id-s1', position: 0, text: 'Welcome')],
          ).copyWith(
            provenance: Provenance(
              source: ProvenanceSource.callersCompanion,
              externalId: 'ext-$id',
              importedAt: DateTime.utc(2026, 1, 1),
            ),
          ),
        );
      }

      final all = await repo.listAll();
      expect(all, hasLength(total));
      // Every program keeps its slot + provenance regardless of which chunk
      // it fell in (a merge bug would drop entries for later chunks).
      expect(all.every((p) => p.slots.length == 1), isTrue);
      expect(all.every((p) => p.provenance?.externalId != null), isTrue);
    });
  });

  group('listIdsAndTitles', () {
    test(
      'returns id+title pairs ordered by title, excluding soft-deleted',
      () async {
        await repo.create(sampleProgram(id: 'p2', title: 'Zesty Night'));
        await repo.create(sampleProgram(id: 'p1', title: 'Autumn Ball'));
        await repo.create(
          sampleProgram(
            id: 'p3',
            title: 'Deleted Program',
            deletedAt: DateTime.utc(2026, 1, 2),
          ),
        );

        final pairs = await repo.listIdsAndTitles();
        expect(pairs, [
          (id: 'p1', title: 'Autumn Ball'),
          (id: 'p2', title: 'Zesty Night'),
        ]);

        final withDeleted = await repo.listIdsAndTitles(includeDeleted: true);
        expect(withDeleted.map((p) => p.title), [
          'Autumn Ball',
          'Deleted Program',
          'Zesty Night',
        ]);
      },
    );

    test('breaks equal-title ties deterministically by id', () async {
      await repo.create(sampleProgram(id: 'p2', title: 'Same Night'));
      await repo.create(sampleProgram(id: 'p1', title: 'Same Night'));
      final pairs = await repo.listIdsAndTitles();
      expect(pairs.map((p) => p.id), ['p1', 'p2']);
    });
  });

  group('soft delete / restore / purge', () {
    test('soft delete then restore clears deletedAt', () async {
      final program = sampleProgram();
      await repo.create(program);
      await repo.softDelete(program.id, at: DateTime.utc(2026, 1, 5));
      expect(
        (await repo.getById(program.id, includeDeleted: true))!.isDeleted,
        isTrue,
      );
      await repo.restore(program.id, at: DateTime.utc(2026, 1, 6));
      expect(await repo.getById(program.id), isNotNull);
    });

    test('purgeDeleted removes programs past retention', () async {
      await repo.create(
        sampleProgram(id: 'old', deletedAt: DateTime.utc(2026, 1, 1)),
      );
      await repo.create(
        sampleProgram(id: 'recent', deletedAt: DateTime.utc(2026, 3, 20)),
      );
      final purged = await repo.purgeDeleted(
        now: DateTime.utc(2026, 4, 1),
        retention: const Duration(days: 30),
      );
      expect(purged, 1);
      expect(await repo.getById('old', includeDeleted: true), isNull);
      expect(await repo.getById('recent', includeDeleted: true), isNotNull);
    });
  });

  group('hardDelete', () {
    test(
      'removes the named programs and their slots, ignoring others',
      () async {
        await dances.create(
          Dance(
            id: 'd1',
            title: 'Chase the Squirrel',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );
        await repo.create(
          sampleProgram(
            id: 'p1',
            slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          ),
        );
        await repo.create(sampleProgram(id: 'p2', title: 'Keep me'));

        await repo.hardDelete(['p1', 'does-not-exist']);

        // p1 is gone even from the include-deleted view (true hard delete)...
        expect(await repo.getById('p1', includeDeleted: true), isNull);
        // ...its slots cascaded away...
        final slotRows = await db
            .customSelect('SELECT COUNT(*) AS n FROM program_slots')
            .getSingle();
        expect(slotRows.read<int>('n'), 0);
        // ...and the unrelated program survives.
        expect(await repo.getById('p2'), isNotNull);
      },
    );

    test('an empty id list is a no-op', () async {
      await repo.create(sampleProgram(id: 'p1'));
      await repo.hardDelete(const []);
      expect(await repo.getById('p1'), isNotNull);
    });

    test('spans an id chunk boundary (#624)', () async {
      // More than one _idChunkSize (500) worth of programs, so the delete
      // must chunk its isIn() batch rather than exceeding SQLite's bound
      // variable limit in a single query.
      const total = 501;
      final ids = [
        for (var i = 0; i < total; i++) 'p${i.toString().padLeft(4, '0')}',
      ];
      for (final id in ids) {
        await repo.create(sampleProgram(id: id, title: id));
      }

      await repo.hardDelete(ids);

      for (final id in ids) {
        expect(await repo.getById(id, includeDeleted: true), isNull);
      }
    });
  });

  group('lastCalledByDance', () {
    Future<void> makeDance(String id) => dances.create(
      Dance(
        id: id,
        title: 'Dance $id',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );

    test('is empty when no slot has been performed', () async {
      await makeDance('d1');
      await repo.create(
        sampleProgram(
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      expect(await repo.lastCalledByDance(), isEmpty);
    });

    test('returns the most recent performedAt across programs', () async {
      await makeDance('d1');
      await repo.create(
        sampleProgram(
          id: 'p1',
          slots: [
            ProgramSlot(
              id: 's1',
              position: 0,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        ),
      );
      await repo.create(
        sampleProgram(
          id: 'p2',
          slots: [
            ProgramSlot(
              id: 's2',
              position: 0,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 3, 1),
            ),
          ],
        ),
      );
      expect(await repo.lastCalledByDance(), {'d1': DateTime.utc(2026, 3, 1)});
    });

    test('ignores slots on soft-deleted programs', () async {
      await makeDance('d1');
      await repo.create(
        sampleProgram(
          slots: [
            ProgramSlot(
              id: 's1',
              position: 0,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        ),
      );
      await repo.softDelete('p1', at: DateTime.utc(2026, 2, 1));
      expect(await repo.lastCalledByDance(), isEmpty);
    });

    test('ignores text-only (dance-less) slots', () async {
      await repo.create(
        sampleProgram(
          slots: [
            ProgramSlot(
              id: 's1',
              position: 0,
              text: 'Waltz break',
              performedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        ),
      );
      expect(await repo.lastCalledByDance(), isEmpty);
    });
  });

  group('countByDance', () {
    Future<void> makeDance(String id) => dances.create(
      Dance(
        id: id,
        title: 'Dance $id',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );

    test('is empty when no dance has ever been called', () async {
      expect(await repo.countByDance(), isEmpty);
    });

    test('counts every occurrence by default, incl. repeats within a program, '
        'and tallies performed separately', () async {
      await makeDance('d1');
      await makeDance('d2');
      await repo.create(
        sampleProgram(
          id: 'p1',
          slots: [
            // d1 appears twice in one program -> counts twice.
            ProgramSlot(
              id: 's1',
              position: 0,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 1, 1),
            ),
            ProgramSlot(id: 's2', position: 1, danceId: 'd1'),
            ProgramSlot(id: 's3', position: 2, danceId: 'd2'),
          ],
        ),
      );
      await repo.create(
        sampleProgram(
          id: 'p2',
          slots: [
            ProgramSlot(
              id: 's4',
              position: 0,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 2, 1),
            ),
          ],
        ),
      );

      final counts = await repo.countByDance();
      // d1: 3 occurrences total, 2 marked performed. d2: 1 total, 0 performed.
      expect(counts['d1'], const DanceCallCounts(all: 3, performed: 2));
      expect(counts['d2'], const DanceCallCounts(all: 1, performed: 0));
    });

    test(
      'parity: counts equal the detail calling-history length in each scope '
      '(same per-slot source of truth, so card & detail never drift)',
      () async {
        await makeDance('d1');
        // Guardrail fixture: d1 appears TWICE in one non-deleted program and
        // ONCE in another; a single occurrence is performed.
        await repo.create(
          sampleProgram(
            id: 'p1',
            slots: [
              ProgramSlot(
                id: 's1',
                position: 0,
                danceId: 'd1',
                performedAt: DateTime.utc(2026, 1, 1),
              ),
              ProgramSlot(id: 's2', position: 1, danceId: 'd1'),
            ],
          ),
        );
        await repo.create(
          sampleProgram(
            id: 'p2',
            slots: [ProgramSlot(id: 's3', position: 0, danceId: 'd1')],
          ),
        );

        final counts = (await repo.countByDance())['d1'];
        final historyAll = await repo.callingHistoryForDance('d1');
        final historyPerformed = await repo.callingHistoryForDance(
          'd1',
          performedOnly: true,
        );
        // The chip's default N must equal the detail history's record count...
        expect(counts!.all, historyAll.length);
        expect(counts.all, 3);
        // ...and the performed-scope N must equal the performed-only history.
        expect(counts.performed, historyPerformed.length);
        expect(counts.performed, 1);
      },
    );

    test('ignores slots on soft-deleted programs', () async {
      await makeDance('d1');
      await repo.create(
        sampleProgram(
          slots: [
            ProgramSlot(
              id: 's1',
              position: 0,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        ),
      );
      await repo.softDelete('p1', at: DateTime.utc(2026, 2, 1));
      expect(await repo.countByDance(), isEmpty);
    });

    test('ignores text-only (dance-less) slots', () async {
      await repo.create(
        sampleProgram(
          slots: [
            ProgramSlot(
              id: 's1',
              position: 0,
              text: 'Waltz break',
              performedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        ),
      );
      expect(await repo.countByDance(), isEmpty);
    });
  });

  group('callingHistoryForDance', () {
    Future<void> makeDance(String id) => dances.create(
      Dance(
        id: id,
        title: 'Dance $id',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );

    test('is empty when the dance is in no program', () async {
      await makeDance('d1');
      await repo.create(sampleProgram());
      expect(await repo.callingHistoryForDance('d1'), isEmpty);
    });

    test('by default includes a program with a non-performed slot', () async {
      await makeDance('d1');
      await repo.create(
        sampleProgram(
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      final history = await repo.callingHistoryForDance('d1');
      expect(history, hasLength(1));
      expect(history.single.programId, 'p1');
      expect(history.single.slotId, 's1');
      expect(history.single.performedAt, isNull);
    });

    test(
      'performedOnly:true restricts to slots that were actually called',
      () async {
        await makeDance('d1');
        await repo.create(
          sampleProgram(
            slots: [
              ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
              ProgramSlot(
                id: 's2',
                position: 1,
                danceId: 'd1',
                performedAt: DateTime.utc(2026, 3, 1),
              ),
            ],
          ),
        );
        final defaulted = await repo.callingHistoryForDance('d1');
        expect(defaulted, hasLength(2));
        final performed = await repo.callingHistoryForDance(
          'd1',
          performedOnly: true,
        );
        expect(performed, hasLength(1));
        expect(performed.single.slotId, 's2');
        expect(performed.single.performedAt, DateTime.utc(2026, 3, 1));
      },
    );

    test('returns programs most-recent first, with metadata', () async {
      await makeDance('d1');
      await repo.create(
        Program(
          id: 'p1',
          title: 'Autumn Ball',
          eventDate: DateTime.utc(2026, 1, 10),
          venue: 'Grange Hall',
          slots: [
            ProgramSlot(
              id: 's1',
              position: 0,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      await repo.create(
        Program(
          id: 'p2',
          title: 'Spring Fling',
          eventDate: DateTime.utc(2026, 3, 20),
          venue: 'Town Hall',
          slots: [
            ProgramSlot(
              id: 's2',
              position: 0,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 3, 1),
            ),
          ],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );

      final history = await repo.callingHistoryForDance('d1');
      expect(history.map((r) => r.programId), ['p2', 'p1']);
      expect(history.first.programTitle, 'Spring Fling');
      expect(history.first.performedAt, DateTime.utc(2026, 3, 1));
      expect(history.first.eventDate, DateTime.utc(2026, 3, 20));
      expect(history.first.venue, 'Town Hall');
      expect(history.last.programId, 'p1');
    });

    test(
      'carries the program venueId (or null) for label resolution',
      () async {
        await makeDance('d1');
        final venues = VenueRepository(db);
        await venues.upsert(Venue(id: 'grange-hall', name: 'Grange Hall'));
        // p-linked: linked to a saved venue by venueId.
        await repo.create(
          Program(
            id: 'p-linked',
            title: 'Autumn Ball',
            eventDate: DateTime.utc(2026, 1, 10),
            venueId: 'grange-hall',
            slots: [ProgramSlot(id: 's-linked', position: 0, danceId: 'd1')],
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );
        // p-freetext: only free-text venue, no link → venueId is null.
        await repo.create(
          Program(
            id: 'p-freetext',
            title: 'Spring Fling',
            eventDate: DateTime.utc(2026, 3, 20),
            venue: 'Town Hall',
            slots: [ProgramSlot(id: 's-freetext', position: 0, danceId: 'd1')],
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );

        final history = await repo.callingHistoryForDance('d1');
        final byId = {for (final r in history) r.programId: r};
        expect(byId['p-linked']!.venueId, 'grange-hall');
        expect(byId['p-linked']!.venue, isNull);
        expect(byId['p-freetext']!.venueId, isNull);
        expect(byId['p-freetext']!.venue, 'Town Hall');
      },
    );

    test('orders by effective date (eventDate / updatedAt) when performedAt is '
        'null', () async {
      await makeDance('d1');
      // p-early: no performedAt, older event date.
      await repo.create(
        Program(
          id: 'p-early',
          title: 'Early',
          eventDate: DateTime.utc(2026, 1, 1),
          slots: [ProgramSlot(id: 's-early', position: 0, danceId: 'd1')],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      // p-late: no performedAt, newer event date.
      await repo.create(
        Program(
          id: 'p-late',
          title: 'Late',
          eventDate: DateTime.utc(2026, 6, 1),
          slots: [ProgramSlot(id: 's-late', position: 0, danceId: 'd1')],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      // p-updated: no performedAt, no event date — falls back to updatedAt,
      // the most recent of all, so it should sort first.
      await repo.create(
        Program(
          id: 'p-updated',
          title: 'Recently updated',
          slots: [ProgramSlot(id: 's-updated', position: 0, danceId: 'd1')],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026, 12, 1),
        ),
      );

      final history = await repo.callingHistoryForDance('d1');
      expect(history.map((r) => r.programId), [
        'p-updated',
        'p-late',
        'p-early',
      ]);
      expect(history.map((r) => r.effectiveDate), [
        DateTime.utc(2026, 12, 1),
        DateTime.utc(2026, 6, 1),
        DateTime.utc(2026, 1, 1),
      ]);
    });

    test('excludes slots on soft-deleted programs', () async {
      await makeDance('d1');
      await repo.create(
        sampleProgram(
          slots: [
            ProgramSlot(
              id: 's1',
              position: 0,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        ),
      );
      await repo.softDelete('p1', at: DateTime.utc(2026, 2, 1));
      expect(await repo.callingHistoryForDance('d1'), isEmpty);
    });

    test('returns every program the dance appears in', () async {
      await makeDance('d1');
      for (final (i, date) in [
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 2, 1),
        DateTime.utc(2026, 3, 1),
      ].indexed) {
        await repo.create(
          sampleProgram(
            id: 'p$i',
            slots: [
              ProgramSlot(
                id: 's$i',
                position: 0,
                danceId: 'd1',
                performedAt: date,
              ),
            ],
          ),
        );
      }
      final history = await repo.callingHistoryForDance('d1');
      expect(history, hasLength(3));
      expect(history.map((r) => r.performedAt), [
        DateTime.utc(2026, 3, 1),
        DateTime.utc(2026, 2, 1),
        DateTime.utc(2026, 1, 1),
      ]);
    });

    test('ignores slots referencing a different dance', () async {
      await makeDance('d1');
      await makeDance('d2');
      await repo.create(
        sampleProgram(
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd2')],
        ),
      );
      expect(await repo.callingHistoryForDance('d1'), isEmpty);
    });
  });

  group('halfCallingStatsForDance', () {
    Future<void> makeDance(String id) => dances.create(
      Dance(
        id: id,
        title: 'Dance $id',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );

    ProgramSlot breakSlot(int position) => ProgramSlot(
      id: 'b$position',
      position: position,
      text: Program.breakSlotText,
    );

    test('is empty when the dance is in no program', () async {
      await makeDance('d1');
      await repo.create(sampleProgram());
      expect(await repo.halfCallingStatsForDance('d1'), HalfCallingStats.empty);
    });

    test('derives halves and positions end-to-end for one program', () async {
      await makeDance('d1');
      await makeDance('d2');
      await makeDance('d3');
      await repo.create(
        sampleProgram(
          slots: [
            ProgramSlot(id: 's0', position: 0, danceId: 'd1'),
            ProgramSlot(id: 's1', position: 1, danceId: 'd2'),
            breakSlot(2),
            ProgramSlot(id: 's3', position: 3, danceId: 'd3'),
            ProgramSlot(id: 's4', position: 4, danceId: 'd1'),
          ],
        ),
      );
      final stats = await repo.halfCallingStatsForDance('d1');
      expect(stats.firstHalfCount, 1);
      expect(stats.secondHalfCount, 1);
      expect(stats.openedFirstHalfCount, 1); // d1 opens the first half
      expect(stats.closedSecondHalfCount, 1); // d1 closes the second half
    });

    test('aggregates across multiple programs', () async {
      await makeDance('d1');
      await makeDance('d2');
      await repo.create(
        sampleProgram(
          id: 'p1',
          slots: [
            ProgramSlot(id: 'a0', position: 0, danceId: 'd1'),
            breakSlot(1),
            ProgramSlot(id: 'a2', position: 2, danceId: 'd1'),
          ],
        ),
      );
      await repo.create(
        sampleProgram(
          id: 'p2',
          slots: [
            ProgramSlot(id: 'c0', position: 0, danceId: 'd2'),
            ProgramSlot(id: 'c1', position: 1, danceId: 'd1'),
            ProgramSlot(
              id: 'c2break',
              position: 2,
              text: Program.breakSlotText,
            ),
            ProgramSlot(id: 'c3', position: 3, danceId: 'd2'),
          ],
        ),
      );
      final stats = await repo.halfCallingStatsForDance('d1');
      expect(stats.firstHalfCount, 2);
      expect(stats.secondHalfCount, 1);
    });

    test('excludes soft-deleted programs', () async {
      await makeDance('d1');
      await repo.create(
        sampleProgram(
          id: 'p1',
          slots: [
            ProgramSlot(id: 's0', position: 0, danceId: 'd1'),
            breakSlot(1),
            ProgramSlot(id: 's2', position: 2, danceId: 'd1'),
          ],
        ),
      );
      await repo.softDelete('p1', at: DateTime.utc(2026, 6, 1));
      expect(await repo.halfCallingStatsForDance('d1'), HalfCallingStats.empty);
    });

    test('performedOnly counts only performed occurrences', () async {
      await makeDance('d1');
      await makeDance('d2');
      await repo.create(
        sampleProgram(
          slots: [
            ProgramSlot(
              id: 's0',
              position: 0,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 3, 1),
            ),
            breakSlot(1),
            ProgramSlot(id: 's2', position: 2, danceId: 'd2'),
            ProgramSlot(id: 's3', position: 3, danceId: 'd1'),
          ],
        ),
      );
      final all = await repo.halfCallingStatsForDance('d1');
      expect(all.firstHalfCount, 1);
      expect(all.secondHalfCount, 1);

      final performed = await repo.halfCallingStatsForDance(
        'd1',
        performedOnly: true,
      );
      expect(performed.firstHalfCount, 1);
      expect(performed.secondHalfCount, 0);
    });

    test('a break-less program contributes nothing', () async {
      await makeDance('d1');
      await repo.create(
        sampleProgram(
          slots: [
            ProgramSlot(id: 's0', position: 0, danceId: 'd1'),
            ProgramSlot(id: 's1', position: 1, danceId: 'd1'),
          ],
        ),
      );
      expect(await repo.halfCallingStatsForDance('d1'), HalfCallingStats.empty);
    });
  });

  group('duplicate', () {
    test('mints fresh ids, resets to draft, and persists the copy', () async {
      await dances.create(
        Dance(
          id: 'd1',
          title: 'Petronella',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await repo.create(
        sampleProgram(
          id: 'p1',
          title: 'Spring Dance 2026',
          slots: [
            ProgramSlot(
              id: 's1',
              position: 0,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 1, 1),
            ),
            ProgramSlot(id: 's2', position: 1, text: 'Waltz', isAlt: true),
          ],
        ),
      );
      // Mark performed so we can assert history is cleared on the copy.
      final performed = (await repo.getById(
        'p1',
      ))!.copyWith(status: ProgramStatus.performed);
      await repo.update(performed);

      var n = 0;
      final now = DateTime.utc(2026, 6, 1);
      final copy = await repo.duplicate(
        id: 'p1',
        newId: 'p2',
        newSlotId: () => 'ns${n++}',
        now: now,
        newTitle: 'Spring Dance 2026 (copy)',
      );

      expect(copy.id, 'p2');
      expect(copy.title, 'Spring Dance 2026 (copy)');
      expect(copy.status, ProgramStatus.draft);
      expect(copy.venue, 'Grange Hall');
      expect(copy.slots.map((s) => s.id), ['ns0', 'ns1']);
      expect(copy.slots[0].performedAt, isNull);
      expect(copy.slots[1].isAlt, isTrue);

      // Persisted and independent from the original.
      final reloaded = await repo.getById('p2');
      expect(reloaded, isNotNull);
      expect(reloaded!.slots, hasLength(2));
      expect(await repo.getById('p1'), isNotNull);
    });

    test('throws for an unknown id', () async {
      expect(
        () => repo.duplicate(
          id: 'missing',
          newId: 'p2',
          newSlotId: () => 's',
          now: DateTime.utc(2026, 6, 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('provenance', () {
    Provenance ccProvenance({String externalId = 'set-7'}) => Provenance(
      source: ProvenanceSource.callersCompanion,
      externalId: externalId,
      importedAt: DateTime.utc(2026, 1, 1),
      sourceVersion: 'cc-usr-1',
    );

    test('round-trips provenance on create and read', () async {
      final program = sampleProgram().copyWith(provenance: ccProvenance());
      await repo.create(program);

      final read = await repo.getById(program.id);
      expect(read, isNotNull);
      final prov = read!.provenance;
      expect(prov, isNotNull);
      expect(prov!.source, ProvenanceSource.callersCompanion);
      expect(prov.externalId, 'set-7');
      expect(prov.importedAt, DateTime.utc(2026, 1, 1));
      expect(prov.sourceVersion, 'cc-usr-1');
    });

    test('listAll rehydrates provenance for a mix of provenance and null '
        'programs (batched map keys correctly)', () async {
      await repo.create(
        sampleProgram(
          id: 'a-prog',
          title: 'Alpha',
        ).copyWith(provenance: ccProvenance(externalId: 'set-a')),
      );
      await repo.create(sampleProgram(id: 'b-prog', title: 'Bravo'));
      await repo.create(
        sampleProgram(
          id: 'c-prog',
          title: 'Charlie',
        ).copyWith(provenance: ccProvenance(externalId: 'set-c')),
      );

      final all = await repo.listAll();
      final byId = {for (final p in all) p.id: p};

      expect(byId['a-prog']!.provenance!.externalId, 'set-a');
      expect(byId['b-prog']!.provenance, isNull);
      expect(byId['c-prog']!.provenance!.externalId, 'set-c');
    });

    test('a program with no provenance reads back null', () async {
      await repo.create(sampleProgram());
      final read = await repo.getById('p1');
      expect(read!.provenance, isNull);
    });

    test('update can clear provenance (row is removed)', () async {
      final program = sampleProgram().copyWith(provenance: ccProvenance());
      await repo.create(program);
      await repo.update(program.copyWith(clearProvenance: true));

      expect((await repo.getById('p1'))!.provenance, isNull);
      expect(
        await repo.externalIdToProgramId(ProvenanceSource.callersCompanion),
        isEmpty,
      );
    });

    test(
      'externalIdToProgramId maps only non-null external ids for the source',
      () async {
        await repo.create(
          sampleProgram(id: 'p1').copyWith(provenance: ccProvenance()),
        );
        await repo.create(
          sampleProgram(
            id: 'p2',
          ).copyWith(provenance: ccProvenance(externalId: 'set-9')),
        );
        // Null-provenance (user-created) program: never dedupes.
        await repo.create(sampleProgram(id: 'p3'));

        final map = await repo.externalIdToProgramId(
          ProvenanceSource.callersCompanion,
        );
        expect(map, {'set-7': 'p1', 'set-9': 'p2'});
      },
    );

    test('externalIdToProgramId includes soft-deleted programs', () async {
      await repo.create(
        sampleProgram(id: 'p1').copyWith(provenance: ccProvenance()),
      );
      await repo.softDelete('p1', at: DateTime.utc(2026, 2, 1));

      final map = await repo.externalIdToProgramId(
        ProvenanceSource.callersCompanion,
      );
      expect(map, {'set-7': 'p1'});
    });

    test('duplicate drops provenance', () async {
      await repo.create(
        sampleProgram(id: 'p1').copyWith(provenance: ccProvenance()),
      );
      final copy = await repo.duplicate(
        id: 'p1',
        newId: 'p2',
        newSlotId: () => 's',
        now: DateTime.utc(2026, 6, 1),
      );
      expect(copy.provenance, isNull);
      expect((await repo.getById('p2'))!.provenance, isNull);
    });
  });

  group('auto-stamp performed on status transition (#356)', () {
    Future<void> makeDance(String id) => dances.create(
      Dance(
        id: id,
        title: 'Dance $id',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );

    Program performedProgram({
      String id = 'p1',
      DateTime? eventDate,
      List<ProgramSlot> slots = const [],
      DateTime? updatedAt,
    }) {
      final now = DateTime.utc(2026, 6, 1);
      return Program(
        id: id,
        title: 'Set Night',
        eventDate: eventDate,
        slots: slots,
        status: ProgramStatus.performed,
        createdAt: now,
        updatedAt: updatedAt ?? now,
      );
    }

    test('create with status performed stamps dance-linked slots with '
        'eventDate', () async {
      await makeDance('d1');
      await repo.create(
        performedProgram(
          eventDate: DateTime.utc(2026, 3, 15),
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
            ProgramSlot(id: 's2', position: 1, text: 'Waltz break'),
          ],
        ),
      );
      final stored = (await repo.getById('p1'))!;
      expect(stored.slots[0].performedAt, DateTime.utc(2026, 3, 15));
      // Free-text slot is never stamped.
      expect(stored.slots[1].performedAt, isNull);
    });

    test('falls back to updatedAt when the program has no eventDate', () async {
      await makeDance('d1');
      final updatedAt = DateTime.utc(2026, 7, 20, 18, 30);
      await repo.create(
        performedProgram(
          updatedAt: updatedAt,
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      final stored = (await repo.getById('p1'))!;
      expect(stored.slots.single.performedAt, updatedAt);
    });

    test('updating from draft to performed stamps the slots', () async {
      await makeDance('d1');
      final draft = performedProgram(
        eventDate: DateTime.utc(2026, 3, 15),
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      ).copyWith(status: ProgramStatus.draft);
      await repo.create(draft);
      expect((await repo.getById('p1'))!.slots.single.performedAt, isNull);

      await repo.update(draft.copyWith(status: ProgramStatus.performed));
      expect(
        (await repo.getById('p1'))!.slots.single.performedAt,
        DateTime.utc(2026, 3, 15),
      );
    });

    test('does not overwrite a manually-set performedAt', () async {
      await makeDance('d1');
      final manual = DateTime.utc(2025, 1, 1);
      await repo.create(
        performedProgram(
          eventDate: DateTime.utc(2026, 3, 15),
          slots: [
            ProgramSlot(
              id: 's1',
              position: 0,
              danceId: 'd1',
              performedAt: manual,
            ),
          ],
        ),
      );
      expect((await repo.getById('p1'))!.slots.single.performedAt, manual);
    });

    test('does not re-stamp a slot cleared while already performed', () async {
      await makeDance('d1');
      // Transition to performed stamps the slot.
      await repo.create(
        performedProgram(
          eventDate: DateTime.utc(2026, 3, 15),
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      final stored = (await repo.getById('p1'))!;
      expect(stored.slots.single.performedAt, isNotNull);

      // User manually clears the stamp while status stays performed; saving
      // must NOT re-stamp because there is no non-performed -> performed
      // transition.
      final cleared = stored.copyWith(
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      );
      await repo.update(cleared);
      expect((await repo.getById('p1'))!.slots.single.performedAt, isNull);
    });

    test('reverting away from performed does not un-stamp', () async {
      await makeDance('d1');
      await repo.create(
        performedProgram(
          eventDate: DateTime.utc(2026, 3, 15),
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      final stored = (await repo.getById('p1'))!;
      await repo.update(stored.copyWith(status: ProgramStatus.finalized));
      expect(
        (await repo.getById('p1'))!.slots.single.performedAt,
        DateTime.utc(2026, 3, 15),
      );
    });

    test('auto-stamped slots surface in performed-only calling history and '
        'half stats (composes with #378)', () async {
      await makeDance('d1');
      await makeDance('d2');
      await repo.create(
        performedProgram(
          eventDate: DateTime.utc(2026, 3, 15),
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
            ProgramSlot(id: 'brk', position: 1, text: Program.breakSlotText),
            ProgramSlot(id: 's2', position: 2, danceId: 'd2'),
          ],
        ),
      );
      final performed = await repo.callingHistoryForDance(
        'd1',
        performedOnly: true,
      );
      expect(performed, hasLength(1));
      expect(performed.single.performedAt, DateTime.utc(2026, 3, 15));

      final stats = await repo.halfCallingStatsForDance(
        'd1',
        performedOnly: true,
      );
      expect(stats.firstHalfCount, 1);
    });
  });

  group('venueId write-time integrity', () {
    late VenueRepository venues;

    setUp(() => venues = VenueRepository(db));

    test(
      'accepts a program whose venueId references an existing venue',
      () async {
        await venues.upsert(Venue(id: 'v1', name: 'Guiding Star Grange'));
        final program = sampleProgram().copyWith(venueId: 'v1');

        await repo.create(program);
        expect((await repo.getById('p1'))!.venueId, 'v1');
      },
    );

    test('rejects a program whose venueId references no venue', () async {
      final program = sampleProgram().copyWith(venueId: 'ghost');

      await expectLater(
        repo.create(program),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('ghost'),
          ),
        ),
      );
      // The rejected write left nothing behind (the transaction rolled back).
      expect(await repo.getById('p1'), isNull);
    });

    test(
      'rejects an update that repoints venueId at a missing venue',
      () async {
        await venues.upsert(Venue(id: 'v1', name: 'Guiding Star Grange'));
        await repo.create(sampleProgram().copyWith(venueId: 'v1'));

        final stored = await repo.getById('p1');
        await expectLater(
          repo.update(stored!.copyWith(venueId: 'gone')),
          throwsA(isA<StateError>()),
        );
        // The original link is intact — the failed update rolled back.
        expect((await repo.getById('p1'))!.venueId, 'v1');
      },
    );

    test('allows clearing venueId back to null', () async {
      await venues.upsert(Venue(id: 'v1', name: 'Guiding Star Grange'));
      await repo.create(sampleProgram().copyWith(venueId: 'v1'));

      final stored = await repo.getById('p1');
      await repo.update(stored!.copyWith(clearVenueId: true));
      expect((await repo.getById('p1'))!.venueId, isNull);
    });
  });

  group('callerFilter (host-caller scoping, #583)', () {
    Future<void> makeDance(String id) => dances.create(
      Dance(
        id: id,
        title: 'Dance $id',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );

    // A fixture spanning several host callers plus a null-caller program, each
    // containing dance d1 once, with performed/unperformed slots so the count
    // and history agree under any combination of gates.
    Future<void> seed() async {
      await makeDance('d1');
      // Alice: one performed occurrence.
      await repo.create(
        sampleProgram(
          id: 'p-alice',
          caller: 'Alice',
          slots: [
            ProgramSlot(
              id: 's-a',
              position: 0,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 3, 1),
            ),
          ],
        ),
      );
      // Alice again, but written with surrounding whitespace + different case,
      // and NOT performed — exercises trim + case-insensitive matching.
      await repo.create(
        sampleProgram(
          id: 'p-alice2',
          caller: '  alice ',
          slots: [ProgramSlot(id: 's-a2', position: 0, danceId: 'd1')],
        ),
      );
      // Bob: a different caller, performed — must be excluded by an Alice filter.
      await repo.create(
        sampleProgram(
          id: 'p-bob',
          caller: 'Bob',
          slots: [
            ProgramSlot(
              id: 's-b',
              position: 0,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 4, 1),
            ),
          ],
        ),
      );
      // A program with no caller at all — included when a filter is active,
      // treated as belonging to the default caller (#850 supersedes the #583
      // exclusion of unattributed programs).
      await repo.create(
        sampleProgram(
          id: 'p-null',
          slots: [
            ProgramSlot(
              id: 's-n',
              position: 0,
              danceId: 'd1',
              performedAt: DateTime.utc(2026, 5, 1),
            ),
          ],
        ),
      );
    }

    test('null/blank filter tracks all callers (unchanged behavior)', () async {
      await seed();
      for (final filter in [null, '', '   ']) {
        expect(
          await repo.callingHistoryForDance('d1', callerFilter: filter),
          hasLength(4),
          reason: 'filter ${filter == null ? 'null' : '"$filter"'}',
        );
        expect(
          (await repo.countByDance(
            callerFilter: filter,
          ))['d1']!.countFor(false),
          4,
        );
      }
    });

    test('scopes history/counts to the matching host caller', () async {
      await seed();
      final history = await repo.callingHistoryForDance(
        'd1',
        callerFilter: 'Alice',
      );
      expect(
        history.map((r) => r.programId),
        unorderedEquals(['p-alice', 'p-alice2', 'p-null']),
        reason:
            'Bob must be excluded; null-caller program must be included (#850)',
      );
    });

    test('matches trim + case-insensitively', () async {
      await seed();
      // A wildly different case/spacing of the same name still matches both
      // Alice programs (one stored "Alice", one stored "  alice ") plus the
      // null-caller program (treated as the user's own; #850).
      final history = await repo.callingHistoryForDance(
        'd1',
        callerFilter: '  ALICE  ',
      );
      expect(history, hasLength(3));
    });

    test('count and history agree under the filter (lockstep)', () async {
      await seed();
      for (final performedOnly in [false, true]) {
        final history = await repo.callingHistoryForDance(
          'd1',
          performedOnly: performedOnly,
          callerFilter: 'Alice',
        );
        final counts = await repo.countByDance(callerFilter: 'Alice');
        expect(
          counts['d1']!.countFor(performedOnly),
          history.length,
          reason: 'performedOnly=$performedOnly',
        );
      }
    });

    test('AND-combines with performedOnly', () async {
      await seed();
      // Alice has 2 occurrences (1 performed, 1 not); the null-caller program
      // is also performed. The performed gate on top of the caller gate (#850)
      // leaves the performed Alice slot and the null-caller slot.
      final history = await repo.callingHistoryForDance(
        'd1',
        performedOnly: true,
        callerFilter: 'Alice',
      );
      // Sort is COALESCE(performed_at, ...) DESC: p-null (2026-05-01) before
      // p-alice (2026-03-01).
      expect(history.map((r) => r.programId), ['p-null', 'p-alice']);
      expect(
        (await repo.countByDance(callerFilter: 'Alice'))['d1']!.countFor(true),
        2,
      );
    });

    test('lastCalledByDance honors the filter', () async {
      await seed();
      // Bob's date (2026-04-01) is excluded (different caller). The null-caller
      // program (2026-05-01) is included (#850) and is the latest performed slot.
      expect(await repo.lastCalledByDance(callerFilter: 'Alice'), {
        'd1': DateTime.utc(2026, 5, 1),
      });
    });

    test('halfCallingStatsForDance honors the filter', () async {
      await seed();
      // A non-matching caller filters every contributing program out, so the
      // id-selection query returns nothing and the stats are empty — proving
      // the filter reaches this query too.
      expect(
        await repo.halfCallingStatsForDance('d1', callerFilter: 'Nobody'),
        HalfCallingStats.empty,
      );
      // Scoping to Alice never yields more half-attributed occurrences than the
      // unfiltered stats.
      final all = await repo.halfCallingStatsForDance('d1');
      final scoped = await repo.halfCallingStatsForDance(
        'd1',
        callerFilter: 'Alice',
      );
      final allTotal = all.firstHalfCount + all.secondHalfCount;
      final scopedTotal = scoped.firstHalfCount + scoped.secondHalfCount;
      expect(scopedTotal, lessThanOrEqualTo(allTotal));
    });

    test(
      'null and blank callers are included when a filter is active (#850)',
      () async {
        await seed(); // provides p-null (NULL caller, performed 2026-05-01)
        // Add a program with an explicitly blank caller (cleared after being set).
        await repo.create(
          sampleProgram(
            id: 'p-blank',
            caller: '',
            slots: [
              ProgramSlot(
                id: 's-bl',
                position: 0,
                danceId: 'd1',
                performedAt: DateTime.utc(2026, 6, 1),
              ),
            ],
          ),
        );

        final history = await repo.callingHistoryForDance(
          'd1',
          callerFilter: 'Alice',
        );
        // Exact set: Alice (p-alice, p-alice2), null-caller (p-null), and
        // blank-caller (p-blank). Bob must not appear — guard against
        // over-correction.
        expect(
          history.map((r) => r.programId),
          unorderedEquals(['p-alice', 'p-alice2', 'p-null', 'p-blank']),
        );
        // Count must match exactly: 4.
        final counts = await repo.countByDance(callerFilter: 'Alice');
        expect(counts['d1']!.countFor(false), 4);
        // lastCalledByDance must also include the blank-caller program:
        // p-blank (2026-06-01) is the latest performed slot in the set.
        expect(
          await repo.lastCalledByDance(callerFilter: 'Alice'),
          {'d1': DateTime.utc(2026, 6, 1)},
          reason:
              'blank-caller program must appear in lastCalledByDance (#850)',
        );
      },
    );

    test(
      'CalledFilter search uses caller, performed, and deleted-program scope',
      () async {
        for (final id in ['d1', 'd2', 'd3', 'd4', 'd5']) {
          await makeDance(id);
        }
        await repo.create(
          sampleProgram(
            id: 'p-d1',
            caller: 'Alice',
            slots: [
              ProgramSlot(
                id: 's-d1',
                position: 0,
                danceId: 'd1',
                performedAt: DateTime.utc(2026, 3, 1),
              ),
            ],
          ),
        );
        await repo.create(
          sampleProgram(
            id: 'p-d2',
            caller: 'Alice',
            slots: [ProgramSlot(id: 's-d2', position: 0, danceId: 'd2')],
          ),
        );
        await repo.create(
          sampleProgram(
            id: 'p-d3-deleted',
            caller: 'Alice',
            deletedAt: DateTime.utc(2026, 4, 1),
            slots: [
              ProgramSlot(
                id: 's-d3',
                position: 0,
                danceId: 'd3',
                performedAt: DateTime.utc(2026, 3, 1),
              ),
            ],
          ),
        );
        await repo.create(
          sampleProgram(
            id: 'p-d4-blank',
            caller: '',
            slots: [
              ProgramSlot(
                id: 's-d4-1',
                position: 0,
                danceId: 'd4',
                performedAt: DateTime.utc(2026, 3, 1),
              ),
              ProgramSlot(
                id: 's-d4-2',
                position: 1,
                danceId: 'd4',
                performedAt: DateTime.utc(2026, 3, 2),
              ),
            ],
          ),
        );
        await repo.create(
          sampleProgram(
            id: 'p-d5-bob',
            caller: 'Bob',
            slots: [
              ProgramSlot(
                id: 's-d5',
                position: 0,
                danceId: 'd5',
                performedAt: DateTime.utc(2026, 3, 1),
              ),
            ],
          ),
        );

        expect(
          await dances.search(
            const CalledFilter(
              called: true,
              callerFilter: ' alice ',
              performedOnly: true,
            ),
          ),
          unorderedEquals(['d1', 'd4']),
        );
        expect(
          await dances.search(
            const CalledFilter(
              called: false,
              callerFilter: 'Alice',
              performedOnly: true,
            ),
          ),
          unorderedEquals(['d2', 'd3', 'd5']),
        );
        expect(
          await dances.search(
            const CalledFilter(called: true, callerFilter: 'Bob'),
          ),
          unorderedEquals(['d4', 'd5']),
        );
      },
    );
  });
}
