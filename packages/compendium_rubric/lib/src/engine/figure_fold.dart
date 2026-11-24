import '../domain/formation.dart';
import '../geometry/geometry.dart';
import '../ops/diagnostics.dart';
import '../ops/operation.dart';
import '../ops/params.dart';
import 'end_normalization.dart';
import 'invocation.dart';
import 'result.dart';

/// Threads a dance's figures over a formation one at a time, exactly as
/// `compile` does: the distance count, and the progressions **held** until a
/// couple reaches an end.
///
/// Anything that steps through a dance figure by figure (a trace, a probe, a
/// golden test's failure report) goes through this, so it cannot disagree
/// with the compile it is explaining. The one thing it does not do is the
/// end-effect retry (`docs/fundamentals.md` §10.7): a dance that compiled only
/// after a waiting pair traded places says so with an `endEffectSwap` warning,
/// and a plain step-through of it refuses where the compile retried.
///
/// **Holding** (`docs/fundamentals.md` §10.2.1, user-ruled 2026-11-23). A
/// progression-flagged figure that leaves no whole couple at either end has
/// nobody to step out yet: a Becket dance progressing on a diagonal `chain` or
/// a `pass_through` along the set is the type case in Becket; in Duple Improper
/// it is a circle or swing that leaves partners split across rows. Its change-over is held
/// ([OperationInvocation.applyHolding]) and runs after the first later figure
/// that brings a whole couple to an end. The progression still counts at the
/// flagged figure, so the distance sets measure from it.
///
/// Holding applies in **every formation** *(user-ruled 2026-11-23)*: the test
/// is only whether a whole couple stands at an end, which does not depend on
/// the formation. The cost is that a flag placed early, sometimes several
/// figures early, can be carried to a later figure that finishes it rather than
/// failing (`docs/fundamentals.md` §10.2.1 has the measurement).
///
/// **A chain or hey after an N2 figure** (`docs/fundamentals.md` §10.3.0):
/// an unflagged `across` chain or hey straight after a figure reaching an odd
/// distance is danced in the phase that figure reached, and the set is handed
/// back after it.
class FigureFold {
  FigureFold();

  /// An independent copy of this fold's bookkeeping, so a retry can resume
  /// from the same point without disturbing the original.
  FigureFold copy() => FigureFold()
    .._progressions = _progressions
    .._followReach = _followReach
    .._reachHandedShifted = _reachHandedShifted
    .._held.addAll(_held)
    .._abandoned.addAll(_abandoned);

  /// Progressions performed so far, counted at the figures that were flagged
  /// (a flagged diagonal slice or diagonal right_left_through counts two; see
  /// [OperationInvocation.progressionCount]).
  int get progressions => _progressions;
  int _progressions = 0;

  /// Whether the figure just run was danced one grouping over, by reaching
  /// or by following a reach, so a chain across or a hey after it is danced
  /// there too.
  bool _followReach = false;

  /// Whether the set was in its shifted phase when the figure just run was
  /// handed it, which is the phase a following figure must find it in again.
  bool _reachHandedShifted = false;

  /// The figure indexes of progressions still held, oldest first.
  final List<int> _held = [];

  /// Held progressions given up because a later flagged figure ran its own
  /// change-over first.
  final List<int> _abandoned = [];

  /// The figure index of every held progression whose change-over has not run
  /// and now never will by this fold's rules, oldest first: those a later
  /// flagged figure overtook, then those still waiting. Non-empty at the end of
  /// a dance is a [WarningKind.heldProgressionUnfinished].
  List<int> get unfinished => List.unmodifiable([..._abandoned, ..._held]);

  /// The set as [figure] will be danced from it when handed [state]: [state]
  /// itself, or one band phase over when [figure] follows a reach (see
  /// [step]). A lint about the figure's own input reads this.
  Formation dancedFrom(OperationInvocation figure, Formation state) =>
      _follows(figure, state) ? toggleBandPhase(state) : state;

  /// Whether [figure], handed [state], follows the reach just danced.
  ///
  /// A hey follows only when its first pass names a role set or partners,
  /// and its second pass one of those or a distance set lying an odd
  /// distance away: partners are the same two dancers in either grouping,
  /// and such a distance set names the grouping the hey is danced in, where
  /// it is matched as plain neighbours. `neighbors`, or a distance set lying
  /// an even distance away, would accept the N2 couple in place of the
  /// couple it names, and a first pass naming a distance set or `shadows`
  /// picks its own phase. *(Agent's call.)* A chain names a role set, as it must to
  /// be danced at all.
  bool _follows(OperationInvocation figure, Formation state) {
    final operation = figure.operation;
    return _followReach &&
        !operation.reachAfter(progressions).isOdd &&
        !figure.progression &&
        ((operation is Chain && operation.dir == ChainDirection.across) ||
            (operation is HeyForFour &&
                _followsIn(operation.pass1) &&
                (operation.pass2 == null ||
                    _followsIn(operation.pass2!) ||
                    _namesReachedGrouping(operation.pass2!)))) &&
        // A held progression that finished on the reaching figure moved the
        // set to the other phase; one phase over from there is not where the
        // reach was danced, so the figure stays put. *(Agent's call.)*
        isShiftedBandPhase(state) == _reachHandedShifted;
  }

  /// Whether [set] is a distance set that, after the progressions so far,
  /// lies an odd distance away, and so names the grouping one phase over.
  bool _namesReachedGrouping(WhoSet set) {
    final distance = set.distance;
    return distance != null && (distance - progressions).abs().isOdd;
  }

  /// Whether a hey pass naming [set] reads the same dancers one grouping
  /// over: role sets and partners do.
  static bool _followsIn(WhoSet set) =>
      set == WhoSet.role1s || set == WhoSet.role2s || set == WhoSet.partners;

  /// Runs [figure] (figure number [index]) on [state].
  Result<Formation, OpError> step(
    OperationInvocation figure,
    Formation state, {
    required int index,
  }) {
    // A chain across or a hey straight after a figure danced one grouping
    // over is danced in that grouping too, and the set is handed back after
    // it, as reaching always does. So is every such figure straight after
    // that one. *(User-ruled 2026-11-24 for the chain, note on Heather's Hop
    // Redux: after an N2 allemande left, "R1-A and R2-D should be the ones who
    // swap in the chain". The hey is the agent's call, from Hudson's notes on
    // Haven't We Met Before? and Hey-ja Vu, whose half hey after an N0 or N2
    // swing is with that couple. The other limits are the agent's calls too:
    // only unflagged, and only straight after; see `docs/fundamentals.md`
    // §10.3.0.)*
    final steppedOut = figure.operation.reachAfter(progressions).isOdd;
    final follows = _follows(figure, state);
    if (steppedOut) _reachHandedShifted = isShiftedBandPhase(state);
    _followReach = steppedOut || follows;
    final outcome = follows
        ? figure
              .applyHolding(toggleBandPhase(state), progressions: progressions)
              .map(
                (value) => (
                  formation: toggleBandPhase(value.formation),
                  held: value.held,
                ),
              )
        : figure.applyHolding(state, progressions: progressions);
    return outcome.map((value) {
      var next = value.formation;
      if (value.held) {
        _held.add(index);
      } else if (figure.progression) {
        // A flagged figure that ran its own change-over while a progression
        // was still held overtakes it. Finishing the held one afterwards would
        // retire the couples this figure has just sent out, so it is given up
        // and reported instead. *(Agent's call, 2026-11-23: two flags inside
        // one hold is hand-authored, and no import produces it.)*
        _abandoned.addAll(_held);
        _held.clear();
      } else if (_held.isNotEmpty) {
        // A held progression finishes on the first later unflagged figure
        // that leaves a whole couple at an end.
        final finished = finishHeldProgression(
          next,
          servedRound: waitingCouples(state),
        );
        if (finished != null) {
          next = finished;
          _held.removeAt(0);
        }
      }
      _progressions += figure.progressionCount;
      return next;
    });
  }
}
