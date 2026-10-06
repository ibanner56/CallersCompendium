import '../storage/database.dart' show ReviewQueueRow;
import 'canonical_json.dart' show sha256Hex;
import 'sync_codec.dart';
import 'sync_record_kind.dart';
import 'wire_mapping.dart' show projectShareableRecordBody;
import 'sync_review.dart';
import 'sync_storage.dart';

/// One record awaiting the user's choice between its versions.
///
/// [localBody] is this device's current copy as it would sync — projected to
/// the fields that travel, so a comparison never reports a difference in
/// fields that stay on this device — or null when this device holds no live
/// copy (two other devices tied). [localUpdatedAt] is when this device last
/// changed it. [candidates] are the other versions on offer, one queue row
/// each.
class SyncConflictGroup {
  const SyncConflictGroup({
    required this.kind,
    required this.recordId,
    required this.localBody,
    required this.candidates,
    this.localUpdatedAt,
  });

  final SyncRecordKind kind;
  final String recordId;
  final Map<String, Object?>? localBody;
  final DateTime? localUpdatedAt;
  final List<SyncReviewQueueItem> candidates;
}

/// Coordinates the persisted queue with the production sync storage adapter.
///
/// The resolver is intentionally small: [CompendiumSyncStorage] owns the
/// transaction-bound writes, while this type supplies the app-facing list and
/// decision API.
final class SyncReviewQueueResolver {
  const SyncReviewQueueResolver(this.storage);

  final CompendiumSyncStorage storage;

  /// Every queued pair decision — merge or keep both. Conflict choices are
  /// listed by [listConflicts] instead, because they are decided on a
  /// different surface with different actions; versions already chosen
  /// against are a record of a decision, not a question, and are not listed.
  Future<List<SyncReviewQueueItem>> list() async {
    final rows = await storage.repositories.syncLocal.listReviewQueue();
    return [
      for (final row in rows)
        if (row.reason != syncConflictChoiceReason &&
            row.reason != syncConflictChoiceCopyReason &&
            row.reason != syncConflictDecidedAgainstReason)
          SyncReviewQueueItem.fromRow(row),
    ];
  }

  /// How many records await a conflict choice.
  Future<int> conflictCount() async {
    final rows = await storage.repositories.syncLocal.listReviewQueue();
    return {
      for (final row in rows)
        if (row.reason == syncConflictChoiceReason) (row.kind, row.recordId),
    }.length;
  }

  /// The records awaiting a conflict choice, oldest first, each with this
  /// device's current copy for comparison.
  Future<List<SyncConflictGroup>> listConflicts() async {
    final rows = await storage.repositories.syncLocal.listReviewQueue();
    final grouped = <(SyncRecordKind, String), List<SyncReviewQueueItem>>{};
    for (final row in rows) {
      if (row.reason != syncConflictChoiceReason) continue;
      grouped
          .putIfAbsent((row.kind, row.recordId), () => [])
          .add(SyncReviewQueueItem.fromRow(row));
    }
    final groups = <SyncConflictGroup>[];
    Set<String>? shareableFieldIds;
    for (final entry in grouped.entries) {
      final (kind, recordId) = entry.key;
      final address = (kind: kind, recordId: recordId);
      final items = entry.value
        ..sort((a, b) => a.row.candidateHash.compareTo(b.row.candidateHash));
      final body = await storage.read(address);
      if (kind == SyncRecordKind.dance && shareableFieldIds == null) {
        shareableFieldIds = {
          for (final def
              in await storage.repositories.customFieldDefs
                  .listAllWithDeleted())
            if (def.field.shareable && !def.deleted) def.field.id,
        };
      }
      groups.add(
        SyncConflictGroup(
          kind: kind,
          recordId: recordId,
          localBody: body == null
              ? null
              : projectShareableRecordBody(
                  kind,
                  body,
                  settingsKey: kind == SyncRecordKind.setting ? recordId : null,
                  allowedCustomFieldIds: shareableFieldIds ?? const {},
                ),
          localUpdatedAt: body == null
              ? null
              : await storage.recordUpdatedAt(address),
          candidates: List.unmodifiable(items),
        ),
      );
    }
    DateTime first(SyncConflictGroup group) => group.candidates
        .map((item) => item.row.queuedAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    groups.sort((a, b) => first(a).compareTo(first(b)));
    return groups;
  }

  Future<void> resolve({
    required SyncReviewQueueItem item,
    required SyncReviewAction action,
    String? newNaturalKey,
  }) => storage.resolveReviewQueue(
    expectedRow: item.row,
    action: action,
    newNaturalKey: newNaturalKey,
  );

  /// Applies the user's conflict choices, all or none (see
  /// [CompendiumSyncStorage.resolveConflicts]).
  Future<SyncConflictResolution> resolveConflicts(
    Iterable<SyncConflictDecision> decisions,
  ) => storage.resolveConflicts(decisions);

  /// Makes a new choice for records already decided — the undo of a choice
  /// (see [CompendiumSyncStorage.reconsiderConflicts]).
  Future<SyncConflictResolution> reconsiderConflicts(
    Iterable<SyncConflictRechoice> rechoices,
  ) => storage.reconsiderConflicts(rechoices);
}

/// The conflict group a remembered choice is reconsidered from: this device's
/// version before the choice and the other versions it was made between,
/// shaped like a queued conflict so the same choice can show it.
///
/// Built in memory; nothing is queued. Each other version is identified by
/// its wire hash, as a queued one is.
SyncConflictGroup syncConflictGroupFor(SyncConflictReconsideration earlier) {
  final before = earlier.before;
  return SyncConflictGroup(
    kind: earlier.kind,
    recordId: earlier.recordId,
    localBody: before?.body,
    localUpdatedAt: before?.updatedAt,
    candidates: [
      for (final blob in earlier.offered)
        SyncReviewQueueItem.fromRow(
          ReviewQueueRow(
            kind: earlier.kind,
            recordId: earlier.recordId,
            counterpartId: sha256Hex(encodeSyncRecordBlobUtf8(blob)),
            reason: syncConflictChoiceReason,
            candidateBlob: encodeSyncRecordBlob(blob),
            candidateHash: sha256Hex(encodeSyncRecordBlobUtf8(blob)),
            localHash: earlier.writtenWireHash,
            queuedAt: earlier.writtenAt,
          ),
        ),
    ],
  );
}
