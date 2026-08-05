import 'package:drift/drift.dart';

import '../../model/tag.dart';
import '../../util/argb.dart';
import '../database.dart';

/// CRUD for flat [Tag] rows.
///
/// Colours are normalized on the way in and out ([normalizeArgb]), so
/// `tags.color` holds either `null` — "no colour assigned" — or a fully opaque
/// 32-bit ARGB int, and never a value that would paint an invisible chip
/// (issue #786). This is the single write choke point for tags: the editor, the
/// batch dialog, and archive restore all go through [upsert].
class TagRepository {
  TagRepository(this._db);

  final CompendiumDatabase _db;

  Future<void> upsert(Tag tag) => _db
      .into(_db.tags)
      .insertOnConflictUpdate(
        TagsCompanion.insert(
          id: tag.id,
          name: tag.name,
          color: Value(normalizeArgb(tag.color)),
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

  /// Reads a row back, re-normalizing the stored colour so a row written by an
  /// older build or a corrupted file cannot paint an invisible chip.
  Tag _toModel(TagRow row) =>
      Tag(id: row.id, name: row.name, color: normalizeArgb(row.color));
}
