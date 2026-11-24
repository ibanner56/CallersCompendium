import 'dart:math' as math;

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

part 'figures/arch_and_dive.dart';
part 'figures/axis_swaps.dart';
part 'figures/butterfly_whirl.dart';
part 'figures/cast.dart';
part 'figures/circle.dart';
part 'figures/containers.dart';
part 'figures/circular_hey.dart';
part 'figures/chain.dart';
part 'figures/contra_corners.dart';
part 'figures/couple_wheel.dart';
part 'figures/do_si_do.dart';
part 'figures/figure_eight.dart';
part 'figures/gate.dart';
part 'figures/give_and_take.dart';
part 'figures/hall.dart';
part 'figures/hey.dart';
part 'figures/pair_swaps.dart';
part 'figures/petronella.dart';
part 'figures/promenade.dart';
part 'figures/revolving_door.dart';
part 'figures/right_left_through.dart';
part 'figures/rings.dart';
part 'figures/slice.dart';
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
  /// `slide_along_set` is one; `slice`, which dances one or two slides, and a
  /// diagonal `right_left_through`, which trades couples with the next hands
  /// four, are the others: the figure's own displacement is what carries
  /// dancers on to the next couple, so flagging it as the progression names
  /// the movement that has already happened. Every other figure that
  /// re-bands the set — a figure danced with the next neighbours — is *not* a
  /// progression, so a progression flag on top of it advances the set a second
  /// time (§8.1). See [OperationInvocation.apply], which is where the
  /// difference is applied.
  bool get isItsOwnProgression => false;

  /// The steps this figure is danced in when it carries the progression flag,
  /// one per progression the flag spends.
  ///
  /// Almost every figure is one step, itself, so a flag on it is one
  /// progression. A `slice` back on the diagonal is two slides, and as the
  /// progression it is **two progressions** *(user-ruled 2026-11-23: "diagonal
  /// is double, straight back is single")*: [OperationInvocation] runs each
  /// step with its own change-over, exactly as two flagged slides would be,
  /// and the progression count advances once per step.
  List<Operation> get progressionSteps => [this];

  /// How many progressions a flag on this figure spends: what the distance
  /// count (`reachAfter`) advances by. One per [progressionSteps], except
  /// where a single step carries the set further, as a diagonal
  /// `right_left_through` does.
  int get progressionsSpent => progressionSteps.length;

  /// Whether this figure reads the wave offsets rather than needing them
  /// settled away first (`docs/fundamentals.md` §8.5.4).
  ///
  /// The test is the figure's **premise**, not its effect: a figure preserves
  /// the offsets only if it is danceable *while standing in a wave*. That is
  /// `balance` — balancing a wave is the ordinary thing to do in one —
  /// `stand_still`, `rory_o_more`, which has no meaning outside a wave at
  /// all, and an `allemande` of a quarter or three-quarter amount, which turns
  /// a pair from the wave it is holding (§8.5.7); and only them.
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
  /// A figure naming only partners that is refused because they are not
  /// standing together is tried once more one band phase over, and on
  /// success the set is left in that phase (see the comment in the body).
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
    // A figure naming a distance set and shadows (a square through with the
    // shadows, then the next neighbours): where you meet your shadows depends
    // on the progression, so there is no rule tying the two sets together to
    // refuse on *(user-ruled 2026-11-22)*. The agent's call, following from
    // that: the distance picks the phase, the shadows phase rule is not
    // applied, and the figure's own `who` checks still are.
    if (reaching.isNotEmpty) {
      return _applyReaching(settled, reaching.single, progressions);
    }
    if (dancerSets.contains(WhoSet.shadows)) {
      return _applyWithShadows(settled);
    }

    // A figure naming partners finds its hands fours by where they stand: if
    // they are not together in the grouping the set is in, it is danced one
    // band phase over, and the set stays grouped that way for the figures
    // after it *(user-ruled 2026-11-24: the hands fours follow the dancers,
    // and the grouping is found by where they stand, never by moving
    // anyone)*. The agent's calls: the current grouping is tried first, and
    // its refusal is the one reported when neither works; only a pairing
    // refusal (`whoMismatch`) is retried; and only a figure naming partners
    // and nothing else. `neighbors` is read from couple numbers, so one
    // phase over it would accept the next neighbours in their place, and
    // allowing it gained no dance.
    final here = _tryIn(settled);
    if (here is Ok<Formation, OpError>) return here;
    if (!_namesPartners || !_isPairingRefusal(here)) return here;
    final otherPhase = toggleBandPhase(settled);
    // With no hands four in the other phase, nothing would be danced there.
    if (handsFourBands(otherPhase).isEmpty) return here;
    final over = _tryIn(otherPhase);
    return over is Ok<Formation, OpError> ? over : here;
  }

  /// Whether partners are the only set this figure names (stated, or the
  /// parser's default when the record names no one): the one pairing that is
  /// the same two dancers whichever grouping they stand in. A figure that
  /// also names another set is not retried, since that set would be read in
  /// a grouping nobody chose for it.
  bool get _namesPartners {
    final named = dancerSets.whereType<WhoSet>().toSet();
    return named.length == 1 && named.single == WhoSet.partners;
  }

  /// Whether [result] is a refusal because the named dancers are not the
  /// ones standing together, the only refusal another grouping can answer.
  static bool _isPairingRefusal(Result<Formation, OpError> result) =>
      result is Err<Formation, OpError> &&
      result.error.kind == ErrorKind.whoMismatch;

  /// Checks and dances this figure with [phase]'s hands fours, as they stand.
  Result<Formation, OpError> _tryIn(Formation phase) {
    final failure = checkPreconditions(phase);
    if (failure != null) return Err<Formation, OpError>(failure);
    return perform(phase);
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

  /// Runs a figure that names `shadows`.
  ///
  /// A dancer's shadows stand in a neighbouring hands four, so whether they
  /// are together depends on the dance so far, not on a fixed distance. The
  /// rule is to pair whoever is standing next to you, and refuse if there is
  /// no one or more than one choice *(user-ruled 2026-11-22)*, which is how
  /// `swing` already treats every set.
  ///
  /// How that is carried out is the agent's call (`docs/taxonomy.md`,
  /// "Shadows"): the choices are the two **band phases**, the figure is danced
  /// in the one in which **every** hands four holds a shadow pair, and the
  /// phase it was given is handed back, as [_applyReaching] does. Neither
  /// phase is `whoMismatch`; both is `unresolvableDancerSet`, unless the
  /// shadows the dance has already named pick one ([_identityPicksCurrent]).
  /// The pairs danced are remembered on each dancer that has no shadow yet.
  Result<Formation, OpError> _applyWithShadows(Formation formation) {
    final over = toggleBandPhase(formation);
    final here = _shadowsStandTogether(formation);
    final there = _shadowsStandTogether(over);
    if (here && there) {
      // Both phases have shadow pairs: the shadows the dance has already
      // named decide, when they pick one *(user-ruled 2026-11-23)*.
      final current = _identityPicksCurrent(formation, over);
      if (current != null) {
        return _danceShadows(current ? formation : over, handBack: !current);
      }
      return Err<Formation, OpError>(
        OpError(
          ErrorKind.unresolvableDancerSet,
          '$name names shadows, and shadow pairs stand together in both band '
          'phases; which pairs dance would be a guess',
        ),
      );
    }
    if (!here && !there) {
      return Err<Formation, OpError>(
        OpError(
          ErrorKind.whoMismatch,
          '$name names shadows, but no band phase has a shadow pair standing '
          'together in every hands four',
        ),
      );
    }
    return _danceShadows(here ? formation : over, handBack: !here);
  }

  /// Dances a shadows figure in [phase], remembering who danced as shadows,
  /// and toggles the phase back afterwards when [handBack].
  Result<Formation, OpError> _danceShadows(
    Formation phase, {
    required bool handBack,
  }) {
    final failure = checkPreconditions(phase);
    if (failure != null) return Err<Formation, OpError>(failure);
    final pairs = _shadowPairs(phase);
    final danced = perform(phase).map((next) => _remember(next, pairs));
    return handBack ? danced.map(toggleBandPhase) : danced;
  }

  /// Which band phase holds the shadows the dance has already named, when
  /// shadow pairs stand together in both: the one in which no dancer stands
  /// in a hands four apart from their remembered [DancerState.shadow], given
  /// that some remembered pair stands together in it. `null` when that does
  /// not pick exactly one phase, or nobody has a shadow yet.
  static bool? _identityPicksCurrent(Formation here, Formation over) {
    final fitsHere = _keepsShadowsTogether(here);
    final fitsOver = _keepsShadowsTogether(over);
    if (fitsHere == fitsOver) return null;
    return fitsHere;
  }

  /// Whether [formation]'s hands fours keep every remembered shadow pair
  /// together, with at least one such pair in them.
  static bool _keepsShadowsTogether(Formation formation) {
    final bandOf = <DancerId, int>{};
    final bands = handsFourBands(formation);
    for (var i = 0; i < bands.length; i++) {
      for (final row in [bands[i].topRow, bands[i].bottomRow]) {
        for (final id in formation.dancersInRow(row)) {
          bandOf[id] = i;
        }
      }
    }
    var together = 0;
    for (final MapEntry(key: id, value: band) in bandOf.entries) {
      final shadow = formation.stateOf(id).shadow;
      if (shadow == null) continue;
      final shadowBand = bandOf[shadow];
      if (shadowBand == null) continue;
      if (shadowBand != band) return false;
      together++;
    }
    return together > 0;
  }

  /// The shadow pairs standing together in [formation]'s hands fours.
  ///
  /// A pair side by side in a side column is taken first, then the rest pair
  /// first match first, as [resolveWhoPairs] pairs them. At an end with nobody out the shadow
  /// wraps to the neighbour, so a dancer can match someone across the set as
  /// well as the dancer beside them; reading the columns first remembers the
  /// pair that danced side by side, as a promenade across checks them
  /// *(agent's call, 2026-11-24)*.
  static List<({DancerId a, DancerId b})> _shadowPairs(Formation formation) {
    final pairs = <({DancerId a, DancerId b})>[];
    for (final band in handsFourBands(formation)) {
      final taken = <DancerId>{};
      for (final col in const [0, kColumnCount - 1]) {
        final a = formation.dancerAt(Position(band.topRow, col));
        final b = formation.dancerAt(Position(band.bottomRow, col));
        if (a == null || b == null) continue;
        if (!whoMatches(formation, a, b, WhoSet.shadows)) continue;
        pairs.add((a: a, b: b));
        taken.addAll([a, b]);
      }
      final rest = [
        for (final row in [band.topRow, band.bottomRow])
          for (final id in formation.dancersInRow(row))
            if (!taken.contains(id)) id,
      ];
      for (var i = 0; i < rest.length; i++) {
        if (taken.contains(rest[i])) continue;
        for (var j = i + 1; j < rest.length; j++) {
          if (taken.contains(rest[j])) continue;
          if (!whoMatches(formation, rest[i], rest[j], WhoSet.shadows)) {
            continue;
          }
          pairs.add((a: rest[i], b: rest[j]));
          taken.addAll([rest[i], rest[j]]);
          break;
        }
      }
    }
    return pairs;
  }

  /// [formation] with each dancer in [pairs] remembering the other as their
  /// shadow, unless they already have one: the first shadow a dance names is
  /// the one it keeps *(user-ruled 2026-11-23)*.
  static Formation _remember(
    Formation formation,
    List<({DancerId a, DancerId b})> pairs,
  ) {
    final changes = <DancerId, DancerState>{};
    for (final pair in pairs) {
      for (final (id, other) in [(pair.a, pair.b), (pair.b, pair.a)]) {
        final state = formation.stateOf(id);
        if (state.shadow == null) changes[id] = state.copyWith(shadow: other);
      }
    }
    return formation.withUpdates(changes);
  }

  /// Whether every hands four of [formation] holds at least one shadow pair.
  static bool _shadowsStandTogether(Formation formation) {
    final bands = handsFourBands(formation);
    return bands.isNotEmpty &&
        bands.every(
          (band) => resolveWhoPairs(
            formation,
            WhoSet.shadows,
            topRow: band.topRow,
            bottomRow: band.bottomRow,
          ).isNotEmpty,
        );
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
