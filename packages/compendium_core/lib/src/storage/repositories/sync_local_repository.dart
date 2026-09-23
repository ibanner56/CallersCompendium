import 'package:drift/drift.dart';

import '../../sync/sync_codec.dart';
import '../../sync/sync_record_kind.dart';
import '../database.dart';
import '../existence.dart';

Iterable<List<T>> _chunked<T>(Iterable<T> values, int size) sync* {
  final list = values.toList(growable: false);
  for (var start = 0; start < list.length; start += size) {
    final end = start + size < list.length ? start + size : list.length;
    yield list.sublist(start, end);
  }
}

/// A polymorphic sync record identity.
typedef SyncRecordAddress = ({SyncRecordKind kind, String recordId});

/// The body-hash representation used by a persisted baseline entry.
enum SyncBaselineBodyHashVersion {
  /// The pre-W9 hash covered the complete record body, including projections.
  legacyFullBody,

  /// W9 hashes cover only the projection-neutral comparison body.
  comparison,
}

const _comparisonBodyHashPrefix = 'comparison-v1:';

SyncBaselineBodyHashVersion _storedBodyHashVersion(String? bodyHash) {
  if (bodyHash == null || bodyHash.startsWith(_comparisonBodyHashPrefix)) {
    return SyncBaselineBodyHashVersion.comparison;
  }
  return SyncBaselineBodyHashVersion.legacyFullBody;
}

String? _decodeStoredBodyHash(
  String? bodyHash,
  SyncBaselineBodyHashVersion version,
) {
  if (bodyHash == null ||
      version == SyncBaselineBodyHashVersion.legacyFullBody) {
    return bodyHash;
  }
  return bodyHash.substring(_comparisonBodyHashPrefix.length);
}

String? _encodeStoredBodyHash(
  String? bodyHash,
  SyncBaselineBodyHashVersion version,
) {
  if (bodyHash == null ||
      version == SyncBaselineBodyHashVersion.legacyFullBody) {
    return bodyHash;
  }
  return '$_comparisonBodyHashPrefix$bodyHash';
}

/// A baseline hash pair to persist for one sync record.
class SyncBaselineEntry {
  const SyncBaselineEntry({
    required this.kind,
    required this.recordId,
    required this.wireHash,
    this.bodyHash,
    this.bodyHashVersion = SyncBaselineBodyHashVersion.comparison,
  });

  final SyncRecordKind kind;
  final String recordId;
  final String wireHash;
  final String? bodyHash;
  final SyncBaselineBodyHashVersion bodyHashVersion;
}

/// Local-only state for the Device Sync protocol.
///
/// Public mutating methods each run in one transaction. Call [transaction]
/// when a caller must compose a lifecycle operation with other database writes.
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

  Future<Map<SyncRecordAddress, SyncBaselineEntry>> snapshotBaseline() async {
    final rows = await listBaselineEntries();
    return {
      for (final row in rows)
        (kind: row.kind, recordId: row.recordId): () {
          final version = _storedBodyHashVersion(row.bodyHash);
          return SyncBaselineEntry(
            kind: row.kind,
            recordId: row.recordId,
            wireHash: row.wireHash,
            bodyHash: _decodeStoredBodyHash(row.bodyHash, version),
            bodyHashVersion: version,
          );
        }(),
    };
  }

  Future<void> replaceBaseline({
    required String epoch,
    Iterable<SyncBaselineEntry> entries = const [],
  }) => transaction((tx) => tx.replaceBaseline(epoch: epoch, entries: entries));

  /// Advances only entries justified by an observed peer manifest.
  ///
  /// Entries not named by [entries] or [drop] are retained so an unresolved
  /// blob or malformed record remains retryable on the next pass.
  Future<void> advanceBaseline({
    required String epoch,
    Iterable<SyncBaselineEntry> entries = const [],
    Iterable<SyncRecordAddress> drop = const [],
  }) => transaction(
    (tx) => tx.advanceBaseline(epoch: epoch, entries: entries, drop: drop),
  );

  Future<void> resetEpoch({
    required String epoch,
    Iterable<SyncBaselineEntry> entries = const [],
  }) => transaction((tx) => tx.resetEpoch(epoch: epoch, entries: entries));

  Future<void> clearBaseline() => transaction((tx) => tx.clearBaseline());

  Future<void> clearOnDetach() => transaction((tx) => tx.clearOnDetach());

  Future<void> clearForRestore({
    required Iterable<SyncRecordAddress> restoredRecords,
    bool revalidatePending = true,
  }) => transaction(
    (tx) => tx.clearForRestore(
      restoredRecords: restoredRecords,
      revalidatePending: revalidatePending,
    ),
  );

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

  Future<PendingDeletionRow?> getPendingDeletion({
    required SyncRecordKind kind,
    required String recordId,
  }) =>
      (_db.select(_db.pendingDeletions)..where(
            (row) => row.kind.equals(kind.name) & row.recordId.equals(recordId),
          ))
          .getSingleOrNull();

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

  Future<void> deletePendingDeletion({
    required SyncRecordKind kind,
    required String recordId,
  }) => transaction(
    (tx) => tx.deletePendingDeletion(kind: kind, recordId: recordId),
  );

  Future<List<ReviewQueueRow>> listReviewQueue() =>
      _db.select(_db.reviewQueue).get();

  Future<ReviewQueueRow?> getReviewQueue({
    required SyncRecordKind kind,
    required String recordId,
    required String counterpartId,
  }) =>
      (_db.select(_db.reviewQueue)..where(
            (row) =>
                row.kind.equals(kind.name) &
                row.recordId.equals(recordId) &
                row.counterpartId.equals(counterpartId),
          ))
          .getSingleOrNull();

  Future<void> enqueueReview({
    required SyncRecordKind kind,
    required String recordId,
    required String counterpartId,
    required String reason,
    required String candidateBlob,
    required String candidateHash,
    String? localHash,
    required DateTime queuedAt,
  }) => transaction(
    (tx) => tx.enqueueReview(
      kind: kind,
      recordId: recordId,
      counterpartId: counterpartId,
      reason: reason,
      candidateBlob: candidateBlob,
      candidateHash: candidateHash,
      localHash: localHash,
      queuedAt: queuedAt,
    ),
  );

  Future<void> deleteReview({
    required SyncRecordKind kind,
    required String recordId,
    required String counterpartId,
  }) => transaction(
    (tx) => tx.deleteReview(
      kind: kind,
      recordId: recordId,
      counterpartId: counterpartId,
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

  Future<void> markPublishedAll(Iterable<SyncRecordAddress> records) =>
      transaction((tx) => tx.markPublishedAll(records));

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

  /// Retires aliases whose losing IDs are absent from every current peer
  /// manifest. The caller must only invoke this after all peer manifests for
  /// the current epoch were verified; an unavailable manifest is not evidence
  /// that it dropped an ID.
  Future<void> retireAliases({required Set<SyncRecordAddress> peerAddresses}) =>
      transaction((tx) => tx.retireAliases(peerAddresses: peerAddresses));

  Future<String> resolveAlias({
    required SyncRecordKind kind,
    required String recordId,
  }) => transaction((tx) => tx.resolveAlias(kind: kind, recordId: recordId));
}

/// The transaction-bound operations of [SyncLocalRepository].
///
/// This type is passed to [SyncLocalRepository.transaction] so callers can
/// compose W4 state changes with writes owned by another repository.
class SyncLocalTransaction {
  SyncLocalTransaction._(this._db);

  final CompendiumDatabase _db;

  Future<void> replaceBaseline({
    required String epoch,
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
              bodyHash: Value(
                _encodeStoredBodyHash(entry.bodyHash, entry.bodyHashVersion),
              ),
            ),
          );
    }
  }

  Future<void> advanceBaseline({
    required String epoch,
    Iterable<SyncBaselineEntry> entries = const [],
    Iterable<SyncRecordAddress> drop = const [],
  }) async {
    final state = await _db.select(_db.baselineState).getSingleOrNull();
    if (state == null || state.epoch != epoch) {
      throw StateError('cannot advance a baseline from a different epoch');
    }
    for (final address in drop) {
      await (_db.delete(_db.baselineEntries)..where(
            (row) =>
                row.kind.equals(address.kind.name) &
                row.recordId.equals(address.recordId),
          ))
          .go();
    }
    for (final entry in entries) {
      await _db
          .into(_db.baselineEntries)
          .insertOnConflictUpdate(
            BaselineEntriesCompanion.insert(
              kind: entry.kind,
              recordId: entry.recordId,
              wireHash: entry.wireHash,
              bodyHash: Value(
                _encodeStoredBodyHash(entry.bodyHash, entry.bodyHashVersion),
              ),
            ),
          );
    }
  }

  Future<void> resetEpoch({
    required String epoch,
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
    bool revalidatePending = true,
  }) async {
    await clearBaseline();
    if (revalidatePending) {
      await revalidatePendingDeletions(restoredRecords: restoredRecords);
    }
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
  }) async {
    // A self-alias is never meaningful and is actively dangerous: `_resolveAlias`
    // seeds its `seen` set with the id it was asked about, so a row mapping an
    // id to itself would be re-read on every hop of a chain that starts
    // elsewhere and spin inside an open write transaction.
    if (losingId == survivingId) return;
    await _db
        .into(_db.idAliases)
        .insertOnConflictUpdate(
          IdAliasesCompanion.insert(
            kind: kind,
            losingId: losingId,
            survivingId: survivingId,
          ),
        );
  }

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
          tombstoneBlob: tombstoneBlob,
        ),
      );

  Future<void> deletePendingDeletion({
    required SyncRecordKind kind,
    required String recordId,
  }) =>
      (_db.delete(_db.pendingDeletions)..where(
            (row) => row.kind.equals(kind.name) & row.recordId.equals(recordId),
          ))
          .go();

  Future<void> enqueueReview({
    required SyncRecordKind kind,
    required String recordId,
    required String counterpartId,
    required String reason,
    required String candidateBlob,
    required String candidateHash,
    String? localHash,
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
          localHash: Value(localHash),
          queuedAt: queuedAt,
        ),
        mode: InsertMode.insertOrIgnore,
      );

  Future<void> deleteReview({
    required SyncRecordKind kind,
    required String recordId,
    required String counterpartId,
  }) async {
    await (_db.delete(_db.reviewQueue)..where(
          (row) =>
              row.kind.equals(kind.name) &
              row.recordId.equals(recordId) &
              row.counterpartId.equals(counterpartId),
        ))
        .go();
  }

  Future<void> markPublished({
    required SyncRecordKind kind,
    required String recordId,
  }) => _db
      .into(_db.publishedRecords)
      .insertOnConflictUpdate(
        PublishedRecordsCompanion.insert(kind: kind, recordId: recordId),
      );

  Future<void> markPublishedAll(Iterable<SyncRecordAddress> records) async {
    final rows = [
      for (final record in records)
        PublishedRecordsCompanion.insert(
          kind: record.kind,
          recordId: record.recordId,
        ),
    ];
    if (rows.isEmpty) return;
    await _db.batch((batch) {
      batch.insertAll(
        _db.publishedRecords,
        rows,
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

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
    for (final chunk in _chunked(rewrittenIds, 500)) {
      await (_db.update(_db.idAliases)..where(
            (row) => row.kind.equals(kind.name) & row.survivingId.isIn(chunk),
          ))
          .write(IdAliasesCompanion(survivingId: Value(target)));
    }
    await upsertAlias(kind: kind, losingId: losingId, survivingId: target);

    final publishedIds = {...rewrittenIds, target};
    for (final chunk in _chunked(publishedIds, 500)) {
      final published =
          await (_db.select(_db.publishedRecords)..where(
                (row) => row.kind.equals(kind.name) & row.recordId.isIn(chunk),
              ))
              .get();
      if (published.isNotEmpty) {
        await markPublished(kind: kind, recordId: target);
        break;
      }
    }
  }

  Future<void> retireAliases({
    required Set<SyncRecordAddress> peerAddresses,
  }) async {
    final aliases = await _db.select(_db.idAliases).get();
    final aliasesByAddress = {
      for (final alias in aliases)
        (kind: alias.kind, recordId: alias.losingId): alias,
    };
    final retainedAddresses = <SyncRecordAddress>{};
    for (final peerAddress in peerAddresses) {
      var current = peerAddress;
      final seen = <SyncRecordAddress>{};
      while (seen.add(current)) {
        final alias = aliasesByAddress[current];
        if (alias == null) break;
        retainedAddresses.add(current);
        current = (kind: alias.kind, recordId: alias.survivingId);
      }
    }
    for (final alias in aliases) {
      final address = (kind: alias.kind, recordId: alias.losingId);
      if (retainedAddresses.contains(address)) continue;
      await (_db.delete(_db.idAliases)..where(
            (row) =>
                row.kind.equals(alias.kind.name) &
                row.losingId.equals(alias.losingId),
          ))
          .go();
    }
  }

  Future<String> resolveAlias({
    required SyncRecordKind kind,
    required String recordId,
  }) => _resolveAlias(kind: kind, recordId: recordId, seen: {recordId});

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

/// Returns whether a record has ever been named by a successfully prepared
/// publication. Repository hard-delete paths use this marker instead of the
/// sync baseline because the marker survives reset, detach, and restore.
Future<bool> isPublishedSyncRecord(
  CompendiumDatabase db, {
  required SyncRecordKind kind,
  required String recordId,
}) async =>
    (await (db.select(db.publishedRecords)..where(
          (row) => row.kind.equals(kind.name) & row.recordId.equals(recordId),
        ))
        .getSingleOrNull()) !=
    null;

Future<Set<String>> publishedSyncRecordIds(
  CompendiumDatabase db, {
  required SyncRecordKind kind,
  required Iterable<String> recordIds,
}) async {
  final ids = recordIds.toSet().toList(growable: false);
  if (ids.isEmpty) return const {};
  final published = <String>{};
  const chunkSize = 500;
  for (var start = 0; start < ids.length; start += chunkSize) {
    final end = start + chunkSize < ids.length ? start + chunkSize : ids.length;
    final chunk = ids.sublist(start, end);
    final rows =
        await (db.select(db.publishedRecords)..where(
              (row) => row.kind.equals(kind.name) & row.recordId.isIn(chunk),
            ))
            .get();
    published.addAll([for (final row in rows) row.recordId]);
  }
  return published;
}

/// Clears a pending tombstone for a deliberate local act on the record.
///
/// Two acts qualify, and sync-spec §6.8 admits no others: an explicit restore
/// from Recently Deleted, and a deliberate local user edit — see
/// [cancelPendingSyncDeletionForLocalEdit], which wraps this call with the
/// existence stamp that edit path also owes.
///
/// Sync-originated body/reference writes deliberately do not call this helper;
/// a newer [updatedAt] alone is not evidence that the user revived a record.
/// Neither is an import, an archive restore, or any automatic write: the gate
/// is the provenance of the write, which only the caller knows.
Future<void> clearPendingSyncDeletion(
  CompendiumDatabase db, {
  required SyncRecordKind kind,
  required String recordId,
}) =>
    (db.delete(db.pendingDeletions)..where(
          (row) => row.kind.equals(kind.name) & row.recordId.equals(recordId),
        ))
        .go();

/// Reads the `existenceAt` of the tombstone held for [recordId], if any.
///
/// `null` means there is no hold — or that its retained blob will not decode,
/// which is deliberately the same answer here. A tombstone that cannot be
/// decoded cannot be stamped above, and `revalidatePendingDeletions` owns that
/// failure: it raises on exactly this condition. Reporting it as "no hold"
/// leaves the row in place for that path to diagnose, where treating it as a
/// cancellable hold would destroy the deferred deletion with nothing left to
/// re-derive it from. `_cancelOutrankedPendingDeletion` swallows the same
/// failure for the same reason.
Future<DateTime?> heldTombstoneExistenceAt(
  CompendiumDatabase db, {
  required SyncRecordKind kind,
  required String recordId,
}) async {
  final pending =
      await (db.select(db.pendingDeletions)..where(
            (row) => row.kind.equals(kind.name) & row.recordId.equals(recordId),
          ))
          .getSingleOrNull();
  if (pending == null) return null;
  try {
    return decodeSyncRecordBlob(pending.tombstoneBlob).existenceAt;
  } on Object {
    return null;
  }
}

/// Cancels a pending tombstone because the user deliberately edited the record
/// it names (sync-spec §6.8), stamping the existence that cancellation owes.
///
/// Returns whether a hold was found and cancelled, so a caller can tell "no
/// hold" from "hold released" without a second query.
///
/// ## Why this path exists at all
///
/// §6.8 holds a peer's tombstone for a still-cited entity in
/// `pending_deletions`, keeps the row **live** locally, and advertises the
/// entity as a tombstone until its last citation goes. The row being live is
/// what makes this necessary: it never appears in Recently Deleted, so
/// `restore()` — §6.8's other cancellation — can never reach it. Without this,
/// an edit to a held record is overwritten by the retained tombstone body the
/// moment the last citation clears, and the record is deleted with the user's
/// work inside it.
///
/// ## The gate is provenance, never recency
///
/// Callers opt in; nothing here infers intent. "This write is a deliberate user
/// edit" is knowledge only the call site has, and the same repository method
/// serves imports, archive restore and automatic back-population. Gating on a
/// newer `updatedAt` instead is forbidden outright: reference rewriting after
/// reconciliation, merge-by-recency and the dance merge's scalar recency all
/// advance `updatedAt` with nobody having touched the record, so a recency gate
/// would let a third device silently reverse another's deletion.
///
/// [table] and [keyColumn] name the row to stamp; [at] is the write's own
/// instant. See [raiseExistenceAbove] for why the tombstone's own `existenceAt`
/// has to floor that stamp.
Future<bool> cancelPendingSyncDeletionForLocalEdit(
  CompendiumDatabase db, {
  required SyncRecordKind kind,
  required String recordId,
  required TableInfo<Table, dynamic> table,
  required String keyColumn,
  required DateTime at,
}) async {
  final floor = await heldTombstoneExistenceAt(
    db,
    kind: kind,
    recordId: recordId,
  );
  if (floor == null) return false;
  await raiseExistenceAbove(
    db,
    table: table,
    keyColumn: keyColumn,
    key: recordId,
    at: at,
    floor: floor,
  );
  await clearPendingSyncDeletion(db, kind: kind, recordId: recordId);
  return true;
}
