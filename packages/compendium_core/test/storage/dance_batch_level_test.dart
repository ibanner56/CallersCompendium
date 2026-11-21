import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';
import 'fixtures.dart';

void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;

  final now = DateTime.utc(2026, 6, 1);

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  test('setLevelForMany sets the level on all listed dances', () async {
    await dances.create(sampleDance(id: 'a', title: 'Alpha'));
    await dances.create(sampleDance(id: 'b', title: 'Bravo'));
    await dances.create(sampleDance(id: 'c', title: 'Charlie'));

    final changed = await dances.setLevelForMany(
      ['a', 'b'],
      difficultyLevelId: DifficultyLevel.intermediateId,
      now: now,
    );

    expect(changed, 2);
    expect(
      (await dances.getById('a'))!.difficultyLevelId,
      DifficultyLevel.intermediateId,
    );
    expect(
      (await dances.getById('b'))!.difficultyLevelId,
      DifficultyLevel.intermediateId,
    );
    // The un-listed dance is untouched.
    expect((await dances.getById('c'))!.difficultyLevelId, isNull);
  });

  test('setLevelForMany stamps updatedAt only on changed dances', () async {
    await dances.create(sampleDance(id: 'a', title: 'Alpha'));
    final before = (await dances.getById('a'))!.updatedAt;

    await dances.setLevelForMany(
      ['a'],
      difficultyLevelId: DifficultyLevel.advancedId,
      now: now,
    );

    expect((await dances.getById('a'))!.updatedAt, now);
    expect(now, isNot(before));
  });

  test(
    'setLevelForMany is idempotent — skips dances already at target',
    () async {
      await dances.create(
        sampleDance(
          id: 'a',
          title: 'Alpha',
        ).copyWith(difficultyLevelId: DifficultyLevel.beginnerId),
      );
      await dances.create(sampleDance(id: 'b', title: 'Bravo'));

      final changed = await dances.setLevelForMany(
        ['a', 'b'],
        difficultyLevelId: DifficultyLevel.beginnerId,
        now: now,
      );

      // Only b changes; a is already beginner.
      expect(changed, 1);
      expect(
        (await dances.getById('a'))!.difficultyLevelId,
        DifficultyLevel.beginnerId,
      );
      expect(
        (await dances.getById('b'))!.difficultyLevelId,
        DifficultyLevel.beginnerId,
      );
    },
  );

  test('setLevelForMany with clearDifficultyLevel unsets the level', () async {
    await dances.create(
      sampleDance(
        id: 'a',
        title: 'Alpha',
      ).copyWith(difficultyLevelId: DifficultyLevel.advancedId),
    );

    final changed = await dances.setLevelForMany(
      ['a'],
      clearDifficultyLevel: true,
      now: now,
    );

    expect(changed, 1);
    expect((await dances.getById('a'))!.difficultyLevelId, isNull);
  });

  test(
    'setLevelForMany clearDifficultyLevel wins over a passed level value',
    () async {
      await dances.create(
        sampleDance(
          id: 'a',
          title: 'Alpha',
        ).copyWith(difficultyLevelId: DifficultyLevel.advancedId),
      );

      await dances.setLevelForMany(
        ['a'],
        difficultyLevelId: DifficultyLevel.beginnerId,
        clearDifficultyLevel: true,
        now: now,
      );

      expect((await dances.getById('a'))!.difficultyLevelId, isNull);
    },
  );

  test('setLevelForMany ignores unknown ids and an empty list', () async {
    await dances.create(sampleDance(id: 'a', title: 'Alpha'));

    expect(
      await dances.setLevelForMany(
        const [],
        difficultyLevelId: DifficultyLevel.intermediateId,
        now: now,
      ),
      0,
    );
    expect(
      await dances.setLevelForMany(
        ['does-not-exist'],
        difficultyLevelId: DifficultyLevel.intermediateId,
        now: now,
      ),
      0,
    );
    expect((await dances.getById('a'))!.difficultyLevelId, isNull);
  });

  test('setLevelForMany throws (and does not wipe) when given neither level '
      'nor clearLevel', () async {
    await dances.create(
      sampleDance(
        id: 'a',
        title: 'Alpha',
      ).copyWith(difficultyLevelId: DifficultyLevel.intermediateId),
    );

    // Release-safe guard: must throw ArgumentError, not silently clear.
    expect(
      () => dances.setLevelForMany(['a'], now: now),
      throwsA(isA<ArgumentError>()),
    );
    // The existing level survives the rejected call.
    expect(
      (await dances.getById('a'))!.difficultyLevelId,
      DifficultyLevel.intermediateId,
    );
  });

  test('setLevelForMany(N) stays within a per-chunk statement budget', () async {
    // Counts every SELECT the batch issues. Before `_updateMany` the loop called
    // `getById` per id (a dance select plus six child selects) and every write
    // then rebuilt the derived rows: 10,000 SELECTs for 1,000 dances. Now the
    // dances and their six child tables are read once per 500-id chunk
    // (`c` = 7 SELECTs) and `_upsert` adds 2 per written dance; measured 2,014,
    // so `k` = 3 per dance leaves room for one more SELECT without admitting a
    // return to the per-id read.
    const n = 1000;
    const c = 7;
    const k = 3;
    final counter = QueryCounter();
    final countingDb = openCountingTestDatabase(counter);
    addTearDown(countingDb.close);
    final repo = DanceRepository(countingDb, contraTaxonomy);
    await countingDb.transaction(() async {
      for (var i = 0; i < n; i++) {
        await repo.create(sampleDance(id: 'd$i', title: 'Dance $i'));
      }
    });
    counter.reset();

    final changed = await repo.setLevelForMany(
      [for (var i = 0; i < n; i++) 'd$i'],
      difficultyLevelId: DifficultyLevel.intermediateId,
      now: now,
    );

    expect(changed, n);
    expect(counter.count, lessThanOrEqualTo(c * (n / 500).ceil() + k * n));
  });
}
