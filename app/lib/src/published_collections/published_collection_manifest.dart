import 'dart:convert';

import '../update/semver.dart';
import 'published_collection_config.dart';

/// A manifest-format or trust-contract violation at the published-collection
/// boundary. The UI maps this stable type to a non-leaking localized message.
class PublishedCollectionFormatException implements Exception {
  const PublishedCollectionFormatException(this.message);

  final String message;

  @override
  String toString() => 'PublishedCollectionFormatException: $message';
}

class PublishedCollectionPermission {
  const PublishedCollectionPermission({
    required this.grantor,
    required this.holder,
    required this.basis,
    required this.license,
    required this.fields,
  });

  final String grantor;
  final String holder;
  final String basis;
  final String license;
  final List<String> fields;

  /// Stable value carried into [Provenance.permission]. The manifest's
  /// declaration, not an inferred URL or publisher default, is authoritative.
  String get declaration => jsonEncode({
    'grantor': grantor,
    'holder': holder,
    'basis': basis,
    'license': license,
    'fields': fields,
  });

  factory PublishedCollectionPermission.fromJson(Object? raw) {
    final map = _object(raw, 'permission');
    final grantor = _boundedString(map, 'grantor', 200);
    final holder = _boundedString(map, 'holder', 200);
    final basis = _boundedString(map, 'basis', 200);
    final license = _boundedString(map, 'license', 200);
    final fields = _stringList(map['fields'], 'permission.fields', 100, 40);
    if (fields.toSet().length != fields.length) {
      throw const PublishedCollectionFormatException(
        'permission.fields contains duplicates',
      );
    }
    return PublishedCollectionPermission(
      grantor: grantor,
      holder: holder,
      basis: basis,
      license: license,
      fields: List.unmodifiable(fields),
    );
  }
}

class PublishedCollectionEntry {
  const PublishedCollectionEntry({
    required this.id,
    required this.version,
    required this.title,
    required this.archiveUrl,
    required this.archiveBytes,
    required this.sha256,
    required this.danceCount,
    required this.license,
    required this.permission,
    required this.requiredCapabilities,
    this.supersedes,
  });

  final String id;
  final String version;
  final String title;
  final Uri archiveUrl;
  final int archiveBytes;
  final String sha256;
  final int danceCount;
  final String license;
  final PublishedCollectionPermission permission;
  final List<String> requiredCapabilities;
  final String? supersedes;

  List<String> get unsupportedCapabilities => requiredCapabilities
      .where(
        (capability) => !PublishedCollectionManifest.supportedCapabilities
            .contains(capability),
      )
      .toList(growable: false);

  bool get isSupported => unsupportedCapabilities.isEmpty;
}

class PublishedCollectionManifest {
  const PublishedCollectionManifest({
    required this.schemaMajor,
    required this.schemaMinor,
    required this.minReaderVersion,
    required this.collections,
  });

  static const int supportedSchemaMajor = 1;
  static const int supportedSchemaMinor = 0;
  static const Set<String> supportedCapabilities = {
    'compositePhraseStructureV1',
  };

  final int schemaMajor;
  final int schemaMinor;
  final SemVer minReaderVersion;
  final List<PublishedCollectionEntry> collections;

  static PublishedCollectionManifest parse(
    String source, {
    required SemVer readerVersion,
  }) {
    final root = _object(jsonDecode(source), 'manifest');
    final schema = _object(root['manifestSchema'], 'manifestSchema');
    final major = _positiveInt(schema, 'major', allowZero: true);
    final minor = _positiveInt(schema, 'minor', allowZero: true);
    if (major != supportedSchemaMajor) {
      throw PublishedCollectionFormatException(
        'unsupported manifest major $major',
      );
    }
    if (minor > supportedSchemaMinor) {
      throw PublishedCollectionFormatException(
        'unsupported manifest minor $minor',
      );
    }
    final minReaderText = _boundedString(root, 'minReaderVersion', 40);
    final minReader = SemVer.tryParse(minReaderText);
    if (minReader == null) {
      throw const PublishedCollectionFormatException(
        'minReaderVersion is not valid semver',
      );
    }
    if (readerVersion.compareTo(minReader) < 0) {
      throw const PublishedCollectionFormatException(
        'reader version is below manifest minimum',
      );
    }

    final rawCollections = root['collections'];
    if (rawCollections is! List || rawCollections.isEmpty) {
      throw const PublishedCollectionFormatException(
        'collections must be a non-empty array',
      );
    }
    final collections = <PublishedCollectionEntry>[];
    final ids = <String>{};
    for (final raw in rawCollections) {
      final entry = _entry(raw);
      if (!ids.add('${entry.id}@${entry.version}')) {
        throw const PublishedCollectionFormatException(
          'duplicate collection version',
        );
      }
      collections.add(entry);
    }
    return PublishedCollectionManifest(
      schemaMajor: major,
      schemaMinor: minor,
      minReaderVersion: minReader,
      collections: List.unmodifiable(collections),
    );
  }

  static PublishedCollectionEntry _entry(Object? raw) {
    final map = _object(raw, 'collection');
    final id = _identifier(map, 'id');
    final version = _identifier(map, 'version');
    final title = _boundedString(map, 'title', 200);
    final archiveUrl = _httpsUrl(map, 'archiveUrl');
    final archiveBytes = _positiveInt(map, 'archiveBytes');
    if (archiveBytes > kMaxPublishedCollectionArchiveBytes) {
      throw const PublishedCollectionFormatException(
        'archiveBytes exceeds the resource-safety ceiling',
      );
    }
    final sha256 = _boundedString(map, 'sha256', 64);
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw const PublishedCollectionFormatException(
        'sha256 must be lowercase hexadecimal',
      );
    }
    final danceCount = _positiveInt(map, 'danceCount', allowZero: true);
    final license = _boundedString(map, 'license', 200);
    final permission = PublishedCollectionPermission.fromJson(
      map['permission'],
    );
    if (permission.license != license) {
      throw const PublishedCollectionFormatException(
        'permission.license must match license',
      );
    }
    final capabilities = _stringList(
      map['requiredCapabilities'] ?? const [],
      'requiredCapabilities',
      100,
      40,
    );
    if (capabilities.toSet().length != capabilities.length) {
      throw const PublishedCollectionFormatException(
        'requiredCapabilities contains duplicates',
      );
    }
    final supersedesRaw = map['supersedes'];
    if (supersedesRaw != null && supersedesRaw is! String) {
      throw const PublishedCollectionFormatException(
        'supersedes must be a string or null',
      );
    }
    if (supersedesRaw is String &&
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(supersedesRaw)) {
      throw const PublishedCollectionFormatException(
        'supersedes has invalid characters',
      );
    }
    return PublishedCollectionEntry(
      id: id,
      version: version,
      title: title,
      archiveUrl: archiveUrl,
      archiveBytes: archiveBytes,
      sha256: sha256,
      danceCount: danceCount,
      license: license,
      permission: permission,
      requiredCapabilities: List.unmodifiable(capabilities),
      supersedes: supersedesRaw as String?,
    );
  }
}

Map<String, Object?> _object(Object? raw, String name) {
  if (raw is Map<String, Object?>) return raw;
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  throw PublishedCollectionFormatException('$name must be an object');
}

String _boundedString(Map<String, Object?> map, String key, int maxLength) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty || value.length > maxLength) {
    throw PublishedCollectionFormatException(
      '$key must be a non-empty string of at most $maxLength characters',
    );
  }
  return value.trim();
}

String _identifier(Map<String, Object?> map, String key) {
  final value = _boundedString(map, key, 64);
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(value)) {
    throw PublishedCollectionFormatException('$key has invalid characters');
  }
  return value;
}

int _positiveInt(
  Map<String, Object?> map,
  String key, {
  bool allowZero = false,
}) {
  final value = map[key];
  if (value is! int || (allowZero ? value < 0 : value <= 0)) {
    throw PublishedCollectionFormatException(
      '$key must be an ${allowZero ? 'non-negative' : 'positive'} integer',
    );
  }
  return value;
}

Uri _httpsUrl(Map<String, Object?> map, String key) {
  final value = _boundedString(map, key, 2048);
  final uri = Uri.tryParse(value);
  if (uri == null || !isAllowedPublishedCollectionUri(uri)) {
    throw PublishedCollectionFormatException(
      '$key is not an allowed HTTPS URL',
    );
  }
  return uri;
}

List<String> _stringList(
  Object? raw,
  String name,
  int maxItemLength,
  int maxItems,
) {
  if (raw is! List || raw.length > maxItems) {
    throw PublishedCollectionFormatException(
      '$name must be an array of at most $maxItems strings',
    );
  }
  final result = <String>[];
  for (final value in raw) {
    if (value is! String ||
        value.trim().isEmpty ||
        value.length > maxItemLength) {
      throw PublishedCollectionFormatException(
        '$name contains an invalid string',
      );
    }
    result.add(value.trim());
  }
  return result;
}
