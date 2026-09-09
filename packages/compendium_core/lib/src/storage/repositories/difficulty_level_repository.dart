import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../model/difficulty_level.dart';
import '../../util/uuid.dart';
import '../database.dart';
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
    final level = DifficultyLevel(
      id: (newId ?? uuidV4)(),
      label: normalizeShareableText(label),
      position: position,
    );
    await upsert(level);
    return level;
  }

  /// Inserts or updates a vocabulary entry without changing its stable ID.
  Future<void> upsert(DifficultyLevel level) {
    final normalized = level.copyWith(
      label: normalizeShareableText(level.label),
    );
    return _db
        .into(_db.difficultyLevels)
        .insertOnConflictUpdate(
          DifficultyLevelsCompanion.insert(
            id: normalized.id,
            label: normalized.label,
            position: normalized.position,
          ),
        );
  }

  Future<DifficultyLevel?> getById(String id) async {
    final row = await (_db.select(
      _db.difficultyLevels,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<List<DifficultyLevel>> listAll() async {
    final rows =
        await (_db.select(_db.difficultyLevels)..orderBy([
              (t) => OrderingTerm(expression: t.position),
              (t) => OrderingTerm(expression: t.id),
            ]))
            .get();
    return rows.map(_toModel).toList();
  }

  /// Replaces the vocabulary order with [ids], which must name every level once.
  Future<void> reorder(List<String> ids) => _db.transaction(() async {
    if (ids.length != ids.toSet().length) {
      throw ArgumentError.value(ids, 'ids', 'must not contain duplicates');
    }
    final existing = await _db.select(_db.difficultyLevels).get();
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
      await (_db.update(_db.difficultyLevels)
            ..where((t) => t.id.equals(ids[position])))
          .write(DifficultyLevelsCompanion(position: Value(position)));
    }
  });

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

  /// Deletes a custom level only when no dance refers to it.
  ///
  /// The reference count and delete share a transaction, mirroring the
  /// custom-field and venue guards: no dance can acquire a reference in the
  /// check-then-delete gap.
  Future<void> delete(String id) => _db.transaction(() async {
    if (DifficultyLevel.shippedIds.contains(id)) {
      throw StateError('cannot delete shipped difficulty level "$id"');
    }
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
    await (_db.delete(
      _db.difficultyLevels,
    )..where((t) => t.id.equals(id))).go();
  });

  DifficultyLevel _toModel(DifficultyLevelRow row) =>
      DifficultyLevel(id: row.id, label: row.label, position: row.position);
}
