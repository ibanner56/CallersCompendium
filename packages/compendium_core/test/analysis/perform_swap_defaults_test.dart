import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The stored `perform_swap_defaults` value (#2346).
void main() {
  const shipped = {
    'version': 1,
    'keep': {
      'formation': true,
      'levelOrEasier': true,
      'sameType': true,
      'notInProgram': true,
    },
  };

  test('the defaults encode as the shipped value', () {
    expect(PerformSwapDefaults.defaults.toJson(), shipped);
  });

  test('a missing key, or a malformed one, reads as every item on, '
      'writable', () {
    for (final stored in <Object?>[
      null,
      'not json',
      42,
      <Object?>[],
      {'version': 'one'},
      {'keep': <String, Object?>{}},
    ]) {
      final read = readPerformSwapDefaults(stored);
      expect(read.defaults, PerformSwapDefaults.defaults, reason: '$stored');
      expect(read.isNewer, isFalse, reason: '$stored');
    }
  });

  test('a missing item, or one that is not a bool, reads as on', () {
    final read = readPerformSwapDefaults({
      'version': 1,
      'keep': {'formation': false, 'sameType': 'no'},
    });
    expect(read.defaults.formation, isFalse);
    expect(read.defaults.levelOrEasier, isTrue);
    expect(read.defaults.sameType, isTrue);
    expect(read.defaults.notInProgram, isTrue);
  });

  test('round-trips each item off, from a JSON string too', () {
    for (final item in PerformSwapKeepItem.values) {
      final off = PerformSwapDefaults.defaults.withItem(item, false);
      final read = readPerformSwapDefaults(jsonEncode(off.toJson()));
      expect(read.defaults, off, reason: item.name);
      for (final other in PerformSwapKeepItem.values) {
        expect(read.defaults.isOn(other), other != item, reason: other.name);
      }
    }
  });

  test('unknown items and keys are written back unchanged', () {
    final read = readPerformSwapDefaults({
      'version': 1,
      'keep': {'formation': false, 'tempo': true},
      'note': {'x': 1},
    });
    final edited = read.defaults.withItem(
      PerformSwapKeepItem.notInProgram,
      false,
    );
    expect(edited.toJson(), {
      'note': {'x': 1},
      'version': 1,
      'keep': {
        'tempo': true,
        'formation': false,
        'levelOrEasier': true,
        'sameType': true,
        'notInProgram': false,
      },
    });
  });

  test('a newer version reads as the defaults, flagged so it is not '
      'overwritten', () {
    final read = readPerformSwapDefaults({
      'version': 2,
      'keep': {'formation': false},
    });
    expect(read.isNewer, isTrue);
    expect(read.defaults, PerformSwapDefaults.defaults);
  });

  group('isValidStoredPerformSwapDefaults', () {
    test('accepts the shipped value, a partial one and a newer one', () {
      expect(isValidStoredPerformSwapDefaults(shipped), isTrue);
      expect(
        isValidStoredPerformSwapDefaults({
          'version': 1,
          'keep': {'formation': false},
        }),
        isTrue,
      );
      expect(isValidStoredPerformSwapDefaults({'version': 1}), isTrue);
      expect(
        isValidStoredPerformSwapDefaults({
          'version': 3,
          'keep': {'formation': 'whatever'},
        }),
        isTrue,
      );
      expect(isValidStoredPerformSwapDefaults(jsonEncode(shipped)), isTrue);
    });

    test('rejects a wrong shape or a non-bool item', () {
      for (final stored in <Object?>[
        null,
        true,
        'not json',
        <Object?>[],
        {'keep': <String, Object?>{}},
        {'version': 0},
        {'version': 1, 'keep': <Object?>[]},
        {
          'version': 1,
          'keep': {'levelOrEasier': 'yes'},
        },
      ]) {
        expect(
          isValidStoredPerformSwapDefaults(stored),
          isFalse,
          reason: '$stored',
        );
      }
    });
  });
}
