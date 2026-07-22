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

  test('setRatingForMany sets the rating on all listed dances', () async {
    await dances.create(sampleDance(id: 'a', title: 'Alpha'));
    await dances.create(sampleDance(id: 'b', title: 'Bravo'));
    await dances.create(sampleDance(id: 'c', title: 'Charlie'));

    final changed = await dances.setRatingForMany(
      ['a', 'b'],
      rating: 4,
      now: now,
    );

    expect(changed, 2);
    expect((await dances.getById('a'))!.rating, 4);
    expect((await dances.getById('b'))!.rating, 4);
    // The un-listed dance is untouched.
    expect((await dances.getById('c'))!.rating, isNull);
  });

  test('setRatingForMany stamps updatedAt only on changed dances', () async {
    await dances.create(sampleDance(id: 'a', title: 'Alpha'));
    final before = (await dances.getById('a'))!.updatedAt;

    await dances.setRatingForMany(['a'], rating: 5, now: now);

    expect((await dances.getById('a'))!.updatedAt, now);
    expect(now, isNot(before));
  });

  test(
    'setRatingForMany is idempotent — skips dances already at target',
    () async {
      await dances.create(
        sampleDance(id: 'a', title: 'Alpha').copyWith(rating: 3),
      );
      await dances.create(sampleDance(id: 'b', title: 'Bravo'));

      final changed = await dances.setRatingForMany(
        ['a', 'b'],
        rating: 3,
        now: now,
      );

      // Only b changes; a is already 3 stars.
      expect(changed, 1);
      expect((await dances.getById('a'))!.rating, 3);
      expect((await dances.getById('b'))!.rating, 3);
    },
  );

  test('setRatingForMany with clearRating unsets the rating', () async {
    await dances.create(
      sampleDance(id: 'a', title: 'Alpha').copyWith(rating: 5),
    );

    final changed = await dances.setRatingForMany(
      ['a'],
      clearRating: true,
      now: now,
    );

    expect(changed, 1);
    expect((await dances.getById('a'))!.rating, isNull);
  });

  test(
    'setRatingForMany clearRating wins over a passed rating value',
    () async {
      await dances.create(
        sampleDance(id: 'a', title: 'Alpha').copyWith(rating: 5),
      );

      await dances.setRatingForMany(
        ['a'],
        rating: 2,
        clearRating: true,
        now: now,
      );

      expect((await dances.getById('a'))!.rating, isNull);
    },
  );

  test('setRatingForMany ignores unknown ids and an empty list', () async {
    await dances.create(sampleDance(id: 'a', title: 'Alpha'));

    expect(await dances.setRatingForMany(const [], rating: 4, now: now), 0);
    expect(
      await dances.setRatingForMany(['does-not-exist'], rating: 4, now: now),
      0,
    );
    expect((await dances.getById('a'))!.rating, isNull);
  });

  test('setRatingForMany throws (and does not wipe) when given neither rating '
      'nor clearRating', () async {
    await dances.create(
      sampleDance(id: 'a', title: 'Alpha').copyWith(rating: 3),
    );

    expect(
      () => dances.setRatingForMany(['a'], now: now),
      throwsA(isA<ArgumentError>()),
    );
    expect((await dances.getById('a'))!.rating, 3);
  });

  test('setRatingForMany rejects an out-of-range rating without touching '
      'dances', () async {
    await dances.create(
      sampleDance(id: 'a', title: 'Alpha').copyWith(rating: 3),
    );

    expect(
      () => dances.setRatingForMany(['a'], rating: 0, now: now),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => dances.setRatingForMany(['a'], rating: 6, now: now),
      throwsA(isA<ArgumentError>()),
    );
    expect((await dances.getById('a'))!.rating, 3);
  });
}
