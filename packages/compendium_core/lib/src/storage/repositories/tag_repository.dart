import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../model/tag.dart';
import '../../util/argb.dart';
import '../database.dart';
import '../existence.dart';

/// CRUD for flat [Tag] rows.
///
/// Colours are normalized on the way in and out ([normalizeArgb]), so
/// `tags.color` holds either `null` — "no colour assigned" — or a fully opaque
/// 32-bit ARGB int, and never a value that would paint an invisible chip
/// (issue #786). This is the single write choke point for tags: the editor, the
/// batch dialog, and archive restore all go through [upsert].
///
/// Tags are **soft-deleted** as of schema v25 (issue #898), and are the one
/// converted kind with no referential guard: [delete] used to rely purely on
/// the `dance_tags` FK cascade to unlink the tag from every dance. A tombstone
/// fires no cascade, so those join rows now outlive the delete — deliberately,
/// so a revived tag keeps its dances — and every read that reaches a tag
/// through `dance_tags` filters on `deleted_at IS NULL` instead.
class TagRepository {
  TagRepository(this._db);

  final CompendiumDatabase _db;

  /// Writes [tag], reviving it if a tombstone is in the way.
  ///
  /// `tags.name` is UNIQUE, so a tag deleted and then re-created under the same
  /// name lands on the tombstoned row rather than inserting beside it. Clearing
  /// `deleted_at` here is what makes that re-creation work at all: drift emits
  /// an *untargeted* `ON CONFLICT DO UPDATE`, which updates every column the
  /// companion mentions and leaves the rest alone — so without this the new tag
  /// would be written onto the tombstone, keep its `deleted_at`, and simply
  /// never appear.
  /// Returns the id the tag actually occupies, which differs from [Tag.id]
  /// only when a tombstoned tag already held this UNIQUE name and was adopted
  /// (see [adoptTombstonedNaturalKey]). Callers minting a fresh UUID must use
  /// the returned id rather than the one they generated, or they will reference
  /// a row that does not exist.
  @useResult
  Future<String> upsert(Tag tag, {DateTime? at}) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      final id =
          await adoptTombstonedNaturalKey(
            _db,
            table: _db.tags,
            keyColumn: 'id',
            naturalKeyColumn: 'name',
            naturalKey: tag.name,
            incomingId: tag.id,
            joinTable: _db.danceTags,
            joinColumn: 'tag_id',
          ) ??
          tag.id;
      await _db
          .into(_db.tags)
          .insertOnConflictUpdate(
            TagsCompanion.insert(
              id: id,
              name: tag.name,
              color: Value(normalizeArgb(tag.color)),
              updatedAt: Value(now),
            ),
          );
      await applyUpsertExistence(
        _db,
        table: _db.tags,
        keyColumn: 'id',
        key: id,
        at: now,
      );
      return id;
    });
  }

  Future<Tag?> getById(String id) async {
    final row = await (_db.select(
      _db.tags,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<List<Tag>> listAll() async {
    final rows =
        await (_db.select(_db.tags)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm(expression: t.name)]))
            .get();
    return rows.map(_toModel).toList();
  }

  Future<List<({Tag tag, bool deleted})>> listAllWithDeleted() async {
    final rows = await (_db.select(
      _db.tags,
    )..orderBy([(t) => OrderingTerm(expression: t.name)])).get();
    return [
      for (final row in rows)
        (tag: _toModel(row), deleted: row.deletedAt != null),
    ];
  }

  /// Returns whether any dance still references [id].
  Future<bool> isInUse(String id) async {
    final row =
        await (_db.select(_db.danceTags)
              ..where((t) => t.tagId.equals(id))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// [listAll] as a live stream: the current tags immediately, then again after
  /// every write that changes them (issue #768).
  ///
  /// Uses the query builder rather than a sentinel `customSelect` with an
  /// explicit `readsFrom`, because [listAll] is a single `select(tags)` with no
  /// Dart fan-out — drift infers `{tags}`, which is the whole read set. See
  /// `VenueRepository.watchAll` for why that differs from the program list, and
  /// for what would invalidate it.
  ///
  /// Note this covers colour edits as well as add/remove: a colour lives in the
  /// tag row, so `upsert` touches this table and a subscriber hears about it.
  Stream<List<Tag>> watchAll() =>
      (_db.select(_db.tags)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .watch()
          .map((rows) => rows.map(_toModel).toList());

  /// Tombstones the tag. Its `dance_tags` rows are deliberately **left in
  /// place**: hard delete used to clear them by FK cascade, but doing that here
  /// would mean a revived tag came back untagged, silently losing every
  /// association. Reads filter the tag out instead, so the dances stop showing
  /// it either way.
  Future<void> delete(String id, {DateTime? at, bool permanent = false}) async {
    if (permanent) {
      await (_db.delete(_db.tags)..where((t) => t.id.equals(id))).go();
      return;
    }
    await stampExistenceTransition(
      _db,
      table: _db.tags,
      keyColumn: 'id',
      key: id,
      at: resolveStamp(at),
      deleted: true,
    );
  }

  Future<void> restore(String id, {required DateTime at}) =>
      stampExistenceTransition(
        _db,
        table: _db.tags,
        keyColumn: 'id',
        key: id,
        at: at,
        deleted: false,
      );

  Future<void> hardDelete(Iterable<String> ids) async {
    for (final id in ids) {
      await delete(id, permanent: true);
    }
  }

  /// Reads a row back, re-normalizing the stored colour so a row written by an
  /// older build or a corrupted file cannot paint an invisible chip.
  Tag _toModel(TagRow row) =>
      Tag(id: row.id, name: row.name, color: normalizeArgb(row.color));
}
