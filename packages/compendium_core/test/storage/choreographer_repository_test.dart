import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  late CompendiumDatabase db;
  late ChoreographerRepository repo;
  late DanceRepository dances;

  setUp(() {
    db = openTestDatabase();
    repo = ChoreographerRepository(db);
    dances = DanceRepository(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  test('round-trips a choreographer', () async {
    final c = Choreographer(
      id: 'c1',
      name: 'Bob Isaacs',
      website: 'https://example.com',
      notes: 'prolific',
    );
    // ignore: unused_result
    await repo.upsert(c);
    expect(await repo.getById('c1'), c);
  });

  test('round-trips contact fields (email/location/deceased)', () async {
    final c = Choreographer(
      id: 'c1',
      name: 'Cary Ravitz',
      email: 'cary@example.com',
      location: 'Lexington, KY',
      deceased: true,
    );
    // ignore: unused_result
    await repo.upsert(c);
    final read = await repo.getById('c1');
    expect(read!.email, 'cary@example.com');
    expect(read.location, 'Lexington, KY');
    expect(read.deceased, isTrue);
  });

  test('contact fields default to null/false when unset', () async {
    // ignore: unused_result
    await repo.upsert(Choreographer(id: 'c1', name: 'Minimal'));
    final read = await repo.getById('c1');
    expect(read!.email, isNull);
    expect(read.location, isNull);
    expect(read.deceased, isFalse);
  });

  test('normalizes empty/whitespace email & location to null', () async {
    // ignore: unused_result
    await repo.upsert(
      Choreographer(id: 'c1', name: 'Blank', email: '   ', location: ''),
    );
    final read = await repo.getById('c1');
    expect(read!.email, isNull);
    expect(read.location, isNull);
  });

  test('trims surrounding whitespace on email & location', () async {
    // ignore: unused_result
    await repo.upsert(
      Choreographer(
        id: 'c1',
        name: 'Trimmed',
        email: '  a@b.com  ',
        location: '  Portland  ',
      ),
    );
    final read = await repo.getById('c1');
    expect(read!.email, 'a@b.com');
    expect(read.location, 'Portland');
  });

  test('copyWith clear flags win over passed values', () async {
    final c = Choreographer(
      id: 'c1',
      name: 'Cleared',
      email: 'a@b.com',
      location: 'Portland',
    );
    final cleared = c.copyWith(
      email: 'ignored@b.com',
      clearEmail: true,
      location: 'Ignored',
      clearLocation: true,
    );
    expect(cleared.email, isNull);
    expect(cleared.location, isNull);
  });

  test('upsert updates in place (same id)', () async {
    // ignore: unused_result
    await repo.upsert(Choreographer(id: 'c1', name: 'Old Name'));
    // ignore: unused_result
    await repo.upsert(Choreographer(id: 'c1', name: 'New Name'));
    final all = await repo.listAll();
    expect(all, hasLength(1));
    expect(all.single.name, 'New Name');
  });

  test('listAll orders by name', () async {
    // ignore: unused_result
    await repo.upsert(Choreographer(id: 'c1', name: 'Zeke'));
    // ignore: unused_result
    await repo.upsert(Choreographer(id: 'c2', name: 'Amy'));
    expect((await repo.listAll()).map((c) => c.name), ['Amy', 'Zeke']);
  });

  test('getById returns null for an unknown id', () async {
    expect(await repo.getById('nope'), isNull);
  });

  test('delete removes an unreferenced choreographer', () async {
    // ignore: unused_result
    await repo.upsert(Choreographer(id: 'c1', name: 'Solo'));
    await repo.delete('c1');
    expect(await repo.getById('c1'), isNull);
  });

  test('delete throws if the choreographer is still credited', () async {
    // ignore: unused_result
    await repo.upsert(Choreographer(id: 'c1', name: 'Credited'));
    await dances.create(
      Dance(
        id: 'd1',
        title: 'Some Dance',
        authorIds: const ['c1'],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
    await expectLater(repo.delete('c1'), throwsA(isA<StateError>()));
    // still there, since delete failed
    expect(await repo.getById('c1'), isNotNull);
  });

  test('delete succeeds when only a soft-deleted dance credits it', () async {
    // A tombstoned dance keeps its `dance_authors` row — a soft delete fires
    // no FK cascade — so counting those rows blocked the delete on the
    // strength of a record that is itself deleted. That is what broke import
    // undo once publication forfeiture started tombstoning a published dance
    // instead of erasing it: the guard threw, `ImportPipeline.undo` swallowed
    // the error, and the import-created choreographer stayed live forever.
    // ignore: unused_result
    await repo.upsert(Choreographer(id: 'c1', name: 'Credited'));
    await dances.create(
      Dance(
        id: 'd1',
        title: 'Some Dance',
        authorIds: const ['c1'],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
    await dances.softDelete('d1', at: DateTime.utc(2026, 2));

    await repo.delete('c1', permanent: true);
    expect(await repo.getById('c1'), isNull);

    // `getById` filters `deleted_at IS NULL`, so the assertion above is
    // satisfied by an erasure AND by a tombstone — it states "gone from live
    // views", which is all #1328 needed, and cannot state which outcome
    // produced it. Issue #1357 changed the outcome from the first to the
    // second, and this test stayed green throughout. Name the outcome here so
    // the next change to this branch has to confront it.
    final row = await (db.select(
      db.choreographers,
    )..where((t) => t.id.equals('c1'))).getSingleOrNull();
    expect(row, isNotNull, reason: 'the row survives as a tombstone (#1357)');
    expect(row!.deletedAt, isNotNull);
  });

  test('delete succeeds once the crediting dance is unlinked', () async {
    // ignore: unused_result
    await repo.upsert(Choreographer(id: 'c1', name: 'Credited'));
    final dance = Dance(
      id: 'd1',
      title: 'Some Dance',
      authorIds: const ['c1'],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await dances.create(dance);
    await dances.update(dance.copyWith(authorIds: const []));

    await repo.delete('c1');
    expect(await repo.getById('c1'), isNull);
  });

  group('permanent delete keeps a tombstoned dance whole (#1357)', () {
    Future<int> authorRows(String choreographerId) async {
      final rows = await (db.select(
        db.danceAuthors,
      )..where((t) => t.choreographerId.equals(choreographerId))).get();
      return rows.length;
    }

    test('tombstones the choreographer instead of erasing it', () async {
      // `dance_authors` is ON DELETE CASCADE, so erasing here destroyed the
      // tombstoned dance's author credit outright — restoring the dance
      // brought it back with no author, and nothing recorded that it ever had
      // one.
      // ignore: unused_result
      await repo.upsert(Choreographer(id: 'c1', name: 'Credited'));
      await dances.create(
        Dance(
          id: 'd1',
          title: 'Some Dance',
          authorIds: const ['c1'],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      await dances.softDelete('d1', at: DateTime.utc(2026, 2));

      await repo.delete('c1', permanent: true);

      final row = await (db.select(
        db.choreographers,
      )..where((t) => t.id.equals('c1'))).getSingleOrNull();
      expect(row, isNotNull, reason: 'the row must survive the rollback');
      expect(row!.deletedAt, isNotNull, reason: 'as a tombstone');
      expect(await authorRows('c1'), 1, reason: 'the credit must survive too');
      expect(
        await repo.getById('c1'),
        isNull,
        reason: 'and still leave every live view, which is what undo needs',
      );
    });

    test('a restored dance keeps its author credit, once the author is '
        'restored too', () async {
      // Both halves asserted deliberately. `_authorsForMany` inner-joins on
      // `choreographers.deleted_at IS NULL`, so restoring the DANCE alone shows
      // nothing: the credit is recoverable, not automatically recovered. The
      // release note says exactly that, and this is what stops it drifting back
      // to "restoring the dance shows them again" — which is what it claimed
      // until review caught it.
      // ignore: unused_result
      await repo.upsert(Choreographer(id: 'c1', name: 'Credited'));
      await dances.create(
        Dance(
          id: 'd1',
          title: 'Some Dance',
          authorIds: const ['c1'],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      await dances.softDelete('d1', at: DateTime.utc(2026, 2));

      await repo.delete('c1', permanent: true);

      await dances.restore('d1', at: DateTime.utc(2026, 3));
      expect(
        (await dances.getById('d1'))!.authorIds,
        isEmpty,
        reason: 'a tombstoned author stays hidden until it is restored',
      );

      await repo.restore('c1', at: DateTime.utc(2026, 3));
      expect((await dances.getById('d1'))!.authorIds, ['c1']);
    });

    test('still erases an unreferenced, unpublished choreographer', () async {
      // ignore: unused_result
      await repo.upsert(Choreographer(id: 'c1', name: 'Solo'));

      await repo.delete('c1', permanent: true);

      final row = await (db.select(
        db.choreographers,
      )..where((t) => t.id.equals('c1'))).getSingleOrNull();
      expect(row, isNull, reason: 'a rollback still leaves nothing behind');
    });
  });

  group('creating onto a live natural key', _liveNameCollisionOnCreate);
}

// ---------------------------------------------------------------------------
// Creating a choreographer whose name a LIVE choreographer already holds.
//
// Same shape as the custom-field and tag guards, driven through this repository
// directly rather than a shared helper: the three `_write` methods are separate
// code, and a guard that exercises one of them proves nothing about the others.
//
// The dance editor cannot currently reach this -- `name_picker` only offers the
// "create" choice when nothing in `options` matches case-insensitively -- so
// this is the repository's own contract rather than a live user path. It is
// guarded anyway because the repository is public API and the sibling defect
// was live.
void _liveNameCollisionOnCreate() {
  late CompendiumDatabase db;
  late ChoreographerRepository repo;

  setUp(() {
    db = openTestDatabase();
    repo = ChoreographerRepository(db);
  });
  tearDown(() => db.close());

  test('refuses a creation onto a live name, typed, before any write', () async {
    // ignore: unused_result
    await repo.upsert(
      Choreographer(id: 'incumbent', name: 'Ada', notes: 'keepme'),
      at: DateTime.utc(2020),
    );

    await expectLater(
      repo.upsert(Choreographer(id: 'newcomer', name: 'Ada')),
      throwsA(
        isA<DuplicateNaturalKeyError>()
            .having((e) => e.table, 'table', 'choreographers')
            .having((e) => e.column, 'column', 'name')
            .having((e) => e.value, 'value', 'Ada')
            .having((e) => e.holderId, 'holderId', 'incumbent'),
      ),
    );

    final rows = await db.select(db.choreographers).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, 'incumbent');
    expect(rows.single.notes, 'keepme');
    expect(rows.single.updatedAt, DateTime.utc(2020).toLocal());
    expect(
      await db.customSelect('SELECT 1 FROM normalisation_skips').get(),
      isEmpty,
    );
  });

  test('still ADOPTS a tombstoned holder rather than refusing', () async {
    // ignore: unused_result
    await repo.upsert(
      Choreographer(id: 'incumbent', name: 'Ada'),
      at: DateTime.utc(2020),
    );
    await repo.delete('incumbent', at: DateTime.utc(2021));
    expect(
      (await (db.select(
        db.choreographers,
      )..where((t) => t.id.equals('incumbent'))).getSingle()).deletedAt,
      isNotNull,
      reason: 'the fixture must actually be a tombstone',
    );

    final written = await repo.upsert(
      Choreographer(id: 'newcomer', name: 'Ada', notes: 'revived'),
      at: DateTime.utc(2022),
    );
    expect(written, 'incumbent', reason: 'the tombstone was adopted');
    final live = await repo.listAll();
    expect(live, hasLength(1));
    expect(live.single.notes, 'revived');
  });

  test('writeFromSync keeps refusing with StateError, not the typed error', () async {
    // ignore: unused_result
    await repo.upsert(Choreographer(id: 'incumbent', name: 'Ada'));
    await expectLater(
      repo.writeFromSync(Choreographer(id: 'inbound', name: 'Ada')),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('wants a name held by'),
        ),
      ),
    );
  });
}
