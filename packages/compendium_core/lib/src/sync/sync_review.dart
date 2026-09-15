import '../storage/database.dart';
import 'canonical_json.dart';
import 'sync_codec.dart';
import 'sync_record_kind.dart';
import 'sync_reconciliation.dart';

/// The review reason whose user resolution is defined by sync-spec §6.6.
const String syncBaselineAbsenceTombstoneReason =
    'a tombstone would remove a locally-created natural-key row before a peer '
    'observed it';

/// The decisions supported by the persisted sync review surface.
enum SyncReviewAction { merge, keepBoth }

/// A stable failure category for callers that need localized error copy.
enum SyncReviewFailureCode {
  candidateInvalid,
  candidateChanged,
  unsupportedReason,
  targetMissing,
  candidateAlreadyPresent,
  nameRequired,
  nameNotDistinct,
}

/// A failed review decision that left the queue row untouched.
class SyncReviewException implements Exception {
  const SyncReviewException(this.code);

  final SyncReviewFailureCode code;

  @override
  String toString() => 'sync review failed: ${code.name}';
}

/// A persisted queue row with a best-effort decoded candidate for display.
///
/// Decoding is deliberately best effort here. The resolver repeats strict
/// validation inside its transaction, so a malformed row can be displayed as
/// retained state without becoming an accidental success.
class SyncReviewQueueItem {
  const SyncReviewQueueItem({required this.row, required this.candidate});

  factory SyncReviewQueueItem.fromRow(ReviewQueueRow row) {
    SyncRecordBlob? candidate;
    try {
      candidate = decodeSyncRecordBlob(row.candidateBlob);
    } on Object {
      candidate = null;
    }
    return SyncReviewQueueItem(row: row, candidate: candidate);
  }

  final ReviewQueueRow row;
  final SyncRecordBlob? candidate;

  String? get naturalKey => candidate == null
      ? null
      : syncNaturalKeyForBody(candidate!.kind, candidate!.body);

  String? get candidateLabel {
    final body = candidate?.body;
    if (body == null) return null;
    final value = switch (candidate!.kind) {
      SyncRecordKind.choreographer || SyncRecordKind.tag => body['name'],
      SyncRecordKind.customFieldDef => body['key'],
      SyncRecordKind.difficultyLevel => body['label'],
      _ => null,
    };
    return value is String && value.isNotEmpty ? value : null;
  }

  bool get isActionable {
    final value = candidate;
    return row.reason == syncBaselineAbsenceTombstoneReason &&
        value != null &&
        value.kind == row.kind &&
        value.id == row.counterpartId &&
        value.body['id'] == value.id &&
        value.deletedAt != null &&
        syncNaturalKeyKinds.contains(row.kind) &&
        naturalKey != null &&
        _hasValidEntityBody(value) &&
        sha256Hex(encodeSyncRecordBlobUtf8(value)) == row.candidateHash &&
        row.recordId != value.id;
  }
}

bool _hasValidEntityBody(SyncRecordBlob candidate) {
  try {
    validateSyncReviewCandidateBody(candidate.kind, candidate.body);
    return true;
  } on Object {
    return false;
  }
}
