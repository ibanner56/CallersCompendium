import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../model/difficulty_level.dart';
import '../../util/uuid.dart';
import '../database.dart';
import '../existence.dart';
import '../shareable_text.dart';

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
  Future<void> upsert(DifficultyLevel level, {DateTime? at}) async {
    final normalized = level.copyWith(label: _normalizeLabel(level.label));
    final now = resolveStamp(at);
    await _db.transaction(() => _upsertInTransaction(normalized, now));
  }

  Future<DifficultyLevel?> getById(String id) async {
    final row = await (_db.select(
      _db.difficultyLevels,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : _toModel(row);
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
  Future<void> restore(String id, {required DateTime at}) =>
      stampExistenceTransition(
        _db,
        table: _db.difficultyLevels,
        keyColumn: 'id',
        key: id,
        at: at,
        deleted: false,
      );

  Future<void> hardDelete(Iterable<String> ids) async {
    for (final id in ids) {
      await (_db.delete(
        _db.difficultyLevels,
      )..where((t) => t.id.equals(id))).go();
    }
  }

  DifficultyLevel _toModel(DifficultyLevelRow row) =>
      DifficultyLevel(id: row.id, label: row.label, position: row.position);

  Future<void> _upsertInTransaction(
    DifficultyLevel normalized,
    DateTime now,
  ) async {
    final duplicateRows = (await _db.select(_db.difficultyLevels).get())
        .where(
          (row) =>
              row.id != normalized.id &&
              row.label.toLowerCase() == normalized.label.toLowerCase(),
        )
        .toList();
    final duplicate = duplicateRows.isEmpty ? null : duplicateRows.first;
    if (duplicate != null) {
      throw StateError(
        'difficulty level labels must be unique: "${normalized.label}"',
      );
    }
    await _db
        .into(_db.difficultyLevels)
        .insertOnConflictUpdate(
          DifficultyLevelsCompanion.insert(
            id: normalized.id,
            label: normalizeShareableText(normalized.label),
            position: normalized.position,
            updatedAt: Value(now),
          ),
        );
    await applyUpsertExistence(
      _db,
      table: _db.difficultyLevels,
      keyColumn: 'id',
      key: normalized.id,
      at: now,
    );
  }

  String _normalizeLabel(String raw) {
    final label = normalizeShareableText(raw).trim();
    if (label.isEmpty) {
      throw ArgumentError.value(raw, 'label', 'must not be empty');
    }
    return label;
  }
}
