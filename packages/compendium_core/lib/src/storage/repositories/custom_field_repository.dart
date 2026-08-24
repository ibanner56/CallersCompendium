import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../model/custom_field.dart';
import '../../model/enums.dart';
import '../database.dart';
import '../existence.dart';

/// CRUD for [CustomFieldDef] rows (the user-defined field schema).
///
/// Value storage/reconstruction ([CustomFieldValue]) lives in
/// [DanceRepository] since values are always read/written as part of a
/// dance; this repository owns only the field *definitions*.
///
/// Definitions are **soft-deleted** as of schema v25 (issue #898).
class CustomFieldDefRepository {
  CustomFieldDefRepository(this._db);

  final CompendiumDatabase _db;

  /// Writes [def], reviving it if a tombstone holds its UNIQUE key. See
  /// `TagRepository.upsert`.
  /// Returns the id the definition actually occupies — see
  /// `TagRepository.upsert` on natural-key adoption.
  @useResult
  Future<String> upsert(CustomFieldDef def, {DateTime? at}) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      final id =
          await adoptTombstonedNaturalKey(
            _db,
            table: _db.customFieldDefs,
            keyColumn: 'id',
            naturalKeyColumn: 'key',
            naturalKey: def.key,
            incomingId: def.id,
            joinTable: _db.customFieldValues,
            joinColumn: 'field_id',
          ) ??
          def.id;
      await _db
          .into(_db.customFieldDefs)
          .insertOnConflictUpdate(
            CustomFieldDefsCompanion.insert(
              id: id,
              key: def.key,
              label: def.label,
              type: def.type,
              choicesJson: Value(
                def.choices == null ? null : jsonEncode(def.choices),
              ),
              showInList: Value(def.showInList),
              searchable: Value(def.searchable),
              shareable: Value(def.shareable),
              updatedAt: Value(now),
            ),
          );
      await applyUpsertExistence(
        _db,
        table: _db.customFieldDefs,
        keyColumn: 'id',
        key: id,
        at: now,
      );
      return id;
    });
  }

  Future<CustomFieldDef?> getById(String id) async {
    final row = await (_db.select(
      _db.customFieldDefs,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : toModel(row);
  }

  Future<List<CustomFieldDef>> listAll() async {
    final rows =
        await (_db.select(_db.customFieldDefs)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm(expression: t.label)]))
            .get();
    return [for (final row in rows) ?toModel(row)];
  }

  /// [listAll] as a live stream: the current definitions immediately, then
  /// again after every write that changes them (issue #768).
  ///
  /// Uses the query builder rather than a hand-written `readsFrom`, because
  /// [listAll] is a single `select(customFieldDefs)` with no Dart fan-out. See
  /// `VenueRepository.watchAll` for the contrast with the program list.
  ///
  /// **Deliberately does not cover [isInUse] or [listUsedChoiceValues].** Those
  /// read `custom_field_values`, which is a different table and is NOT in this
  /// stream's inferred set — so a dance gaining or losing a value for a field
  /// does not re-emit here. That is correct for the definitions list, which
  /// renders none of it, and it is stated because the two questions sound alike:
  /// "which fields exist" is not "which fields are used".
  Stream<List<CustomFieldDef>> watchAll() =>
      (_db.select(_db.customFieldDefs)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.label)]))
          .watch()
          .map((rows) => [for (final row in rows) ?toModel(row)]);

  /// Returns `true` if any dance currently has a value for field [id].
  ///
  /// Uses a `LIMIT 1` query so it short-circuits on the first match and avoids
  /// loading the full dance collection.
  Future<bool> isInUse(String id) async {
    final row =
        await (_db.select(_db.customFieldValues)
              ..where((t) => t.fieldId.equals(id))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// Returns all distinct text values currently stored for field [id].
  ///
  /// For `choice` fields this tells you which choices are in use so the editor
  /// can block their removal.
  Future<Set<String>> listUsedChoiceValues(String id) async {
    final rows = await (_db.select(
      _db.customFieldValues,
    )..where((t) => t.fieldId.equals(id))).get();
    return {
      for (final r in rows)
        if (r.valueText != null) r.valueText!,
    };
  }

  /// Throws if any dance still has a value for [id] — deleting a field
  /// definition out from under populated data would silently strand values
  /// that can no longer be decoded (their type is only known via the def).
  /// The "still used?" check and the delete run inside a single transaction
  /// so no dance can acquire a value for [id] between the check and the
  /// delete (no check-then-act race). Mirrors `VenueRepository.delete`.
  ///
  /// Tombstones by default (schema v25, issue #898); the guard is kept. See
  /// `ChoreographerRepository.delete` for [permanent].
  Future<void> delete(String id, {DateTime? at, bool permanent = false}) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      final stillUsed = await (_db.select(
        _db.customFieldValues,
      )..where((t) => t.fieldId.equals(id))).get();
      if (stillUsed.isNotEmpty) {
        throw StateError(
          'cannot delete custom field "$id": still set on '
          '${stillUsed.length} dance(s)',
        );
      }
      if (permanent) {
        await (_db.delete(
          _db.customFieldDefs,
        )..where((t) => t.id.equals(id))).go();
        return;
      }
      await stampExistenceTransition(
        _db,
        table: _db.customFieldDefs,
        keyColumn: 'id',
        key: id,
        at: now,
        deleted: true,
      );
    });
  }

  /// Maps a row to a [CustomFieldDef], returning `null` for a row whose
  /// stored data can't be reconstructed rather than throwing — a malformed or
  /// non-string `choicesJson` (corruption, a bad import, or a future schema
  /// change) would otherwise throw during a normal read and break loading any
  /// dance/definition that references it. Tolerating it here means one
  /// corrupt row can't fail the whole custom-fields load (`listAll`/
  /// `getById`), mirroring `DanceRepository._linkFromRow` /
  /// `ProgramRepository._slotFromRow`.
  static CustomFieldDef? toModel(CustomFieldDefRow row) {
    List<String>? choices;
    if (row.choicesJson != null) {
      try {
        // `.cast<String>()` is lazy — force it eagerly with `.toList()` so a
        // wrong-type element throws here, inside the try, rather than later
        // (e.g. inside `List.unmodifiable` in the [CustomFieldDef]
        // constructor, outside this catch).
        choices = (jsonDecode(row.choicesJson!) as List)
            .cast<String>()
            .toList();
      } catch (_) {
        // Malformed JSON or a non-string element — can't recover a usable
        // choice list for this row.
        return null;
      }
    }
    try {
      return CustomFieldDef(
        id: row.id,
        key: row.key,
        label: row.label,
        type: row.type,
        choices: choices,
        showInList: row.showInList,
        searchable: row.searchable,
        shareable: row.shareable,
      );
    } on ArgumentError {
      // E.g. a `choice` field whose decoded list came back empty — the
      // constructor's own invariant rejects that, so surface it the same way
      // as an undecodable row rather than throwing out of a read.
      return null;
    }
  }
}

/// Encodes a [CustomFieldValue] into the `(valueText, valueNum)` pair stored
/// on `custom_field_values`, per [def]'s type. Booleans are stored as 0/1 in
/// `valueNum` (see `docs/design/storage.md`).
(String?, double?) encodeCustomFieldValue(
  CustomFieldValue value,
  CustomFieldDef def,
) {
  if (!value.matchesType(def)) {
    throw ArgumentError(
      'value ${value.value} does not match field "${def.key}" '
      'type ${def.type}',
    );
  }
  switch (def.type) {
    case CustomFieldType.text:
    case CustomFieldType.choice:
      return (value.value as String, null);
    case CustomFieldType.number:
      final numeric = value.value as num;
      if (!isFiniteCustomFieldNumber(numeric)) {
        throw ArgumentError.value(
          value.value,
          'value',
          'must be finite and representable as a double',
        );
      }
      return (null, numeric.toDouble());
    case CustomFieldType.boolean:
      return (null, (value.value as bool) ? 1.0 : 0.0);
  }
}

/// Inverse of [encodeCustomFieldValue].
CustomFieldValue decodeCustomFieldValue({
  required String fieldId,
  required CustomFieldType type,
  required String? valueText,
  required double? valueNum,
}) {
  final Object value;
  switch (type) {
    case CustomFieldType.text:
    case CustomFieldType.choice:
      value = valueText!;
    case CustomFieldType.number:
      value = valueNum!;
    case CustomFieldType.boolean:
      value = valueNum != 0;
  }
  return CustomFieldValue(fieldId: fieldId, value: value);
}
