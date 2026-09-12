import '../storage/repositories/sync_local_repository.dart';
import '../storage/shareable_text.dart';
import 'sync_codec.dart';
import 'sync_merge.dart';
import 'sync_record_kind.dart';
import 'sync_report.dart';
import 'wire_mapping.dart';

/// The transaction-facing value passed to an inbound storage adapter.
class SyncApplyRecord {
  const SyncApplyRecord({
    required this.address,
    required this.body,
    required this.updatedAt,
    required this.deletedAt,
    required this.existenceAt,
  });

  final SyncRecordAddress address;
  final Map<String, Object?> body;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime existenceAt;
}

/// The narrow storage seam required by the core apply engine.
///
/// An app adapter implements [transaction] with the database transaction that
/// owns its repositories. [write] is responsible for mapping the already
/// validated, shareable overlay to parent and join tables and for rebuilding
/// derived indexes before the transaction commits.
abstract interface class SyncApplyStorage {
  Future<T> transaction<T>(Future<T> Function() action);

  Future<Map<String, Object?>?> read(SyncRecordAddress address);

  Future<void> write(SyncApplyRecord record);

  Future<void> rebuildDerivedIndexes();
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
/// Parent rows are written first, then references and join rows are validated
/// and written. This permits forward references and cycles without weakening
/// the database's foreign-key checks.
abstract interface class SyncApplyBatchStorage
    implements SyncApplyReportingStorage {
  Future<SyncReport?> writeParentWithReport(SyncApplyRecord record) =>
      writeWithReport(record);

  Future<SyncReport?> writeJoinsWithReport(SyncApplyRecord record) async =>
      null;
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
  const SyncApplyEngine({this.onAfterWrite});

  final SyncApplyWriteHook? onAfterWrite;

  /// Applies [candidates] in dependency order inside one transaction.
  Future<SyncApplyResult> apply({
    required Iterable<SyncMergeCandidate> candidates,
    required SyncApplyStorage storage,
  }) async {
    final applied = <SyncRecordAddress>[];
    final reports = <SyncReport>[];
    final ordered = candidates.toList()..sort(_compareCandidates);

    await storage.transaction(() async {
      if (storage is SyncApplyBatchStorage) {
        await _applyInPhases(
          candidates: ordered,
          storage: storage,
          applied: applied,
          reports: reports,
        );
      } else {
        for (final candidate in ordered) {
          final validation = validateShareableRecordBody(
            candidate.blob.kind,
            candidate.blob.body,
            settingsKey: candidate.blob.kind == SyncRecordKind.setting
                ? candidate.blob.id
                : null,
          );
          if (!validation.isValid) {
            reports.add(
              SyncReport(
                code: SyncReportCode.invalidClassification,
                kind: candidate.blob.kind,
                recordId: candidate.blob.id,
                message:
                    'Inbound body contains a non-shareable wire path '
                    '${validation.invalidPath}.',
              ),
            );
            continue;
          }
          if (_isReceiveOnlySetting(candidate)) {
            reports.add(
              SyncReport(
                code: SyncReportCode.invalidClassification,
                kind: candidate.blob.kind,
                recordId: candidate.blob.id,
                message:
                    'Inbound sync credentials are receive-only and were not '
                    'adopted.',
              ),
            );
            continue;
          }

          final current = await storage.read(candidate.address) ?? const {};
          final Object? normalized;
          try {
            normalized = normalizeShareableJson(candidate.blob.body);
          } on ArgumentError catch (error) {
            reports.add(
              SyncReport(
                code: SyncReportCode.malformedRecord,
                kind: candidate.blob.kind,
                recordId: candidate.blob.id,
                message: 'Inbound record body could not be normalized: $error.',
              ),
            );
            continue;
          } on ShareableJsonKeyCollision catch (error) {
            reports.add(
              SyncReport(
                code: SyncReportCode.malformedRecord,
                kind: candidate.blob.kind,
                recordId: candidate.blob.id,
                message:
                    'Inbound record body has a normalized key collision: '
                    '${error.normalizedKey}.',
              ),
            );
            continue;
          }
          if (normalized is! Map) {
            reports.add(
              SyncReport(
                code: SyncReportCode.malformedRecord,
                kind: candidate.blob.kind,
                recordId: candidate.blob.id,
                message: 'Inbound record body is not an object.',
              ),
            );
            continue;
          }
          final merged = _overlay(
            Map<String, Object?>.from(current),
            Map<String, Object?>.from(normalized),
          );
          try {
            final applyRecord = SyncApplyRecord(
              address: candidate.address,
              body: merged,
              updatedAt: candidate.updatedAt,
              deletedAt: candidate.blob.deletedAt,
              existenceAt: candidate.existenceAt,
            );
            final reportingStorage = storage is SyncApplyReportingStorage
                ? storage
                : null;
            final referenceReport = reportingStorage == null
                ? null
                : await reportingStorage.validateInboundReferences(applyRecord);
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
                message: 'Inbound record referenced unavailable data: $error.',
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

    return SyncApplyResult(
      applied: List.unmodifiable(applied),
      reports: List.unmodifiable(reports),
    );
  }

  Future<void> _applyInPhases({
    required List<SyncMergeCandidate> candidates,
    required SyncApplyBatchStorage storage,
    required List<SyncRecordAddress> applied,
    required List<SyncReport> reports,
  }) async {
    final prepared = <SyncApplyRecord>[];
    for (final candidate in candidates) {
      final validation = validateShareableRecordBody(
        candidate.blob.kind,
        candidate.blob.body,
        settingsKey: candidate.blob.kind == SyncRecordKind.setting
            ? candidate.blob.id
            : null,
      );
      if (!validation.isValid) {
        reports.add(
          SyncReport(
            code: SyncReportCode.invalidClassification,
            kind: candidate.blob.kind,
            recordId: candidate.blob.id,
            message:
                'Inbound body contains a non-shareable wire path '
                '${validation.invalidPath}.',
          ),
        );
        continue;
      }
      if (_isReceiveOnlySetting(candidate)) {
        reports.add(
          SyncReport(
            code: SyncReportCode.invalidClassification,
            kind: candidate.blob.kind,
            recordId: candidate.blob.id,
            message:
                'Inbound sync credentials are receive-only and were not '
                'adopted.',
          ),
        );
        continue;
      }

      final current = await storage.read(candidate.address) ?? const {};
      final Object? normalized;
      try {
        normalized = normalizeShareableJson(candidate.blob.body);
      } on ArgumentError catch (error) {
        reports.add(
          SyncReport(
            code: SyncReportCode.malformedRecord,
            kind: candidate.blob.kind,
            recordId: candidate.blob.id,
            message: 'Inbound record body could not be normalized: $error.',
          ),
        );
        continue;
      } on ShareableJsonKeyCollision catch (error) {
        reports.add(
          SyncReport(
            code: SyncReportCode.malformedRecord,
            kind: candidate.blob.kind,
            recordId: candidate.blob.id,
            message:
                'Inbound record body has a normalized key collision: '
                '${error.normalizedKey}.',
          ),
        );
        continue;
      }
      if (normalized is! Map) {
        reports.add(
          SyncReport(
            code: SyncReportCode.malformedRecord,
            kind: candidate.blob.kind,
            recordId: candidate.blob.id,
            message: 'Inbound record body is not an object.',
          ),
        );
        continue;
      }
      prepared.add(
        SyncApplyRecord(
          address: candidate.address,
          body: _overlay(
            Map<String, Object?>.from(current),
            Map<String, Object?>.from(normalized),
          ),
          updatedAt: candidate.updatedAt,
          deletedAt: candidate.blob.deletedAt,
          existenceAt: candidate.existenceAt,
        ),
      );
    }

    var eligible = List<SyncApplyRecord>.of(prepared);
    var inboundAddresses = {for (final record in eligible) record.address};
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
      inboundLiveAddresses
        ..clear()
        ..addAll({
          for (final record in eligible)
            if (record.deletedAt == null) record.address,
        });
    }

    final parentWritten = <SyncApplyRecord>[];
    for (final record in eligible) {
      try {
        final report = await storage.writeParentWithReport(record);
        if (report != null) reports.add(report);
        parentWritten.add(record);
      } on FormatException catch (error) {
        reports.add(
          _writeReport(record, SyncReportCode.malformedRecord, '$error'),
        );
      } on ArgumentError catch (error) {
        reports.add(
          _writeReport(record, SyncReportCode.malformedRecord, '$error'),
        );
      } on StateError catch (error) {
        reports.add(
          _writeReport(record, SyncReportCode.unresolvedReference, '$error'),
        );
      }
    }

    for (final record in parentWritten) {
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
      } on ArgumentError catch (error) {
        reports.add(
          _writeReport(record, SyncReportCode.malformedRecord, '$error'),
        );
      } on StateError catch (error) {
        reports.add(
          _writeReport(record, SyncReportCode.unresolvedReference, '$error'),
        );
      }
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

  static bool _isReceiveOnlySetting(SyncMergeCandidate candidate) {
    if (candidate.blob.kind != SyncRecordKind.setting) return false;
    return candidate.blob.id == 'sync_id' ||
        candidate.blob.id == 'sync_device_id';
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
