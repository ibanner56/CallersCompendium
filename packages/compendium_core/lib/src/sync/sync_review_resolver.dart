import '../storage/database.dart' show ReviewQueueRow;
import 'canonical_json.dart' show sha256Hex;
import 'sync_codec.dart';
import 'sync_conflict_compare.dart'
    show syncUserVisibleBody, syncUserVisibleContentHash;
import 'sync_record_kind.dart';
import 'sync_retained_fields.dart';
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
/// each. [aliases] maps each id merged away by natural-key reconciliation to
/// the id it was merged into, by kind: another device's version may still
/// cite a merged-away id, and a comparison reads it as the record it became
/// ([syncUserVisibleBody]).
class SyncConflictGroup {
  const SyncConflictGroup({
    required this.kind,
    required this.recordId,
    required this.localBody,
    required this.candidates,
    this.localUpdatedAt,
    this.aliases = const {},
  });

  final SyncRecordKind kind;
  final String recordId;
  final Map<String, Object?>? localBody;
  final DateTime? localUpdatedAt;
  final List<SyncReviewQueueItem> candidates;
  final Map<SyncRecordKind, Map<String, String>> aliases;
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

  /// How many records await a conflict choice, counted as [listConflicts]
  /// lists them.
  Future<int> conflictCount() async {
    final rows = await storage.repositories.syncLocal.listReviewQueue();
    if (!rows.any((row) => row.reason == syncConflictChoiceReason)) return 0;
    return (await listConflicts()).length;
  }

  /// The records awaiting a conflict choice, oldest first, each with this
  /// device's current copy for comparison.
  ///
  /// A version that looks the same as this device's, or as another version
  /// listed, is left out ([syncUserVisibleContentHash]): choosing between
  /// versions a person cannot tell apart is arbitrary, so it is never asked,
  /// and a record left with nothing to choose between is not listed. The
  /// merge no longer queues such a choice and drops one queued earlier on its
  /// next pass.
  Future<List<SyncConflictGroup>> listConflicts() async {
    final rows = await storage.repositories.syncLocal.listReviewQueue();
    final aliases = <SyncRecordKind, Map<String, String>>{};
    for (final row in await storage.repositories.syncLocal.listAliases()) {
      aliases.putIfAbsent(row.kind, () => {})[row.losingId] = row.survivingId;
    }
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
      // The merge queued these against this device's live copy, or against
      // none (its hash is null) when the copy here is deleted; `read` returns
      // a deleted row's body too, so liveness is taken from the rows.
      final live = items.any((item) => item.row.localHash != null);
      final body = live ? await storage.read(address) : null;
      if (kind == SyncRecordKind.dance && shareableFieldIds == null) {
        shareableFieldIds = {
          for (final def
              in await storage.repositories.customFieldDefs
                  .listAllWithDeleted())
            if (def.field.shareable && !def.deleted) def.field.id,
        };
      }
      final projected = body == null
          ? null
          : projectShareableRecordBody(
              kind,
              body,
              settingsKey: kind == SyncRecordKind.setting ? recordId : null,
              allowedCustomFieldIds: shareableFieldIds ?? const {},
            );
      // The copy this device shares includes what it keeps for a newer
      // version (spec §6.7), so compare against that, not a stripped copy.
      final kept = projected == null
          ? null
          : await storage.retainedSyncParts(address);
      final localBody = projected == null || kept == null
          ? projected
          : mergeRetainedFields(projected, kept);
      String visible(Map<String, Object?> body) =>
          syncUserVisibleContentHash(kind, body, aliases: aliases);
      final seen = {if (localBody != null) visible(localBody)};
      final distinct = [
        for (final item in items)
          // An undecodable version stays listed: deciding it reports why.
          if (item.candidate == null || seen.add(visible(item.candidate!.body)))
            item,
      ];
      // With no live copy here, versions that all look alike leave one
      // version on offer: nothing to choose.
      if (distinct.isEmpty ||
          (localBody == null && items.length > 1 && distinct.length < 2)) {
        continue;
      }
      groups.add(
        SyncConflictGroup(
          kind: kind,
          recordId: recordId,
          localBody: localBody,
          localUpdatedAt: body == null
              ? null
              : await storage.recordUpdatedAt(address),
          candidates: List.unmodifiable(distinct),
          aliases: aliases,
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
