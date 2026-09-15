part of '../operation.dart';

/// The axis reflections: `pass_through`, `pull_by_direction`, `zig_zag`,
/// `poussette`, `cross_trails` and `square_through`.
///
/// All six reduce to [reflectBands] over one or both axes of the hands four.
/// What separates them is which parameter chooses the axis, which values they
/// refuse, and what facing they leave — not the permutation, which is shared.

/// Refuses a `dir` value outside the along/across pair these figures define.
OpError? _requireTravelAxis(Direction dir, String moveName) {
  if (dir == Direction.along || dir == Direction.across) return null;
  return OpError(
    ErrorKind.unsupportedParam,
    '$moveName is defined for dir:along and dir:across only; '
    'dir:${dir.key} is deferred',
  );
}

/// `pass_through` — facing dancers walk forward and pass by to exchange places.
///
/// The only member of the family with an **input-facing precondition**: you
/// cannot walk through someone you are not facing. A [Facing.flexible] dancer
/// satisfies it, since an undetermined facing is resolved by the figure that
/// consumes it.
///
/// Progression is **not** baked in. The prior verifier folded a regrouping into
/// `dir:along`; here it is a plain in-hands-four swap unless the invocation
/// carries the explicit `progression` flag.
final class PassThrough extends Operation {
  const PassThrough({this.dir = Direction.along, this.shoulder = Hand.right});

  /// The travel axis: `across` the set, or `along` it (up and down the hall).
  final Direction dir;

  /// Which shoulder passes. Styling; no positional effect.
  final Hand shoulder;

  @override
  String get name => 'pass_through';

  @override
  bool get progressionEligible => true;

  @override
  OpError? checkPreconditions(Formation formation) =>
      _requireTravelAxis(dir, name);

  /// Reports dancers who are not aligned with the travel axis.
  ///
  /// This was a refusal until facing was ruled non-fatal
  /// ([WarningKind.facingPrecondition]). A dancer left facing across the set by
  /// an earlier figure can still walk along it; what the record omitted was the
  /// turn, not the travel. Dancers whose facing is undetermined are skipped
  /// entirely — a [Facing.flexible] dancer is resolved *by* this figure, so
  /// there is nothing to report about them.
  @override
  Iterable<Warning> lint(Formation formation) {
    for (final band in handsFourBands(formation)) {
      for (final row in [band.topRow, band.bottomRow]) {
        for (final id in formation.dancersInRow(row)) {
          final facing = formation.stateOf(id).facing;
          if (!facing.isConcrete) continue;
          final aligned = dir == Direction.across
              ? facing.isAcross
              : facing.isAlongHall;
          if (aligned) continue;
          return [
            Warning(
              WarningKind.facingPrecondition,
              detail:
                  'pass_through dir:${dir.key} travels that axis, but $id '
                  'faces ${facing.label}; they turn to it before passing',
            ),
          ];
        }
      }
    }
    return const [];
  }

  @override
  Result<Formation, OpError> perform(Formation formation) => Ok(
    reflectBands(
      formation,
      rows: dir == Direction.along,
      columns: dir == Direction.across,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is PassThrough && other.dir == dir && other.shoulder == shoulder;

  @override
  int get hashCode => Object.hash(name, dir, shoulder);

  @override
  String toString() => 'pass_through(${dir.key})';
}

/// `pull_by_direction` — a hand pass named by axis rather than by dancer.
///
/// Positionally identical to [PassThrough], but it names no pair and imposes no
/// facing precondition: everyone pulls past along the stated axis.
final class PullByDirection extends Operation {
  const PullByDirection({
    this.balance = false,
    this.dir = Direction.along,
    this.hand = Hand.right,
  });

  /// A balance lead-in; no end-state effect.
  final bool balance;

  /// The pass axis.
  final Direction dir;

  /// Which hand pulls. Styling; no positional effect.
  final Hand hand;

  @override
  String get name => 'pull_by_direction';

  @override
  bool get progressionEligible => true;

  @override
  OpError? checkPreconditions(Formation formation) =>
      _requireTravelAxis(dir, name);

  @override
  Result<Formation, OpError> perform(Formation formation) => Ok(
    reflectBands(
      formation,
      rows: dir == Direction.along,
      columns: dir == Direction.across,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is PullByDirection &&
      other.balance == balance &&
      other.dir == dir &&
      other.hand == hand;

  @override
  int get hashCode => Object.hash(name, balance, dir, hand);

  @override
  String toString() => 'pull_by_direction(${dir.key}, ${hand.key})';
}

/// What a `zig_zag` is said to lead into. Descriptive only.
///
/// A real ring or allemande ending is expressed as its own figure, consistent
/// with the taxonomy's stance against baking follow-ons into a move.
enum ZigZagEnder {
  none('none'),
  ring('ring'),
  allemande('allemande');

  const ZigZagEnder(this.key);

  /// The value as it appears in the external JSON.
  final String key;

  static ZigZagEnder? fromKey(String key) {
    for (final value in ZigZagEnder.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// `zig_zag` — dancers weave along the set, passing an oncoming couple.
///
/// Distance is fixed at a single pass for now, which nets the same permutation
/// as `pass_through dir:along`. A future `count`/`places` parameter would make
/// even counts net to zero and odd counts to this swap.
final class ZigZag extends Operation {
  const ZigZag({
    this.who = WhoSet.partners,
    this.turn = Hand.left,
    this.ender = ZigZagEnder.none,
  });

  /// Who weaves together. Descriptive; no end-position effect.
  final WhoSet who;

  /// Which shoulder starts the weave. Styling; no end-position effect. (`turn`
  /// here is a left/right token, not an amount and not a spin direction — see
  /// the `turn` polymorphism note in `docs/taxonomy.md`.)
  final Hand turn;

  /// A descriptive tag for what the weave leads into; no end-state effect.
  final ZigZagEnder ender;

  @override
  String get name => 'zig_zag';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  bool get progressionEligible => true;

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      Ok(reflectBands(formation, rows: true));

  @override
  bool operator ==(Object other) =>
      other is ZigZag &&
      other.who == who &&
      other.turn == turn &&
      other.ender == ender;

  @override
  int get hashCode => Object.hash(name, who, turn, ender);

  @override
  String toString() => 'zig_zag(${who.key}, ${turn.key}, ${ender.key})';
}

/// `poussette` — two couples join hands and push and pull each other around a
/// shared centre.
///
/// A full poussette returns home; a half trades the two couples end for end,
/// which is a global row swap. Quarter and three-quarter amounts are deferred
/// along with the rest of the quarter-turn family.
final class Poussette extends Operation {
  const Poussette({
    this.who = WhoSet.ones,
    this.whom = WhoSet.neighbors,
    this.half = TurnFraction.half,
    this.turn = SpinDirection.clockwise,
  });

  /// One of the two poussetting couples.
  final WhoSet who;

  /// The other couple.
  final WhoSet whom;

  /// How far around. Only `half` and `full` are implemented.
  final TurnFraction half;

  /// The spin sense. Irrelevant to a half — 180° lands the same either way.
  final SpinDirection turn;

  @override
  String get name => 'poussette';

  @override
  Iterable<WhoSet?> get dancerSets => [who, whom];

  @override
  bool get progressionEligible => true;

  @override
  OpError? checkPreconditions(Formation formation) {
    if (half == TurnFraction.half || half == TurnFraction.full) return null;
    return OpError(
      ErrorKind.unsupportedParam,
      'poussette supports half:half and half:full; half:${half.key} is '
      'deferred along with the rest of the quarter-turn family',
    );
  }

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      Ok(reflectBands(formation, rows: half == TurnFraction.half));

  @override
  bool operator ==(Object other) =>
      other is Poussette &&
      other.who == who &&
      other.whom == whom &&
      other.half == half &&
      other.turn == turn;

  @override
  int get hashCode => Object.hash(name, who, whom, half, turn);

  @override
  String toString() => 'poussette(${who.key}, ${half.key})';
}

/// `cross_trails` — pass across, then pass along, netting a diagonal swap.
///
/// Both `who` parameters are descriptive: they name whom you meet on each pass
/// but do not change the permutation, which is the composition of the two
/// reflections.
///
/// Facing comes from the **second** pass, the one along the set: a dancer
/// finishing in the band's top row faces up and one finishing in its bottom row
/// faces down — that is, out along the set in the direction they travelled.
final class CrossTrails extends Operation {
  const CrossTrails({
    this.who = WhoSet.partners,
    this.dir = Direction.across,
    this.shoulder = Hand.right,
    this.who2 = WhoSet.neighbors,
  });

  /// Whom you pass on the first (across) pass. Descriptive.
  final WhoSet who;

  /// The axis of the first pass. Only `across` is defined; `along` degenerates
  /// to a no-op and is out of scope.
  final Direction dir;

  /// Dialect styling; no effect.
  final Hand shoulder;

  /// Whom you pass on the second (along) pass. Descriptive.
  final WhoSet who2;

  @override
  String get name => 'cross_trails';

  @override
  Iterable<WhoSet?> get dancerSets => [who, who2];

  @override
  bool get progressionEligible => true;

  @override
  OpError? checkPreconditions(Formation formation) {
    if (dir == Direction.across) return null;
    return OpError(
      ErrorKind.unsupportedParam,
      'cross_trails is defined for dir:across only; dir:${dir.key} degenerates '
      'to a no-op and is deferred',
    );
  }

  @override
  Result<Formation, OpError> perform(Formation formation) => Ok(
    reflectBands(
      formation,
      rows: true,
      columns: true,
      facing: (before, after, band) =>
          after.row == band.topRow ? Facing.up : Facing.down,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is CrossTrails &&
      other.who == who &&
      other.dir == dir &&
      other.shoulder == shoulder &&
      other.who2 == who2;

  @override
  int get hashCode => Object.hash(name, who, dir, shoulder, who2);

  @override
  String toString() => 'cross_trails(${who.key}, ${dir.key}, ${who2.key})';
}

/// `square_through` — a chain of pull-bys alternating across and along, turning
/// to face a new dancer after each.
///
/// The net effect depends only on `places mod 4`, because the two reflections
/// generate a group of order four: one pull-by is a column swap, two compose to
/// the diagonal, three to a row swap, and four return everyone home.
final class SquareThrough extends Operation {
  const SquareThrough({
    this.who = WhoSet.partners,
    this.who2 = WhoSet.neighbors,
    this.balance = true,
    this.hand = Hand.right,
    this.places = 4,
  });

  /// The odd (across) pull-by relationship. Descriptive.
  final WhoSet who;

  /// The even (along) pull-by relationship. Descriptive.
  final WhoSet who2;

  /// A balance lead-in; styling and beats only.
  final bool balance;

  /// Which hand pulls. Styling; no positional effect.
  final Hand hand;

  /// The number of pull-bys.
  final int places;

  @override
  String get name => 'square_through';

  @override
  Iterable<WhoSet?> get dancerSets => [who, who2];

  @override
  bool get progressionEligible => true;

  @override
  Result<Formation, OpError> perform(Formation formation) {
    final net = places % 4;
    return Ok(
      reflectBands(
        formation,
        columns: net == 1 || net == 2,
        rows: net == 2 || net == 3,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SquareThrough &&
      other.who == who &&
      other.who2 == who2 &&
      other.balance == balance &&
      other.hand == hand &&
      other.places == places;

  @override
  int get hashCode => Object.hash(name, who, who2, balance, hand, places);

  @override
  String toString() => 'square_through(${who.key}, $places)';
}
