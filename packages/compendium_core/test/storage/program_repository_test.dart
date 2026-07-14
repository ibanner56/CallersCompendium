import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

Program sampleProgram({
  String id = 'p1',
  String title = 'Spring Dance 2026',
  List<ProgramSlot> slots = const [],
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
}
