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
}

/// What this build understands and what it holds back until every attached
/// device does (#709): the capability gate's policy.
final class SyncCapabilityPolicy {
  const SyncCapabilityPolicy({
    this.advertised = const {},
    this.gatedRecordKinds = const {},
    this.gatedSettingKeys = const {},
    this.gatedGlossaryEntryKinds = const {},
  });

  /// The capabilities this build advertises in its capability record. A
  /// capability is only ever open on a device whose own build advertises it,
  /// so data a build only partly supports can never be published by it.
  final Set<String> advertised;

  /// Record kinds whose records wait for a capability.
  final Map<SyncRecordKind, String> gatedRecordKinds;

  /// Settings keys whose records wait for a capability.
  final Map<String, String> gatedSettingKeys;

  /// Kinds of user glossary entry (the `kind` in a `glossaryEntry` record's
  /// body) whose records wait for a capability of their own (#1023). An entry
  /// of any other kind, one this build does not know included, waits for the
  /// record kind's capability in [gatedRecordKinds].
  final Map<String, String> gatedGlossaryEntryKinds;

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
  /// the figures has no use for them. This build does not advertise it yet,
  /// so they stay on their device.
  static const SyncCapabilityPolicy build = SyncCapabilityPolicy(
    advertised: {SyncCapabilities.glossaryV1},
    gatedRecordKinds: {
      SyncRecordKind.glossaryEntry: SyncCapabilities.glossaryV1,
      SyncRecordKind.figureNote: SyncCapabilities.glossaryV1,
    },
    gatedSettingKeys: {
      'show_custom_figures': SyncCapabilities.glossaryV1,
      'compound_shorthands': SyncCapabilities.glossaryV1,
      'user_figure_shorthands': SyncCapabilities.glossaryV2,
    },
    gatedGlossaryEntryKinds: {
      'term': SyncCapabilities.glossaryV2,
      'customFigure': SyncCapabilities.glossaryV2,
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
    if (kind == SyncRecordKind.setting) return gatedSettingKeys[recordId];
    if (kind == SyncRecordKind.glossaryEntry) {
      final entryKind = body?['kind'];
      if (entryKind is String) {
        final capability = gatedGlossaryEntryKinds[entryKind];
        if (capability != null) return capability;
      }
    }
    return gatedRecordKinds[kind];
  }

  /// Every capability something is gated on.
  Set<String> get gatedCapabilities => {
    ...gatedRecordKinds.values,
    ...gatedSettingKeys.values,
    ...gatedGlossaryEntryKinds.values,
  };
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
