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
    await _db.transaction(() async {
      await _db
          .into(_db.collectionImportEvents)
          .insert(
            CollectionImportEventsCompanion.insert(
              collectionId: event.collectionId,
              version: event.version,
              archiveDigest: event.archiveDigest,
              importedAt: event.importedAt,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      final existing =
          await (_db.select(_db.collectionImportEvents)..where(
                (t) =>
                    t.collectionId.equals(event.collectionId) &
                    t.version.equals(event.version),
              ))
              .getSingle();
      if (existing.archiveDigest != event.archiveDigest) {
        throw StateError(
          'collection import event digest conflict for '
          '${event.collectionId}/${event.version}',
        );
      }
    });
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
  /// The prefix comparison is performed with SQLite `substr`, so collection
  /// identifiers containing SQL wildcard characters remain literal values.
  Future<int> heldCount(String collectionId, {String? version}) async {
    final prefix = '$collectionId/';
    final count = _db.provenance.danceId.count();
    return (_db.selectOnly(_db.provenance)
          ..addColumns([count])
          ..where(
            _db.provenance.source.equals(
                  ProvenanceSource.publishedCollection.name,
                ) &
                (version == null
                    ? const Constant(true)
                    : _db.provenance.sourceVersion.equals(version)) &
                _db.provenance.externalId
                    .substr(1, prefix.length)
                    .equals(prefix),
          ))
        .map((row) => row.read(count) ?? 0)
        .getSingle();
  }

  CollectionImportEvent _toModel(CollectionImportEventRow row) =>
      CollectionImportEvent(
        collectionId: row.collectionId,
        version: row.version,
        archiveDigest: row.archiveDigest,
        importedAt: row.importedAt,
      );
}
