import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../model/tag.dart';
import '../../sync/sync_record_kind.dart';
import '../../util/argb.dart';
import '../database.dart';
import '../existence.dart';
import '../shareable_text.dart';
import 'sync_local_repository.dart';

/// CRUD for flat [Tag] rows.
///
/// Colours are normalized on the way in and out ([normalizeArgb]), so
/// `tags.color` holds either `null` — "no colour assigned" — or a fully opaque
/// 32-bit ARGB int, and never a value that would paint an invisible chip
/// (issue #786). This is the single write choke point for tags: the editor, the
/// batch dialog, and archive restore all go through [upsert].
///
/// Tags are **soft-deleted** as of schema v25 (issue #898): [delete] used to
/// rely purely on the `dance_tags` FK cascade to unlink the tag from every
/// dance. A tombstone fires no cascade, so those join rows now outlive the
/// delete — deliberately, so a revived tag keeps its dances — and every read
/// that reaches a tag through `dance_tags` filters on `deleted_at IS NULL`
/// instead.
///
/// The ordinary tombstoning [delete] is the one converted kind's delete with no
/// referential guard, which is safe precisely because it strands nothing. Its
/// `permanent` branch is a different matter and **is** guarded as of issue
/// #1357: that branch erases, and the FK cascade then strips the tag from every
/// dance holding it, live ones included. See [delete].
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
  Future<String> upsert(Tag tag, {DateTime? at}) =>
      _write(tag, at: at, fromSync: false);

  /// Applies a validated inbound sync record.
  ///
  /// §6.7 keeps the inbound write off the editor's path. Concretely this
  /// skips three behaviours that exist for a person editing a record and
  /// are wrong for a peer's: it does not adopt a tombstoned row's identity
  /// (identity is reconciliation's decision, and silently relocating the
  /// record would store it under an id the peer never named), it does not
  /// substitute the local name when another row holds the incoming one
  /// (§6.7 refuses a record rather than storing an altered copy), and it does
  /// not seed `existence_at`, which the envelope owns.
  Future<void> writeFromSync(Tag tag, {DateTime? at}) async {
    final _ = await _write(tag, at: at, fromSync: true);
  }

  Future<String> _write(
    Tag tag, {
    required DateTime? at,
    required bool fromSync,
  }) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      final name = normalizeShareableText(tag.name);
      final incumbent = await (_db.select(
        _db.tags,
      )..where((t) => t.name.equals(name))).getSingleOrNull();
      final current = await (_db.select(
        _db.tags,
      )..where((t) => t.id.equals(tag.id))).getSingleOrNull();
      final collidingEdit =
          !fromSync &&
          current != null &&
          incumbent != null &&
          incumbent.id != tag.id;
      if (fromSync && incumbent != null && incumbent.id != tag.id) {
        // Refuse rather than guess: reconciliation owns natural-key
        // identity, so reaching the writer with the key held by another
        // row means the record must be reported, not altered to fit.
        throw StateError(
          'inbound tag "${tag.id}" wants a name held by '
          '"${incumbent.id}"',
        );
      }
      final id = (collidingEdit || fromSync)
          ? tag.id
          : await adoptTombstonedNaturalKey(
                  _db,
                  table: _db.tags,
                  keyColumn: 'id',
                  naturalKeyColumn: 'name',
                  naturalKey: name,
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
              name: collidingEdit
                  ? current.name
                  : normalizeShareableText(tag.name),
              color: Value(normalizeArgb(tag.color)),
              updatedAt: Value(now),
            ),
          );
      if (collidingEdit) {
        await recordNormalisationSkip(
          _db,
          table: 'tags',
          column: 'name',
          recordId: tag.id,
        );
      }
      if (!fromSync) {
        await applyUpsertExistence(
          _db,
          table: _db.tags,
          keyColumn: 'id',
          key: id,
          at: now,
        );
      }
      return id;
    });
  }

  /// Commits a tag staged by a dance editor or batch operation.
  ///
  /// A live natural-key match is reused without changing its identity. A
  /// tombstoned match is passed to [upsert], which revives it and returns the
  /// adopted id. This keeps provisional ids out of dance-tag joins in both
  /// cases.
  @useResult
  Future<String> upsertStaged(Tag tag, {DateTime? at}) async {
    final live = await idByName(tag.name);
    if (live != null) return live;

    final existingId = await idByName(tag.name, includeDeleted: true);
    if (existingId == null) return upsert(tag, at: at);

    // Preserve the incumbent's spelling so a legacy case-only duplicate is
    // adopted through the existing exact-key path. A different staged ID is
    // a new entity, so adoption must clear the tombstone's retained joins;
    // retrying the incumbent ID remains a revival and keeps them.
    final existing = await (_db.select(
      _db.tags,
    )..where((t) => t.id.equals(existingId))).getSingle();
    if (tag.id == existing.id) {
      return upsert(
        Tag(id: existing.id, name: existing.name, color: tag.color),
        at: at,
      );
    }
    return upsert(
      Tag(id: tag.id, name: existing.name, color: tag.color),
      at: at,
    );
  }

  /// Returns the existing id for [name], including tombstoned rows when
  /// [includeDeleted] is true. Matching is case-insensitive for compatibility
  /// with legacy case-only duplicates; live rows win, then the smallest id.
  Future<String?> idByName(String name, {bool includeDeleted = false}) async {
    final normalized = normalizeShareableText(name);
    final rows =
        await (_db.select(_db.tags)..where(
              (t) =>
                  includeDeleted ? const Constant(true) : t.deletedAt.isNull(),
            ))
            .get();
    final matches =
        rows
            .where((row) => row.name.toLowerCase() == normalized.toLowerCase())
            .toList()
          ..sort((a, b) {
            if (includeDeleted) {
              final deletedOrder = (a.deletedAt != null ? 1 : 0).compareTo(
                b.deletedAt != null ? 1 : 0,
              );
              if (deletedOrder != 0) return deletedOrder;
            }
            return a.id.compareTo(b.id);
          });
    return matches.isEmpty ? null : matches.first.id;
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

  /// Returns live tags that are attached to at least one non-deleted dance.
  ///
  /// This is intentionally narrower than [listAll]: standalone tags remain
  /// available to administrative surfaces, while pickers that attach tags to
  /// dances should not offer rows that have no live dance reference.
  Future<List<Tag>> listReferencedByLiveDances() async {
    final rows =
        await (_db.select(_db.tags).join([
                innerJoin(
                  _db.danceTags,
                  _db.danceTags.tagId.equalsExp(_db.tags.id),
                ),
                innerJoin(
                  _db.dances,
                  _db.dances.id.equalsExp(_db.danceTags.danceId) &
                      _db.dances.deletedAt.isNull(),
                ),
              ])
              ..where(_db.tags.deletedAt.isNull())
              ..orderBy([
                OrderingTerm(expression: _db.tags.name),
                OrderingTerm(expression: _db.tags.id),
              ]))
            .get();
    final unique = <String, Tag>{};
    for (final row in rows) {
      final tag = _toModel(row.readTable(_db.tags));
      unique[tag.id] = tag;
    }
    return unique.values.toList();
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
  ///
  /// The default (tombstone) path is deliberately **unguarded** — it is what
  /// the tag manager calls, and a tombstone strands nothing. The [permanent]
  /// path is guarded, because it erases: `dance_tags.tag_id` is
  /// `ON DELETE CASCADE` (`tables.dart`), so erasing a referenced tag strips it
  /// from the referencing dances with no error at all. Until issue #1357 this
  /// hatch had no check of any kind — the only sibling in that state — and was
  /// held closed solely by its one caller's `isInUse` read, which sits outside
  /// the delete's transaction and is therefore check-then-act.
  ///
  /// The guard matches `ChoreographerRepository.delete`'s, which is the shape
  /// every cascading parent now uses:
  ///
  /// * a **live** dance holding the tag throws a [StateError] (sync-spec §3.1:
  ///   "refuse to hard-delete an entity still referenced by a live record"),
  ///   because the tag must stay live for that dance to keep showing it;
  /// * a **tombstoned** dance's `dance_tags` row downgrades the erase to a
  ///   tombstone, so the association survives for the dance's restore instead
  ///   of cascading away;
  /// * an unreferenced tag is erased, or tombstoned if already published.
  Future<void> delete(String id, {DateTime? at, bool permanent = false}) =>
      _db.transaction(() async {
        if (permanent) {
          final liveUses =
              await (_db.select(_db.danceTags).join([
                    innerJoin(
                      _db.dances,
                      _db.dances.id.equalsExp(_db.danceTags.danceId),
                    ),
                  ])..where(
                    _db.danceTags.tagId.equals(id) &
                        _db.dances.deletedAt.isNull(),
                  ))
                  .get();
          if (liveUses.isNotEmpty) {
            throw StateError(
              'cannot delete tag "$id": still applied to '
              '${liveUses.length} dance(s)',
            );
          }
          // Any surviving `dance_tags` row — necessarily a tombstoned dance's,
          // since a live one threw above — downgrades the erase to a tombstone.
          final taggedBySurvivor =
              await (_db.select(_db.danceTags)
                    ..where((t) => t.tagId.equals(id))
                    ..limit(1))
                  .getSingleOrNull() !=
              null;
          if (taggedBySurvivor ||
              await isPublishedSyncRecord(
                _db,
                kind: SyncRecordKind.tag,
                recordId: id,
              )) {
            await stampExistenceTransition(
              _db,
              table: _db.tags,
              keyColumn: 'id',
              key: id,
              at: resolveStamp(at),
              deleted: true,
            );
            return;
          }
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
      });

  Future<void> restore(
    String id, {
    required DateTime at,
    bool clearPending = true,
  }) => _db.transaction(() async {
    await stampExistenceTransition(
      _db,
      table: _db.tags,
      keyColumn: 'id',
      key: id,
      at: at,
      deleted: false,
    );
    if (clearPending) {
      await clearPendingSyncDeletion(
        _db,
        kind: SyncRecordKind.tag,
        recordId: id,
      );
    }
  });

  /// Erases the unpublished, unreferenced tags [ids], for reverting a
  /// just-committed import (`ShareMetadataImporter.undo`).
  ///
  /// Delegates to [delete], so it inherits that method's `permanent` guard in
  /// full: a tag a **live** dance still holds throws a [StateError] (which
  /// abandons the whole batch — callers revert per id, or catch and continue),
  /// a tag only a tombstoned dance holds is tombstoned, and a published tag is
  /// tombstoned. Unlike `VenueRepository.hardDelete` this is not a
  /// batch-at-a-time query; the tag lists it is called with are single-import
  /// sized.
  Future<void> hardDelete(Iterable<String> ids) => _db.transaction(() async {
    for (final id in ids) {
      await delete(id, permanent: true);
    }
  });

  /// Reads a row back, re-normalizing the stored colour so a row written by an
  /// older build or a corrupted file cannot paint an invisible chip.
  Tag _toModel(TagRow row) =>
      Tag(id: row.id, name: row.name, color: normalizeArgb(row.color));
}
