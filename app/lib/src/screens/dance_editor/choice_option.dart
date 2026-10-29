import 'package:compendium_core/compendium_core.dart';

/// Result of an inline add-an-option attempt on a `choice` custom field, so the
/// UI can report why an add did nothing. Shared by the dance editor
/// ([DanceEditorController.addChoiceOption]) and the Collection's batch
/// edit-custom-field dialog.
enum AddChoiceResult { added, empty, duplicate, notFound }

/// Appends [raw] as a new option to the `choice` field [def] and persists the
/// definition, so the option round-trips through backup/export like any other.
///
/// OWASP input discipline: [normalizeChoiceOption] trims and soft-clamps the
/// raw value to [kMaxCustomFieldChoiceLength]; an empty result is rejected
/// ([AddChoiceResult.empty]) and a case-sensitive duplicate of an existing
/// option is rejected ([AddChoiceResult.duplicate]). A non-`choice` [def] is
/// [AddChoiceResult.notFound]. Only [AddChoiceResult.added] carries the updated
/// definition and the normalized option that was added.
Future<({AddChoiceResult result, CustomFieldDef? def, String? option})>
addChoiceOptionToDef(
  CompendiumRepositories repos,
  CustomFieldDef def,
  String raw,
) async {
  if (def.type != CustomFieldType.choice) {
    return (result: AddChoiceResult.notFound, def: null, option: null);
  }
  final normalized = normalizeChoiceOption(raw);
  if (normalized == null) {
    return (result: AddChoiceResult.empty, def: null, option: null);
  }
  final existing = def.choices ?? const <String>[];
  if (existing.contains(normalized)) {
    return (result: AddChoiceResult.duplicate, def: null, option: null);
  }

  final updated = CustomFieldDef(
    id: def.id,
    key: def.key,
    label: def.label,
    type: def.type,
    choices: [...existing, normalized],
    showInList: def.showInList,
    searchable: def.searchable,
    // Preserve the privacy flag: the constructor defaults to `true`, so
    // omitting it would silently make a private field shareable.
    shareable: def.shareable,
  );
  // Safe discard: `updated` is built from `def.id` (an already-persisted row),
  // not a fresh UUID. Tombstone adoption requires a minting caller; it cannot
  // fire here, so the returned id is always identical to updated.id.
  // ignore: unused_result
  await repos.customFieldDefs.upsert(updated, localUserEdit: true);
  return (result: AddChoiceResult.added, def: updated, option: normalized);
}
