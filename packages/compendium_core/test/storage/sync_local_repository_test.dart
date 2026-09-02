import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/storage/database.dart'
    show BaselineStateCompanion;
import 'package:drift/drift.dart' show Value;
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  group('SyncLocalRepository schema', () {
    test(
      'uses typed composite identities and an enforced singleton epoch',
      () async {
        final db = openTestDatabase();
        addTearDown(db.close);

        final tables = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name IN ('baseline_state', 'baseline_entries', 'id_aliases', "
              "'pending_deletions', 'review_queue', 'published_records')",
            )
            .get();
        expect(tables.map((row) => row.read<String>('name')).toSet(), {
          'baseline_state',
          'baseline_entries',
          'id_aliases',
          'pending_deletions',
          'review_queue',
          'published_records',
        });

        final baselineColumns = await db
            .customSelect('PRAGMA table_info(baseline_state)')
            .get();
        final baselineInfo = {
          for (final row in baselineColumns) row.read<String>('name'): row.data,
        };
        expect(baselineInfo['id']!['notnull'], 1);
        expect(baselineInfo['id']!['pk'], 1);
        expect(baselineInfo['epoch']!['type'], 'TEXT');
        expect(baselineInfo['epoch']!['notnull'], 1);

        final entries = await db
            .customSelect('PRAGMA table_info(baseline_entries)')
            .get();
        final entryInfo = {
          for (final row in entries) row.read<String>('name'): row.data,
        };
        expect(entryInfo['kind']!['pk'], 1);
        expect(entryInfo['record_id']!['pk'], 2);
        expect(entryInfo['body_hash']!['notnull'], 0);

        final repository = SyncLocalRepository(db);
        await repository.replaceBaseline(
          epoch: '9c4a1f2e8b7d4a6c9e0f1a2b3c4d5e6f',
          entries: [
            const SyncBaselineEntry(
              kind: SyncRecordKind.dance,
              recordId: 'same-id',
              wireHash: 'wire-dance',
            ),
            const SyncBaselineEntry(
              kind: SyncRecordKind.program,
              recordId: 'same-id',
              wireHash: 'wire-program',
            ),
          ],
        );
        expect((await repository.listBaselineEntries()), hasLength(2));

        await expectLater(
          db
              .into(db.baselineState)
              .insert(
                BaselineStateCompanion.insert(
                  id: const Value(2),
                  epoch: '8b3d2e1f0a9c8b7d6e5f4a3b2c1d0e9f',
                ),
              ),
          throwsA(isA<SqliteException>()),
        );
      },
    );
  });

  test('fresh empty baseline retains its epoch', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final repository = SyncLocalRepository(db);

    await repository.replaceBaseline(epoch: '9c4a1f2e8b7d4a6c9e0f1a2b3c4d5e6f');

    expect(
      (await repository.getBaselineState())!.epoch,
      '9c4a1f2e8b7d4a6c9e0f1a2b3c4d5e6f',
    );
    expect(await repository.listBaselineEntries(), isEmpty);
  });

  group('SyncLocalRepository lifecycle', () {
    late CompendiumDatabase db;
    late SyncLocalRepository repository;

    setUp(() async {
      db = openTestDatabase();
      repository = SyncLocalRepository(db);
      await repository.replaceBaseline(
        epoch: '9c4a1f2e8b7d4a6c9e0f1a2b3c4d5e6f',
        entries: [
          const SyncBaselineEntry(
            kind: SyncRecordKind.dance,
            recordId: 'd1',
            wireHash: 'w1',
            bodyHash: 'b1',
          ),
        ],
      );
      await repository.upsertAlias(
        kind: SyncRecordKind.dance,
        losingId: 'old',
        survivingId: 'new',
      );
      await repository.upsertPendingDeletion(
        kind: SyncRecordKind.dance,
        recordId: 'd1',
        tombstonedAt: DateTime.utc(2026, 1, 1),
        tombstoneHash: 't1',
        tombstoneBlob: '{"id":"d1"}',
      );
      await repository.upsertPendingDeletion(
        kind: SyncRecordKind.program,
        recordId: 'p1',
        tombstonedAt: DateTime.utc(2026, 1, 1),
        tombstoneHash: 't2',
        tombstoneBlob: '{"id":"p1"}',
      );
      await repository.enqueueReview(
        kind: SyncRecordKind.dance,
        recordId: 'd1',
        counterpartId: 'remote-d1',
        reason: 'collision',
        candidateBlob: '{"id":"d1"}',
        candidateHash: 'c1',
        queuedAt: DateTime.utc(2026, 1, 1),
      );
      await repository.markPublished(
        kind: SyncRecordKind.dance,
        recordId: 'd1',
      );
    });

    tearDown(() => db.close());

    test(
      'same-epoch baseline replacement preserves aliases and review queue',
      () async {
        await repository.replaceBaseline(
          epoch: '9c4a1f2e8b7d4a6c9e0f1a2b3c4d5e6f',
        );
        expect(
          (await repository.getBaselineState())!.epoch,
          '9c4a1f2e8b7d4a6c9e0f1a2b3c4d5e6f',
        );
        expect(await repository.listBaselineEntries(), isEmpty);
        expect(await repository.listAliases(), hasLength(1));
        expect(await repository.listReviewQueue(), hasLength(1));
        expect(await repository.listPendingDeletions(), hasLength(2));
        expect(await repository.listPublishedRecords(), hasLength(1));
      },
    );

    test(
      'epoch reset clears baseline conclusions but preserves monotonic state',
      () async {
        await repository.resetEpoch(epoch: '8b3d2e1f0a9c8b7d6e5f4a3b2c1d0e9f');
        expect(
          (await repository.getBaselineState())!.epoch,
          '8b3d2e1f0a9c8b7d6e5f4a3b2c1d0e9f',
        );
        expect(await repository.listBaselineEntries(), isEmpty);
        expect(await repository.listAliases(), isEmpty);
        expect(await repository.listReviewQueue(), isEmpty);
        expect(await repository.listPendingDeletions(), hasLength(2));
        expect(
          await repository.isPublished(
            kind: SyncRecordKind.dance,
            recordId: 'd1',
          ),
          isTrue,
        );
      },
    );

    test(
      'restore clears baseline groups and revalidates pending deletions',
      () async {
        await repository.clearForRestore(
          restoredRecords: const [(kind: SyncRecordKind.dance, recordId: 'd1')],
        );
        expect(await repository.getBaselineState(), isNull);
        expect(await repository.listBaselineEntries(), isEmpty);
        expect(await repository.listAliases(), isEmpty);
        expect(await repository.listReviewQueue(), isEmpty);
        expect(await repository.listPendingDeletions(), hasLength(1));
        expect((await repository.listPendingDeletions()).single.recordId, 'd1');
        expect(
          await repository.isPublished(
            kind: SyncRecordKind.dance,
            recordId: 'd1',
          ),
          isTrue,
        );
      },
    );

    test(
      'detach clears local sync state but not publication history',
      () async {
        await repository.clearOnDetach();
        expect(await repository.getBaselineState(), isNull);
        expect(await repository.listBaselineEntries(), isEmpty);
        expect(await repository.listAliases(), isEmpty);
        expect(await repository.listReviewQueue(), isEmpty);
        expect(await repository.listPendingDeletions(), isEmpty);
        expect(await repository.listPublishedRecords(), hasLength(1));
      },
    );

    test(
      'transaction composition rolls back a coupled lifecycle failure',
      () async {
        final repos = CompendiumRepositories(db, contraTaxonomy);
        await expectLater(
          repository.transaction((tx) async {
            await tx.clearOnDetach();
            await repos.settings.set('sync_id', 'sync-1');
            throw StateError('simulated settings failure');
          }),
          throwsA(isA<StateError>()),
        );
        expect(await repository.getBaselineState(), isNotNull);
        expect(await repository.listBaselineEntries(), hasLength(1));
        expect(await repository.listAliases(), hasLength(1));
        expect(await repository.listReviewQueue(), hasLength(1));
        expect(await repository.listPendingDeletions(), hasLength(2));
        expect(await repository.listPublishedRecords(), hasLength(1));
        expect(await repos.settings.get('sync_id'), isNull);
      },
    );
  });

  group('SyncLocalRepository remapping and review queue', () {
    test(
      'remap unions publication markers and rewrites aliases to a fixed point',
      () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        final repository = SyncLocalRepository(db);

        await repository.upsertAlias(
          kind: SyncRecordKind.dance,
          losingId: 'older',
          survivingId: 'losing',
        );
        await repository.upsertAlias(
          kind: SyncRecordKind.dance,
          losingId: 'oldest',
          survivingId: 'older',
        );
        await repository.markPublished(
          kind: SyncRecordKind.dance,
          recordId: 'oldest',
        );
        await repository.markPublished(
          kind: SyncRecordKind.dance,
          recordId: 'older',
        );
        await repository.markPublished(
          kind: SyncRecordKind.dance,
          recordId: 'losing',
        );

        await repository.remapIdentity(
          kind: SyncRecordKind.dance,
          losingId: 'losing',
          survivingId: 'survivor',
        );

        expect(
          await repository.isPublished(
            kind: SyncRecordKind.dance,
            recordId: 'losing',
          ),
          isTrue,
        );
        expect(
          await repository.isPublished(
            kind: SyncRecordKind.dance,
            recordId: 'older',
          ),
          isTrue,
        );
        expect(
          await repository.isPublished(
            kind: SyncRecordKind.dance,
            recordId: 'oldest',
          ),
          isTrue,
        );
        expect(
          await repository.isPublished(
            kind: SyncRecordKind.dance,
            recordId: 'survivor',
          ),
          isTrue,
        );
        final aliases = await repository.listAliases();
        expect(aliases.map((row) => (row.losingId, row.survivingId)).toSet(), {
          ('oldest', 'survivor'),
          ('older', 'survivor'),
          ('losing', 'survivor'),
        });
      },
    );

    test('review queueing is idempotent for an immutable pair', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final repository = SyncLocalRepository(db);

      await repository.enqueueReview(
        kind: SyncRecordKind.dance,
        recordId: 'local',
        counterpartId: 'remote',
        reason: 'first',
        candidateBlob: '{"v":1}',
        candidateHash: 'h1',
        queuedAt: DateTime.utc(2026, 1, 1),
      );
      await repository.enqueueReview(
        kind: SyncRecordKind.dance,
        recordId: 'local',
        counterpartId: 'remote',
        reason: 'second',
        candidateBlob: '{"v":2}',
        candidateHash: 'h2',
        queuedAt: DateTime.utc(2026, 1, 2),
      );

      final rows = await repository.listReviewQueue();
      expect(rows, hasLength(1));
      expect(rows.single.reason, 'first');
      expect(rows.single.candidateHash, 'h1');

      await repository.markPublished(
        kind: SyncRecordKind.dance,
        recordId: 'survivor-2',
      );
      await repository.remapIdentity(
        kind: SyncRecordKind.dance,
        losingId: 'losing-2',
        survivingId: 'survivor-2',
      );
      expect(
        await repository.isPublished(
          kind: SyncRecordKind.dance,
          recordId: 'survivor-2',
        ),
        isTrue,
      );
    });
  });
}
