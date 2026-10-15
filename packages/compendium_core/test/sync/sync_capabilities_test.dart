import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The capability gate's rules (#709).
void main() {
  Map<String, Set<String>> closed({
    Set<String> gated = const {'g.v1'},
    Set<String> advertised = const {'g.v1'},
    List<String> devices = const ['me', 'peer'],
    Map<String, Set<String>?> records = const {},
  }) => closedSyncCapabilities(
    gated: gated,
    advertised: advertised,
    deviceId: 'me',
    devices: devices,
    recordsByDevice: records,
  );

  test('open when this build and every other device advertise it', () {
    expect(
      closed(
        records: {
          'peer': {'g.v1'},
        },
      ),
      isEmpty,
    );
    expect(closed(devices: const ['me']), isEmpty, reason: 'alone');
  });

  test(
    'a device with no record, a malformed one or another list closes it',
    () {
      expect(closed(), {
        'g.v1': {'peer'},
      });
      expect(closed(records: const {'peer': null}), {
        'g.v1': {'peer'},
      });
      expect(
        closed(
          devices: const ['me', 'a', 'b'],
          records: {
            'a': {'g.v1'},
            'b': {'other.v1'},
          },
        ),
        {
          'g.v1': {'b'},
        },
      );
    },
  );

  test('a build that does not advertise it never opens it, even alone', () {
    expect(closed(advertised: const {}, devices: const ['me']), {
      'g.v1': <String>{},
    });
  });

  test('a record of a device no longer listed counts for nothing', () {
    expect(
      closed(
        devices: const ['me', 'peer'],
        records: {
          'gone': {'g.v1'},
        },
      ),
      {
        'g.v1': {'peer'},
      },
    );
  });

  group('the record', () {
    test('round-trips, sorted so its bytes depend only on the set', () {
      final value = syncCapabilityRecordValue({'b', 'a'});
      expect(value, {
        'capabilities': ['a', 'b'],
      });
      expect(decodeSyncCapabilityRecord(value), {'a', 'b'});
    });

    test('anything else is no record', () {
      for (final raw in <Object?>[
        null,
        'x',
        <String, Object?>{},
        {'capabilities': 'a'},
        {
          'capabilities': [1],
        },
        {
          'capabilities': [''],
        },
      ]) {
        expect(decodeSyncCapabilityRecord(raw), isNull, reason: '$raw');
      }
    });

    test('its key carries the device id after the shared prefix', () {
      expect(syncCapabilityRecordKey('d1'), 'sync_capabilities:d1');
    });

    test('is classified shareable, so it travels', () {
      expect(
        classifySettingsKey(syncCapabilityRecordKey('d1'))?.egress,
        EgressClass.shareable,
      );
    });
  });

  test('the policy maps a gated record to its capability', () {
    const policy = SyncCapabilityPolicy(
      gatedRecordKinds: {SyncRecordKind.venue: 'v.v1'},
      gatedSettingKeys: {'k': 's.v1'},
    );
    expect(policy.capabilityFor(SyncRecordKind.venue, 'x'), 'v.v1');
    expect(policy.capabilityFor(SyncRecordKind.setting, 'k'), 's.v1');
    expect(policy.capabilityFor(SyncRecordKind.setting, 'other'), isNull);
    expect(policy.capabilityFor(SyncRecordKind.dance, 'x'), isNull);
    expect(policy.gatedCapabilities, {'v.v1', 's.v1'});
  });
}
