/// The handful of permutations the figure taxonomy is actually built from.
///
/// Read end to end, `docs/taxonomy.md` describes far fewer *transformations*
/// than it does figures: most of the thirty-odd figures collapse onto a pair
/// swap, an axis reflection, or a ring rotation, and differ only in which
/// dancers they select, which parameter values they refuse, and what facing
/// they leave behind. Those three shared permutations live here so that a
/// correction to one of them lands everywhere at once rather than in the
/// dozen-odd figures that would otherwise each re-derive it.
///
/// Everything here is a pure function of state, like the figures that call it.
library;

import '../domain/dancer.dart';
import '../domain/facing.dart';
import '../domain/formation.dart';
import '../domain/position.dart';
import '../geometry/geometry.dart';
import 'params.dart';
import 'who.dart';

/// Two dancers a figure acts on together.
typedef DancerPair = ({DancerId a, DancerId b});

/// A two-row band of the set, as [handsFourBands] reports it.
typedef Band = ({int topRow, int bottomRow});

/// How far around a rotation figure turns, reduced to the four cases the
/// taxonomy actually distinguishes.
///
/// Every figure taking a numeric `turn` (or, for `orbit`, an `amount`) sorts
/// its behaviour into exactly these buckets: a whole turn is the identity, a
/// half swaps the pair, and a quarter or three-quarter lands the pair in a
/// short wave (§8.5.1). The two quarter cases share a handedness and differ
/// only in that a three-quarter is a half turn taken first, which swaps which
/// dancers finish in the centre of the wave.
enum RotationAmount {
  whole,
  half,
  quarter,
  threeQuarter;

  /// Whether this amount lands the pair in a wave rather than on a cell they
  /// could have reached by standing still or swapping.
  ///
  /// The figures that have not been given a wave landing refuse on this, so
  /// they refuse both quarter cases together rather than only the literal
  /// [quarter].
  bool get landsInWave =>
      this == RotationAmount.quarter || this == RotationAmount.threeQuarter;
}

/// Classifies a numeric rotation amount.
///
/// Only the fractional part matters: 1.5 and 2.5 are both half turns because
/// the extra full revolutions return the dancers to where they started.
RotationAmount rotationAmountOf(num turn) {
  final quarters = ((turn % 1) * 4).round();
  return switch (quarters) {
    0 => RotationAmount.whole,
    1 => RotationAmount.quarter,
    2 => RotationAmount.half,
    _ => RotationAmount.threeQuarter,
  };
}

/// Every pair [who] names, gathered across all complete hands four.
///
/// The set-wide counterpart of [resolveWhoPairs], which works one band at a
/// time. Waiting-out couples belong to no band and are therefore never
/// selected, which is the correct scoping for every figure using this: they
/// are all documented as acting "within the hands four".
List<DancerPair> whoPairsInSet(Formation formation, WhoSet who) => [
  for (final band in handsFourBands(formation))
    ...resolveWhoPairs(
      formation,
      who,
      topRow: band.topRow,
      bottomRow: band.bottomRow,
    ),
];

/// Whether [a] and [b] stand adjacent — sharing a row or a column.
///
/// The physical availability test behind the couple-hold figures: a two-handed
/// hold (`two_hand_turn`, `courtesy_turn`, `turn_as_couples`) and a facing
/// trade (`box_the_gnat`) both require the pair to be side by side rather than
/// diagonally opposite.
bool areAdjacent(Formation formation, DancerId a, DancerId b) {
  final stateA = formation.stateOf(a);
  final stateB = formation.stateOf(b);
  return stateA.row == stateB.row || stateA.col == stateB.col;
}

/// The first pair in [pairs] whose members are not adjacent, or `null` when
/// every pair is.
///
/// Shared by the figures that require a physical two-handed hold — the rigid
/// couple wheels and `two_hand_turn` — so that all of them refuse the same
/// arrangements for the same reason.
DancerPair? firstNonAdjacentPair(Formation formation, List<DancerPair> pairs) {
  for (final pair in pairs) {
    if (!areAdjacent(formation, pair.a, pair.b)) return pair;
  }
  return null;
}

/// The first pair in [pairs] standing **across** the set rather than along it,
/// or `null` when every pair is a column pair.
///
/// Along-the-set pairs share a column and span their band's two rows, which is
/// the arrangement the quarter-turn wave landing is defined over: the sideways
/// step of §8.5.1 is a *column* step, so a pair already separated by columns
/// has no such step to take.
DancerPair? firstPairAcrossTheSet(Formation formation, List<DancerPair> pairs) {
  for (final pair in pairs) {
    if (formation.stateOf(pair.a).col != formation.stateOf(pair.b).col) {
      return pair;
    }
  }
  return null;
}

/// The direction pointing from [from] to [to], or `null` when they are
/// diagonal.
///
/// Used by the figures whose ending facing is **relational** — stated as "each
/// dancer faces the other dancer of their pair" rather than as a cardinal
/// direction (`two_hand_turn`, `box_the_gnat`).
Facing? facingToward(Position from, Position to) {
  if (from.row == to.row) {
    if (from.col == to.col) return null;
    return to.col > from.col ? Facing.acrossEast : Facing.acrossWest;
  }
  if (from.col == to.col) {
    return to.row > from.row ? Facing.down : Facing.up;
  }
  return null;
}

/// The across facing that points from [col] **into** the set.
Facing acrossFacingInto(int col) =>
    col == 0 ? Facing.acrossEast : Facing.acrossWest;

/// The determinate facing left by the "focus" figures, `box_circulate` and
/// `shoulder_round` (`docs/taxonomy.md`).
///
/// With the right hand/shoulder the dancers ending at `(topRow, c0)` and
/// `(bottomRow, c4)` face **in** and the other two face **out**; with the left
/// it is reversed.
///
/// Returns `null` for a dancer who is not in a side column: the rule is stated
/// over the corner ring only, and inventing a facing for a centre-column
/// dancer would assert something the taxonomy does not say.
Facing? focusFacing({
  required Hand focus,
  required Position at,
  required Band band,
}) {
  if (at.col != 0 && at.col != kColumnCount - 1) return null;
  final facesIn =
      (at.row == band.topRow && at.col == 0) ||
      (at.row == band.bottomRow && at.col == kColumnCount - 1);
  final inward = acrossFacingInto(at.col);
  final withRightHand = facesIn ? inward : inward.reversed;
  return focus == Hand.right ? withRightHand : withRightHand.reversed;
}

/// The row a line of four facing [facing] occupies in [band], or `null` when
/// [facing] does not run along the hall.
///
/// A line's row is **derived from its facing** without exception
/// (`docs/fundamentals.md` §8.1): facing Down it sits in the band's upper row,
/// facing Up in the lower — the row it would travel *from*. The row is a
/// normalization slot rather than a hall position, so reversing facing migrates
/// the whole line rather than leaving it where it stood.
int? lineRowFor(Band band, Facing facing) => switch (facing) {
  Facing.down => band.topRow,
  Facing.up => band.bottomRow,
  _ => null,
};

/// Whether all four corners of [band] are occupied.
///
/// A hands four with a hole in it is a transient shape — a couple waiting out
/// at the end of the set, or a band mid-progression — and several figures are
/// defined only on the complete ring. Occupancy has to be tested rather than
/// assumed: `handsFourBands` yields the band regardless of how full it is.
bool bandIsComplete(Formation formation, Band band) =>
    handsFourRing(band).every((cell) => formation.dancerAt(cell) != null);

/// Leaves every dancer of a **complete** hands four in [Facing.flexible].
///
/// The ring-rotation figures (`circle`, `star`, `facing_star`) end with the
/// dancers still holding the ring, so their absolute facing is undetermined
/// until the next figure resolves it — that is the "facing (output): Flexible"
/// contract those moves carry in `docs/taxonomy.md`. The consumers already
/// expect it: [PassThrough.checkPreconditions] and its family skip any dancer
/// whose facing is not concrete rather than refusing them.
///
/// Incomplete bands are skipped, matching [rotateHandsFourRings], which leaves
/// them where they are. Imposing a facing on a shape the rotation deliberately
/// declined to touch would invent state.
Formation loosenBandFacing(Formation formation) => mapBandFacing(
  formation,
  (id, state, band) => bandIsComplete(formation, band) ? Facing.flexible : null,
);

/// The row a **line of four** occupies in [band], or `null` when the band does
/// not hold one.
///
/// A line of four (`docs/fundamentals.md` §8.1) puts all four dancers of a
/// hands four into a single row, leaving the band's other row empty. That empty
/// row is a normalization slot rather than a hall position, so the shape has to
/// be recognized from occupancy rather than assumed from context — both
/// `turn_alone` and the hall figures branch on it.
int? lineOfFourRow(Formation formation, Band band) {
  for (final row in [band.topRow, band.bottomRow]) {
    final other = row == band.topRow ? band.bottomRow : band.topRow;
    if (formation.dancersInRow(row).length == 4 &&
        formation.dancersInRow(other).isEmpty) {
      return row;
    }
  }
  return null;
}

/// The column a dancer standing at [col] and facing [facing] steps to in order
/// to join [hand] hands with the dancer they face
/// (`docs/fundamentals.md` §8.5.1).
///
/// Two dancers facing each other cannot join *matching* hands while squarely
/// aligned, so joining them takes a sideways step: **to join right hands each
/// steps toward their own left, to join left hands toward their own right.**
/// The step is derived from [Facing.turnedLeft] / [Facing.turnedRight] rather
/// than from the dancer's role, which is the whole point of the rule — at the
/// standard start it *reads* role-uniformly, but that is a consequence of
/// facing being role-uniform there and stops holding the moment it is not.
///
/// A step that would leave the matrix is not taken: the dancer on the grid edge
/// **holds** and their opposite absorbs the whole offset. Returns [col]
/// unchanged in that case, and also when [facing] does not run along the hall
/// — a dancer facing across the set has no sideways step across it to take.
int waveOffsetColumn({
  required int col,
  required Facing facing,
  required Hand hand,
}) {
  final step = hand == Hand.right ? facing.turnedLeft : facing.turnedRight;
  final delta = switch (step) {
    Facing.acrossEast => 1,
    Facing.acrossWest => -1,
    _ => 0,
  };
  final target = col + delta;
  if (target < 0 || target >= kColumnCount) return col;
  return target;
}

/// Returns [formation] with each pair in [pairs] turned a quarter — or, when
/// [afterHalfTurn], three quarters — of the way around their shared midpoint,
/// landing them in a short wave (`docs/fundamentals.md` §8.5.1).
///
/// [pairs] must be along the set; callers refuse anything else via
/// [firstPairAcrossTheSet]. A column pair spans its band's two rows, so the
/// upper cell is the band's top row and the lower is its bottom row, which is
/// all the wave's resting facing needs.
///
/// **Three quarters is a half turn and then a quarter**, in that order: the
/// pair trade cells, and the same handed offset is then taken from where they
/// land. The wave's handedness is therefore identical either way — [hand] alone
/// fixes it — and the only difference is *which* dancers finish in the centre,
/// because the half turn has moved the couples between rows first.
///
/// Facing is the wave's own (§8.5.1): concrete alternating, top row Down and
/// bottom row Up. That is imposed rather than rotated out of the input, which
/// is what makes a do-si-do and an allemande land identically despite their
/// opposite facing rules — the shape they land in owns the facing.
Formation quarterTurnIntoWave(
  Formation formation,
  List<DancerPair> pairs, {
  required Hand hand,
  required bool afterHalfTurn,
}) {
  final changes = <DancerId, DancerState>{};
  for (final pair in pairs) {
    final stateA = formation.stateOf(pair.a);
    final stateB = formation.stateOf(pair.b);
    final topRow = stateA.row < stateB.row ? stateA.row : stateB.row;
    final landings = [
      (
        id: pair.a,
        from: stateA,
        at: afterHalfTurn ? stateB.position : stateA.position,
      ),
      (
        id: pair.b,
        from: stateB,
        at: afterHalfTurn ? stateA.position : stateB.position,
      ),
    ];
    for (final landing in landings) {
      final facing = landing.at.row == topRow ? Facing.down : Facing.up;
      changes[landing.id] = landing.from.copyWith(
        position: Position(
          landing.at.row,
          waveOffsetColumn(col: landing.at.col, facing: facing, hand: hand),
        ),
        facing: facing,
      );
    }
  }
  return formation.withUpdates(changes);
}

/// Returns [formation] with every dancer standing in a wave offset moved back
/// to their side column (`docs/fundamentals.md` §8.5.4).
///
/// Leaving a wave is not the departing figure's responsibility: a figure that
/// knows nothing about waves runs against settled side columns, and this is
/// what settles them. [Operation.apply] calls it for every figure that does not
/// declare [Operation.preservesWaveOffsets].
///
/// **A line of four is not a wave.** Both shapes occupy `{c0, c1, c3, c4}`, so
/// the two are told apart the only way they can be — a line puts all four
/// dancers of a band in one row and leaves the other empty (§8.1), which is
/// exactly what [lineOfFourRow] recognizes. Bands holding one are skipped
/// untouched.
///
/// Short-wave offsets return to their own side of the set (`c1 -> c0`,
/// `c3 -> c4`), which §8.1's side-preservation rule already guarantees is where
/// they came from. A centre long wave (§8.5.5) is different: `c2` is equidistant
/// from both, so the dancer returns to **the side column their rank has left
/// free**. That is well defined by construction, because a centre wave is
/// role-scoped precisely so that each rank puts one dancer in the centre and
/// leaves the other holding its line.
Formation normalizeWaveOffsets(Formation formation) {
  final changes = <DancerId, DancerState>{};
  for (final band in handsFourBands(formation)) {
    if (lineOfFourRow(formation, band) != null) continue;
    for (final row in [band.topRow, band.bottomRow]) {
      final ids = formation.dancersInRow(row);
      final occupiedSides = {
        for (final id in ids)
          if (_isSideColumn(formation.stateOf(id).col))
            formation.stateOf(id).col,
      };
      for (final id in ids) {
        final state = formation.stateOf(id);
        final home = _waveHomeColumn(state.col, occupiedSides);
        if (home == null || home == state.col) continue;
        changes[id] = state.movedTo(Position(row, home));
      }
    }
  }
  return formation.withUpdates(changes);
}

bool _isSideColumn(int col) => col == 0 || col == kColumnCount - 1;

/// The side column an offset dancer at [col] belongs back in, or `null` when
/// they are not offset at all.
///
/// Returns `null` for a centre dancer whose rank has both side columns free or
/// both filled: neither says which line they stepped out of, and moving them on
/// a guess would put a dancer in a line they were never in. That case cannot
/// arise from any figure here, so it is left alone rather than resolved.
int? _waveHomeColumn(int col, Set<int> occupiedSides) {
  const east = kColumnCount - 1;
  return switch (col) {
    1 => 0,
    3 => east,
    2 => switch ((occupiedSides.contains(0), occupiedSides.contains(east))) {
      (true, false) => east,
      (false, true) => 0,
      _ => null,
    },
    _ => null,
  };
}

/// Swaps the two members of each pair in [pairs].
///
/// Role, number and couple identity travel with each dancer for free: the
/// entity map is keyed by invariant identity, so moving a dancer moves
/// everything held about them (`docs/architecture.md` §6, D2/D3).
///
/// [facing] receives each dancer's prior state, the cell they land in, and the
/// cell their partner lands in, and returns the facing they finish with.
/// Omitted, facing is preserved — the default for the pass/pull family, where
/// a dancer walks forward past the other and keeps their direction.
Formation swapPairs(
  Formation formation,
  List<DancerPair> pairs, {
  Facing Function(DancerState before, Position after, Position other)? facing,
}) {
  final changes = <DancerId, DancerState>{};
  for (final pair in pairs) {
    final stateA = formation.stateOf(pair.a);
    final stateB = formation.stateOf(pair.b);
    final toA = stateB.position;
    final toB = stateA.position;
    changes[pair.a] = stateA.copyWith(
      position: toA,
      facing: facing?.call(stateA, toA, toB),
    );
    changes[pair.b] = stateB.copyWith(
      position: toB,
      facing: facing?.call(stateB, toB, toA),
    );
  }
  return formation.withUpdates(changes);
}

/// Reflects every dancer in each complete hands four across the named axes.
///
/// This one function is the whole axis-swap family. Reflecting [rows] exchanges
/// the band's two rows (`(r0,c) ↔ (r1,c)` — a pass along the set); reflecting
/// [columns] mirrors the matrix left-to-right (`(r,c0) ↔ (r,c4)` — a pass
/// across the set); doing both is the diagonal swap that `right_left_through`,
/// `cross_trails` and a half `star_promenade` all land on.
///
/// Columns are mirrored rather than merely exchanging `c0` and `c4` so the
/// transform stays well defined on a **line of four**, whose dancers occupy the
/// centre columns `c1` and `c3` (`docs/fundamentals.md` §8.1).
///
/// [facing] receives each dancer's prior state, the cell they land in, and the
/// band they land in; omitted, facing is preserved.
Formation reflectBands(
  Formation formation, {
  bool rows = false,
  bool columns = false,
  Facing Function(DancerState before, Position after, Band band)? facing,
}) {
  if (!rows && !columns && facing == null) return formation;

  final changes = <DancerId, DancerState>{};
  for (final band in handsFourBands(formation)) {
    for (final row in [band.topRow, band.bottomRow]) {
      for (final id in formation.dancersInRow(row)) {
        final state = formation.stateOf(id);
        final newRow = rows
            ? (row == band.topRow ? band.bottomRow : band.topRow)
            : row;
        final newCol = columns ? kColumnCount - 1 - state.col : state.col;
        final after = Position(newRow, newCol);
        changes[id] = state.copyWith(
          position: after,
          facing: facing?.call(state, after, band),
        );
      }
    }
  }
  return formation.withUpdates(changes);
}

/// Rewrites the facing of every dancer in a complete hands four, leaving
/// positions untouched.
///
/// The companion to [reflectBands] for the figures whose entire effect is a
/// facing change (`turn_alone`), and for the ones that set facing after a
/// permutation the caller has already applied.
///
/// [facing] returning `null` leaves that dancer's facing alone, which is how
/// a rule that is silent about some dancers (see [focusFacing]) stays silent
/// rather than defaulting.
Formation mapBandFacing(
  Formation formation,
  Facing? Function(DancerId id, DancerState state, Band band) facing,
) {
  final changes = <DancerId, DancerState>{};
  for (final band in handsFourBands(formation)) {
    for (final row in [band.topRow, band.bottomRow]) {
      for (final id in formation.dancersInRow(row)) {
        final state = formation.stateOf(id);
        final next = facing(id, state, band);
        if (next == null || next == state.facing) continue;
        changes[id] = state.copyWith(facing: next);
      }
    }
  }
  return formation.withUpdates(changes);
}
