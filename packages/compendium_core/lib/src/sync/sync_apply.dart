import '../storage/repositories/sync_local_repository.dart';
import 'sync_admission.dart';
import 'sync_codec.dart';
import 'sync_merge.dart';
import 'sync_quarantine.dart';
import 'sync_record_kind.dart';
import 'sync_report.dart';

/// The transaction-facing value passed to an inbound storage adapter.
class SyncApplyRecord {
  const SyncApplyRecord({
    required this.address,
    required this.body,
    required this.updatedAt,
    required this.deletedAt,
    required this.existenceAt,
    this.sourceBlob,
  });

  final SyncRecordAddress address;
  final Map<String, Object?> body;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime existenceAt;

  /// The post-admission canonical wire candidate that produced this record.
  ///
  /// [body] may contain device-local fields overlaid from the current row,
  /// so pending tombstones must retain this source rather than re-encoding
  /// [body] as if it were the peer's blob.
  final SyncRecordBlob? sourceBlob;
}

/// The narrow storage seam required by the core apply engine.
///
/// An app adapter implements [transaction] with the database transaction that
/// owns its repositories. [write] is responsible for mapping the already
/// validated, shareable overlay to parent and join tables. The engine invokes
/// [rebuildDerivedIndexes] once after the batch has been applied.
abstract interface class SyncApplyStorage {
  Future<T> transaction<T>(Future<T> Function() action);

  Future<Map<String, Object?>?> read(SyncRecordAddress address);

  Future<void> write(SyncApplyRecord record);

  Future<void> rebuildDerivedIndexes();
}

/// Optional storage seam for guarding an inbound apply against a local edit
/// that happened after the coordinator's merge snapshot.
abstract interface class SyncApplyConcurrencyStorage
    implements SyncApplyStorage {
  Future<Map<SyncRecordAddress, SyncMergeCandidate?>> snapshotCandidates();
}

/// Optional extension implemented by adapters that can return a recoverable
/// report while applying a record.
abstract interface class SyncApplyReportingStorage implements SyncApplyStorage {
  /// Validates references before a write can mutate any repository rows.
  ///
  /// Returning a report skips only this record; the outer batch transaction
  /// remains available for valid records.
  Future<SyncReport?> validateInboundReferences(
    SyncApplyRecord record, {
    Set<SyncRecordAddress> inboundLiveAddresses = const {},
    Set<SyncRecordAddress> inboundAddresses = const {},
    Map<SyncRecordAddress, SyncApplyRecord> inboundRecords = const {},
  }) async => null;

  /// Writes one record and optionally reports a recoverable reference repair.
  ///
  /// The default keeps lightweight adapters source-compatible; concrete
  /// database adapters can return a report when they repair a dangling
  /// reference while still applying the record.
  Future<SyncReport?> writeWithReport(SyncApplyRecord record) async {
    await write(record);
    return null;
  }
}

/// Optional two-phase writer for stores whose join rows have foreign keys to
/// other records in the same inbound batch.
///
/// References are validated to a fixed point before any parent row is written.
/// Parent rows are then written, followed by references and join rows. This
/// permits forward references and cycles without weakening the database's
/// foreign-key checks.
abstract interface class SyncApplyBatchStorage
    implements SyncApplyReportingStorage {
  Future<SyncReport?> writeParentWithReport(SyncApplyRecord record) =>
      writeWithReport(record);

  Future<SyncReport?> writeJoinsWithReport(SyncApplyRecord record) async =>
      null;
}

/// Optional seam that lets the engine undo a record's parent write when the
/// second phase of that same record's apply fails.
///
/// The two-phase order — every parent before any join, so a reference between
/// two records of the same batch resolves whichever way it points — means a
/// record's parent and join writes land in two separate savepoints. Catching a
/// join failure and continuing would otherwise commit the peer's parent row
/// beside this device's existing join rows, at the peer's `updatedAt`: a body
/// that matches neither side at a timestamp that ties, which §6.3 declines to
/// resolve and which therefore never converges.
///
/// The token is opaque on purpose. The engine orchestrates; only the adapter
/// knows the schema, so only the adapter decides what has to be captured.
abstract interface class SyncApplyRestorableStorage
    implements SyncApplyBatchStorage {
  /// Captures whatever [restorePreImage] needs to put [address] back the way
  /// it is now, or `null` when this kind has no separate join phase to undo.
  Future<Object?> capturePreImage(SyncRecordAddress address);

  /// Restores the state [capturePreImage] returned, removing the row entirely
  /// when the record did not exist at capture time.
  Future<void> restorePreImage(SyncRecordAddress address, Object? preImage);
}

/// Result of the transaction-bound W7 reconciliation phase.
class SyncApplyPreparation {
  const SyncApplyPreparation({
    required this.candidates,
    this.reports = const [],
  });

  final List<SyncMergeCandidate> candidates;
  final List<SyncReport> reports;
}

/// Optional W7 extension for stores that reconcile aliases and natural-key
/// collisions before dependency validation and parent/join writes.
abstract interface class SyncApplyReconciliationStorage
    implements SyncApplyBatchStorage {
  Future<SyncApplyPreparation> reconcileInbound(
    List<SyncMergeCandidate> candidates, {
    Map<SyncRecordAddress, String?>? expectedWireHashes,
  });

  /// Provides the tombstones the batch will actually write.
  ///
  /// Adapters use this to suppress a citation whose owner is itself being
  /// tombstoned here, so the set has to be the one the write pass settled on:
  /// reconciliation prepares candidates that both the batch-wide fixed point
  /// and the later per-group settling can still reject, and naming a tombstone
  /// that is then dropped would delete a record whose live owner still cites
  /// it. The engine therefore calls this only after every group has settled.
  Future<void> setInboundTombstoneContext(
    Set<SyncRecordAddress> tombstonedAddresses,
  ) async {}

  /// Clears batch-only reconciliation context after the transaction ends.
  ///
  /// The default keeps lightweight adapters source-compatible; database
  /// adapters use it to prevent one inbound batch's tombstones from affecting
  /// a later batch.
  Future<void> clearReconciliationContext() async {}
}

/// Result of applying a batch. A report for one record does not reject the
/// other validated records in the same batch.
class SyncApplyResult {
  const SyncApplyResult({required this.applied, required this.reports});

  final List<SyncRecordAddress> applied;
  final List<SyncReport> reports;
}

/// A hook invoked after one record has been written but before its transaction
/// can continue. The app isolate uses this only as an interruption seam.
typedef SyncApplyWriteHook = Future<void> Function(SyncApplyRecord record);

/// Transaction-bound read-modify-write application for validated blobs.
class SyncApplyEngine {
  const SyncApplyEngine({this.onAfterWrite, this.now = _syncNowUtc});

  final SyncApplyWriteHook? onAfterWrite;
  final DateTime Function() now;

  /// Applies [candidates] in dependency order inside one transaction.
  Future<SyncApplyResult> apply({
    required Iterable<SyncMergeCandidate> candidates,
    required SyncApplyStorage storage,
    Map<SyncRecordAddress, String?>? expectedWireHashes,
  }) async {
    final applied = <SyncRecordAddress>[];
    final reports = <SyncReport>[];
    final windowEnd = syncQuarantineWindowEnd(now());
    final ordered = <SyncMergeCandidate>[];
    for (final candidate in candidates) {
      final assessment = const SyncQuarantineClassifier().assess(
        candidate,
        windowEnd: windowEnd,
      );
      if (assessment.isQuarantined) {
        reports.add(
          SyncReport(
            // Not `malformedRecord`: the blob decoded and validated fine, its
            // clock is implausible. A consumer filtering by code has to be
            // able to tell "this peer's clock is wrong" from "this blob is
            // corrupt" — they call for different things from the user.
            code: SyncReportCode.quarantinedRecord,
            kind: candidate.blob.kind,
            recordId: candidate.blob.id,
            peerId: candidate.peerId,
            message:
                'Inbound record timestamp exceeded the local clock window.',
          ),
        );
        continue;
      }
      ordered.add(candidate);
    }
    ordered.sort(_compareCandidates);
    final admitted = _admitCandidates(ordered, reports);

    try {
      if (admitted.isNotEmpty) {
        await storage.transaction(() async {
          final guarded = await _guardConcurrentCandidates(
            candidates: admitted,
            storage: storage,
            expectedWireHashes: expectedWireHashes,
            reports: reports,
          );
          if (storage is SyncApplyBatchStorage) {
            await _applyInPhases(
              candidates: guarded,
              storage: storage,
              expectedWireHashes: expectedWireHashes,
              applied: applied,
              reports: reports,
            );
          } else {
            for (final candidate in guarded) {
              final current = await storage.read(candidate.address) ?? const {};
              final merged = _overlay(
                Map<String, Object?>.from(current),
                Map<String, Object?>.from(candidate.blob.body),
              );
              try {
                final applyRecord = SyncApplyRecord(
                  address: candidate.address,
                  body: merged,
                  updatedAt: candidate.updatedAt,
                  deletedAt: candidate.blob.deletedAt,
                  existenceAt: candidate.existenceAt,
                  sourceBlob: candidate.blob,
                );
                final reportingStorage = storage is SyncApplyReportingStorage
                    ? storage
                    : null;
                final referenceReport = reportingStorage == null
                    ? null
                    : await reportingStorage.validateInboundReferences(
                        applyRecord,
                      );
                if (referenceReport != null) {
                  reports.add(referenceReport);
                  continue;
                }
                final writeReport = reportingStorage == null
                    ? await _writeWithoutReport(storage, applyRecord)
                    : await reportingStorage.writeWithReport(applyRecord);
                if (writeReport != null) reports.add(writeReport);
                final afterWrite = onAfterWrite;
                if (afterWrite != null) await afterWrite(applyRecord);
              } on FormatException catch (error) {
                reports.add(
                  SyncReport(
                    code: SyncReportCode.malformedRecord,
                    kind: candidate.blob.kind,
                    recordId: candidate.blob.id,
                    peerId: candidate.peerId,
                    message:
                        'Inbound record could not be decoded: ${error.message}.',
                  ),
                );
                continue;
              } on ArgumentError catch (error) {
                reports.add(
                  SyncReport(
                    code: SyncReportCode.malformedRecord,
                    kind: candidate.blob.kind,
                    recordId: candidate.blob.id,
                    peerId: candidate.peerId,
                    message: 'Inbound record was invalid: $error.',
                  ),
                );
                continue;
              } on StateError catch (error) {
                reports.add(
                  SyncReport(
                    code: SyncReportCode.unresolvedReference,
                    kind: candidate.blob.kind,
                    recordId: candidate.blob.id,
                    peerId: candidate.peerId,
                    message:
                        'Inbound record referenced unavailable data: $error.',
                  ),
                );
                continue;
              }

              applied.add(candidate.address);
            }
          }
          if (applied.isNotEmpty) {
            await storage.rebuildDerivedIndexes();
          }
        });
      }
    } on _NamedTombstoneWriteFailure catch (failure) {
      // The transaction rolled back, so nothing was applied; report the batch
      // rather than throwing a pass. See [_guardNamedTombstone].
      applied.clear();
      reports.add(
        SyncReport(
          code: SyncReportCode.unresolvedReference,
          kind: failure.address.kind,
          recordId: failure.address.recordId,
          message:
              'A tombstone other records had already been reconciled against '
              'could not be written, so the batch was rolled back and will be '
              'retried.',
        ),
      );
    } finally {
      if (storage is SyncApplyReconciliationStorage) {
        await storage.clearReconciliationContext();
      }
    }

    return SyncApplyResult(
      applied: List.unmodifiable(applied),
      reports: List.unmodifiable(reports),
    );
  }

  List<SyncMergeCandidate> _admitCandidates(
    Iterable<SyncMergeCandidate> candidates,
    List<SyncReport> reports,
  ) {
    final admitted = <SyncMergeCandidate>[];
    for (final candidate in candidates) {
      final admission = admitSyncInboundCandidate(candidate);
      final report = admission.report;
      if (report != null) {
        reports.add(report);
      } else {
        admitted.add(admission.candidate!);
      }
    }
    return admitted;
  }

  Future<List<SyncMergeCandidate>> _guardConcurrentCandidates({
    required List<SyncMergeCandidate> candidates,
    required SyncApplyStorage storage,
    required Map<SyncRecordAddress, String?>? expectedWireHashes,
    required List<SyncReport> reports,
  }) async {
    if (expectedWireHashes == null || expectedWireHashes.isEmpty) {
      return candidates;
    }
    if (storage is! SyncApplyConcurrencyStorage) {
      throw StateError(
        'expected wire hashes require a concurrency-aware sync storage',
      );
    }
    final current = await storage.snapshotCandidates();
    final guarded = <SyncMergeCandidate>[];
    for (final candidate in candidates) {
      if (!expectedWireHashes.containsKey(candidate.address)) {
        guarded.add(candidate);
        continue;
      }
      final expected = expectedWireHashes[candidate.address];
      final actual = current[candidate.address]?.wireHash;
      if (actual == expected) {
        guarded.add(candidate);
        continue;
      }
      reports.add(
        SyncReport(
          code: SyncReportCode.concurrentLocalChange,
          kind: candidate.blob.kind,
          recordId: candidate.blob.id,
          message:
              'Local record changed while sync was preparing its inbound update.',
        ),
      );
    }
    return guarded;
  }

  Future<void> _applyInPhases({
    required List<SyncMergeCandidate> candidates,
    required SyncApplyBatchStorage storage,
    required Map<SyncRecordAddress, String?>? expectedWireHashes,
    required List<SyncRecordAddress> applied,
    required List<SyncReport> reports,
  }) async {
    var reconciledCandidates = candidates;
    final reconciliationStorage = storage is SyncApplyReconciliationStorage
        ? storage
        : null;
    if (reconciliationStorage != null) {
      final preparation = await reconciliationStorage.reconcileInbound(
        candidates,
        expectedWireHashes: expectedWireHashes,
      );
      reports.addAll(preparation.reports);
      reconciledCandidates = preparation.candidates;
    }
    final prepared = <SyncApplyRecord>[];
    for (final candidate in reconciledCandidates) {
      final admission = admitSyncInboundCandidate(candidate);
      final admittedCandidate = admission.candidate;
      final report = admission.report;
      if (report != null) {
        reports.add(report);
        continue;
      }

      final accepted = admittedCandidate!;
      final current = await storage.read(accepted.address) ?? const {};
      prepared.add(
        SyncApplyRecord(
          address: accepted.address,
          body: _overlay(
            Map<String, Object?>.from(current),
            Map<String, Object?>.from(accepted.blob.body),
          ),
          updatedAt: accepted.updatedAt,
          deletedAt: accepted.blob.deletedAt,
          existenceAt: accepted.existenceAt,
          sourceBlob: accepted.blob,
        ),
      );
    }

    var eligible = List<SyncApplyRecord>.of(prepared);
    var inboundAddresses = {for (final record in eligible) record.address};
    var inboundRecords = {
      for (final record in eligible) record.address: record,
    };
    var inboundLiveAddresses = {
      for (final record in eligible)
        if (record.deletedAt == null) record.address,
    };
    final reported = <SyncRecordAddress>{};
    while (eligible.isNotEmpty) {
      final next = <SyncApplyRecord>[];
      for (final record in eligible) {
        final referenceReport = await storage.validateInboundReferences(
          record,
          inboundLiveAddresses: inboundLiveAddresses,
          inboundAddresses: inboundAddresses,
          inboundRecords: inboundRecords,
        );
        if (referenceReport == null) {
          next.add(record);
        } else {
          if (reported.add(record.address)) reports.add(referenceReport);
        }
      }
      if (next.length == eligible.length) break;
      eligible = next;
      inboundAddresses = {for (final record in eligible) record.address};
      inboundRecords = {for (final record in eligible) record.address: record};
      inboundLiveAddresses
        ..clear()
        ..addAll({
          for (final record in eligible)
            if (record.deletedAt == null) record.address,
        });
    }
    final groups = _kindGroups(eligible);

    // Settle every group against the same per-group rules the write pass uses,
    // before naming any tombstone to the storage adapter. The batch-wide
    // fixed-point above is not enough on its own: it validates each record
    // against every other eligible record, while the write pass only offers a
    // record the groups already settled, so a record can survive there and
    // still be dropped here. A tombstone dropped after being named would have
    // already suppressed a citation — leaving a record hard-tombstoned while
    // the live owner that cites it stays — so the naming has to come last.
    final settled = <SyncRecordAddress, SyncApplyRecord>{};
    final settledGroups = <List<SyncApplyRecord>>[];
    for (final group in groups) {
      final ready = await _settleGroup(
        storage: storage,
        group: group,
        available: settled,
        reports: reports,
        reported: reported,
      );
      settledGroups.add(ready);
      for (final record in ready) {
        settled[record.address] = record;
      }
    }

    final namedTombstones = {
      for (final group in settledGroups)
        for (final record in group)
          if (record.deletedAt != null) record.address,
    };
    await reconciliationStorage?.setInboundTombstoneContext(namedTombstones);

    final parentWrittenByAddress = <SyncRecordAddress, SyncApplyRecord>{};
    final restorable = storage is SyncApplyRestorableStorage ? storage : null;
    final preImages = <SyncRecordAddress, Object?>{};
    for (final group in settledGroups) {
      // Re-settle against the records that were actually written rather than
      // the ones expected to be: a parent whose write failed must still prune
      // its dependents.
      final ready = await _settleGroup(
        storage: storage,
        group: group,
        available: parentWrittenByAddress,
        reports: reports,
        reported: reported,
      );

      for (final record in ready) {
        try {
          if (restorable != null) {
            preImages[record.address] = await restorable.capturePreImage(
              record.address,
            );
          }
          final report = await storage.writeParentWithReport(record);
          if (report != null) reports.add(report);
          parentWrittenByAddress[record.address] = record;
        } on FormatException catch (error) {
          reports.add(
            _writeReport(record, SyncReportCode.malformedRecord, '$error'),
          );
          _guardNamedTombstone(record, namedTombstones);
        } on ArgumentError catch (error) {
          reports.add(
            _writeReport(record, SyncReportCode.malformedRecord, '$error'),
          );
          _guardNamedTombstone(record, namedTombstones);
        } on StateError catch (error) {
          reports.add(
            _writeReport(record, SyncReportCode.unresolvedReference, '$error'),
          );
          _guardNamedTombstone(record, namedTombstones);
        } on Object catch (error) {
          // §6.7's contract is "one record skipped, batch intact", and §6.7
          // requires per-record handling to catch `Error` as well as
          // `Exception`. Anything the typed arms above do not name — a driver
          // exception such as a UNIQUE or FOREIGN KEY constraint failure, or a
          // cast error on a hostile body — used to escape the engine entirely,
          // rolling the transaction back and throwing the pass to its caller.
          // Because the inputs are durable, that repeated on every later pass.
          if (error is _NamedTombstoneWriteFailure) rethrow;
          reports.add(
            _writeReport(record, SyncReportCode.malformedRecord, '$error'),
          );
          _guardNamedTombstone(record, namedTombstones);
        }
      }
    }

    // Re-settle once more against what was *actually* written. The pass above
    // settles each group before its own writes run, so `parentWrittenByAddress`
    // then holds only earlier groups' results: a record whose same-kind
    // dependency failed inside its own group still looked ready. Writing its
    // joins would insert a row pointing at a parent that was never written —
    // a foreign-key failure, or a dangling row that `_hasCitation` would later
    // read as a live citation.
    final joinReady = <SyncApplyRecord>[];
    for (final group in settledGroups) {
      final written = [
        for (final record in group)
          if (parentWrittenByAddress.containsKey(record.address)) record,
      ];
      if (written.isEmpty) continue;
      joinReady.addAll(
        await _settleGroup(
          storage: storage,
          group: written,
          available: parentWrittenByAddress,
          reports: reports,
          reported: reported,
        ),
      );
    }

    // A join failure rolls that record's parent write back with it, so a
    // record is either applied whole or not at all. Its two phases are separate
    // savepoints — the two-phase order requires every parent before any join —
    // so without this the peer's parent row would commit beside this device's
    // existing join rows at the peer's `updatedAt`, which §6.3 reads as a tie
    // it declines to resolve and therefore never converges.
    Future<void> undoParentWrite(SyncApplyRecord record) async {
      if (restorable == null) return;
      await restorable.restorePreImage(
        record.address,
        preImages[record.address],
      );
    }

    for (final record in joinReady) {
      try {
        final report = await storage.writeJoinsWithReport(record);
        if (report != null) reports.add(report);
        final afterWrite = onAfterWrite;
        if (afterWrite != null) await afterWrite(record);
        applied.add(record.address);
      } on FormatException catch (error) {
        reports.add(
          _writeReport(record, SyncReportCode.malformedRecord, '$error'),
        );
        await undoParentWrite(record);
      } on ArgumentError catch (error) {
        reports.add(
          _writeReport(record, SyncReportCode.malformedRecord, '$error'),
        );
        await undoParentWrite(record);
      } on StateError catch (error) {
        reports.add(
          _writeReport(record, SyncReportCode.unresolvedReference, '$error'),
        );
        await undoParentWrite(record);
      } on Object catch (error) {
        // As in the parent loop: an unnamed failure must skip this record, not
        // escape the engine and strand the whole batch on every later pass.
        reports.add(
          _writeReport(record, SyncReportCode.malformedRecord, '$error'),
        );
        await undoParentWrite(record);
      }
    }
  }

  /// Aborts the batch when a tombstone the adapter was told about fails to
  /// write.
  ///
  /// Settling every group before naming closes the case where validation drops
  /// a named tombstone, but not this one: a write can still throw afterwards,
  /// and referenced kinds are written before the dances and programs that cite
  /// them. By then a record in an earlier group may already have been
  /// tombstoned outright because its last citation was supposed to disappear
  /// with this record — and now will not.
  ///
  /// There is nothing to undo towards: the engine holds the pre-write body but
  /// not the pre-write timestamps, so it cannot restore the earlier record to
  /// live and re-queue its tombstone as pending. Rolling the transaction back
  /// is the honest option — every record is retried on the next pass, and the
  /// reports already collected still reach the caller. Batch isolation is
  /// deliberately kept for every other write failure: only a *named tombstone*
  /// can have changed another record's citation decision.
  static void _guardNamedTombstone(
    SyncApplyRecord record,
    Set<SyncRecordAddress> namedTombstones,
  ) {
    if (record.deletedAt == null) return;
    if (!namedTombstones.contains(record.address)) return;
    throw _NamedTombstoneWriteFailure(record.address);
  }

  /// Splits an already kind-ordered batch into consecutive same-kind runs.
  static List<List<SyncApplyRecord>> _kindGroups(
    List<SyncApplyRecord> records,
  ) {
    final groups = <List<SyncApplyRecord>>[];
    var start = 0;
    while (start < records.length) {
      final kind = records[start].address.kind;
      var end = start + 1;
      while (end < records.length && records[end].address.kind == kind) {
        end++;
      }
      groups.add(records.sublist(start, end));
      start = end;
    }
    return groups;
  }

  /// Reduces one kind group to the records whose references all resolve.
  ///
  /// A record may reference another record of its own kind, so dropping one
  /// can invalidate another; the group is therefore reduced to a fixed point.
  /// [available] is what the group may reference beyond itself — records
  /// already settled, or already written, depending on the caller. Each
  /// dropped address is reported once across both passes via [reported].
  static Future<List<SyncApplyRecord>> _settleGroup({
    required SyncApplyBatchStorage storage,
    required List<SyncApplyRecord> group,
    required Map<SyncRecordAddress, SyncApplyRecord> available,
    required List<SyncReport> reports,
    required Set<SyncRecordAddress> reported,
  }) async {
    var ready = group;
    while (true) {
      final availableRecords = <SyncRecordAddress, SyncApplyRecord>{
        ...available,
        for (final record in ready) record.address: record,
      };
      final availableAddresses = availableRecords.keys.toSet();
      final availableLiveAddresses = {
        for (final record in availableRecords.values)
          if (record.deletedAt == null) record.address,
      };
      final next = <SyncApplyRecord>[];
      for (final record in ready) {
        final referenceReport = await storage.validateInboundReferences(
          record,
          inboundLiveAddresses: availableLiveAddresses,
          inboundAddresses: availableAddresses,
          inboundRecords: availableRecords,
        );
        if (referenceReport == null) {
          next.add(record);
        } else if (reported.add(record.address)) {
          reports.add(referenceReport);
        }
      }
      if (next.length == ready.length) return ready;
      ready = next;
    }
  }

  SyncReport _writeReport(
    SyncApplyRecord record,
    SyncReportCode code,
    String error,
  ) => SyncReport(
    code: code,
    kind: record.address.kind,
    recordId: record.address.recordId,
    message: 'Inbound record could not be applied: $error.',
  );

  Future<SyncReport?> _writeWithoutReport(
    SyncApplyStorage storage,
    SyncApplyRecord record,
  ) async {
    await storage.write(record);
    return null;
  }

  /// Decodes one batch without allowing a malformed record to abort its peers.
  Future<SyncApplyResult> applyJson({
    required Iterable<String> blobs,
    required SyncApplyStorage storage,
  }) async {
    final candidates = <SyncMergeCandidate>[];
    final reports = <SyncReport>[];
    for (final encoded in blobs) {
      try {
        candidates.add(
          SyncMergeCandidate.fromBlob(decodeSyncRecordBlob(encoded)),
        );
      } on FormatException catch (error) {
        reports.add(
          SyncReport(
            code: SyncReportCode.malformedRecord,
            message: 'Malformed inbound record: ${error.message}.',
          ),
        );
      }
    }

    final result = await apply(candidates: candidates, storage: storage);
    return SyncApplyResult(
      applied: result.applied,
      reports: [...reports, ...result.reports],
    );
  }

  static Map<String, Object?> _overlay(
    Map<String, Object?> current,
    Map<String, Object?> incoming,
  ) {
    for (final entry in incoming.entries) {
      final value = entry.value;
      final previous = current[entry.key];
      if (value is Map && previous is Map) {
        current[entry.key] = _overlay(
          Map<String, Object?>.from(previous),
          Map<String, Object?>.from(value),
        );
      } else {
        current[entry.key] = value;
      }
    }
    return current;
  }

  static int _compareCandidates(
    SyncMergeCandidate left,
    SyncMergeCandidate right,
  ) {
    final kind = _kindOrder(
      left.blob.kind,
    ).compareTo(_kindOrder(right.blob.kind));
    return kind == 0 ? left.blob.id.compareTo(right.blob.id) : kind;
  }

  static int _kindOrder(SyncRecordKind kind) => switch (kind) {
    SyncRecordKind.choreographer => 0,
    SyncRecordKind.publishedSource => 1,
    SyncRecordKind.tag => 2,
    SyncRecordKind.difficultyLevel => 3,
    SyncRecordKind.customFieldDef => 4,
    SyncRecordKind.venue => 5,
    SyncRecordKind.dance => 6,
    SyncRecordKind.program => 7,
    SyncRecordKind.setting => 8,
  };
}

DateTime _syncNowUtc() => DateTime.now().toUtc();

/// Rolls the inbound batch back when a named tombstone cannot be written.
///
/// Private to this library: it never escapes [SyncApplyEngine.apply], which
/// converts it into a report once the transaction has unwound.
final class _NamedTombstoneWriteFailure implements Exception {
  const _NamedTombstoneWriteFailure(this.address);

  final SyncRecordAddress address;

  @override
  String toString() =>
      'named tombstone ${address.kind.name}:${address.recordId} failed to write';
}
