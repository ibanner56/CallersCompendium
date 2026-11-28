import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';

import '../diagnostics/error_log.dart';
import 'display_defaults.dart';
import 'event_rules_scope.dart' show kEventRulesEnabledKey;

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
/// version 1, byte for byte as before. Version 3 (#2342) adds one top-level
/// field, `eventRuleIds`, the event rules a program made from the template
/// starts with ([ProgramTemplate.eventRuleIds]); a template without one is
/// still written as version 1 or 2, byte for byte as before.
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

/// The value version of a template with at least one event rule (#2342), in
/// its top-level `eventRuleIds`.
///
/// A template holding event rules waits for `eventRules.v1` as well as
/// `programTemplates.v1` (`SyncCapabilityPolicy.gatedSettingValueFields`), so
/// no build without event rules is sent one. Event-rule ids joined templates
/// before any release carried either capability, so a build that advertises
/// both reads it as long as no release carries event rules without this. A
/// build that cannot read it skips the template and never writes it, so the
/// value is kept whole rather than rewritten without the field.
const int _programTemplateVersionWithEventRules = 3;

/// The top-level field of a template value listing its event rules (#2342).
///
/// The sync capability gate names it too (`gatedSettingValueFields` in
/// `SyncCapabilityPolicy.build`), so a template holding rules waits for
/// `eventRules.v1`.
const String kProgramTemplateEventRuleIdsField = 'eventRuleIds';

/// The longest event-rule id a template keeps (#2342): the longest an
/// `eventRule` record's id may be in sync (`sync_event_rule_body.dart`), so
/// a rule this device holds can be put on a template.
const int kMaxProgramTemplateEventRuleIdLength = 200;

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

/// A named program template: an ordered list of slot entries, and the event
/// rules a program made from it starts with.
class ProgramTemplate {
  const ProgramTemplate({
    required this.id,
    required this.name,
    this.entries = const [],
    this.eventRuleIds = const [],
  });

  final String id;
  final String name;
  final List<ProgramTemplateEntry> entries;

  /// The ids of the event rules (#2340) a program made from this template
  /// starts with applied (#2342), in order. Kept whatever the Experimental
  /// Event rules toggle says, and whether or not each rule is still live: a
  /// rule that is deleted or not on this device is skipped when a program is
  /// made ([newProgramEventRuleIds]), and an Undo of its delete
  /// brings it back here too. Written normalized ([normalizeEventRuleIds]).
  final List<String> eventRuleIds;

  /// A copy with the fields given replaced; every other field, the event
  /// rules included, is kept, so a write that does not edit them (a rename,
  /// or the editor while Event rules is off) never drops them.
  ProgramTemplate copyWith({
    String? name,
    List<ProgramTemplateEntry>? entries,
    List<String>? eventRuleIds,
  }) => ProgramTemplate(
    id: id,
    name: name ?? this.name,
    entries: entries ?? this.entries,
    eventRuleIds: eventRuleIds ?? this.eventRuleIds,
  );
}

/// [ids] as a template keeps them: [normalizeEventRuleIds], less any id longer
/// than [kMaxProgramTemplateEventRuleIdLength], so the result always decodes.
List<String> _normalizeTemplateEventRuleIds(List<String> ids) =>
    normalizeEventRuleIds([
      for (final id in ids)
        if (id.trim().isNotEmpty &&
            id.length <= kMaxProgramTemplateEventRuleIdLength)
          id,
    ]);

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
  final eventRuleIds = _normalizeTemplateEventRuleIds(template.eventRuleIds);
  return jsonEncode({
    'version': eventRuleIds.isNotEmpty
        ? _programTemplateVersionWithEventRules
        : hasRule
        ? _programTemplateVersionWithRules
        : _programTemplateVersion,
    'name': name,
    'slots': slots,
    // Last, and only when there is one, so a template without event rules is
    // the version 1 or 2 value it always was.
    if (eventRuleIds.isNotEmpty)
      kProgramTemplateEventRuleIdsField: eventRuleIds,
  });
}

/// Decodes the value stored for template [id], or `null` when the id or the
/// value is invalid. Strict, so it doubles as the backup validator: unknown
/// fields, an unknown version or any bad slot reject the whole value. A slot
/// rule is accepted only in a version 2 or 3 value, and `eventRuleIds` only in
/// a version 3 value, as a list of 1 to [maxProgramEventRules] distinct
/// non-blank ids of at most [kMaxProgramTemplateEventRuleIdLength] units.
ProgramTemplate? tryDecodeProgramTemplate(String id, Object? stored) {
  if (!isValidProgramTemplateId(id) || stored is! String) return null;
  try {
    final decoded = jsonDecode(stored);
    if (decoded is! Map) return null;
    final version = decoded['version'];
    if (version != _programTemplateVersion &&
        version != _programTemplateVersionWithRules &&
        version != _programTemplateVersionWithEventRules) {
      return null;
    }
    final withEventRules = version == _programTemplateVersionWithEventRules;
    if (!decoded.keys.every(
      (key) =>
          key == 'version' ||
          key == 'name' ||
          key == 'slots' ||
          (withEventRules && key == kProgramTemplateEventRuleIdsField),
    )) {
      return null;
    }
    final name = decoded['name'];
    if (name is! String || name.length > kMaxProgramTemplateNameLength) {
      return null;
    }
    final entries = tryDecodeProgramTemplateSlots(
      decoded['slots'],
      allowRules: version != _programTemplateVersion,
    );
    if (entries == null) return null;
    var eventRuleIds = const <String>[];
    if (withEventRules) {
      final decodedIds = _tryDecodeTemplateEventRuleIds(
        decoded[kProgramTemplateEventRuleIdsField],
      );
      if (decodedIds == null) return null;
      eventRuleIds = decodedIds;
    }
    return ProgramTemplate(
      id: id,
      name: name,
      entries: entries,
      eventRuleIds: eventRuleIds,
    );
  } catch (_) {
    // diagnostics: silent — malformed settings data returns null.
    return null;
  }
}

/// A version 3 template's `eventRuleIds`, or `null` unless it is a list of 1
/// to [maxProgramEventRules] distinct non-blank strings of at most
/// [kMaxProgramTemplateEventRuleIdLength] units: exactly what
/// [encodeProgramTemplate] writes.
List<String>? _tryDecodeTemplateEventRuleIds(Object? raw) {
  if (raw is! List || raw.isEmpty || raw.length > maxProgramEventRules) {
    return null;
  }
  final ids = <String>[];
  final seen = <String>{};
  for (final id in raw) {
    if (id is! String ||
        id.trim().isEmpty ||
        id.length > kMaxProgramTemplateEventRuleIdLength ||
        !seen.add(id)) {
      return null;
    }
    ids.add(id);
  }
  return List.unmodifiable(ids);
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
  /// (the Default template was deleted) reads as the first template, so New
  /// program, which asks nothing with one template, and the calendar import
  /// still start from one (pre-release audit finding D1a-01). Only with no
  /// template left, an explicit Blank program or no default ever stored is
  /// it Blank program.
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
/// not list, by name (case- and accent-insensitive, [foldForTitleMatch]) and
/// then id.
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
        final byName = foldForTitleMatch(
          a.name,
        ).compareTo(foldForTitleMatch(b.name));
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
/// unless another default is stored, the default; a stored default whose
/// template is gone reads as the first template ([ProgramTemplates.defaultId])
/// while the key keeps naming the deleted one, so Undo of the delete gives it
/// back. Unreadable template values are skipped.
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
  final templates = orderProgramTemplates(byId, order);
  return ProgramTemplates(
    templates: templates,
    defaultId: switch (storedDefault) {
      null || kProgramTemplateBlankDefault => null,
      final id when byId.containsKey(id) => id,
      _ => templates.firstOrNull?.id,
    },
  );
}

/// The **Default template**, or `null` for Blank program: the one function a
/// program created outside the New program flow (the calendar import, #2352)
/// calls for its starting shape, its slots and ([newProgramEventRuleIds]) its
/// event rules.
Future<ProgramTemplate?> defaultProgramTemplate(
  SettingsRepository settings,
) async => (await loadProgramTemplates(settings)).defaultTemplate;

/// The slot entries of the **Default template** ([defaultProgramTemplate]),
/// or none for Blank program.
Future<List<ProgramTemplateEntry>> defaultProgramTemplateEntries(
  SettingsRepository settings,
) async => (await defaultProgramTemplate(settings))?.entries ?? const [];

/// The event rules a new program made from [template] starts with applied
/// (#2342): every rule [ProgramTemplate.eventRuleIds] lists that is live on
/// this device, in the template's order; none for no template (Blank
/// program), or while the Experimental Event rules toggle
/// ([kEventRulesEnabledKey]) is off.
///
/// The one function both ways a program is made from a template call: **New
/// program** and the Default template's use outside it (the calendar
/// import). Choosing a template that carries rules is the caller adding them,
/// so they are copied onto the program as it is made; a later edit to the
/// template changes no program. A rule that is deleted, or not on this device
/// yet, is skipped, and the template keeps it.
///
/// Never throws: a failed read starts the program with no rules (and is
/// logged), so it cannot cost the program the template's slots.
Future<List<String>> newProgramEventRuleIds(
  CompendiumRepositories repos,
  ProgramTemplate? template,
) async {
  final ids = template?.eventRuleIds ?? const <String>[];
  if (ids.isEmpty) return const [];
  try {
    if (await repos.settings.get(kEventRulesEnabledKey) != true) {
      return const [];
    }
    final live = await repos.eventRules.getMany(ids);
    return normalizeEventRuleIds([for (final rule in live) rule.id]);
  } catch (error, stackTrace) {
    logCaughtError(
      error,
      stackTrace,
      source: 'program_templates.new_program_rules',
    );
    return const [];
  }
}

/// Which of a template's slot rules [saveProgramTemplate] checks name a saved
/// search that is stored (#2529): a slot rule cannot start using one that is
/// not.
enum SlotRuleSearchCheck {
  /// None: the slot rules are written as they are (an Undo, which brings
  /// rules back rather than starting them).
  none,

  /// Those the stored copy of the template does not already name: the
  /// template editor's saves, so a template whose search was deleted since
  /// can still be renamed. With no stored copy (the template was deleted
  /// elsewhere while its editor was open), none, and the template is written
  /// back.
  added,

  /// Every one: a copy (**Duplicate**), whose every slot rule is a new use.
  all,
}

/// Writes [template] under its own key, and only that key (after
/// [materializeProgramTemplates], which writes nothing once the Starting
/// program has been copied).
///
/// Unless [checkSlotRules] is [SlotRuleSearchCheck.none], the slot rules it
/// selects are checked to name a stored saved search, in one transaction with
/// the write, and [SavedSearchGone] is thrown, writing nothing, for the first
/// that does not.
Future<void> saveProgramTemplate(
  SettingsRepository settings,
  ProgramTemplate template, {
  SlotRuleSearchCheck checkSlotRules = SlotRuleSearchCheck.none,
}) async {
  await materializeProgramTemplates(settings);
  final key = programTemplateKey(template.id);
  if (checkSlotRules == SlotRuleSearchCheck.none) {
    await settings.set(key, encodeProgramTemplate(template));
    return;
  }
  await settings.transaction(() async {
    final Set<String> named;
    if (checkSlotRules == SlotRuleSearchCheck.all) {
      named = const {};
    } else {
      final stored = tryDecodeProgramTemplate(
        template.id,
        await settings.get(key),
      );
      if (stored == null) {
        // Deleted elsewhere while the editor was open (or unreadable): there
        // is no stored copy to tell a new slot rule from an old one, so the
        // write goes through as it did before, bringing the template back.
        await settings.set(key, encodeProgramTemplate(template));
        return;
      }
      named = {for (final entry in stored.entries) ?entry.savedSearchId};
    }
    for (final entry in template.entries) {
      final id = entry.savedSearchId;
      if (id == null || named.contains(id)) continue;
      if (!await isSavedSearchStored(settings, id)) throw SavedSearchGone(id);
    }
    await settings.set(key, encodeProgramTemplate(template));
  });
}

/// [entries] with the slot rules a refused save added or changed to name the
/// saved search [goneId] undone (#2529): a rule that [editedFrom] maps to the
/// entry it replaced goes back to that entry, in its place, and one added is
/// removed. A slot rule naming [goneId] that the stored copy already names
/// ([storedSearchIds]) is kept, and so is every other entry, so an edit made
/// after the refused save is not lost. Returns `null` when nothing changed.
List<ProgramTemplateEntry>? undoSlotRulesNaming(
  List<ProgramTemplateEntry> entries,
  String goneId, {
  required Set<String> storedSearchIds,
  required Map<ProgramTemplateEntry, ProgramTemplateEntry> editedFrom,
}) {
  if (storedSearchIds.contains(goneId)) return null;
  var changed = false;
  final next = <ProgramTemplateEntry>[];
  for (final entry in entries) {
    if (entry.savedSearchId != goneId) {
      next.add(entry);
      continue;
    }
    changed = true;
    final original = editedFrom[entry];
    if (original != null) next.add(original);
  }
  return changed ? next : null;
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
/// creates is the one New program starts from (with one template there is no
/// chooser). After the default was deleted, the template already standing in
/// for it ([ProgramTemplates.defaultId], the first in the list) is written
/// instead, so creating a template does not move the default; [id] is written
/// only when it is the one template. An explicit Blank program is left alone.
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
  final standIn = stored == null
      ? null
      : (await loadProgramTemplates(settings)).defaultId;
  await saveProgramTemplateDefault(settings, standIn ?? id);
}

/// Removes template [id]'s key (a tombstone a peer learns from). The order and
/// default keys are left alone, so Undo ([saveProgramTemplate] with the same
/// template) brings it back as the default if it was one and no other
/// template has taken that place since ([saveProgramTemplateDefaultIfUnset]),
/// and in its old place unless the order was rewritten in between (a later
/// reorder, create or duplicate drops it, and it then sorts after the listed
/// ones by name). Until then a missing id in the order reads as absent, and
/// a default naming it reads as the first template left
/// ([ProgramTemplates.defaultId]).
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

/// The template [choice] resolves to in [templates], or `null` for Blank
/// program or a template that is no longer there.
ProgramTemplate? programTemplateFor(
  ProgramTemplates templates,
  ProgramTemplateChoice choice,
) {
  if (choice.blank) return null;
  final id = choice.templateId;
  return id == null ? templates.defaultTemplate : templates.byId(id);
}

/// The entries [choice] resolves to in [templates] ([programTemplateFor]). A
/// template that is no longer there gives none.
List<ProgramTemplateEntry> programTemplateEntriesFor(
  ProgramTemplates templates,
  ProgramTemplateChoice choice,
) => programTemplateFor(templates, choice)?.entries ?? const [];

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
