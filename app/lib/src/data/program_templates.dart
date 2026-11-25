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
/// add a field. Version 2 (#2338) adds one entry kind, the slot rule
/// ([ProgramTemplateEntry.rule]); a template without one is still written as
/// version 1, byte for byte as before.
const String kProgramTemplateKeyPrefix = 'program_template:';

/// The templates' order, as a JSON list of template ids.
///
/// Its presence also marks the legacy Starting program as copied
/// ([materializeProgramTemplates]).
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

/// The value version of a template with only dances, notes and breaks.
const int _programTemplateVersion = 1;

/// The value version of a template with at least one slot rule (#2338).
///
/// Every build that advertises the `programTemplates.v1` sync capability reads
/// it: slot rules joined that capability before any release carried it, so a
/// peer that can be sent a template can read one with rules, and no build
/// that would skip it as unreadable (and so drop it from a backup restore)
/// is ever sent one.
const int _programTemplateVersionWithRules = 2;

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
  var end = trimmed.length;
  if (end > kMaxProgramTemplateNameLength) {
    end = kMaxProgramTemplateNameLength;
    // Never cut inside a surrogate pair.
    final last = trimmed.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
  }
  final name = trimmed.substring(0, end);
  final slots = encodeProgramTemplateSlots(template.entries);
  final hasRule = slots.any((slot) => slot.containsKey('savedSearchId'));
  return jsonEncode({
    'version': hasRule
        ? _programTemplateVersionWithRules
        : _programTemplateVersion,
    'name': name,
    'slots': slots,
  });
}

/// Decodes the value stored for template [id], or `null` when the id or the
/// value is invalid. Strict, so it doubles as the backup validator: unknown
/// fields, an unknown version or any bad slot reject the whole value. A slot
/// rule is accepted only in a version 2 value.
ProgramTemplate? tryDecodeProgramTemplate(String id, Object? stored) {
  if (!isValidProgramTemplateId(id) || stored is! String) return null;
  try {
    final decoded = jsonDecode(stored);
    if (decoded is! Map) return null;
    final version = decoded['version'];
    if (version != _programTemplateVersion &&
        version != _programTemplateVersionWithRules) {
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
    final entries = tryDecodeProgramTemplateSlots(
      decoded['slots'],
      allowRules: version == _programTemplateVersionWithRules,
    );
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

/// The legacy Starting program as the template it becomes, while it has not
/// been written as one: `null` once [kProgramTemplateOrderKey] exists, or when
/// the Starting program is empty or unreadable.
///
/// Its name is empty and shown localized ("Starting program"), so two devices
/// that copy the same Starting program write the same value whatever their
/// language.
Future<ProgramTemplate?> _pendingStartingProgram(
  SettingsRepository settings,
) async {
  if (await settings.contains(kProgramTemplateOrderKey)) return null;
  final legacy = startingProgramTemplateFromStored(
    await settings.get(kDefaultStartingProgramKey),
  );
  if (legacy.isEmpty) return null;
  return ProgramTemplate(
    id: kMigratedStartingProgramTemplateId,
    name: '',
    entries: legacy,
  );
}

/// Writes the legacy Starting program ([kDefaultStartingProgramKey]) as the
/// first program template, as the default if none is set, and writes
/// [kProgramTemplateOrderKey], which marks the copy done.
///
/// Until then [loadProgramTemplates] shows the Starting program as that
/// template without writing anything, so merely opening a screen on a
/// device that has not synced yet cannot write over, or bring back, what a
/// peer already did with it. The copy is written only by the first change the
/// user makes to their templates (every write function here calls this
/// first), stamped at that moment like the change itself, so it resolves
/// against a peer's edits as an ordinary edit does. Running it again, or with
/// an empty Starting program, writes nothing.
///
/// The legacy key is left in place, so a device still on an older build keeps
/// its starting program after a sync.
Future<void> materializeProgramTemplates(SettingsRepository settings) async {
  final pending = await _pendingStartingProgram(settings);
  if (pending == null) return;
  final key = programTemplateKey(pending.id);
  if (!await settings.contains(key)) {
    await settings.set(key, encodeProgramTemplate(pending));
  }
  if (!await settings.contains(kProgramTemplateDefaultKey)) {
    await settings.set(kProgramTemplateDefaultKey, pending.id);
  }
  await settings.set(kProgramTemplateOrderKey, [pending.id]);
}

/// Loads every program template. Writes nothing: a Starting program not yet
/// copied ([materializeProgramTemplates]) is shown as the first template and,
/// unless another default is stored, the default. Unreadable template values
/// are skipped.
Future<ProgramTemplates> loadProgramTemplates(
  SettingsRepository settings,
) async {
  final byId = <String, ProgramTemplate>{};
  for (final key in await settings.keysWithPrefix(kProgramTemplateKeyPrefix)) {
    final id = key.substring(kProgramTemplateKeyPrefix.length);
    final template = tryDecodeProgramTemplate(id, await settings.get(key));
    if (template != null) byId[id] = template;
  }
  var order =
      tryDecodeProgramTemplateOrder(
        await settings.get(kProgramTemplateOrderKey),
      ) ??
      const <String>[];
  var storedDefault = tryDecodeProgramTemplateDefault(
    await settings.get(kProgramTemplateDefaultKey),
  );
  final pending = await _pendingStartingProgram(settings);
  if (pending != null) {
    byId.putIfAbsent(pending.id, () => pending);
    order = [pending.id];
    storedDefault ??= pending.id;
  }
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
  SettingsRepository settings,
) async {
  final templates = await loadProgramTemplates(settings);
  return templates.defaultTemplate?.entries ?? const [];
}

/// Writes [template] under its own key, and only that key (after
/// [materializeProgramTemplates], which writes nothing once the Starting
/// program has been copied).
Future<void> saveProgramTemplate(
  SettingsRepository settings,
  ProgramTemplate template,
) async {
  await materializeProgramTemplates(settings);
  await settings.set(
    programTemplateKey(template.id),
    encodeProgramTemplate(template),
  );
}

/// Writes the templates' order, keeping at most
/// [kMaxProgramTemplateOrderLength] ids (more can exist after two devices
/// add templates at once; the rest then sort after these by name).
Future<void> saveProgramTemplateOrder(
  SettingsRepository settings,
  List<String> ids,
) async {
  await materializeProgramTemplates(settings);
  await settings.set(
    kProgramTemplateOrderKey,
    ids.length > kMaxProgramTemplateOrderLength
        ? ids.sublist(0, kMaxProgramTemplateOrderLength)
        : ids,
  );
}

/// Writes the default template: [id], or Blank program when `null`.
Future<void> saveProgramTemplateDefault(
  SettingsRepository settings,
  String? id,
) async {
  await materializeProgramTemplates(settings);
  await settings.set(
    kProgramTemplateDefaultKey,
    id ?? kProgramTemplateBlankDefault,
  );
}

/// Makes template [id] the default when there is none: no default stored, or
/// one naming a template that no longer exists. So the first template a user
/// creates, or the first after deleting the default, is the one New program
/// starts from (with one template there is no chooser). An explicit Blank
/// program is left alone.
///
/// The check is local: a device that has not yet synced a peer's newer
/// explicit choice writes this one now, and last-writer-wins keeps whichever
/// was written later.
Future<void> saveProgramTemplateDefaultIfUnset(
  SettingsRepository settings,
  String id,
) async {
  await materializeProgramTemplates(settings);
  final stored = tryDecodeProgramTemplateDefault(
    await settings.get(kProgramTemplateDefaultKey),
  );
  if (stored == kProgramTemplateBlankDefault) return;
  if (stored != null && await settings.contains(programTemplateKey(stored))) {
    return;
  }
  await saveProgramTemplateDefault(settings, id);
}

/// Removes template [id]'s key (a tombstone a peer learns from). The order and
/// default keys are left alone, so Undo ([saveProgramTemplate] with the same
/// template) brings it back as the default if it was one and no other
/// template has taken that place since ([saveProgramTemplateDefaultIfUnset]),
/// and in its old place unless the order was rewritten in between (a later
/// reorder, create or duplicate drops it, and it then sorts after the listed
/// ones by name). Until then a missing id in either reads as absent.
Future<void> deleteProgramTemplate(
  SettingsRepository settings,
  String id,
) async {
  await materializeProgramTemplates(settings);
  await settings.remove(programTemplateKey(id));
}

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
///
/// A slot rule becomes an unfilled placeholder ([programSlotForTemplateEntry]).
List<ProgramSlot> programSlotsFromTemplate(
  List<ProgramTemplateEntry> entries, {
  required bool Function(String danceId) danceExists,
}) {
  final slots = <ProgramSlot>[];
  for (final entry in entries) {
    final danceId = entry.danceId;
    if (danceId != null && !danceExists(danceId)) continue;
    slots.add(programSlotForTemplateEntry(entry, position: slots.length));
  }
  return slots;
}

/// A fresh program slot (new id) at [position] for template [entry].
///
/// A slot rule (#2338) becomes a note slot whose text is the rule's label and
/// which remembers the rule's saved search
/// ([ProgramSlot.placeholderSearchId]), so **Fill** works on it from the
/// builder, later and on another device, until a dance is chosen. Its saved
/// search is not read here: one that is gone or names something deleted
/// still gives that plain note with its label, and **Fill** is where the
/// missing criterion is named. Every other entry is copied as it is.
ProgramSlot programSlotForTemplateEntry(
  ProgramTemplateEntry entry, {
  required int position,
}) => ProgramSlot(
  id: uuidV4(),
  position: position,
  danceId: entry.danceId,
  text: entry.text,
  placeholderSearchId: entry.savedSearchId,
);

/// The [SavedSearchUse.kind] of a template's slot rule (#2338).
const String kProgramTemplateSlotRuleUse = 'programTemplateSlotRule';

/// The owner name [registerProgramTemplateSavedSearchUses] registers under.
const String kProgramTemplateSavedSearchUsageOwner = 'programTemplates';

/// Every slot rule in every program template that uses the saved search
/// [savedSearchId], as a [SavedSearchUse]: its label is the rule's label and
/// its detail the template's stored name (empty for an unnamed one, which the
/// message names as the template list does).
Future<List<SavedSearchUse>> programTemplateSlotRuleUses(
  SettingsRepository settings,
  String savedSearchId,
) async {
  final templates = await loadProgramTemplates(settings);
  return [
    for (final template in templates.templates)
      for (final entry in template.entries)
        if (entry.savedSearchId == savedSearchId)
          SavedSearchUse(
            kind: kProgramTemplateSlotRuleUse,
            label: entry.text ?? '',
            detail:
                template.id == kMigratedStartingProgramTemplateId &&
                    template.name.trim().isEmpty
                ? null
                : template.name,
          ),
  ];
}

/// Registers the templates' slot rules as users of saved searches, so deleting
/// a saved search that a slot rule names is refused and the message lists the
/// rule (#2325, "Deleting a saved search that something uses is refused").
///
/// An unfilled placeholder in a program does not count: it is a reminder, not
/// a rule, and **Fill** says so when its saved search is gone.
void registerProgramTemplateSavedSearchUses(CompendiumRepositories repos) {
  final settings = repos.settings;
  repos.savedSearches.usage.register(
    kProgramTemplateSavedSearchUsageOwner,
    (id) => programTemplateSlotRuleUses(settings, id),
  );
}
