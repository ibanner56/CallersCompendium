part of '../operation.dart';

/// Which way the lines travel along the set.
enum SlideDirection {
  left('left'),
  right('right');

  const SlideDirection(this.key);

  /// The value as it appears in the external JSON.
  final String key;

  static SlideDirection? fromKey(String key) {
    for (final value in SlideDirection.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// `slide_along_set` — the explicit Becket column-slide.
///
/// Every dancer travels one row in the direction their own left (or right)
/// hand points. Facing across the set, a dancer in the west column has the top
/// of the hall on their left and a dancer in the east column has the bottom of
/// it on theirs, so a **slide left moves the west column up and the east column
/// down** — the two lines counter-rotate, which is what carries each dancer to
/// the next couple along. A slide right is the exact mirror.
///
/// A dancer pushed past the end of the set **rounds it**: they reappear in the
/// *other* column of that same end row, having turned the corner. This happens
/// on every slide, flagged as a progression or not.
///
/// ## Re-banding
///
/// Moving everyone one row also moves where the hands four *boundaries* fall.
/// The band grid has two phases — aligned to row 0 (`(0,1)`, `(2,3)`, …, with
/// nobody out) or shifted one row (`(1,2)`, …, with the top and bottom rows
/// stranded as half-bands) — and a slide toggles between them. So a slide from
/// a settled set sends the two end rows out, and a slide from a set that
/// already has couples out at the ends brings them **back in**, pairing them
/// with the couple that has just arrived beside them.
///
/// That phase reading is **load-bearing and held at moderate confidence**: it
/// reproduces all three of the worked examples on record, but it is an
/// inference from them rather than something the source spells out. If a dance
/// involving slides ever lands wrong, start here.
///
/// Out-ness is decided by the phase, not by who happens to arrive at an end.
/// The pair stranded at an end is very often not a couple, and per
/// `docs/fundamentals.md` §10.2.1 a non-couple end row is *not* renumbered —
/// so a slide can leave dancers standing out without giving them an end number.
/// The number only changes when a whole couple collects at an end **and** the
/// slide carries the dance's progression flag.
final class SlideAlongSet extends Operation {
  const SlideAlongSet({this.slide = SlideDirection.left});

  /// Which way the lines travel.
  final SlideDirection slide;

  @override
  String get name => 'slide_along_set';

  /// The slide reaches into the neighbouring grouping to find room to slide to.
  @override
  int get hands4Contribution => 1;

  @override
  bool get progressionEligible => true;

  /// The slide **is** the progression: its displacement is what carries every
  /// dancer on to the next couple, so a progression flag on it names movement
  /// the figure has already made rather than asking for more.
  @override
  bool get isItsOwnProgression => true;

  /// The row step for each side column: west first, then east.
  ///
  /// They are always opposite — the lines counter-rotate — so this is the whole
  /// of the direction handling.
  (int west, int east) get _steps =>
      slide == SlideDirection.left ? (-1, 1) : (1, -1);

  @override
  OpError? checkPreconditions(Formation formation) {
    // The slide is defined over the two side columns. A dancer left in a centre
    // column once wave offsets have settled (fundamentals §8.5.4) is standing
    // in a line of four (§8.1), which has no side lines to slide and no defined
    // landing here.
    for (final entry in formation.dancers.entries) {
      if (entry.value.position.isSideColumn) continue;
      return OpError(
        ErrorKind.unresolvableDancerSet,
        'slide_along_set needs both lines standing along the sides of the set, '
        'but ${entry.key} is in a centre column',
      );
    }
    return null;
  }

  @override
  Result<Formation, OpError> perform(Formation formation) {
    final (west, east) = _steps;
    final lastRow = formation.lastRow;

    final changes = <DancerId, DancerState>{};
    for (final entry in formation.dancers.entries) {
      final state = entry.value;
      final onWest = state.col == Position.westColumn;
      final step = onWest ? west : east;
      final target = state.row + step;

      // Off the end: round the corner into the other line, staying in the end
      // row they reached. Facing is untouched -- the turn-around is a path, and
      // only a progression's end-normalization ever rewrites facing.
      final landing = (target < 0 || target > lastRow)
          ? Position(
              target < 0 ? 0 : lastRow,
              onWest ? Position.eastColumn : Position.westColumn,
            )
          : Position(target, state.col);

      changes[entry.key] = state.copyWith(position: landing);
    }

    final slid = formation.withUpdates(changes);
    // The phase is read from the state *before* the slide: the dancers who were
    // standing out have moved too, so reading it from the result would ask the
    // question of a set that has already changed underneath it.
    return Ok(
      isShiftedBandPhase(formation)
          ? clearWaitingOut(slid)
          : markWaitingOut(slid, rows: [0, slid.lastRow]),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SlideAlongSet && other.slide == slide;

  @override
  int get hashCode => Object.hash(name, slide);

  @override
  String toString() => 'slide_along_set(${slide.key})';
}
