import 'dart:convert';

import 'package:drift/drift.dart';

import '../../model/custom_field.dart';
import '../../model/enums.dart';
import '../database.dart';

/// CRUD for [CustomFieldDef] rows (the user-defined field schema).
///
/// Value storage/reconstruction ([CustomFieldValue]) lives in
/// [DanceRepository] since values are always read/written as part of a
/// dance; this repository owns only the field *definitions*.
class CustomFieldDefRepository {
  CustomFieldDefRepository(this._db);

  final CompendiumDatabase _db;

  Future<void> upsert(CustomFieldDef def) => _db
      .into(_db.customFieldDefs)
      .insertOnConflictUpdate(
        CustomFieldDefsCompanion.insert(
          id: def.id,
          key: def.key,
          label: def.label,
          type: def.type,
          choicesJson: Value(
            def.choices == null ? null : jsonEncode(def.choices),
          ),
          showInList: Value(def.showInList),
          searchable: Value(def.searchable),
        ),
      );

  Future<CustomFieldDef?> getById(String id) async {
    final row = await (_db.select(
      _db.customFieldDefs,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : toModel(row);
  }

  Future<List<CustomFieldDef>> listAll() async {
    final rows = await (_db.select(
      _db.customFieldDefs,
    )..orderBy([(t) => OrderingTerm(expression: t.label)])).get();
    return rows.map(toModel).toList();
  }

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
  Future<void> delete(String id) async {
    final stillUsed = await (_db.select(
      _db.customFieldValues,
    )..where((t) => t.fieldId.equals(id))).get();
    if (stillUsed.isNotEmpty) {
      throw StateError(
        'cannot delete custom field "$id": still set on '
        '${stillUsed.length} dance(s)',
      );
    }
    await (_db.delete(_db.customFieldDefs)..where((t) => t.id.equals(id))).go();
  }

  static CustomFieldDef toModel(CustomFieldDefRow row) => CustomFieldDef(
    id: row.id,
    key: row.key,
    label: row.label,
    type: row.type,
    choices: row.choicesJson == null
        ? null
        : (jsonDecode(row.choicesJson!) as List).cast<String>(),
    showInList: row.showInList,
    searchable: row.searchable,
  );
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
      return (null, (value.value as num).toDouble());
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
