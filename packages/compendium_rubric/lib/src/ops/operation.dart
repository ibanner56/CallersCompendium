import 'package:meta/meta.dart';

import '../domain/couple_number.dart';
import '../domain/dancer.dart';
import '../domain/facing.dart';
import '../domain/formation.dart';
import '../domain/position.dart';
import '../domain/role.dart';
import '../engine/result.dart';
import '../geometry/geometry.dart';
import 'diagnostics.dart';
import 'params.dart';
import 'transforms.dart';
import 'who.dart';

part 'figures/axis_swaps.dart';
part 'figures/circle.dart';
part 'figures/chain.dart';
part 'figures/couple_wheel.dart';
part 'figures/do_si_do.dart';
part 'figures/figure_eight.dart';
part 'figures/gate.dart';
part 'figures/give_and_take.dart';
part 'figures/hall.dart';
part 'figures/hey.dart';
part 'figures/pair_swaps.dart';
part 'figures/petronella.dart';
part 'figures/right_left_through.dart';
part 'figures/rings.dart';
part 'figures/slide_along_set.dart';
part 'figures/stand_still.dart';
part 'figures/star.dart';
part 'figures/stationary.dart';
part 'figures/swing.dart';
part 'figures/turns.dart';
part 'figures/waves.dart';

/// One figure from the taxonomy, with its parameters bound.
///
/// **Sealed** (`docs/architecture.md` §8.1, D5): the taxonomy is a closed set,
/// so no code outside this library may define a figure. Concrete figures live
/// in `lib/src/ops/figures/` as `part` files of this library — that is the only
/// way Dart permits a sealed hierarchy to span files, and the cost (their
/// imports must be declared here) is worth the guarantee that the operation set
/// cannot be extended behind the compiler's back.
///
/// Every figure is a **pure function of state**: [apply] never mutates its
/// input and never consults anything but the formation it is handed.
@immutable
sealed class Operation {
  const Operation();

  /// The registry key — the `move` field in the external JSON (§9).
  String get name;

  /// Extra hands four this *instance* requires beyond the base (§3.1, D7).
  ///
  /// Counted **per instance**, not per figure type: three expanding
  /// occurrences contribute `+3`. Most figures contribute `0`.
  int get hands4Contribution => 0;

  /// Whether this figure may carry the shared `progression` flag (§8.1).
  ///
  /// Tracked per the taxonomy's *progression-eligible* line. Enforcement — what
  /// the compiler should do when a dance flags a non-eligible figure — is not
  /// yet ruled on, so nothing currently reads this beyond diagnostics.
  bool get progressionEligible => false;

  /// Whether this figure **is** the dance's progression rather than merely
  /// carrying its flag.
  ///
  /// `slide_along_set` is the only one: the slide's own displacement is what
  /// carries dancers on to the next couple, so flagging it as the progression
  /// names the movement that has already happened. Every other figure that
  /// re-bands the set — a figure danced with the next neighbours — is *not* a
  /// progression, so a progression flag on top of it advances the set a second
  /// time (§8.1). See [OperationInvocation.apply], which is where the
  /// difference is applied.
  bool get isItsOwnProgression => false;

  /// Whether this figure reads the wave offsets rather than needing them
  /// settled away first (`docs/fundamentals.md` §8.5.4).
  ///
  /// The test is the figure's **premise**, not its effect: a figure preserves
  /// the offsets only if it is danceable *while standing in a wave*. That is
  /// `balance` — balancing a wave is the ordinary thing to do in one —
  /// `stand_still`, and `rory_o_more`, which has no meaning outside a wave at
  /// all; and only them.
  ///
  /// Moving nobody is not sufficient. `balance_the_ring` needs a ring of four
  /// with hands joined all the way round and `long_lines` is danced in the two
  /// side lines; neither shape is a wave, so the dancers must come out of one
  /// before either can begin, and both settle like any other figure.
  ///
  /// Every other figure is defined over the side columns and gets them — the
  /// wave figures included, since re-forming a wave from settled columns is
  /// what keeps two in a row from compounding their offsets.
  bool get preservesWaveOffsets => false;

  /// The dancer sets this figure names, for the cross-hands-four resolution.
  ///
  /// Every figure carrying a `who` / `whom` / `who2` / `pair` parameter lists
  /// it here. [apply] uses them to decide whether the set has to be re-banded
  /// before the figure can run, and to check that the dancers the caller named
  /// really are standing where the figure needs them.
  ///
  /// `null` entries are ignored, so a figure with an optional set can list it
  /// without unwrapping.
  Iterable<WhoSet?> get dancerSets => const [];

  /// The distance this figure really reaches once [progressions] have run.
  ///
  /// A figure danced with the next neighbours reaches one grouping past its
  /// own, exactly as a diagonal `chain` does, so the set has to be sized with
  /// somewhere for it to reach (§3.1, D7). Counted separately from
  /// [hands4Contribution] so that a subclass overriding that one for its own
  /// reasons cannot accidentally drop it.
  ///
  /// The distance-named sets (`nextNeighbors`, `thirdNeighbors`, …) are
  /// **absolute**: they are fixed at the start of the dance and do not
  /// re-anchor as the set advances, so the couple a dancer called their next
  /// neighbours is still that same couple after a progression has carried the
  /// dancer to them. What changes is how far away they are — each progression
  /// closes the gap by one grouping, hence `distance - progressions`. Pass `0`
  /// for the reach measured from the start of the dance.
  ///
  /// `neighbors` is the single exception in the vocabulary, and it needs no
  /// arithmetic here because it carries no distance at all: it always means
  /// whoever is in the current hands four.
  ///
  /// A figure whose effective distance falls to zero is not reaching any more
  /// — the progression already delivered it — so it is danced in place.
  int reachAfter(int progressions) {
    var reach = 0;
    for (final set in dancerSets) {
      final distance = set?.distance;
      if (distance == null) continue;
      final effective = (distance - progressions).abs();
      if (effective > reach) reach = effective;
    }
    return reach;
  }

  /// Non-fatal observations this figure makes about [formation].
  ///
  /// The state-dependent counterpart to the engine's dance-level lints: an
  /// operation sees exactly one formation, which is enough for "this will do
  /// something the caller probably did not intend" but never for "this figure
  /// list is unbalanced". Returned warnings carry no `opIndex` — the engine
  /// stamps that, because only it knows where in the list this figure sits.
  ///
  /// Warnings never change the outcome, so this is not consulted by [apply]:
  /// a figure that has something to warn about still runs, unchanged.
  Iterable<Warning> lint(Formation formation) => const [];

  /// Checks whether this figure can run against [formation].
  ///
  /// Returns `null` when the figure may proceed, or the [OpError] explaining
  /// the refusal. Preconditions short-circuit the execution fold (§3.3): no
  /// `expected`/`actual` comparison is performed once one fails.
  OpError? checkPreconditions(Formation formation) => null;

  /// The figure's own transformation, run only after preconditions pass.
  ///
  /// Returns a [Result] rather than a bare [Formation] because some figures
  /// only discover an unresolvable dancer set part-way through the transform.
  @protected
  Result<Formation, OpError> perform(Formation formation);

  /// Runs this figure against [formation]: preconditions, then the transform.
  ///
  /// This does **not** apply progression end-normalization — that is the
  /// engine's job, driven by the per-invocation flag rather than by the figure
  /// (§3.2, §8.1).
  ///
  /// [progressions] is how many progressions the dance has already performed
  /// when this figure runs. It matters only to the distance-named dancer sets,
  /// which are anchored at the start of the dance rather than to the current
  /// hands four — see [reachAfter].
  ///
  /// A figure naming a **cross-hands-four** dancer set runs against the
  /// re-banded set rather than the one it was handed; see [_applyReaching].
  ///
  /// Wave offsets are settled first unless this figure [preservesWaveOffsets],
  /// so a figure defined over the side columns never has to know that the
  /// previous one left dancers standing between them (§8.5.4).
  Result<Formation, OpError> apply(
    Formation formation, {
    int progressions = 0,
  }) {
    final settled = preservesWaveOffsets
        ? formation
        : normalizeWaveOffsets(formation);
    final reaching = _reachingSets();
    if (reaching.length > 1) {
      // Re-banding puts the set into one phase, so it can satisfy one distance.
      // A figure naming two would have to be danced in two places at once.
      return Err<Formation, OpError>(
        OpError(
          ErrorKind.unresolvableDancerSet,
          '$name names ${reaching.map((set) => set.key).join(' and ')}, which '
          'reach different groupings; a figure can only be danced in one',
        ),
      );
    }
    if (reaching.isNotEmpty) {
      return _applyReaching(settled, reaching.single, progressions);
    }

    final failure = checkPreconditions(settled);
    if (failure != null) return Err<Formation, OpError>(failure);
    return perform(settled);
  }

  /// Runs a figure that names dancers a stated distance along the set.
  ///
  /// Reaching is **transient**: the figure steps out into the band phase where
  /// the named couples stand together, dances there, and hands back the phase
  /// it was given. Every band-scoped resolver inside it then pairs the right
  /// dancers without knowing anything about it.
  ///
  /// **Which phase is fixed by the parity of the distance**, not by toggling
  /// from wherever the set happens to be. The band grid has exactly two phases,
  /// so each grouping travelled along the set moves the boundaries once and
  /// only the parity survives: an odd distance is danced one phase over, an
  /// even one in the phase the figure was handed. Deriving it from the distance
  /// rather than from the set's history is what lets a figure list *retrace* —
  /// a grand right and left goes out to the fourth neighbours and comes back
  /// past the third and the second, and each of those figures has to land in
  /// the phase its own label names rather than one further on.
  ///
  /// The distance used is the one left after [progressions] have been taken off
  /// it, because the named couples never move in the labelling — the dancer
  /// does. When that leaves nothing to travel the figure is danced in place,
  /// with no phase shift and no cross-hands-four check, because the couples it
  /// names are the ones already standing there.
  Result<Formation, OpError> _applyReaching(
    Formation formation,
    WhoSet who,
    int progressions,
  ) {
    final distance = who.distance! - progressions;
    if (distance == 0) {
      final failure = checkPreconditions(formation);
      if (failure != null) return Err<Formation, OpError>(failure);
      return perform(formation);
    }

    final stepsOut = distance.isOdd;
    final shifted = stepsOut ? toggleBandPhase(formation) : formation;

    final unreachable = crossHandsFourRefusal(
      formation,
      shifted,
      who,
      name,
      distance: distance,
    );
    if (unreachable != null) return Err<Formation, OpError>(unreachable);

    final failure = checkPreconditions(shifted);
    if (failure != null) return Err<Formation, OpError>(failure);

    return perform(
      shifted,
    ).map((next) => stepsOut ? toggleBandPhase(next) : next);
  }

  /// The distinct cross-hands-four sets this figure names, empty for a figure
  /// that stays inside its own hands four.
  Set<WhoSet> _reachingSets() => {
    for (final set in dancerSets)
      if (set != null && set.isCrossHandsFour) set,
  };

  @override
  String toString() => name;
}
