/// Commits a planned spreadsheet (CSV) import (#2329): resolves the tags and
/// custom fields the sheet names, then hands the batch to [ImportPipeline].
library;

import '../model/custom_field.dart';
import '../model/enums.dart';
import '../model/dance.dart';
import '../model/tag.dart';
import '../storage/repositories/custom_field_repository.dart';
import '../storage/repositories/tag_repository.dart';
import '../storage/shareable_text.dart';
import 'callers_companion_user_fields.dart' show ccUserFieldKeyForLabel;
import 'csv_adapter.dart';
import 'dedupe.dart';
import 'import_pipeline.dart';

/// A committed CSV import: the pipeline's [session], plus the tags and custom
/// fields the commit created, which [CsvImporter.undo] removes again.
class CsvImportSession {
  CsvImportSession(
    this.session, {
    required List<String> createdTagIds,
    required List<String> createdFieldIds,
  }) : createdTagIds = List.unmodifiable(createdTagIds),
       createdFieldIds = List.unmodifiable(createdFieldIds);

  final ImportSession session;
  final List<String> createdTagIds;
  final List<String> createdFieldIds;
}

/// Writes a planned CSV batch. Nothing is written before [commit]: the plan
/// carries placeholder ids for tags ([kCsvTagPlaceholderPrefix]) and for new
/// custom fields ([kCsvNewFieldPlaceholderPrefix]), and [commit] resolves them
/// first, as `CallersCompanionUsrImporter` does for `.USR` user fields.
///
/// - A tag is matched by name, ignoring case and surrounding space, or
///   created.
/// - A new custom field reuses a field of the same type and label, the
///   caller's own or one an earlier column created; otherwise it is created
///   once, under a key derived from its label and kept distinct from the
///   caller's own keys. A choice field takes, or gains, its choices from the
///   values the committed rows carry.
///
/// If the commit fails, what it created is removed before the error is
/// rethrown. [undo] reverts the dances, then removes the created tags and
/// fields that nothing else uses.
class CsvImporter {
  CsvImporter(this._pipeline, this._tags, this._customFields);

  final ImportPipeline _pipeline;
  final TagRepository _tags;
  final CustomFieldDefRepository _customFields;

  Future<CsvImportSession> commit(
    ImportBatchResult batch, {
    required CsvImportMapping mapping,
    required DateTime now,
    required String Function() newId,
    Map<int, DedupeResolution> resolutions = const {},
    List<String> defaultTagIds = const [],
    void Function(int done, int total)? onProgress,
  }) async {
    final createdTagIds = <String>[];
    final createdFieldIds = <String>[];
    try {
      final tagIdByName = await _resolveTags(batch, newId, createdTagIds);
      final optionSpellings = <String, Map<String, String>>{};
      final fieldIdByColumn = await _createFields(
        batch,
        mapping,
        newId,
        createdFieldIds,
        optionSpellings,
      );
      final rewritten = ImportBatchResult(
        records: [
          for (final plan in batch.records)
            ImportRecordPlan(
              draft: plan.draft.copyWith(
                dance: _rewrite(
                  plan.draft.dance,
                  tagIdByName,
                  fieldIdByColumn,
                  optionSpellings: optionSpellings,
                ),
              ),
              verdict: plan.verdict,
            ),
        ],
        errors: batch.errors,
        warnings: batch.warnings,
        dedupeIndex: batch.dedupeIndex,
      );
      final session = await _pipeline.commit(
        rewritten,
        now: now,
        newId: newId,
        resolutions: resolutions,
        defaultTagIds: defaultTagIds,
        onProgress: onProgress,
      );
      return CsvImportSession(
        session,
        createdTagIds: createdTagIds,
        createdFieldIds: createdFieldIds,
      );
    } on Object {
      await _removeUnused(createdTagIds, createdFieldIds);
      rethrow;
    }
  }

  Future<void> undo(CsvImportSession session) async {
    await _pipeline.undo(session.session);
    await _removeUnused(session.createdTagIds, session.createdFieldIds);
  }

  Future<void> _removeUnused(List<String> tagIds, List<String> fieldIds) async {
    final tags = [
      for (final id in tagIds)
        if (!await _tags.isInUse(id)) id,
    ];
    if (tags.isNotEmpty) await _tags.hardDelete(tags);
    final fields = [
      for (final id in fieldIds)
        if (!await _customFields.isInUse(id)) id,
    ];
    if (fields.isNotEmpty) await _customFields.hardDelete(fields);
  }

  Future<Map<String, String>> _resolveTags(
    ImportBatchResult batch,
    String Function() newId,
    List<String> created,
  ) async {
    final wanted = <String>{
      for (final plan in batch.records)
        for (final id in plan.draft.dance.tagIds)
          if (id.startsWith(kCsvTagPlaceholderPrefix))
            id.substring(kCsvTagPlaceholderPrefix.length),
    };
    if (wanted.isEmpty) return const {};
    final existing = {
      for (final tag in await _tags.listAll()) csvFold(tag.name): tag.id,
    };
    final result = <String, String>{};
    for (final name in wanted) {
      final found = existing[csvFold(name)];
      if (found != null) {
        result[name] = found;
        continue;
      }
      // The repository may adopt a row it already holds under this name (one
      // in Recently deleted, say) and return that row's id. Only a row stored
      // under the fresh id is this commit's own, to remove again.
      final fresh = newId();
      final id = await _tags.upsert(Tag(id: fresh, name: name.trim()));
      if (id == fresh) created.add(id);
      existing[csvFold(name)] = id;
      result[name] = id;
    }
    return result;
  }

  /// Resolves each new-field column to a field, by placeholder. For a choice
  /// field, [optionSpellings] gets, by placeholder, each option's
  /// [_optionKey] → the option as the field spells it, for [_rewrite].
  Future<Map<String, String>> _createFields(
    ImportBatchResult batch,
    CsvImportMapping mapping,
    String Function() newId,
    List<String> created,
    Map<String, Map<String, String>> optionSpellings,
  ) async {
    final result = <String, String>{};
    final existing = [...await _customFields.listAll()];
    final usedKeys = {for (final f in existing) f.key};
    for (var i = 0; i < mapping.columns.length; i++) {
      final column = mapping.columns[i];
      if (column.target != CsvColumnTarget.newCustomField) continue;
      final placeholder = '$kCsvNewFieldPlaceholderPrefix$i';
      final values = [
        for (final plan in batch.records)
          for (final v in plan.draft.dance.customFields)
            if (v.fieldId == placeholder) v.value,
      ];
      if (values.isEmpty) continue;
      final type = column.newFieldType!;
      final label = column.newFieldLabel!.trim();
      // Options that differ only by case or spacing are one option, spelled
      // as first met, as a cell is matched to an existing field's option.
      final byKey = <String, String>{};
      if (type == CustomFieldType.choice) {
        for (final v in values) {
          if (_choiceOption(v.toString()) case final option?) {
            byKey.putIfAbsent(_optionKey(option), () => option);
          }
        }
      }
      // Cells with nothing visible in them make no option, and so no field.
      if (type == CustomFieldType.choice && byKey.isEmpty) continue;
      final choices = byKey.values.toList();
      // A field of this name and type already there (made by an earlier
      // commit from this sheet, such as Import and edit on one row, an
      // earlier column of this one, or the caller's own) is reused rather
      // than doubled; a choice field gains the options it lacks. It is not
      // this commit's to remove.
      final same = existing
          .where((f) => f.type == type && csvFold(f.label) == csvFold(label))
          .firstOrNull;
      if (same != null) {
        final had = {
          for (final c in same.choices ?? const <String>[]) _optionKey(c): c,
        };
        final missing = [
          for (final MapEntry(:key, :value) in byKey.entries)
            if (!had.containsKey(key)) value,
        ];
        if (type == CustomFieldType.choice) {
          optionSpellings[placeholder] = {...byKey, ...had};
        }
        if (missing.isNotEmpty) {
          // An update in place: the id stays the field's own.
          final grown = CustomFieldDef(
            id: same.id,
            key: same.key,
            label: same.label,
            type: same.type,
            choices: [...?same.choices, ...missing],
            showInList: same.showInList,
            searchable: same.searchable,
            shareable: same.shareable,
          );
          final _ = await _customFields.upsert(grown);
          // A later column of this name grows it from here, not from the
          // options it had before.
          existing[existing.indexOf(same)] = grown;
        }
        result[placeholder] = same.id;
        continue;
      }
      var key = ccUserFieldKeyForLabel(label);
      final base = key;
      for (var n = 2; usedKeys.contains(key); n++) {
        key = '${base}_$n';
      }
      usedKeys.add(key);
      if (type == CustomFieldType.choice) optionSpellings[placeholder] = byKey;
      final fresh = newId();
      final id = await _customFields.upsert(
        CustomFieldDef(
          id: fresh,
          key: key,
          label: label,
          type: type,
          choices: type == CustomFieldType.choice ? choices : null,
        ),
      );
      // As for tags: a definition the repository adopted is not this
      // commit's to remove.
      if (id == fresh) created.add(id);
      result[placeholder] = id;
      // A later column of the same name and type, filled on other rows,
      // reuses this one rather than making a second.
      existing.add(
        CustomFieldDef(
          id: id,
          key: key,
          label: label,
          type: type,
          choices: type == CustomFieldType.choice ? choices : null,
        ),
      );
    }
    return result;
  }

  /// [dance] with its placeholders replaced. Only a new *choice* field's
  /// values are normalized as its options were ([_choiceOption]) and written
  /// as the field spells that option ([optionSpellings]); a text field keeps
  /// its value whole.
  Dance _rewrite(
    Dance dance,
    Map<String, String> tagIdByName,
    Map<String, String> fieldIdByPlaceholder, {
    required Map<String, Map<String, String>> optionSpellings,
  }) => dance.copyWith(
    tagIds: [
      ...{
        for (final id in dance.tagIds)
          id.startsWith(kCsvTagPlaceholderPrefix)
              ? tagIdByName[id.substring(kCsvTagPlaceholderPrefix.length)]!
              : id,
      },
    ],
    customFields: [
      for (final v in dance.customFields)
        if (!v.fieldId.startsWith(kCsvNewFieldPlaceholderPrefix))
          v
        else if (fieldIdByPlaceholder[v.fieldId] case final id?)
          if (optionSpellings[v.fieldId] == null || v.value is! String)
            CustomFieldValue(fieldId: id, value: v.value)
          // A cell with nothing visible in it is no option; the row has no
          // value for the field rather than one the field lacks.
          else if (_choiceOption(v.value as String) case final option?)
            CustomFieldValue(
              fieldId: id,
              value: optionSpellings[v.fieldId]![_optionKey(option)] ?? option,
            ),
    ],
  );
}

/// [option] as options are told apart: ignoring case, surrounding space and
/// Unicode form, as a cell is matched to an existing field's option.
String _optionKey(String option) => csvFold(normalizeShareableText(option));

/// A cell's value as an option of a new choice field, spelled as the
/// repository stores one ([normalizeShareableText]), so an option the field
/// already has is matched whatever the cell's Unicode form, and a row's value
/// equals its option. It is trimmed after that spelling (removing an invisible
/// character can leave a space at the edge) and clamped to
/// [kMaxCustomFieldChoiceLength] after it (NFC can lengthen a cell). `null`
/// when nothing visible is left.
String? _choiceOption(String raw) {
  var option = normalizeShareableText(raw).trim();
  if (option.length > kMaxCustomFieldChoiceLength) {
    var end = kMaxCustomFieldChoiceLength;
    // Never end on half of a surrogate pair.
    final last = option.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    option = normalizeShareableText(option.substring(0, end)).trim();
  }
  return option.isEmpty ? null : option;
}
