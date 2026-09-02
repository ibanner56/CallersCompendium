import 'package:drift/drift.dart';

import '../../sync/sync_record_kind.dart';
import '../database.dart';
import '../shareable_text.dart';

/// A polymorphic sync record identity.
typedef SyncRecordAddress = ({SyncRecordKind kind, String recordId});

/// A baseline hash pair to persist for one sync record.
class SyncBaselineEntry {
  const SyncBaselineEntry({
    required this.kind,
    required this.recordId,
    required this.wireHash,
    this.bodyHash,
  });

  final SyncRecordKind kind;
  final String recordId;
  final String wireHash;
  final String? bodyHash;
}

/// Local-only state for the Device Sync protocol.
///
/// The public methods each run in one transaction. Call [transaction] when a
/// caller must compose a lifecycle operation with other database writes.
class SyncLocalRepository {
  SyncLocalRepository(this._db);

  final CompendiumDatabase _db;

  Future<T> transaction<T>(
    Future<T> Function(SyncLocalTransaction transaction) action,
  ) => _db.transaction(() => action(SyncLocalTransaction._(_db)));

  Future<BaselineStateRow?> getBaselineState() async =>
      _db.select(_db.baselineState).getSingleOrNull();

  Future<List<BaselineEntryRow>> listBaselineEntries() =>
      _db.select(_db.baselineEntries).get();

  Future<void> replaceBaseline({
    required DateTime epoch,
    Iterable<SyncBaselineEntry> entries = const [],
  }) => transaction((tx) => tx.replaceBaseline(epoch: epoch, entries: entries));

  Future<void> resetEpoch({
    required DateTime epoch,
    Iterable<SyncBaselineEntry> entries = const [],
  }) => transaction((tx) => tx.resetEpoch(epoch: epoch, entries: entries));

  Future<void> clearBaseline() => transaction((tx) => tx.clearBaseline());

  Future<void> clearOnDetach() => transaction((tx) => tx.clearOnDetach());

  Future<void> clearForRestore({
    required Iterable<SyncRecordAddress> restoredRecords,
  }) =>
      transaction((tx) => tx.clearForRestore(restoredRecords: restoredRecords));

  Future<List<IdAliasRow>> listAliases() => _db.select(_db.idAliases).get();

  Future<void> upsertAlias({
    required SyncRecordKind kind,
    required String losingId,
    required String survivingId,
  }) => transaction(
    (tx) => tx.upsertAlias(
      kind: kind,
      losingId: losingId,
      survivingId: survivingId,
    ),
  );

  Future<List<PendingDeletionRow>> listPendingDeletions() =>
      _db.select(_db.pendingDeletions).get();

  Future<void> upsertPendingDeletion({
    required SyncRecordKind kind,
    required String recordId,
    required DateTime tombstonedAt,
    required String tombstoneHash,
    required String tombstoneBlob,
  }) => transaction(
    (tx) => tx.upsertPendingDeletion(
      kind: kind,
      recordId: recordId,
      tombstonedAt: tombstonedAt,
      tombstoneHash: tombstoneHash,
      tombstoneBlob: tombstoneBlob,
    ),
  );

  Future<List<ReviewQueueRow>> listReviewQueue() =>
      _db.select(_db.reviewQueue).get();

  Future<void> enqueueReview({
    required SyncRecordKind kind,
    required String recordId,
    required String counterpartId,
    required String reason,
    required String candidateBlob,
    required String candidateHash,
    required DateTime queuedAt,
  }) => transaction(
    (tx) => tx.enqueueReview(
      kind: kind,
      recordId: recordId,
      counterpartId: counterpartId,
      reason: reason,
      candidateBlob: candidateBlob,
      candidateHash: candidateHash,
      queuedAt: queuedAt,
    ),
  );

  Future<List<PublishedRecordRow>> listPublishedRecords() =>
      _db.select(_db.publishedRecords).get();

  Future<bool> isPublished({
    required SyncRecordKind kind,
    required String recordId,
  }) async =>
      (await (_db.select(_db.publishedRecords)..where(
            (row) => row.kind.equals(kind.name) & row.recordId.equals(recordId),
          ))
          .getSingleOrNull()) !=
      null;

  Future<void> markPublished({
    required SyncRecordKind kind,
    required String recordId,
  }) => transaction((tx) => tx.markPublished(kind: kind, recordId: recordId));

  Future<void> remapIdentity({
    required SyncRecordKind kind,
    required String losingId,
    required String survivingId,
  }) => transaction(
    (tx) => tx.remapIdentity(
      kind: kind,
      losingId: losingId,
      survivingId: survivingId,
    ),
  );
}

/// The transaction-bound operations of [SyncLocalRepository].
///
/// This type is passed to [SyncLocalRepository.transaction] so callers can
/// compose W4 state changes with writes owned by another repository.
class SyncLocalTransaction {
  SyncLocalTransaction._(this._db);

  final CompendiumDatabase _db;

  Future<void> replaceBaseline({
    required DateTime epoch,
    Iterable<SyncBaselineEntry> entries = const [],
  }) async {
    await _db.delete(_db.baselineState).go();
    await _db.delete(_db.baselineEntries).go();
    await _db
        .into(_db.baselineState)
        .insertOnConflictUpdate(
          BaselineStateCompanion.insert(id: const Value(1), epoch: epoch),
        );
    for (final entry in entries) {
      await _db
          .into(_db.baselineEntries)
          .insertOnConflictUpdate(
            BaselineEntriesCompanion.insert(
              kind: entry.kind,
              recordId: entry.recordId,
              wireHash: entry.wireHash,
              bodyHash: Value(entry.bodyHash),
            ),
          );
    }
  }

  Future<void> resetEpoch({
    required DateTime epoch,
    Iterable<SyncBaselineEntry> entries = const [],
  }) async {
    await clearBaseline();
    await replaceBaseline(epoch: epoch, entries: entries);
  }

  Future<void> clearBaseline() async {
    await _db.delete(_db.baselineState).go();
    await _db.delete(_db.baselineEntries).go();
    await _db.delete(_db.idAliases).go();
    await _db.delete(_db.reviewQueue).go();
  }

  Future<void> clearOnDetach() async {
    await clearBaseline();
    await _db.delete(_db.pendingDeletions).go();
  }

  Future<void> clearForRestore({
    required Iterable<SyncRecordAddress> restoredRecords,
  }) async {
    await clearBaseline();
    await revalidatePendingDeletions(restoredRecords: restoredRecords);
  }

  Future<void> revalidatePendingDeletions({
    required Iterable<SyncRecordAddress> restoredRecords,
  }) async {
    final retained = restoredRecords
        .map((record) => (record.kind, record.recordId))
        .toSet();
    final rows = await _db.select(_db.pendingDeletions).get();
    for (final row in rows) {
      if (retained.contains((row.kind, row.recordId))) continue;
      await (_db.delete(_db.pendingDeletions)..where(
            (table) =>
                table.kind.equals(row.kind.name) &
                table.recordId.equals(row.recordId),
          ))
          .go();
    }
  }

  Future<void> upsertAlias({
    required SyncRecordKind kind,
    required String losingId,
    required String survivingId,
  }) => _db
      .into(_db.idAliases)
      .insertOnConflictUpdate(
        IdAliasesCompanion.insert(
          kind: kind,
          losingId: losingId,
          survivingId: survivingId,
        ),
      );

  Future<void> upsertPendingDeletion({
    required SyncRecordKind kind,
    required String recordId,
    required DateTime tombstonedAt,
    required String tombstoneHash,
    required String tombstoneBlob,
  }) => _db
      .into(_db.pendingDeletions)
      .insertOnConflictUpdate(
        PendingDeletionsCompanion.insert(
          kind: kind,
          recordId: recordId,
          tombstonedAt: tombstonedAt,
          tombstoneHash: tombstoneHash,
          tombstoneBlob: normalizeShareableText(tombstoneBlob),
        ),
      );

  Future<void> enqueueReview({
    required SyncRecordKind kind,
    required String recordId,
    required String counterpartId,
    required String reason,
    required String candidateBlob,
    required String candidateHash,
    required DateTime queuedAt,
  }) => _db
      .into(_db.reviewQueue)
      .insert(
        ReviewQueueCompanion.insert(
          kind: kind,
          recordId: recordId,
          counterpartId: counterpartId,
          reason: reason,
          candidateBlob: candidateBlob,
          candidateHash: candidateHash,
          queuedAt: queuedAt,
        ),
        mode: InsertMode.insertOrIgnore,
      );

  Future<void> markPublished({
    required SyncRecordKind kind,
    required String recordId,
  }) => _db
      .into(_db.publishedRecords)
      .insertOnConflictUpdate(
        PublishedRecordsCompanion.insert(kind: kind, recordId: recordId),
      );

  Future<void> remapIdentity({
    required SyncRecordKind kind,
    required String losingId,
    required String survivingId,
  }) async {
    if (losingId == survivingId) return;
    final target = await _resolveAlias(
      kind: kind,
      recordId: survivingId,
      seen: {losingId},
    );
    final aliases = await (_db.select(
      _db.idAliases,
    )..where((row) => row.kind.equals(kind.name))).get();
    final rewrittenIds = <String>{losingId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final alias in aliases) {
        if (rewrittenIds.contains(alias.survivingId) &&
            rewrittenIds.add(alias.losingId)) {
          changed = true;
        }
      }
    }
    await (_db.update(_db.idAliases)..where(
          (row) =>
              row.kind.equals(kind.name) & row.survivingId.isIn(rewrittenIds),
        ))
        .write(IdAliasesCompanion(survivingId: Value(target)));
    await upsertAlias(kind: kind, losingId: losingId, survivingId: target);

    final published =
        await (_db.select(_db.publishedRecords)..where(
              (row) =>
                  row.kind.equals(kind.name) &
                  row.recordId.isIn({...rewrittenIds, target}),
            ))
            .get();
    if (published.isNotEmpty) {
      await markPublished(kind: kind, recordId: target);
    }
    await (_db.delete(_db.publishedRecords)..where(
          (row) =>
              row.kind.equals(kind.name) &
              row.recordId.isIn(rewrittenIds) &
              row.recordId.isNotIn({target}),
        ))
        .go();
  }

  Future<String> _resolveAlias({
    required SyncRecordKind kind,
    required String recordId,
    required Set<String> seen,
  }) async {
    var current = recordId;
    while (true) {
      final alias =
          await (_db.select(_db.idAliases)..where(
                (row) =>
                    row.kind.equals(kind.name) & row.losingId.equals(current),
              ))
              .getSingleOrNull();
      if (alias == null) return current;
      if (!seen.add(alias.survivingId)) {
        throw StateError('Cyclic sync ID alias for ${kind.name}: $recordId');
      }
      current = alias.survivingId;
    }
  }
}
