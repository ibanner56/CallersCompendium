import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The stored `suggestion_settings` value (#2343).
void main() {
  const shipped = {
    'version': 1,
    'factors': {
      'matrixVariety': {'weight': 'aLot'},
      'formationBalance': {'weight': 'aLittle'},
      'difficultyCurve': {'weight': 'aLittle', 'shape': 'buildThenEase'},
      'venueRecency': {'weight': 'aLot', 'window': '3mo'},
    },
    'preferences': <Object?>[],
  };

  test('the defaults encode as the shipped value', () {
    expect(SuggestionSettings.defaults.toJson(), shipped);
  });

  test(
    'a missing key, or a malformed one, reads as the defaults, writable',
    () {
      for (final stored in <Object?>[
        null,
        'not json',
        42,
        <Object?>[],
        {'version': 'one'},
        {'factors': <String, Object?>{}},
      ]) {
        final read = readSuggestionSettings(stored);
        expect(read.settings, SuggestionSettings.defaults, reason: '$stored');
        expect(read.isNewer, isFalse, reason: '$stored');
      }
    },
  );

  test('a missing factor, or an unknown token, reads as that field\'s '
      'default', () {
    final read = readSuggestionSettings({
      'version': 1,
      'factors': {
        'matrixVariety': {'weight': 'off'},
        'difficultyCurve': {'weight': 'loads', 'shape': 'even'},
        'venueRecency': {'window': '6mo'},
      },
    });
    final s = read.settings;
    expect(s.matrixVariety, SuggestionWeight.off);
    expect(s.formationBalance, SuggestionWeight.aLittle);
    expect(s.difficultyCurve, SuggestionWeight.aLittle);
    expect(s.curveShape, DifficultyCurveShape.even);
    expect(s.venueRecency, SuggestionWeight.aLot);
    expect(s.venueWindow, VenueRecencyWindow.sixMonths);
  });

  test('reads a JSON string as well as an object', () {
    final read = readSuggestionSettings(
      jsonEncode({
        'version': 1,
        'factors': {
          'formationBalance': {'weight': 'aLot'},
        },
      }),
    );
    expect(read.settings.formationBalance, SuggestionWeight.aLot);
  });

  test('round-trips every choice', () {
    final settings = SuggestionSettings.defaults
        .withWeight(SuggestionFactor.venueRecency, SuggestionWeight.off)
        .copyWith(
          curveShape: DifficultyCurveShape.off,
          venueWindow: VenueRecencyWindow.oneMonth,
        );
    expect(readSuggestionSettings(settings.toJson()).settings, settings);
  });

  test('an unknown factor, unknown keys and every preference are written '
      'back verbatim, and ignored', () {
    final stored = {
      'version': 1,
      'factors': {
        'matrixVariety': {'weight': 'aLittle', 'cap': 3},
        'tempo': {'weight': 'aLot', 'bpm': 120},
      },
      'preferences': [
        {'savedSearchId': 's1', 'kind': 'prefer'},
        {'something': 'new'},
      ],
      'extra': true,
    };
    final read = readSuggestionSettings(stored);
    expect(read.isNewer, isFalse);
    expect(read.settings.matrixVariety, SuggestionWeight.aLittle);
    final edited = read.settings.withWeight(
      SuggestionFactor.formationBalance,
      SuggestionWeight.off,
    );
    final written = edited.toJson();
    final factors = written['factors']! as Map;
    expect(factors['tempo'], {'weight': 'aLot', 'bpm': 120});
    expect(factors['matrixVariety'], {'weight': 'aLittle', 'cap': 3});
    expect(factors['formationBalance'], {'weight': 'off'});
    expect(written['preferences'], stored['preferences']);
    expect(written['extra'], true);
    // Reset to defaults keeps them too.
    final reset = edited.resetChoices();
    expect(reset.hasDefaultChoices, isTrue);
    expect((reset.toJson()['factors']! as Map)['tempo'], isNotNull);
    expect(reset.toJson()['preferences'], stored['preferences']);
  });

  test('a newer version reads as the defaults and is flagged', () {
    final read = readSuggestionSettings({
      'version': 2,
      'factors': {
        'matrixVariety': {'weight': 'off'},
      },
    });
    expect(read.isNewer, isTrue);
    expect(read.settings, SuggestionSettings.defaults);
  });

  test('backup validation', () {
    expect(isValidStoredSuggestionSettings(shipped), isTrue);
    expect(isValidStoredSuggestionSettings({'version': 1}), isTrue);
    // A newer version is kept as it stands.
    expect(
      isValidStoredSuggestionSettings({
        'version': 3,
        'factors': {
          'matrixVariety': {'weight': 'enormous'},
        },
      }),
      isTrue,
    );
    for (final bad in <Object?>[
      null,
      'nope',
      <Object?>[],
      {'version': 0},
      {'version': '1'},
      {'version': 1, 'factors': <Object?>[]},
      {'version': 1, 'preferences': <String, Object?>{}},
      {
        'version': 1,
        'factors': {
          'matrixVariety': {'weight': 'enormous'},
        },
      },
      {
        'version': 1,
        'factors': {
          'difficultyCurve': {'shape': 'zigzag'},
        },
      },
      {
        'version': 1,
        'factors': {
          'venueRecency': {'window': '1y'},
        },
      },
      {
        'version': 1,
        'factors': {'formationBalance': 'aLot'},
      },
    ]) {
      expect(isValidStoredSuggestionSettings(bad), isFalse, reason: '$bad');
    }
  });
}
