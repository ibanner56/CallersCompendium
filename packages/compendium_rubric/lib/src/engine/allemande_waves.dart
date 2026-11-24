import '../domain/dancer.dart';
import '../domain/facing.dart';
import '../domain/formation.dart';
import '../geometry/geometry.dart';
import '../domain/position.dart';
import '../ops/operation.dart';
import '../ops/params.dart';
import '../ops/transforms.dart';
import 'result.dart';

/// The set an allemande may have left in short waves, for the retries the
/// compiler makes when the figure straight after it refuses, or when the
/// whole dance lands somewhere other than its expected end
/// (`docs/fundamentals.md` §8.5.8, user-ruled 2026-11-24).
///
/// [handed] is the set [allemande] was danced from and [state] the set it
/// left. Null when there is no wave reading to try:
///
/// - an allemande **in the centre**, every turning pair having started one on
///   each side of the set and finishing in the two rows of one band, moves
///   each of those dancers one column in, so the pair stands as the centre
///   of a short wave. A pair that finishes in one row has no reading (the
///   two would stand side by side facing the same way, a box), and a pair a
///   change-over sent out to an end is left where it is;
/// - an allemande **on the side**, every turning pair having started on one
///   side line, sets every complete hands four's columns as
///   `form_short_waves` would with that outside hand, so a neighbour
///   allemande right forms the wave whose centre joins left.
///
/// In the centre case each dancer keeps their row and marks, and only
/// columns and facing change: the turning pairs step in, and every band's top
/// row faces down and bottom row up, as a short wave stands (§8.5.1). The
/// side case takes the positions and facings `form_short_waves` gives
/// outright. A quarter or three-quarter allemande already lands in a wave and
/// is not read again, and a set whose turning pairs are some across and some
/// along, or whose centre turners are not on the side lines, has no reading.
Formation? allemandeWaveReading(
  Formation handed,
  Formation state,
  Allemande allemande,
) {
  if (rotationAmountOf(allemande.turn).landsInWave) return null;
  final pairs = whoPairsInSet(handed, allemande.who);
  if (pairs.isEmpty) return null;
  // Across or along is read from where the pairs stood when they started: a
  // flagged allemande's change-over may have crossed the end couples since.
  Position before(DancerId id) => handed.stateOf(id).position;
  final across = pairs.every(
    (pair) => before(pair.a).col != before(pair.b).col,
  );
  final along = pairs.every((pair) => before(pair.a).col == before(pair.b).col);
  const east = kColumnCount - 1;
  final changes = <DancerId, DancerState>{};
  if (across) {
    final bands = handsFourBands(state);
    final active = {
      for (final band in bands) ...[band.topRow, band.bottomRow],
    };
    for (final pair in pairs) {
      final a = state.stateOf(pair.a).position;
      final b = state.stateOf(pair.b).position;
      // A pair a change-over sent out to an end is waiting, not in a wave.
      if (!active.contains(a.row) || !active.contains(b.row)) continue;
      // Two who finish in one row would step in to stand side by side
      // facing the same way, a box rather than a wave (§8.5.1); two in
      // different bands are no one wave's centre.
      if (a.row == b.row ||
          handsFourBandContaining(state, a.row) !=
              handsFourBandContaining(state, b.row)) {
        return null;
      }
      for (final id in [pair.a, pair.b]) {
        final dancer = state.stateOf(id);
        final at = dancer.position.col;
        if (at != 0 && at != east) return null;
        changes[id] = dancer.copyWith(
          position: Position(dancer.position.row, at == 0 ? 1 : east - 1),
        );
      }
    }
    if (changes.isEmpty) return null;
    // A wave faces its top row down and its bottom row up (§8.5.1).
    for (final band in bands) {
      for (final (row, facing) in [
        (band.topRow, Facing.down),
        (band.bottomRow, Facing.up),
      ]) {
        for (final id in state.dancersInRow(row)) {
          final current = changes[id] ?? state.stateOf(id);
          changes[id] = current.copyWith(facing: facing);
        }
      }
    }
  } else if (along) {
    final wave = FormShortWaves(
      centerHand: allemande.hand == Hand.right ? Hand.left : Hand.right,
      center: null,
      sides: null,
    ).perform(state);
    if (wave case Ok(:final value)) {
      for (final entry in value.dancers.entries) {
        final dancer = state.stateOf(entry.key);
        if (dancer.position == entry.value.position &&
            dancer.facing == entry.value.facing) {
          continue;
        }
        changes[entry.key] = dancer.copyWith(
          position: entry.value.position,
          facing: entry.value.facing,
        );
      }
    } else {
      return null;
    }
  } else {
    return null;
  }
  if (changes.isEmpty) return null;
  return state.withUpdates(changes);
}
