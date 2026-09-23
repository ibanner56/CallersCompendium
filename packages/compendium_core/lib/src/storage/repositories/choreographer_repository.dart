import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../model/choreographer.dart';
import '../../sync/sync_record_kind.dart';
import '../database.dart';
import '../existence.dart';
import '../shareable_text.dart';
import 'sync_local_repository.dart';

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
  @useResult
  ///
  /// Pass `localUserEdit: true` only when the person using the app deliberately
  /// edited this record: that cancels a peer's pending tombstone for it
  /// (sync-spec §6.8, [cancelPendingSyncDeletionForLocalEdit]). It defaults to
  /// false because imports, archive restore and automatic writes share this
  /// method, and a cancellation they did not intend reverses a peer's deletion.
  Future<String> upsert(
    Choreographer c, {
    DateTime? at,
    bool localUserEdit = false,
  }) => _write(c, at: at, fromSync: false, localUserEdit: localUserEdit);

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
  Future<void> writeFromSync(Choreographer c, {DateTime? at}) async {
    final _ = await _write(c, at: at, fromSync: true, localUserEdit: false);
  }

  Future<String> _write(
    Choreographer c, {
    required DateTime? at,
    required bool fromSync,
    required bool localUserEdit,
  }) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      final name = normalizeShareableText(c.name);
      final incumbent = await (_db.select(
        _db.choreographers,
      )..where((t) => t.name.equals(name))).getSingleOrNull();
      final current = await (_db.select(
        _db.choreographers,
      )..where((t) => t.id.equals(c.id))).getSingleOrNull();
      final collidingEdit =
          !fromSync &&
          current != null &&
          incumbent != null &&
          incumbent.id != c.id;
      if (fromSync && incumbent != null && incumbent.id != c.id) {
        // Refuse rather than guess: reconciliation owns natural-key
        // identity, so reaching the writer with the key held by another
        // row means the record must be reported, not altered to fit.
        throw StateError(
          'inbound choreographer "${c.id}" wants a name held by '
          '"${incumbent.id}"',
        );
      }
      final authorIndexChanged =
          (!collidingEdit &&
              current != null &&
              (current.name != name || current.deletedAt != null)) ||
          (current == null && incumbent?.deletedAt != null);
      final id = (collidingEdit || fromSync)
          ? c.id
          : await adoptTombstonedNaturalKey(
                  _db,
                  table: _db.choreographers,
                  keyColumn: 'id',
                  naturalKeyColumn: 'name',
                  naturalKey: name,
                  incomingId: c.id,
                  joinTable: _db.danceAuthors,
                  joinColumn: 'choreographer_id',
                ) ??
                c.id;
      await _db
          .into(_db.choreographers)
          .insertOnConflictUpdate(
            ChoreographersCompanion.insert(
              id: id,
              name: collidingEdit
                  ? current.name
                  : normalizeShareableText(c.name),
              website: Value(
                c.website == null ? null : normalizeShareableText(c.website!),
              ),
              notes: Value(
                c.notes == null ? null : normalizeShareableText(c.notes!),
              ),
              email: Value(c.email),
              location: Value(c.location),
              deceased: Value(c.deceased),
              updatedAt: Value(now),
            ),
          );
      if (collidingEdit) {
        await recordNormalisationSkip(
          _db,
          table: 'choreographers',
          column: 'name',
          recordId: c.id,
        );
      }
      if (!fromSync) {
        await applyUpsertExistence(
          _db,
          table: _db.choreographers,
          keyColumn: 'id',
          key: id,
          at: now,
        );
      }
      if (authorIndexChanged) {
        await _refreshAuthorIndex(id);
      }
      return id;
    });
  }

  /// Keeps the denormalized author text in both FTS tables aligned with a
  /// choreographer rename without rebuilding unrelated dance-derived rows.
  Future<void> _refreshAuthorIndex(String choreographerId) async {
    for (final table in const ['dance_fts', 'dance_substring_fts']) {
      await _db.customStatement(
        'UPDATE $table '
        'SET authors = ('
        '  SELECT group_concat(name, \' \') FROM ('
        '    SELECT c.name FROM dance_authors da '
        '    JOIN choreographers c ON c.id = da.choreographer_id '
        '    WHERE da.dance_id = $table.dance_id '
        '      AND c.deleted_at IS NULL '
        '    ORDER BY da.position'
        '  )'
        ') '
        'WHERE dance_id IN ('
        '  SELECT dance_id FROM dance_authors WHERE choreographer_id = ?'
        ')',
        [choreographerId],
      );
    }
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
  /// [permanent] removes the row for an unpublished record, for rolling back a
  /// just-committed import (`ImportPipeline.undo`). A published record is
  /// tombstoned instead so peers retain deletion evidence. The guard applies
  /// either way.
  ///
  /// [permanent] also **tombstones rather than erases** whenever any
  /// `dance_authors` row still names this choreographer — the case the live
  /// guard above lets through because every such dance is itself tombstoned
  /// (issue #1357). `dance_authors` is `ON DELETE CASCADE`, so erasing here
  /// would take the tombstoned dance's author credit with it, and restoring
  /// that dance would bring it back with no author: data loss a rollback has no
  /// business causing. A tombstone keeps the join row, keeps the choreographer
  /// out of every live view (which is what `ImportPipeline.undo` needs of it),
  /// and lets a later restore of both rows show the credit again.
  Future<void> delete(String id, {DateTime? at, bool permanent = false}) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      // Only a *live* dance holds this choreographer back (§3.1: "refuse to
      // hard-delete an entity still referenced by a live record"). A
      // soft-deleted dance keeps its `dance_authors` rows — the tombstone
      // fires no FK cascade — so counting them would block a delete on the
      // strength of a record that is itself deleted. That regressed import
      // undo once publication forfeiture started tombstoning published dances
      // instead of erasing them: the surviving rows made this guard throw, the
      // caller swallowed it, and the import-created choreographer stayed live.
      // `CompendiumSyncStorage._hasCitation` counts liveness the same way.
      final stillUsed =
          await (_db.select(_db.danceAuthors).join([
                innerJoin(
                  _db.dances,
                  _db.dances.id.equalsExp(_db.danceAuthors.danceId),
                ),
              ])..where(
                _db.danceAuthors.choreographerId.equals(id) &
                    _db.dances.deletedAt.isNull(),
              ))
              .get();
      if (stillUsed.isNotEmpty) {
        throw StateError(
          'cannot delete choreographer "$id": still credited on '
          '${stillUsed.length} dance(s)',
        );
      }
      if (permanent) {
        // Any surviving `dance_authors` row — necessarily a tombstoned dance's,
        // since a live one threw above — downgrades the erase to a tombstone
        // rather than cascading that dance's credit away (issue #1357).
        final creditedBySurvivor =
            await (_db.select(_db.danceAuthors)
                  ..where((t) => t.choreographerId.equals(id))
                  ..limit(1))
                .getSingleOrNull() !=
            null;
        if (creditedBySurvivor ||
            await isPublishedSyncRecord(
              _db,
              kind: SyncRecordKind.choreographer,
              recordId: id,
            )) {
          await stampExistenceTransition(
            _db,
            table: _db.choreographers,
            keyColumn: 'id',
            key: id,
            at: now,
            deleted: true,
          );
          return;
        }
        await (_db.delete(
          _db.choreographers,
        )..where((t) => t.id.equals(id))).go();
        return;
      }
      await stampExistenceTransition(
        _db,
        table: _db.choreographers,
        keyColumn: 'id',
        key: id,
        at: now,
        deleted: true,
      );
    });
  }

  /// Explicitly revives a tombstoned choreographer and, by default, cancels
  /// any pending sync tombstone held for it.
  Future<void> restore(
    String id, {
    required DateTime at,
    bool clearPending = true,
  }) => _db.transaction(() async {
    await stampExistenceTransition(
      _db,
      table: _db.choreographers,
      keyColumn: 'id',
      key: id,
      at: at,
      deleted: false,
    );
    if (clearPending) {
      await clearPendingSyncDeletion(
        _db,
        kind: SyncRecordKind.choreographer,
        recordId: id,
      );
    }
  });

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
