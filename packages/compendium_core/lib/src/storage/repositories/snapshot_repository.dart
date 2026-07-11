import 'package:meta/meta.dart';

import '../database.dart';
import '../utc_datetime.dart';

/// Tracks the last-imported snapshot for an external source (e.g. a hosted
/// CallersBox archive or ContraDB export), so the app can offer "update
/// available" prompts without re-fetching the source. Not part of the core
/// domain model (`Dance`, `Program`, ...) — this is storage/import
/// bookkeeping only.
@immutable
class SnapshotRecord {
  const SnapshotRecord({
    required this.source,
    required this.snapshotDate,
    required this.manifestJson,
    required this.importedAt,
  });

  /// Stable source identifier (e.g. `callersbox`, `contradb`).
  final String source;

  /// The snapshot's own version/date, as published by the source.
  final DateTime snapshotDate;

  /// Raw JSON manifest as fetched (file list, checksums, counts, ...).
  final String manifestJson;

  /// When this snapshot was imported locally.
  final DateTime importedAt;

  @override
  bool operator ==(Object other) =>
      other is SnapshotRecord &&
      other.source == source &&
      other.snapshotDate == snapshotDate &&
      other.manifestJson == manifestJson &&
      other.importedAt == importedAt;

  @override
  int get hashCode =>
      Object.hash(source, snapshotDate, manifestJson, importedAt);
}

/// CRUD for [SnapshotRecord]s, one row per external source.
class SnapshotRepository {
  SnapshotRepository(this._db);

  final CompendiumDatabase _db;

  Future<void> upsert(SnapshotRecord snapshot) {
    assertUtc(snapshot.snapshotDate, 'snapshot.snapshotDate');
    assertUtc(snapshot.importedAt, 'snapshot.importedAt');
    return _db
        .into(_db.snapshots)
        .insertOnConflictUpdate(
          SnapshotsCompanion.insert(
            source: snapshot.source,
            snapshotDate: snapshot.snapshotDate,
            manifestJson: snapshot.manifestJson,
            importedAt: snapshot.importedAt,
          ),
        );
  }

  Future<SnapshotRecord?> getBySource(String source) async {
    final row = await (_db.select(
      _db.snapshots,
    )..where((t) => t.source.equals(source))).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<List<SnapshotRecord>> listAll() async {
    final rows = await _db.select(_db.snapshots).get();
    return rows.map(_toModel).toList();
  }

  Future<void> delete(String source) =>
      (_db.delete(_db.snapshots)..where((t) => t.source.equals(source))).go();

  SnapshotRecord _toModel(SnapshotRow row) => SnapshotRecord(
    source: row.source,
    snapshotDate: asUtc(row.snapshotDate),
    manifestJson: row.manifestJson,
    importedAt: asUtc(row.importedAt),
  );
}
