import 'param_types.dart';

/// How far a [ParamKind] has an opposite (#709).
enum OppositeCoverage {
  /// Every value has one (right ↔ left).
  total,

  /// Some values have one and others do not (`everyone` has no other pair).
  partial,

  /// No value has one.
  none,
}

/// The opposites a user compound figure can use (#709): when a compound
/// declares a parameter of a kind listed here, the editor also offers the
/// computed opposite (`hand` → "other hand"), and expansion writes the raw
/// opposite value onto the receiving figure.
///
/// Every [ParamKind] is classified here, through an exhaustive switch, and
/// `param_opposites_test.dart` pins the full table value by value, so a new
/// kind or a new vocabulary value cannot be added without deciding its
/// opposite. Pair inversion is not restated: it is [invertPairDancerSet], the
/// single source of truth the renderer and importers already share. On top of
/// it, `partners` is opposed by `neighbors` and every neighbor-series token
/// is opposed by `partners`.
///
/// The `unspecified` sentinel is its own opposite — "not stated" stays not
/// stated — so a kind keeps its coverage when a slot opts into it.
abstract final class ParamOpposites {
  /// How far [kind] has opposites.
  static OppositeCoverage coverage(ParamKind kind) => switch (kind) {
    ParamKind.handedness ||
    ParamKind.shoulder ||
    ParamKind.spinDirection => OppositeCoverage.total,
    ParamKind.dancerSet ||
    ParamKind.dancerPair ||
    ParamKind.direction => OppositeCoverage.partial,
    // A rotation, a count of places or beats, a fraction, free text or a
    // flag has no opposite a caller would name.
    ParamKind.rotation ||
    ParamKind.places ||
    ParamKind.fraction ||
    ParamKind.beats ||
    ParamKind.text ||
    ParamKind.flag => OppositeCoverage.none,
    // A move-specific choice can spell left/right (circle's direction), but
    // its values are the move's own vocabulary, not a shared one with a
    // meaning: no opposite (a named limitation, #709).
    ParamKind.choice => OppositeCoverage.none,
  };

  /// The opposite of [value] for [kind], or null when it has none.
  static Object? of(ParamKind kind, Object? value) {
    if (coverage(kind) == OppositeCoverage.none || value is! String) {
      return null;
    }
    if (value == ParamVocab.unspecified) return ParamVocab.unspecified;
    return switch (kind) {
      ParamKind.handedness || ParamKind.shoulder => _sides[value],
      ParamKind.spinDirection => _spins[value],
      ParamKind.dancerSet || ParamKind.dancerPair => _dancerOpposite(value),
      ParamKind.direction => _directions[value],
      _ => null,
    };
  }

  /// A dancer set's opposite: the pair [invertPairDancerSet] names, else the
  /// partner/neighbor swap. `partners` ↔ `neighbors`, and every other member
  /// of the neighbor series ([_neighborSeries]) is opposed by `partners`, so
  /// "other who" always offers the partner whichever neighbor was chosen.
  ///
  /// The swap is deliberately not an involution: `nextNeighbors` →
  /// `partners` → `neighbors`. The renderer and importers keep using
  /// [invertPairDancerSet], which still declines these tokens.
  static String? _dancerOpposite(String value) {
    if (value == 'partners') return 'neighbors';
    if (_neighborSeries.contains(value)) return 'partners';
    return invertPairDancerSet(value);
  }

  static const Set<String> _neighborSeries = {
    'neighbors',
    'prevNeighbors',
    'nextNeighbors',
    'thirdNeighbors',
    'fourthNeighbors',
  };

  static const Map<String, String> _sides = {'right': 'left', 'left': 'right'};

  static const Map<String, String> _spins = {
    'clockwise': 'counterclockwise',
    'counterclockwise': 'clockwise',
  };

  /// `along` and `across` name an axis, not one end of it, so they have none.
  static const Map<String, String> _directions = {
    'up': 'down',
    'down': 'up',
    'in': 'out',
    'out': 'in',
    'rightDiagonal': 'leftDiagonal',
    'leftDiagonal': 'rightDiagonal',
  };
}

/// Every value [spec] accepts, or null for free text, which accepts any
/// string. Every other kind's domain is finite: the numeric kinds are
/// enumerated over [ParamSpec.validate]'s range.
Set<Object>? paramDomain(ParamSpec spec) {
  final choices = spec.choices;
  return switch (spec.kind) {
    ParamKind.dancerSet ||
    ParamKind.dancerPair => {...choices ?? ParamVocab.dancerSets},
    ParamKind.handedness ||
    ParamKind.shoulder => {...choices ?? ParamVocab.sides},
    ParamKind.spinDirection => {...choices ?? ParamVocab.spins},
    ParamKind.fraction => {...choices ?? ParamVocab.fractions},
    ParamKind.direction => {...choices ?? ParamVocab.directions},
    ParamKind.choice => {...?choices},
    ParamKind.rotation => {
      for (var quarters = 1; quarters <= 10; quarters++) quarters / 4,
      if (choices?.contains(ParamVocab.unspecified) ?? false)
        ParamVocab.unspecified,
    },
    ParamKind.places => {for (var i = 1; i <= 10; i++) i},
    ParamKind.beats => {for (var i = 0; i <= 64; i++) i},
    ParamKind.flag => {true, false},
    ParamKind.text => null,
  }?..removeWhere((value) => !spec.validate(value));
}
