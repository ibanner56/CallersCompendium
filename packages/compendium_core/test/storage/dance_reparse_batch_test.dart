import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

void main() {
  final now = DateTime.utc(2026, 6, 1);

  test('reparseImportGapFiguresForMany issues a chunked prefetch, not one '
      'getById per dance', () async {
    // Counts every SELECT the batch issues, with the budget CS-34a set for the
    // other batch methods: the dances and their six child tables are read once
    // per 500-id chunk (`c` = 7 SELECTs) and `_upsert` adds a few per written
    // dance. Before `_updateMany` the loop called `getById` per id (a dance
    // select plus six child selects), so 100 dances cost ~700 reads before any
    // write.
    const n = 100;
    const c = 7;
    const k = 3;
    final counter = QueryCounter();
    final countingDb = openCountingTestDatabase(counter);
    addTearDown(countingDb.close);
    final repo = DanceRepository(countingDb, contraTaxonomy);
    await countingDb.transaction(() async {
      for (var i = 0; i < n; i++) {
        await repo.create(
          sampleDance(
            id: 'd$i',
            title: 'Dance $i',
            figures: [
              customFigure(
                'Neighbor swing',
                beats: 16,
                origin: CustomOrigin.importGap,
              ),
            ],
          ),
        );
      }
    });
    counter.reset();

    final changed = await repo.reparseImportGapFiguresForMany(
      [for (var i = 0; i < n; i++) 'd$i'],
      reparse: reparseImportGapFigures,
      now: now,
    );

    expect(changed, n);
    expect(counter.count, lessThanOrEqualTo(c * (n / 500).ceil() + k * n));
  });

  test('a reparse is not a local user edit: it leaves a held sync tombstone '
      'in place and stamps updatedAt', () async {
    // §6.8: only a deliberate user edit cancels a pending tombstone, and the
    // reparse is a re-derivation of stored content (`localUserEdit: false`).
    // `_updateMany` defaults the flag to true, so this pins the explicit false.
    final db = openTestDatabase();
    addTearDown(db.close);
    final repos = CompendiumRepositories(db, contraTaxonomy);
    final stamp = DateTime.utc(2025, 1, 2, 12);
    final dance = sampleDance(
      id: 'held',
      figures: [customFigure('Neighbor swing', origin: CustomOrigin.importGap)],
    );
    await repos.dances.create(dance);
    final tombstone = SyncRecordBlob(
      kind: SyncRecordKind.dance,
      id: 'held',
      updatedAt: stamp,
      deletedAt: stamp,
      existenceAt: stamp,
      body: syncBodyForEntity(SyncRecordKind.dance, dance),
    );
    await repos.syncLocal.upsertPendingDeletion(
      kind: SyncRecordKind.dance,
      recordId: 'held',
      tombstonedAt: stamp,
      tombstoneHash: 'hash',
      tombstoneBlob: encodeSyncRecordBlob(tombstone),
    );

    final changed = await repos.dances.reparseImportGapFiguresForMany(
      ['held'],
      reparse: reparseImportGapFigures,
      now: now,
    );

    expect(changed, 1);
    expect((await repos.dances.getById('held'))!.updatedAt, now);
    expect(
      await repos.syncLocal.getPendingDeletion(
        kind: SyncRecordKind.dance,
        recordId: 'held',
      ),
      isNotNull,
      reason: 'a reparse must not cancel a pending tombstone',
    );
  });
}
