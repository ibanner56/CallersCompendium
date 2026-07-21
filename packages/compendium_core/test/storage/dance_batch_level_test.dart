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
      level: DanceLevel.intermediate,
      now: now,
    );

    expect(changed, 2);
    expect((await dances.getById('a'))!.level, DanceLevel.intermediate);
    expect((await dances.getById('b'))!.level, DanceLevel.intermediate);
    // The un-listed dance is untouched.
    expect((await dances.getById('c'))!.level, isNull);
  });

  test('setLevelForMany stamps updatedAt only on changed dances', () async {
    await dances.create(sampleDance(id: 'a', title: 'Alpha'));
    final before = (await dances.getById('a'))!.updatedAt;

    await dances.setLevelForMany(['a'], level: DanceLevel.advanced, now: now);

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
        ).copyWith(level: DanceLevel.beginner),
      );
      await dances.create(sampleDance(id: 'b', title: 'Bravo'));

      final changed = await dances.setLevelForMany(
        ['a', 'b'],
        level: DanceLevel.beginner,
        now: now,
      );

      // Only b changes; a is already beginner.
      expect(changed, 1);
      expect((await dances.getById('a'))!.level, DanceLevel.beginner);
      expect((await dances.getById('b'))!.level, DanceLevel.beginner);
    },
  );

  test('setLevelForMany with clearLevel unsets the level', () async {
    await dances.create(
      sampleDance(id: 'a', title: 'Alpha').copyWith(level: DanceLevel.advanced),
    );

    final changed = await dances.setLevelForMany(
      ['a'],
      clearLevel: true,
      now: now,
    );

    expect(changed, 1);
    expect((await dances.getById('a'))!.level, isNull);
  });

  test('setLevelForMany clearLevel wins over a passed level value', () async {
    await dances.create(
      sampleDance(id: 'a', title: 'Alpha').copyWith(level: DanceLevel.advanced),
    );

    await dances.setLevelForMany(
      ['a'],
      level: DanceLevel.beginner,
      clearLevel: true,
      now: now,
    );

    expect((await dances.getById('a'))!.level, isNull);
  });

  test('setLevelForMany ignores unknown ids and an empty list', () async {
    await dances.create(sampleDance(id: 'a', title: 'Alpha'));

    expect(
      await dances.setLevelForMany(
        const [],
        level: DanceLevel.intermediate,
        now: now,
      ),
      0,
    );
    expect(
      await dances.setLevelForMany(
        ['does-not-exist'],
        level: DanceLevel.intermediate,
        now: now,
      ),
      0,
    );
    expect((await dances.getById('a'))!.level, isNull);
  });

  test('setLevelForMany asserts a level or clearLevel is provided', () async {
    await dances.create(sampleDance(id: 'a', title: 'Alpha'));

    // Neither a level nor clearLevel — must not silently clear.
    expect(
      () => dances.setLevelForMany(['a'], now: now),
      throwsA(isA<AssertionError>()),
    );
  });
}
