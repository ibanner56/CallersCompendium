import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../model/difficulty_level.dart';
import '../../sync/sync_record_kind.dart';
import '../../util/uuid.dart';
import '../database.dart';
import '../existence.dart';
import '../shareable_text.dart';
import 'sync_local_repository.dart';

/// CRUD for the collection's user-configurable difficulty vocabulary.
class DifficultyLevelRepository {
  DifficultyLevelRepository(this._db);

  final CompendiumDatabase _db;

  /// Creates a custom level with a generated UUIDv4 identifier.
  @useResult
  Future<DifficultyLevel> createCustom({
    required String label,
    required int position,
    String Function()? newId,
  }) async {
    final normalizedLabel = _normalizeLabel(label);
    final now = resolveStamp(null);
    return _db.transaction(() async {
      final existingRows = await _db.select(_db.difficultyLevels).get();
      DifficultyLevelRow? tombstone;
      for (final row in existingRows) {
        if (row.label.toLowerCase() == normalizedLabel.toLowerCase()) {
          if (row.deletedAt == null) {
            throw StateError(
              'difficulty level labels must be unique: "$normalizedLabel"',
            );
          }
          tombstone = row;
          break;
        }
      }
      final level = DifficultyLevel(
        id: tombstone?.id ?? (newId ?? uuidV4)(),
        label: normalizedLabel,
        position: position,
      );
      await _upsertInTransaction(level, now);
      return level;
    });
  }

  /// Inserts or updates a vocabulary entry without changing its stable ID.
  ///
  /// Throws [StateError] when the write would rename this level onto a label
  /// another row already holds, case-insensitively — the visible refusal
  /// `defaults_section` already surfaces. It no longer throws when the label is
  /// **unchanged** and merely derives a target another row occupies: that is
  /// §4.1's carve-out, and the write stores the label un-normalised and records
  /// the row in `normalisation_skips` instead. Before #1348 there was no
  /// carve-out at all, so re-importing a recorded level from an archive failed.
  ///
  /// Pass `localUserEdit: true` only when the person using the app deliberately
  /// edited this record: that cancels a peer's pending tombstone for it
  /// (sync-spec §6.8, [cancelPendingSyncDeletionForLocalEdit]). It defaults to
  /// false because imports, archive restore and automatic writes share this
  /// method, and a cancellation they did not intend reverses a peer's deletion.
  Future<void> upsert(
    DifficultyLevel level, {
    DateTime? at,
    bool localUserEdit = false,
  }) async {
    final normalized = level.copyWith(label: _normalizeLabel(level.label));
    final now = resolveStamp(at);
    await _db.transaction(
      () => _upsertInTransaction(
        normalized,
        now,
        localUserEdit: localUserEdit,
        // Only this entry point offers §4.1's carve-out. [createCustom] is a
        // creation, so it has no recorded row to re-save, and [writeFromSync]
        // must keep refusing per §6.7 — a natural-key collision there is an
        // identity decision reconciliation owns.
        unnormalisedLabel: _sanitizeLabel(level.label),
      ),
    );
  }

  /// Applies a validated inbound sync record.
  ///
  /// Separate from [upsert] per §6.7 so the interactive path cannot change what
  /// an inbound apply does. The duplicate-label check is kept deliberately: a
  /// collision is an identity decision that belongs to reconciliation, so the
  /// writer refuses rather than guessing, and the engine reports the record.
  Future<void> writeFromSync(DifficultyLevel level, {DateTime? at}) async {
    final normalized = level.copyWith(label: _normalizeLabel(level.label));
    final now = resolveStamp(at);
    await _db.transaction(
      () => _upsertInTransaction(normalized, now, seedExistence: false),
    );
  }

  Future<DifficultyLevel?> getById(String id) async {
    final row = await (_db.select(
      _db.difficultyLevels,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  /// Finds a live level by its case-insensitive normalized label.
  Future<DifficultyLevel?> findByLabel(String label) async {
    final normalized = _normalizeLabel(label).toLowerCase();
    for (final level in await listAll()) {
      if (level.label.toLowerCase() == normalized) return level;
    }
    return null;
  }

  Future<List<DifficultyLevel>> listAll() async {
    final rows =
        await (_db.select(_db.difficultyLevels)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([
                (t) => OrderingTerm(expression: t.position),
                (t) => OrderingTerm(expression: t.id),
              ]))
            .get();
    return rows.map(_toModel).toList();
  }

  /// Replaces the vocabulary order with [ids], which must name every level once.
  Future<void> reorder(List<String> ids, {DateTime? at}) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      if (ids.length != ids.toSet().length) {
        throw ArgumentError.value(ids, 'ids', 'must not contain duplicates');
      }
      final existing = await (_db.select(
        _db.difficultyLevels,
      )..where((t) => t.deletedAt.isNull())).get();
      final existingIds = {for (final level in existing) level.id};
      if (ids.toSet().length != existingIds.length ||
          !ids.toSet().containsAll(existingIds)) {
        throw ArgumentError.value(
          ids,
          'ids',
          'must contain every existing difficulty level exactly once',
        );
      }
      for (var position = 0; position < ids.length; position++) {
        await (_db.update(
          _db.difficultyLevels,
        )..where((t) => t.id.equals(ids[position]))).write(
          DifficultyLevelsCompanion(
            position: Value(position),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  /// Returns `true` when any dance, including a tombstoned dance, refers to
  /// [id]. A deleted dance can be restored, so it still protects the level.
  Future<bool> isInUse(String id) async {
    final row =
        await (_db.select(_db.dances)
              ..where((t) => t.levelId.equals(id))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Future<List<({DifficultyLevel level, bool deleted})>>
  listAllWithDeleted() async {
    final rows =
        await (_db.select(_db.difficultyLevels)..orderBy([
              (t) => OrderingTerm(expression: t.position),
              (t) => OrderingTerm(expression: t.id),
            ]))
            .get();
    return [
      for (final row in rows)
        (level: _toModel(row), deleted: row.deletedAt != null),
    ];
  }

  /// Tombstones a level only when no dance refers to it.
  ///
  /// The reference count and delete share a transaction, mirroring the
  /// custom-field and venue guards: no dance can acquire a reference in the
  /// check-then-delete gap.
  Future<void> delete(String id, {DateTime? at}) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      // Deliberately counts tombstoned dances too, unlike the other
      // referential guards: [isInUse] states the policy for this kind — a
      // deleted dance can be restored, so it still protects its level.
      final references = _db.dances.id.count();
      final count =
          await (_db.selectOnly(_db.dances)
                ..addColumns([references])
                ..where(_db.dances.levelId.equals(id)))
              .map((row) => row.read(references) ?? 0)
              .getSingle();
      if (count > 0) {
        throw StateError(
          'cannot delete difficulty level "$id": still referenced by '
          '$count dance(s)',
        );
      }
      await stampExistenceTransition(
        _db,
        table: _db.difficultyLevels,
        keyColumn: 'id',
        key: id,
        at: now,
        deleted: true,
      );
    });
  }

  /// Revives a tombstoned level without changing its stable ID.
  Future<void> restore(
    String id, {
    required DateTime at,
    bool clearPending = true,
  }) => _db.transaction(() async {
    await stampExistenceTransition(
      _db,
      table: _db.difficultyLevels,
      keyColumn: 'id',
      key: id,
      at: at,
      deleted: false,
    );
    if (clearPending) {
      await clearPendingSyncDeletionForRestore(
        _db,
        kind: SyncRecordKind.difficultyLevel,
        recordId: id,
        table: _db.difficultyLevels,
        keyColumn: 'id',
        at: at,
      );
    }
  });

  Future<void> hardDelete(Iterable<String> ids) => _db.transaction(() async {
    for (final id in ids) {
      if (await isPublishedSyncRecord(
        _db,
        kind: SyncRecordKind.difficultyLevel,
        recordId: id,
      )) {
        await stampExistenceTransition(
          _db,
          table: _db.difficultyLevels,
          keyColumn: 'id',
          key: id,
          at: DateTime.now().toUtc(),
          deleted: true,
        );
      } else {
        await (_db.delete(
          _db.difficultyLevels,
        )..where((t) => t.id.equals(id))).go();
      }
    }
  });

  DifficultyLevel _toModel(DifficultyLevelRow row) =>
      DifficultyLevel(id: row.id, label: row.label, position: row.position);

  /// [unnormalisedLabel] is the caller's own label, sanitised but not composed,
  /// and is supplied only by paths §4.1's write-path carve-out applies to. When
  /// it is null the historical behaviour is unchanged: any duplicate label
  /// raises.
  Future<void> _upsertInTransaction(
    DifficultyLevel normalized,
    DateTime now, {
    bool seedExistence = true,
    bool localUserEdit = false,
    String? unnormalisedLabel,
  }) async {
    final rows = await _db.select(_db.difficultyLevels).get();
    final duplicateRows = rows
        .where(
          (row) =>
              row.id != normalized.id &&
              row.label.toLowerCase() == normalized.label.toLowerCase(),
        )
        .toList();
    final duplicate = duplicateRows.isEmpty ? null : duplicateRows.first;
    // The label stored when the collision is §4.1's carve-out rather than a
    // genuine duplicate, or null when the write normalises as usual. The two
    // questions are [resolveNaturalKeyCollision]'s, asked here against this
    // repository's own case-insensitive uniqueness rule instead of a bare
    // `UNIQUE` index (#1348).
    String? deferredLabel;
    if (duplicate != null) {
      final ownRows = rows.where((row) => row.id == normalized.id).toList();
      final current = ownRows.isEmpty ? null : ownRows.first;
      var refuse = true;
      if (current != null && unnormalisedLabel != null) {
        final deferred = unnormalisedLabel;
        final deferredLower = deferred.toLowerCase();
        // 1. Did the user change the value? A row whose stored label derives a
        //    different target is being renamed onto a label somebody else
        //    holds, and §4.1's remedy has nothing to offer it.
        // 2. Would the un-normalised form still collide? If it would, storing
        //    it is not available either, so refusing visibly is all that is
        //    left.
        refuse =
            normalizeShareableText(current.label) != normalized.label ||
            rows.any(
              (row) =>
                  row.id != normalized.id &&
                  row.label.toLowerCase() == deferredLower,
            );
        if (!refuse) deferredLabel = deferred;
      }
      if (refuse) {
        throw StateError(
          'difficulty level labels must be unique: "${normalized.label}"',
        );
      }
    }
    await _db
        .into(_db.difficultyLevels)
        .insertOnConflictUpdate(
          DifficultyLevelsCompanion.insert(
            id: normalized.id,
            label: deferredLabel ?? normalizeShareableText(normalized.label),
            position: normalized.position,
            updatedAt: Value(now),
          ),
        );
    if (deferredLabel != null) {
      await recordNormalisationSkipAt(
        _db,
        difficultyLevelLabelNormalisation,
        recordId: normalized.id,
      );
    }
    if (seedExistence) {
      await applyUpsertExistence(
        _db,
        table: _db.difficultyLevels,
        keyColumn: 'id',
        key: normalized.id,
        at: now,
      );
    }
    if (localUserEdit) {
      await cancelPendingSyncDeletionForLocalEdit(
        _db,
        kind: SyncRecordKind.difficultyLevel,
        recordId: normalized.id,
        table: _db.difficultyLevels,
        keyColumn: 'id',
        at: now,
      );
    }
  }

  String _normalizeLabel(String raw) => normalizeShareableText(
    _sanitizeLabel(raw),
  );

  /// The label as stored when §4.1 defers its composition: sanitised — §4.6
  /// binds that to every write path with no carve-out — and trimmed, but not
  /// NFC-composed.
  ///
  /// [_normalizeLabel] is defined over this rather than beside it, so a label
  /// stored through the carve-out always derives the target it would otherwise
  /// have been normalized to. The pass re-derives that target from the stored
  /// bytes, so if the two disagreed the recorded skip could never discharge.
  String _sanitizeLabel(String raw) {
    final label = sanitizeShareableText(raw).trim();
    if (label.isEmpty) {
      throw ArgumentError.value(raw, 'label', 'must not be empty');
    }
    return label;
  }
}
