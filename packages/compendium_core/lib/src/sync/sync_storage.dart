import 'dart:convert';

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
import '../storage/repositories/repositories.dart';
import '../storage/repositories/custom_field_repository.dart';
import '../storage/repositories/sync_local_repository.dart';
import '../storage/shareable_text.dart';
import 'sync_apply.dart';
import 'sync_codec.dart';
import 'sync_merge.dart';
import 'sync_record_kind.dart';
import 'sync_report.dart';

/// A complete local sync snapshot owned by the repository/database boundary.
class SyncStorageSnapshot {
  const SyncStorageSnapshot({
    required this.epoch,
    required this.previouslyUsed,
    required this.local,
    required this.baseline,
  });

  final String? epoch;
  final bool previouslyUsed;
  final Map<SyncRecordAddress, SyncMergeCandidate?> local;
  final Map<SyncRecordAddress, SyncBaselineEntry> baseline;
}

/// The production storage adapter for the core sync engine.
///
/// Reads use full-fidelity models so a shareable inbound overlay cannot erase
/// device-local fields. Writes use dedicated inbound repository writers so
/// interactive side effects cannot alter the validated peer body, then restore
/// the wire timestamp triple because local persistence stamps causal times.
final class CompendiumSyncStorage
    implements SyncApplyBatchStorage, SyncApplyConcurrencyStorage {
  CompendiumSyncStorage(this.repositories);

  final CompendiumRepositories repositories;
  final Map<SyncRecordAddress, Object> _deferredEntities = {};

  CompendiumDatabase get _db => repositories.db;

  Future<SyncStorageSnapshot> snapshot({
    String? syncId,
  }) => repositories.transaction(() async {
    final baseline = await repositories.syncLocal.snapshotBaseline();
    final baselineState = await repositories.syncLocal.getBaselineState();
    final lastUsedMarker = syncId == null
        ? null
        : await repositories.settings.get(syncLastUsedFingerprintKey);
    final usedFingerprints = _decodeUsedFingerprints(lastUsedMarker);
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

    return SyncStorageSnapshot(
      epoch: baselineState?.epoch,
      previouslyUsed:
          syncId != null &&
          usedFingerprints.contains(syncIdentityFingerprint(syncId)),
      local: local,
      baseline: baseline,
    );
  });

  Future<void> markSyncUsed(String syncId) async {
    final fingerprints = _decodeUsedFingerprints(
      await repositories.settings.get(syncLastUsedFingerprintKey),
    )..add(syncIdentityFingerprint(syncId));
    await repositories.settings.set(
      syncLastUsedFingerprintKey,
      fingerprints.toList()..sort(),
    );
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) =>
      repositories.transaction(action);

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
    }
    final classificationIssue = await _invalidCustomFieldClassification(
      record,
      entity,
      inboundLiveAddresses: inboundLiveAddresses,
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

    final dependentRowIssue = switch (record.address.kind) {
      SyncRecordKind.dance => await _invalidDanceDependentRows(
        entity as Dance,
        inboundRecords: inboundRecords,
      ),
      SyncRecordKind.program => await _invalidProgramDependentRows(
        entity as Program,
        inboundRecords: inboundRecords,
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

    final entity = _decodeEntity(kind, record.body);
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
    required Map<SyncRecordAddress, SyncApplyRecord> inboundRecords,
  }) async {
    final linkIds = dance.links.map((link) => link.id).toList();
    final duplicateId = _firstDuplicate(linkIds);
    if (duplicateId != null) {
      return 'Dance "${dance.id}" contains duplicate link id "$duplicateId".';
    }
    if (linkIds.isEmpty) return null;

    for (final entry in inboundRecords.entries) {
      if (entry.key.kind != SyncRecordKind.dance ||
          entry.key.recordId == dance.id) {
        continue;
      }
      final Dance other;
      try {
        other = _decodeEntity(SyncRecordKind.dance, entry.value.body) as Dance;
      } on FormatException {
        continue;
      } on ArgumentError {
        continue;
      } on StateError {
        continue;
      }
      for (final link in other.links) {
        if (!linkIds.contains(link.id)) continue;
        return 'Dance link id "${link.id}" is also owned by '
            '"${entry.key.recordId}".';
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
    required Map<SyncRecordAddress, SyncApplyRecord> inboundRecords,
  }) async {
    final slotIds = program.slots.map((slot) => slot.id).toList();
    final duplicateId = _firstDuplicate(slotIds);
    if (duplicateId != null) {
      return 'Program "${program.id}" contains duplicate slot id "$duplicateId".';
    }
    if (slotIds.isEmpty) return null;

    for (final entry in inboundRecords.entries) {
      if (entry.key.kind != SyncRecordKind.program ||
          entry.key.recordId == program.id) {
        continue;
      }
      final Program other;
      try {
        other =
            _decodeEntity(SyncRecordKind.program, entry.value.body) as Program;
      } on FormatException {
        continue;
      } on ArgumentError {
        continue;
      } on StateError {
        continue;
      }
      for (final slot in other.slots) {
        if (!slotIds.contains(slot.id)) continue;
        return 'Program slot id "${slot.id}" is also owned by '
            '"${entry.key.recordId}".';
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
    required Set<SyncRecordAddress> inboundLiveAddresses,
    required Set<SyncRecordAddress> inboundAddresses,
    required Map<SyncRecordAddress, SyncApplyRecord> inboundRecords,
  }) async {
    if (record.address.kind == SyncRecordKind.customFieldDef) {
      if (record.deletedAt == null &&
          entity is CustomFieldDef &&
          !entity.shareable) {
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
      if (inboundLiveAddresses.contains(address)) {
        final inbound = inboundRecords[address];
        if (inbound == null) continue;
        try {
          final definition =
              _decodeEntity(SyncRecordKind.customFieldDef, inbound.body)
                  as CustomFieldDef;
          if (!definition.shareable) {
            return 'Inbound dance contains a value for non-shareable custom '
                'field "${value.fieldId}".';
          }
        } on FormatException {
          // The malformed definition receives its own malformed-record report.
        } on ArgumentError {
          // The malformed definition receives its own malformed-record report.
        }
      } else if (!inboundAddresses.contains(address)) {
        final row =
            await (_db.select(_db.customFieldDefs)..where(
                  (table) =>
                      table.id.equals(value.fieldId) & table.deletedAt.isNull(),
                ))
                .getSingleOrNull();
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
        } on FormatException catch (error) {
          return 'Dance "${dance.id}" references malformed custom field '
              '"${value.fieldId}": $error';
        } on ArgumentError catch (error) {
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
    final key = switch (kind) {
      SyncRecordKind.dance => 'dances',
      SyncRecordKind.program => 'programs',
      SyncRecordKind.choreographer => 'choreographers',
      SyncRecordKind.tag => 'tags',
      SyncRecordKind.publishedSource => 'publishedSources',
      SyncRecordKind.customFieldDef => 'customFields',
      SyncRecordKind.difficultyLevel => 'difficultyLevels',
      SyncRecordKind.venue => 'venues',
      SyncRecordKind.setting => throw StateError(
        'settings have no archive entity',
      ),
    };
    final result = archiveFromJson({
      'schemaVersion': 4,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      key: [body],
    });
    final errors = result.errors
        .where((error) => !_isUnknownDifficultyReference(error.message))
        .toList(growable: false);
    if (errors.isNotEmpty || result.droppedEntities.isNotEmpty) {
      throw FormatException(
        errors.isEmpty
            ? 'decoded entity was dropped'
            : errors.map((error) => error.message).join('; '),
      );
    }
    final archive = result.archive;
    return switch (kind) {
      SyncRecordKind.dance => _one(archive.dances, kind),
      SyncRecordKind.program => _one(archive.programs, kind),
      SyncRecordKind.choreographer => _one(archive.choreographers, kind),
      SyncRecordKind.tag => _one(archive.tags, kind),
      SyncRecordKind.publishedSource => _one(archive.publishedSources, kind),
      SyncRecordKind.customFieldDef => _one(archive.customFields, kind),
      SyncRecordKind.difficultyLevel => _one(archive.difficultyLevels, kind),
      SyncRecordKind.venue => _one(archive.venues, kind),
      SyncRecordKind.setting => throw StateError(
        'settings have no archive entity',
      ),
    };
  }

  T _one<T>(List<T> values, SyncRecordKind kind) {
    if (values.length != 1) {
      throw FormatException('expected one ${kind.name} entity');
    }
    return values.single;
  }

  bool _isUnknownDifficultyReference(String message) =>
      message.startsWith('references unknown difficulty level "');

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
    switch (kind) {
      case SyncRecordKind.dance:
        await (_db.update(_db.dances)..where((row) => row.id.equals(id))).write(
          DancesCompanion(
            updatedAt: Value(updatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.program:
        await (_db.update(
          _db.programs,
        )..where((row) => row.id.equals(id))).write(
          ProgramsCompanion(
            updatedAt: Value(updatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.choreographer:
        await (_db.update(
          _db.choreographers,
        )..where((row) => row.id.equals(id))).write(
          ChoreographersCompanion(
            updatedAt: Value(updatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.tag:
        await (_db.update(_db.tags)..where((row) => row.id.equals(id))).write(
          TagsCompanion(
            updatedAt: Value(updatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.publishedSource:
        await (_db.update(
          _db.publishedSources,
        )..where((row) => row.id.equals(id))).write(
          PublishedSourcesCompanion(
            updatedAt: Value(updatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.customFieldDef:
        await (_db.update(
          _db.customFieldDefs,
        )..where((row) => row.id.equals(id))).write(
          CustomFieldDefsCompanion(
            updatedAt: Value(updatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.difficultyLevel:
        await (_db.update(
          _db.difficultyLevels,
        )..where((row) => row.id.equals(id))).write(
          DifficultyLevelsCompanion(
            updatedAt: Value(updatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.venue:
        await (_db.update(_db.venues)..where((row) => row.id.equals(id))).write(
          VenuesCompanion(
            updatedAt: Value(updatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
      case SyncRecordKind.setting:
        await (_db.update(
          _db.settings,
        )..where((row) => row.key.equals(id))).write(
          SettingsCompanion(
            updatedAt: Value(updatedAt),
            deletedAt: Value(deletedAt),
            existenceAt: Value(existenceAt),
          ),
        );
    }
  }

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

/// Device-local marker for configured sync identities that completed a
/// publication. The raw bearer credentials are never stored in this marker.
const syncLastUsedFingerprintKey = 'sync_last_used_fingerprint';

String syncIdentityFingerprint(String syncId) => sha256Hex(utf8.encode(syncId));

Set<String> _decodeUsedFingerprints(Object? marker) => switch (marker) {
  String value when value.isNotEmpty => {value},
  List<Object?> values => {
    for (final value in values)
      if (value is String && value.isNotEmpty) value,
  },
  _ => <String>{},
};
