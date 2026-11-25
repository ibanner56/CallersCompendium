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
/// kind or a new [ParamVocab] value cannot be added without deciding its
/// opposite. A group only English has ([_englishPairs]) is pinned by pair, and
/// a new English-only group gets none until it is added there. Pair inversion is not restated: it is [invertPairDancerSet], the
/// single source of truth the renderer and importers already share. On top of
/// it, `partners` is opposed by `neighbors`, every neighbor-series token is
/// opposed by `partners`, and four pairs of English's own groups are opposed
/// to each other ([_englishPairs]).
///
/// The `unspecified` sentinel is its own opposite — "not stated" stays not
/// stated — so a kind keeps its coverage when a slot opts into it.
abstract final class ParamOpposites {
  /// How far [kind] has opposites.
  ///
  /// A shoulder is total for the values contra stores; ECD's `cloverleaf`
  /// turn single (ADR-006 §9.3) is a shoulder value with no opposite, so
  /// [of] gives it none. Callers only ask whether a kind has any.
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
    ParamKind.number ||
    ParamKind.fraction ||
    ParamKind.beats ||
    ParamKind.text ||
    ParamKind.flag => OppositeCoverage.none,
    // A list of dancers (ECD's `who`) is not one token with an opposite.
    ParamKind.dancerList => OppositeCoverage.none,
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
  /// partner/neighbor swap, else one of English's own pairs
  /// ([_englishPairs]). `partners` ↔ `neighbors`, and every other member of
  /// the neighbor series ([_neighborSeries]) is opposed by `partners`, so
  /// "other who" always offers the partner whichever neighbor was chosen.
  ///
  /// The swap is deliberately not an involution: `nextNeighbors` →
  /// `partners` → `neighbors`. The renderer's other-pair wording and the
  /// importers keep using [invertPairDancerSet], which still declines these
  /// tokens, and English's pairs. A custom figure's opposite slot
  /// (`{otherWho}`) renders this swap.
  static String? _dancerOpposite(String value) {
    if (value == 'partners') return 'neighbors';
    if (_neighborSeries.contains(value)) return 'partners';
    return _englishPairs[value] ?? invertPairDancerSet(value);
  }

  /// The pairs among the groups only English has (`ecdSelectors`): the top
  /// and the bottom of the set, its ends and its middles, the left-hand and
  /// the right-hand file, and the two diagonals. The maintainer chose these
  /// four (#2294 follow-up); ADR-006 names no opposite for any English group,
  /// so every other one, such as `couples` or `actives`, has none.
  ///
  /// None of these tokens is in [ParamVocab.dancerSets], which a figure made
  /// for contra, square or an unknown form validates against. The one
  /// exception is `ends`, which a Rory O'More's `twoPlaces` (contra taxonomy
  /// v40) lists in its own choices; its opposite `middles` is not among them,
  /// so a compound's opposite slot on that param accepts no `ends` argument
  /// (`compound_definition.dart` keeps only values whose opposite the slot
  /// takes).
  static const Map<String, String> _englishPairs = {
    'top': 'bottom',
    'bottom': 'top',
    'ends': 'middles',
    'middles': 'ends',
    'leftFile': 'rightFile',
    'rightFile': 'leftFile',
    'firstDiagonals': 'secondDiagonals',
    'secondDiagonals': 'firstDiagonals',
  };

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
/// string. Empty for a [ParamKind.dancerList], whose values are lists. Every
/// other kind's domain is finite: the numeric kinds are enumerated over
/// [ParamSpec.validate]'s range.
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
    ParamKind.places => {
      for (var i = 1; i <= 10; i++) i,
      if (choices?.contains(ParamVocab.unspecified) ?? false)
        ParamVocab.unspecified,
    },
    ParamKind.number => {for (var i = 0; i <= 99; i++) i},
    ParamKind.beats => {for (var i = 0; i <= 64; i++) i},
    ParamKind.flag => {true, false},
    ParamKind.text => null,
    // A list of dancers (ECD's `who`) holds no single value, so no single
    // value fills it: a compound cannot bind one.
    ParamKind.dancerList => <Object>{},
  }?..removeWhere((value) => !spec.validate(value));
}
