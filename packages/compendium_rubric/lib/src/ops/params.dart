/// Shared parameter value types for the figure taxonomy.
///
/// These are the small closed enums that several figures share
/// (`docs/taxonomy.md`, "Shared parameter vocabulary"). Figure-specific value
/// sets stay with their figure.
library;

/// Which hand a figure is danced with.
///
/// For `star` this also selects the rotation direction (left hand in the centre
/// turns the ring counter-clockwise); for `chain` and `allemande` it is the
/// hand used and has no positional effect.
enum Hand {
  left('left'),
  right('right');

  const Hand(this.key);

  /// The value as it appears in the external JSON.
  final String key;

  static Hand? fromKey(String key) {
    for (final value in Hand.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// The direction a ring figure turns.
///
/// **`left` is clockwise and `right` is counter-clockwise** — the reverse of
/// the naive reading, and one of the three unrelated meanings the `turn`
/// parameter carries across the taxonomy. Always resolve `turn` per move.
enum CircleDirection {
  left('left'),
  right('right');

  const CircleDirection(this.key);

  /// The value as it appears in the external JSON.
  final String key;

  /// The sign applied to `places` to get a corner-ring offset: counter-
  /// clockwise is positive, matching `rotateHandsFourRings`.
  int get ringSign => this == CircleDirection.right ? 1 : -1;

  static CircleDirection? fromKey(String key) {
    for (final value in CircleDirection.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// The dancer sets a figure's `who` parameter can name.
///
/// Canonical spelling is **plural with numbered roles**, matching the form real
/// dance records arrive in (`docs/taxonomy.md`, "The `who` vocabulary"). The
/// older singular and role-name spellings are accepted as aliases at the JSON
/// parse boundary only, so the pure core sees exactly one vocabulary.
///
/// Note that `ones`/`twos` are **couple numbers** while `role1s`/`role2s` are
/// **roles** — two different concepts with confusable names.
enum WhoSet {
  role1s('role1s', aliases: {'larks', 'lark'}),
  role2s('role2s', aliases: {'robins', 'robin'}),
  ones('ones', aliases: {'1s', 'one'}),
  twos('twos', aliases: {'2s', 'two'}),
  partners('partners', aliases: {'partner'}),
  neighbors('neighbors', aliases: {'neighbor'}),
  prevNeighbors('prevNeighbors', aliases: {'prevNeighbor'}, distance: -1),
  nextNeighbors('nextNeighbors', aliases: {'nextNeighbor'}, distance: 1),
  thirdNeighbors('thirdNeighbors', aliases: {'thirdNeighbor'}, distance: 2),
  fourthNeighbors('fourthNeighbors', aliases: {'fourthNeighbor'}, distance: 3),
  everyone('everyone', aliases: {'all'});

  const WhoSet(this.key, {this.aliases = const {}, this.distance});

  /// The canonical value as it appears in the external JSON.
  final String key;

  /// Legacy spellings accepted on input and normalized to [key].
  final Set<String> aliases;

  /// How many **groupings** away this set reaches, signed by the direction the
  /// naming dancer travels, or `null` for a set inside the current hands four.
  ///
  /// The dance counts your current neighbours as the first, so the *next*
  /// neighbours are one grouping on (`+1`) and the *third* are two (`+2`).
  /// `prevNeighbors` reaches one grouping back against the direction of travel
  /// (`-1`).
  final int? distance;

  /// Whether this set names dancers **outside** the current hands four.
  ///
  /// A cross-hands-four reference cannot be resolved from a single band, so
  /// [Operation.apply] re-bands the set before the figure runs rather than
  /// letting the band-scoped resolvers return the empty set — which would turn
  /// the figure into a silent no-op and then compare the result against the
  /// oracle anyway.
  bool get isCrossHandsFour => distance != null;

  /// Whether the resolution rule has been verified against a worked example at
  /// this distance.
  ///
  /// Every distance now has one. `nextNeighbors`, `thirdNeighbors` and
  /// `fourthNeighbors` appear in *Sleepless at Pinewoods*, whose grand right
  /// and left goes out to the fourth neighbours and retraces past the third
  /// and the second. `prevNeighbors` — the one set reached *against* the
  /// direction of travel — appears in *Becky's Brouhaha* and *Jet Lag*, which
  /// both reach it the same way: box the gnat with the neighbours and pull by,
  /// which returns everyone to their own row facing the way they came, so the
  /// couple behind is standing in front of them.
  ///
  /// Kept as a named concept rather than inlined because the next distance to
  /// arrive should have to earn the same way.
  bool get isVerifiedDistance => distance != null;

  static WhoSet? fromKey(String key) {
    for (final value in WhoSet.values) {
      if (value.key == key || value.aliases.contains(key)) return value;
    }
    return null;
  }
}

/// The rotational sense a figure turns in.
///
/// The second of the three unrelated meanings the `turn` parameter carries
/// (`docs/taxonomy.md`, "`turn` is polymorphic"): `facing_star`, `orbit`,
/// `poussette` and `promenade` spend the `turn` slot on direction rather than
/// on an amount. `courtesy_turn` and `mad_robin` carry it under the name
/// `direction`.
enum SpinDirection {
  clockwise('clockwise'),
  counterclockwise('counterclockwise');

  const SpinDirection(this.key);

  /// The value as it appears in the external JSON.
  final String key;

  /// The sign applied to `places` to get a corner-ring offset.
  ///
  /// [rotateHandsFourRings] takes a positive offset as counter-clockwise, so
  /// clockwise is negative. This is the same convention [CircleDirection]
  /// uses, stated once per vocabulary rather than re-derived per figure.
  int get ringSign => this == SpinDirection.counterclockwise ? 1 : -1;

  static SpinDirection? fromKey(String key) {
    for (final value in SpinDirection.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// A spatial direction, spanning the whole upstream `direction` vocabulary.
///
/// Deliberately wider than any single figure implements. A value that is legal
/// here but not implemented by the figure receiving it is refused with
/// [ErrorKind.unsupportedParam] — which is only expressible if the parser can
/// *represent* it, so narrowing this enum to the implemented subset would
/// collapse "valid but out of scope" into "malformed input".
enum Direction {
  along('along'),
  across('across'),
  rightDiagonal('rightDiagonal', aliases: {'right_diagonal'}),
  leftDiagonal('leftDiagonal', aliases: {'left_diagonal'}),
  towardSet('in'),
  awayFromSet('out'),
  up('up'),
  down('down');

  const Direction(this.key, {this.aliases = const {}});

  /// The canonical value as it appears in the external JSON.
  final String key;

  /// Legacy snake_case spellings accepted on input.
  final Set<String> aliases;

  static Direction? fromKey(String key) {
    for (final value in Direction.values) {
      if (value.key == key || value.aliases.contains(key)) return value;
    }
    return null;
  }
}

/// A fraction of a figure, as the upstream `fraction` parameter kind spells it.
///
/// Used where a figure is measured in halves rather than in turns (`figure_8`,
/// `poussette`). Distinct from the numeric `turn` rotation amount.
enum TurnFraction {
  quarter('quarter'),
  half('half'),
  threeQuarter('threeQuarter'),
  full('full'),
  other('other');

  const TurnFraction(this.key);

  /// The value as it appears in the external JSON.
  final String key;

  static TurnFraction? fromKey(String key) {
    for (final value in TurnFraction.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// Where a `swing` resolves.
enum SwingWhere {
  center('center'),
  sides('sides');

  const SwingWhere(this.key);

  /// The value as it appears in the external JSON.
  final String key;

  static SwingWhere? fromKey(String key) {
    for (final value in SwingWhere.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// A figure's finishing facing.
///
/// `in`/`out` are relative to the set — a dancer on the west side facing `in`
/// faces east — while `up`/`down` run along the hall and are absolute. The
/// taxonomy accepts `endFacing` as an input synonym for this parameter.
enum FaceDirection {
  up('up'),
  down('down'),
  towardSet('in'),
  awayFromSet('out');

  const FaceDirection(this.key);

  /// The value as it appears in the external JSON.
  final String key;

  /// Whether this direction runs along the hall rather than across the set.
  bool get isAlongHall =>
      this == FaceDirection.up || this == FaceDirection.down;

  static FaceDirection? fromKey(String key) {
    for (final value in FaceDirection.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}
