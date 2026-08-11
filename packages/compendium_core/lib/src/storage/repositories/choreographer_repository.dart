import 'package:drift/drift.dart';

import '../../model/choreographer.dart';
import '../database.dart';
import '../existence.dart';

/// CRUD for [Choreographer] rows. "Traditional"/"Unknown" are real rows the
/// app seeds on first launch, not magic sentinel values — this repository
/// treats them like any other choreographer.
///
/// Choreographers are **soft-deleted** as of schema v25 (issue #898).
class ChoreographerRepository {
  ChoreographerRepository(this._db);

  final CompendiumDatabase _db;

  /// Writes [c], reviving it if a tombstone holds its UNIQUE name. See
  /// `TagRepository.upsert` for why clearing `deleted_at` is what makes
  /// re-creating a deleted entity work at all.
  /// Returns the id the choreographer actually occupies — see
  /// `TagRepository.upsert` on natural-key adoption.
  Future<String> upsert(Choreographer c, {DateTime? at}) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      final id =
          await adoptTombstonedNaturalKey(
            _db,
            table: 'choreographers',
            keyColumn: 'id',
            naturalKeyColumn: 'name',
            naturalKey: c.name,
            incomingId: c.id,
            joinTable: 'dance_authors',
            joinColumn: 'choreographer_id',
          ) ??
          c.id;
      await _db
          .into(_db.choreographers)
          .insertOnConflictUpdate(
            ChoreographersCompanion.insert(
              id: id,
              name: c.name,
              website: Value(c.website),
              notes: Value(c.notes),
              email: Value(c.email),
              location: Value(c.location),
              deceased: Value(c.deceased),
              updatedAt: Value(now),
            ),
          );
      await applyUpsertExistence(
        _db,
        table: 'choreographers',
        keyColumn: 'id',
        key: id,
        at: now,
      );
      return id;
    });
  }

  Future<Choreographer?> getById(String id) async {
    final row = await (_db.select(
      _db.choreographers,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<List<Choreographer>> listAll() async {
    final rows =
        await (_db.select(_db.choreographers)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm(expression: t.name)]))
            .get();
    return rows.map(_toModel).toList();
  }

  /// Throws if [id] is still referenced by any `dance_authors` row — callers
  /// should reassign or remove authorship first (deleting a choreographer
  /// silently orphaning credited dances would be a silent data loss bug). The
  /// "still credited?" check and the delete run inside a single transaction
  /// so no dance can acquire a reference between the check and the delete (no
  /// check-then-act race). Mirrors `VenueRepository.delete`.
  ///
  /// Tombstones by default (schema v25, issue #898). The guard is **kept**:
  /// soft delete does not make it safe to remove an entity a live record still
  /// references, and a tombstone for a still-credited author could not be
  /// applied by a peer anyway.
  ///
  /// [permanent] hard-deletes instead, for rolling back a just-committed
  /// import (`ImportPipeline.undo`). A rollback must leave nothing behind: the
  /// import is being erased, so a tombstone would advertise the deletion of an
  /// entity that, as far as every other device is concerned, never existed.
  /// This mirrors `DanceRepository.hardDelete` / `VenueRepository.hardDelete`,
  /// which are hard deletes on kinds that have had soft delete for far longer.
  /// The guard applies either way.
  Future<void> delete(String id, {DateTime? at, bool permanent = false}) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      final stillUsed = await (_db.select(
        _db.danceAuthors,
      )..where((t) => t.choreographerId.equals(id))).get();
      if (stillUsed.isNotEmpty) {
        throw StateError(
          'cannot delete choreographer "$id": still credited on '
          '${stillUsed.length} dance(s)',
        );
      }
      if (permanent) {
        await (_db.delete(
          _db.choreographers,
        )..where((t) => t.id.equals(id))).go();
        return;
      }
      await stampExistenceTransition(
        _db,
        table: 'choreographers',
        keyColumn: 'id',
        key: id,
        at: now,
        deleted: true,
      );
    });
  }

  Choreographer _toModel(ChoreographerRow row) => Choreographer(
    id: row.id,
    name: row.name,
    website: row.website,
    notes: row.notes,
    email: row.email,
    location: row.location,
    deceased: row.deceased,
  );
}
