import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';

import 'display_defaults.dart';

/// Program templates (#2337): named starting shapes for a new program.
///
/// Each template is its own settings value under
/// [kProgramTemplateKeyPrefix]`<id>`, so two devices editing *different*
/// templates never conflict, and two edits to the same template resolve as
/// one settings key does. Two exact keys sit beside them: the templates' order
/// ([kProgramTemplateOrderKey], a list of ids, so a reorder rewrites one key)
/// and the default template ([kProgramTemplateDefaultKey], an id or
/// [kProgramTemplateBlankDefault]).
///
/// A template's slots use the same entry codec as the legacy Starting program
/// ([encodeProgramTemplateSlots]); its value is versioned so a later change can
/// add a field.
const String kProgramTemplateKeyPrefix = 'program_template:';

/// The templates' order, as a JSON list of template ids.
///
/// Its presence also marks the one-time Starting program migration as done
/// ([migrateStartingProgramToTemplates]).
const String kProgramTemplateOrderKey = 'program_template_order';

/// The id of the template a program created outside the New program chooser
/// starts from, or [kProgramTemplateBlankDefault].
const String kProgramTemplateDefaultKey = 'program_template_default';

/// The [kProgramTemplateDefaultKey] value meaning "Blank program".
const String kProgramTemplateBlankDefault = 'blank';

/// The id the migrated Starting program gets. Fixed rather than random, so two
/// devices that both migrate the same synced Starting program write the same
/// key with the same value instead of two copies of it.
const String kMigratedStartingProgramTemplateId = 'starting_program';

const int _programTemplateVersion = 1;

/// The longest template name kept; a longer one is cut on encode and rejected
/// on decode.
const int kMaxProgramTemplateNameLength = 100;

/// The most template ids the order key holds.
const int kMaxProgramTemplateOrderLength = 200;

final RegExp _templateIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// Whether [id] can name a template's settings key: 1 to 64 letters, digits,
/// `_` or `-` (a UUID, or [kMigratedStartingProgramTemplateId]).
bool isValidProgramTemplateId(String id) => _templateIdPattern.hasMatch(id);

/// The settings key holding template [id].
String programTemplateKey(String id) => '$kProgramTemplateKeyPrefix$id';

/// A named program template: an ordered list of slot entries.
class ProgramTemplate {
  const ProgramTemplate({
    required this.id,
    required this.name,
    this.entries = const [],
  });

  final String id;
  final String name;
  final List<ProgramTemplateEntry> entries;

  ProgramTemplate copyWith({
    String? name,
    List<ProgramTemplateEntry>? entries,
  }) => ProgramTemplate(
    id: id,
    name: name ?? this.name,
    entries: entries ?? this.entries,
  );
}

/// Encodes [template]'s value (its id is the key, not part of the value).
String encodeProgramTemplate(ProgramTemplate template) {
  final trimmed = template.name.trim();
  final name = trimmed.length > kMaxProgramTemplateNameLength
      ? trimmed.substring(0, kMaxProgramTemplateNameLength)
      : trimmed;
  return jsonEncode({
    'version': _programTemplateVersion,
    'name': name,
    'slots': encodeProgramTemplateSlots(template.entries),
  });
}

/// Decodes the value stored for template [id], or `null` when the id or the
/// value is invalid. Strict, so it doubles as the backup validator: unknown
/// fields, an unknown version or any bad slot reject the whole value.
ProgramTemplate? tryDecodeProgramTemplate(String id, Object? stored) {
  if (!isValidProgramTemplateId(id) || stored is! String) return null;
  try {
    final decoded = jsonDecode(stored);
    if (decoded is! Map || decoded['version'] != _programTemplateVersion) {
      return null;
    }
    if (!decoded.keys.every(
      (key) => key == 'version' || key == 'name' || key == 'slots',
    )) {
      return null;
    }
    final name = decoded['name'];
    if (name is! String || name.length > kMaxProgramTemplateNameLength) {
      return null;
    }
    final entries = tryDecodeProgramTemplateSlots(decoded['slots']);
    if (entries == null) return null;
    return ProgramTemplate(id: id, name: name, entries: entries);
  } catch (_) {
    // diagnostics: silent — malformed settings data returns null.
    return null;
  }
}

/// Decodes the order key: a list of distinct valid template ids, or `null`.
List<String>? tryDecodeProgramTemplateOrder(Object? stored) {
  if (stored is! List || stored.length > kMaxProgramTemplateOrderLength) {
    return null;
  }
  final ids = <String>[];
  final seen = <String>{};
  for (final raw in stored) {
    if (raw is! String || !isValidProgramTemplateId(raw) || !seen.add(raw)) {
      return null;
    }
    ids.add(raw);
  }
  return ids;
}

/// Decodes the default key: a template id or [kProgramTemplateBlankDefault],
/// or `null` when it is neither.
String? tryDecodeProgramTemplateDefault(Object? stored) {
  if (stored is! String) return null;
  if (stored == kProgramTemplateBlankDefault) return stored;
  return isValidProgramTemplateId(stored) ? stored : null;
}

/// The templates in the order the user chose, with the default.
class ProgramTemplates {
  const ProgramTemplates({required this.templates, this.defaultId});

  static const ProgramTemplates empty = ProgramTemplates(templates: []);

  /// Every readable template, in the user's order: those the order key lists,
  /// in its order, then any it does not (a template that arrived by sync
  /// before its order did), by name and then id.
  final List<ProgramTemplate> templates;

  /// The default template's id, or `null` for Blank program. Never names a
  /// template missing from [templates]: a default whose template is gone
  /// reads as Blank program.
  final String? defaultId;

  ProgramTemplate? get defaultTemplate {
    for (final template in templates) {
      if (template.id == defaultId) return template;
    }
    return null;
  }

  ProgramTemplate? byId(String id) {
    for (final template in templates) {
      if (template.id == id) return template;
    }
    return null;
  }

  /// [templates] with the default first, for the New program chooser.
  List<ProgramTemplate> get defaultFirst {
    final chosen = defaultTemplate;
    if (chosen == null) return templates;
    return [
      chosen,
      for (final t in templates)
        if (t.id != chosen.id) t,
    ];
  }
}

/// Puts [byId] in the order [order] gives, followed by any template it does
/// not list, by name (case-insensitive) and then id.
List<ProgramTemplate> orderProgramTemplates(
  Map<String, ProgramTemplate> byId,
  List<String> order,
) {
  final result = <ProgramTemplate>[];
  final placed = <String>{};
  for (final id in order) {
    final template = byId[id];
    if (template != null && placed.add(id)) result.add(template);
  }
  final rest =
      [
        for (final entry in byId.entries)
          if (!placed.contains(entry.key)) entry.value,
      ]..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
  return [...result, ...rest];
}

/// The time every Starting program migration write is stamped at. It is older
/// than any edit a user can make, so a device that migrates late never
/// overwrites a template, order or default a peer already edited: under
/// last-writer-wins any real edit is newer and wins.
final DateTime kProgramTemplateMigrationStamp = DateTime.utc(2000);

/// Copies a non-empty legacy Starting program ([kDefaultStartingProgramKey])
/// into the first program template, named [migratedName], and makes it the
/// default. Writing [kProgramTemplateOrderKey] last marks it done, so an
/// interrupted run is retried and a completed one never repeats. An empty or
/// unreadable Starting program writes nothing, and is checked again on the
/// next load, in case a peer on an older build syncs one in.
///
/// Every write is stamped at [kProgramTemplateMigrationStamp], not now.
///
/// The legacy key is left in place, so a device still on an older build keeps
/// its starting program after a sync.
Future<void> migrateStartingProgramToTemplates(
  SettingsRepository settings, {
  required String migratedName,
}) async {
  if (await settings.contains(kProgramTemplateOrderKey)) return;
  final legacy = startingProgramTemplateFromStored(
    await settings.get(kDefaultStartingProgramKey),
  );
  if (legacy.isEmpty) return;
  const id = kMigratedStartingProgramTemplateId;
  final at = kProgramTemplateMigrationStamp;
  // A peer that migrated first may already have written this template; its
  // value is the same Starting program, so only an absent one is written.
  if (!await settings.contains(programTemplateKey(id))) {
    await settings.set(
      programTemplateKey(id),
      encodeProgramTemplate(
        ProgramTemplate(id: id, name: migratedName, entries: legacy),
      ),
      at: at,
    );
  }
  if (!await settings.contains(kProgramTemplateDefaultKey)) {
    await settings.set(kProgramTemplateDefaultKey, id, at: at);
  }
  await settings.set(kProgramTemplateOrderKey, const [id], at: at);
}

/// Loads every program template, after running the one-time migration.
///
/// [migratedName] is the localized name the migrated Starting program gets
/// ("Starting program"). Unreadable template values are skipped.
Future<ProgramTemplates> loadProgramTemplates(
  SettingsRepository settings, {
  required String migratedName,
}) async {
  await migrateStartingProgramToTemplates(settings, migratedName: migratedName);
  final byId = <String, ProgramTemplate>{};
  for (final key in await settings.keysWithPrefix(kProgramTemplateKeyPrefix)) {
    final id = key.substring(kProgramTemplateKeyPrefix.length);
    final template = tryDecodeProgramTemplate(id, await settings.get(key));
    if (template != null) byId[id] = template;
  }
  final order =
      tryDecodeProgramTemplateOrder(
        await settings.get(kProgramTemplateOrderKey),
      ) ??
      const <String>[];
  final storedDefault = tryDecodeProgramTemplateDefault(
    await settings.get(kProgramTemplateDefaultKey),
  );
  return ProgramTemplates(
    templates: orderProgramTemplates(byId, order),
    defaultId: storedDefault != null && byId.containsKey(storedDefault)
        ? storedDefault
        : null,
  );
}

/// The slot entries of the **Default template**, or none for Blank program:
/// the one function a program created outside the New program flow (the
/// calendar import, #2352) calls for its starting shape.
Future<List<ProgramTemplateEntry>> defaultProgramTemplateEntries(
  SettingsRepository settings, {
  required String migratedName,
}) async {
  final templates = await loadProgramTemplates(
    settings,
    migratedName: migratedName,
  );
  return templates.defaultTemplate?.entries ?? const [];
}

/// Writes [template] under its own key, and only that key.
Future<void> saveProgramTemplate(
  SettingsRepository settings,
  ProgramTemplate template,
) => settings.set(
  programTemplateKey(template.id),
  encodeProgramTemplate(template),
);

/// Writes the templates' order.
Future<void> saveProgramTemplateOrder(
  SettingsRepository settings,
  List<String> ids,
) => settings.set(kProgramTemplateOrderKey, ids);

/// Writes the default template: [id], or Blank program when `null`.
Future<void> saveProgramTemplateDefault(
  SettingsRepository settings,
  String? id,
) => settings.set(
  kProgramTemplateDefaultKey,
  id ?? kProgramTemplateBlankDefault,
);

/// Makes template [id] the default when no default has ever been chosen, so
/// the first template a user creates is the one New program starts from
/// (with one template there is no chooser). An explicit Blank program, or a
/// default naming a deleted template, is left alone.
Future<void> saveProgramTemplateDefaultIfUnset(
  SettingsRepository settings,
  String id,
) async {
  if (await settings.contains(kProgramTemplateDefaultKey)) return;
  await saveProgramTemplateDefault(settings, id);
}

/// Removes template [id]'s key (a tombstone a peer learns from). The order and
/// default keys are left alone, so Undo ([saveProgramTemplate] with the same
/// template) brings it back as the default if it was one, and in its old
/// place unless the order was rewritten in between (a later reorder, create
/// or duplicate drops it, and it then sorts after the listed ones by name).
/// Until then a missing id in either reads as absent.
Future<void> deleteProgramTemplate(SettingsRepository settings, String id) =>
    settings.remove(programTemplateKey(id));

/// Which template a new program from the builder starts from.
class ProgramTemplateChoice {
  /// The Default template (Blank program when none is set).
  const ProgramTemplateChoice.useDefault() : templateId = null, blank = false;

  /// Blank program.
  const ProgramTemplateChoice.blank() : templateId = null, blank = true;

  /// Template [templateId].
  const ProgramTemplateChoice.template(String this.templateId) : blank = false;

  final String? templateId;
  final bool blank;

  @override
  bool operator ==(Object other) =>
      other is ProgramTemplateChoice &&
      other.templateId == templateId &&
      other.blank == blank;

  @override
  int get hashCode => Object.hash(templateId, blank);
}

/// The entries [choice] resolves to in [templates]. A template that is no
/// longer there gives none.
List<ProgramTemplateEntry> programTemplateEntriesFor(
  ProgramTemplates templates,
  ProgramTemplateChoice choice,
) {
  if (choice.blank) return const [];
  final id = choice.templateId;
  final template = id == null ? templates.defaultTemplate : templates.byId(id);
  return template?.entries ?? const [];
}

/// Fresh program slots for template [entries]: a new id and position for each,
/// skipping a dance no longer in the collection ([danceExists]) while the
/// others keep their order.
List<ProgramSlot> programSlotsFromTemplate(
  List<ProgramTemplateEntry> entries, {
  required bool Function(String danceId) danceExists,
}) {
  final slots = <ProgramSlot>[];
  for (final entry in entries) {
    final danceId = entry.danceId;
    if (danceId != null && !danceExists(danceId)) continue;
    slots.add(
      ProgramSlot(
        id: uuidV4(),
        position: slots.length,
        danceId: danceId,
        text: entry.text,
      ),
    );
  }
  return slots;
}
