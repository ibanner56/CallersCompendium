import 'package:meta/meta.dart';

import '../domain/formation.dart';
import '../domain/formation_type.dart';
import '../domain/starting_formations.dart';
import '../ops/diagnostics.dart';
import '../ops/operation.dart';
// For the §8.5.4 settler used to compare a dance that ends standing in a wave.
import '../ops/transforms.dart';
import 'compile_result.dart';
import 'invocation.dart';
import 'result.dart';
import 'sizing.dart';
import 'success_criterion.dart';

/// A dance as the compiler takes it: a starting formation, the success
/// condition it claims to achieve, and the ordered figures that should get it
/// there (`docs/architecture.md` §2).
///
/// The formation is a **type**, not a sized matrix. How big the set needs to be
/// is derived, not supplied — see [compile].
@immutable
class Dance {
  const Dance({
    required this.formation,
    required this.success,
    required this.figures,
    this.name = '',
    this.warnings = const [],
  });

  /// The starting formation type.
  final FormationType formation;

  /// What the dance is supposed to achieve.
  final SuccessCriterion success;

  /// The ordered figure list, each with its own progression flag.
  final List<OperationInvocation> figures;

  /// Optional label, used only in diagnostics.
  final String name;

  /// Diagnostics raised before the dance reached the compiler at all.
  ///
  /// Everything else in a compile's warning list is an observation about a
  /// formation — either a figure's own lint or the engine's pre-scan of the
  /// figure list. These come from **reading the record**: an
  /// `unrecognizedFormation` is a fact about the notation, and by the time
  /// there is a [Dance] to compile the fact has already been absorbed. Carrying
  /// them here is what keeps them from being silently dropped between the
  /// parser and the result the caller actually looks at.
  final List<Warning> warnings;

  /// How many hands four this dance needs to be evaluated coherently
  /// (§3.1, D7).
  ///
  /// Contributions are counted **per instance**, so a dance with three
  /// expanding figures gets `+3`.
  ///
  /// Reach is the **largest** any one figure asks for rather than the sum.
  /// A figure reaching three groupings along the set needs three to reach
  /// across, and a later one reaching two dances inside that same room — the
  /// two do not stack, because reaching is transient and hands the set back.
  ///
  /// Each figure's reach is measured against the progressions that run *before*
  /// it, because the distance-named sets are anchored at the start of the dance
  /// and every progression closes the gap by one (see [Operation.reachAfter]).
  /// A dance that progresses and only then names its next neighbours needs no
  /// extra room at all: it is already standing with them.
  int get requiredHandsFour => computeHandsFour([
    success.hands4Contribution,
    for (final figure in figures) figure.operation.hands4Contribution,
    _widestReach,
  ]);

  /// The largest distance any one figure still has to travel at its own point
  /// in the figure list.
  int get _widestReach {
    var widest = 0;
    var progressions = 0;
    for (final figure in figures) {
      final reach = figure.operation.reachAfter(progressions);
      if (reach > widest) widest = reach;
      if (figure.progression) progressions++;
    }
    return widest;
  }

  /// The concrete starting matrix, instantiated at [requiredHandsFour].
  Formation instantiate() =>
      startingFormation(formation, handsFour: requiredHandsFour);
}

/// Compiles [dance] (`docs/architecture.md` §3).
///
/// The pipeline is: pre-scan the figure list for size (§3.1) → instantiate the
/// starting matrix → fold the figures over it, short-circuiting on the first
/// refusal (§3.2, §3.3) → compare the result against the criterion's
/// independently computed expectation (§3.4, §3.5).
///
/// Three outcomes, and the last two stay distinct on purpose: a [Mismatch]
/// means the dance *ran* and landed somewhere else, while a [CompileError]
/// means it could not run at all. Those are different facts about the
/// choreography and collapsing them would hide which one happened.
///
/// Pure: nothing here mutates [dance] or any formation, and no exception is
/// used for control flow.
CompileResult compile(Dance dance) {
  final warnings = <Warning>[
    ...dance.warnings,
    ..._oneSidedHallWarnings(dance),
  ];

  final unperformed = _unperformedProgression(dance);
  if (unperformed != null) {
    return CompileError(error: unperformed, warnings: warnings);
  }

  final input = dance.instantiate();

  var state = input;
  var progressions = 0;
  for (var index = 0; index < dance.figures.length; index++) {
    final figure = dance.figures[index];
    // Linted against the state the figure is handed, before it runs -- a
    // state-dependent observation is only meaningful about its own input.
    warnings.addAll(
      figure.operation
          .lint(state)
          .map(
            (warning) =>
                Warning(warning.kind, opIndex: index, detail: warning.detail),
          ),
    );
    final outcome = figure.apply(state, progressions: progressions);
    switch (outcome) {
      case Ok(:final value):
        state = value;
        if (figure.progression) progressions++;
      case Err(:final error):
        // Short-circuit (§3.3): no expected/actual comparison is performed
        // once a figure refuses, so there is no final state to report.
        return CompileError(
          opIndex: index,
          opName: figure.name,
          error: error,
          warnings: warnings,
        );
    }
  }

  // Computed from the *input*, never from `state` — that independence is what
  // makes this a check rather than a restatement (§3.4).
  final expected = dance.success.expected(input);
  // The oracle walks the set from a settled input, so it never predicts a wave
  // offset. A dance may legitimately *end* standing in one — Apples and
  // Caramel's last figure is a quarter-turn do-si-do "to short waves" — and
  // the offsets are a sub-position within the side columns rather than a
  // different grid state (§8.5.1, §8.5.4). So the comparison is made against
  // the settled projection, exactly as the next figure would see it; the dance
  // that loops back to its own A1 is judged on where it left the set, not on
  // whether the dancers had already stepped into the wave.
  //
  // The reported state is the **real** one, offsets and all. Settling is how
  // the two are compared, not a claim about where the dancers are standing.
  return normalizeWaveOffsets(state) == expected
      ? Compiled(state, warnings: warnings)
      : Mismatch(actual: state, expected: expected, warnings: warnings);
}

/// Refuses a dance that claims a progression its figure list never performs.
///
/// Progression is never inferred from matrix state (§10.1): a figure advances
/// the set only when its invocation carries the flag. So a dance declaring a
/// [ProgressionCriterion] with nothing flagged cannot possibly land where the
/// criterion says, and every figure would run before the mismatch was
/// reported — pointing at the choreography rather than at the missing flag.
///
/// Refusing up front names the real fault. It is deliberately **not** inferred
/// onto the last eligible figure: which figure progresses is choreography, and
/// guessing it would turn a data gap into a silently different dance.
OpError? _unperformedProgression(Dance dance) {
  final criterion = dance.success;
  if (criterion is! ProgressionCriterion) return null;
  if (dance.figures.any((figure) => figure.progression)) return null;

  return OpError(
    ErrorKind.unperformedProgression,
    'the dance claims '
    '${criterion.count == 1 ? 'a single progression' : '${criterion.count} progressions'}, '
    'but none of its ${dance.figures.length} figures is flagged as the '
    'progression; progression is never inferred from the matrix, so the set '
    'would never advance',
  );
}

/// The dance-level `oneSidedHall` lint (`docs/taxonomy.md`, `down_the_hall`).
///
/// A hall figure that travels one way and never comes back leaves the set
/// displaced along the hall. That is a **warning**, not an error: the return
/// need not be adjacent to the departure, and the compiler has no business
/// insisting on a particular arrangement of the figure list.
///
/// The pairing is positional rather than a bare count so the warning can point
/// at the specific figure that has no partner. A figure whose `facing` is
/// `forwardThenBackward` completes the round trip inside itself and is excluded
/// from the pairing entirely.
///
/// This is the first diagnostic in the taxonomy that is not a single state
/// transition, which is exactly why it lives here: an operation only ever sees
/// one formation, so it could not detect this if it wanted to.
List<Warning> _oneSidedHallWarnings(Dance dance) {
  final outbound = <int>[];
  final inbound = <int>[];
  for (var index = 0; index < dance.figures.length; index++) {
    final operation = dance.figures[index].operation;
    if (operation is! HallFigure) continue;
    if (operation.facing == HallFacing.forwardThenBackward) continue;
    (operation is DownTheHall ? outbound : inbound).add(index);
  }

  final matched = outbound.length < inbound.length
      ? outbound.length
      : inbound.length;
  return [
    for (final index in [
      ...outbound.skip(matched),
      ...inbound.skip(matched),
    ]..sort())
      Warning(
        WarningKind.oneSidedHall,
        opIndex: index,
        detail:
            '${dance.figures[index].name} has no matching return; the set may '
            'be left off-balance',
      ),
  ];
}
