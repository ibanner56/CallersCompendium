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

  test('setStatusForMany sets the status on the listed dances only', () async {
    await dances.create(sampleDance(id: 'a', title: 'Alpha'));
    await dances.create(sampleDance(id: 'b', title: 'Bravo'));
    await dances.create(sampleDance(id: 'c', title: 'Charlie'));

    final changed = await dances.setStatusForMany(
      ['a', 'b'],
      status: DanceStatus.deprecated,
      now: now,
    );

    expect(changed, 2);
    expect((await dances.getById('a'))!.status, DanceStatus.deprecated);
    expect((await dances.getById('b'))!.status, DanceStatus.deprecated);
    expect((await dances.getById('c'))!.status, DanceStatus.active);
  });

  test('setStatusForMany stamps and counts only dances that change', () async {
    await dances.create(
      sampleDance(id: 'a', title: 'Alpha').copyWith(status: DanceStatus.broken),
    );
    await dances.create(sampleDance(id: 'b', title: 'Bravo'));
    final untouchedStamp = (await dances.getById('a'))!.updatedAt;

    final changed = await dances.setStatusForMany(
      ['a', 'b', 'missing'],
      status: DanceStatus.broken,
      now: now,
    );

    expect(changed, 1);
    expect((await dances.getById('a'))!.updatedAt, untouchedStamp);
    expect((await dances.getById('b'))!.updatedAt, now);
    expect((await dances.getById('b'))!.status, DanceStatus.broken);
  });

  test('setStatusForMany returns 0 when every dance already matches', () async {
    await dances.create(sampleDance(id: 'a', title: 'Alpha'));

    expect(
      await dances.setStatusForMany(
        ['a'],
        status: DanceStatus.active,
        now: now,
      ),
      0,
    );
    expect(
      await dances.setStatusForMany([], status: DanceStatus.draft, now: now),
      0,
    );
  });

  test('setStatusForMany changes nothing but status and updatedAt', () async {
    await dances.create(sampleDance(id: 'a', title: 'Alpha'));
    final before = (await dances.getById('a'))!;

    await dances.setStatusForMany(
      ['a'],
      status: DanceStatus.variation,
      now: now,
    );

    final after = (await dances.getById('a'))!;
    expect(
      after.copyWith(status: before.status, updatedAt: before.updatedAt),
      before,
    );
  });
}
