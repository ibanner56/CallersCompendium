import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  test('every withdrawn setting is classified and does not sync', () {
    // A key made shareable again must come off the list in the same change,
    // or every peer's value for it would still be dropped.
    for (final key in syncWithdrawnSettingKeys) {
      final egress = classifySettingsKey(key)?.egress;
      expect(egress, isNotNull, reason: '$key is not in the registry');
      expect(egress, isNot(EgressClass.shareable), reason: key);
    }
  });

  group('withoutWithdrawnSyncSettings', () {
    SyncManifest manifest(Map<SyncRecordKind, Map<String, String>> records) =>
        SyncManifest(
          deviceId: 'peer',
          epoch: 'epoch-1',
          writtenAt: DateTime.utc(2026, 10, 29),
          records: records,
          unknownKinds: const {'addedLater'},
        );

    test('leaves out only the withdrawn settings', () {
      final filtered = withoutWithdrawnSyncSettings(
        manifest({
          SyncRecordKind.setting: {
            'reduce_motion': 'a' * 64,
            'theme_mode': 'b' * 64,
          },
          SyncRecordKind.tag: {'reduce_motion': 'c' * 64},
        }),
      );

      expect(filtered.records[SyncRecordKind.setting], {
        'theme_mode': 'b' * 64,
      });
      expect(filtered.records[SyncRecordKind.tag], {
        'reduce_motion': 'c' * 64,
      }, reason: 'only a setting record is withdrawn, whatever its id');
      expect(filtered.deviceId, 'peer');
      expect(filtered.epoch, 'epoch-1');
      expect(filtered.writtenAt, DateTime.utc(2026, 10, 29));
      expect(filtered.unknownKinds, {'addedLater'});
    });

    test('returns the manifest itself when it lists none', () {
      final original = manifest({
        SyncRecordKind.setting: {'theme_mode': 'b' * 64},
      });
      expect(withoutWithdrawnSyncSettings(original), same(original));
    });
  });
}
