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
/// name exactly one pair, standing across the set from each other, which is
/// where a contra corners starts. Anything else is refused rather than
/// guessed. *(The across-the-set check is the agent's call, 2026-11-22, not
/// yet ruled.)*
///
/// `custom` is the record's own note on the variation ("same-role",
/// "opposite-role", …). It is carried for fidelity. It does not change the
/// landing: whichever corners are turned, they turn once around.
///
/// The actives' facing is left as it was (flexible). Facing is only ever a
/// warning here.
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
      final pair = pairs.single;
      final a = formation.stateOf(pair.a).position;
      final b = formation.stateOf(pair.b).position;
      if (a.row != b.row) {
        return Err(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'contra_corners starts with the actives facing each other across '
            'the set, but ${pair.a} and ${pair.b} are in different rows',
          ),
        );
      }
      actives.add(pair);
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
      _actives(formation).map((pairs) => swapPairs(formation, pairs));

  @override
  bool operator ==(Object other) =>
      other is ContraCorners && other.who == who && other.custom == custom;

  @override
  int get hashCode => Object.hash(name, who, custom);

  @override
  String toString() => 'contra_corners(${who.key})';
}
