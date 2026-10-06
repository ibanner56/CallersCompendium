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

/// The reason for a record whose versions differ and which only the user can
/// settle (sync-spec §6.3, §6.6): bodies at an equal `updatedAt`, or a
/// changed/changed conflict on a whole-collection setting.
///
/// One row per offered version that is not this device's own, keyed by that
/// version's wire hash as `counterpart_id`. `record_id` is the record itself,
/// and `local_hash` is this device's wire hash when the row was queued, so a
/// decision made against a copy that has since changed is refused rather than
/// applied over the newer edit.
const String syncConflictChoiceReason =
    'versions of one record differ and need the user to choose which to keep';

/// The reason for a version of a whole-collection setting that the user
/// chose against on this device (sync-spec §6.6, *Conflict choices*).
///
/// Not something to review: these rows are never listed. One row per version
/// that was on offer when the choice was written — the other devices' and this
/// device's own copy before the choice — keyed by that version's wire hash as
/// `counterpart_id` (and `candidate_hash`), with an empty `candidate_blob`,
/// since only the hash is needed. The merge drops a changed version whose hash
/// is recorded here before deciding whether the setting is in conflict, so a
/// device that has not synced since, or a leftover manifest that never will,
/// cannot raise the choice again on this device. The record lives only here:
/// another device cannot see it, so one that changed the set too is asked once
/// more. Cleared with the rest of the queue when the store epoch resets or the
/// device detaches.
const String syncConflictDecidedAgainstReason =
    'a version of a whole-collection setting the user chose against';

/// One user choice in a conflict review: keep [keepCandidateHash]'s version
/// of the record, or this device's own when it is null — or, when
/// [combineTakingOther] is set, combine both versions of a whole-collection
/// setting, taking the other device's version of each entry named in it and
/// this device's for every other entry both have.
class SyncConflictDecision {
  const SyncConflictDecision({
    required this.kind,
    required this.recordId,
    this.keepCandidateHash,
    this.combineTakingOther,
  });

  final SyncRecordKind kind;
  final String recordId;
  final String? keepCandidateHash;
  final Set<String>? combineTakingOther;
}

/// What one conflict choice replaced and wrote, so it can be reconsidered.
///
/// Held in memory only, for as long as the app offers to undo the choice. A
/// reconsideration offers [before] and [offered] again; it is refused when
/// this device's copy no longer matches [writtenWireHash] — something newer
/// has arrived since, and the choice is no longer the one being undone.
class SyncConflictReconsideration {
  const SyncConflictReconsideration({
    required this.kind,
    required this.recordId,
    required this.before,
    required this.offered,
    required this.writtenWireHash,
    required this.writtenAt,
  });

  final SyncRecordKind kind;
  final String recordId;

  /// This device's version before the choice, or null when it had none.
  final SyncRecordBlob? before;

  /// The other versions that were on offer.
  final List<SyncRecordBlob> offered;
  final String writtenWireHash;
  final DateTime writtenAt;
}

/// The outcome of a batch of conflict choices: the kinds written, and how to
/// reconsider each choice.
class SyncConflictResolution {
  const SyncConflictResolution({
    required this.kinds,
    required this.reconsiderations,
  });

  final Set<SyncRecordKind> kinds;
  final List<SyncConflictReconsideration> reconsiderations;
}

/// A new choice for a reconsidered record: keep the offered version whose
/// wire hash is [keepVersionHash], this device's earlier version when it is
/// null, or combine as in [SyncConflictDecision.combineTakingOther].
class SyncConflictRechoice {
  const SyncConflictRechoice({
    required this.reconsideration,
    this.keepVersionHash,
    this.combineTakingOther,
  });

  final SyncConflictReconsideration reconsideration;
  final String? keepVersionHash;
  final Set<String>? combineTakingOther;
}

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

  /// A §6.6 step-1 merge was asked for while the row holding the natural key
  /// is a tombstone.
  ///
  /// Distinct from [targetMissing]: the row is not missing. A tombstone keeps
  /// occupying its name, because none of the four natural-key indexes is
  /// filtered on `deleted_at` (§4.1), which is exactly how the collision
  /// arises. Merging it with a live record would be an *existence* decision,
  /// and keep-both remains available.
  counterpartDeleted,

  /// Combine both was asked for a record that cannot be combined: not a
  /// whole-collection setting, or not exactly two versions to combine.
  combineUnavailable,

  /// The combined collection would hold more entries than its library keeps,
  /// so loading it would quietly drop some.
  combineOverLimit,

  /// The decision could not be stamped later than every version on offer
  /// without leaving this device's clock window (§6.9), so applying it would
  /// only quarantine it. The fix is this device's date and time.
  clockOutOfRange,
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

  /// A version offered in a conflict review rather than a pair to merge.
  bool get isConflictChoice => row.reason == syncConflictChoiceReason;

  /// The id of the record that exists only on this device.
  ///
  /// Reason-aware, because the queue's two identity layouts disagree about
  /// which column that is. Every reason but §6.6 step 1 stores the local row
  /// as `record_id`; a step-1 row stores the *candidate* there and the local
  /// name-holder as `counterpart_id`.
  ///
  /// This pairing is not cosmetic. A user deciding a step-1 merge is choosing
  /// which of two of their own records survives, irreversibly, and a screen
  /// that labelled them the wrong way round would be inviting that choice
  /// against the wrong record.
  String get localRecordId =>
      isNaturalKeyRenameCollision ? row.counterpartId : row.recordId;

  /// The id of the record the peer sent — the one [candidateLabel] describes.
  ///
  /// The counterpart of [localRecordId]; see that doc for why it is
  /// reason-aware. For a step-1 row this device also holds a row under this
  /// id, since the collision is a peer's *update* to a record already known
  /// here; it is "the peer's" in the sense that the queued body came from a
  /// peer, not that the id is unknown locally.
  String get peerRecordId =>
      isNaturalKeyRenameCollision ? row.recordId : row.counterpartId;

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
        // A setting's body is its value; its id is the key, on the envelope.
        (value.kind == SyncRecordKind.setting ||
            value.body['id'] == value.id) &&
        sha256Hex(encodeSyncRecordBlobUtf8(value)) == row.candidateHash &&
        _hasValidEntityBody(value);
    if (!wellFormedCandidate) return false;
    if (row.reason == syncConflictChoiceReason) {
      // The candidate is another version of `record_id` itself, filed under
      // its own wire hash.
      return value.id == row.recordId &&
          row.counterpartId == row.candidateHash &&
          value.deletedAt == null;
    }
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
  // A setting's body is a value, not an archive entity, and is validated by
  // inbound admission instead (`resolveConflicts`).
  if (candidate.kind == SyncRecordKind.setting) return true;
  try {
    validateSyncReviewCandidateBody(candidate.kind, candidate.body);
    return true;
  } on Object {
    return false;
  }
}
