import 'package:meta/meta.dart';

import '../domain/formation.dart';
import '../geometry/geometry.dart';
import '../ops/diagnostics.dart';
import '../ops/operation.dart';
import 'end_normalization.dart';
import 'result.dart';

/// One entry in a dance's figure list: a bound [Operation] plus the shared
/// per-invocation `progression` flag (`docs/architecture.md` §8.1, D5).
///
/// The flag lives here rather than on [Operation] because it is *not* a
/// property of the figure — the same figure progresses in one dance and not in
/// another. This type expresses §3.2's ordering: the operation's own transform
/// runs first, and end-normalization runs after it. The one exception is a
/// **held** progression ([applyHolding]), whose change-over `FigureFold` runs
/// after a later figure instead.
@immutable
class OperationInvocation {
  const OperationInvocation(this.operation, {this.progression = false});

  final Operation operation;

  /// When `true`, this is *the* progression: after the figure's own transform,
  /// the §10.2 end-normalization is applied.
  ///
  /// Progression is never inferred from matrix state (§10.1) — only this flag
  /// triggers it.
  final bool progression;

  /// The registry key of the underlying figure.
  String get name => operation.name;

  /// Runs the figure and, when flagged, the end-normalization that follows it.
  ///
  /// The served-round list is read from [formation] — the state *before* the
  /// figure ran — so that a figure which sets waiting-out state itself does not
  /// have that work undone by the change-over it triggers.
  ///
  /// [progressions] is the number the dance has already performed, which the
  /// distance-named dancer sets are measured against (see [Operation.reachAfter]).
  ///
  /// **A figure that reached along the set advances it twice.** Stepping out to
  /// dance with a couple further along the set is itself movement along the
  /// set, and a progression flag on top of that names more, so a flagged
  /// reaching figure finishes one phase past where an ordinary one would.
  /// `slide_along_set` is exempt because the slide *is* the progression
  /// ([Operation.isItsOwnProgression]): its displacement is the movement the
  /// flag names, so counting it twice would undo it. A figure whose reach has
  /// been closed to nothing by earlier progressions did not step out at all,
  /// so it does not qualify either.
  ///
  /// **A figure danced in several progression steps spends one progression per
  /// step** ([Operation.progressionSteps]): a flagged diagonal `slice` runs as
  /// two flagged slides, each with its own change-over *(user-ruled
  /// 2026-11-23)*.
  Result<Formation, OpError> apply(
    Formation formation, {
    int progressions = 0,
  }) {
    if (_steps case final steps?) {
      return _applySteps(steps, formation, progressions);
    }
    return operation
        .apply(formation, progressions: progressions)
        .map((next) => _finish(formation, next, progressions));
  }

  /// How many progressions this entry spends: none unflagged, otherwise
  /// [Operation.progressionsSpent].
  int get progressionCount => progression ? operation.progressionsSpent : 0;

  /// The steps of a flagged figure that spends more than one progression, or
  /// `null` for every other entry.
  List<Operation>? get _steps {
    if (!progression) return null;
    final steps = operation.progressionSteps;
    return steps.length > 1 ? steps : null;
  }

  /// Runs each step as its own flagged figure, the distance count advancing
  /// after each one.
  static Result<Formation, OpError> _applySteps(
    List<Operation> steps,
    Formation formation,
    int progressions,
  ) {
    Result<Formation, OpError> state = Ok(formation);
    for (var i = 0; i < steps.length; i++) {
      final step = OperationInvocation(steps[i], progression: true);
      state = state.flatMap(
        (current) => step.apply(current, progressions: progressions + i),
      );
    }
    return state;
  }

  /// [apply], except that a progression with nobody to step out yet is
  /// **held** rather than spent.
  ///
  /// The end-normalization a progression runs (`docs/fundamentals.md` §10.2)
  /// needs a whole couple standing in an end row. A Becket dance that
  /// progresses on a diagonal `chain` or a `pass_through` along the set has
  /// not brought one there yet: the robins have moved on, but the couples
  /// only stand together at the ends a figure or two later. Run there, the
  /// change-over would mark nobody and the progression would be lost. Held,
  /// it finishes on the first later figure that leaves a whole couple at an
  /// end; see [finishHeldProgression] and `FigureFold`. *(User-ruled
  /// 2026-11-23, in every formation: the test is only whether a whole couple
  /// stands at an end.)*
  ///
  /// When the result's `held` is `true`, its formation is the figure's own
  /// transform with no change-over applied, and the caller owes one
  /// progression. Otherwise this is exactly [apply].
  ///
  /// Only an ordinary figure is held. A figure that is its own progression
  /// decides its own waiting-out state, and a figure that reached along the
  /// set finishes a phase further on, which a later change-over could not
  /// reproduce; both finish where they are, as before. *(Agent's call,
  /// 2026-11-23: neither shape needed holding in the corpus measured.)*
  ///
  /// A figure danced in several progression steps is never held: each step is
  /// its own progression, run as [apply] runs it.
  Result<({Formation formation, bool held}), OpError> applyHolding(
    Formation formation, {
    int progressions = 0,
  }) {
    if (_steps case final steps?) {
      return _applySteps(
        steps,
        formation,
        progressions,
      ).map((next) => (formation: next, held: false));
    }
    return operation.apply(formation, progressions: progressions).map((next) {
      final hold =
          progression &&
          !operation.isItsOwnProgression &&
          !_reached(progressions) &&
          !endHasWholeCouple(next);
      return hold
          ? (formation: next, held: true)
          : (formation: _finish(formation, next, progressions), held: false);
    });
  }

  /// The change-over that follows a flagged figure, given the state it
  /// started in ([before]) and the state its transform produced ([next]).
  Formation _finish(Formation before, Formation next, int progressions) {
    if (!progression) return next;
    final normalized = applyEndNormalization(
      next,
      servedRound: waitingCouples(before),
    );
    return _reached(progressions) ? toggleBandPhase(normalized) : normalized;
  }

  /// Whether the figure names dancers a distance along the set, and so has
  /// already moved the set once before the flag asks for more.
  bool _reached(int progressions) =>
      !operation.isItsOwnProgression && operation.reachAfter(progressions) > 0;

  @override
  bool operator ==(Object other) =>
      other is OperationInvocation &&
      other.operation == operation &&
      other.progression == progression;

  @override
  int get hashCode => Object.hash(operation, progression);

  @override
  String toString() => progression ? '$name (progression)' : name;
}
