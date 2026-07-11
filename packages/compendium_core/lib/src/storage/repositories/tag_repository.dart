import 'package:drift/drift.dart';

import '../../model/tag.dart';
import '../database.dart';

/// CRUD for flat [Tag] rows.
class TagRepository {
  TagRepository(this._db);

  final CompendiumDatabase _db;

  Future<void> upsert(Tag tag) => _db
      .into(_db.tags)
      .insertOnConflictUpdate(
        TagsCompanion.insert(
          id: tag.id,
          name: tag.name,
          color: Value(tag.color),
        ),
      );

  Future<Tag?> getById(String id) async {
    final row = await (_db.select(
      _db.tags,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<List<Tag>> listAll() async {
    final rows = await (_db.select(
      _db.tags,
    )..orderBy([(t) => OrderingTerm(expression: t.name)])).get();
    return rows.map(_toModel).toList();
  }

  /// Deletes the tag; `dance_tags` rows cascade automatically (FK).
  Future<void> delete(String id) =>
      (_db.delete(_db.tags)..where((t) => t.id.equals(id))).go();

  Tag _toModel(TagRow row) => Tag(id: row.id, name: row.name, color: row.color);
}
