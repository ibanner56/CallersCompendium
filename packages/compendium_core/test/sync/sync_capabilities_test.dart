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

    test(
      'advertises glossary.v1 and glossary.v2, and gates on both (#1023)',
      () {
        expect(build.advertised, {
          SyncCapabilities.glossaryV1,
          SyncCapabilities.glossaryV2,
        });
        // Saved searches (#2325) are gated but not yet advertised: a
        // capability is advertised only once the whole feature is in the
        // build, so this build publishes none and nothing writes one.
        expect(build.gatedCapabilities, {
          SyncCapabilities.glossaryV1,
          SyncCapabilities.glossaryV2,
          SyncCapabilities.savedSearchesV1,
        });
        expect(
          build.advertised,
          isNot(contains(SyncCapabilities.savedSearchesV1)),
        );
      },
    );

    test('gates every saved_search: key on savedSearches.v1', () {
      for (final key in ['saved_search:abc', 'saved_search:x:y']) {
        expect(
          build.capabilityFor(SyncRecordKind.setting, key),
          SyncCapabilities.savedSearchesV1,
          reason: key,
        );
      }
      // Only the prefix, and only settings.
      for (final key in ['saved_search', 'saved_searches:abc', 'theme_mode']) {
        expect(
          build.capabilityFor(SyncRecordKind.setting, key),
          isNot(SyncCapabilities.savedSearchesV1),
          reason: key,
        );
      }
      expect(
        build.capabilityFor(SyncRecordKind.dance, 'saved_search:abc'),
        isNull,
      );
    });

    test('a saved search is shareable user configuration', () {
      final c = classifySettingsKey('${savedSearchKeyPrefix}abc');
      expect(c?.egress, EgressClass.shareable);
      expect(c?.subject, DataSubject.appUser);
    });

    test('rollout: with no record from any peer, every peer holds both '
        'closed', () {
      expect(closedBeside(['a', 'b'], const {}), {
        SyncCapabilities.glossaryV1: {'a', 'b'},
        SyncCapabilities.glossaryV2: {'a', 'b'},
        // Not advertised by this build, so closed with no device to name.
        SyncCapabilities.savedSearchesV1: <String>{},
      });
    });

    test('rollout: beside peers on the build before this one, which '
        'advertise only glossary.v1, every peer holds glossary.v2 closed', () {
      expect(
        closedBeside(
          ['a', 'b'],
          {
            'a': {SyncCapabilities.glossaryV1},
            'b': {SyncCapabilities.glossaryV1},
          },
        ),
        {
          SyncCapabilities.glossaryV2: {'a', 'b'},
          SyncCapabilities.savedSearchesV1: <String>{},
        },
      );
    });

    test('with every peer advertising what the build does, the glossary '
        'capabilities are open and saved searches stay closed', () {
      expect(
        closedBeside(
          ['a', 'b'],
          {'a': build.advertised, 'b': build.advertised},
        ),
        {SyncCapabilities.savedSearchesV1: <String>{}},
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

  group('a gated settings-key prefix', () {
    const policy = SyncCapabilityPolicy(
      gatedSettingKeys: {'p:exact': 'exact.v1'},
      gatedSettingKeyPrefixes: {'p:': 'short.v1', 'p:long:': 'long.v1'},
    );

    test('gates every key under it, and counts as gated', () {
      expect(policy.capabilityFor(SyncRecordKind.setting, 'p:abc'), 'short.v1');
      expect(policy.capabilityFor(SyncRecordKind.setting, 'q:abc'), isNull);
      expect(
        policy.gatedCapabilities,
        containsAll(['exact.v1', 'short.v1', 'long.v1']),
      );
    });

    test('the longest prefix wins, and an exact key beats any prefix', () {
      expect(
        policy.capabilityFor(SyncRecordKind.setting, 'p:long:abc'),
        'long.v1',
      );
      expect(
        policy.capabilityFor(SyncRecordKind.setting, 'p:exact'),
        'exact.v1',
      );
    });

    test('does not gate other kinds of record', () {
      expect(policy.capabilityFor(SyncRecordKind.dance, 'p:abc'), isNull);
    });
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
