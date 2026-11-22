part of '../operation.dart';

/// `right_left_through` — two facing couples pass through and courtesy-turn,
/// trading with the couple across (`docs/taxonomy.md`).
///
/// The net effect is a **diagonal swap** within the hands four:
/// `(r0,c0) ↔ (r1,c4)` and `(r0,c4) ↔ (r1,c0)` — equivalently "the two larks
/// swap and the two robins swap, then courtesy-turn."
///
/// The courtesy turn is **internal to this figure**; the taxonomy is explicit
/// that a separate `courtesy_turn` op must not be paired with it. Because the
/// turn is a rigid wheel it *preserves* handedness rather than imposing
/// lark-left/robin-right, so no normalization is applied here — a couple
/// arriving inverted ends inverted, which the plain diagonal swap already
/// produces.
///
/// Only `dir: across` is defined. `along` and the diagonals are deferred in the
/// spec itself and raise [ErrorKind.unsupportedParam].
final class RightLeftThrough extends Operation {
  const RightLeftThrough({this.dir = 'across'});

  /// The direction of the trade. Only `across` is supported.
  final String dir;

  @override
  String get name => 'right_left_through';

  @override
  OpError? checkPreconditions(Formation formation) {
    if (dir != 'across') {
      return OpError(
        ErrorKind.unsupportedParam,
        'right_left_through supports dir:across only; dir:$dir is deferred',
      );
    }
    return null;
  }

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      Ok(_tradeDiagonallyFacingIn(formation));

  @override
  bool operator ==(Object other) =>
      other is RightLeftThrough && other.dir == dir;

  @override
  int get hashCode => Object.hash(name, dir);

  @override
  String toString() => 'right_left_through($dir)';
}

/// Each dancer trades with the one **diagonally across** their hands four and
/// faces back into the set: `(top, west) ↔ (bottom, east)` and
/// `(top, east) ↔ (bottom, west)` in every band.
///
/// The landing `right_left_through` and `promenade` across share. Both carry a
/// pair over to the far side and finish with a rigid 180° couple wheel, and a
/// wheel turns the pair end for end, so whoever crossed on the top row lands
/// on the bottom one (`docs/taxonomy.md`, both entries). A cell with nobody in
/// it leaves its diagonal untouched.
Formation _tradeDiagonallyFacingIn(Formation formation) {
  const west = 0;
  const east = kColumnCount - 1;
  Facing facingIn(int col) =>
      col == west ? Facing.acrossEast : Facing.acrossWest;
  final changes = <DancerId, DancerState>{};

  for (final band in handsFourBands(formation)) {
    final diagonals = [
      (Position(band.topRow, west), Position(band.bottomRow, east)),
      (Position(band.topRow, east), Position(band.bottomRow, west)),
    ];
    for (final (from, to) in diagonals) {
      final a = formation.dancerAt(from);
      final b = formation.dancerAt(to);
      if (a == null || b == null) continue;
      changes[a] = formation
          .stateOf(a)
          .copyWith(position: to, facing: facingIn(to.col));
      changes[b] = formation
          .stateOf(b)
          .copyWith(position: from, facing: facingIn(from.col));
    }
  }
  return formation.withUpdates(changes);
}
