import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../model/choreographer.dart';
import '../model/custom_field.dart';
import '../model/dance.dart';
import '../model/difficulty_level.dart';
import '../model/provenance.dart';
import '../model/published_source.dart';
import '../model/program.dart';
import '../model/tag.dart';
import '../model/venue.dart';
import '../privacy/data_classification.dart';
import '../privacy/settings_registry.dart';
import '../serialization/archive_codec.dart';
import '../serialization/archive_entity_codec.dart';
import '../sync/canonical_json.dart';
import '../storage/database.dart';
import '../storage/existence.dart';
import '../storage/repositories/repositories.dart';
import '../storage/repositories/custom_field_repository.dart';
import '../storage/repositories/sync_local_repository.dart';
import '../storage/shareable_text.dart';
import 'sync_apply.dart';
import 'sync_codec.dart';
import 'sync_id.dart';
import 'sync_merge.dart';
import 'sync_record_kind.dart';
import 'sync_reconciliation.dart';
import 'sync_report.dart';
import 'sync_review.dart';
import 'wire_mapping.dart';

Iterable<List<T>> _chunked<T>(Iterable<T> values, int size) sync* {
  final list = values.toList(growable: false);
  for (var start = 0; start < list.length; start += size) {
    final end = start + size < list.length ? start + size : list.length;
    yield list.sublist(start, end);
  }
}

typedef _NaturalKeyAddress = ({SyncRecordKind kind, String key});
typedef _NaturalKeyValue = ({
  String id,
  String? type,
  bool deleted,
  bool? shareable,
});

final class _NaturalKeyIndex {
  _NaturalKeyIndex(this._rows);

  final Map<_NaturalKeyAddress, _NaturalKeyValue> _rows;

  _NaturalKeyValue? lookup(SyncRecordKind kind, String key) =>
      _rows[(kind: kind, key: key)];

  void removeId(SyncRecordKind kind, String id) {
    _rows.removeWhere(
      (address, value) => address.kind == kind && value.id == id,
    );
  }

  void add({
    required SyncRecordKind kind,
    required String key,
    required _NaturalKeyValue value,
  }) {
    final address = (kind: kind, key: key);
    final current = _rows[address];
    if (current == null || _prefer(value, current)) {
      _rows[address] = value;
    }
  }

  void replace({
    required SyncRecordKind kind,
    required String id,
    required String key,
    required String? type,
    required bool deleted,
    required bool? shareable,
  }) {
    removeId(kind, id);
    add(
      kind: kind,
      key: key,
      value: (id: id, type: type, deleted: deleted, shareable: shareable),
    );
  }

  static bool _prefer(_NaturalKeyValue candidate, _NaturalKeyValue current) {
    if (candidate.deleted != current.deleted) return !candidate.deleted;
    if (candidate.shareable != current.shareable) {
      return candidate.shareable == false;
    }
    return candidate.id.compareTo(current.id) < 0;
  }
}

/// A complete local sync snapshot owned by the repository/database boundary.
class SyncStorageSnapshot {
  const SyncStorageSnapshot({
    required this.epoch,
    required this.previouslyUsed,
    required this.local,
    required this.baseline,
    Map<SyncRecordAddress, SyncMergeCandidate?>? publication,
    Map<SyncRecordAddress, SyncMergeCandidate?>? pendingLive,
    this.pending = const {},
  }) : publication = publication ?? local,
       pendingLive = pendingLive ?? const {};

  final String? epoch;
  final bool previouslyUsed;
  final Map<SyncRecordAddress, SyncMergeCandidate?> local;
  final Map<SyncRecordAddress, SyncBaselineEntry> baseline;

  /// The manifest view. Pending tombstones overlay live rows here without
  /// changing the live merge view until their citation is gone.
  final Map<SyncRecordAddress, SyncMergeCandidate?> publication;

  /// The captured live rows underneath pending tombstones. These rows stay out
  /// of [local] but still participate in optimistic-concurrency checks.
  final Map<SyncRecordAddress, SyncMergeCandidate?> pendingLive;

  /// Addresses held in [pendingDeletions], excluded from merge and baseline
  /// advancement while their local citations still exist.
  final Set<SyncRecordAddress> pending;
}

final class _InboundDependentIndex {
  final Map<String, List<SyncRecordAddress>> danceLinkOwners = {};
  final Map<String, List<SyncRecordAddress>> programSlotOwners = {};
}

/// The production storage adapter for the core sync engine.
///
/// Reads use full-fidelity models so a shareable inbound overlay cannot erase
/// device-local fields. Writes use dedicated inbound repository writers so
/// interactive side effects cannot alter the validated peer body, then restore
/// the wire timestamp triple because local persistence stamps causal times.
final class CompendiumSyncStorage
    implements SyncApplyReconciliationStorage, SyncApplyConcurrencyStorage {
  CompendiumSyncStorage(this.repositories);

  final CompendiumRepositories repositories;
  final Map<SyncRecordAddress, Object> _deferredEntities = {};
  final Set<SyncRecordAddress> _pendingParentWrites = {};
  Set<SyncRecordAddress> _inboundTombstonedAddresses = {};
  _NaturalKeyIndex? _naturalKeyIndex;
  final Expando<_InboundDependentIndex> _dependentIndexCache =
      Expando<_InboundDependentIndex>();

  CompendiumDatabase get _db => repositories.db;

  Future<SyncStorageSnapshot> snapshot({
    String? syncId,
  }) => repositories.transaction(() async {
    await _revalidatePendingDeletions();
    final usedVerifiers = await _loadUsedIdentityVerifiers(syncId);
    final baseline = await repositories.syncLocal.snapshotBaseline();
    final baselineState = await repositories.syncLocal.getBaselineState();
    final local = <SyncRecordAddress, SyncMergeCandidate?>{};
    final customFields = await repositories.customFieldDefs
        .listAllWithDeleted();
    final allowedCustomFieldIds = {
      for (final entry in customFields)
        if (entry.field.shareable && !entry.deleted) entry.field.id,
    };

    Future<void> addEntity({
      required SyncRecordKind kind,
      required String id,
      required Object entity,
      required DateTime updatedAt,
      required DateTime existenceAt,
      DateTime? deletedAt,
    }) async {
      final blob = syncRecordBlobForEntity(
        kind,
        entity,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        existenceAt: existenceAt,
        allowedCustomFieldIds: allowedCustomFieldIds,
      );
      if (blob == null) return;
      final address = (kind: kind, recordId: id);
      local[address] = SyncMergeCandidate(
        blob: blob,
        wireHash: sha256Hex(encodeSyncRecordBlobUtf8(blob)),
      );
    }

    final dances = await repositories.dances.listAll(includeDeleted: true);
    final danceRows = await _db.select(_db.dances).get();
    final danceRowsById = {for (final row in danceRows) row.id: row};
    for (final dance in dances) {
      final row = danceRowsById[dance.id];
      if (row == null) continue;
      await addEntity(
        kind: SyncRecordKind.dance,
        id: dance.id,
        entity: dance,
        updatedAt: row.updatedAt,
        existenceAt: row.existenceAt ?? row.updatedAt,
        deletedAt: row.deletedAt,
      );
    }

    final programs = await repositories.programs.listAll(includeDeleted: true);
    final programRows = await _db.select(_db.programs).get();
    final programRowsById = {for (final row in programRows) row.id: row};
    for (final program in programs) {
      final row = programRowsById[program.id];
      if (row == null) continue;
      await addEntity(
        kind: SyncRecordKind.program,
        id: program.id,
        entity: program,
        updatedAt: row.updatedAt,
        existenceAt: row.existenceAt ?? row.updatedAt,
        deletedAt: row.deletedAt,
      );
    }

    final choreographerRows = await _db.select(_db.choreographers).get();
    for (final row in choreographerRows) {
      await addEntity(
        kind: SyncRecordKind.choreographer,
        id: row.id,
        entity: Choreographer(
          id: row.id,
          name: row.name,
          website: row.website,
          notes: row.notes,
          email: row.email,
          location: row.location,
          deceased: row.deceased,
        ),
        updatedAt:
            row.updatedAt ??
            row.existenceAt ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        existenceAt:
            row.existenceAt ??
            row.updatedAt ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        deletedAt: row.deletedAt,
      );
    }

    final tagRows = await _db.select(_db.tags).get();
    for (final row in tagRows) {
      await addEntity(
        kind: SyncRecordKind.tag,
        id: row.id,
        entity: Tag(id: row.id, name: row.name, color: row.color),
        updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
        existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
        deletedAt: row.deletedAt,
      );
    }

    final sourceRows = await _db.select(_db.publishedSources).get();
    for (final row in sourceRows) {
      await addEntity(
        kind: SyncRecordKind.publishedSource,
        id: row.id,
        entity: PublishedSource(
          id: row.id,
          title: row.title,
          author: row.author,
          year: row.year,
          url: row.url,
          notes: row.notes,
        ),
        updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
        existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
        deletedAt: row.deletedAt,
      );
    }

    for (final entry in customFields) {
      final row = await (_db.select(
        _db.customFieldDefs,
      )..where((table) => table.id.equals(entry.field.id))).getSingleOrNull();
      if (row == null) continue;
      await addEntity(
        kind: SyncRecordKind.customFieldDef,
        id: entry.field.id,
        entity: entry.field,
        updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
        existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
        deletedAt: row.deletedAt,
      );
    }

    final difficultyRows = await _db.select(_db.difficultyLevels).get();
    for (final row in difficultyRows) {
      await addEntity(
        kind: SyncRecordKind.difficultyLevel,
        id: row.id,
        entity: DifficultyLevel(
          id: row.id,
          label: row.label,
          position: row.position,
        ),
        updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
        existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
        deletedAt: row.deletedAt,
      );
    }

    final venueRows = await _db.select(_db.venues).get();
    for (final row in venueRows) {
      final provenance = await _venueProvenance(row.id);
      await addEntity(
        kind: SyncRecordKind.venue,
        id: row.id,
        entity: Venue(
          id: row.id,
          name: row.name,
          address1: row.address1,
          address2: row.address2,
          city: row.city,
          stateProv: row.stateProv,
          country: row.country,
          postalCode: row.postalCode,
          plus4: row.plus4,
          website: row.website,
          sponsor: row.sponsor,
          eventName: row.eventName,
          time: row.time,
          genericSchedule: row.genericSchedule,
          price: row.price,
          notes: row.notes,
          contact1Name: row.contact1Name,
          contact1Phone: row.contact1Phone,
          contact1Email: row.contact1Email,
          contact2Name: row.contact2Name,
          contact2Phone: row.contact2Phone,
          contact2Email: row.contact2Email,
          provenance: provenance,
        ),
        updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
        existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
        deletedAt: row.deletedAt,
      );
    }

    final settingRows = await _db.select(_db.settings).get();
    for (final row in settingRows) {
      if (classifySettingsKey(row.key)?.egress != EgressClass.shareable) {
        continue;
      }
      final blob = SyncSettingsRecord(
        key: row.key,
        value: jsonDecode(row.valueJson),
        updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
        deletedAt: row.deletedAt,
        existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
      ).toBlob();
      if (blob == null) continue;
      final address = (kind: SyncRecordKind.setting, recordId: row.key);
      local[address] = SyncMergeCandidate(
        blob: blob,
        wireHash: sha256Hex(encodeSyncRecordBlobUtf8(blob)),
      );
    }

    final publication = <SyncRecordAddress, SyncMergeCandidate?>{...local};
    final pendingLive = <SyncRecordAddress, SyncMergeCandidate?>{};
    final pendingAddresses = <SyncRecordAddress>{};
    final pendingRows = await repositories.syncLocal.listPendingDeletions();
    for (final row in pendingRows) {
      final blob = decodeSyncRecordBlob(row.tombstoneBlob);
      final hash = sha256Hex(encodeSyncRecordBlobUtf8(blob));
      if (blob.kind != row.kind ||
          blob.id != row.recordId ||
          hash != row.tombstoneHash ||
          blob.deletedAt == null) {
        throw StateError(
          'pending tombstone does not match its stored identity or hash',
        );
      }
      final address = (kind: row.kind, recordId: row.recordId);
      pendingLive[address] = local[address];
      local.remove(address);
      publication[address] = SyncMergeCandidate(blob: blob, wireHash: hash);
      pendingAddresses.add(address);
    }

    return SyncStorageSnapshot(
      epoch: baselineState?.epoch,
      previouslyUsed:
          syncId != null &&
          usedVerifiers.any((verifier) => verifier.matches(syncId)),
      local: local,
      baseline: baseline,
      publication: publication,
      pendingLive: pendingLive,
      pending: pendingAddresses,
    );
  });

  /// Revalidates pending tombstones against the complete current library.
  ///
  /// Archive merge restores must not use only the archive's written records:
  /// untouched local rows can still cite a pending record.
  Future<void> revalidatePendingDeletions({bool dropMissing = false}) =>
      repositories.transaction(
        () => revalidatePendingDeletionsInTransaction(dropMissing: dropMissing),
      );

  /// Revalidates pending tombstones within an already-open repository
  /// transaction. The caller owns the transaction boundary.
  Future<void> revalidatePendingDeletionsInTransaction({
    bool dropMissing = false,
  }) => _revalidatePendingDeletions(dropMissing: dropMissing);

  /// Applies pending tombstones whose final local citation disappeared.
  ///
  /// This runs before every snapshot so a citation removed by an ordinary
  /// repository transaction is observed by the next pass without requiring a
  /// separate sync trigger.
  Future<void> _revalidatePendingDeletions({bool dropMissing = false}) async {
    final rows = await repositories.syncLocal.listPendingDeletions();
    for (final row in rows) {
      if (await _hasCitation(row.kind, row.recordId)) continue;
      final blob = decodeSyncRecordBlob(row.tombstoneBlob);
      if (blob.kind != row.kind ||
          blob.id != row.recordId ||
          blob.deletedAt == null ||
          sha256Hex(encodeSyncRecordBlobUtf8(blob)) != row.tombstoneHash) {
        throw StateError(
          'pending tombstone does not match its stored identity or hash',
        );
      }
      final current = await read((kind: blob.kind, recordId: blob.id));
      if (current == null && dropMissing) {
        await repositories.syncLocal.deletePendingDeletion(
          kind: row.kind,
          recordId: row.recordId,
        );
        continue;
      }
      final body = _overlay(
        Map<String, Object?>.from(current ?? const {}),
        blob.body,
      );
      final record = SyncApplyRecord(
        address: (kind: blob.kind, recordId: blob.id),
        body: body,
        updatedAt: blob.updatedAt,
        deletedAt: blob.deletedAt,
        existenceAt: blob.existenceAt,
        sourceBlob: blob,
      );
      await writeWithReport(record);
      await repositories.syncLocal.deletePendingDeletion(
        kind: row.kind,
        recordId: row.recordId,
      );
    }
  }

  Map<String, Object?> _overlay(
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

  Future<bool> _hasCitation(
    SyncRecordKind kind,
    String recordId, {
    bool ignoreInboundTombstones = false,
  }) async {
    Future<bool> ownerRemainsLive(
      SyncRecordKind ownerKind,
      String ownerId,
    ) async {
      if (ignoreInboundTombstones &&
          _inboundTombstonedAddresses.contains((
            kind: ownerKind,
            recordId: ownerId,
          ))) {
        return false;
      }
      switch (ownerKind) {
        case SyncRecordKind.dance:
          final row = await (_db.select(
            _db.dances,
          )..where((table) => table.id.equals(ownerId))).getSingleOrNull();
          return row != null && row.deletedAt == null;
        case SyncRecordKind.program:
          final row = await (_db.select(
            _db.programs,
          )..where((table) => table.id.equals(ownerId))).getSingleOrNull();
          return row != null && row.deletedAt == null;
        case SyncRecordKind.choreographer:
        case SyncRecordKind.tag:
        case SyncRecordKind.publishedSource:
        case SyncRecordKind.customFieldDef:
        case SyncRecordKind.difficultyLevel:
        case SyncRecordKind.venue:
        case SyncRecordKind.setting:
          return false;
      }
    }

    switch (kind) {
      case SyncRecordKind.choreographer:
        final rows = await (_db.select(
          _db.danceAuthors,
        )..where((row) => row.choreographerId.equals(recordId))).get();
        for (final row in rows) {
          if (await ownerRemainsLive(SyncRecordKind.dance, row.danceId)) {
            return true;
          }
        }
        return false;
      case SyncRecordKind.tag:
        final rows = await (_db.select(
          _db.danceTags,
        )..where((row) => row.tagId.equals(recordId))).get();
        for (final row in rows) {
          if (await ownerRemainsLive(SyncRecordKind.dance, row.danceId)) {
            return true;
          }
        }
        return false;
      case SyncRecordKind.publishedSource:
        final rows = await (_db.select(
          _db.danceSources,
        )..where((row) => row.sourceId.equals(recordId))).get();
        for (final row in rows) {
          if (await ownerRemainsLive(SyncRecordKind.dance, row.danceId)) {
            return true;
          }
        }
        return false;
      case SyncRecordKind.customFieldDef:
        final rows = await (_db.select(
          _db.customFieldValues,
        )..where((row) => row.fieldId.equals(recordId))).get();
        for (final row in rows) {
          if (await ownerRemainsLive(SyncRecordKind.dance, row.danceId)) {
            return true;
          }
        }
        return false;
      case SyncRecordKind.difficultyLevel:
        final rows = await (_db.select(
          _db.dances,
        )..where((row) => row.levelId.equals(recordId))).get();
        for (final row in rows) {
          if (await ownerRemainsLive(SyncRecordKind.dance, row.id)) {
            return true;
          }
        }
        return false;
      case SyncRecordKind.venue:
        final rows = await (_db.select(
          _db.programs,
        )..where((row) => row.venueId.equals(recordId))).get();
        for (final row in rows) {
          if (await ownerRemainsLive(SyncRecordKind.program, row.id)) {
            return true;
          }
        }
        return false;
      case SyncRecordKind.dance:
        final slots = await (_db.select(
          _db.programSlots,
        )..where((row) => row.danceId.equals(recordId))).get();
        for (final row in slots) {
          if (await ownerRemainsLive(SyncRecordKind.program, row.programId)) {
            return true;
          }
        }
        final links = await (_db.select(
          _db.danceLinks,
        )..where((row) => row.targetDanceId.equals(recordId))).get();
        for (final row in links) {
          if (await ownerRemainsLive(SyncRecordKind.dance, row.danceId)) {
            return true;
          }
        }
        return false;
      case SyncRecordKind.program:
      case SyncRecordKind.setting:
        return false;
    }
  }

  Future<void> markSyncUsed(String syncId) async {
    final verifiers = await _loadUsedIdentityVerifiers(syncId);
    if (verifiers.any((verifier) => verifier.matches(syncId))) return;
    final next = [...verifiers, _StoredSyncIdentityVerifier.create(syncId)];
    final encoded = next.map((verifier) => verifier.toJson()).toList()
      ..sort(
        (left, right) => (left['verifier']! as String).compareTo(
          right['verifier']! as String,
        ),
      );
    await repositories.settings.set(syncLastUsedFingerprintKey, encoded);
  }

  /// Atomically records publication intent before the manifest request.
  ///
  /// The verifier is deliberately conservative: once a manifest is prepared,
  /// a later crash or network failure must still require replacement
  /// confirmation if the server accepted that publication.
  Future<void> markPublicationAttempt({
    required String syncId,
    required Iterable<SyncRecordAddress> records,
  }) => repositories.transaction(() async {
    await repositories.syncLocal.markPublishedAll(records);
    await markSyncUsed(syncId);
  });

  Future<List<_StoredSyncIdentityVerifier>> _loadUsedIdentityVerifiers(
    String? syncId,
  ) async {
    final marker = await repositories.settings.get(syncLastUsedFingerprintKey);
    final verifiers = _decodeUsedIdentityVerifiers(marker);
    final legacyFingerprints = _decodeLegacyIdentityFingerprints(marker);
    if (legacyFingerprints.isEmpty) return verifiers;

    final migrated = [...verifiers];
    if (syncId != null &&
        legacyFingerprints.contains(_legacyIdentityFingerprint(syncId))) {
      migrated.add(_StoredSyncIdentityVerifier.create(syncId));
    }
    await repositories.settings.set(
      syncLastUsedFingerprintKey,
      migrated.map((verifier) => verifier.toJson()).toList(),
    );
    return migrated;
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) =>
      repositories.transaction(action);

  /// Resolves the one review reason whose user decision is normative in W14.
  ///
  /// The queue row is re-read inside the transaction so a stale screen cannot
  /// clear a replacement candidate. The inherited queue has no historical
  /// local hash, so this deliberately validates the current natural-key target
  /// rather than claiming to detect every edit made after enqueue.
  Future<void> resolveReviewQueue({
    required ReviewQueueRow expectedRow,
    required SyncReviewAction action,
    String? newNaturalKey,
  }) => repositories.transaction(() async {
    final currentRow = await repositories.syncLocal.getReviewQueue(
      kind: expectedRow.kind,
      recordId: expectedRow.recordId,
      counterpartId: expectedRow.counterpartId,
    );
    if (currentRow == null || !_sameReviewQueueRow(currentRow, expectedRow)) {
      throw const SyncReviewException(SyncReviewFailureCode.candidateChanged);
    }
    final SyncRecordBlob candidate;
    try {
      candidate = decodeSyncRecordBlob(currentRow.candidateBlob);
    } on Object {
      throw const SyncReviewException(SyncReviewFailureCode.candidateInvalid);
    }
    if (currentRow.candidateHash !=
            sha256Hex(encodeSyncRecordBlobUtf8(candidate)) ||
        currentRow.candidateHash != expectedRow.candidateHash ||
        candidate.kind != currentRow.kind ||
        candidate.id != currentRow.counterpartId ||
        candidate.body['id'] != candidate.id ||
        candidate.deletedAt == null ||
        currentRow.recordId == candidate.id ||
        !syncNaturalKeyKinds.contains(candidate.kind) ||
        syncNaturalKeyForBody(candidate.kind, candidate.body) == null) {
      throw const SyncReviewException(SyncReviewFailureCode.candidateInvalid);
    }
    try {
      validateSyncReviewCandidateBody(candidate.kind, candidate.body);
    } on Object {
      throw const SyncReviewException(SyncReviewFailureCode.candidateInvalid);
    }
    if (currentRow.reason != syncBaselineAbsenceTombstoneReason) {
      throw const SyncReviewException(SyncReviewFailureCode.unsupportedReason);
    }

    final localAddress = (kind: currentRow.kind, recordId: currentRow.recordId);
    final localBody = await read(localAddress);
    final localMetadata = await _naturalRecordMetadata(
      currentRow.kind,
      currentRow.recordId,
    );
    if (localBody == null ||
        localMetadata == null ||
        localMetadata.deletedAt != null) {
      throw const SyncReviewException(SyncReviewFailureCode.targetMissing);
    }
    final queuedCandidateAddress = (
      kind: candidate.kind,
      recordId: candidate.id,
    );
    if (await repositories.syncLocal.resolveAlias(
          kind: candidate.kind,
          recordId: candidate.id,
        ) !=
        candidate.id) {
      throw const SyncReviewException(SyncReviewFailureCode.candidateChanged);
    }
    if (await read(queuedCandidateAddress) != null) {
      throw const SyncReviewException(
        SyncReviewFailureCode.candidateAlreadyPresent,
      );
    }
    final candidateKey = syncNaturalKeyForBody(candidate.kind, candidate.body)!;
    final localKey = syncNaturalKeyForBody(currentRow.kind, localBody);
    if (localKey == null || localKey != candidateKey) {
      throw const SyncReviewException(SyncReviewFailureCode.candidateChanged);
    }

    var candidateForApply = candidate;
    switch (action) {
      case SyncReviewAction.merge:
        final localIdentity = await _recordIdentity(
          currentRow.kind,
          currentRow.recordId,
        );
        if (localIdentity == null) {
          throw const SyncReviewException(SyncReviewFailureCode.targetMissing);
        }
        final canonicalDifficultyId =
            currentRow.kind == SyncRecordKind.difficultyLevel
            ? _canonicalDifficultyId(
                candidateKey,
                candidateId: candidate.id,
                incumbentId: currentRow.recordId,
              )
            : null;
        final survivorId =
            canonicalDifficultyId ??
            (currentRow.recordId.compareTo(candidate.id) <= 0
                ? currentRow.recordId
                : candidate.id);
        final aliases = <SyncRecordKind, Map<String, String>>{};
        if (currentRow.recordId != survivorId) {
          await _adoptCollision(
            kind: currentRow.kind,
            losingId: currentRow.recordId,
            survivingId: survivorId,
            aliases: aliases,
            localIdentity: localIdentity,
          );
        }
        if (candidate.id != survivorId) {
          await _adoptCollision(
            kind: currentRow.kind,
            losingId: candidate.id,
            survivingId: survivorId,
            aliases: aliases,
          );
          candidateForApply = _rewriteCandidateIdentity(
            SyncMergeCandidate(blob: candidate),
            survivorId,
            aliases,
            preserveUpdatedAt: true,
          ).blob;
        }
        break;
      case SyncReviewAction.keepBoth:
        final renamedKey = _validatedReviewName(
          newNaturalKey,
          currentKey: localKey,
        );
        final occupied = await _naturalKeyRow(
          currentRow.kind,
          normalizeShareableText(renamedKey).toLowerCase(),
        );
        if (occupied != null) {
          throw const SyncReviewException(
            SyncReviewFailureCode.nameNotDistinct,
          );
        }
        await _renameLocalNaturalKey(
          currentRow.kind,
          currentRow.recordId,
          renamedKey,
        );
    }

    final candidateAddress = (
      kind: candidateForApply.kind,
      recordId: candidateForApply.id,
    );
    final currentCandidateBody = Map<String, Object?>.from(
      await read(candidateAddress) ?? const {},
    );
    final report = await writeWithReport(
      SyncApplyRecord(
        address: candidateAddress,
        body: _overlay(currentCandidateBody, candidateForApply.body),
        updatedAt: candidateForApply.updatedAt,
        deletedAt: candidateForApply.deletedAt,
        existenceAt: candidateForApply.existenceAt,
        sourceBlob: candidateForApply,
      ),
    );
    if (report != null) {
      throw StateError(report.message);
    }
    await rebuildDerivedIndexes();
    await repositories.syncLocal.deleteReview(
      kind: currentRow.kind,
      recordId: currentRow.recordId,
      counterpartId: currentRow.counterpartId,
    );
  });

  bool _sameReviewQueueRow(ReviewQueueRow left, ReviewQueueRow right) =>
      left.kind == right.kind &&
      left.recordId == right.recordId &&
      left.counterpartId == right.counterpartId &&
      left.reason == right.reason &&
      left.candidateBlob == right.candidateBlob &&
      left.candidateHash == right.candidateHash &&
      left.queuedAt == right.queuedAt;

  String _validatedReviewName(String? raw, {required String currentKey}) {
    if (raw == null) {
      throw const SyncReviewException(SyncReviewFailureCode.nameRequired);
    }
    final normalized = normalizeShareableText(raw);
    if (normalized.trim().isEmpty) {
      throw const SyncReviewException(SyncReviewFailureCode.nameRequired);
    }
    if (normalizeShareableText(normalized).toLowerCase() == currentKey) {
      throw const SyncReviewException(SyncReviewFailureCode.nameNotDistinct);
    }
    return normalized;
  }

  Future<void> _renameLocalNaturalKey(
    SyncRecordKind kind,
    String id,
    String value,
  ) async {
    final normalized = normalizeShareableText(value);
    final stamp = nextExistenceStamp(
      now: DateTime.now().toUtc(),
      current: (await _naturalRecordMetadata(kind, id))?.updatedAt,
    );
    switch (kind) {
      case SyncRecordKind.choreographer:
        await (_db.update(
          _db.choreographers,
        )..where((row) => row.id.equals(id))).write(
          ChoreographersCompanion(
            name: Value(normalized),
            updatedAt: Value(stamp),
          ),
        );
      case SyncRecordKind.tag:
        await (_db.update(_db.tags)..where((row) => row.id.equals(id))).write(
          TagsCompanion(name: Value(normalized), updatedAt: Value(stamp)),
        );
      case SyncRecordKind.customFieldDef:
        await (_db.update(
          _db.customFieldDefs,
        )..where((row) => row.id.equals(id))).write(
          CustomFieldDefsCompanion(
            key: Value(normalized),
            updatedAt: Value(stamp),
          ),
        );
      case SyncRecordKind.difficultyLevel:
        await (_db.update(
          _db.difficultyLevels,
        )..where((row) => row.id.equals(id))).write(
          DifficultyLevelsCompanion(
            label: Value(normalized),
            updatedAt: Value(stamp),
          ),
        );
      case SyncRecordKind.dance:
      case SyncRecordKind.program:
      case SyncRecordKind.publishedSource:
      case SyncRecordKind.venue:
      case SyncRecordKind.setting:
        throw const SyncReviewException(
          SyncReviewFailureCode.unsupportedReason,
        );
    }
    if (_naturalKeyIndex != null) {
      final identity = await _recordIdentity(kind, id);
      if (identity != null) {
        _naturalKeyIndex!.replace(
          kind: kind,
          id: id,
          key: normalized.toLowerCase(),
          type: identity.type,
          deleted: identity.deleted,
          shareable: identity.shareable,
        );
      }
    }
  }

  @override
  Future<Map<String, Object?>?> read(SyncRecordAddress address) async {
    if (address.kind == SyncRecordKind.setting) {
      final row =
          await (_db.select(_db.settings)
                ..where((table) => table.key.equals(address.recordId)))
              .getSingleOrNull();
      return row == null ? null : {'value': jsonDecode(row.valueJson)};
    }

    final body = switch (address.kind) {
      SyncRecordKind.dance => await _readDanceBody(address.recordId),
      SyncRecordKind.program => await _readProgramBody(address.recordId),
      SyncRecordKind.choreographer => await _readChoreographerBody(
        address.recordId,
      ),
      SyncRecordKind.tag => await _readTagBody(address.recordId),
      SyncRecordKind.publishedSource => await _readPublishedSourceBody(
        address.recordId,
      ),
      SyncRecordKind.customFieldDef => await _readCustomFieldBody(
        address.recordId,
      ),
      SyncRecordKind.difficultyLevel => await _readDifficultyBody(
        address.recordId,
      ),
      SyncRecordKind.venue => await _readVenueBody(address.recordId),
      SyncRecordKind.setting => throw StateError('handled above'),
    };
    return body;
  }

  @override
  Future<Map<SyncRecordAddress, SyncMergeCandidate?>>
  snapshotCandidates() async => (await snapshot()).local;

  Future<_NaturalKeyIndex> _loadNaturalKeyIndex() async {
    final index = _NaturalKeyIndex({});
    final choreographers = await _db.select(_db.choreographers).get();
    for (final row in choreographers) {
      index.add(
        kind: SyncRecordKind.choreographer,
        key: normalizeShareableText(row.name).toLowerCase(),
        value: (
          id: row.id,
          type: null,
          deleted: row.deletedAt != null,
          shareable: true,
        ),
      );
    }
    final tags = await _db.select(_db.tags).get();
    for (final row in tags) {
      index.add(
        kind: SyncRecordKind.tag,
        key: normalizeShareableText(row.name).toLowerCase(),
        value: (
          id: row.id,
          type: null,
          deleted: row.deletedAt != null,
          shareable: true,
        ),
      );
    }
    final customFields = await _db.select(_db.customFieldDefs).get();
    for (final row in customFields) {
      index.add(
        kind: SyncRecordKind.customFieldDef,
        key: normalizeShareableText(row.key).toLowerCase(),
        value: (
          id: row.id,
          type: row.type.name,
          deleted: row.deletedAt != null,
          shareable: row.shareable,
        ),
      );
    }
    final difficultyLevels = await _db.select(_db.difficultyLevels).get();
    for (final row in difficultyLevels) {
      index.add(
        kind: SyncRecordKind.difficultyLevel,
        key: normalizeShareableText(row.label).toLowerCase(),
        value: (
          id: row.id,
          type: null,
          deleted: row.deletedAt != null,
          shareable: true,
        ),
      );
    }
    return index;
  }

  @override
  Future<SyncApplyPreparation> reconcileInbound(
    List<SyncMergeCandidate> candidates, {
    Map<SyncRecordAddress, String?>? expectedWireHashes,
  }) async {
    final previousNaturalKeyIndex = _naturalKeyIndex;
    _naturalKeyIndex = await _loadNaturalKeyIndex();
    _inboundTombstonedAddresses = {};
    try {
      return await _reconcileInbound(
        candidates,
        expectedWireHashes: expectedWireHashes,
      );
    } finally {
      _naturalKeyIndex = previousNaturalKeyIndex;
    }
  }

  Future<SyncApplyPreparation> _reconcileInbound(
    List<SyncMergeCandidate> candidates, {
    Map<SyncRecordAddress, String?>? expectedWireHashes,
  }) async {
    final aliases = await _aliasMap();
    final baseline = await repositories.syncLocal.snapshotBaseline();
    final prepared = <SyncMergeCandidate>[];
    final reports = <SyncReport>[];
    final preparedNatural = <({SyncRecordKind kind, String key}), int>{};
    for (var candidate in candidates) {
      final preflightReport = _preflightInboundCandidate(candidate);
      if (preflightReport != null) {
        if (candidate.blob.kind == SyncRecordKind.customFieldDef &&
            candidate.blob.body['shareable'] == false) {
          // Keep the rejected definition in the validation context so
          // dependent inbound dances receive the same classification report.
          // It must not enter natural-key reconciliation, which can migrate
          // local identities before the final semantic validation.
          prepared.add(candidate);
        } else {
          reports.add(preflightReport);
        }
        continue;
      }
      final kind = candidate.blob.kind;
      if (syncNaturalKeyKinds.contains(kind)) {
        final originalAddress = candidate.address;
        candidate = _rewriteCandidate(candidate, aliases);
        if (candidate.address != originalAddress &&
            !await _guardReconciliationTarget(
              kind: candidate.blob.kind,
              recordId: candidate.blob.id,
              expectedWireHashes: expectedWireHashes,
              reports: reports,
            )) {
          continue;
        }
        final inboundCandidateId = candidate.blob.id;
        final naturalKey = syncNaturalKeyForBody(kind, candidate.blob.body);
        if (naturalKey != null) {
          final byId = await _recordIdentity(kind, candidate.blob.id);
          final incumbent = await _naturalKeyRow(kind, naturalKey);

          if (kind == SyncRecordKind.difficultyLevel &&
              incumbent != null &&
              candidate.blob.id != incumbent.id &&
              DifficultyLevel.shippedIds.contains(candidate.blob.id) &&
              DifficultyLevel.shippedIds.contains(incumbent.id)) {
            await _enqueueCollisionReview(
              candidate,
              incumbent.id,
              reason: 'two distinct shipped difficulty IDs share a natural key',
            );
            continue;
          }

          // Shipped difficulty IDs are part of the persisted relationship
          // contract and outrank a same-label custom ID.
          final canonicalDifficultyId = kind == SyncRecordKind.difficultyLevel
              ? _canonicalDifficultyId(
                  naturalKey,
                  candidateId: candidate.blob.id,
                  incumbentId: incumbent?.id,
                )
              : null;
          if (canonicalDifficultyId != null) {
            if (byId != null && incumbent != null && byId.id != incumbent.id) {
              await _enqueueCollisionReview(
                candidate,
                incumbent.id,
                reason:
                    'known UUID natural-key rename collides with '
                    'the shipped difficulty row',
              );
              continue;
            }
            if (incumbent != null) {
              if (candidate.blob.deletedAt != null &&
                  !incumbent.deleted &&
                  !baseline.containsKey((kind: kind, recordId: incumbent.id))) {
                await _enqueueCollisionReview(
                  candidate,
                  candidate.blob.id,
                  recordId: incumbent.id,
                  reason:
                      'a tombstone would remove a locally-created '
                      'natural-key row before a peer observed it',
                );
                continue;
              }
              if (!await _guardReconciliationTarget(
                kind: kind,
                recordId: incumbent.id,
                expectedWireHashes: expectedWireHashes,
                reports: reports,
              )) {
                continue;
              }
              final localCandidate = await _localNaturalCandidate(
                kind: kind,
                id: incumbent.id,
              );
              if (localCandidate == null) continue;
              final reconciled = await _reconcileNaturalKeyCollision(
                candidate: candidate,
                local: localCandidate,
                survivorId: canonicalDifficultyId,
              );
              if (reconciled == null) continue;
              candidate = reconciled;
            }
            if (incumbent != null && incumbent.id != canonicalDifficultyId) {
              if (!await _guardReconciliationTarget(
                kind: kind,
                recordId: canonicalDifficultyId,
                expectedWireHashes: expectedWireHashes,
                reports: reports,
              )) {
                continue;
              }
              await _adoptCollision(
                kind: kind,
                losingId: incumbent.id,
                survivingId: canonicalDifficultyId,
                aliases: aliases,
                localIdentity: incumbent,
              );
            }
            if (inboundCandidateId != canonicalDifficultyId &&
                inboundCandidateId != incumbent?.id) {
              if (!await _guardReconciliationTarget(
                kind: kind,
                recordId: inboundCandidateId,
                expectedWireHashes: expectedWireHashes,
                reports: reports,
              )) {
                continue;
              }
              await _adoptCollision(
                kind: kind,
                losingId: inboundCandidateId,
                survivingId: canonicalDifficultyId,
                aliases: aliases,
                localIdentity: byId,
              );
            }
            candidate = _rewriteCandidateIdentity(
              candidate,
              canonicalDifficultyId,
              aliases,
            );
          } else if (byId != null &&
              incumbent != null &&
              incumbent.id != candidate.blob.id) {
            await _enqueueCollisionReview(
              candidate,
              incumbent.id,
              reason:
                  'known UUID natural-key rename collides with '
                  'another local row',
            );
            continue;
          } else if (incumbent != null &&
              kind == SyncRecordKind.customFieldDef &&
              incumbent.shareable == false &&
              candidate.blob.body['shareable'] == true) {
            if (incumbent.id == candidate.blob.id) {
              await _enqueueCollisionReview(
                candidate,
                incumbent.id,
                reason:
                    'a shareable inbound definition cannot replace a '
                    'private local definition',
              );
              continue;
            }
            final renamed = await _renameInboundCustomField(
              candidate,
              incumbent.id,
              reason:
                  'shareability mismatch cannot reconcile a private '
                  'custom-field definition',
            );
            if (renamed == null) continue;
            candidate = renamed;
          } else if (incumbent != null && incumbent.id != candidate.blob.id) {
            if (candidate.blob.deletedAt != null &&
                !incumbent.deleted &&
                !baseline.containsKey((kind: kind, recordId: incumbent.id))) {
              await _enqueueCollisionReview(
                candidate,
                candidate.blob.id,
                recordId: incumbent.id,
                reason:
                    'a tombstone would remove a locally-created '
                    'natural-key row before a peer observed it',
              );
              continue;
            }
            if (!await _guardReconciliationTarget(
              kind: kind,
              recordId: incumbent.id,
              expectedWireHashes: expectedWireHashes,
              reports: reports,
            )) {
              continue;
            }

            if (kind == SyncRecordKind.customFieldDef &&
                incumbent.type != _customFieldType(candidate.blob.body)) {
              final reconciled = await _reconcileCustomFieldTypeMismatch(
                candidate,
                incumbent,
              );
              if (reconciled == null) continue;
              candidate = reconciled;
            } else {
              final localCandidate = await _localNaturalCandidate(
                kind: kind,
                id: incumbent.id,
              );
              if (localCandidate == null) {
                continue;
              }
              final survivingId = candidate.blob.id.compareTo(incumbent.id) < 0
                  ? candidate.blob.id
                  : incumbent.id;
              final reconciled = await _reconcileNaturalKeyCollision(
                candidate: candidate,
                local: localCandidate,
                survivorId: survivingId,
              );
              if (reconciled == null) continue;
              if (!await _guardReconciliationTarget(
                kind: kind,
                recordId: survivingId,
                expectedWireHashes: expectedWireHashes,
                reports: reports,
              )) {
                continue;
              }
              await _adoptCollision(
                kind: kind,
                losingId: survivingId == candidate.blob.id
                    ? incumbent.id
                    : candidate.blob.id,
                survivingId: survivingId,
                aliases: aliases,
                localIdentity: survivingId == incumbent.id ? null : incumbent,
              );
              candidate = reconciled;
            }
          }
        }
      } else {
        candidate = _rewriteCandidate(candidate, aliases);
      }
      final naturalKey = syncNaturalKeyKinds.contains(kind)
          ? syncNaturalKeyForBody(kind, candidate.blob.body)
          : null;
      if (naturalKey != null) {
        final naturalAddress = (kind: kind, key: naturalKey);
        final previousIndex = preparedNatural[naturalAddress];
        if (previousIndex != null) {
          final previous = prepared[previousIndex];
          if (kind == SyncRecordKind.customFieldDef &&
              _customFieldType(previous.blob.body) !=
                  _customFieldType(candidate.blob.body)) {
            final incomingWins =
                candidate.blob.id.compareTo(previous.blob.id) < 0;
            final losing = incomingWins ? previous : candidate;
            final losingKey = losing.blob.body['key'];
            if (losingKey is! String) continue;
            final shortKey = syncCustomFieldSuffix(
              losingKey,
              losing.blob.id,
              full: false,
            );
            final fullKey = syncCustomFieldSuffix(
              losingKey,
              losing.blob.id,
              full: true,
            );
            Future<bool> isOccupied(String key) async {
              final address = (
                kind: SyncRecordKind.customFieldDef,
                key: key.toLowerCase(),
              );
              if (preparedNatural.containsKey(address) &&
                  preparedNatural[address] != previousIndex) {
                return true;
              }
              return await _naturalKeyRow(
                    SyncRecordKind.customFieldDef,
                    key.toLowerCase(),
                  ) !=
                  null;
            }

            final suffix = !await isOccupied(shortKey)
                ? shortKey
                : !await isOccupied(fullKey)
                ? fullKey
                : null;
            if (suffix == null) {
              await _enqueueCollisionReview(
                candidate,
                previous.blob.id,
                reason:
                    'custom-field type mismatch has no deterministic free key',
              );
              continue;
            }
            final losingBody = Map<String, Object?>.from(losing.blob.body)
              ..['key'] = suffix;
            final renamed = _candidateWithBody(
              losing,
              losing.blob.id,
              losingBody,
              updatedAt: nextExistenceStamp(
                now: DateTime.now().toUtc(),
                current: losing.blob.updatedAt,
              ),
            );
            if (incomingWins) {
              prepared[previousIndex] = renamed;
              preparedNatural.remove(naturalAddress);
              preparedNatural[(
                    kind: SyncRecordKind.customFieldDef,
                    key: suffix.toLowerCase(),
                  )] =
                  previousIndex;
              preparedNatural[naturalAddress] = prepared.length;
            } else {
              candidate = renamed;
              preparedNatural[(
                    kind: SyncRecordKind.customFieldDef,
                    key: suffix.toLowerCase(),
                  )] =
                  prepared.length;
            }
          } else {
            final survivingId =
                candidate.blob.id.compareTo(previous.blob.id) < 0
                ? candidate.blob.id
                : previous.blob.id;
            final reconciled = await _reconcileNaturalKeyCollision(
              candidate: candidate,
              local: previous,
              survivorId: survivingId,
            );
            if (reconciled == null) continue;
            await _adoptCollision(
              kind: kind,
              losingId: survivingId == candidate.blob.id
                  ? previous.blob.id
                  : candidate.blob.id,
              survivingId: survivingId,
              aliases: aliases,
              localIdentity: null,
            );
            prepared[previousIndex] = reconciled;
            continue;
          }
        } else {
          preparedNatural[naturalAddress] = prepared.length;
        }
      }
      prepared.add(candidate);
    }
    return SyncApplyPreparation(candidates: prepared, reports: reports);
  }

  @override
  Future<void> setInboundTombstoneContext(
    Set<SyncRecordAddress> tombstonedAddresses,
  ) async {
    _inboundTombstonedAddresses = Set<SyncRecordAddress>.of(
      tombstonedAddresses,
    );
  }

  @override
  Future<void> clearReconciliationContext() async {
    _inboundTombstonedAddresses = {};
    _naturalKeyIndex = null;
  }

  SyncReport? _preflightInboundCandidate(SyncMergeCandidate candidate) {
    final validation = validateShareableRecordBody(
      candidate.blob.kind,
      candidate.blob.body,
      settingsKey: candidate.blob.kind == SyncRecordKind.setting
          ? candidate.blob.id
          : null,
    );
    if (!validation.isValid) {
      return SyncReport(
        code: SyncReportCode.invalidClassification,
        kind: candidate.blob.kind,
        recordId: candidate.blob.id,
        message:
            'Inbound body contains a non-shareable wire path '
            '${validation.invalidPath}.',
      );
    }
    if (candidate.blob.kind == SyncRecordKind.customFieldDef &&
        candidate.blob.body['shareable'] == false) {
      return SyncReport(
        code: SyncReportCode.invalidClassification,
        kind: candidate.blob.kind,
        recordId: candidate.blob.id,
        message:
            'Inbound custom-field definition '
            '"${candidate.blob.id}" is not shareable.',
      );
    }
    if (candidate.blob.kind == SyncRecordKind.setting &&
        (candidate.blob.id == 'sync_id' ||
            candidate.blob.id == 'sync_device_id')) {
      return SyncReport(
        code: SyncReportCode.invalidClassification,
        kind: candidate.blob.kind,
        recordId: candidate.blob.id,
        message:
            'Inbound sync credentials are receive-only and were not adopted.',
      );
    }

    final Object? normalized;
    try {
      normalized = normalizeShareableJson(candidate.blob.body);
    } on ArgumentError catch (error) {
      return SyncReport(
        code: SyncReportCode.malformedRecord,
        kind: candidate.blob.kind,
        recordId: candidate.blob.id,
        message: 'Inbound record body could not be normalized: $error.',
      );
    } on ShareableJsonKeyCollision catch (error) {
      return SyncReport(
        code: SyncReportCode.malformedRecord,
        kind: candidate.blob.kind,
        recordId: candidate.blob.id,
        message:
            'Inbound record body has a normalized key collision: '
            '${error.normalizedKey}.',
      );
    }
    if (normalized is! Map) {
      return SyncReport(
        code: SyncReportCode.malformedRecord,
        kind: candidate.blob.kind,
        recordId: candidate.blob.id,
        message: 'Inbound record body is not an object.',
      );
    }
    if (candidate.blob.kind == SyncRecordKind.setting) return null;

    try {
      _decodeEntity(candidate.blob.kind, Map<String, Object?>.from(normalized));
    } on Object catch (error) {
      return SyncReport(
        code: SyncReportCode.malformedRecord,
        kind: candidate.blob.kind,
        recordId: candidate.blob.id,
        message: 'Inbound record could not be decoded: $error.',
      );
    }
    return null;
  }

  Future<Map<SyncRecordKind, Map<String, String>>> _aliasMap() async {
    final result = <SyncRecordKind, Map<String, String>>{};
    for (final row in await repositories.syncLocal.listAliases()) {
      result.putIfAbsent(row.kind, () => <String, String>{})[row.losingId] =
          row.survivingId;
    }
    for (final byKind in result.values) {
      for (final losingId in byKind.keys.toList()) {
        var current = losingId;
        final seen = <String>{losingId};
        while (byKind[current] != null) {
          final next = byKind[current]!;
          if (!seen.add(next)) {
            throw StateError('cyclic sync alias chain');
          }
          current = next;
        }
        byKind[losingId] = current;
      }
    }
    return result;
  }

  SyncMergeCandidate _rewriteCandidate(
    SyncMergeCandidate candidate,
    Map<SyncRecordKind, Map<String, String>> aliases,
  ) {
    final byKind = aliases[candidate.blob.kind];
    final resolvedId = _resolveInMap(candidate.blob.id, byKind);
    final body = rewriteSyncInboundReferences(candidate.blob.body, aliases);
    if (candidate.blob.kind != SyncRecordKind.setting) {
      body['id'] = resolvedId;
    }
    return _candidateWithBody(
      candidate,
      resolvedId,
      body,
      updatedAt: contentHash(candidate.blob.body) == contentHash(body)
          ? null
          : nextExistenceStamp(
              now: DateTime.now().toUtc(),
              current: candidate.blob.updatedAt,
            ),
    );
  }

  SyncMergeCandidate _rewriteCandidateIdentity(
    SyncMergeCandidate candidate,
    String id,
    Map<SyncRecordKind, Map<String, String>> aliases, {
    bool preserveUpdatedAt = false,
  }) {
    final body = rewriteSyncInboundReferences(candidate.blob.body, aliases);
    if (candidate.blob.kind != SyncRecordKind.setting) body['id'] = id;
    return _candidateWithBody(
      candidate,
      id,
      body,
      updatedAt: preserveUpdatedAt
          ? candidate.blob.updatedAt
          : contentHash(candidate.blob.body) == contentHash(body)
          ? null
          : nextExistenceStamp(
              now: DateTime.now().toUtc(),
              current: candidate.blob.updatedAt,
            ),
    );
  }

  SyncMergeCandidate _candidateWithBody(
    SyncMergeCandidate candidate,
    String id,
    Map<String, Object?> body, {
    DateTime? updatedAt,
  }) {
    final blob = SyncRecordBlob(
      v: candidate.blob.v,
      kind: candidate.blob.kind,
      id: id,
      updatedAt: updatedAt ?? candidate.blob.updatedAt,
      deletedAt: candidate.blob.deletedAt,
      existenceAt: candidate.blob.existenceAt,
      body: body,
    );
    return SyncMergeCandidate(blob: blob);
  }

  String _resolveInMap(String id, Map<String, String>? aliases) {
    if (aliases == null) return id;
    var current = id;
    final seen = <String>{id};
    while (aliases[current] != null) {
      final next = aliases[current]!;
      if (!seen.add(next)) throw StateError('cyclic sync alias chain');
      current = next;
    }
    return current;
  }

  Future<void> _adoptCollision({
    required SyncRecordKind kind,
    required String losingId,
    required String survivingId,
    required Map<SyncRecordKind, Map<String, String>> aliases,
    _NaturalKeyValue? localIdentity,
  }) async {
    if (losingId == survivingId) return;
    final target = await repositories.syncLocal.resolveAlias(
      kind: kind,
      recordId: survivingId,
    );
    final targetIdentity = await _recordIdentity(kind, target);
    if (localIdentity != null && localIdentity.id == losingId) {
      if (target == survivingId && targetIdentity == null) {
        await _migrateLocalIdentity(kind, losingId, target);
      } else if (targetIdentity != null) {
        await _rewriteLocalReferences(kind, losingId, target);
        await _deleteIdentityRow(kind, losingId);
      }
    }
    await _rewriteLocalReferences(kind, losingId, target);
    await _remapPendingDeletions(
      kind: kind,
      losingId: losingId,
      survivingId: target,
      aliases: aliases,
    );
    await repositories.syncLocal.remapIdentity(
      kind: kind,
      losingId: losingId,
      survivingId: target,
    );
    _naturalKeyIndex?.removeId(kind, losingId);
    final byKind = aliases.putIfAbsent(kind, () => <String, String>{});
    for (final entry in byKind.entries.toList()) {
      if (entry.value == losingId) byKind[entry.key] = target;
    }
    byKind[losingId] = target;
  }

  Future<void> _remapPendingDeletions({
    required SyncRecordKind kind,
    required String losingId,
    required String survivingId,
    required Map<SyncRecordKind, Map<String, String>> aliases,
  }) async {
    if (losingId == survivingId) return;
    final persistedAliases = await repositories.syncLocal.listAliases();
    final remappedIds = <String>{losingId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final alias in persistedAliases) {
        if (alias.kind == kind &&
            remappedIds.contains(alias.survivingId) &&
            remappedIds.add(alias.losingId)) {
          changed = true;
        }
      }
    }
    final pendingIds = {...remappedIds, survivingId};
    final rows = await _db.select(_db.pendingDeletions).get();
    if (rows.isEmpty) return;

    final rewriteAliases = <SyncRecordKind, Map<String, String>>{
      for (final entry in aliases.entries)
        entry.key: Map<String, String>.from(entry.value),
    };
    for (final alias in persistedAliases) {
      rewriteAliases.putIfAbsent(
        alias.kind,
        () => <String, String>{},
      )[alias.losingId] = alias.survivingId;
    }
    rewriteAliases.putIfAbsent(kind, () => <String, String>{})[losingId] =
        survivingId;

    final candidates =
        <({SyncRecordBlob blob, DateTime tombstonedAt, String hash})>[];
    for (final row in rows) {
      final blob = decodeSyncRecordBlob(row.tombstoneBlob);
      if (blob.kind != row.kind ||
          blob.id != row.recordId ||
          blob.deletedAt == null ||
          sha256Hex(encodeSyncRecordBlobUtf8(blob)) != row.tombstoneHash) {
        throw StateError(
          'pending tombstone does not match its stored identity or hash',
        );
      }
      final remapOwnIdentity =
          row.kind == kind && pendingIds.contains(row.recordId);
      final body = Map<String, Object?>.from(blob.body);
      if (remapOwnIdentity && kind != SyncRecordKind.setting) {
        body['id'] = survivingId;
      }
      final rewrittenBody = rewriteSyncInboundReferences(body, rewriteAliases);
      final remappedId = remapOwnIdentity && kind != SyncRecordKind.setting
          ? survivingId
          : blob.id;
      final remappedUpdatedAt =
          contentHash(blob.body) == contentHash(rewrittenBody)
          ? blob.updatedAt
          : nextExistenceStamp(
              now: DateTime.now().toUtc(),
              current: blob.updatedAt,
            );
      final remapped = SyncRecordBlob(
        v: blob.v,
        kind: blob.kind,
        id: remappedId,
        updatedAt: remappedUpdatedAt,
        deletedAt: blob.deletedAt,
        existenceAt: blob.existenceAt,
        body: rewrittenBody,
      );
      final remappedHash = sha256Hex(encodeSyncRecordBlobUtf8(remapped));
      if (remapOwnIdentity) {
        candidates.add((
          blob: remapped,
          tombstonedAt: row.tombstonedAt,
          hash: remappedHash,
        ));
      } else if (remappedHash != row.tombstoneHash) {
        await repositories.syncLocal.upsertPendingDeletion(
          kind: row.kind,
          recordId: row.recordId,
          tombstonedAt: row.tombstonedAt,
          tombstoneHash: remappedHash,
          tombstoneBlob: encodeSyncRecordBlob(remapped),
        );
      }
    }
    if (candidates.isEmpty) return;
    candidates.sort((a, b) {
      final existence = a.blob.existenceAt.compareTo(b.blob.existenceAt);
      if (existence != 0) return existence;
      final updated = a.blob.updatedAt.compareTo(b.blob.updatedAt);
      if (updated != 0) return updated;
      final tombstoned = a.tombstonedAt.compareTo(b.tombstonedAt);
      if (tombstoned != 0) return tombstoned;
      return a.hash.compareTo(b.hash);
    });
    final selected = candidates.last;
    for (final chunk in _chunked(pendingIds, 500)) {
      await (_db.delete(_db.pendingDeletions)..where(
            (row) => row.kind.equals(kind.name) & row.recordId.isIn(chunk),
          ))
          .go();
    }
    await _db
        .into(_db.pendingDeletions)
        .insert(
          PendingDeletionsCompanion.insert(
            kind: kind,
            recordId: survivingId,
            tombstonedAt: selected.tombstonedAt,
            tombstoneHash: selected.hash,
            tombstoneBlob: encodeSyncRecordBlob(selected.blob),
          ),
        );
  }

  Future<_NaturalKeyValue?> _recordIdentity(
    SyncRecordKind kind,
    String id,
  ) async {
    switch (kind) {
      case SyncRecordKind.choreographer:
        final row = await (_db.select(
          _db.choreographers,
        )..where((table) => table.id.equals(id))).getSingleOrNull();
        return row == null
            ? null
            : (
                id: row.id,
                type: null,
                deleted: row.deletedAt != null,
                shareable: true,
              );
      case SyncRecordKind.tag:
        final row = await (_db.select(
          _db.tags,
        )..where((table) => table.id.equals(id))).getSingleOrNull();
        return row == null
            ? null
            : (
                id: row.id,
                type: null,
                deleted: row.deletedAt != null,
                shareable: true,
              );
      case SyncRecordKind.customFieldDef:
        final row = await (_db.select(
          _db.customFieldDefs,
        )..where((table) => table.id.equals(id))).getSingleOrNull();
        return row == null
            ? null
            : (
                id: row.id,
                type: row.type.name,
                deleted: row.deletedAt != null,
                shareable: row.shareable,
              );
      case SyncRecordKind.difficultyLevel:
        final row = await (_db.select(
          _db.difficultyLevels,
        )..where((table) => table.id.equals(id))).getSingleOrNull();
        return row == null
            ? null
            : (
                id: row.id,
                type: null,
                deleted: row.deletedAt != null,
                shareable: true,
              );
      case SyncRecordKind.dance:
      case SyncRecordKind.program:
      case SyncRecordKind.publishedSource:
      case SyncRecordKind.venue:
      case SyncRecordKind.setting:
        return null;
    }
  }

  Future<_NaturalKeyValue?> _naturalKeyRow(
    SyncRecordKind kind,
    String key,
  ) async {
    final indexed = _naturalKeyIndex?.lookup(kind, key);
    if (_naturalKeyIndex != null) return indexed;
    switch (kind) {
      case SyncRecordKind.choreographer:
        final rows = await _db.select(_db.choreographers).get();
        for (final row in rows) {
          if (normalizeShareableText(row.name).toLowerCase() == key) {
            return (
              id: row.id,
              type: null,
              deleted: row.deletedAt != null,
              shareable: true,
            );
          }
        }
      case SyncRecordKind.tag:
        final rows = await _db.select(_db.tags).get();
        for (final row in rows) {
          if (normalizeShareableText(row.name).toLowerCase() == key) {
            return (
              id: row.id,
              type: null,
              deleted: row.deletedAt != null,
              shareable: true,
            );
          }
        }
      case SyncRecordKind.customFieldDef:
        final rows = await _db.select(_db.customFieldDefs).get();
        for (final row in rows) {
          if (normalizeShareableText(row.key).toLowerCase() == key) {
            return (
              id: row.id,
              type: row.type.name,
              deleted: row.deletedAt != null,
              shareable: row.shareable,
            );
          }
        }
      case SyncRecordKind.difficultyLevel:
        final rows = await _db.select(_db.difficultyLevels).get();
        for (final row in rows) {
          if (normalizeShareableText(row.label).toLowerCase() == key) {
            return (
              id: row.id,
              type: null,
              deleted: row.deletedAt != null,
              shareable: true,
            );
          }
        }
      case SyncRecordKind.dance:
      case SyncRecordKind.program:
      case SyncRecordKind.publishedSource:
      case SyncRecordKind.venue:
      case SyncRecordKind.setting:
        break;
    }
    return null;
  }

  String? _customFieldType(Map<String, Object?> body) =>
      body['type'] is String ? body['type']! as String : null;

  Future<SyncMergeCandidate?> _localNaturalCandidate({
    required SyncRecordKind kind,
    required String id,
  }) async {
    final body = await read((kind: kind, recordId: id));
    if (body == null) return null;
    final metadata = await _naturalRecordMetadata(kind, id);
    if (metadata == null) return null;
    final entity = _decodeEntity(kind, body);
    return SyncMergeCandidate(
      blob: SyncRecordBlob(
        kind: kind,
        id: id,
        updatedAt: metadata.updatedAt,
        deletedAt: metadata.deletedAt,
        existenceAt: metadata.existenceAt,
        body: syncBodyForEntity(kind, entity),
      ),
    );
  }

  Future<({DateTime updatedAt, DateTime existenceAt, DateTime? deletedAt})?>
  _naturalRecordMetadata(SyncRecordKind kind, String id) async {
    switch (kind) {
      case SyncRecordKind.choreographer:
        final row = await (_db.select(
          _db.choreographers,
        )..where((table) => table.id.equals(id))).getSingleOrNull();
        if (row == null) return null;
        return (
          updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
          existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
          deletedAt: row.deletedAt,
        );
      case SyncRecordKind.tag:
        final row = await (_db.select(
          _db.tags,
        )..where((table) => table.id.equals(id))).getSingleOrNull();
        if (row == null) return null;
        return (
          updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
          existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
          deletedAt: row.deletedAt,
        );
      case SyncRecordKind.customFieldDef:
        final row = await (_db.select(
          _db.customFieldDefs,
        )..where((table) => table.id.equals(id))).getSingleOrNull();
        if (row == null) return null;
        return (
          updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
          existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
          deletedAt: row.deletedAt,
        );
      case SyncRecordKind.difficultyLevel:
        final row = await (_db.select(
          _db.difficultyLevels,
        )..where((table) => table.id.equals(id))).getSingleOrNull();
        if (row == null) return null;
        return (
          updatedAt: row.updatedAt ?? row.existenceAt ?? _epoch,
          existenceAt: row.existenceAt ?? row.updatedAt ?? _epoch,
          deletedAt: row.deletedAt,
        );
      case SyncRecordKind.dance:
      case SyncRecordKind.program:
      case SyncRecordKind.publishedSource:
      case SyncRecordKind.venue:
      case SyncRecordKind.setting:
        return null;
    }
  }

  Future<SyncMergeCandidate?> _reconcileNaturalKeyCollision({
    required SyncMergeCandidate candidate,
    required SyncMergeCandidate local,
    required String survivorId,
  }) async {
    final incomingExistenceWins =
        candidate.blob.existenceAt.isAfter(local.blob.existenceAt) ||
        (candidate.blob.existenceAt == local.blob.existenceAt &&
            candidate.blob.deletedAt != null &&
            local.blob.deletedAt == null);
    final localExistenceWins =
        local.blob.existenceAt.isAfter(candidate.blob.existenceAt) ||
        (candidate.blob.existenceAt == local.blob.existenceAt &&
            local.blob.deletedAt != null &&
            candidate.blob.deletedAt == null);
    final existenceSource = incomingExistenceWins
        ? candidate
        : localExistenceWins
        ? local
        : candidate;
    final winningDeleted = existenceSource.blob.deletedAt != null;
    final contentCandidates = [
      if ((candidate.blob.deletedAt != null) == winningDeleted) candidate,
      if ((local.blob.deletedAt != null) == winningDeleted) local,
    ];
    final contentSource = _newerNaturalContent(
      candidate: contentCandidates.first,
      other: contentCandidates.length == 1 ? null : contentCandidates.last,
    );
    if (contentSource == null) {
      await _enqueueCollisionReview(
        candidate,
        local.blob.id,
        reason:
            'natural-key collision has different bodies at the same '
            'updatedAt',
      );
      return null;
    }
    final body = Map<String, Object?>.from(contentSource.blob.body)
      ..['id'] = survivorId;
    return SyncMergeCandidate(
      blob: SyncRecordBlob(
        v: contentSource.blob.v,
        kind: candidate.blob.kind,
        id: survivorId,
        updatedAt: contentSource.blob.updatedAt,
        deletedAt: existenceSource.blob.deletedAt,
        existenceAt: candidate.blob.existenceAt.isAfter(local.blob.existenceAt)
            ? candidate.blob.existenceAt
            : local.blob.existenceAt,
        body: body,
      ),
    );
  }

  SyncMergeCandidate? _newerNaturalContent({
    required SyncMergeCandidate candidate,
    required SyncMergeCandidate? other,
  }) {
    if (other == null) return candidate;
    final comparison = candidate.blob.updatedAt.compareTo(other.blob.updatedAt);
    if (comparison > 0) return candidate;
    if (comparison < 0) return other;
    final candidateBody = Map<String, Object?>.from(candidate.blob.body)
      ..remove('id');
    final otherBody = Map<String, Object?>.from(other.blob.body)..remove('id');
    return contentHash(candidateBody) == contentHash(otherBody)
        ? candidate
        : null;
  }

  String? _canonicalDifficultyId(
    String key, {
    required String candidateId,
    String? incumbentId,
  }) {
    final incumbent = DifficultyLevel.knownForId(incumbentId);
    if (incumbent != null) return incumbent.id;
    final candidate = DifficultyLevel.knownForId(candidateId);
    if (candidate != null) return candidate.id;
    for (final level in DifficultyLevel.shipped) {
      if (normalizeShareableText(level.label).toLowerCase() == key) {
        return level.id;
      }
    }
    return null;
  }

  Future<SyncMergeCandidate?> _reconcileCustomFieldTypeMismatch(
    SyncMergeCandidate candidate,
    _NaturalKeyValue incumbent,
  ) async {
    final incomingWins = candidate.blob.id.compareTo(incumbent.id) < 0;
    final losingId = incomingWins ? incumbent.id : candidate.blob.id;
    final key = candidate.blob.body['key'];
    if (key is! String) return null;
    final shortKey = syncCustomFieldSuffix(key, losingId, full: false);
    final fullKey = syncCustomFieldSuffix(key, losingId, full: true);
    final suffix =
        await _naturalKeyRow(
              SyncRecordKind.customFieldDef,
              shortKey.toLowerCase(),
            ) ==
            null
        ? shortKey
        : await _naturalKeyRow(
                SyncRecordKind.customFieldDef,
                fullKey.toLowerCase(),
              ) ==
              null
        ? fullKey
        : null;
    if (suffix == null) {
      await _enqueueCollisionReview(
        candidate,
        incumbent.id,
        reason: 'custom-field type mismatch has no deterministic free key',
      );
      return null;
    }
    if (incomingWins) {
      await _renameLocalCustomField(incumbent.id, suffix);
      return candidate;
    }
    final body = rewriteSyncInboundReferences(
      candidate.blob.body,
      const <SyncRecordKind, Map<String, String>>{},
    )..['key'] = suffix;
    final stamp = nextExistenceStamp(
      now: DateTime.now().toUtc(),
      current: candidate.blob.updatedAt,
    );
    return _candidateWithBody(
      candidate,
      candidate.blob.id,
      body,
      updatedAt: stamp,
    );
  }

  Future<SyncMergeCandidate?> _renameInboundCustomField(
    SyncMergeCandidate candidate,
    String counterpartId, {
    required String reason,
  }) async {
    final key = candidate.blob.body['key'];
    if (key is! String) return null;
    final shortKey = syncCustomFieldSuffix(key, candidate.blob.id, full: false);
    final fullKey = syncCustomFieldSuffix(key, candidate.blob.id, full: true);
    final suffix =
        await _naturalKeyRow(
              SyncRecordKind.customFieldDef,
              shortKey.toLowerCase(),
            ) ==
            null
        ? shortKey
        : await _naturalKeyRow(
                SyncRecordKind.customFieldDef,
                fullKey.toLowerCase(),
              ) ==
              null
        ? fullKey
        : null;
    if (suffix == null) {
      await _enqueueCollisionReview(candidate, counterpartId, reason: reason);
      return null;
    }
    final body = Map<String, Object?>.from(candidate.blob.body)
      ..['key'] = suffix;
    return _candidateWithBody(
      candidate,
      candidate.blob.id,
      body,
      updatedAt: nextExistenceStamp(
        now: DateTime.now().toUtc(),
        current: candidate.blob.updatedAt,
      ),
    );
  }

  Future<void> _enqueueCollisionReview(
    SyncMergeCandidate candidate,
    String counterpartId, {
    String? recordId,
    required String reason,
  }) => repositories.syncLocal.enqueueReview(
    kind: candidate.blob.kind,
    recordId: recordId ?? candidate.blob.id,
    counterpartId: counterpartId,
    reason: reason,
    candidateBlob: encodeSyncRecordBlob(candidate.blob),
    candidateHash: candidate.wireHash,
    queuedAt: DateTime.now().toUtc(),
  );

  Future<bool> _guardReconciliationTarget({
    required SyncRecordKind kind,
    required String recordId,
    required Map<SyncRecordAddress, String?>? expectedWireHashes,
    required List<SyncReport> reports,
  }) async {
    final address = (kind: kind, recordId: recordId);
    if (expectedWireHashes == null ||
        !expectedWireHashes.containsKey(address)) {
      return true;
    }
    final expected = expectedWireHashes[address];
    final current = await _localNaturalCandidate(kind: kind, id: recordId);
    if (current?.wireHash == expected) return true;
    reports.add(
      SyncReport(
        code: SyncReportCode.concurrentLocalChange,
        kind: kind,
        recordId: recordId,
        message:
            'Local reconciliation target changed while sync was preparing '
            'its inbound update.',
      ),
    );
    return false;
  }

  Future<void> _renameLocalCustomField(String id, String newKey) async {
    final row = await (_db.select(
      _db.customFieldDefs,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    final stamp = nextExistenceStamp(
      now: DateTime.now().toUtc(),
      current: row.updatedAt,
    );
    await (_db.update(
      _db.customFieldDefs,
    )..where((table) => table.id.equals(id))).write(
      CustomFieldDefsCompanion(key: Value(newKey), updatedAt: Value(stamp)),
    );
    _naturalKeyIndex?.replace(
      kind: SyncRecordKind.customFieldDef,
      id: id,
      key: normalizeShareableText(newKey).toLowerCase(),
      type: row.type.name,
      deleted: row.deletedAt != null,
      shareable: row.shareable,
    );
  }

  Future<String> _temporaryNaturalKey(
    SyncRecordKind kind,
    String losingId,
    String survivingId,
  ) async {
    final base = '__sync_${losingId}_$survivingId';
    var candidate = base;
    var suffix = 2;
    while (await _naturalKeyRow(
          kind,
          normalizeShareableText(candidate).toLowerCase(),
        ) !=
        null) {
      candidate = '${base}_$suffix';
      suffix++;
    }
    return candidate;
  }

  /// Moves a local losing row onto the deterministic survivor identity before
  /// the inbound candidate is written. The temporary natural key keeps the
  /// unique index valid while the new parent row is inserted.
  Future<void> _migrateLocalIdentity(
    SyncRecordKind kind,
    String losingId,
    String survivingId,
  ) async {
    if (losingId == survivingId) return;
    final temporaryNaturalKey = await _temporaryNaturalKey(
      kind,
      losingId,
      survivingId,
    );
    switch (kind) {
      case SyncRecordKind.choreographer:
        final row = await (_db.select(
          _db.choreographers,
        )..where((table) => table.id.equals(losingId))).getSingleOrNull();
        if (row == null) return;
        await (_db.update(
          _db.choreographers,
        )..where((table) => table.id.equals(losingId))).write(
          ChoreographersCompanion(
            name: Value(temporaryNaturalKey),
            updatedAt: Value(row.updatedAt),
          ),
        );
        await _db
            .into(_db.choreographers)
            .insert(
              ChoreographersCompanion.insert(
                id: survivingId,
                name: row.name,
                website: Value(row.website),
                notes: Value(row.notes),
                email: Value(row.email),
                location: Value(row.location),
                deceased: Value(row.deceased),
                updatedAt: Value(row.updatedAt),
                deletedAt: Value(row.deletedAt),
                existenceAt: Value(row.existenceAt),
              ),
            );
        _naturalKeyIndex?.replace(
          kind: kind,
          id: survivingId,
          key: normalizeShareableText(row.name).toLowerCase(),
          type: null,
          deleted: row.deletedAt != null,
          shareable: true,
        );
      case SyncRecordKind.tag:
        final row = await (_db.select(
          _db.tags,
        )..where((table) => table.id.equals(losingId))).getSingleOrNull();
        if (row == null) return;
        await (_db.update(
          _db.tags,
        )..where((table) => table.id.equals(losingId))).write(
          TagsCompanion(
            name: Value(temporaryNaturalKey),
            updatedAt: Value(row.updatedAt),
          ),
        );
        await _db
            .into(_db.tags)
            .insert(
              TagsCompanion.insert(
                id: survivingId,
                name: row.name,
                color: Value(row.color),
                updatedAt: Value(row.updatedAt),
                deletedAt: Value(row.deletedAt),
                existenceAt: Value(row.existenceAt),
              ),
            );
        _naturalKeyIndex?.replace(
          kind: kind,
          id: survivingId,
          key: normalizeShareableText(row.name).toLowerCase(),
          type: null,
          deleted: row.deletedAt != null,
          shareable: true,
        );
      case SyncRecordKind.customFieldDef:
        final row = await (_db.select(
          _db.customFieldDefs,
        )..where((table) => table.id.equals(losingId))).getSingleOrNull();
        if (row == null) return;
        await (_db.update(
          _db.customFieldDefs,
        )..where((table) => table.id.equals(losingId))).write(
          CustomFieldDefsCompanion(
            key: Value(temporaryNaturalKey),
            updatedAt: Value(row.updatedAt),
          ),
        );
        await _db
            .into(_db.customFieldDefs)
            .insert(
              CustomFieldDefsCompanion.insert(
                id: survivingId,
                key: row.key,
                label: row.label,
                type: row.type,
                choicesJson: Value(row.choicesJson),
                showInList: Value(row.showInList),
                searchable: Value(row.searchable),
                shareable: Value(row.shareable),
                updatedAt: Value(row.updatedAt),
                deletedAt: Value(row.deletedAt),
                existenceAt: Value(row.existenceAt),
              ),
            );
        _naturalKeyIndex?.replace(
          kind: kind,
          id: survivingId,
          key: normalizeShareableText(row.key).toLowerCase(),
          type: row.type.name,
          deleted: row.deletedAt != null,
          shareable: row.shareable,
        );
      case SyncRecordKind.difficultyLevel:
        final row = await (_db.select(
          _db.difficultyLevels,
        )..where((table) => table.id.equals(losingId))).getSingleOrNull();
        if (row == null) return;
        await (_db.update(
          _db.difficultyLevels,
        )..where((table) => table.id.equals(losingId))).write(
          DifficultyLevelsCompanion(
            label: Value(temporaryNaturalKey),
            updatedAt: Value(row.updatedAt),
          ),
        );
        await _db
            .into(_db.difficultyLevels)
            .insert(
              DifficultyLevelsCompanion.insert(
                id: survivingId,
                label: row.label,
                position: row.position,
                updatedAt: Value(row.updatedAt),
                deletedAt: Value(row.deletedAt),
                existenceAt: Value(row.existenceAt),
              ),
            );
        _naturalKeyIndex?.replace(
          kind: kind,
          id: survivingId,
          key: normalizeShareableText(row.label).toLowerCase(),
          type: null,
          deleted: row.deletedAt != null,
          shareable: true,
        );
      case SyncRecordKind.dance:
      case SyncRecordKind.program:
      case SyncRecordKind.publishedSource:
      case SyncRecordKind.venue:
      case SyncRecordKind.setting:
        return;
    }
    await _rewriteLocalReferences(kind, losingId, survivingId);
    await _deleteIdentityRow(kind, losingId);
    _naturalKeyIndex?.removeId(kind, losingId);
  }

  Future<void> _deleteIdentityRow(SyncRecordKind kind, String id) async {
    switch (kind) {
      case SyncRecordKind.choreographer:
        await (_db.delete(
          _db.choreographers,
        )..where((table) => table.id.equals(id))).go();
      case SyncRecordKind.tag:
        await (_db.delete(
          _db.tags,
        )..where((table) => table.id.equals(id))).go();
      case SyncRecordKind.customFieldDef:
        await (_db.delete(
          _db.customFieldDefs,
        )..where((table) => table.id.equals(id))).go();
      case SyncRecordKind.difficultyLevel:
        await (_db.delete(
          _db.difficultyLevels,
        )..where((table) => table.id.equals(id))).go();
      case SyncRecordKind.dance:
      case SyncRecordKind.program:
      case SyncRecordKind.publishedSource:
      case SyncRecordKind.venue:
      case SyncRecordKind.setting:
        return;
    }
  }

  Future<void> _rewriteLocalReferences(
    SyncRecordKind kind,
    String losingId,
    String survivingId,
  ) async {
    if (losingId == survivingId) return;
    final affectedDances = <String>{};
    switch (kind) {
      case SyncRecordKind.choreographer:
        final rows = await (_db.select(
          _db.danceAuthors,
        )..where((row) => row.choreographerId.equals(losingId))).get();
        affectedDances.addAll(rows.map((row) => row.danceId));
        for (final row in rows) {
          final existing =
              await (_db.select(_db.danceAuthors)..where(
                    (table) =>
                        table.danceId.equals(row.danceId) &
                        table.choreographerId.equals(survivingId),
                  ))
                  .getSingleOrNull();
          if (existing != null) {
            await (_db.delete(_db.danceAuthors)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.choreographerId.equals(losingId),
                ))
                .go();
          } else {
            await (_db.update(_db.danceAuthors)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.choreographerId.equals(losingId),
                ))
                .write(
                  DanceAuthorsCompanion(choreographerId: Value(survivingId)),
                );
          }
        }
      case SyncRecordKind.tag:
        final rows = await (_db.select(
          _db.danceTags,
        )..where((row) => row.tagId.equals(losingId))).get();
        affectedDances.addAll(rows.map((row) => row.danceId));
        for (final row in rows) {
          final existing =
              await (_db.select(_db.danceTags)..where(
                    (table) =>
                        table.danceId.equals(row.danceId) &
                        table.tagId.equals(survivingId),
                  ))
                  .getSingleOrNull();
          if (existing != null) {
            await (_db.delete(_db.danceTags)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.tagId.equals(losingId),
                ))
                .go();
          } else {
            await (_db.update(_db.danceTags)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.tagId.equals(losingId),
                ))
                .write(DanceTagsCompanion(tagId: Value(survivingId)));
          }
        }
      case SyncRecordKind.publishedSource:
        final rows = await (_db.select(
          _db.danceSources,
        )..where((row) => row.sourceId.equals(losingId))).get();
        affectedDances.addAll(rows.map((row) => row.danceId));
        for (final row in rows) {
          final existing =
              await (_db.select(_db.danceSources)..where(
                    (table) =>
                        table.danceId.equals(row.danceId) &
                        table.sourceId.equals(survivingId),
                  ))
                  .getSingleOrNull();
          if (existing != null) {
            await (_db.delete(_db.danceSources)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.sourceId.equals(losingId),
                ))
                .go();
          } else {
            await (_db.update(_db.danceSources)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.sourceId.equals(losingId),
                ))
                .write(DanceSourcesCompanion(sourceId: Value(survivingId)));
          }
        }
      case SyncRecordKind.customFieldDef:
        final rows = await (_db.select(
          _db.customFieldValues,
        )..where((row) => row.fieldId.equals(losingId))).get();
        affectedDances.addAll(rows.map((row) => row.danceId));
        for (final row in rows) {
          final existing =
              await (_db.select(_db.customFieldValues)..where(
                    (table) =>
                        table.danceId.equals(row.danceId) &
                        table.fieldId.equals(survivingId),
                  ))
                  .getSingleOrNull();
          if (existing != null) {
            await (_db.delete(_db.customFieldValues)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.fieldId.equals(losingId),
                ))
                .go();
          } else {
            await (_db.update(_db.customFieldValues)..where(
                  (table) =>
                      table.danceId.equals(row.danceId) &
                      table.fieldId.equals(losingId),
                ))
                .write(CustomFieldValuesCompanion(fieldId: Value(survivingId)));
          }
        }
      case SyncRecordKind.difficultyLevel:
        final rows = await (_db.select(
          _db.dances,
        )..where((row) => row.levelId.equals(losingId))).get();
        affectedDances.addAll(rows.map((row) => row.id));
        for (final row in rows) {
          await (_db.update(
            _db.dances,
          )..where((table) => table.id.equals(row.id))).write(
            DancesCompanion(
              levelId: Value(survivingId),
              updatedAt: Value(row.updatedAt),
            ),
          );
        }
      case SyncRecordKind.dance:
      case SyncRecordKind.program:
      case SyncRecordKind.venue:
      case SyncRecordKind.setting:
        return;
    }
    if (affectedDances.isEmpty) return;
    final now = DateTime.now().toUtc();
    for (final danceId in affectedDances) {
      final row = await (_db.select(
        _db.dances,
      )..where((table) => table.id.equals(danceId))).getSingleOrNull();
      if (row == null) continue;
      await (_db.update(
        _db.dances,
      )..where((table) => table.id.equals(danceId))).write(
        DancesCompanion(
          updatedAt: Value(
            nextExistenceStamp(now: now, current: row.updatedAt),
          ),
        ),
      );
    }
  }

  @override
  Future<void> write(SyncApplyRecord record) async {
    await writeWithReport(record);
  }

  @override
  Future<SyncReport?> validateInboundReferences(
    SyncApplyRecord record, {
    Set<SyncRecordAddress> inboundLiveAddresses = const {},
    Set<SyncRecordAddress> inboundAddresses = const {},
    Map<SyncRecordAddress, SyncApplyRecord> inboundRecords = const {},
  }) async {
    if (record.address.kind == SyncRecordKind.setting) return null;
    final Object entity;
    try {
      entity = _decodeEntity(record.address.kind, record.body);
    } on FormatException catch (error) {
      return _malformedReferenceReport(record, error.message);
    } on ArgumentError catch (error) {
      return _malformedReferenceReport(record, '$error');
    } on Object catch (error) {
      return _malformedReferenceReport(record, '$error');
    }
    final classificationIssue = await _invalidCustomFieldClassification(
      record,
      entity,
      inboundAddresses: inboundAddresses,
      inboundRecords: inboundRecords,
    );
    if (classificationIssue != null) {
      return SyncReport(
        code: SyncReportCode.invalidClassification,
        kind: record.address.kind,
        recordId: record.address.recordId,
        message: classificationIssue,
      );
    }
    // A tombstone may retain joins to other tombstones in the same batch. The
    // live-record guard still applies, but deletion records resolve references
    // against any existing row so their existence transition can converge.
    final allowTombstonedReferences = record.deletedAt != null;
    final referenceInboundLiveAddresses = allowTombstonedReferences
        ? inboundAddresses
        : inboundLiveAddresses;
    final dependentIndex = _dependentIndexFor(inboundRecords);

    final dependentRowIssue = switch (record.address.kind) {
      SyncRecordKind.dance => await _invalidDanceDependentRows(
        entity as Dance,
        dependentIndex: dependentIndex,
      ),
      SyncRecordKind.program => await _invalidProgramDependentRows(
        entity as Program,
        dependentIndex: dependentIndex,
      ),
      _ => null,
    };
    if (dependentRowIssue != null) {
      return SyncReport(
        code: SyncReportCode.malformedRecord,
        kind: record.address.kind,
        recordId: record.address.recordId,
        message: dependentRowIssue,
      );
    }

    final missing = switch (record.address.kind) {
      SyncRecordKind.dance => await _missingDanceReference(
        entity as Dance,
        inboundLiveAddresses: referenceInboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        inboundRecords: inboundRecords,
        allowTombstonedReferences: allowTombstonedReferences,
      ),
      SyncRecordKind.program => await _missingProgramReference(
        entity as Program,
        inboundLiveAddresses: referenceInboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        allowTombstonedReferences: allowTombstonedReferences,
      ),
      _ => null,
    };
    return missing == null
        ? null
        : SyncReport(
            code: SyncReportCode.unresolvedReference,
            kind: record.address.kind,
            recordId: record.address.recordId,
            message: missing,
          );
  }

  @override
  Future<SyncReport?> writeWithReport(SyncApplyRecord record) async {
    final kind = record.address.kind;
    if (record.deletedAt != null &&
        await _hasCitation(
          kind,
          record.address.recordId,
          ignoreInboundTombstones: true,
        )) {
      await _storePendingDeletion(record);
      return null;
    }
    if (kind == SyncRecordKind.setting) {
      final value = record.body['value'];
      await _db
          .into(_db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: record.address.recordId,
              valueJson: jsonEncode(normalizeShareableJson(value)),
              updatedAt: Value(record.updatedAt),
              deletedAt: Value(record.deletedAt),
              existenceAt: Value(record.existenceAt),
            ),
          );
      return null;
    }

    final Object entity;
    try {
      entity = _decodeEntity(kind, record.body);
    } on Object catch (error) {
      return _malformedReferenceReport(record, '$error');
    }
    SyncReport? report;
    Object entityToWrite = entity;
    if (kind == SyncRecordKind.program) {
      final program = entity as Program;
      if (program.venueId != null && !(await _isLiveVenue(program.venueId!))) {
        entityToWrite = program.copyWith(clearVenueId: true);
        report = SyncReport(
          code: SyncReportCode.unresolvedReference,
          kind: kind,
          recordId: record.address.recordId,
          message:
              'Program venue reference was cleared because the venue is missing.',
        );
      }
    }

    switch (kind) {
      case SyncRecordKind.dance:
        await repositories.dances.writeFromSync(entityToWrite as Dance);
      case SyncRecordKind.program:
        await repositories.programs.writeFromSync(entityToWrite as Program);
      case SyncRecordKind.choreographer:
        final _ = await repositories.choreographers.upsert(
          entityToWrite as Choreographer,
          at: record.updatedAt,
        );
      case SyncRecordKind.tag:
        final _ = await repositories.tags.upsert(
          entityToWrite as Tag,
          at: record.updatedAt,
        );
      case SyncRecordKind.publishedSource:
        await repositories.publishedSources.upsert(
          entityToWrite as PublishedSource,
          at: record.updatedAt,
        );
      case SyncRecordKind.customFieldDef:
        final _ = await repositories.customFieldDefs.upsert(
          entityToWrite as CustomFieldDef,
          at: record.updatedAt,
        );
      case SyncRecordKind.difficultyLevel:
        final _ = await repositories.difficultyLevels.upsert(
          entityToWrite as DifficultyLevel,
          at: record.updatedAt,
        );
      case SyncRecordKind.venue:
        await repositories.venues.upsert(
          entityToWrite as Venue,
          at: record.updatedAt,
        );
      case SyncRecordKind.setting:
        throw StateError('settings are handled above');
    }
    await _restoreTimestamps(
      kind: kind,
      id: record.address.recordId,
      updatedAt: record.updatedAt,
      deletedAt: record.deletedAt,
      existenceAt: record.existenceAt,
    );
    return report;
  }

  @override
  Future<SyncReport?> writeParentWithReport(SyncApplyRecord record) async {
    if (record.deletedAt != null &&
        await _hasCitation(
          record.address.kind,
          record.address.recordId,
          ignoreInboundTombstones: true,
        )) {
      await _storePendingDeletion(record);
      _pendingParentWrites.add(record.address);
      return null;
    }
    _pendingParentWrites.remove(record.address);
    final kind = record.address.kind;
    if (kind != SyncRecordKind.dance && kind != SyncRecordKind.program) {
      return writeWithReport(record);
    }

    final prepared = await _prepareEntity(record);
    _deferredEntities[record.address] = prepared.entity;
    switch (kind) {
      case SyncRecordKind.dance:
        await repositories.dances.writeFromSyncParent(prepared.entity as Dance);
      case SyncRecordKind.program:
        await repositories.programs.writeFromSyncParent(
          prepared.entity as Program,
        );
      case SyncRecordKind.setting:
      case SyncRecordKind.choreographer:
      case SyncRecordKind.tag:
      case SyncRecordKind.publishedSource:
      case SyncRecordKind.customFieldDef:
      case SyncRecordKind.difficultyLevel:
      case SyncRecordKind.venue:
        throw StateError('unexpected non-parent sync kind: $kind');
    }
    return prepared.report;
  }

  @override
  Future<SyncReport?> writeJoinsWithReport(SyncApplyRecord record) async {
    if (_pendingParentWrites.remove(record.address)) return null;
    if (record.address.kind != SyncRecordKind.dance &&
        record.address.kind != SyncRecordKind.program) {
      return null;
    }

    final entity = _deferredEntities.remove(record.address);
    if (entity == null) {
      throw StateError(
        'missing deferred sync parent for ${record.address.kind.name}:'
        '${record.address.recordId}',
      );
    }
    switch (record.address.kind) {
      case SyncRecordKind.dance:
        await repositories.dances.writeFromSyncRelations(entity as Dance);
      case SyncRecordKind.program:
        await repositories.programs.writeFromSyncRelations(entity as Program);
      case SyncRecordKind.setting:
      case SyncRecordKind.choreographer:
      case SyncRecordKind.tag:
      case SyncRecordKind.publishedSource:
      case SyncRecordKind.customFieldDef:
      case SyncRecordKind.difficultyLevel:
      case SyncRecordKind.venue:
        return null;
    }
    await _restoreTimestamps(
      kind: record.address.kind,
      id: record.address.recordId,
      updatedAt: record.updatedAt,
      deletedAt: record.deletedAt,
      existenceAt: record.existenceAt,
    );
    return null;
  }

  Future<void> _storePendingDeletion(SyncApplyRecord record) async {
    final blob =
        record.sourceBlob ??
        SyncRecordBlob(
          kind: record.address.kind,
          id: record.address.recordId,
          updatedAt: record.updatedAt,
          deletedAt: record.deletedAt,
          existenceAt: record.existenceAt,
          body: record.body,
        );
    final encoded = encodeSyncRecordBlob(blob);
    await repositories.syncLocal.upsertPendingDeletion(
      kind: record.address.kind,
      recordId: record.address.recordId,
      tombstonedAt: record.deletedAt!,
      tombstoneHash: sha256Hex(utf8.encode(encoded)),
      tombstoneBlob: encoded,
    );
  }

  Future<({Object entity, SyncReport? report})> _prepareEntity(
    SyncApplyRecord record,
  ) async {
    final kind = record.address.kind;
    final entity = _decodeEntity(kind, record.body);
    if (kind != SyncRecordKind.program) {
      return (entity: entity, report: null);
    }
    final program = entity as Program;
    if (program.venueId == null || await _isLiveVenue(program.venueId!)) {
      return (entity: program, report: null);
    }
    return (
      entity: program.copyWith(clearVenueId: true),
      report: SyncReport(
        code: SyncReportCode.unresolvedReference,
        kind: kind,
        recordId: record.address.recordId,
        message:
            'Program venue reference was cleared because the venue is missing.',
      ),
    );
  }

  @override
  Future<void> rebuildDerivedIndexes() async {
    await repositories.dances.rebuildAllDerived();
  }

  Future<String?> _missingDanceReference(
    Dance dance, {
    required Set<SyncRecordAddress> inboundLiveAddresses,
    required Set<SyncRecordAddress> inboundAddresses,
    required Map<SyncRecordAddress, SyncApplyRecord> inboundRecords,
    required bool allowTombstonedReferences,
  }) async {
    final difficultyId = dance.difficultyLevelId;
    if (difficultyId != null) {
      final difficultyAddress = (
        kind: SyncRecordKind.difficultyLevel,
        recordId: difficultyId,
      );
      final difficulty = inboundLiveAddresses.contains(difficultyAddress)
          ? difficultyId
          : inboundAddresses.contains(difficultyAddress)
          ? null
          : (await (_db.select(_db.difficultyLevels)..where(
                      (row) =>
                          row.id.equals(difficultyId) &
                          (allowTombstonedReferences
                              ? const Constant(true)
                              : row.deletedAt.isNull()),
                    ))
                    .getSingleOrNull())
                ?.id;
      if (difficulty == null) {
        return 'Dance "${dance.id}" references unavailable difficulty '
            '"$difficultyId".';
      }
    }

    final authorIds = dance.authorIds.toSet();
    final authorLookupIds = _referenceIdsToLookUp(
      ids: authorIds,
      kind: SyncRecordKind.choreographer,
      inboundLiveAddresses: inboundLiveAddresses,
      inboundAddresses: inboundAddresses,
    );
    if (authorLookupIds.isNotEmpty) {
      final rows =
          await (_db.select(_db.choreographers)..where(
                (row) =>
                    row.id.isIn(authorLookupIds) &
                    (allowTombstonedReferences
                        ? const Constant(true)
                        : row.deletedAt.isNull()),
              ))
              .get();
      final missing = _missingReferenceIds(
        ids: authorIds,
        kind: SyncRecordKind.choreographer,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: rows.map((row) => row.id).toSet(),
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable choreographer '
            '"${missing.first}".';
      }
    } else if (authorIds.isNotEmpty) {
      final missing = _missingReferenceIds(
        ids: authorIds,
        kind: SyncRecordKind.choreographer,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: const {},
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable choreographer '
            '"${missing.first}".';
      }
    }

    final tagIds = dance.tagIds.toSet();
    final tagLookupIds = _referenceIdsToLookUp(
      ids: tagIds,
      kind: SyncRecordKind.tag,
      inboundLiveAddresses: inboundLiveAddresses,
      inboundAddresses: inboundAddresses,
    );
    if (tagLookupIds.isNotEmpty) {
      final rows =
          await (_db.select(_db.tags)..where(
                (row) =>
                    row.id.isIn(tagLookupIds) &
                    (allowTombstonedReferences
                        ? const Constant(true)
                        : row.deletedAt.isNull()),
              ))
              .get();
      final missing = _missingReferenceIds(
        ids: tagIds,
        kind: SyncRecordKind.tag,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: rows.map((row) => row.id).toSet(),
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable tag '
            '"${missing.first}".';
      }
    } else if (tagIds.isNotEmpty) {
      final missing = _missingReferenceIds(
        ids: tagIds,
        kind: SyncRecordKind.tag,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: const {},
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable tag '
            '"${missing.first}".';
      }
    }

    final sourceIds = dance.sourceCitations
        .map((citation) => citation.sourceId)
        .toSet();
    final sourceLookupIds = _referenceIdsToLookUp(
      ids: sourceIds,
      kind: SyncRecordKind.publishedSource,
      inboundLiveAddresses: inboundLiveAddresses,
      inboundAddresses: inboundAddresses,
    );
    if (sourceLookupIds.isNotEmpty) {
      final rows =
          await (_db.select(_db.publishedSources)..where(
                (row) =>
                    row.id.isIn(sourceLookupIds) &
                    (allowTombstonedReferences
                        ? const Constant(true)
                        : row.deletedAt.isNull()),
              ))
              .get();
      final missing = _missingReferenceIds(
        ids: sourceIds,
        kind: SyncRecordKind.publishedSource,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: rows.map((row) => row.id).toSet(),
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable source '
            '"${missing.first}".';
      }
    } else if (sourceIds.isNotEmpty) {
      final missing = _missingReferenceIds(
        ids: sourceIds,
        kind: SyncRecordKind.publishedSource,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: const {},
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable source '
            '"${missing.first}".';
      }
    }

    final customFieldIds = dance.customFields
        .map((value) => value.fieldId)
        .toSet();
    final customFieldLookupIds = _referenceIdsToLookUp(
      ids: customFieldIds,
      kind: SyncRecordKind.customFieldDef,
      inboundLiveAddresses: inboundLiveAddresses,
      inboundAddresses: inboundAddresses,
    );
    if (customFieldLookupIds.isNotEmpty) {
      final rows =
          await (_db.select(_db.customFieldDefs)..where(
                (row) =>
                    row.id.isIn(customFieldLookupIds) &
                    (allowTombstonedReferences
                        ? const Constant(true)
                        : row.deletedAt.isNull()),
              ))
              .get();
      final missing = _missingReferenceIds(
        ids: customFieldIds,
        kind: SyncRecordKind.customFieldDef,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: rows.map((row) => row.id).toSet(),
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable custom field '
            '"${missing.first}".';
      }
    } else if (customFieldIds.isNotEmpty) {
      final missing = _missingReferenceIds(
        ids: customFieldIds,
        kind: SyncRecordKind.customFieldDef,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: const {},
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable custom field '
            '"${missing.first}".';
      }
    }
    final customFieldIssue = await _invalidCustomFieldValue(
      dance,
      inboundLiveAddresses: inboundLiveAddresses,
      inboundAddresses: inboundAddresses,
      inboundRecords: inboundRecords,
    );
    if (customFieldIssue != null) return customFieldIssue;

    final targetDanceIds = dance.links
        .map((link) => link.targetDanceId)
        .whereType<String>()
        .toSet();
    final targetDanceLookupIds = _referenceIdsToLookUp(
      ids: targetDanceIds,
      kind: SyncRecordKind.dance,
      inboundLiveAddresses: inboundLiveAddresses,
      inboundAddresses: inboundAddresses,
    );
    if (targetDanceLookupIds.isNotEmpty) {
      final rows =
          await (_db.select(_db.dances)..where(
                (row) =>
                    row.id.isIn(targetDanceLookupIds) &
                    (allowTombstonedReferences
                        ? const Constant(true)
                        : row.deletedAt.isNull()),
              ))
              .get();
      final missing = _missingReferenceIds(
        ids: targetDanceIds,
        kind: SyncRecordKind.dance,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: rows.map((row) => row.id).toSet(),
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable related dance '
            '"${missing.first}".';
      }
    } else if (targetDanceIds.isNotEmpty) {
      final missing = _missingReferenceIds(
        ids: targetDanceIds,
        kind: SyncRecordKind.dance,
        inboundLiveAddresses: inboundLiveAddresses,
        inboundAddresses: inboundAddresses,
        storedLiveIds: const {},
      );
      if (missing.isNotEmpty) {
        return 'Dance "${dance.id}" references unavailable related dance '
            '"${missing.first}".';
      }
    }
    return null;
  }

  Future<String?> _missingProgramReference(
    Program program, {
    required Set<SyncRecordAddress> inboundLiveAddresses,
    required Set<SyncRecordAddress> inboundAddresses,
    required bool allowTombstonedReferences,
  }) async {
    final danceIds = program.slots
        .map((slot) => slot.danceId)
        .whereType<String>()
        .toSet();
    final lookupIds = _referenceIdsToLookUp(
      ids: danceIds,
      kind: SyncRecordKind.dance,
      inboundLiveAddresses: inboundLiveAddresses,
      inboundAddresses: inboundAddresses,
    );
    final rows =
        await (_db.select(_db.dances)..where(
              (row) =>
                  row.id.isIn(lookupIds) &
                  (allowTombstonedReferences
                      ? const Constant(true)
                      : row.deletedAt.isNull()),
            ))
            .get();
    final missing = _missingReferenceIds(
      ids: danceIds,
      kind: SyncRecordKind.dance,
      inboundLiveAddresses: inboundLiveAddresses,
      inboundAddresses: inboundAddresses,
      storedLiveIds: rows.map((row) => row.id).toSet(),
    );
    return missing.isEmpty
        ? null
        : 'Program "${program.id}" references unavailable dance '
              '"${missing.first}".';
  }

  Future<String?> _invalidDanceDependentRows(
    Dance dance, {
    required _InboundDependentIndex dependentIndex,
  }) async {
    final duplicateAuthorId = _firstDuplicate(dance.authorIds);
    if (duplicateAuthorId != null) {
      return 'Dance "${dance.id}" contains duplicate choreographer id '
          '"$duplicateAuthorId".';
    }
    final duplicateTagId = _firstDuplicate(dance.tagIds);
    if (duplicateTagId != null) {
      return 'Dance "${dance.id}" contains duplicate tag id "$duplicateTagId".';
    }
    final duplicateSourceId = _firstDuplicate(
      dance.sourceCitations.map((citation) => citation.sourceId),
    );
    if (duplicateSourceId != null) {
      return 'Dance "${dance.id}" contains duplicate source id '
          '"$duplicateSourceId".';
    }
    final linkIds = dance.links.map((link) => link.id).toList();
    final duplicateId = _firstDuplicate(linkIds);
    if (duplicateId != null) {
      return 'Dance "${dance.id}" contains duplicate link id "$duplicateId".';
    }
    if (linkIds.isEmpty) return null;

    for (final linkId in linkIds) {
      for (final owner
          in dependentIndex.danceLinkOwners[linkId] ??
              const <SyncRecordAddress>[]) {
        if (owner.recordId == dance.id) continue;
        return 'Dance link id "$linkId" is also owned by '
            '"${owner.recordId}".';
      }
    }

    final rows = await (_db.select(
      _db.danceLinks,
    )..where((row) => row.id.isIn(linkIds))).get();
    for (final row in rows) {
      if (row.danceId != dance.id) {
        return 'Dance link id "${row.id}" is already owned by '
            '"${row.danceId}".';
      }
    }
    return null;
  }

  Future<String?> _invalidProgramDependentRows(
    Program program, {
    required _InboundDependentIndex dependentIndex,
  }) async {
    final slotIds = program.slots.map((slot) => slot.id).toList();
    final duplicateId = _firstDuplicate(slotIds);
    if (duplicateId != null) {
      return 'Program "${program.id}" contains duplicate slot id "$duplicateId".';
    }
    if (slotIds.isEmpty) return null;

    for (final slotId in slotIds) {
      for (final owner
          in dependentIndex.programSlotOwners[slotId] ??
              const <SyncRecordAddress>[]) {
        if (owner.recordId == program.id) continue;
        return 'Program slot id "$slotId" is also owned by '
            '"${owner.recordId}".';
      }
    }

    final rows = await (_db.select(
      _db.programSlots,
    )..where((row) => row.id.isIn(slotIds))).get();
    for (final row in rows) {
      if (row.programId != program.id) {
        return 'Program slot id "${row.id}" is already owned by '
            '"${row.programId}".';
      }
    }
    return null;
  }

  _InboundDependentIndex _dependentIndexFor(
    Map<SyncRecordAddress, SyncApplyRecord> inboundRecords,
  ) {
    final cached = _dependentIndexCache[inboundRecords];
    if (cached != null) return cached;

    final index = _InboundDependentIndex();
    for (final entry in inboundRecords.entries) {
      try {
        switch (entry.key.kind) {
          case SyncRecordKind.dance:
            final dance =
                _decodeEntity(SyncRecordKind.dance, entry.value.body) as Dance;
            for (final link in dance.links) {
              index.danceLinkOwners
                  .putIfAbsent(link.id, () => <SyncRecordAddress>[])
                  .add(entry.key);
            }
          case SyncRecordKind.program:
            final program =
                _decodeEntity(SyncRecordKind.program, entry.value.body)
                    as Program;
            for (final slot in program.slots) {
              index.programSlotOwners
                  .putIfAbsent(slot.id, () => <SyncRecordAddress>[])
                  .add(entry.key);
            }
          default:
            continue;
        }
      } on Object {
        // The current record's decode result reports malformed input; an
        // invalid peer body cannot own a dependent row for another record.
      }
    }
    _dependentIndexCache[inboundRecords] = index;
    return index;
  }

  String? _firstDuplicate(Iterable<String> ids) {
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id)) return id;
    }
    return null;
  }

  Future<String?> _invalidCustomFieldClassification(
    SyncApplyRecord record,
    Object entity, {
    required Set<SyncRecordAddress> inboundAddresses,
    required Map<SyncRecordAddress, SyncApplyRecord> inboundRecords,
  }) async {
    if (record.address.kind == SyncRecordKind.customFieldDef) {
      if (entity is CustomFieldDef && !entity.shareable) {
        return 'Inbound custom-field definition '
            '"${record.address.recordId}" is not shareable.';
      }
      return null;
    }
    if (record.address.kind != SyncRecordKind.dance || entity is! Dance) {
      return null;
    }

    for (final value in entity.customFields) {
      final address = (
        kind: SyncRecordKind.customFieldDef,
        recordId: value.fieldId,
      );
      final inbound = inboundRecords[address];
      if (inbound != null) {
        try {
          final definition =
              _decodeEntity(SyncRecordKind.customFieldDef, inbound.body)
                  as CustomFieldDef;
          if (!definition.shareable) {
            return 'Inbound dance contains a value for non-shareable custom '
                'field "${value.fieldId}".';
          }
        } on Object {
          // The malformed definition receives its own malformed-record report.
        }
      } else if (!inboundAddresses.contains(address)) {
        final row = await (_db.select(
          _db.customFieldDefs,
        )..where((table) => table.id.equals(value.fieldId))).getSingleOrNull();
        final definition = row == null
            ? null
            : CustomFieldDefRepository.toModel(row);
        if (definition != null && !definition.shareable) {
          return 'Inbound dance contains a value for non-shareable custom '
              'field "${value.fieldId}".';
        }
      }
    }
    return null;
  }

  Future<String?> _invalidCustomFieldValue(
    Dance dance, {
    required Set<SyncRecordAddress> inboundLiveAddresses,
    required Set<SyncRecordAddress> inboundAddresses,
    required Map<SyncRecordAddress, SyncApplyRecord> inboundRecords,
  }) async {
    for (final value in dance.customFields) {
      final address = (
        kind: SyncRecordKind.customFieldDef,
        recordId: value.fieldId,
      );
      if (inboundAddresses.contains(address) &&
          !inboundLiveAddresses.contains(address)) {
        continue;
      }

      late final CustomFieldDef definition;
      if (inboundLiveAddresses.contains(address)) {
        final inbound = inboundRecords[address];
        if (inbound == null) continue;
        try {
          definition =
              _decodeEntity(SyncRecordKind.customFieldDef, inbound.body)
                  as CustomFieldDef;
        } on Object catch (error) {
          return 'Dance "${dance.id}" references malformed custom field '
              '"${value.fieldId}": $error';
        }
      } else {
        final row =
            await (_db.select(_db.customFieldDefs)..where(
                  (table) =>
                      table.id.equals(value.fieldId) & table.deletedAt.isNull(),
                ))
                .getSingleOrNull();
        if (row == null) continue;
        final decoded = CustomFieldDefRepository.toModel(row);
        if (decoded == null) {
          return 'Dance "${dance.id}" references corrupt custom field '
              '"${value.fieldId}".';
        }
        definition = decoded;
      }

      try {
        encodeCustomFieldValue(value, definition);
      } on ArgumentError catch (error) {
        return 'Dance "${dance.id}" has an invalid value for custom field '
            '"${value.fieldId}": $error';
      }
    }
    return null;
  }

  Set<String> _referenceIdsToLookUp({
    required Iterable<String> ids,
    required SyncRecordKind kind,
    required Set<SyncRecordAddress> inboundLiveAddresses,
    required Set<SyncRecordAddress> inboundAddresses,
  }) => {
    for (final id in ids)
      if (!inboundLiveAddresses.contains((kind: kind, recordId: id)) &&
          !inboundAddresses.contains((kind: kind, recordId: id)))
        id,
  };

  Set<String> _missingReferenceIds({
    required Iterable<String> ids,
    required SyncRecordKind kind,
    required Set<SyncRecordAddress> inboundLiveAddresses,
    required Set<SyncRecordAddress> inboundAddresses,
    required Set<String> storedLiveIds,
  }) => {
    for (final id in ids)
      if (!inboundLiveAddresses.contains((kind: kind, recordId: id)) &&
          (inboundAddresses.contains((kind: kind, recordId: id)) ||
              !storedLiveIds.contains(id)))
        id,
  };

  SyncReport _malformedReferenceReport(
    SyncApplyRecord record,
    String message,
  ) => SyncReport(
    code: SyncReportCode.malformedRecord,
    kind: record.address.kind,
    recordId: record.address.recordId,
    message: 'Inbound record could not be decoded: $message.',
  );

  Future<Map<String, Object?>?> _readDanceBody(String id) async {
    final dance = await repositories.dances.getById(id, includeDeleted: true);
    return dance == null
        ? null
        : archiveDanceToJson(dance, const {}, includeOptionalFields: true);
  }

  Future<Map<String, Object?>?> _readProgramBody(String id) async {
    final program = await repositories.programs.getById(
      id,
      includeDeleted: true,
    );
    return program == null
        ? null
        : archiveProgramToJson(program, includeOptionalFields: true);
  }

  Future<Map<String, Object?>?> _readChoreographerBody(String id) async {
    final row = await (_db.select(
      _db.choreographers,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return archiveChoreographerToJson(
      Choreographer(
        id: row.id,
        name: row.name,
        website: row.website,
        notes: row.notes,
        email: row.email,
        location: row.location,
        deceased: row.deceased,
      ),
      includeOptionalFields: true,
    );
  }

  Future<Map<String, Object?>?> _readTagBody(String id) async {
    final row = await (_db.select(
      _db.tags,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row == null
        ? null
        : archiveTagToJson(
            Tag(id: row.id, name: row.name, color: row.color),
            includeOptionalFields: true,
          );
  }

  Future<Map<String, Object?>?> _readPublishedSourceBody(String id) async {
    final row = await (_db.select(
      _db.publishedSources,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row == null
        ? null
        : archivePublishedSourceToJson(
            PublishedSource(
              id: row.id,
              title: row.title,
              author: row.author,
              year: row.year,
              url: row.url,
              notes: row.notes,
            ),
            includeOptionalFields: true,
          );
  }

  Future<Map<String, Object?>?> _readCustomFieldBody(String id) async {
    final row = await (_db.select(
      _db.customFieldDefs,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    final field = row == null ? null : CustomFieldDefRepository.toModel(row);
    return field == null
        ? null
        : archiveCustomFieldDefToJson(
            field,
            includeShareable: true,
            includeOptionalFields: true,
          );
  }

  Future<Map<String, Object?>?> _readDifficultyBody(String id) async {
    final row = await (_db.select(
      _db.difficultyLevels,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row == null
        ? null
        : archiveDifficultyLevelToJson(
            DifficultyLevel(
              id: row.id,
              label: row.label,
              position: row.position,
            ),
          );
  }

  Future<Map<String, Object?>?> _readVenueBody(String id) async {
    final row = await (_db.select(
      _db.venues,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return archiveVenueToJson(
      Venue(
        id: row.id,
        name: row.name,
        address1: row.address1,
        address2: row.address2,
        city: row.city,
        stateProv: row.stateProv,
        country: row.country,
        postalCode: row.postalCode,
        plus4: row.plus4,
        website: row.website,
        sponsor: row.sponsor,
        eventName: row.eventName,
        time: row.time,
        genericSchedule: row.genericSchedule,
        price: row.price,
        notes: row.notes,
        contact1Name: row.contact1Name,
        contact1Phone: row.contact1Phone,
        contact1Email: row.contact1Email,
        contact2Name: row.contact2Name,
        contact2Phone: row.contact2Phone,
        contact2Email: row.contact2Email,
        provenance: await _venueProvenance(id),
      ),
      includeOptionalFields: true,
    );
  }

  Object _decodeEntity(SyncRecordKind kind, Map<String, Object?> body) {
    return decodeSyncRecordEntity(kind, body);
  }

  Future<bool> _isLiveVenue(String id) async =>
      (await (_db.select(_db.venues)
            ..where((table) => table.id.equals(id) & table.deletedAt.isNull()))
          .getSingleOrNull()) !=
      null;

  Future<Provenance?> _venueProvenance(String id) async {
    final row = await (_db.select(
      _db.venueProvenance,
    )..where((table) => table.venueId.equals(id))).getSingleOrNull();
    return row == null
        ? null
        : Provenance(
            source: row.source,
            externalId: row.externalId,
            importedAt: row.importedAt,
            permission: row.permission,
            license: row.license,
            sourceVersion: row.sourceVersion,
          );
  }

  Future<void> _restoreTimestamps({
    required SyncRecordKind kind,
    required String id,
    required DateTime updatedAt,
    required DateTime? deletedAt,
    required DateTime existenceAt,
  }) async {
    final currentUpdatedAt = await _currentUpdatedAt(kind, id);
    final effectiveUpdatedAt =
        currentUpdatedAt == null || currentUpdatedAt.isBefore(updatedAt)
        ? updatedAt
        : currentUpdatedAt;
    switch (kind) {
      case SyncRecordKind.dance:
        await (_db.update(_db.dances)..where((row) => row.id.equals(id))).write(
          DancesCompanion(
            updatedAt: Value(effectiveUpdatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.program:
        await (_db.update(
          _db.programs,
        )..where((row) => row.id.equals(id))).write(
          ProgramsCompanion(
            updatedAt: Value(effectiveUpdatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.choreographer:
        await (_db.update(
          _db.choreographers,
        )..where((row) => row.id.equals(id))).write(
          ChoreographersCompanion(
            updatedAt: Value(effectiveUpdatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.tag:
        await (_db.update(_db.tags)..where((row) => row.id.equals(id))).write(
          TagsCompanion(
            updatedAt: Value(effectiveUpdatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.publishedSource:
        await (_db.update(
          _db.publishedSources,
        )..where((row) => row.id.equals(id))).write(
          PublishedSourcesCompanion(
            updatedAt: Value(effectiveUpdatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.customFieldDef:
        await (_db.update(
          _db.customFieldDefs,
        )..where((row) => row.id.equals(id))).write(
          CustomFieldDefsCompanion(
            updatedAt: Value(effectiveUpdatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.difficultyLevel:
        await (_db.update(
          _db.difficultyLevels,
        )..where((row) => row.id.equals(id))).write(
          DifficultyLevelsCompanion(
            updatedAt: Value(effectiveUpdatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.venue:
        await (_db.update(_db.venues)..where((row) => row.id.equals(id))).write(
          VenuesCompanion(
            updatedAt: Value(effectiveUpdatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.setting:
        await (_db.update(
          _db.settings,
        )..where((row) => row.key.equals(id))).write(
          SettingsCompanion(
            updatedAt: Value(effectiveUpdatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
    }
  }

  Future<DateTime?> _currentUpdatedAt(SyncRecordKind kind, String id) async {
    switch (kind) {
      case SyncRecordKind.dance:
        return (await (_db.select(
          _db.dances,
        )..where((row) => row.id.equals(id))).getSingleOrNull())?.updatedAt;
      case SyncRecordKind.program:
        return (await (_db.select(
          _db.programs,
        )..where((row) => row.id.equals(id))).getSingleOrNull())?.updatedAt;
      case SyncRecordKind.choreographer:
        return (await (_db.select(
          _db.choreographers,
        )..where((row) => row.id.equals(id))).getSingleOrNull())?.updatedAt;
      case SyncRecordKind.tag:
        return (await (_db.select(
          _db.tags,
        )..where((row) => row.id.equals(id))).getSingleOrNull())?.updatedAt;
      case SyncRecordKind.publishedSource:
        return (await (_db.select(
          _db.publishedSources,
        )..where((row) => row.id.equals(id))).getSingleOrNull())?.updatedAt;
      case SyncRecordKind.customFieldDef:
        return (await (_db.select(
          _db.customFieldDefs,
        )..where((row) => row.id.equals(id))).getSingleOrNull())?.updatedAt;
      case SyncRecordKind.difficultyLevel:
        return (await (_db.select(
          _db.difficultyLevels,
        )..where((row) => row.id.equals(id))).getSingleOrNull())?.updatedAt;
      case SyncRecordKind.venue:
        return (await (_db.select(
          _db.venues,
        )..where((row) => row.id.equals(id))).getSingleOrNull())?.updatedAt;
      case SyncRecordKind.setting:
        return (await (_db.select(
          _db.settings,
        )..where((row) => row.key.equals(id))).getSingleOrNull())?.updatedAt;
    }
  }

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

/// Device-local marker for configured sync identities that completed a
/// publication. The marker stores salted, slow credential verifiers rather
/// than the raw bearer credentials or a fast unsalted hash.
const syncLastUsedFingerprintKey = 'sync_last_used_fingerprint';

const _syncIdentityVerifierAlgorithm = 'pbkdf2-sha256';
const _syncIdentityKdfIterations = 600000;
const _syncIdentitySaltBytes = 16;
const _syncIdentityVerifierBytes = 32;
final _syncIdentityRandom = Random.secure();

final class _StoredSyncIdentityVerifier {
  const _StoredSyncIdentityVerifier({
    required this.salt,
    required this.verifier,
  });

  factory _StoredSyncIdentityVerifier.create(String syncId) {
    final salt = List<int>.generate(
      _syncIdentitySaltBytes,
      (_) => _syncIdentityRandom.nextInt(256),
    );
    return _StoredSyncIdentityVerifier(
      salt: salt,
      verifier: _deriveSyncIdentityVerifier(syncId, salt),
    );
  }

  final List<int> salt;
  final List<int> verifier;

  bool matches(String syncId) =>
      _constantTimeEquals(verifier, _deriveSyncIdentityVerifier(syncId, salt));

  Map<String, Object?> toJson() => {
    'algorithm': _syncIdentityVerifierAlgorithm,
    'iterations': _syncIdentityKdfIterations,
    'salt': _encodeVerifierBytes(salt),
    'verifier': _encodeVerifierBytes(verifier),
  };
}

List<_StoredSyncIdentityVerifier> _decodeUsedIdentityVerifiers(Object? marker) {
  if (marker is! List) return [];
  final decoded = <_StoredSyncIdentityVerifier>[];
  for (final value in marker) {
    if (value is! Map ||
        value['algorithm'] != _syncIdentityVerifierAlgorithm ||
        value['iterations'] != _syncIdentityKdfIterations ||
        value['salt'] is! String ||
        value['verifier'] is! String) {
      continue;
    }
    final salt = _decodeVerifierBytes(
      value['salt'] as String,
      expectedLength: _syncIdentitySaltBytes,
    );
    final verifier = _decodeVerifierBytes(
      value['verifier'] as String,
      expectedLength: _syncIdentityVerifierBytes,
    );
    if (salt == null || verifier == null) continue;
    decoded.add(_StoredSyncIdentityVerifier(salt: salt, verifier: verifier));
  }
  return decoded;
}

Set<String> _decodeLegacyIdentityFingerprints(Object? marker) =>
    switch (marker) {
      String value when value.isNotEmpty => {value},
      List<Object?> values => {
        for (final value in values)
          if (value is String && value.isNotEmpty) value,
      },
      _ => <String>{},
    };

String _legacyIdentityFingerprint(String syncId) =>
    sha256Hex(utf8.encode(normalizeSyncId(syncId)));

List<int> _deriveSyncIdentityVerifier(String syncId, List<int> salt) {
  final hmac = Hmac(sha256, utf8.encode(normalizeSyncId(syncId)));
  var block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final derived = List<int>.from(block);
  for (var iteration = 1; iteration < _syncIdentityKdfIterations; iteration++) {
    block = hmac.convert(block).bytes;
    for (var index = 0; index < derived.length; index++) {
      derived[index] ^= block[index];
    }
  }
  return derived;
}

String _encodeVerifierBytes(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

List<int>? _decodeVerifierBytes(String value, {required int expectedLength}) {
  if (value.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    return null;
  }
  try {
    final padding = (4 - value.length % 4) % 4;
    final decoded = base64Url.decode('$value${'=' * padding}');
    return decoded.length == expectedLength ? decoded : null;
  } on FormatException {
    return null;
  }
}

bool _constantTimeEquals(List<int> left, List<int> right) {
  var difference = left.length ^ right.length;
  final length = min(left.length, right.length);
  for (var index = 0; index < length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
