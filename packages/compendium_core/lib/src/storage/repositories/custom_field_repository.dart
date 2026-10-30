import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../model/custom_field.dart';
import '../../model/enums.dart';
import '../../model/stored_timestamp.dart';
import '../../sync/sync_record_kind.dart';
import '../database.dart';
import '../duplicate_natural_key.dart';
import '../existence.dart';
import '../shareable_text.dart';
import '../utc_datetime.dart';
import 'sync_local_repository.dart';

/// Thrown by [CustomFieldDefRepository.delete] when live dances still hold a
/// value for the field.
///
/// Carries the count so a screen can pluralise its own localised sentence
/// instead of parsing a message. [toString] names the field id and is for logs
/// only: screens MUST NOT surface it (CWE-209).
class CustomFieldInUseException implements Exception {
  const CustomFieldInUseException({
    required this.fieldId,
    required this.danceCount,
  });

  /// The id of the field definition that could not be deleted.
  final String fieldId;

  /// How many **live** dances still hold a value for [fieldId].
  final int danceCount;

  @override
  String toString() =>
      'cannot delete custom field "$fieldId": still set on '
      '$danceCount dance(s)';
}

/// Whether the search bar's text index (`dance_fts.custom_values`) carries the
/// values of the custom field [def], assuming the definition is live
/// (maintainer decision search-index (a), 2026-10-29).
///
/// * **Searchable off** keeps the field's values out of the search bar as well
///   as out of the Filters panel: the setting is how a caller keeps a private
///   note from turning up in an "All fields" search.
/// * **Yes/no fields** are never indexed. Their stored value would index as the
///   word "true" or "false", which no caller types for a field and which
///   matched every dance with any yes/no field set. The field's own facet in
///   the Filters panel is how a yes/no value is found.
///
/// `DanceRepository` applies this when it writes a dance's index rows;
/// [CustomFieldDefRepository.onIndexedValuesChanged] reindexes the dances
/// holding a value when a local edit changes the answer, and the one-shot pass
/// behind `customFieldIndexRepairDoneKey` repairs indexes written before the
/// rule existed.
bool customFieldIndexesValueText(CustomFieldDefRow def) =>
    def.searchable && def.type != CustomFieldType.boolean;

/// CRUD for [CustomFieldDef] rows (the user-defined field schema).
///
/// Value storage/reconstruction ([CustomFieldValue]) lives in
/// [DanceRepository] since values are always read/written as part of a
/// dance; this repository owns only the field *definitions*.
///
/// Definitions are **soft-deleted** as of schema v25 (issue #898).
class CustomFieldDefRepository {
  CustomFieldDefRepository(this._db, {this.onIndexedValuesChanged});

  final CompendiumDatabase _db;

  /// Called, inside the write's transaction, after [upsert] changes whether
  /// the search bar's text index carries the field's values
  /// ([customFieldIndexesValueText], for a live row): in practice, when its
  /// Searchable setting is switched. The dance index holds those values, so
  /// the dances holding one are reindexed. An inbound sync apply needs nothing of
  /// its own: after each batch it reindexes the dances holding a value for
  /// every definition it wrote (#1920,
  /// `CompendiumSyncStorage.reindexDerivedAfterApply`).
  final Future<void> Function(String id)? onIndexedValuesChanged;

  /// Writes [def], reviving it if a tombstone holds its UNIQUE key. See
  /// `TagRepository.upsert`.
  /// Returns the id the definition actually occupies — see
  /// `TagRepository.upsert` on natural-key adoption.
  @useResult
  ///
  /// Pass `localUserEdit: true` only when the person using the app deliberately
  /// edited this record: that cancels a peer's pending tombstone for it
  /// (sync-spec §6.8, [cancelPendingSyncDeletionForLocalEdit]). It defaults to
  /// false because imports, archive restore and automatic writes share this
  /// method, and a cancellation they did not intend reverses a peer's deletion.
  ///
  /// Throws [DuplicateNaturalKeyError] when the write would move this
  /// definition onto a key another row already holds, and when it would
  /// **create** a definition under a key a *live* row holds; see
  /// [resolveNaturalKeyCollision] for when the first happens rather than §4.1's
  /// store-un-normalised carve-out, and [refuseCreationOntoLiveNaturalKey] for
  /// why the second is refused rather than adopted (#1348). A key a *tombstone*
  /// holds is still adopted, not refused.
  Future<String> upsert(
    CustomFieldDef def, {
    DateTime? at,
    bool localUserEdit = false,
  }) => _write(def, at: at, fromSync: false, localUserEdit: localUserEdit);

  /// Applies a validated inbound sync record.
  ///
  /// §6.7 keeps the inbound write off the editor's path. Concretely this
  /// skips three behaviours that exist for a person editing a record and
  /// are wrong for a peer's: it does not adopt a tombstoned row's identity
  /// (identity is reconciliation's decision, and silently relocating the
  /// record would store it under an id the peer never named), it does not
  /// take §4.1's collision carve-out when another row holds the incoming value
  /// (§6.7 refuses the record to reconciliation rather than storing an altered
  /// copy — or, since #1348, an un-normalised one), and it does not seed
  /// `existence_at`, which the envelope owns.
  Future<void> writeFromSync(CustomFieldDef def, {DateTime? at}) async {
    final _ = await _write(def, at: at, fromSync: true, localUserEdit: false);
  }

  Future<String> _write(
    CustomFieldDef def, {
    required DateTime? at,
    required bool fromSync,
    required bool localUserEdit,
  }) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      final key = normalizeShareableText(def.key);
      final choices = def.choices
          ?.map(normalizeShareableText)
          .toList(growable: false);
      final incumbent = await (_db.select(
        _db.customFieldDefs,
      )..where((t) => t.key.equals(key))).getSingleOrNull();
      final current = await (_db.select(
        _db.customFieldDefs,
      )..where((t) => t.id.equals(def.id))).getSingleOrNull();
      final collidingEdit =
          !fromSync &&
          current != null &&
          incumbent != null &&
          incumbent.id != def.id;
      // §4.1's carve-out value, resolved before anything is written: either
      // the un-normalised form this row keeps, or a throw for a genuine
      // duplicate (#1348). See [resolveNaturalKeyCollision].
      final deferredKey = collidingEdit
          ? await resolveNaturalKeyCollision(
              _db,
              address: customFieldKeyNormalisation,
              recordId: def.id,
              storedValue: current.key,
              incomingValue: def.key,
              incumbentId: incumbent.id,
            )
          : null;
      if (fromSync && incumbent != null && incumbent.id != def.id) {
        // Refuse rather than guess: reconciliation owns natural-key
        // identity, so reaching the writer with the key held by another
        // row means the record must be reported, not altered to fit.
        throw StateError(
          'inbound custom field "${def.id}" wants a name held by '
          '"${incumbent.id}"',
        );
      }
      // A creation onto a key another row holds. `current == null` makes
      // `collidingEdit` false, so the decision above never ran; a *live* holder
      // must be refused here or the insert fails as a raw `SqliteException`
      // that `custom_fields_screen` does not catch. A tombstoned holder is
      // adopted immediately below instead. `incumbent.id != def.id` is implied:
      // a row with `def.id` would have made `current` non-null.
      if (!fromSync && current == null && incumbent != null) {
        refuseCreationOntoLiveNaturalKey(
          address: customFieldKeyNormalisation,
          normalisedValue: key,
          incumbentId: incumbent.id,
          incumbentDeletedAt: incumbent.deletedAt,
        );
      }
      final id = (collidingEdit || fromSync)
          ? def.id
          : await adoptTombstonedNaturalKey(
                  _db,
                  table: _db.customFieldDefs,
                  keyColumn: 'id',
                  naturalKeyColumn: 'key',
                  naturalKey: key,
                  incomingId: def.id,
                  joinTable: _db.customFieldValues,
                  joinColumn: 'field_id',
                ) ??
                def.id;
      final heldBefore = fromSync ? null : await _publishesValues(id);
      final indexedBefore = fromSync ? null : await _indexesValues(id);
      final typeBefore = fromSync
          ? null
          : (await (_db.select(
              _db.customFieldDefs,
            )..where((t) => t.id.equals(id))).getSingleOrNull())?.type;
      await _db
          .into(_db.customFieldDefs)
          .insertOnConflictUpdate(
            CustomFieldDefsCompanion.insert(
              id: id,
              // The carve-out stores the *user's* value with NFC deferred,
              // not the row's previous one (#1348).
              key: deferredKey ?? normalizeShareableText(def.key),
              label: normalizeShareableText(def.label),
              type: def.type,
              choicesJson: Value(choices == null ? null : jsonEncode(choices)),
              showInList: Value(def.showInList),
              searchable: Value(def.searchable),
              shareable: Value(def.shareable),
              updatedAt: Value(now),
            ),
          );
      if (collidingEdit) {
        await recordNormalisationSkipAt(
          _db,
          customFieldKeyNormalisation,
          recordId: def.id,
        );
      }
      if (!fromSync) {
        await applyUpsertExistence(
          _db,
          table: _db.customFieldDefs,
          keyColumn: 'id',
          key: id,
          at: now,
        );
        if (typeBefore != null) {
          await _dropTrashedValuesThatNoLongerFit(
            id,
            typeBefore: typeBefore,
            type: def.type,
            choices: choices,
            restamp: heldBefore!,
            at: now,
          );
        }
        // The upsert leaves the row live, so it publishes values exactly when
        // it is shareable.
        if (heldBefore != def.shareable) await _restampDancesHolding(id, now);
        if (indexedBefore != await _indexesValues(id)) {
          await onIndexedValuesChanged?.call(id);
        }
      }
      if (localUserEdit) {
        await cancelPendingSyncDeletionForLocalEdit(
          _db,
          kind: SyncRecordKind.customFieldDef,
          recordId: id,
          table: _db.customFieldDefs,
          keyColumn: 'id',
          at: now,
        );
      }
      return id;
    });
  }

  /// Deletes the values that dances in Recently deleted hold for field [id]
  /// once an edit has left them no longer fitting it: every such value when the
  /// type changed from [typeBefore] to [type] (other than between text and
  /// choice, which store the same text), and, for a choice field, any value
  /// that is not one of [choices].
  ///
  /// The trash does not protect what its records use (the maintainer's
  /// trash-policy decision, 2026-10-29, option b), so [isInUse] and
  /// [listUsedChoiceValues] let a field change under a trashed dance. Its value
  /// cannot stay: `encodeCustomFieldValue` refuses a value that does not match
  /// its field, so restoring the dance and saving it would fail, as would a
  /// backup restore or a peer's inbound check of its body, and a text value
  /// under a number type does not even decode. Only trashed dances are touched:
  /// a live dance's value locks the type and its choice in the editor, and this
  /// write is not where that is enforced.
  ///
  /// When the field published its values before this write ([restamp]), each
  /// affected dance's wire body loses one, so its `updated_at` advances as
  /// [_restampDancesHolding] does (sync-spec §6.5 I1). A dance whose value is
  /// kept is not restamped: its body is unchanged.
  Future<void> _dropTrashedValuesThatNoLongerFit(
    String id, {
    required CustomFieldType typeBefore,
    required CustomFieldType type,
    required List<String>? choices,
    required bool restamp,
    required DateTime at,
  }) async {
    const textual = {CustomFieldType.text, CustomFieldType.choice};
    final typeKept =
        typeBefore == type ||
        (textual.contains(typeBefore) && textual.contains(type));
    if (typeKept && type != CustomFieldType.choice) return;
    final values = _db.customFieldValues;
    final rows =
        await (_db.select(values).join([
              innerJoin(
                _db.dances,
                _db.dances.id.equalsExp(values.danceId) &
                    _db.dances.deletedAt.isNotNull(),
                useColumns: false,
              ),
            ])..where(values.fieldId.equals(id)))
            .map((row) => row.readTable(values))
            .get();
    final dropped = [
      for (final row in rows)
        if (!typeKept || !(choices ?? const []).contains(row.valueText))
          row.danceId,
    ];
    if (dropped.isEmpty) return;
    // One JSON array rather than an `IN (?, ?, ...)` list, so a large trash
    // cannot outgrow SQLite's variable limit.
    final droppedJson = jsonEncode(dropped);
    await _db.customUpdate(
      'DELETE FROM custom_field_values '
      'WHERE field_id = ? AND dance_id IN (SELECT value FROM json_each(?))',
      variables: [Variable<String>(id), Variable<String>(droppedJson)],
      updates: {values},
      updateKind: UpdateKind.delete,
    );
    if (!restamp) return;
    // normalization-structure-exempt: writes `updated_at` only, no shareable
    // text.
    await _db.customUpdate(
      // sync-invariant-exclusion: join-hydrated-body the dance body loses a custom-field value its field definition no longer admits.
      'UPDATE dances SET updated_at = MAX(updated_at + 1, ?) '
      'WHERE id IN (SELECT value FROM json_each(?))',
      variables: [
        Variable<int>(unixSeconds(at)),
        Variable<String>(droppedJson),
      ],
      updates: {_db.dances},
      updateKind: UpdateKind.update,
    );
  }

  /// Whether definition [id] currently lets its values onto the wire: a live,
  /// shareable row. This is the per-field term of `allowedCustomFieldIds` in
  /// `CompendiumSyncStorage.snapshot`, and the two must stay in step.
  Future<bool> _publishesValues(String id) async {
    final row = await (_db.select(
      _db.customFieldDefs,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row != null && row.deletedAt == null && row.shareable;
  }

  /// Whether definition [id] currently lets its values into the search bar's
  /// text index: a live row that [customFieldIndexesValueText] admits.
  Future<bool> _indexesValues(String id) async {
    final row = await (_db.select(
      _db.customFieldDefs,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row != null &&
        row.deletedAt == null &&
        customFieldIndexesValueText(row);
  }

  /// Advances `updated_at` on every dance holding a value for [fieldId], live or
  /// tombstoned, to [at] (sync-spec §6.5 I1). A dance already stamped at or
  /// after [at] moves one stored tick past its own stamp instead, so the stamp
  /// never ties or moves backward.
  ///
  /// A dance's wire body carries a custom-field value only while its definition
  /// is live and shareable, so a change to that state changes the body of every
  /// dance holding a value while touching none of their rows. Without a stamp
  /// two devices then carry the same `updatedAt` over different bodies, which
  /// the merge reports as `equalUpdatedAt` and never resolves. Tombstoned dances
  /// are included: they publish the same body shape and keep their values.
  ///
  /// Callers stamp only on a real change to that state, so the stamp always
  /// accompanies a body change (I2). Inbound writes never call this: §6.7 keeps
  /// them off the editor's path.
  Future<void> _restampDancesHolding(String fieldId, DateTime at) {
    assertUtc(at, 'at');
    // normalization-structure-exempt: writes `updated_at` only, no shareable
    // text.
    return _db.customUpdate(
      // sync-invariant-exclusion: join-hydrated-body the dance body changes with its field definition's wire eligibility.
      'UPDATE dances SET updated_at = MAX(updated_at + 1, ?) '
      'WHERE id IN (SELECT dance_id FROM custom_field_values WHERE field_id = ?)',
      variables: [Variable<int>(unixSeconds(at)), Variable<String>(fieldId)],
      updates: {_db.dances},
      updateKind: UpdateKind.update,
    );
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

  Future<List<({CustomFieldDef field, bool deleted})>>
  listAllWithDeleted() async {
    final rows = await (_db.select(
      _db.customFieldDefs,
    )..orderBy([(t) => OrderingTerm(expression: t.label)])).get();
    return [
      for (final row in rows)
        if (toModel(row) case final field?)
          (field: field, deleted: row.deletedAt != null),
    ];
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

  /// Returns `true` if any **live** dance has a value for field [id]; the
  /// editor locks the field's type and key while it does.
  ///
  /// A dance in Recently deleted does not count: the trash does not protect
  /// what its records use (the maintainer's trash-policy decision, 2026-10-29,
  /// option b). Its value is dropped instead if an edit leaves it no longer
  /// fitting the field; see [_dropTrashedValuesThatNoLongerFit].
  Future<bool> isInUse(String id) async =>
      await liveDanceCitationCount(
        _db,
        joinTable: _db.customFieldValues,
        keyColumn: _db.customFieldValues.fieldId,
        danceIdColumn: _db.customFieldValues.danceId,
        id: id,
      ) >
      0;

  /// Returns all distinct text values that **live** dances hold for field [id].
  ///
  /// For `choice` fields this tells you which choices are in use so the editor
  /// can block their removal. A value only a dance in Recently deleted holds
  /// does not block it, as for [isInUse].
  Future<Set<String>> listUsedChoiceValues(String id) async {
    final values = _db.customFieldValues;
    final rows =
        await (_db.selectOnly(values, distinct: true)
              ..addColumns([values.valueText])
              ..join([
                innerJoin(
                  _db.dances,
                  _db.dances.id.equalsExp(values.danceId) &
                      _db.dances.deletedAt.isNull(),
                  useColumns: false,
                ),
              ])
              ..where(values.fieldId.equals(id) & values.valueText.isNotNull()))
            .get();
    return {for (final row in rows) row.read(values.valueText)!};
  }

  /// Throws [CustomFieldInUseException] if any live dance still has a value for
  /// [id] (counted by `liveDanceCitationCount`) — deleting a field
  /// definition out from under populated data would silently strand values
  /// that can no longer be decoded (their type is only known via the def).
  /// The "still used?" check and the delete run inside a single transaction
  /// so no dance can acquire a value for [id] between the check and the
  /// delete (no check-then-act race). Mirrors `VenueRepository.delete`.
  ///
  /// Tombstones by default (schema v25, issue #898); the guard is kept.
  /// [permanent] removes unpublished rows for rollback, while published rows
  /// are tombstoned so peers retain deletion evidence.
  ///
  /// [permanent] also **tombstones rather than erases** whenever any
  /// `custom_field_values` row still names this definition — the case the live
  /// guard below lets through because every such dance is itself tombstoned
  /// (issue #1357). `custom_field_values` is `ON DELETE CASCADE`, so erasing
  /// here would take the tombstoned dance's value with it and restoring that
  /// dance would bring it back with the field empty. See
  /// `ChoreographerRepository.delete` for the full reasoning.
  Future<void> delete(String id, {DateTime? at, bool permanent = false}) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      // Live dances only; a soft-deleted dance keeps its `custom_field_values`
      // rows because the tombstone fires no FK cascade. See the note in
      // `ChoreographerRepository.delete`.
      final stillUsed = await liveDanceCitationCount(
        _db,
        joinTable: _db.customFieldValues,
        keyColumn: _db.customFieldValues.fieldId,
        danceIdColumn: _db.customFieldValues.danceId,
        id: id,
      );
      if (stillUsed > 0) {
        throw CustomFieldInUseException(fieldId: id, danceCount: stillUsed);
      }

      final publishedBefore = await _publishesValues(id);
      if (permanent) {
        // Any surviving `custom_field_values` row — necessarily a tombstoned
        // dance's, since a live one threw above — downgrades the erase to a
        // tombstone rather than cascading that value away (issue #1357).
        final valuedBySurvivor =
            await (_db.select(_db.customFieldValues)
                  ..where((t) => t.fieldId.equals(id))
                  ..limit(1))
                .getSingleOrNull() !=
            null;
        if (valuedBySurvivor ||
            await isPublishedSyncRecord(
              _db,
              kind: SyncRecordKind.customFieldDef,
              recordId: id,
            )) {
          await stampExistenceTransition(
            _db,
            table: _db.customFieldDefs,
            keyColumn: 'id',
            key: id,
            at: now,
            deleted: true,
          );
          if (publishedBefore) await _restampDancesHolding(id, now);
          return;
        }
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
      if (publishedBefore) await _restampDancesHolding(id, now);
    });
  }

  Future<void> restore(
    String id, {
    required DateTime at,
    bool clearPending = true,
  }) => _db.transaction(() async {
    final row = await (_db.select(
      _db.customFieldDefs,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    await stampExistenceTransition(
      _db,
      table: _db.customFieldDefs,
      keyColumn: 'id',
      key: id,
      at: at,
      deleted: false,
    );
    if (row != null && row.deletedAt != null && row.shareable) {
      await _restampDancesHolding(id, at);
    }
    if (clearPending) {
      await clearPendingSyncDeletionForRestore(
        _db,
        kind: SyncRecordKind.customFieldDef,
        recordId: id,
        table: _db.customFieldDefs,
        keyColumn: 'id',
        at: at,
      );
    }
  });

  Future<void> hardDelete(Iterable<String> ids) async {
    for (final id in ids) {
      await delete(id, permanent: true);
    }
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
