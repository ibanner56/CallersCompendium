import 'dart:convert';

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

    test('advertises glossary.v1, glossary.v2, programTemplates.v1, '
        'savedSearches.v1, suggestions.v1, performSwap.v1, eventRules.v1 and '
        'weekendsAndSeries.v1, and gates on each (#1023, #2325, #2337, #2340, '
        '#2343, #2346, #2349)', () {
      expect(build.advertised, {
        SyncCapabilities.glossaryV1,
        SyncCapabilities.glossaryV2,
        SyncCapabilities.programTemplatesV1,
        SyncCapabilities.savedSearchesV1,
        SyncCapabilities.suggestionsV1,
        SyncCapabilities.performSwapV1,
        SyncCapabilities.eventRulesV1,
        SyncCapabilities.weekendsAndSeriesV1,
      });
      // Every gated capability is advertised: the whole of each feature,
      // saved searches included now saving and using them is in, is in this build.
      expect(build.gatedCapabilities, build.advertised);
    });

    test('rollout: with no record from any peer, every peer holds each '
        'closed', () {
      expect(closedBeside(['a', 'b'], const {}), {
        SyncCapabilities.glossaryV1: {'a', 'b'},
        SyncCapabilities.glossaryV2: {'a', 'b'},
        SyncCapabilities.programTemplatesV1: {'a', 'b'},
        SyncCapabilities.savedSearchesV1: {'a', 'b'},
        SyncCapabilities.suggestionsV1: {'a', 'b'},
        SyncCapabilities.performSwapV1: {'a', 'b'},
        SyncCapabilities.eventRulesV1: {'a', 'b'},
        SyncCapabilities.weekendsAndSeriesV1: {'a', 'b'},
      });
    });

    test('rollout: beside peers on the build before this one, which '
        'advertise every capability but weekendsAndSeries.v1, every peer '
        'holds it closed and is named (#2349)', () {
      final previous = {...build.advertised}
        ..remove(SyncCapabilities.weekendsAndSeriesV1);
      expect(closedBeside(['a', 'b'], {'a': previous, 'b': previous}), {
        SyncCapabilities.weekendsAndSeriesV1: {'a', 'b'},
      });
      expect(closedBeside(['a', 'b'], {'a': build.advertised, 'b': previous}), {
        SyncCapabilities.weekendsAndSeriesV1: {'b'},
      });
    });

    test('the Weekends and series toggle waits on weekendsAndSeries.v1 '
        '(#2349)', () {
      expect(
        build.capabilityFor(
          SyncRecordKind.setting,
          'weekends_and_series_enabled',
        ),
        SyncCapabilities.weekendsAndSeriesV1,
      );
    });

    test('rollout: beside peers on the build before this one, which '
        'advertise every capability but eventRules.v1 (and the later '
        'weekendsAndSeries.v1), every peer holds eventRules.v1 closed and is '
        'named (#2340)', () {
      final previous = {...build.advertised}
        ..remove(SyncCapabilities.eventRulesV1)
        ..remove(SyncCapabilities.weekendsAndSeriesV1);
      expect(closedBeside(['a', 'b'], {'a': previous, 'b': previous}), {
        SyncCapabilities.eventRulesV1: {'a', 'b'},
        SyncCapabilities.weekendsAndSeriesV1: {'a', 'b'},
      });
      expect(closedBeside(['a', 'b'], {'a': build.advertised, 'b': previous}), {
        SyncCapabilities.eventRulesV1: {'b'},
        SyncCapabilities.weekendsAndSeriesV1: {'b'},
      });
    });

    test('event rules and the Experimental toggle wait on eventRules.v1; a '
        "program's applied rule ids do not (#2340)", () {
      expect(
        build.capabilityFor(SyncRecordKind.eventRule, 'r1'),
        SyncCapabilities.eventRulesV1,
      );
      expect(
        build.capabilityFor(SyncRecordKind.setting, 'event_rules_enabled'),
        SyncCapabilities.eventRulesV1,
      );
      expect(build.capabilityFor(SyncRecordKind.program, 'p1'), isNull);
    });

    test("the rule picker's order waits on eventRules.v1 too, not a "
        'capability of its own (#2341)', () {
      expect(
        build.capabilityFor(SyncRecordKind.setting, 'event_rule_order'),
        SyncCapabilities.eventRulesV1,
      );
    });

    test('rollout: beside peers on the build before this one, which '
        'advertise every capability but savedSearches.v1, eventRules.v1 and '
        'weekendsAndSeries.v1, '
        'every peer holds savedSearches.v1 closed and is named', () {
      const previous = {
        SyncCapabilities.glossaryV1,
        SyncCapabilities.glossaryV2,
        SyncCapabilities.programTemplatesV1,
        SyncCapabilities.suggestionsV1,
        SyncCapabilities.performSwapV1,
      };
      expect(closedBeside(['a', 'b'], {'a': previous, 'b': previous}), {
        SyncCapabilities.savedSearchesV1: {'a', 'b'},
        SyncCapabilities.eventRulesV1: {'a', 'b'},
        SyncCapabilities.weekendsAndSeriesV1: {'a', 'b'},
      });
      // Once one of them is updated, only the other holds it closed.
      expect(closedBeside(['a', 'b'], {'a': build.advertised, 'b': previous}), {
        SyncCapabilities.savedSearchesV1: {'b'},
        SyncCapabilities.eventRulesV1: {'b'},
        SyncCapabilities.weekendsAndSeriesV1: {'b'},
      });
    });

    test('rollout: beside peers on the build before this one, which '
        'advertise suggestions.v1 too, every peer holds performSwap.v1 and '
        'savedSearches.v1 closed (#2346, #2325)', () {
      const previous = {
        SyncCapabilities.glossaryV1,
        SyncCapabilities.glossaryV2,
        SyncCapabilities.programTemplatesV1,
        SyncCapabilities.suggestionsV1,
      };
      expect(closedBeside(['a', 'b'], {'a': previous, 'b': previous}), {
        SyncCapabilities.performSwapV1: {'a', 'b'},
        SyncCapabilities.savedSearchesV1: {'a', 'b'},
        SyncCapabilities.eventRulesV1: {'a', 'b'},
        SyncCapabilities.weekendsAndSeriesV1: {'a', 'b'},
      });
    });

    test('the Swap a dance defaults wait on performSwap.v1 (#2346)', () {
      expect(
        build.capabilityFor(SyncRecordKind.setting, 'perform_swap_defaults'),
        SyncCapabilities.performSwapV1,
      );
    });

    test('every suggestions key waits on suggestions.v1 (#2343, #2348)', () {
      for (final key in [
        'suggestions_enabled',
        'suggestion_settings',
        'suggestions_in_perform_swap',
      ]) {
        expect(
          build.capabilityFor(SyncRecordKind.setting, key),
          SyncCapabilities.suggestionsV1,
          reason: key,
        );
      }
    });

    test('every program template key waits on programTemplates.v1, by prefix '
        'for the per-template keys (#2337)', () {
      for (final key in [
        'program_template:starting_program',
        'program_template:3f1c9a52-6a0f-4d7b-9a51-0b5e4f2d7c11',
        'program_template_order',
        'program_template_default',
      ]) {
        expect(
          build.capabilityFor(SyncRecordKind.setting, key),
          SyncCapabilities.programTemplatesV1,
          reason: key,
        );
      }
      // The legacy Starting program stays ungated: older builds read it.
      expect(
        build.capabilityFor(SyncRecordKind.setting, 'default_starting_program'),
        isNull,
      );
    });

    test('a program template that carries event rules waits on '
        'eventRules.v1 as well as programTemplates.v1; one without waits on '
        'programTemplates.v1 alone (#2342)', () {
      const key = 'program_template:3f1c9a52-6a0f-4d7b-9a51-0b5e4f2d7c11';
      Set<String> waits(Object? value) => build.capabilitiesFor(
        SyncRecordKind.setting,
        key,
        body: {'value': value},
      );
      // As the app stores it: the template's JSON, as a string.
      String template(Map<String, Object?> value) => jsonEncode(value);
      const both = {
        SyncCapabilities.programTemplatesV1,
        SyncCapabilities.eventRulesV1,
      };
      expect(
        waits(
          template({
            'version': 3,
            'name': 'Family dance',
            'slots': <Object?>[],
            'eventRuleIds': ['r1'],
          }),
        ),
        both,
      );
      expect(
        waits({
          'version': 3,
          'eventRuleIds': ['r1'],
        }),
        both,
        reason: 'an object as well as a string holding one',
      );
      for (final (label, value) in <(String, Object?)>[
        ('v1', template({'version': 1, 'name': 'X', 'slots': <Object?>[]})),
        ('v2', template({'version': 2, 'name': 'X', 'slots': <Object?>[]})),
        ('an empty list', template({'eventRuleIds': <Object?>[]})),
        ('null', template({'eventRuleIds': null})),
        ('not JSON', '{'),
        ('no value', null),
      ]) {
        expect(waits(value), {
          SyncCapabilities.programTemplatesV1,
        }, reason: label);
      }
      // Only template keys look at their value.
      expect(
        build.capabilitiesFor(
          SyncRecordKind.setting,
          'program_template_order',
          body: {
            'value': {
              'eventRuleIds': ['r1'],
            },
          },
        ),
        {SyncCapabilities.programTemplatesV1},
      );
      expect(
        build.capabilitiesFor(
          SyncRecordKind.setting,
          'theme_mode',
          body: {'value': '{"eventRuleIds":["r1"]}'},
        ),
        isEmpty,
      );
      expect(build.capabilitiesFor(SyncRecordKind.eventRule, 'r1'), {
        SyncCapabilities.eventRulesV1,
      });
    });

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

    test('with every peer advertising what the build does, every '
        'capability is open, saved searches included', () {
      expect(
        closedBeside(
          ['a', 'b'],
          {'a': build.advertised, 'b': build.advertised},
        ),
        isEmpty,
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

  test('a settings key prefix gates every key under it; an exact key wins, '
      'then the longest prefix', () {
    const policy = SyncCapabilityPolicy(
      gatedSettingKeys: {'p:exact': 'exact.v1'},
      gatedSettingKeyPrefixes: {'p:': 'short.v1', 'p:long:': 'long.v1'},
    );
    String? forKey(String key) =>
        policy.capabilityFor(SyncRecordKind.setting, key);
    expect(forKey('p:anything'), 'short.v1');
    expect(forKey('p:long:x'), 'long.v1');
    expect(forKey('p:exact'), 'exact.v1');
    expect(forKey('p'), isNull);
    expect(forKey('other:p:x'), isNull);
    // Only settings keys are matched by prefix.
    expect(policy.capabilityFor(SyncRecordKind.tag, 'p:x'), isNull);
    expect(policy.gatedCapabilities, {'exact.v1', 'short.v1', 'long.v1'});
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
