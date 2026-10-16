import 'dart:convert';
import 'dart:typed_data';

import '../model/choreographer.dart';
import '../model/custom_field.dart';
import '../model/dance.dart';
import '../model/difficulty_level.dart';
import '../model/published_source.dart';
import '../model/program.dart';
import '../model/tag.dart';
import '../model/user_glossary.dart';
import '../model/venue.dart';
import '../privacy/data_classification.dart';
import '../privacy/settings_registry.dart';
import '../serialization/archive_codec.dart';
import '../serialization/archive_entity_codec.dart';
import 'canonical_json.dart';
import 'sync_glossary_body.dart';
import 'sync_record_kind.dart';
import 'sync_retained_fields.dart';
import 'wire_mapping.dart';

/// The record-blob and manifest envelope version defined by W3.
///
/// Bump only when the current value has shipped in a release. While it has
/// not, a wire change joins that version instead, and a server already
/// deployed at it is redeployed first (sync-spec §7.2, "An unreleased `v`";
/// CONTRIBUTING.md, "Versioned formats").
const int syncWireVersion = 1;

/// A record blob or manifest written in an envelope version newer than
/// [syncWireVersion]: another device runs a newer build of the app, and this
/// one cannot read what it shares until it is updated.
///
/// A [FormatException] subtype, so every caller that already treats an
/// undecodable envelope as malformed — the server's manifest validation, the
/// local storage decoders — keeps doing exactly that. Only the client's peer
/// download distinguishes it, to report `SyncReportCode.newerWireVersion`
/// instead of a generic malformed record (spec §6.9).
class SyncNewerWireVersionException extends FormatException {
  const SyncNewerWireVersionException(String label, this.version)
    : super('$label uses a newer sync wire version');

  /// The envelope's own `v`, always greater than [syncWireVersion].
  final int version;
}

/// A record blob carrying a part a newer build added that this build can
/// neither apply nor keep in place (spec §6.7): a key inside a dance's
/// figures, a tune that is no longer text, a kept part on a list item with no
/// id, or a transport setting key. The record is refused whole and reported as
/// coming from a newer version of the app (§6.9).
///
/// Every other field this build does not sync is kept, not refused: see
/// [partitionInboundRecordBody].
///
/// A [FormatException] subtype for the same reason as
/// [SyncNewerWireVersionException]: every caller that treats an undecodable
/// blob as malformed keeps doing so, and only the client's peer download
/// distinguishes it, to report `SyncReportCode.newerRecordFields` rather than
/// a malformed record.
///
/// A body that is structurally wrong — a setting with no `value`, an id that
/// does not match its envelope — is not this, and stays a plain
/// [FormatException].
class SyncNewerFieldException extends FormatException {
  const SyncNewerFieldException(this.kind, this.path)
    : super('body contains a part this build cannot keep: $path');

  final SyncRecordKind kind;

  /// The first such wire path, dot-joined, such as "figures.handHold"; `value`
  /// for a setting.
  final String path;
}

/// A validated, versioned Device Sync record blob.
class SyncRecordBlob {
  SyncRecordBlob({
    this.v = syncWireVersion,
    required this.kind,
    required this.id,
    required DateTime updatedAt,
    required DateTime? deletedAt,
    required DateTime existenceAt,
    required Map<String, Object?> body,
  }) : updatedAt = _normalizeTimestamp(updatedAt),
       deletedAt = deletedAt == null ? null : _normalizeTimestamp(deletedAt),
       existenceAt = _normalizeTimestamp(existenceAt),
       body = _freezeJsonObject(body) {
    _validateVersion(v);
    _validateId(id);
    _validateBlobBody(kind, id, this.body);
    // The whole envelope, not the body: the wire hash covers `toJson()`. Eager
    // on purpose — encoding is also what rejects a body that cannot be
    // canonicalised, and every wire hash reads these bytes instead of
    // re-encoding.
    canonicalUtf8 = canonicalJsonUtf8(toJson()).asUnmodifiableView();
  }

  final int v;
  final SyncRecordKind kind;
  final String id;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime existenceAt;
  final Map<String, Object?> body;

  /// The canonical UTF-8 encoding of [toJson], computed once at construction.
  /// Assigned in the constructor body, never lazily. A read-only view, because
  /// [encodeSyncRecordBlobUtf8] hands the same instance to every caller.
  late final Uint8List canonicalUtf8;

  Map<String, Object?> toJson() => {
    'v': v,
    'kind': kind.name,
    'id': id,
    'updatedAt': _timestampString(updatedAt),
    'deletedAt': deletedAt == null ? null : _timestampString(deletedAt!),
    'existenceAt': _timestampString(existenceAt),
    'body': body,
  };

  static SyncRecordBlob fromJson(Map<String, Object?> value) {
    _rejectNewerVersion(value, 'record blob');
    _requireExactKeys(value, const {
      'v',
      'kind',
      'id',
      'updatedAt',
      'deletedAt',
      'existenceAt',
      'body',
    }, 'record blob');
    final version = value['v'];
    if (version is! int || version != syncWireVersion) {
      throw FormatException('unsupported record blob version');
    }
    final kind = _kindFromJson(value['kind']);
    final id = _requiredString(value['id'], 'id');
    final updatedAt = _parseTimestamp(value['updatedAt'], 'updatedAt');
    final deletedAt = value['deletedAt'] == null
        ? null
        : _parseTimestamp(value['deletedAt'], 'deletedAt');
    final existenceAt = _parseTimestamp(value['existenceAt'], 'existenceAt');
    final body = _decodeCompatibleBody(
      kind,
      _requiredObject(value['body'], 'body'),
    );

    return SyncRecordBlob(
      v: version,
      kind: kind,
      id: id,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      existenceAt: existenceAt,
      body: body,
    );
  }

  /// Adapts records queued by builds that emitted the pre-#1233 total duration.
  ///
  /// Validation runs after this step, so a queued `plannedMinutes` value remains
  /// admitted even though new outbound records use the two classified fields.
  static Map<String, Object?> _decodeCompatibleBody(
    SyncRecordKind kind,
    Map<String, Object?> body,
  ) {
    if (kind != SyncRecordKind.program || body['slots'] is! List) return body;
    return {
      ...body,
      'slots': [
        for (final slot in body['slots']! as List)
          if (slot is Map)
            () {
              final timing = Map<String, Object?>.from(
                slot.cast<String, Object?>(),
              );
              final legacy = timing.remove('plannedMinutes');
              if (!timing.containsKey('danceMinutes') && legacy != null) {
                timing['danceMinutes'] = legacy;
              }
              return timing;
            }()
          else
            slot,
      ],
    };
  }
}

/// A per-key settings record before it is converted to a sync blob.
///
/// Unknown and non-shareable keys fail closed: [toBlob] returns `null`.
class SyncSettingsRecord {
  const SyncSettingsRecord({
    required this.key,
    required this.value,
    required this.updatedAt,
    required this.deletedAt,
    required this.existenceAt,
  });

  final String key;
  final Object? value;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime existenceAt;

  SyncRecordBlob? toBlob() {
    if (classifySettingsKey(key)?.egress != EgressClass.shareable) {
      return null;
    }
    return SyncRecordBlob(
      kind: SyncRecordKind.setting,
      id: key,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      existenceAt: existenceAt,
      body: {'value': value},
    );
  }
}

/// A manifest mapping kind to record id to record content hash.
class SyncManifest {
  SyncManifest({
    this.v = syncWireVersion,
    required this.deviceId,
    required this.epoch,
    required DateTime writtenAt,
    required Map<SyncRecordKind, Map<String, String>> records,
    Set<String> unknownKinds = const {},
  }) : writtenAt = _normalizeTimestamp(writtenAt),
       records = _copyManifestRecords(records),
       unknownKinds = Set.unmodifiable(unknownKinds) {
    _validateVersion(v);
    _validateNonEmptyString(deviceId, 'deviceId');
    _validateNonEmptyString(epoch, 'epoch');
    _validateManifestRecords(this.records);
  }

  final int v;
  final String deviceId;
  final String epoch;
  final DateTime writtenAt;
  final Map<SyncRecordKind, Map<String, String>> records;

  /// The `records` keys this build did not recognise as a record kind and
  /// skipped, when decoded with `skipUnknownKinds: true`; otherwise empty.
  ///
  /// Not part of the wire form: [toJson] writes [records] only, so a manifest
  /// re-encoded from a tolerant decode has lost these kinds. That is why a
  /// caller must never keep such a manifest as a stand-in for the peer's own
  /// (see the app's peer-manifest cache).
  final Set<String> unknownKinds;

  Map<String, Object?> toJson() => {
    'v': v,
    'deviceId': deviceId,
    'epoch': epoch,
    'writtenAt': _timestampString(writtenAt),
    'records': {
      for (final entry in records.entries)
        entry.key.name: Map<String, Object?>.from(entry.value),
    },
  };

  /// Decodes [value] strictly by shape.
  ///
  /// A `records` key naming a kind this build does not know throws, unless
  /// [skipUnknownKinds] is set: then that kind is left out of [records] and
  /// its name is recorded in [unknownKinds]. Everything else stays strict,
  /// including the shape of the skipped kind's own entries.
  ///
  /// Only a client reading a **peer's** manifest may pass it (#709). A peer on
  /// a newer build may publish a kind this one does not know, and refusing the
  /// whole manifest would stop every record that peer holds from arriving.
  /// The server must stay strict (sync-spec §4.5): it reads `records` to
  /// decide which blobs are reachable, so a manifest it only half understood
  /// would let it collect live blobs. A device's own manifest stays strict
  /// too, since it can only ever hold kinds its own build wrote.
  static SyncManifest fromJson(
    Map<String, Object?> value, {
    bool skipUnknownKinds = false,
  }) {
    _rejectNewerVersion(value, 'manifest');
    _requireExactKeys(value, const {
      'v',
      'deviceId',
      'epoch',
      'writtenAt',
      'records',
    }, 'manifest');
    final version = value['v'];
    if (version is! int || version != syncWireVersion) {
      throw FormatException('unsupported manifest version');
    }
    final deviceId = _requiredString(value['deviceId'], 'deviceId');
    final epoch = _requiredString(value['epoch'], 'epoch');
    final writtenAt = _parseTimestamp(value['writtenAt'], 'writtenAt');
    final rawRecords = _requiredObject(value['records'], 'records');
    final records = <SyncRecordKind, Map<String, String>>{};
    final unknownKinds = <String>{};
    for (final entry in rawRecords.entries) {
      final kind = skipUnknownKinds
          ? _knownKindFromJson(entry.key)
          : _kindFromJson(entry.key);
      final rawById = _requiredObject(entry.value, 'records.${entry.key}');
      final byId = <String, String>{};
      for (final record in rawById.entries) {
        final id = _requiredString(record.key, 'record id');
        final hash = _requiredString(record.value, 'record hash');
        if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
          throw FormatException('record hash must be lowercase SHA-256 hex');
        }
        byId[id] = hash;
      }
      if (kind == null) {
        unknownKinds.add(entry.key);
      } else {
        records[kind] = byId;
      }
    }
    return SyncManifest(
      v: version,
      deviceId: deviceId,
      epoch: epoch,
      writtenAt: writtenAt,
      records: records,
      unknownKinds: unknownKinds,
    );
  }
}

/// Returns canonical UTF-8 bytes for a record blob.
Uint8List encodeSyncRecordBlobUtf8(SyncRecordBlob blob) => blob.canonicalUtf8;

/// Returns canonical JSON for a record blob.
String encodeSyncRecordBlob(SyncRecordBlob blob) =>
    canonicalJson(blob.toJson());

/// Decodes a canonical or non-canonical JSON record blob strictly by shape.
SyncRecordBlob decodeSyncRecordBlob(String json) {
  final decoded = _decodeObject(json, 'record blob');
  return SyncRecordBlob.fromJson(decoded);
}

/// Returns canonical UTF-8 bytes for a manifest.
Uint8List encodeSyncManifestUtf8(SyncManifest manifest) =>
    canonicalJsonUtf8(manifest.toJson());

/// Returns canonical JSON for a manifest.
String encodeSyncManifest(SyncManifest manifest) =>
    canonicalJson(manifest.toJson());

/// Decodes a canonical or non-canonical JSON manifest strictly by shape.
///
/// [skipUnknownKinds] is for a client reading a peer's manifest only; see
/// [SyncManifest.fromJson].
SyncManifest decodeSyncManifest(String json, {bool skipUnknownKinds = false}) {
  final decoded = _decodeObject(json, 'manifest');
  return SyncManifest.fromJson(decoded, skipUnknownKinds: skipUnknownKinds);
}

/// Encodes a settings value when its key is classified as shareable.
String? encodeSyncSettingsRecord(SyncSettingsRecord record) {
  final blob = record.toBlob();
  return blob == null ? null : encodeSyncRecordBlob(blob);
}

/// Builds a shareable body for one of the entity kinds: archive-shaped for
/// the eight the compendium archive carries, and from
/// `sync_glossary_body.dart` for the user's glossary (#709).
///
/// [retained] is what this device keeps of the record for a newer version of
/// the app ([partitionInboundRecordBody]); it is put back after projection so
/// the body this device shares is the one it received (spec §6.7). A record
/// this device shares none of (a private custom-field definition) yields an
/// empty body whatever [retained] holds.
Map<String, Object?> syncBodyForEntity(
  SyncRecordKind kind,
  Object entity, {
  Set<String> allowedCustomFieldIds = const {},
  Map<String, Object?>? retained,
}) {
  final archiveBody = switch (kind) {
    SyncRecordKind.dance => archiveDanceToJson(
      _requireEntity<Dance>(entity, kind),
      const {},
      includeOptionalFields: true,
    ),
    SyncRecordKind.program => archiveProgramToJson(
      _requireEntity<Program>(entity, kind),
      includeOptionalFields: true,
    ),
    SyncRecordKind.choreographer => archiveChoreographerToJson(
      _requireEntity<Choreographer>(entity, kind),
      includeOptionalFields: true,
    ),
    SyncRecordKind.tag => archiveTagToJson(
      _requireEntity<Tag>(entity, kind),
      includeOptionalFields: true,
    ),
    SyncRecordKind.publishedSource => archivePublishedSourceToJson(
      _requireEntity<PublishedSource>(entity, kind),
      includeOptionalFields: true,
    ),
    SyncRecordKind.customFieldDef => archiveCustomFieldDefToJson(
      _requireEntity<CustomFieldDef>(entity, kind),
      includeShareable: true,
      includeOptionalFields: true,
    ),
    SyncRecordKind.difficultyLevel => archiveDifficultyLevelToJson(
      _requireEntity<DifficultyLevel>(entity, kind),
    ),
    SyncRecordKind.venue => archiveVenueToJson(
      _requireEntity<Venue>(entity, kind),
      includeOptionalFields: true,
    ),
    SyncRecordKind.glossaryEntry => syncGlossaryEntryBody(
      _requireEntity<StoredUserGlossaryEntry>(entity, kind),
    ),
    SyncRecordKind.figureNote => syncFigureNoteBody(
      _requireEntity<FigureNote>(entity, kind),
    ),
    SyncRecordKind.setting => throw ArgumentError(
      'settings use SyncSettingsRecord',
    ),
  };
  final projected = projectShareableRecordBody(
    kind,
    archiveBody,
    allowedCustomFieldIds: allowedCustomFieldIds,
  );
  // The blob constructor accepts a kept private field from a peer, so it can
  // no longer catch this device's own private field leaking through the
  // projection. Check what this device built itself, before anything kept is
  // put back.
  final own = validateShareableRecordBody(kind, projected);
  if (!own.isValid) {
    throw StateError(
      'projected ${kind.name} body contains non-shareable path '
      '${own.invalidPath}',
    );
  }
  // A body projected to nothing — a private custom-field definition, which
  // shares none of itself — has no record to put kept parts back into. Merging
  // them anyway would publish a body with no identity (and make the blob
  // builder throw on every snapshot); they are swept with the record.
  return retained == null || projected.isEmpty
      ? projected
      : mergeRetainedFields(projected, retained);
}

/// Strictly decodes a sync body into its entity model.
///
/// This is shared by inbound application and persisted review validation so a
/// candidate cannot be presented as actionable when the eventual write would
/// reject its entity body.
Object decodeSyncRecordEntity(SyncRecordKind kind, Map<String, Object?> body) {
  if (kind == SyncRecordKind.setting) {
    throw StateError('settings have no archive entity');
  }
  // The user's glossary is not in the archive; its bodies have their own
  // reader (#709).
  if (kind == SyncRecordKind.glossaryEntry) {
    return decodeSyncGlossaryEntryBody(body);
  }
  if (kind == SyncRecordKind.figureNote) {
    return decodeSyncFigureNoteBody(body);
  }
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
    SyncRecordKind.glossaryEntry ||
    SyncRecordKind.figureNote => throw StateError('decoded above'),
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
    SyncRecordKind.dance => _oneDecoded(archive.dances, kind),
    SyncRecordKind.program => _oneDecoded(archive.programs, kind),
    SyncRecordKind.choreographer => _oneDecoded(archive.choreographers, kind),
    SyncRecordKind.tag => _oneDecoded(archive.tags, kind),
    SyncRecordKind.publishedSource => _oneDecoded(
      archive.publishedSources,
      kind,
    ),
    SyncRecordKind.customFieldDef => _oneDecoded(archive.customFields, kind),
    SyncRecordKind.difficultyLevel => _oneDecoded(
      archive.difficultyLevels,
      kind,
    ),
    SyncRecordKind.venue => _oneDecoded(archive.venues, kind),
    SyncRecordKind.setting => throw StateError(
      'settings have no archive entity',
    ),
    SyncRecordKind.glossaryEntry ||
    SyncRecordKind.figureNote => throw StateError('decoded above'),
  };
}

/// Validates the entity and classification constraints for a review action.
void validateSyncReviewCandidateBody(
  SyncRecordKind kind,
  Map<String, Object?> body,
) {
  final split = partitionInboundRecordBody(kind, body);
  if (split.refusedPath case final path?) {
    throw SyncNewerFieldException(kind, path);
  }
  if (kind == SyncRecordKind.customFieldDef && body['shareable'] == false) {
    throw FormatException('custom-field definition is not shareable');
  }
  decodeSyncRecordEntity(kind, split.known);
}

/// Builds a versioned blob for one of the entity kinds (every kind but
/// `setting`).
SyncRecordBlob? syncRecordBlobForEntity(
  SyncRecordKind kind,
  Object entity, {
  required DateTime updatedAt,
  required DateTime existenceAt,
  DateTime? deletedAt,
  Set<String> allowedCustomFieldIds = const {},
  Map<String, Object?>? retained,
}) {
  if (kind == SyncRecordKind.setting) {
    throw ArgumentError('settings use SyncSettingsRecord');
  }
  final body = syncBodyForEntity(
    kind,
    entity,
    allowedCustomFieldIds: allowedCustomFieldIds,
    retained: retained,
  );
  if (body.isEmpty) return null;
  final id = _requiredString(body['id'], 'body.id');
  return SyncRecordBlob(
    kind: kind,
    id: id,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
    existenceAt: existenceAt,
    body: body,
  );
}

T _oneDecoded<T>(List<T> values, SyncRecordKind kind) {
  if (values.length != 1) {
    throw FormatException('expected one ${kind.name} entity');
  }
  return values.single;
}

T _requireEntity<T>(Object entity, SyncRecordKind kind) {
  if (entity is T) return entity as T;
  throw ArgumentError('entity does not match kind ${kind.name}');
}

Map<String, Object?> _decodeObject(String json, String label) {
  final decoded = jsonDecode(json);
  if (decoded is! Map) throw FormatException('$label must be a JSON object');
  return _requiredObject(decoded, label);
}

Map<String, Object?> _requiredObject(Object? value, String field) {
  if (value is! Map) throw FormatException('$field must be an object');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$field keys must be strings');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
  return value;
}

/// The kind [value] names, or null when it is a well-formed name this build
/// does not know. A value that is not a non-empty string is still malformed.
SyncRecordKind? _knownKindFromJson(Object? value) {
  if (value is! String || value.isEmpty) {
    throw FormatException('kind must be a non-empty string');
  }
  for (final kind in SyncRecordKind.values) {
    if (kind.name == value) return kind;
  }
  return null;
}

SyncRecordKind _kindFromJson(Object? value) {
  if (value is! String) throw FormatException('kind must be a string');
  for (final kind in SyncRecordKind.values) {
    if (kind.name == value) return kind;
  }
  throw FormatException('unknown record kind $value');
}

bool _isUnknownDifficultyReference(String message) =>
    message.startsWith('references unknown difficulty level "');

void _validateBlobBody(
  SyncRecordKind kind,
  String id,
  Map<String, Object?> body,
) {
  if (kind == SyncRecordKind.setting && !body.containsKey('value')) {
    throw FormatException('setting body must contain value');
  }
  if (kind != SyncRecordKind.setting && body['id'] != id) {
    throw FormatException('body id must match envelope id');
  }
  final split = partitionInboundRecordBody(
    kind,
    body,
    settingsKey: kind == SyncRecordKind.setting ? id : null,
  );
  if (split.refusedPath case final path?) {
    throw SyncNewerFieldException(kind, path);
  }
}

DateTime _parseTimestamp(Object? value, String field) {
  if (value is! String || !value.endsWith('Z')) {
    throw FormatException('$field must be a UTC timestamp');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      !parsed.isUtc ||
      parsed.millisecond != 0 ||
      parsed.microsecond != 0) {
    throw FormatException('$field must use UTC one-second precision');
  }
  return parsed;
}

DateTime _normalizeTimestamp(DateTime value) {
  final micros = value.toUtc().microsecondsSinceEpoch;
  return DateTime.fromMicrosecondsSinceEpoch(
    micros - micros.remainder(Duration.microsecondsPerSecond),
    isUtc: true,
  );
}

String _timestampString(DateTime value) =>
    _normalizeTimestamp(value).toIso8601String();

void _validateVersion(int value) {
  if (value != syncWireVersion) {
    throw ArgumentError.value(value, 'v', 'unsupported sync wire version');
  }
}

void _validateId(String value) => _validateNonEmptyString(value, 'id');

void _validateNonEmptyString(String value, String field) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, field, 'must not be empty');
  }
}

Map<String, Object?> _freezeJsonObject(Map<String, Object?> value) {
  final active = Set<Object>.identity();
  return _freezeJsonMap(value, active);
}

Map<String, Object?> _freezeJsonMap(
  Map<Object?, Object?> value,
  Set<Object> active,
) {
  if (!active.add(value)) {
    throw ArgumentError.value(value, 'body', 'must not contain cycles');
  }
  try {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw ArgumentError.value(
          entry.key,
          'body',
          'nested map keys must be strings',
        );
      }
      result[entry.key as String] = _freezeJsonValue(entry.value, active);
    }
    return Map.unmodifiable(result);
  } finally {
    active.remove(value);
  }
}

Object? _freezeJsonValue(Object? value, Set<Object> active) {
  if (value is Map) return _freezeJsonMap(value, active);
  if (value is List) {
    if (!active.add(value)) {
      throw ArgumentError.value(value, 'body', 'must not contain cycles');
    }
    try {
      return List<Object?>.unmodifiable([
        for (final item in value) _freezeJsonValue(item, active),
      ]);
    } finally {
      active.remove(value);
    }
  }
  return value;
}

/// Throws [SyncNewerWireVersionException] when [value] declares an envelope
/// version newer than this build's.
///
/// Runs before every other check, the exact key set included: a newer version
/// is free to add envelope keys, and checked second, that added key made a
/// newer envelope fail as a malformed one — leaving the user told something
/// was broken when the remedy was to update the app.
void _rejectNewerVersion(Map<String, Object?> value, String label) {
  final version = value['v'];
  if (version is int && version > syncWireVersion) {
    throw SyncNewerWireVersionException(label, version);
  }
}

void _requireExactKeys(
  Map<String, Object?> value,
  Set<String> required,
  String label,
) {
  if (!value.keys.toSet().containsAll(required) ||
      value.length != required.length) {
    throw FormatException('$label has an invalid envelope shape');
  }
}

Map<SyncRecordKind, Map<String, String>> _copyManifestRecords(
  Map<SyncRecordKind, Map<String, String>> input,
) => Map.unmodifiable(<SyncRecordKind, Map<String, String>>{
  for (final entry in input.entries)
    entry.key: Map.unmodifiable(Map<String, String>.from(entry.value)),
});

void _validateManifestRecords(
  Map<SyncRecordKind, Map<String, String>> records,
) {
  for (final entry in records.entries) {
    for (final record in entry.value.entries) {
      _validateNonEmptyString(record.key, 'record id');
      _validateHash(record.value);
    }
  }
}

void _validateHash(String value) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'record hash',
      'must be lowercase SHA-256 hex',
    );
  }
}
