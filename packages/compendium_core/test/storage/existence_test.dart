// The causal existence stamp (schema v25, issue #898).
//
// `nextExistenceStamp` is the reference implementation of
// `max(localNow, currentExistenceAt + 1 tick)`, but nothing in production calls
// it: the repositories apply the same arithmetic in SQL so a transition is one
// statement with no preceding read. Two implementations of one rule can drift
// apart silently, so the second group here runs both over the same table of
// cases and asserts they agree.
import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  final t0 = DateTime.utc(2026, 5, 1, 12);

  group('nextExistenceStamp', () {
    test('with nothing to supersede, it is the plain clock', () {
      expect(nextExistenceStamp(now: t0), t0);
      expect(nextExistenceStamp(now: t0, current: null), t0);
    });

    test('a clock ahead of the current value wins outright', () {
      expect(
        nextExistenceStamp(
          now: t0,
          current: t0.subtract(const Duration(days: 1)),
        ),
        t0,
      );
    });

    test('an equal clock is bumped past the value it supersedes', () {
      // This is the case the rule exists for. A delete and an undo inside one
      // tick is an ordinary user action, and a bare clock read would stamp the
      // revival equal to the tombstone — which §6.4 resolves in favour of the
      // tombstone, so the undo would silently lose.
      //
      // NOTE ON WHAT THIS TEST CANNOT CATCH. It asserts the pure function is
      // self-consistent with whatever [existenceStampTick] says, so shrinking
      // the tick to a millisecond moves both sides and this stays green — it is
      // structurally incapable of catching that mutation. Verified, not
      // assumed: under a `+ 1ms` tick this test passes while ten others fail.
      // Granularity is pinned by 'the tick is the smallest increment the column
      // can hold' below, and by the storage-level Undo-snackbar tests in
      // `soft_delete_test.dart`.
      expect(
        nextExistenceStamp(now: t0, current: t0),
        t0.add(existenceStampTick),
      );
    });

    test('a clock behind the current value is dragged past it', () {
      // A device whose clock is wrong must not be able to stamp a transition
      // that reads as older than the one it replaces.
      final future = t0.add(const Duration(days: 3650));
      expect(
        nextExistenceStamp(now: t0, current: future),
        future.add(existenceStampTick),
      );
    });

    test('repeated transitions strictly increase, clock or no clock', () {
      var current = t0;
      for (var i = 0; i < 5; i++) {
        final next = nextExistenceStamp(now: t0, current: current);
        expect(next.isAfter(current), isTrue, reason: 'step $i');
        current = next;
      }
    });

    test('the tick is the smallest increment the column can hold', () {
      // `existence_at` is stored as unix seconds, so a sub-second tick would
      // round away and the stamp would tie with what it supersedes. Guard the
      // constant itself: a future change to something smaller than one second
      // silently breaks every case above at the storage layer while leaving
      // this file's pure-Dart assertions green.
      expect(existenceStampTick.inMilliseconds, greaterThanOrEqualTo(1000));
      expect(
        unixSeconds(t0.add(existenceStampTick)),
        unixSeconds(t0) + 1,
        reason: 'one tick must survive the round trip to unix seconds',
      );
    });
  });

  group('the SQL and the reference implementation agree', () {
    late CompendiumDatabase db;
    late CompendiumRepositories repos;

    setUp(() {
      db = openTestDatabase();
      repos = CompendiumRepositories(db, contraTaxonomy);
    });
    tearDown(() => db.close());

    Future<int?> existenceOf(String id) async {
      final rows = await db
          .customSelect("SELECT existence_at AS v FROM tags WHERE id = '$id'")
          .get();
      return rows.single.data['v'] as int?;
    }

    /// Every interesting relationship between the clock and the stored value:
    /// clock ahead, clock equal, clock behind.
    final cases = <(String, DateTime, DateTime)>[
      ('clock ahead', t0, t0.add(const Duration(hours: 1))),
      ('clock equal', t0, t0),
      ('clock behind', t0, t0.subtract(const Duration(hours: 1))),
    ];

    for (final (label, seededAt, transitionAt) in cases) {
      test('$label: a delete stamps what nextExistenceStamp says', () async {
        await repos.tags.upsert(
          Tag(id: 't1', name: 'Easy'),
          at: seededAt,
        );
        final before = await existenceOf('t1');
        await repos.tags.delete('t1', at: transitionAt);

        expect(
          await existenceOf('t1'),
          unixSeconds(
            nextExistenceStamp(
              now: transitionAt,
              current: DateTime.fromMillisecondsSinceEpoch(
                before! * 1000,
                isUtc: true,
              ),
            ),
          ),
          reason: '$label: SQL transition must match the reference rule',
        );
      });

      test('$label: a revival stamps what nextExistenceStamp says', () async {
        await repos.tags.upsert(
          Tag(id: 't1', name: 'Easy'),
          at: seededAt,
        );
        await repos.tags.delete('t1', at: seededAt);
        final tombstone = await existenceOf('t1');

        await repos.tags.upsert(
          Tag(id: 't1', name: 'Easy'),
          at: transitionAt,
        );
        expect(
          await existenceOf('t1'),
          unixSeconds(
            nextExistenceStamp(
              now: transitionAt,
              current: DateTime.fromMillisecondsSinceEpoch(
                tombstone! * 1000,
                isUtc: true,
              ),
            ),
          ),
          reason: '$label: SQL revival must match the reference rule',
        );
        expect(
          await existenceOf('t1'),
          greaterThan(tombstone),
          reason: '$label: a revival must outrank the tombstone in every case',
        );
      });
    }

    test(
      'a row carrying no stamp at all falls back to the plain clock',
      () async {
        // COALESCE(existence_at, 0) covers a row written by something that
        // bypassed the repositories — the settings markers written with
        // INSERT OR REPLACE are exactly that. `0 + 1` is 1970, so the MAX yields
        // the clock, which is right when there is nothing to supersede.
        await repos.tags.upsert(
          Tag(id: 't1', name: 'Easy'),
          at: t0,
        );
        await db.customStatement('UPDATE tags SET existence_at = NULL');
        await repos.tags.delete('t1', at: t0);
        expect(await existenceOf('t1'), unixSeconds(t0));
        expect(nextExistenceStamp(now: t0, current: null), t0);
      },
    );
  });
}
