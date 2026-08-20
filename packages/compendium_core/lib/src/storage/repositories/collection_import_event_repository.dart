import 'package:drift/drift.dart';

import '../../model/collection_import_event.dart';
import '../../model/enums.dart';
import '../database.dart';
import '../utc_datetime.dart';

/// Durable history of published collection imports.
class CollectionImportEventRepository {
  CollectionImportEventRepository(this._db);

  final CompendiumDatabase _db;

  /// Records an import idempotently by `(collectionId, version)`.
  Future<void> record(CollectionImportEvent event) async {
    assertUtc(event.importedAt, 'collectionImportEvent.importedAt');
    await _db
        .into(_db.collectionImportEvents)
        .insertOnConflictUpdate(
          CollectionImportEventsCompanion.insert(
            collectionId: event.collectionId,
            version: event.version,
            archiveDigest: event.archiveDigest,
            importedAt: event.importedAt,
          ),
        );
  }

  Future<List<CollectionImportEvent>> listAll() async {
    final rows = await (_db.select(
      _db.collectionImportEvents,
    )..orderBy([(t) => OrderingTerm(expression: t.importedAt)])).get();
    return [for (final row in rows) _toModel(row)];
  }

  Future<bool> contains(String collectionId, String version) async {
    final row =
        await (_db.select(_db.collectionImportEvents)..where(
              (t) =>
                  t.collectionId.equals(collectionId) &
                  t.version.equals(version),
            ))
            .getSingleOrNull();
    return row != null;
  }

  /// Counts the published dances from [collectionId] still held locally.
  ///
  /// When [version] is supplied, only that manifest version is counted.
  /// Filtering the collection prefix in Dart avoids treating a collection id
  /// containing SQL wildcard characters as a pattern.
  Future<int> heldCount(String collectionId, {String? version}) async {
    final rows =
        await (_db.select(_db.provenance)..where(
              (t) =>
                  t.source.equals(ProvenanceSource.publishedCollection.name) &
                  (version == null
                      ? const Constant(true)
                      : t.sourceVersion.equals(version)),
            ))
            .get();
    final prefix = '$collectionId/';
    return rows
        .where((row) => row.externalId?.startsWith(prefix) ?? false)
        .length;
  }

  CollectionImportEvent _toModel(CollectionImportEventRow row) =>
      CollectionImportEvent(
        collectionId: row.collectionId,
        version: row.version,
        archiveDigest: row.archiveDigest,
        importedAt: row.importedAt,
      );
}
