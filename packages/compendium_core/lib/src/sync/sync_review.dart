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

/// The sync-spec §6.6 step-1 reason: a record whose UUID this device already
/// knows arrived carrying a natural key another local row holds.
///
/// Step 1 is not step 2. Both sides are pre-existing local rows, so the pair
/// may be two genuinely different entities and MUST NOT merge silently
/// (`docs/design/sync-spec.md` §6.6, ADR-004). Two producers write this
/// reason: the stored-row guard and the in-batch guard added by #1364.
const String syncNaturalKeyRenameCollisionReason =
    'known UUID natural-key rename collides with another local row';

/// The step-1 reason for a rename that collides with a shipped difficulty row.
///
/// Identical in shape to [syncNaturalKeyRenameCollisionReason] — two local
/// rows, one natural key — but the survivor is the canonical shipped ID rather
/// than the lexicographically smaller UUID, because a shipped difficulty ID is
/// part of the persisted relationship contract (§6.6).
const String syncShippedDifficultyRenameCollisionReason =
    'known UUID natural-key rename collides with the shipped difficulty row';

/// The step-1 reasons whose resolution is defined by §6.6 and ADR-004.
///
/// These rows carry the *opposite* identity layout to every other queued
/// reason: `record_id` is the candidate's own id and `counterpart_id` is the
/// other local row, because the candidate updates a record this device already
/// knows. Reading a step-1 row with the tombstone layout in mind is the single
/// easiest mistake to make here, so the set is named rather than inlined.
const Set<String> syncNaturalKeyRenameCollisionReasons = {
  syncNaturalKeyRenameCollisionReason,
  syncShippedDifficultyRenameCollisionReason,
};

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

  bool get isNaturalKeyRenameCollision =>
      syncNaturalKeyRenameCollisionReasons.contains(row.reason);

  /// Whether [SyncReviewAction.merge] would discard device-local contact
  /// fields that are held nowhere else.
  ///
  /// Step 1 merges two pre-existing local rows and MUST NOT coalesce (§6.6),
  /// so the losing choreographer's email, location and deceased flag go with
  /// it. They are stripped from every shareable body, so no peer can return
  /// them. The user is told before the merge, not after.
  bool get mergeDiscardsContactFields =>
      isNaturalKeyRenameCollision && row.kind == SyncRecordKind.choreographer;

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

  /// Whether the persisted row can be handed to the resolver at all.
  ///
  /// The identity checks are deliberately **not** shared across reasons. A
  /// §6.6 step-1 row stores the candidate's own id as `record_id` and the
  /// other local row as `counterpart_id`; the tombstone and dance reasons
  /// store the opposite. A single shared `candidate.id == counterpartId`
  /// precondition — which is what this method used to open with — silently
  /// rejects every step-1 row no matter which reasons the allowlist below
  /// names, so the orientation belongs inside each branch.
  ///
  /// This is display-time triage only. The resolver repeats every check
  /// inside its transaction (see the class doc), so a row that slips through
  /// here still cannot become an accidental success.
  bool get isActionable {
    final value = candidate;
    final wellFormedCandidate =
        value != null &&
        value.kind == row.kind &&
        value.body['id'] == value.id &&
        sha256Hex(encodeSyncRecordBlobUtf8(value)) == row.candidateHash &&
        _hasValidEntityBody(value);
    if (!wellFormedCandidate) return false;
    if (syncNaturalKeyRenameCollisionReasons.contains(row.reason)) {
      // Step 1: the candidate updates `record_id`, and `counterpart_id` is the
      // other local row that currently holds the natural key.
      return value.id == row.recordId &&
          row.recordId != row.counterpartId &&
          value.deletedAt == null &&
          syncNaturalKeyKinds.contains(row.kind) &&
          naturalKey != null &&
          (row.reason != syncShippedDifficultyRenameCollisionReason ||
              row.kind == SyncRecordKind.difficultyLevel);
    }
    // Every remaining reason stores the candidate under `counterpart_id`.
    if (value.id != row.counterpartId || row.recordId == value.id) return false;
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
