// Figure parameters in the ContraDB Advanced translation.
//
// ContraDB's `figure` operator takes the figure's parameters as POSITIONAL
// filters after the move name (`["figure", "swing", "partners", "*", 16]`),
// compared with the figure's stored `parameter_values` by
// `param_passes_filter?` (lib/filter_dances.rb). The Collection names its
// parameters; this file maps each one that ContraDB also has onto its position
// and value spelling, and reports the ones it cannot.
//
// A parameter ContraDB has no counterpart for, or an app value with no exact
// ContraDB value, is LEFT OUT of the filter (the figure is still searched, by
// its other parameters) and named in [ContraDbParamTranslation.ignored], so the
// caller can say the search is not the one the panel describes (usually
// broader; narrower under a negation). That is deliberately not a refusal of
// the figure.
//
// The positions and value vocabularies come from reading ContraDB's
// `app/javascript/libfigure/figure.js` and `param.js`, and the value mappings
// were checked against the importer (`contradb_figure_dialect.dart`) on
// rendered figure lines. A few facts from that reading shape the code and are
// easy to get wrong:
//
// - `*` means "any" at every formal EXCEPT a free-text one (`contra corners`
//   and `turn alone`, position 1), where it is just a keyword: those positions
//   are filled with `''`.
// - An alias (`see saw`, `swat the flea`) pins its parameter only when the
//   filter has NO parameters (`alias_filter`), so an alias leaf that has any
//   must pin it itself.
// - Sending more positional items than the move has formals raises on ContraDB.
// - ContraDB maps a dancer value to a category before comparing
//   (`dancers_category`): a `neighbors` filter also matches stored `prev`,
//   `next`, `3rd` and `4th neighbors`, and `shadows` also matches `2nd shadows`.
//   The Collection keeps those apart, so those two values over-match, and the
//   five values that are only ever stored under another category can never
//   match: they are left out, not sent.
//
// The figure NAME and the no-parameter expression stay in
// `_contraDbForCollectionMove` (`contradb_advanced_filter.dart`); this file only
// adds the parameters, and a test checks the two agree.
library;

/// The result of applying a leaf's parameters to a move's ContraDB figure.
class ContraDbParamTranslation {
  const ContraDbParamTranslation(this.expression, this.ignored);

  /// The ContraDB filter with the parameters applied, or `null` when none of
  /// them could be (the caller then uses the move's plain expression).
  final List<Object?>? expression;

  /// `move.param` for every parameter the leaf set that was left out.
  final Set<String> ignored;
}

/// Translates [params] of the Collection move [move] onto ContraDB's figure.
///
/// Returns `null` for a move this file has no parameter table for.
ContraDbParamTranslation? translateContraDbFigureParams(
  String move,
  Map<String, Object?> params,
) {
  final spec = _moves[move];
  if (spec == null) return null;
  final applied = <String>{};
  final expression = spec(params, applied);
  final ignored = {
    for (final entry in params.entries)
      if (!applied.contains(entry.key) && entry.value != 'unspecified')
        '$move.${entry.key}',
  };
  return ContraDbParamTranslation(applied.isEmpty ? null : expression, ignored);
}

/// Every ContraDB figure the table can send parameters to: the Collection move
/// it serves, the figure's ContraDB name, and the position of each app
/// parameter, for tests that check the table against the taxonomy and against
/// ContraDB's formal-parameter lists.
Iterable<({String move, String figure, Map<String, int> positions})>
get contraDbParamTable => [
  for (final entry in _alts.entries)
    for (final alt in entry.value)
      (
        move: entry.key,
        figure: alt.name,
        positions: {
          for (final param in alt.params.entries)
            param.key: param.value.position,
        },
      ),
];

// ---------------------------------------------------------------------------
// Value maps. Each returns the ContraDB filter value, [_skip] (no exact
// counterpart: the parameter is left out), or a [_OneOf].
// ---------------------------------------------------------------------------

final class _Skip {
  const _Skip();
}

const Object _skip = _Skip();

/// One app value that is several ContraDB values on one figure: the figure is
/// searched once per value and the results joined with `or`.
final class _OneOf {
  const _OneOf(this.values);
  final List<Object?> values;
}

typedef _Map = Object? Function(Object? value);

Object? _bool(Object? v) => v is bool ? v : _skip;

/// Beats: an integer, sent as a number (`to_s` equality, so `8.0` would not
/// equal a stored `8`).
Object? _beats(Object? v) =>
    v is num && v > 0 && v == v.truncate() ? v.truncate() : _skip;

/// Dancer sets, app token -> the string ContraDB stores. `neighbors` and
/// `shadows` over-match (see the library comment); the tokens the Collection
/// has but ContraDB cannot match are absent, so they are left out.
const Map<String, String> _dancerTokens = {
  'role1s': 'gentlespoons',
  'role2s': 'ladles',
  'ones': 'ones',
  'twos': 'twos',
  'partners': 'partners',
  'neighbors': 'neighbors',
  'everyone': 'everyone',
  'sameRoles': 'same roles',
  'firstCorners': 'first corners',
  'secondCorners': 'second corners',
  'centers': 'centers',
  'shadows': 'shadows',
};

Object? _dancer(Object? v) => _dancerTokens[v] ?? _skip;

/// A single named dancer (`dolphin hey`'s `whom`).
const Map<String, String> _singleTokens = {
  'onesRole1': 'first gentlespoon',
  'onesRole2': 'first ladle',
  'twosRole1': 'second gentlespoon',
  'twosRole2': 'second ladle',
};

Object? _single(Object? v) => _singleTokens[v] ?? _skip;

/// A hand or a shoulder: ContraDB stores `true` for the right one.
Object? _hand(Object? v) => switch (v) {
  'right' => true,
  'left' => false,
  _ => _skip,
};

/// Only `right`: `do si do` and `box the gnat` leaves, whose left-handed forms
/// are the separate `see saw` and `swat the flea` moves.
Object? _rightOnly(Object? v) => v == 'right' ? true : _skip;

/// Only `left`: the alias moves, whose pinned parameter is already `false`.
Object? _leftOnly(Object? v) => v == 'left' ? false : _skip;

/// Only `false`: a `swat the flea` with a balance is not a figure the
/// importer reads (it falls to `custom`), so only the plain form is exact.
Object? _falseOnly(Object? v) => v == false ? false : _skip;

/// A slide or circle direction: ContraDB stores `true` for left.
Object? _slide(Object? v) => switch (v) {
  'left' => true,
  'right' => false,
  _ => _skip,
};

/// A spin where ContraDB stores `true` for clockwise (`facing star`,
/// `promenade`, `poussette`).
Object? _spinClockwise(Object? v) => switch (v) {
  'clockwise' => true,
  'counterclockwise' => false,
  _ => _skip,
};

/// A rotation in turns (`1.5`) -> the degrees ContraDB stores (`540`), for the
/// quarter-turn multiples it offers (90..900).
Object? _rotation(Object? v) {
  if (v is! num) return _skip;
  final quarters = v * 4;
  if (quarters != quarters.truncate() || quarters < 1 || quarters > 10) {
    return _skip;
  }
  return quarters.truncate() * 90;
}

/// "N places" -> `90 * N` degrees (1..10).
Object? _places(Object? v) {
  if (v is! num || v != v.truncate() || v < 1 || v > 10) return _skip;
  return v.truncate() * 90;
}

/// `square through` only offers 180, 270 and 360 degrees (2, 3 or 4 places).
Object? _placesSquare(Object? v) =>
    v is num && (v == 2 || v == 3 || v == 4) ? v.truncate() * 90 : _skip;

/// A half or full figure 8 / poussette, compared as a float.
Object? _fraction(Object? v) => switch (v) {
  'half' => 0.5,
  'full' => 1.0,
  _ => _skip,
};

_Map _strings(Map<String, Object?> table) =>
    (v) => table.containsKey(v) ? table[v] : _skip;

Object? _acrossOnly(Object? v) => v == 'across' ? 'across' : _skip;

final _chainWhere = _strings(const {
  'across': 'across',
  'leftDiagonal': 'left diagonal',
  'rightDiagonal': 'right diagonal',
});
final _gridWhere = _strings(const {'across': 'across', 'along': 'along'});
final _movingMap = _strings(const {
  'all': 'all',
  'center': 'center',
  'outsides': 'outsides',
});

/// `forward` under-matches: a ContraDB `forward then backward` hall imports as
/// `forward` with its ender dropped. `forwardThenBackward` is never imported.
final _hallFacing = _strings(const {
  'forward': 'forward',
  'backward': 'backward',
});
final _hallEnder = _strings(const {
  'none': '',
  'turnCouple': 'turn-couple',
  'turnAlone': 'turn-alone',
  'circle': 'circle',
  'cozy': 'cozy',
  'cloverleaf': 'cloverleaf',
  'threadNeedle': 'thread-needle',
  'rightHandHigh': 'right-high',
  'slidingDoors': 'sliding-doors',
});
final _gateFacing = _strings(const {
  'up': 'up',
  'down': 'down',
  'in': 'in',
  'out': 'out',
});
final _grip = _strings(const {
  'none': '',
  'wristGrip': 'wrist grip',
  'handsAcross': 'hands across',
});
final _swingPrefix = _strings(const {
  'none': 'none',
  'balance': 'balance',
  'meltdown': 'meltdown',
});
final _heyLength = _strings(const {'full': 'full', 'half': 'half'});

/// `figure 8`'s `where`: `above` is stored both as `''` (silent) and as
/// `above` (printed), and the importer reads both as `above`.
Object? _figure8Where(Object? v) => switch (v) {
  'below' => 'below',
  'across' => 'across',
  'above' => const _OneOf(['', 'above']),
  _ => _skip,
};

/// `pass through` where: `across` is exact; `along` under-matches (diagonal
/// passes import as `along`).
final _passWhere = _gridWhere;

/// `promenade` where: `along` is exact; `across` under-matches.
final _promenadeWhere = _gridWhere;

/// A `hey` ricochet: only `true` has a ContraDB value, and it over-matches
/// when the first pass is not a pair.
Object? _trueOnly(Object? v) => v == true ? true : _skip;

// ---------------------------------------------------------------------------
// The tables.
// ---------------------------------------------------------------------------

final class _P {
  const _P(this.position, this.map);
  final int position;
  final _Map map;
}

/// One ContraDB figure that a Collection move can be stored as.
final class _Alt {
  const _Alt(
    this.name,
    this.params, {
    this.pins = const {},
    this.textPositions = const {},
  });

  /// The ContraDB figure name.
  final String name;

  /// App parameter name -> its position and value map.
  final Map<String, _P> params;

  /// Positions this figure always pins when any parameter is given (an alias's
  /// parameter).
  final Map<int, Object?> pins;

  /// Free-text positions, where an unconstrained slot is `''`, not `*`.
  final Set<int> textPositions;
}

/// The figure expression for [alt], applying the parameters it can. Adds the
/// app names it used to [applied]; returns the plain figure when none were.
List<Object?> _figure(
  _Alt alt,
  Map<String, Object?> params,
  Set<String> applied,
) {
  final fixed = <int, Object?>{};
  final used = <String>{};
  _OneOf? choice;
  int? choicePosition;
  for (final entry in params.entries) {
    final p = alt.params[entry.key];
    if (p == null) continue;
    final value = p.map(entry.value);
    if (value is _Skip) continue;
    used.add(entry.key);
    if (value is _OneOf) {
      choice = value;
      choicePosition = p.position;
    } else {
      fixed[p.position] = value;
    }
  }
  applied.addAll(used);
  if (used.isEmpty) return ['figure', alt.name];

  List<Object?> row(Map<int, Object?> values) {
    final all = {...alt.pins, ...values};
    var last = 0;
    for (final position in all.keys) {
      if (position > last) last = position;
    }
    return [
      'figure',
      alt.name,
      for (var i = 0; i <= last; i++)
        all.containsKey(i)
            ? all[i]
            : alt.textPositions.contains(i)
            ? ''
            : '*',
    ];
  }

  if (choice == null) return row(fixed);
  final rows = [
    for (final value in choice.values) row({...fixed, choicePosition!: value}),
  ];
  return rows.length == 1 ? rows.single : ['or', ...rows];
}

typedef _Build =
    List<Object?> Function(Map<String, Object?> params, Set<String> applied);

/// Excludes a move's alias from a figure that ContraDB stores as the same move
/// (`do si do` minus `see saw`), because the Collection keeps them apart.
_Build _minusAlias(List<_Alt> alts, String alias) =>
    (params, applied) => [
      '&',
      _figure(alts.single, params, applied),
      [
        'not',
        ['figure', alias],
      ],
    ];

_Build _plain(_Alt alt) =>
    (params, applied) => _figure(alt, params, applied);

// -- dancers / hands / places, the shared shapes ----------------------------

const _who = _P(0, _dancer);
_P _beatsPos(int position) => _P(position, _beats);

final _Alt _allemandeAlt = _Alt('allemande', {
  'who': _who,
  'hand': const _P(1, _hand),
  'travel': const _P(2, _rotation),
  'beats': _beatsPos(3),
});

/// The orbit figure's own positions. The importer puts an orbit's beats on the
/// `meanwhile` container and leaves the inner allemande with the default 8, so
/// the orbit alternative carries no beats filter and is dropped for any other
/// beats value (see [_allemande]).
final _Alt _orbitAlt = _Alt('allemande orbit', {
  'who': _who,
  'hand': const _P(1, _hand),
  'travel': const _P(2, _rotation),
});

/// `allemande orbit` only exists for a pair (`subject_pair`).
const Set<String> _orbitDancers = {
  'gentlespoons',
  'ladles',
  'ones',
  'twos',
  'first corners',
  'second corners',
};

List<Object?> _allemande(Map<String, Object?> params, Set<String> applied) {
  final main = _figure(_allemandeAlt, params, applied);
  final who = params['who'] == null ? null : _dancer(params['who']);
  final beats = params['beats'] == null ? null : _beats(params['beats']);
  final orbitPossible =
      (who == null || who is _Skip || _orbitDancers.contains(who)) &&
      (beats == null || beats is _Skip || beats == 8);
  if (!orbitPossible) return main;
  final orbit = _figure(_orbitAlt, params, <String>{});
  return ['or', main, orbit];
}

final _Alt _pullByDancers = _Alt('pull by dancers', {
  'who': _who,
  'balance': const _P(1, _bool),
  'hand': const _P(2, _hand),
  'beats': _beatsPos(3),
});

final _Alt _pullByDirection = _Alt('pull by direction', {
  'balance': const _P(0, _bool),
  'where': const _P(1, _acrossOnly),
  'hand': const _P(2, _hand),
  'beats': _beatsPos(3),
});

/// `pull_by` is two ContraDB figures. A `who` can only be the dancers one, and
/// a `where` of `across` only the direction one; with neither, a leaf is
/// either, so both are searched.
List<Object?> _pullBy(Map<String, Object?> params, Set<String> applied) {
  final who = params['who'] == null ? _skip : _dancer(params['who']);
  final across = params['where'] == 'across';
  if (who is! _Skip) {
    return _figure(_pullByDancers, params, applied);
  }
  if (across) return _figure(_pullByDirection, params, applied);
  final dancers = _figure(_pullByDancers, params, applied);
  final direction = _figure(_pullByDirection, params, applied);
  return ['or', dancers, direction];
}

final Map<String, List<_Alt>> _alts = {
  'allemande': [_allemandeAlt, _orbitAlt],
  'pull_by': [_pullByDancers, _pullByDirection],
  'arch_and_dive': [
    _Alt('arch & dive', {'who': _who, 'beats': _beatsPos(1)}),
  ],
  'balance': [
    _Alt('balance', {'who': _who, 'beats': _beatsPos(1)}),
  ],
  'balance_the_ring': [
    _Alt('balance the ring', {'beats': _beatsPos(0)}),
  ],
  'box_circulate': [
    _Alt('box circulate', {
      'who': _who,
      'balance': const _P(1, _bool),
      'hand': const _P(2, _hand),
      'beats': _beatsPos(3),
    }),
  ],
  'box_the_gnat': [
    _Alt('box the gnat', {
      'who': _who,
      'balance': const _P(1, _bool),
      'hand': const _P(2, _rightOnly),
      'beats': _beatsPos(3),
    }),
  ],
  'butterfly_whirl': [
    _Alt('butterfly whirl', {'beats': _beatsPos(0)}),
  ],
  'california_twirl': [
    _Alt('California twirl', {'who': _who, 'beats': _beatsPos(1)}),
  ],
  'chain': [
    _Alt('chain', {
      'who': _who,
      'hand': const _P(1, _hand),
      'where': _P(2, _chainWhere),
      'beats': _beatsPos(3),
    }),
  ],
  'circle': [
    _Alt('circle', {
      'direction': const _P(0, _slide),
      'places': const _P(1, _places),
      'beats': _beatsPos(2),
    }),
  ],
  'contra_corners': [
    _Alt(
      'contra corners',
      {'who': _who, 'beats': _beatsPos(2)},
      textPositions: const {1},
    ),
  ],
  'cross_trails': [
    _Alt('cross trails', {
      'who': _who,
      'where': _P(1, _gridWhere),
      'shoulder': const _P(2, _hand),
      'who2': const _P(3, _dancer),
      'beats': _beatsPos(4),
    }),
  ],
  'do_si_do': [
    _Alt('do si do', {
      'who': _who,
      'shoulder': const _P(1, _rightOnly),
      'travel': const _P(2, _rotation),
      'beats': _beatsPos(3),
    }),
  ],
  'dolphin_hey': [
    _Alt('dolphin hey', {
      'who': _who,
      'whom': const _P(1, _single),
      'shoulder': const _P(2, _hand),
      'beats': _beatsPos(3),
    }),
  ],
  'down_the_hall': [_hall('down the hall')],
  'up_the_hall': [_hall('up the hall')],
  'facing_star': [
    _Alt('facing star', {
      'who': _who,
      'direction': const _P(1, _spinClockwise),
      'places': const _P(2, _places),
      'beats': _beatsPos(3),
    }),
  ],
  'figure_8': [
    _Alt('figure 8', {
      'who': _who,
      'where': const _P(1, _figure8Where),
      'fraction': const _P(3, _fraction),
      'beats': _beatsPos(4),
    }),
  ],
  'form_a_long_wave': [
    _Alt('form a long wave', {
      'who': _who,
      'in': const _P(1, _bool),
      'out': const _P(2, _bool),
      'balance': const _P(3, _bool),
      'beats': _beatsPos(4),
    }),
  ],
  'form_long_waves': [
    _Alt('form long waves', {'who': _who, 'beats': _beatsPos(1)}),
  ],
  'gate': [
    _Alt('gate', {
      'who': _who,
      'whom': const _P(1, _dancer),
      'endFacing': _P(2, _gateFacing),
      'beats': _beatsPos(3),
    }),
  ],
  'give_and_take': [
    _Alt('give & take', {
      'who': _who,
      'whom': const _P(1, _dancer),
      'give': const _P(2, _bool),
      'beats': _beatsPos(3),
    }),
  ],
  'hey': [
    _Alt('hey', {
      'pass1': _who,
      'shoulder': const _P(2, _hand),
      'length': _P(3, _heyLength),
      'where': const _P(4, _acrossOnly),
      'rico1': const _P(5, _trueOnly),
      'rico2': const _P(6, _trueOnly),
      'rico3': const _P(7, _trueOnly),
      'rico4': const _P(8, _trueOnly),
      'beats': _beatsPos(9),
    }),
  ],
  'long_lines': [
    _Alt('long lines', {'goBack': const _P(0, _bool), 'beats': _beatsPos(1)}),
  ],
  'mad_robin': [
    _Alt('mad robin', {
      'who': _who,
      'travel': const _P(1, _rotation),
      'beats': _beatsPos(2),
    }),
  ],
  'pass_by': [
    _Alt('pass by', {
      'who': _who,
      'shoulder': const _P(1, _hand),
      'beats': _beatsPos(2),
    }),
  ],
  'pass_through': [
    _Alt('pass through', {
      'where': _P(0, _passWhere),
      'shoulder': const _P(1, _hand),
      'beats': _beatsPos(2),
    }),
  ],
  'petronella': [
    _Alt('petronella', {'balance': const _P(0, _bool), 'beats': _beatsPos(1)}),
  ],
  'poussette': [
    _Alt('poussette', {
      'fraction': const _P(0, _fraction),
      'who': const _P(1, _dancer),
      'whom': const _P(2, _dancer),
      // ContraDB stores a clockwise poussette as `true` and writes it "back
      // then left", which the importer reads as clockwise since #2121 (it read
      // the sides the other way round before, and this mapping was inverted
      // to match).
      'direction': const _P(3, _spinClockwise),
      'beats': _beatsPos(4),
    }),
  ],
  'promenade': [
    _Alt('promenade', {
      'who': _who,
      'where': _P(1, _promenadeWhere),
      'direction': const _P(2, _spinClockwise),
      'beats': _beatsPos(3),
    }),
  ],
  'revolving_door': [
    _Alt('revolving door', {
      'who': _who,
      'hand': const _P(1, _hand),
      'whom': const _P(2, _dancer),
      'beats': _beatsPos(3),
    }),
  ],
  'right_left_through': [
    _Alt('right left through', {
      'where': const _P(0, _acrossOnly),
      'beats': _beatsPos(1),
    }),
  ],
  'roll_away': [
    _Alt('roll away', {
      'who': _who,
      'whom': const _P(1, _dancer),
      'beats': _beatsPos(3),
    }),
  ],
  'rory_o_more': [
    _Alt("Rory O'More", {
      'who': _who,
      'balance': const _P(1, _bool),
      'slide': const _P(2, _slide),
      'beats': _beatsPos(3),
    }),
  ],
  'see_saw': [
    _Alt(
      'see saw',
      {
        'who': _who,
        'shoulder': const _P(1, _leftOnly),
        'travel': const _P(2, _rotation),
        'beats': _beatsPos(3),
      },
      pins: const {1: false},
    ),
  ],
  'shoulder_round': [
    _Alt('gyre', {
      'who': _who,
      'shoulder': const _P(1, _hand),
      'travel': const _P(2, _rotation),
      'beats': _beatsPos(3),
    }),
  ],
  'slice': [
    _Alt('slice', {'slice': const _P(0, _slide), 'beats': _beatsPos(3)}),
  ],
  'slide_along_set': [
    _Alt('slide along set', {
      'slide': const _P(0, _slide),
      'beats': _beatsPos(1),
    }),
  ],
  'square_through': [
    _Alt('square through', {
      'who': _who,
      'who2': const _P(1, _dancer),
      'balance': const _P(2, _bool),
      'hand': const _P(3, _hand),
      'places': const _P(4, _placesSquare),
      'beats': _beatsPos(5),
    }),
  ],
  'stand_still': [
    _Alt('stand still', {'beats': _beatsPos(0)}),
  ],
  'star': [
    _Alt('star', {
      'hand': const _P(0, _hand),
      'places': const _P(1, _places),
      'grip': _P(2, _grip),
      'beats': _beatsPos(3),
    }),
  ],
  'swat_the_flea': [
    _Alt(
      'swat the flea',
      {
        'who': _who,
        'balance': const _P(1, _falseOnly),
        'hand': const _P(2, _leftOnly),
        'beats': _beatsPos(3),
      },
      pins: const {2: false},
    ),
  ],
  'swing': [
    _Alt('swing', {
      'who': _who,
      'prefix': _P(1, _swingPrefix),
      'beats': _beatsPos(2),
    }),
  ],
  'turn_alone': [
    _Alt(
      'turn alone',
      {'who': _who, 'beats': _beatsPos(2)},
      textPositions: const {1},
    ),
  ],
  'zig_zag': [
    _Alt('zig zag', {
      'who': _who,
      'slide': const _P(1, _slide),
      'beats': _beatsPos(3),
    }),
  ],
};

_Alt _hall(String name) => _Alt(name, {
  'who': _who,
  'moving': _P(1, _movingMap),
  'facing': _P(2, _hallFacing),
  'ender': _P(3, _hallEnder),
  'beats': _beatsPos(4),
});

/// Per move: how its leaf parameters become a ContraDB expression.
final Map<String, _Build> _moves = {
  for (final entry in _alts.entries)
    if (entry.key != 'allemande' && entry.key != 'pull_by')
      entry.key: switch (entry.key) {
        'do_si_do' => _minusAlias(entry.value, 'see saw'),
        'box_the_gnat' => _minusAlias(entry.value, 'swat the flea'),
        _ => _plain(entry.value.single),
      },
  'allemande': _allemande,
  'pull_by': _pullBy,
};
