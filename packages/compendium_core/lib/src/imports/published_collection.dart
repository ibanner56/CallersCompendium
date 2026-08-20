import 'dart:convert';

import 'package:meta/meta.dart';

import '../model/collection_import_event.dart';
import '../model/choreographer.dart';
import '../model/dance.dart';
import '../model/enums.dart';
import '../serialization/archive_codec.dart';
import '../serialization/compendium_archive.dart';
import '../util/uuid.dart';
import 'dedupe.dart';
import 'import_error.dart';
import 'import_pipeline.dart';
import 'raw_record.dart';
import 'source_adapter.dart';
import 'structured_draft.dart';

/// The manifest-authoritative metadata for one published collection archive.
///
/// The manifest is owned and parsed by the app/network layer. Core receives
/// this value object only after that layer has verified the manifest and archive
/// digest.
@immutable
class PublishedCollectionMetadata {
  const PublishedCollectionMetadata({
    required this.collectionId,
    required this.collectionVersion,
    required this.archiveDigest,
    this.permission,
    this.license,
  }) : assert(collectionId != ''),
       assert(collectionVersion != ''),
       assert(archiveDigest != '');

  final String collectionId;
  final String collectionVersion;
  final String archiveDigest;
  final String? permission;
  final String? license;
}

/// Decodes and validates the hard dance-only v1 archive contract.
class PublishedCollectionArchive {
  const PublishedCollectionArchive._();

  /// Returns the decoded archive, or throws [ImportError] before any import
  /// planning can occur.
  static CompendiumArchive decode(String payload) {
    if (payload.trim().isEmpty) {
      throw _invalid('No published collection archive provided.');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException catch (error) {
      throw _invalid('Published collection archive is not valid JSON: $error');
    }
    if (decoded is! Map) {
      throw _invalid('Published collection archive must have an object root.');
    }

    final root = Map<String, Object?>.from(decoded);
    const allowed = {
      'schemaVersion',
      'exportedAt',
      'dances',
      'choreographers',
      'programs',
      'venues',
      'publishedSources',
      'customFields',
      'tags',
    };
    final unknown = root.keys.where((key) => !allowed.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw _invalid('Unknown top-level entities: ${unknown.join(', ')}.');
    }

    for (final key in const [
      'programs',
      'venues',
      'publishedSources',
      'customFields',
      'tags',
    ]) {
      _rejectNonEmptyEntity(root, key);
    }

    final dances = root['dances'];
    if (dances is! List) {
      throw _invalid(
        'Published collection archive must contain a dances array.',
      );
    }
    final ids = <String>{};
    for (var index = 0; index < dances.length; index++) {
      final item = dances[index];
      if (item is! Map) {
        throw _invalid('Dance at index $index must be an object.');
      }
      final dance = Map<String, Object?>.from(item);
      final id = dance['id'];
      if (id is! String || id.trim().isEmpty) {
        throw _invalid('Dance at index $index is missing a dance id.');
      }
      if (!ids.add(id)) {
        throw _invalid(
          'Published collection contains duplicate dance id "$id".',
        );
      }
      final provenance = dance['provenance'];
      if (provenance is Map &&
          provenance['source'] == ProvenanceSource.publishedCollection.name) {
        throw _invalid(
          'Published collection dance "$id" contains embedded published '
          'provenance.',
        );
      }
      _rejectNonEmptyDanceEntity(dance, 'customFields', id);
    }

    final result = decodeArchive(payload);
    for (final error in result.errors) {
      if (error.entityType == 'archive' &&
          error.kind == ArchiveErrorKind.read) {
        throw _invalid(
          'Published collection archive could not be decoded: $error',
        );
      }
    }
    return result.archive;
  }

  static ImportError _invalid(String message) => ImportError(
    stage: ImportStage.discover,
    source: ProvenanceSource.publishedCollection,
    message: message,
  );

  static void _rejectNonEmptyEntity(Map<String, Object?> root, String key) {
    final value = root[key];
    if (value is List && value.isNotEmpty) {
      throw _invalid(
        'Published collection v1 does not permit top-level "$key" content.',
      );
    }
    if (value != null && value is! List) {
      throw _invalid('Published collection "$key" must be an array.');
    }
  }

  static void _rejectNonEmptyDanceEntity(
    Map<String, Object?> dance,
    String key,
    String danceId,
  ) {
    final value = dance[key];
    if (value is List && value.isNotEmpty) {
      throw _invalid(
        'Published collection dance "$danceId" contains custom-field content.',
      );
    }
    if (value != null && value is! List) {
      throw _invalid('Published collection dance "$danceId" has invalid $key.');
    }
  }
}

/// A strict dance-only adapter for a published collection archive.
///
/// Unlike the generic JSON adapter, this path validates the complete envelope
/// before the pipeline can plan a single record. Programs, venues, metadata
/// entities, unknown top-level keys, duplicate/missing dance ids, and embedded
/// provenance are rejected rather than being silently dropped or trusted.
class PublishedCollectionAdapter implements SourceAdapter {
  PublishedCollectionAdapter(this.metadata)
    : _delegate = _buildDelegate(metadata);

  final PublishedCollectionMetadata metadata;
  final SourceAdapter _delegate;

  static SourceAdapter _buildDelegate(PublishedCollectionMetadata metadata) =>
      _PublishedGenericJsonAdapter(metadata);

  @override
  ProvenanceSource get source => ProvenanceSource.publishedCollection;

  @override
  Future<List<DiscoveredRecord>> discover(ImportRequest request) async {
    PublishedCollectionArchive.decode(request.payload ?? '');
    return _delegate.discover(request);
  }

  @override
  Future<RawRecord> fetch(DiscoveredRecord record) => _delegate.fetch(record);

  @override
  StructuredDraft parse(RawRecord raw) => _delegate.parse(raw);
}

/// The published-collection adapter's generic JSON implementation.
///
/// Kept private so callers cannot accidentally use a published source without
/// the strict envelope validation above.
class _PublishedGenericJsonAdapter implements SourceAdapter {
  _PublishedGenericJsonAdapter(this.metadata);

  final PublishedCollectionMetadata metadata;
  final Map<String, Dance> _dancesById = {};
  final Map<String, Choreographer> _choreographersById = {};
  int _schemaVersion = archiveSchemaVersion;

  @override
  ProvenanceSource get source => ProvenanceSource.publishedCollection;

  @override
  Future<List<DiscoveredRecord>> discover(ImportRequest request) async {
    _dancesById.clear();
    _choreographersById.clear();
    final result = decodeArchive(request.payload!);
    final rootError = _rootReadError(result);
    if (rootError != null) {
      throw ImportError(
        stage: ImportStage.discover,
        source: source,
        message:
            'Published collection archive could not be decoded: $rootError',
      );
    }
    _schemaVersion = result.archive.schemaVersion;
    _dancesById.addEntries(
      result.archive.dances.map((dance) => MapEntry(dance.id, dance)),
    );
    _choreographersById.addEntries(
      result.archive.choreographers.map((c) => MapEntry(c.id, c)),
    );
    return [
      for (final dance in result.archive.dances)
        DiscoveredRecord(
          source: source,
          externalId: '${metadata.collectionId}/${dance.id}',
          label: dance.title,
          locator: {'danceId': dance.id},
        ),
    ];
  }

  @override
  Future<RawRecord> fetch(DiscoveredRecord record) async {
    final id = record.locator['danceId'];
    if (id is! String || !_dancesById.containsKey(id)) {
      throw fetchError(
        source,
        'Published collection dance locator is invalid; re-run discover.',
        externalId: record.externalId,
      );
    }
    final dance = _dancesById[id]!;
    return RawRecord(
      source: source,
      externalId: '${metadata.collectionId}/$id',
      sourceVersion: metadata.collectionVersion,
      permission: metadata.permission,
      license: metadata.license,
      payload: encodeArchive(
        CompendiumArchive(
          schemaVersion: _schemaVersion,
          exportedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          dances: [dance.copyWith(clearProvenance: true)],
          choreographers: [
            for (final authorId in dance.authorIds)
              if (_choreographersById[authorId] != null)
                _choreographersById[authorId]!,
          ],
        ),
      ),
      contentType: 'application/json',
    );
  }

  @override
  StructuredDraft parse(RawRecord raw) {
    final result = decodeArchive(raw.payload);
    final rootError = _rootReadError(result);
    if (rootError != null || result.archive.dances.length != 1) {
      throw parseError(
        source,
        'Published collection record does not contain exactly one dance.',
        externalId: raw.externalId,
      );
    }
    final dance = result.archive.dances.single;
    final names = <String>[];
    final seen = <String>{};
    final namesById = {
      for (final c in result.archive.choreographers) c.id: c.name,
    };
    for (final id in dance.authorIds) {
      final name = namesById[id]?.trim();
      if (seen.add(id) && name != null && name.isNotEmpty) names.add(name);
    }
    return StructuredDraft(
      dance: dance.copyWith(clearProvenance: true),
      raw: raw,
      authorNames: names,
    );
  }

  static ArchiveError? _rootReadError(ArchiveReadResult result) {
    for (final error in result.errors) {
      if (error.entityType == 'archive' &&
          error.kind == ArchiveErrorKind.read) {
        return error;
      }
    }
    return null;
  }
}

/// The result of planning and committing a published collection's dances.
@immutable
class PublishedCollectionImportResult {
  const PublishedCollectionImportResult({
    required this.session,
    required this.metadata,
    required this.importedAt,
  });

  final ImportSession session;
  final PublishedCollectionMetadata metadata;
  final DateTime importedAt;

  CollectionImportEvent get event => CollectionImportEvent(
    collectionId: metadata.collectionId,
    version: metadata.collectionVersion,
    archiveDigest: metadata.archiveDigest,
    importedAt: importedAt,
  );
}

/// Coordinates strict published-collection planning and the shared dance commit.
class PublishedCollectionImporter {
  PublishedCollectionImporter(this._pipeline);

  final ImportPipeline _pipeline;

  Future<ImportBatchResult> plan(
    String archiveJson,
    PublishedCollectionMetadata metadata,
  ) => _pipeline.plan(
    PublishedCollectionAdapter(metadata),
    ImportRequest(payload: archiveJson),
  );

  Future<PublishedCollectionImportResult> commit(
    ImportBatchResult batch, {
    required PublishedCollectionMetadata metadata,
    required DateTime now,
    String Function()? newId,
    Map<int, DedupeResolution> resolutions = const {},
  }) async {
    final session = await _pipeline.commit(
      batch,
      now: now,
      newId: newId ?? uuidV4,
      resolutions: resolutions,
    );
    return PublishedCollectionImportResult(
      session: session,
      metadata: metadata,
      importedAt: now,
    );
  }
}
