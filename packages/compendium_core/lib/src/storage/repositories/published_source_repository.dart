import 'package:drift/drift.dart';

import '../../model/published_source.dart';
import '../../sync/sync_record_kind.dart';
import '../database.dart';
import '../existence.dart';
import '../shareable_text.dart';
import 'sync_local_repository.dart';

/// CRUD for [PublishedSource] rows — the reusable bibliographic entity many
/// dances cite. Mirrors `ChoreographerRepository`: editing a source's metadata
/// happens in one place and a delete is guarded while the source is still
/// referenced by any dance citation.
///
/// Published sources are **soft-deleted** as of schema v25 (issue #898). They
/// carry no UNIQUE natural key, so an upsert can only ever land on the row
/// sharing its id.
class PublishedSourceRepository {
  PublishedSourceRepository(this._db);

  final CompendiumDatabase _db;

  ///
  /// Pass `localUserEdit: true` only when the person using the app deliberately
  /// edited this record: that cancels a peer's pending tombstone for it
  /// (sync-spec §6.8, [cancelPendingSyncDeletionForLocalEdit]). It defaults to
  /// false because imports, archive restore and automatic writes share this
  /// method, and a cancellation they did not intend reverses a peer's deletion.
  Future<void> upsert(
    PublishedSource s, {
    DateTime? at,
    bool localUserEdit = false,
  }) => _write(s, at: at, fromSync: false, localUserEdit: localUserEdit);

  /// Applies a validated inbound sync record.
  ///
  /// Separate from [upsert] so the interactive path can gain behaviour without
  /// silently changing what an inbound apply does — §6.7 requires the sync
  /// write never to travel through the editor's path. Today the only
  /// difference is existence seeding: the envelope owns `existence_at`, which
  /// `_restoreTimestamps` writes straight after this returns.
  Future<void> writeFromSync(PublishedSource s, {DateTime? at}) =>
      _write(s, at: at, fromSync: true, localUserEdit: false);

  Future<void> _write(
    PublishedSource s, {
    required DateTime? at,
    required bool fromSync,
    required bool localUserEdit,
  }) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      await _db
          .into(_db.publishedSources)
          .insertOnConflictUpdate(
            PublishedSourcesCompanion.insert(
              id: s.id,
              title: normalizeShareableText(s.title),
              author: Value(
                s.author == null ? null : normalizeShareableText(s.author!),
              ),
              year: Value(s.year),
              url: Value(s.url == null ? null : normalizeShareableText(s.url!)),
              notes: Value(
                s.notes == null ? null : normalizeShareableText(s.notes!),
              ),
              updatedAt: Value(now),
            ),
          );
      if (!fromSync) {
        await applyUpsertExistence(
          _db,
          table: _db.publishedSources,
          keyColumn: 'id',
          key: s.id,
          at: now,
        );
      }
    });
  }

  Future<PublishedSource?> getById(String id) async {
    final row = await (_db.select(
      _db.publishedSources,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<List<PublishedSource>> listAll() async {
    final rows =
        await (_db.select(_db.publishedSources)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([
                (t) =>
                    OrderingTerm(expression: t.title.collate(Collate.noCase)),
              ]))
            .get();
    return rows.map(_toModel).toList();
  }

  Future<List<({PublishedSource source, bool deleted})>>
  listAllWithDeleted() async {
    final rows =
        await (_db.select(_db.publishedSources)..orderBy([
              (t) => OrderingTerm(expression: t.title.collate(Collate.noCase)),
            ]))
            .get();
    return [
      for (final row in rows)
        (source: _toModel(row), deleted: row.deletedAt != null),
    ];
  }

  /// Throws if [id] is still referenced by any `dance_sources` row — callers
  /// must remove the citing dances' citations first (deleting a source out
  /// from under citing dances would be a silent data-loss bug). The "still
  /// cited?" check and the delete run inside a single transaction so no
  /// dance can acquire a citation between the check and the delete (no
  /// check-then-act race). Mirrors `VenueRepository.delete` /
  /// `ChoreographerRepository.delete`.
  ///
  /// Tombstones by default (schema v25, issue #898); the guard is kept.
  /// [permanent] removes unpublished rows for rollback, while published rows
  /// are tombstoned so peers retain deletion evidence.
  ///
  /// [permanent] also **tombstones rather than erases** whenever any
  /// `dance_sources` row still cites this source — the case the live guard
  /// below lets through because every such dance is itself tombstoned (issue
  /// #1357). `dance_sources` is `ON DELETE CASCADE`, so erasing here would take
  /// the tombstoned dance's citation with it and restoring that dance would
  /// bring it back uncited. See `ChoreographerRepository.delete` for the full
  /// reasoning.
  Future<void> delete(String id, {DateTime? at, bool permanent = false}) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      // Live dances only; a soft-deleted dance keeps its `dance_sources` rows
      // because the tombstone fires no FK cascade. See the note in
      // `ChoreographerRepository.delete`.
      final stillUsed =
          await (_db.select(_db.danceSources).join([
                innerJoin(
                  _db.dances,
                  _db.dances.id.equalsExp(_db.danceSources.danceId),
                ),
              ])..where(
                _db.danceSources.sourceId.equals(id) &
                    _db.dances.deletedAt.isNull(),
              ))
              .get();
      if (stillUsed.isNotEmpty) {
        throw StateError(
          'cannot delete published source "$id": still cited by '
          '${stillUsed.length} dance(s)',
        );
      }

      if (permanent) {
        // Any surviving `dance_sources` row — necessarily a tombstoned dance's,
        // since a live one threw above — downgrades the erase to a tombstone
        // rather than cascading that citation away (issue #1357).
        final citedBySurvivor =
            await (_db.select(_db.danceSources)
                  ..where((t) => t.sourceId.equals(id))
                  ..limit(1))
                .getSingleOrNull() !=
            null;
        if (citedBySurvivor ||
            await isPublishedSyncRecord(
              _db,
              kind: SyncRecordKind.publishedSource,
              recordId: id,
            )) {
          await stampExistenceTransition(
            _db,
            table: _db.publishedSources,
            keyColumn: 'id',
            key: id,
            at: now,
            deleted: true,
          );
          return;
        }
        await (_db.delete(
          _db.publishedSources,
        )..where((t) => t.id.equals(id))).go();
        return;
      }
      await stampExistenceTransition(
        _db,
        table: _db.publishedSources,
        keyColumn: 'id',
        key: id,
        at: now,
        deleted: true,
      );
    });
  }

  Future<void> restore(
    String id, {
    required DateTime at,
    bool clearPending = true,
  }) => _db.transaction(() async {
    await stampExistenceTransition(
      _db,
      table: _db.publishedSources,
      keyColumn: 'id',
      key: id,
      at: at,
      deleted: false,
    );
    if (clearPending) {
      await clearPendingSyncDeletion(
        _db,
        kind: SyncRecordKind.publishedSource,
        recordId: id,
      );
    }
  });

  Future<void> hardDelete(Iterable<String> ids) async {
    for (final id in ids) {
      await delete(id, permanent: true);
    }
  }

  PublishedSource _toModel(PublishedSourceRow row) => PublishedSource(
    id: row.id,
    title: row.title,
    author: row.author,
    year: row.year,
    url: row.url,
    notes: row.notes,
  );
}
