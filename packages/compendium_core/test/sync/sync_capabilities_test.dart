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

  group('the shipped policy (SyncCapabilityPolicy.build)', () {
    const build = SyncCapabilityPolicy.build;
    Map<String, Set<String>> closedBeside(
      List<String> peers,
      Map<String, Set<String>?> records,
    ) => closedSyncCapabilities(
      gated: build.gatedCapabilities,
      advertised: build.advertised,
      deviceId: 'me',
      devices: ['me', ...peers],
      recordsByDevice: records,
    );

    test('advertises glossary.v1 and gates glossary.v2 without advertising '
        'it', () {
      expect(build.advertised, {SyncCapabilities.glossaryV1});
      expect(build.gatedCapabilities, {
        SyncCapabilities.glossaryV1,
        SyncCapabilities.glossaryV2,
      });
    });

    test('rollout: with no record from any peer, every peer holds '
        'glossary.v1 closed', () {
      expect(closedBeside(['a', 'b'], const {}), {
        SyncCapabilities.glossaryV1: {'a', 'b'},
        SyncCapabilities.glossaryV2: <String>{},
      });
    });

    test('with every peer advertising what the build does, glossary.v1 is '
        'open and glossary.v2 is closed with no device to name', () {
      expect(
        closedBeside(
          ['a', 'b'],
          {'a': build.advertised, 'b': build.advertised},
        ),
        {SyncCapabilities.glossaryV2: <String>{}},
      );
    });
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

  test('a glossary entry waits on its own kind\'s capability when it has one '
      '(#1023)', () {
    const policy = SyncCapabilityPolicy(
      gatedRecordKinds: {SyncRecordKind.glossaryEntry: 'g.v1'},
      gatedGlossaryEntryKinds: {'customFigure': 'g.v2'},
    );
    String? forKind(Object? kind) => policy.capabilityFor(
      SyncRecordKind.glossaryEntry,
      'id',
      body: {'kind': kind},
    );
    expect(forKind('customFigure'), 'g.v2');
    expect(forKind('compound'), 'g.v1');
    expect(forKind('someLaterKind'), 'g.v1', reason: 'relayed as before');
    expect(forKind(null), 'g.v1');
    expect(policy.capabilityFor(SyncRecordKind.glossaryEntry, 'id'), 'g.v1');
    // Only a glossary entry's body is read.
    expect(
      policy.capabilityFor(
        SyncRecordKind.figureNote,
        'id',
        body: {'kind': 'customFigure'},
      ),
      isNull,
    );
    // A capability only an entry kind names is still one the gate closes.
    expect(policy.gatedCapabilities, {'g.v1', 'g.v2'});
  });
}
