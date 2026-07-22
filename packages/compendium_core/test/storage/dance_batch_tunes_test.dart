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

  group('addTunesForMany', () {
    test(
      'merges tunes into each dance without removing existing ones',
      () async {
        await dances.create(
          sampleDance(id: 'a', title: 'Alpha').copyWith(tunes: ['Reel A']),
        );
        await dances.create(sampleDance(id: 'b', title: 'Bravo'));

        final changed = await dances.addTunesForMany(
          ['a', 'b'],
          tunes: ['Jig B', 'Reel C'],
          now: now,
        );

        expect(changed, 2);
        // Existing tune preserved, additions appended.
        expect((await dances.getById('a'))!.tunes, [
          'Reel A',
          'Jig B',
          'Reel C',
        ]);
        expect((await dances.getById('b'))!.tunes, ['Jig B', 'Reel C']);
      },
    );

    test(
      'is idempotent — adding tunes already present changes nothing',
      () async {
        await dances.create(
          sampleDance(
            id: 'a',
            title: 'Alpha',
          ).copyWith(tunes: ['Reel A', 'Jig B']),
        );

        final changed = await dances.addTunesForMany(
          ['a'],
          tunes: ['Reel A', 'Jig B'],
          now: now,
        );

        expect(changed, 0);
        expect((await dances.getById('a'))!.tunes, ['Reel A', 'Jig B']);
      },
    );

    test('sanitizes incoming tunes: trims, drops blanks, de-dupes', () async {
      await dances.create(sampleDance(id: 'a', title: 'Alpha'));

      final changed = await dances.addTunesForMany(
        ['a'],
        tunes: ['  Reel A  ', '', '   ', 'Reel A', 'Jig B'],
        now: now,
      );

      expect(changed, 1);
      expect((await dances.getById('a'))!.tunes, ['Reel A', 'Jig B']);
    });

    test('stamps updatedAt only on changed dances', () async {
      await dances.create(
        sampleDance(id: 'a', title: 'Alpha').copyWith(tunes: ['Reel A']),
      );
      await dances.create(sampleDance(id: 'b', title: 'Bravo'));

      final changed = await dances.addTunesForMany(
        ['a', 'b'],
        tunes: ['Reel A'],
        now: now,
      );

      // a already has Reel A (skipped); only b changes.
      expect(changed, 1);
      expect((await dances.getById('b'))!.updatedAt, now);
    });

    test('no-op for empty ids or tunes that sanitize to empty', () async {
      await dances.create(sampleDance(id: 'a', title: 'Alpha'));

      expect(await dances.addTunesForMany(const [], tunes: ['x'], now: now), 0);
      expect(
        await dances.addTunesForMany(['a'], tunes: ['', '  '], now: now),
        0,
      );
      expect(
        await dances.addTunesForMany(
          ['does-not-exist'],
          tunes: ['x'],
          now: now,
        ),
        0,
      );
      expect((await dances.getById('a'))!.tunes, isEmpty);
    });
  });

  group('clearTunesForMany', () {
    test('removes all tunes from listed dances', () async {
      await dances.create(
        sampleDance(
          id: 'a',
          title: 'Alpha',
        ).copyWith(tunes: ['Reel A', 'Jig B']),
      );
      await dances.create(
        sampleDance(id: 'b', title: 'Bravo').copyWith(tunes: ['Reel C']),
      );
      await dances.create(
        sampleDance(id: 'c', title: 'Charlie').copyWith(tunes: ['Reel D']),
      );

      final changed = await dances.clearTunesForMany(['a', 'b'], now: now);

      expect(changed, 2);
      expect((await dances.getById('a'))!.tunes, isEmpty);
      expect((await dances.getById('b'))!.tunes, isEmpty);
      // Un-listed dance keeps its tunes.
      expect((await dances.getById('c'))!.tunes, ['Reel D']);
    });

    test('is idempotent — skips dances that already have no tunes', () async {
      await dances.create(
        sampleDance(id: 'a', title: 'Alpha').copyWith(tunes: ['Reel A']),
      );
      await dances.create(sampleDance(id: 'b', title: 'Bravo'));

      final changed = await dances.clearTunesForMany(['a', 'b'], now: now);

      expect(changed, 1);
      expect((await dances.getById('a'))!.tunes, isEmpty);
    });

    test('no-op for empty ids and unknown ids', () async {
      await dances.create(
        sampleDance(id: 'a', title: 'Alpha').copyWith(tunes: ['Reel A']),
      );

      expect(await dances.clearTunesForMany(const [], now: now), 0);
      expect(await dances.clearTunesForMany(['does-not-exist'], now: now), 0);
      expect((await dances.getById('a'))!.tunes, ['Reel A']);
    });
  });
}
