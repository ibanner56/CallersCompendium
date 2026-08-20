import 'package:meta/meta.dart';

/// A durable record that a published collection version was imported.
///
/// This is intentionally separate from dance provenance: the event remains
/// useful after the user deletes some or all of the imported dances.
@immutable
class CollectionImportEvent {
  const CollectionImportEvent({
    required this.collectionId,
    required this.version,
    required this.archiveDigest,
    required this.importedAt,
  });

  final String collectionId;
  final String version;
  final String archiveDigest;
  final DateTime importedAt;

  @override
  bool operator ==(Object other) =>
      other is CollectionImportEvent &&
      other.collectionId == collectionId &&
      other.version == version &&
      other.archiveDigest == archiveDigest &&
      other.importedAt == importedAt;

  @override
  int get hashCode =>
      Object.hash(collectionId, version, archiveDigest, importedAt);
}
