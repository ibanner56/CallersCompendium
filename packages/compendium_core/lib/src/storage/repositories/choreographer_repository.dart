import 'package:drift/drift.dart';

import '../../model/choreographer.dart';
import '../database.dart';

/// CRUD for [Choreographer] rows. "Traditional"/"Unknown" are real rows the
/// app seeds on first launch, not magic sentinel values — this repository
/// treats them like any other choreographer.
class ChoreographerRepository {
  ChoreographerRepository(this._db);

  final CompendiumDatabase _db;

  Future<void> upsert(Choreographer c) => _db
      .into(_db.choreographers)
      .insertOnConflictUpdate(
        ChoreographersCompanion.insert(
          id: c.id,
          name: c.name,
          website: Value(c.website),
          notes: Value(c.notes),
          email: Value(c.email),
          location: Value(c.location),
          deceased: Value(c.deceased),
        ),
      );

  Future<Choreographer?> getById(String id) async {
    final row = await (_db.select(
      _db.choreographers,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<List<Choreographer>> listAll() async {
    final rows = await (_db.select(
      _db.choreographers,
    )..orderBy([(t) => OrderingTerm(expression: t.name)])).get();
    return rows.map(_toModel).toList();
  }

  /// Throws if [id] is still referenced by any `dance_authors` row — callers
  /// should reassign or remove authorship first (deleting a choreographer
  /// silently orphaning credited dances would be a silent data loss bug).
  Future<void> delete(String id) async {
    final stillUsed = await (_db.select(
      _db.danceAuthors,
    )..where((t) => t.choreographerId.equals(id))).get();
    if (stillUsed.isNotEmpty) {
      throw StateError(
        'cannot delete choreographer "$id": still credited on '
        '${stillUsed.length} dance(s)',
      );
    }
    await (_db.delete(_db.choreographers)..where((t) => t.id.equals(id))).go();
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
