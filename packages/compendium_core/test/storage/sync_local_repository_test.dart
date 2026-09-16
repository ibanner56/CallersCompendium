import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/storage/database.dart'
    show BaselineEntriesCompanion, BaselineStateCompanion;
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'test_database.dart';

class _SqliteBindLimitGuard extends QueryInterceptor {
  static const maxVariables = 999;

  void _check(List<Object?> args) {
    if (args.length > maxVariables) {
      throw StateError(
        'test SQLite bind limit exceeded: ${args.length} > $maxVariables',
      );
    }
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _check(args);
    return super.runSelect(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _check(args);
    return super.runUpdate(executor, statement, args);
  }
}

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

  test(
    'distinguishes legacy full-body hashes from W9 comparison hashes',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final repository = SyncLocalRepository(db);
      final address = (kind: SyncRecordKind.dance, recordId: 'legacy');

      await db
          .into(db.baselineEntries)
          .insert(
            BaselineEntriesCompanion.insert(
              kind: address.kind,
              recordId: address.recordId,
              wireHash: 'legacy-wire',
              bodyHash: const Value('legacy-full-body'),
            ),
          );

      final legacy = (await repository.snapshotBaseline()).values.single;
      expect(legacy.bodyHash, 'legacy-full-body');
      expect(
        legacy.bodyHashVersion,
        SyncBaselineBodyHashVersion.legacyFullBody,
      );

      await repository.replaceBaseline(
        epoch: 'epoch-1',
        entries: [
          SyncBaselineEntry(
            kind: address.kind,
            recordId: address.recordId,
            wireHash: 'comparison-wire',
            bodyHash: 'comparison-body',
          ),
        ],
      );

      final comparison = (await repository.snapshotBaseline()).values.single;
      expect(comparison.bodyHash, 'comparison-body');
      expect(
        comparison.bodyHashVersion,
        SyncBaselineBodyHashVersion.comparison,
      );
    },
  );

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

  test(
    'preserves opaque tombstone bytes alongside their supplied hash',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final repository = SyncLocalRepository(db);
      const blob = '{"id":"e\u0301\u0001"}';

      await repository.upsertPendingDeletion(
        kind: SyncRecordKind.dance,
        recordId: 'opaque',
        tombstonedAt: DateTime.utc(2026, 1, 15),
        tombstoneHash: 'hash-for-opaque-blob',
        tombstoneBlob: blob,
      );

      final row = (await repository.listPendingDeletions()).single;
      expect(row.tombstoneBlob, blob);
      expect(row.tombstoneHash, 'hash-for-opaque-blob');
    },
  );

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
        localHash: 'local-h1',
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
      'remaps a large alias closure without exceeding SQLite bind limits',
      () async {
        final db = CompendiumDatabase(
          NativeDatabase.memory().interceptWith(_SqliteBindLimitGuard()),
        );
        addTearDown(db.close);
        final repository = SyncLocalRepository(db);
        const total = 1001;

        await repository.transaction((tx) async {
          for (var i = 0; i < total; i++) {
            await tx.upsertAlias(
              kind: SyncRecordKind.dance,
              losingId: 'alias-${i.toString().padLeft(4, '0')}',
              survivingId: 'alias-${(i + 1).toString().padLeft(4, '0')}',
            );
          }
          await tx.markPublished(
            kind: SyncRecordKind.dance,
            recordId: 'alias-0000',
          );
        });

        await repository.remapIdentity(
          kind: SyncRecordKind.dance,
          losingId: 'alias-1001',
          survivingId: 'survivor',
        );

        expect(
          await repository.resolveAlias(
            kind: SyncRecordKind.dance,
            recordId: 'alias-0000',
          ),
          'survivor',
        );
        expect(
          await repository.isPublished(
            kind: SyncRecordKind.dance,
            recordId: 'survivor',
          ),
          isTrue,
        );
        expect(
          (await repository.listAliases())
              .where((row) => row.kind == SyncRecordKind.dance)
              .every((row) => row.survivingId == 'survivor'),
          isTrue,
        );
      },
    );

    test(
      'remap unions publication markers and rewrites aliases to a fixed point',
      () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        final repository = SyncLocalRepository(db);

        await repository.upsertAlias(
          kind: SyncRecordKind.dance,
          losingId: 'a',
          survivingId: 'b',
        );
        await repository.upsertAlias(
          kind: SyncRecordKind.dance,
          losingId: 'b',
          survivingId: 'c',
        );
        expect(
          await repository.resolveAlias(
            kind: SyncRecordKind.dance,
            recordId: 'a',
          ),
          'c',
        );
        await repository.markPublished(
          kind: SyncRecordKind.dance,
          recordId: 'a',
        );

        await repository.remapIdentity(
          kind: SyncRecordKind.dance,
          losingId: 'c',
          survivingId: 'survivor',
        );

        expect(
          await repository.isPublished(
            kind: SyncRecordKind.dance,
            recordId: 'a',
          ),
          isTrue,
        );
        expect(
          await repository.isPublished(
            kind: SyncRecordKind.dance,
            recordId: 'b',
          ),
          isFalse,
        );
        expect(
          await repository.isPublished(
            kind: SyncRecordKind.dance,
            recordId: 'c',
          ),
          isFalse,
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
          ('a', 'survivor'),
          ('b', 'survivor'),
          ('c', 'survivor'),
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
        localHash: 'local-h1',
        queuedAt: DateTime.utc(2026, 1, 1),
      );
      await repository.enqueueReview(
        kind: SyncRecordKind.dance,
        recordId: 'local',
        counterpartId: 'remote',
        reason: 'second',
        candidateBlob: '{"v":2}',
        candidateHash: 'h2',
        localHash: 'local-h2',
        queuedAt: DateTime.utc(2026, 1, 2),
      );

      final rows = await repository.listReviewQueue();
      expect(rows, hasLength(1));
      expect(rows.single.reason, 'first');
      expect(rows.single.candidateHash, 'h1');
      expect(rows.single.localHash, 'local-h1');

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

    test('marks publication records with one database batch', () async {
      final counter = _PublishedRecordBatchCounter();
      final db = openCountingTestDatabase(counter);
      addTearDown(db.close);
      final repository = SyncLocalRepository(db);
      counter.reset();

      await repository.markPublishedAll([
        for (var index = 0; index < 3; index++)
          (kind: SyncRecordKind.dance, recordId: 'dance-$index'),
      ]);

      expect(counter.batchedSqlCounts, [1]);
      expect(counter.individualInserts, 0);
      expect(await repository.listPublishedRecords(), hasLength(3));
    });
  });

  test('retires aliases by peer-manifest content without markers', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final repository = SyncLocalRepository(db);

    await repository.upsertAlias(
      kind: SyncRecordKind.tag,
      losingId: 'old-tag',
      survivingId: 'new-tag',
    );
    await repository.markPublished(
      kind: SyncRecordKind.tag,
      recordId: 'old-tag',
    );

    await repository.retireAliases(
      peerAddresses: const {
        (kind: SyncRecordKind.tag, recordId: 'unrelated-tag'),
      },
    );

    expect(await repository.listAliases(), isEmpty);
    expect(
      await repository.isPublished(
        kind: SyncRecordKind.tag,
        recordId: 'old-tag',
      ),
      isTrue,
    );
  });

  test('retains aliases named by a current peer manifest', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final repository = SyncLocalRepository(db);

    await repository.upsertAlias(
      kind: SyncRecordKind.tag,
      losingId: 'old-tag',
      survivingId: 'new-tag',
    );

    await repository.retireAliases(
      peerAddresses: const {(kind: SyncRecordKind.tag, recordId: 'old-tag')},
    );

    expect(await repository.listAliases(), hasLength(1));
  });

  test('retains every alias in a peer-advertised alias chain', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final repository = SyncLocalRepository(db);

    await repository.upsertAlias(
      kind: SyncRecordKind.tag,
      losingId: 'a-tag',
      survivingId: 'b-tag',
    );
    await repository.upsertAlias(
      kind: SyncRecordKind.tag,
      losingId: 'b-tag',
      survivingId: 'c-tag',
    );

    await repository.retireAliases(
      peerAddresses: const {(kind: SyncRecordKind.tag, recordId: 'a-tag')},
    );

    expect(
      (await repository.listAliases())
          .map((alias) => (alias.losingId, alias.survivingId))
          .toSet(),
      {('a-tag', 'b-tag'), ('b-tag', 'c-tag')},
    );
  });
}

final class _PublishedRecordBatchCounter extends QueryInterceptor {
  final batchedSqlCounts = <int>[];
  int individualInserts = 0;

  void reset() {
    batchedSqlCounts.clear();
    individualInserts = 0;
  }

  bool _matches(String statement) =>
      statement.toLowerCase().contains('published_records');

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) {
    final matchingStatements = statements.statements.where(_matches).length;
    if (matchingStatements > 0) {
      batchedSqlCounts.add(matchingStatements);
    }
    return super.runBatched(executor, statements);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (_matches(statement)) individualInserts++;
    return super.runInsert(executor, statement, args);
  }
}
