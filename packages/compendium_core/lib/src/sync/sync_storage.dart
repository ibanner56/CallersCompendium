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
/// device-local fields. Writes use the existing repositories for entity and
/// join-table handling, then restore the wire timestamp triple because the
/// repositories intentionally stamp local causal times.
final class CompendiumSyncStorage implements SyncApplyReportingStorage {
  CompendiumSyncStorage(this.repositories);

  final CompendiumRepositories repositories;

  CompendiumDatabase get _db => repositories.db;

  Future<SyncStorageSnapshot> snapshot() async {
    final baseline = await repositories.syncLocal.snapshotBaseline();
    final baselineState = await repositories.syncLocal.getBaselineState();
    final published = await repositories.syncLocal.listPublishedRecords();
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
      previouslyUsed: published.isNotEmpty,
      local: local,
      baseline: baseline,
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
  Future<void> write(SyncApplyRecord record) async {
    await writeWithReport(record);
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
        final existing = await repositories.dances.getById(
          record.address.recordId,
          includeDeleted: true,
        );
        if (existing == null) {
          await repositories.dances.create(entityToWrite as Dance);
        } else {
          await repositories.dances.update(entityToWrite as Dance);
        }
      case SyncRecordKind.program:
        final existing = await repositories.programs.getById(
          record.address.recordId,
          includeDeleted: true,
        );
        if (existing == null) {
          await repositories.programs.create(entityToWrite as Program);
        } else {
          await repositories.programs.update(entityToWrite as Program);
        }
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
  Future<void> rebuildDerivedIndexes() async {
    await repositories.dances.rebuildAllDerived();
  }

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
    if (result.errors.isNotEmpty || result.droppedEntities.isNotEmpty) {
      throw FormatException(
        result.errors.isEmpty
            ? 'decoded entity was dropped'
            : result.errors.map((error) => error.message).join('; '),
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
