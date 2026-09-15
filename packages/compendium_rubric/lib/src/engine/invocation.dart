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
/// another. This type is therefore the single place where §3.2's ordering is
/// expressed: the operation's own transform runs first, and end-normalization
/// runs after it.
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
  Result<Formation, OpError> apply(
    Formation formation, {
    int progressions = 0,
  }) => operation.apply(formation, progressions: progressions).map((next) {
    if (!progression) return next;
    final normalized = applyEndNormalization(
      next,
      servedRound: waitingCouples(formation),
    );
    return _reached(progressions) ? toggleBandPhase(normalized) : normalized;
  });

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
