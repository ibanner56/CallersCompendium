import 'package:meta/meta.dart';

import '../domain/dancer.dart';
import '../domain/formation.dart';
import '../domain/formation_type.dart';
import '../domain/position.dart';
import '../domain/starting_formations.dart';
import '../ops/diagnostics.dart';
import '../ops/operation.dart';
import '../ops/params.dart';
// For the §8.5.4 settler used to compare a dance that ends standing in a wave.
import '../ops/transforms.dart';
import 'compile_result.dart';
import 'figure_fold.dart';
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
      // Shadows stand one hands four along, and at an end with nobody out they
      // wrap round to the neighbours. A set of two hands four is all ends, so
      // its shadows could never be told from its neighbours: give it a middle.
      if (widest < 1 && figure.operation.dancerSets.contains(WhoSet.shadows)) {
        widest = 1;
      }
      progressions += figure.progressionCount;
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
  final fold = FigureFold();
  for (var index = 0; index < dance.figures.length; index++) {
    final figure = dance.figures[index];
    // Linted against the state the figure is handed, before it runs -- a
    // state-dependent observation is only meaningful about its own input.
    // A figure following a reach is danced one phase over, so that is its
    // input.
    warnings.addAll(
      figure.operation
          .lint(fold.dancedFrom(figure, state))
          .map(
            (warning) =>
                Warning(warning.kind, opIndex: index, detail: warning.detail),
          ),
    );
    final outcome = fold.step(figure, state, index: index);
    switch (outcome) {
      case Ok(:final value):
        state = value;
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
  warnings.addAll([
    for (final index in fold.unfinished)
      Warning(WarningKind.heldProgressionUnfinished, opIndex: index),
  ]);

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
  final settled = normalizeWaveOffsets(state);
  if (settled == expected) return Compiled(state, warnings: warnings);
  // A dance may also end with every dancer in the right row but up to one
  // column to the side, in a wave the settling above does not recognise
  // rather than on the side line (user-ruled 2026-11-24). It compiles, and
  // says so.
  if (endsWithinOneColumn(settled, expected)) {
    return Compiled(
      state,
      warnings: [
        ...warnings,
        Warning(
          WarningKind.endedColumnOffset,
          detail:
              'one column off: '
              '${[for (final MapEntry(:key, :value) in settled.dancers.entries)
                if (value.position.col != expected.stateOf(key).position.col) '$key'].join(', ')}',
        ),
      ],
    );
  }
  return Mismatch(actual: state, expected: expected, warnings: warnings);
}

/// Whether [actual] holds exactly [expected]'s dancers, each with the
/// expected couple number, in the expected row and at most one column away
/// from their expected place, and with every row in the expected order from
/// west to east: the near miss [compile] accepts, with
/// [WarningKind.endedColumnOffset].
///
/// Only the column is relaxed. A wrong number (a couple at an end whose
/// change-over never ran) or two dancers trading places in a row is still a
/// mismatch.
bool endsWithinOneColumn(Formation actual, Formation expected) {
  if (actual.rowCount != expected.rowCount) return false;
  if (actual.dancers.length != expected.dancers.length) return false;
  for (final MapEntry(key: id, value: state) in actual.dancers.entries) {
    final want = expected.dancers[id];
    if (want == null) return false;
    if (want.number != state.number) return false;
    if (want.position.row != state.position.row) return false;
    if ((want.position.col - state.position.col).abs() > 1) return false;
  }
  List<DancerId> order(Formation formation, int row) => [
    for (var col = 0; col < kColumnCount; col++)
      ?formation.dancerAt(Position(row, col)),
  ];
  for (var row = 0; row < actual.rowCount; row++) {
    final got = order(actual, row);
    final want = order(expected, row);
    if (got.length != want.length) return false;
    for (var i = 0; i < got.length; i++) {
      if (got[i] != want[i]) return false;
    }
  }
  return true;
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
///
/// A hall figure inside a container (`modifier`, `meanwhile`, nested
/// `sequence`) is paired like one on its own line, and a warning about it
/// points at the container's position, which is where it is danced.
List<Warning> _oneSidedHallWarnings(Dance dance) {
  final outbound = <(int, HallFigure)>[];
  final inbound = <(int, HallFigure)>[];
  for (var index = 0; index < dance.figures.length; index++) {
    for (final hall in _hallFiguresIn(dance.figures[index].operation)) {
      if (hall.facing == HallFacing.forwardThenBackward) continue;
      (hall is DownTheHall ? outbound : inbound).add((index, hall));
    }
  }

  final matched = outbound.length < inbound.length
      ? outbound.length
      : inbound.length;
  return [
    for (final (index, hall) in [
      ...outbound.skip(matched),
      ...inbound.skip(matched),
    ]..sort((a, b) => a.$1.compareTo(b.$1)))
      Warning(
        WarningKind.oneSidedHall,
        opIndex: index,
        detail:
            '${hall.name} has no matching return; the set may be left '
            'off-balance',
      ),
  ];
}

/// The hall figures [operation] dances: itself, or those inside it.
Iterable<HallFigure> _hallFiguresIn(Operation operation) => switch (operation) {
  HallFigure() => [operation],
  FiguresInOrder(:final figures) || Meanwhile(:final figures) => [
    for (final child in figures) ..._hallFiguresIn(child),
  ],
  _ => const [],
};
