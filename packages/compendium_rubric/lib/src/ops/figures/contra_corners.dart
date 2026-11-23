part of '../operation.dart';

/// `contra_corners` — the active couple turn each other by the right, a corner
/// by the left, each other again, and the other corner by the left.
///
/// **User-ruled (2026-11-22):** a full-phrase contra corners returns the
/// actives to their **partner's place**, in the centre facing each other. The
/// corners turn once around and end where they began. So the landing is the
/// two actives swapping places, and nobody else moving.
///
/// `who` names the actives (the ones by default). In every hands four it must
/// name exactly one pair; anything else (no actives, or a `who` such as
/// `partners` that names two pairs) has no single couple to swap and is
/// refused rather than guessed.
///
/// `custom` is the record's own note on the variation ("same-role",
/// "opposite-role", …). It is carried for fidelity. It does not change the
/// landing: whichever corners are turned, they turn once around.
///
/// The actives end facing each other, as ruled: each faces across the set
/// toward the other's column, or along it toward the other's row when they
/// share a column. Facing is only ever a warning here.
final class ContraCorners extends Operation {
  const ContraCorners({this.who = WhoSet.ones, this.custom = ''});

  /// The actives.
  final WhoSet who;

  /// Free-text variation note; no positional effect.
  final String custom;

  @override
  String get name => 'contra_corners';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  Result<List<DancerPair>, OpError> _actives(Formation formation) {
    final actives = <DancerPair>[];
    for (final band in handsFourBands(formation)) {
      final pairs = resolveWhoPairs(
        formation,
        who,
        topRow: band.topRow,
        bottomRow: band.bottomRow,
      );
      if (pairs.length != 1) {
        return Err(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'contra_corners needs exactly one ${who.key} pair to turn the '
            'corners in each hands four, but rows '
            '${band.topRow}-${band.bottomRow} have ${pairs.length}',
          ),
        );
      }
      actives.add(pairs.single);
    }
    return Ok(actives);
  }

  @override
  OpError? checkPreconditions(Formation formation) =>
      switch (_actives(formation)) {
        Ok() => null,
        Err(:final error) => error,
      };

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      _actives(formation).map(
        (pairs) => swapPairs(
          formation,
          pairs,
          facing: (before, after, other) => _toward(after, other),
        ),
      );

  /// The facing from [from] toward [to].
  static Facing _toward(Position from, Position to) {
    if (from.col != to.col) {
      return to.col > from.col ? Facing.acrossEast : Facing.acrossWest;
    }
    return to.row > from.row ? Facing.down : Facing.up;
  }

  @override
  bool operator ==(Object other) =>
      other is ContraCorners && other.who == who && other.custom == custom;

  @override
  int get hashCode => Object.hash(name, who, custom);

  @override
  String toString() => custom.isEmpty
      ? 'contra_corners(${who.key})'
      : 'contra_corners(${who.key}, $custom)';
}
