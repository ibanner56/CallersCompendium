import '../domain/dancer.dart';
import '../domain/formation.dart';
import '../geometry/geometry.dart';
import '../ops/diagnostics.dart';

/// The most end-effect trades one compile tries along a single path: one at
/// each end of the set, enforced by the `spentRows` of [endEffectCandidates].
/// *(Agent's call, 2026-11-24: allowing four trades gained no corpus dance.)*
const maxEndEffectSwaps = 2;

/// The pairs of dancers an end-effect retry may trade in place before the
/// figure that refused with [error] (`docs/fundamentals.md` §10.7).
///
/// A pair qualifies when, in [state] (the set the refusing figure was handed):
///
/// - they are the **only two dancers** in the top or bottom row, whoever they
///   are: partners, or a neighbour or shadow pair left there by a figure that
///   mixed the couples *(user-ruled 2026-11-24)*;
/// - **neither moved** in the figure before, which was handed [previous], while
///   **someone else did**. A figure that leaves everyone in place (a whole
///   circle) says nothing about who is waiting, and without this every end row
///   would look idle after it;
/// - they were **out of that figure**: either their row was standing out of
///   every hands four as [previous] was danced (its dancers marked waiting
///   out, which a caller makes sure of by passing the set as the figure was
///   danced, one band phase over where it followed a reach), or **every
///   dancer outside the end rows moved** in it, so a pair at an end that
///   stood still is one that had nobody to dance with there (no shadow above
///   the top, say). A figure for part of the set, which leaves some of the
///   middle standing too, says nothing about who is waiting, and a pair in a
///   live hands four is never offered for it;
/// - [error] **names one of them**, so the retry only answers a refusal about
///   the dancers at the end;
/// - their row is not in [spentRows]: each end trades at most once along one
///   fold.
///
/// Each pair is listed in its row's order, top row first. With no figure
/// before (the first figure refused), nobody is waiting and the list is empty.
List<(int, (DancerId, DancerId))> endEffectCandidates(
  Formation state, {
  required Formation? previous,
  required OpError error,
  Set<int> spentRows = const {},
}) {
  if (previous == null) return const [];
  bool stood(DancerId id) =>
      previous.stateOf(id).position == state.stateOf(id).position;
  final stranded = waitingOutRows(previous).toSet();
  final middleAllMoved = state.dancers.keys
      .where((id) {
        final row = state.stateOf(id).position.row;
        return row != 0 && row != state.lastRow;
      })
      .every((id) => !stood(id));

  final found = <(int, (DancerId, DancerId))>[];
  for (final row in {0, state.lastRow}) {
    if (spentRows.contains(row)) continue;
    if (!stranded.contains(row) && !middleAllMoved) continue;
    final ids = state.dancersInRow(row);
    if (ids.length != 2) continue;
    if (!ids.every(stood)) continue;
    final othersMoved = state.dancers.keys.any(
      (id) => !ids.contains(id) && !stood(id),
    );
    if (!othersMoved) continue;
    final message = error.message;
    if (!ids.any((id) => message.contains('$id'))) continue;
    found.add((row, (ids[0], ids[1])));
  }
  return found;
}

/// [state] with the two dancers of [pair] standing in each other's places.
///
/// Only positions trade. Each keeps their own facing, number and waiting-out
/// mark: the pair crosses over where it stands, as a couple out at an end does,
/// and nobody else moves.
Formation tradeInPlace(Formation state, (DancerId, DancerId) pair) {
  final (a, b) = pair;
  final first = state.stateOf(a);
  final second = state.stateOf(b);
  return state.withUpdates({
    a: first.copyWith(position: second.position),
    b: second.copyWith(position: first.position),
  });
}
