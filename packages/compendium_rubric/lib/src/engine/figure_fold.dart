import '../domain/formation.dart';
import '../ops/diagnostics.dart';
import 'end_normalization.dart';
import 'invocation.dart';
import 'result.dart';

/// Threads a dance's figures over a formation one at a time, exactly as
/// `compile` does: the distance count, and the progressions **held** until a
/// couple reaches an end.
///
/// Anything that steps through a dance figure by figure (a trace, a probe, a
/// golden test's failure report) goes through this, so it cannot disagree
/// with the compile it is explaining.
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
class FigureFold {
  FigureFold();

  /// Progressions performed so far, counted at the figures that were flagged.
  int get progressions => _progressions;
  int _progressions = 0;

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

  /// Runs [figure] (figure number [index]) on [state].
  Result<Formation, OpError> step(
    OperationInvocation figure,
    Formation state, {
    required int index,
  }) {
    final outcome = figure.applyHolding(state, progressions: progressions);
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
      if (figure.progression) _progressions++;
      return next;
    });
  }
}
