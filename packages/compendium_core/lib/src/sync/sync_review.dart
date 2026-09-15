import '../storage/database.dart';
import '../imports/dedupe.dart';
import 'canonical_json.dart';
import 'sync_codec.dart';
import 'sync_record_kind.dart';
import 'sync_reconciliation.dart';

/// The review reason whose user resolution is defined by sync-spec §6.6.
const String syncBaselineAbsenceTombstoneReason =
    'a tombstone would remove a locally-created natural-key row before a peer '
    'observed it';

/// The review reason produced when fresh attach finds same-title dances whose
/// choreography differs.
const String syncDanceChoreographyAmbiguityReason =
    'live dances share a normalized title but have different choreography';

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
  invalidCustomFieldKey,
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

  bool get isDanceAmbiguity =>
      row.reason == syncDanceChoreographyAmbiguityReason;

  String? get naturalKey {
    final value = candidate;
    if (value == null) return null;
    if (value.kind == SyncRecordKind.dance) {
      final title = value.body['title'];
      return title is String ? normalizeTitle(title) : null;
    }
    return syncNaturalKeyForBody(value.kind, value.body);
  }

  String? get candidateLabel {
    final body = candidate?.body;
    if (body == null) return null;
    final value = switch (candidate!.kind) {
      SyncRecordKind.choreographer || SyncRecordKind.tag => body['name'],
      SyncRecordKind.customFieldDef => body['key'],
      SyncRecordKind.difficultyLevel => body['label'],
      SyncRecordKind.dance => body['title'],
      _ => null,
    };
    return value is String && value.isNotEmpty ? value : null;
  }

  bool get isActionable {
    final value = candidate;
    final validCandidate =
        value != null &&
        value.kind == row.kind &&
        value.id == row.counterpartId &&
        value.body['id'] == value.id &&
        sha256Hex(encodeSyncRecordBlobUtf8(value)) == row.candidateHash &&
        row.recordId != value.id &&
        _hasValidEntityBody(value);
    if (!validCandidate) return false;
    if (row.reason == syncBaselineAbsenceTombstoneReason) {
      return value.deletedAt != null &&
          syncNaturalKeyKinds.contains(row.kind) &&
          naturalKey != null;
    }
    return row.reason == syncDanceChoreographyAmbiguityReason &&
        value.kind == SyncRecordKind.dance &&
        value.deletedAt == null &&
        naturalKey != null &&
        value.body['title'] is String;
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
