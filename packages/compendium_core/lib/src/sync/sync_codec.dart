import 'dart:convert';
import 'dart:typed_data';

import '../model/choreographer.dart';
import '../model/custom_field.dart';
import '../model/dance.dart';
import '../model/published_source.dart';
import '../model/program.dart';
import '../model/tag.dart';
import '../model/venue.dart';
import '../privacy/data_classification.dart';
import '../privacy/settings_registry.dart';
import '../serialization/archive_entity_codec.dart';
import 'canonical_json.dart';
import 'sync_record_kind.dart';
import 'wire_mapping.dart';

/// The record-blob and manifest envelope version defined by W3.
const int syncWireVersion = 1;

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
       body = Map.unmodifiable(body) {
    _validateVersion(v);
    _validateId(id);
    _validateBlobBody(kind, id, this.body);
  }

  final int v;
  final SyncRecordKind kind;
  final String id;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime existenceAt;
  final Map<String, Object?> body;

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
    final body = _requiredObject(value['body'], 'body');

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
  }) : writtenAt = _normalizeTimestamp(writtenAt),
       records = _copyManifestRecords(records) {
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

  static SyncManifest fromJson(Map<String, Object?> value) {
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
    for (final entry in rawRecords.entries) {
      final kind = _kindFromJson(entry.key);
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
      records[kind] = byId;
    }
    return SyncManifest(
      v: version,
      deviceId: deviceId,
      epoch: epoch,
      writtenAt: writtenAt,
      records: records,
    );
  }
}

/// Returns canonical UTF-8 bytes for a record blob.
Uint8List encodeSyncRecordBlobUtf8(SyncRecordBlob blob) =>
    canonicalJsonUtf8(blob.toJson());

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
SyncManifest decodeSyncManifest(String json) {
  final decoded = _decodeObject(json, 'manifest');
  return SyncManifest.fromJson(decoded);
}

/// Encodes a settings value when its key is classified as shareable.
String? encodeSyncSettingsRecord(SyncSettingsRecord record) {
  final blob = record.toBlob();
  return blob == null ? null : encodeSyncRecordBlob(blob);
}

/// Builds a shareable archive-shaped body for one of the seven entity kinds.
Map<String, Object?> syncBodyForEntity(
  SyncRecordKind kind,
  Object entity, {
  Set<String> allowedCustomFieldIds = const {},
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
    SyncRecordKind.venue => archiveVenueToJson(
      _requireEntity<Venue>(entity, kind),
      includeOptionalFields: true,
    ),
    SyncRecordKind.setting => throw ArgumentError(
      'settings use SyncSettingsRecord',
    ),
  };
  return projectShareableRecordBody(
    kind,
    archiveBody,
    allowedCustomFieldIds: allowedCustomFieldIds,
  );
}

/// Builds a versioned blob for one of the seven archive entity kinds.
SyncRecordBlob syncRecordBlobForEntity(
  SyncRecordKind kind,
  Object entity, {
  required DateTime updatedAt,
  required DateTime existenceAt,
  DateTime? deletedAt,
  Set<String> allowedCustomFieldIds = const {},
}) {
  if (kind == SyncRecordKind.setting) {
    throw ArgumentError('settings use SyncSettingsRecord');
  }
  final body = syncBodyForEntity(
    kind,
    entity,
    allowedCustomFieldIds: allowedCustomFieldIds,
  );
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

T _requireEntity<T>(Object entity, SyncRecordKind kind) {
  if (entity is T) return entity as T;
  throw ArgumentError('entity does not match kind ${kind.name}');
}

Map<String, Object?> _decodeObject(String json, String label) {
  final decoded = jsonDecode(json);
  if (decoded is! Map) throw FormatException('$label must be a JSON object');
  return Map<String, Object?>.from(decoded);
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

SyncRecordKind _kindFromJson(Object? value) {
  if (value is! String) throw FormatException('kind must be a string');
  for (final kind in SyncRecordKind.values) {
    if (kind.name == value) return kind;
  }
  throw FormatException('unknown record kind $value');
}

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
  final validation = validateShareableRecordBody(
    kind,
    body,
    settingsKey: kind == SyncRecordKind.setting ? id : null,
  );
  if (!validation.isValid) {
    throw FormatException(
      'body contains non-shareable path ${validation.invalidPath}',
    );
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
