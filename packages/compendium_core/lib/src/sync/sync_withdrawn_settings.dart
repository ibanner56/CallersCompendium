import 'sync_codec.dart';
import 'sync_record_kind.dart';

/// Settings keys an older build synced and this one keeps on each device
/// instead (spec §6.7, amended 2026-10-29).
///
/// They are the screen-bound settings the maintainer made per-device on
/// 2026-10-29 (settings-sync-scope): app language, Reduce motion, Auto-size
/// Perform cards and the Perform stage theme. The registry classifies each one
/// `deviceLocal` and gives the reason.
///
/// A peer still on an older build keeps publishing its value for these keys.
/// That value is **dropped** on the way in, before the merge sees it. It is
/// not applied. It is not kept for the peer either, as §6.7 otherwise requires
/// for a setting this build does not sync. A kept copy would be shared back,
/// and so would never die out: a peer that upgrades later receives its own
/// last value back, keeps it in turn, and shares it on. It would also raise
/// `keptNewerFields` on every pass, telling an up-to-date user to update.
/// Dropping loses no data, because a record missing from a manifest is never
/// read as a deletion (spec §4.5), so the older peer keeps its own value.
///
/// It does cost the older peer a false notice. That device sees its value go
/// uncarried by upgraded peers, so it reports `unreflectedPublication` against
/// them ("may need an app update") until it is itself updated. The maintainer
/// accepted that on 2026-10-30, because keeping the copy would have made every
/// upgraded device republish deviceLocal values indefinitely.
///
/// A key goes on this list only when it is withdrawn from sync. If a later
/// build makes one shareable again, it must come off the list in that change.
/// `sync_withdrawn_settings_test.dart` fails while a listed key is shareable.
const Set<String> syncWithdrawnSettingKeys = {
  'app_locale',
  'reduce_motion',
  'auto_size_perform_cards',
  'perform_stage_mode',
};

/// Whether a record of [kind] with [recordId] is a withdrawn setting, which an
/// inbound pass drops without a word (see [syncWithdrawnSettingKeys]).
bool isWithdrawnSyncSetting(SyncRecordKind kind, String recordId) =>
    kind == SyncRecordKind.setting &&
    syncWithdrawnSettingKeys.contains(recordId);

/// [manifest] without its entries for withdrawn settings, so a pass neither
/// downloads nor merges them. Returns [manifest] itself when it lists none.
///
/// Apply only to a copy the pass reads. A copy kept for the next `ETag`
/// request must stay as the peer published it.
SyncManifest withoutWithdrawnSyncSettings(SyncManifest manifest) {
  final settings = manifest.records[SyncRecordKind.setting];
  if (settings == null ||
      !settings.keys.any(syncWithdrawnSettingKeys.contains)) {
    return manifest;
  }
  return SyncManifest(
    v: manifest.v,
    deviceId: manifest.deviceId,
    epoch: manifest.epoch,
    writtenAt: manifest.writtenAt,
    records: {
      for (final MapEntry(key: kind, value: records)
          in manifest.records.entries)
        kind: kind == SyncRecordKind.setting
            ? {
                for (final MapEntry(key: id, value: hash) in records.entries)
                  if (!syncWithdrawnSettingKeys.contains(id)) id: hash,
              }
            : records,
    },
    unknownKinds: manifest.unknownKinds,
  );
}
