import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show QueryRow, Table, TableInfo, Variable;
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

/// Guards that the one-shot migration sweeps in [CompendiumRepositories] reach
/// drift's `.watch()` subscribers (issue #768, following #932).
///
/// ## What these can and cannot prove
///
/// Every assertion here is on a **stream**. Querying the table afterwards
/// would pass no matter what, because the SQL in these sweeps was always
/// correct — a bare `customStatement` writes the right rows, it just does not
/// tell drift which table it touched. The missing thing is a *notification*,
/// and a subscriber is the only thing that can observe its absence.
///
/// ## Why these are worth having when the hazard is not live
///
/// The sweeps run from `ensureMigrated`, whose one production caller runs
/// before the app shell is built, so today no watcher exists to be starved.
/// These tests do not assert that a user is affected; they assert the writes
/// are *visible*, so that the safety no longer depends on that ordering. The
/// invalidating change is small and plausible — exposing any of these sweeps
/// as a "repair my library" action from a settings screen — and it would not
/// touch this file, which is exactly why the guard belongs here rather than
/// in a comment.
void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repos;

  setUp(() {
    db = openTestDatabase();
    repos = CompendiumRepositories(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  /// Watches `SELECT COUNT(*)` over [table] — the smallest probe that shows
  /// whether a raw write reached drift's stream machinery at all.
  ///
  /// [table] supplies BOTH the SQL identifier and the `readsFrom` target, so
  /// the probe cannot count one table while listening to another. That
  /// mismatch would make a test pass or fail for a reason unrelated to the
  /// code under test, in a file whose entire purpose is proving notifications
  /// arrive — the same single-source rule the sweeps themselves now follow.
  Future<({List<int> seen, StreamSubscription<List<QueryRow>> sub})> watchCount(
    TableInfo<Table, dynamic> table,
  ) async {
    final seen = <int>[];
    final sub = db
        .customSelect(
          'SELECT COUNT(*) AS n FROM ${table.actualTableName}',
          readsFrom: {table},
        )
        .watch()
        .listen((rows) => seen.add(rows.single.read<int>('n')));
    // Let the initial value arrive so a later emit is a real change.
    await pumpEventQueue();
    return (seen: seen, sub: sub);
  }

  group('migration sweeps reach .watch() subscribers (issue #768)', () {
    test('a sweep completion marker notifies a settings watcher', () async {
      // Covers the five marker writes routed through `_writeSweepMarker`.
      // A fresh database has none of the markers, so `ensureMigrated` runs
      // every sweep and writes all of them.
      final probe = await watchCount(db.settings);
      addTearDown(probe.sub.cancel);
      final before = probe.seen.single;

      await repos.ensureMigrated();
      await pumpEventQueue();

      expect(
        probe.seen.last,
        greaterThan(before),
        reason:
            'the sweep markers were written with a bare customStatement, '
            'so a settings watcher never heard about them',
      );
    });

    test(
      'clearing the rebuild-required marker notifies a settings watcher '
      '(isolated: the DELETE is the only settings write in the window)',
      () async {
        // ## Why the isolation, and why it is done this way
        //
        // `ensureMigrated` writes five sweep markers as well as this DELETE. On
        // a fresh database all six land in one call, so a watcher fires whether
        // or not the DELETE notifies — and this test passed while unable to
        // catch a regression isolated to it. Round 1 of #940 caught that.
        //
        // The precondition is therefore established by RUNNING the sweeps
        // rather than by hand-seeding the five markers: seeding would duplicate
        // each guard's expected key AND its expected value (`'true'`,
        // `'"done"'`, `'"$kSectionRuleVersion"'`), and a copy that drifts from
        // the guard it mirrors would silently stop suppressing the sweep — the
        // test would go quiet rather than red.
        //
        // A second `ensureMigrated` on the same repositories object is a no-op
        // (`_migration ??=` memoises the future), so isolating the DELETE needs
        // a fresh repositories object over the same database.
        await repos.ensureMigrated();

        await db.customUpdate(
          'INSERT OR REPLACE INTO ${db.settings.actualTableName} '
          '(key, value_json) VALUES (?, ?)',
          variables: [
            Variable<String>(derivedRebuildRequiredKey),
            const Variable<String>('true'),
          ],
          updates: {db.settings},
        );
        final probe = await watchCount(db.settings);
        addTearDown(probe.sub.cancel);
        final before = probe.seen.single;

        await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();
        await pumpEventQueue();

        // The marker is hard-deleted once the rebuild it demands has run.
        final rows = await db
            .customSelect(
              'SELECT 1 FROM ${db.settings.actualTableName} WHERE key = ?',
              variables: [Variable<String>(derivedRebuildRequiredKey)],
            )
            .get();
        expect(rows, isEmpty, reason: 'the sweep should have cleared it');

        // Exactly one further emit, and it must carry the post-DELETE count.
        // `greaterThan(1)` would be satisfied by any unrelated settings write
        // that happened to slip into the window, which is the hole this test
        // had; pinning both the emit count and the value closes it.
        expect(
          probe.seen.length,
          2,
          reason: 'one initial value, then exactly one notification',
        );
        expect(
          probe.seen.last,
          before - 1,
          reason: 'and the notification carries the row the DELETE removed',
        );
      },
    );

    test(
      'the purge-corruption repair notifies a program_slots watcher',
      () async {
        // A slot with neither a dance nor text is the corruption this sweep
        // exists to clear (#902-era purge bug). It cannot be built through the
        // repository — it is corruption — so it goes in directly, under a real
        // program so the foreign key holds.
        final now = DateTime.utc(2026);
        await repos.programs.create(
          Program(
            id: 'p1',
            title: 'Evening',
            slots: const [],
            createdAt: now,
            updatedAt: now,
          ),
        );
        await db.customUpdate(
          'INSERT INTO ${db.programSlots.actualTableName} '
          '(id, program_id, position, dance_id, text) VALUES (?, ?, ?, NULL, NULL)',
          variables: [
            const Variable<String>('orphan-slot'),
            const Variable<String>('p1'),
            const Variable<int>(0),
          ],
          updates: {db.programSlots},
        );
        final probe = await watchCount(db.programSlots);
        addTearDown(probe.sub.cancel);
        expect(probe.seen, [1]);

        await repos.ensureMigrated();
        await pumpEventQueue();

        expect(
          probe.seen.last,
          0,
          reason:
              'the orphaned slot was deleted by a bare customStatement, so '
              'a program_slots watcher kept reporting it',
        );
      },
    );

    test(
      'the purge-corruption repair notifies a dance_links watcher',
      () async {
        // A related-dance link whose target is gone is exactly the dangling
        // row this sweep clears; the repository will not create one.
        await repos.dances.create(sampleDance(id: 'd1', title: 'Linked'));
        await db.customUpdate(
          'INSERT INTO ${db.danceLinks.actualTableName} '
          '(id, dance_id, kind, target_dance_id) VALUES (?, ?, ?, NULL)',
          variables: [
            const Variable<String>('orphan-link'),
            const Variable<String>('d1'),
            Variable<String>(LinkKind.relatedDance.name),
          ],
          updates: {db.danceLinks},
        );
        final probe = await watchCount(db.danceLinks);
        addTearDown(probe.sub.cancel);
        expect(probe.seen, [1]);

        await repos.ensureMigrated();
        await pumpEventQueue();

        expect(
          probe.seen.last,
          0,
          reason:
              'the dangling related-dance link was deleted by a bare '
              'customStatement, so a dance_links watcher kept reporting it',
        );
      },
    );

    test('a figures_json rewrite notifies a dances watcher', () async {
      // `star_promenade.hand` was retired in taxonomy v26 (#843); the sweep
      // rewrites figures_json in place for every dance still carrying it.
      // invalid-fixture: the retired param is the point — this is pre-v26 data on disk, which is exactly what the sweep exists to clean up, so a fixture valid under the current taxonomy could not exercise it
      await repos.dances.create(
        sampleDance(
          id: 'd1',
          title: 'Star Dance',
          figures: [
            Figure(move: 'star_promenade', params: const {'hand': 'right'}),
          ],
        ),
      );
      final seen = <String>[];
      final sub = db
          .customSelect(
            'SELECT figures_json AS f FROM ${db.dances.actualTableName} '
            'WHERE id = ?',
            variables: [const Variable<String>('d1')],
            readsFrom: {db.dances},
          )
          .watch()
          .listen((rows) {
            if (rows.isNotEmpty) seen.add(rows.single.read<String>('f'));
          });
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(seen, hasLength(1));
      expect(seen.single, contains('hand'));

      await repos.ensureMigrated();
      await pumpEventQueue();

      expect(
        seen.last,
        isNot(contains('hand')),
        reason:
            'the figures_json rewrite used a bare customStatement, so a '
            'dances watcher kept reporting the retired param',
      );
    });
  });
}
