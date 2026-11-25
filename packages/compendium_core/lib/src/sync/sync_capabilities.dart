import 'dart:convert';

import '../search/saved_search.dart' show savedSearchKeyPrefix;
import 'sync_record_kind.dart';

/// The settings-key prefix of a device's capability record (#709):
/// `sync_capabilities:<deviceId>`, whose value is
/// `{"capabilities": ["glossary.v1", …]}`.
///
/// Each device writes only its own, except that removing a device from the
/// store tombstones the removed device's record (sync-spec §6.15). It travels
/// as an ordinary `setting`
/// record, which every build since v0.7.0 keeps whole when it does not know
/// the key (ADR-004), so advertising is safe to older peers.
const String syncCapabilityKeyPrefix = 'sync_capabilities:';

/// The settings key of [deviceId]'s capability record.
String syncCapabilityRecordKey(String deviceId) =>
    '$syncCapabilityKeyPrefix$deviceId';

/// The named sync capabilities (#709). A capability names a set of record
/// kinds and settings keys an older build cannot hold; data gated on it is
/// published only once every device attached to the store says it
/// understands it. Named, not numbered, so features can ship in any order.
abstract final class SyncCapabilities {
  /// User glossary entries, notes on shipped figures, and their settings.
  static const String glossaryV1 = 'glossary.v1';

  /// The user's own terms and figures (#1023): glossary entries of the
  /// `term` and `customFigure` kinds. A build that only understands
  /// [glossaryV1] reads such an entry as one it cannot use, so they wait for
  /// every device to understand this too.
  static const String glossaryV2 = 'glossary.v2';

  /// The user's saved searches (#2325), one settings value each under
  /// `saved_search:`. An older build keeps such a value whole but cannot read
  /// it, so they wait for every device to understand them.
  static const String savedSearchesV1 = 'savedSearches.v1';

  /// Program templates (#2337): one settings value per template
  /// (`program_template:<id>`), their order and the default template. An
  /// older build only knows the single Starting program, so it would keep
  /// these keys whole without using them; they wait so a peer is never shown
  /// a "template" it cannot apply.
  static const String programTemplatesV1 = 'programTemplates.v1';

  /// Suggestions (#2343): the Experimental Suggestions toggle
  /// (`suggestions_enabled`), what suggestions look for
  /// (`suggestion_settings`) and whether Perform's swap sheet orders by them
  /// (`suggestions_in_perform_swap`, #2348). An older build has no Suggested
  /// sort, so it would keep these keys without using them; they wait so a
  /// peer never holds a setting it cannot show or edit.
  static const String suggestionsV1 = 'suggestions.v1';

  /// Perform's **Swap a dance** defaults (#2346): which Keep items start on
  /// (`perform_swap_defaults`). An older build has no swap sheet, so it would
  /// keep the key without using it; it waits so a peer never holds a setting
  /// it cannot show or edit.
  static const String performSwapV1 = 'performSwap.v1';

  /// Event rules (#2340): every `eventRule` record, the Experimental Event
  /// rules toggle (`event_rules_enabled`), the rule picker's order
  /// (`event_rule_order`, #2341) and whether Perform's swap sheet checks the
  /// rules (`event_rules_check_perform_swap`, #2347); both joined it while it
  /// was unreleased: one capability per feature. An older build has no
  /// `event_rules` table, so it could only keep such a record whole without
  /// using it; they wait so a peer never holds a rule it cannot show, edit or
  /// check. A program's applied rule ids (`eventRuleIds`) are not gated:
  /// they are a top-level field of the `program` record, which an older build
  /// keeps as a kept part (sync-spec §6.7). A program template that carries
  /// rules (#2342, a non-empty `eventRuleIds` in its value) waits for this as
  /// well as [programTemplatesV1] ([SyncCapabilityPolicy.gatedSettingValueFields]).
  static const String eventRulesV1 = 'eventRules.v1';

  /// Weekends and series (#2349): the Experimental toggle
  /// (`weekends_and_series_enabled`). An older build has no combined view, so
  /// it would keep the key without using it; it waits so a peer never holds
  /// a setting it cannot show or edit. Nothing else of the feature is stored.
  static const String weekendsAndSeriesV1 = 'weekendsAndSeries.v1';
}

/// What this build understands and what it holds back until every attached
/// device does (#709): the capability gate's policy.
final class SyncCapabilityPolicy {
  const SyncCapabilityPolicy({
    this.advertised = const {},
    this.gatedRecordKinds = const {},
    this.gatedSettingKeys = const {},
    this.gatedSettingKeyPrefixes = const {},
    this.gatedGlossaryEntryKinds = const {},
    this.gatedSettingValueFields = const {},
  });

  /// The capabilities this build advertises in its capability record. A
  /// capability is only ever open on a device whose own build advertises it,
  /// so data a build only partly supports can never be published by it.
  final Set<String> advertised;

  /// Record kinds whose records wait for a capability.
  final Map<SyncRecordKind, String> gatedRecordKinds;

  /// Settings keys whose records wait for a capability.
  final Map<String, String> gatedSettingKeys;

  /// Prefixes of settings keys built at runtime (one key per item, such as
  /// `program_template:<id>`) whose records wait for a capability. An exact
  /// entry in [gatedSettingKeys] wins; otherwise the longest matching prefix
  /// does, as `classifySettingsKey` resolves the privacy registry's prefixes.
  final Map<String, String> gatedSettingKeyPrefixes;

  /// Kinds of user glossary entry (the `kind` in a `glossaryEntry` record's
  /// body) whose records wait for a capability of their own (#1023). An entry
  /// of any other kind, one this build does not know included, waits for the
  /// record kind's capability in [gatedRecordKinds].
  final Map<String, String> gatedGlossaryEntryKinds;

  /// Settings keys, by prefix, whose value waits for one more capability
  /// while it holds a top-level field (#2342): a value that is a JSON object,
  /// or a string holding one, whose [field] is present and not `null` or an
  /// empty list. Such a record waits for that [capability] **and** for the
  /// one its key is gated on ([gatedSettingKeys], [gatedSettingKeyPrefixes]),
  /// tombstones included when their body still carries the value; the same
  /// key without the field waits for its key's capability alone.
  ///
  /// A key matches the longest prefix it starts with, as
  /// [gatedSettingKeyPrefixes] does.
  final Map<String, ({String field, String capability})>
  gatedSettingValueFields;

  /// This build's policy. Its gated entries are registered by the features
  /// that need them; a capability is advertised only once the whole feature
  /// it covers, sync included, is in the build.
  ///
  /// [SyncCapabilities.glossaryV1] (#709) gates the user's glossary entries,
  /// their notes on shipped figures, the Custom Figures toggle and the
  /// compound shorthands, and this build advertises it: they publish once
  /// every other device attached to the store advertises it too. Until then
  /// this device sends none of them, and leaves alone what it already holds.
  ///
  /// [SyncCapabilities.glossaryV2] (#1023) gates the user's own terms and
  /// figures, and the shorthands for those figures: a peer that can't read
  /// the figures has no use for them. This build advertises it too, now that
  /// the whole of #1023 is in it: they publish once every other device
  /// attached to the store advertises it, and until then a device that
  /// doesn't is named in a held-back notice (sync-spec §6.15).
  ///
  /// [SyncCapabilities.savedSearchesV1] (#2325) gates the user's saved searches
  /// (every `saved_search:` key), and this build advertises it, now that the
  /// whole feature is in it (saving and using them in the Collection came last):
  /// they publish once every other device attached to the store advertises
  /// it, and until then a device that doesn't is named in a held-back notice.
  /// The sync server must already accept the prefix: deploy it before the
  /// first build that advertises this (sync-spec §6.15).
  ///
  /// [SyncCapabilities.programTemplatesV1] (#2337) gates every program
  /// template (by its key prefix), the templates' order and the default
  /// template, and this build advertises it. The legacy Starting program key
  /// is not gated: older builds read it, and it is no longer written. A
  /// template that carries event rules (#2342) also waits for
  /// [SyncCapabilities.eventRulesV1] ([gatedSettingValueFields]): its rule ids
  /// name `eventRule` records a peer without event rules could not hold, and
  /// a build without them cannot read the template's version 3 value.
  ///
  /// [SyncCapabilities.suggestionsV1] (#2343) gates the Suggestions toggle
  /// and its settings, and this build advertises it.
  ///
  /// [SyncCapabilities.performSwapV1] (#2346) gates the Swap a dance
  /// defaults, and this build advertises it.
  ///
  /// [SyncCapabilities.eventRulesV1] (#2340) gates the caller's event rules,
  /// their toggle, the rule picker's order (#2341) and whether Perform's swap
  /// sheet checks them (#2347), and this build advertises it. The sync
  /// server must
  /// already accept the `eventRule` record kind: deploy it before the first
  /// build that advertises this (sync-spec §6.15).
  ///
  /// [SyncCapabilities.weekendsAndSeriesV1] (#2349) gates the Weekends and
  /// series toggle, and this build advertises it.
  static const SyncCapabilityPolicy build = SyncCapabilityPolicy(
    advertised: {
      SyncCapabilities.glossaryV1,
      SyncCapabilities.glossaryV2,
      SyncCapabilities.programTemplatesV1,
      SyncCapabilities.savedSearchesV1,
      SyncCapabilities.suggestionsV1,
      SyncCapabilities.performSwapV1,
      SyncCapabilities.eventRulesV1,
      SyncCapabilities.weekendsAndSeriesV1,
    },
    gatedRecordKinds: {
      SyncRecordKind.glossaryEntry: SyncCapabilities.glossaryV1,
      SyncRecordKind.figureNote: SyncCapabilities.glossaryV1,
      SyncRecordKind.eventRule: SyncCapabilities.eventRulesV1,
    },
    gatedSettingKeys: {
      'show_custom_figures': SyncCapabilities.glossaryV1,
      'compound_shorthands': SyncCapabilities.glossaryV1,
      'user_figure_shorthands': SyncCapabilities.glossaryV2,
      'program_template_order': SyncCapabilities.programTemplatesV1,
      'program_template_default': SyncCapabilities.programTemplatesV1,
      'suggestions_enabled': SyncCapabilities.suggestionsV1,
      'suggestion_settings': SyncCapabilities.suggestionsV1,
      'suggestions_in_perform_swap': SyncCapabilities.suggestionsV1,
      'perform_swap_defaults': SyncCapabilities.performSwapV1,
      'event_rules_enabled': SyncCapabilities.eventRulesV1,
      'event_rule_order': SyncCapabilities.eventRulesV1,
      'event_rules_check_perform_swap': SyncCapabilities.eventRulesV1,
      'weekends_and_series_enabled': SyncCapabilities.weekendsAndSeriesV1,
    },
    gatedSettingKeyPrefixes: {
      'program_template:': SyncCapabilities.programTemplatesV1,
      savedSearchKeyPrefix: SyncCapabilities.savedSearchesV1,
    },
    gatedGlossaryEntryKinds: {
      'term': SyncCapabilities.glossaryV2,
      'customFigure': SyncCapabilities.glossaryV2,
    },
    gatedSettingValueFields: {
      'program_template:': (
        field: 'eventRuleIds',
        capability: SyncCapabilities.eventRulesV1,
      ),
    },
  );

  /// The capability a record waits for, or null when it is not gated.
  ///
  /// [body] is the record's blob body, tombstones included (a tombstone blob
  /// carries its body, sync-spec §4.3). Only a `glossaryEntry` record reads
  /// it, for the entry's kind ([gatedGlossaryEntryKinds]).
  String? capabilityFor(
    SyncRecordKind kind,
    String recordId, {
    Map<String, Object?>? body,
  }) {
    if (kind == SyncRecordKind.setting) return _settingCapability(recordId);
    if (kind == SyncRecordKind.glossaryEntry) {
      final entryKind = body?['kind'];
      if (entryKind is String) {
        final capability = gatedGlossaryEntryKinds[entryKind];
        if (capability != null) return capability;
      }
    }
    return gatedRecordKinds[kind];
  }

  /// Every capability a record waits for: [capabilityFor]'s, and for a
  /// setting whose value holds a field named in [gatedSettingValueFields],
  /// that field's (#2342). Empty when it is not gated. The record is held
  /// back while any of them is closed.
  Set<String> capabilitiesFor(
    SyncRecordKind kind,
    String recordId, {
    Map<String, Object?>? body,
  }) {
    final byKind = capabilityFor(kind, recordId, body: body);
    final byValue = kind == SyncRecordKind.setting
        ? _settingValueCapability(recordId, body?['value'])
        : null;
    return {?byKind, ?byValue};
  }

  String? _settingValueCapability(String key, Object? value) {
    String? best;
    ({String field, String capability})? gate;
    for (final entry in gatedSettingValueFields.entries) {
      if (!key.startsWith(entry.key)) continue;
      if (best == null || entry.key.length > best.length) {
        best = entry.key;
        gate = entry.value;
      }
    }
    if (gate == null) return null;
    return _valueHoldsField(value, gate.field) ? gate.capability : null;
  }

  String? _settingCapability(String key) {
    final exact = gatedSettingKeys[key];
    if (exact != null) return exact;
    String? best;
    String? capability;
    for (final entry in gatedSettingKeyPrefixes.entries) {
      if (!key.startsWith(entry.key)) continue;
      if (best == null || entry.key.length > best.length) {
        best = entry.key;
        capability = entry.value;
      }
    }
    return capability;
  }

  /// Every capability something is gated on.
  Set<String> get gatedCapabilities => {
    ...gatedRecordKinds.values,
    ...gatedSettingKeys.values,
    ...gatedSettingKeyPrefixes.values,
    ...gatedGlossaryEntryKinds.values,
    for (final gate in gatedSettingValueFields.values) gate.capability,
  };
}

/// Whether a setting's [value] — a JSON object, or a string holding one, as a
/// program template's is — has [field] present and not `null` or an empty
/// list. Anything it cannot read as an object has no field.
bool _valueHoldsField(Object? value, String field) {
  var decoded = value;
  if (decoded is String) {
    try {
      decoded = jsonDecode(decoded);
    } on FormatException {
      return false;
    }
  }
  if (decoded is! Map) return false;
  final held = decoded[field];
  return held != null && !(held is List && held.isEmpty);
}

/// The value a capability record stores for [capabilities]: sorted, so the
/// record's bytes depend only on the set.
Map<String, Object?> syncCapabilityRecordValue(Set<String> capabilities) => {
  'capabilities': capabilities.toList()..sort(),
};

/// The capabilities a capability record's stored [value] lists, or null when
/// it is not one. A malformed record counts as no record: its device is not
/// capable of anything.
Set<String>? decodeSyncCapabilityRecord(Object? value) {
  if (value is! Map) return null;
  final raw = value['capabilities'];
  if (raw is! List) return null;
  final capabilities = <String>{};
  for (final entry in raw) {
    if (entry is! String || entry.isEmpty) return null;
    capabilities.add(entry);
  }
  return capabilities;
}

/// The capabilities in [gated] that are closed, each with the devices that
/// hold it closed.
///
/// A capability is open only when this build [advertised] it **and** every
/// other device in [devices] — the store's device list for this pass — has a
/// capability record listing it ([recordsByDevice], from the synced settings
/// as they stand after this pass's pull). A device with no record, or a
/// malformed one, holds every capability closed. When this build does not
/// advertise a capability it is closed with no device to name.
Map<String, Set<String>> closedSyncCapabilities({
  required Set<String> gated,
  required Set<String> advertised,
  required String deviceId,
  required Iterable<String> devices,
  required Map<String, Set<String>?> recordsByDevice,
}) {
  final closed = <String, Set<String>>{};
  for (final capability in gated) {
    if (!advertised.contains(capability)) {
      closed[capability] = <String>{};
      continue;
    }
    for (final device in devices) {
      if (device == deviceId) continue;
      final listed = recordsByDevice[device];
      if (listed == null || !listed.contains(capability)) {
        closed.putIfAbsent(capability, () => <String>{}).add(device);
      }
    }
  }
  return closed;
}
