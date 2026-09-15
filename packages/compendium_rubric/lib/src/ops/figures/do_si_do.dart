part of '../operation.dart';

/// `do_si_do` — two dancers walk around each other back-to-back
/// (`docs/taxonomy.md`).
///
/// Unlike [Swing] this is **not** a normalizing figure and facing is
/// **preserved**: dancers keep the direction they arrived with, whatever the
/// amount of [circling] — except where the figure lands them in a wave, whose
/// own resting facing owns the result (§8.5.1). At a duple improper start the
/// two coincide, so the distinction only shows from a set already turned.
///
/// Supported amounts:
/// - **whole** (1, 2, …) — a full orbit back to place, so the identity.
/// - **half** (0.5, 1.5, …) — the two `who` dancers swap cells, carrying role,
///   number, couple identity and facing with them. [shoulder] is irrelevant
///   here because 180° lands opposite either way.
/// - **quarter** (0.25, 1.25, …) — the pair rotate 90° about their midpoint and
///   land in a short wave, [shoulder] fixing its handedness. This is the corpus
///   form `do-si-do 1¼; form wave of four`.
/// - **three-quarter** (0.75, 1.75, …) — a half turn and then a quarter, so the
///   same wave with the other role in the centre.
///
/// Quarters are defined for an **along-the-set** pair only; across the set they
/// raise [ErrorKind.unsupportedParam] rather than being approximated.
final class DoSiDo extends Operation {
  const DoSiDo({
    required this.who,
    this.circling = 1,
    this.shoulder = Hand.right,
  });

  /// The pair that walks around each other. A **precondition** in the sense
  /// that no pairing is inferred from position — but here it also *selects*
  /// the dancers who move.
  final WhoSet who;

  /// How far around, in full orbits.
  final double circling;

  /// Which shoulder leads. At whole and half amounts it has no end-state
  /// effect; on a quarter it is the token that fixes the resulting wave's
  /// handedness, `right` building the canonical wave.
  final Hand shoulder;

  @override
  String get name => 'do_si_do';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  /// How far around [circling] goes, as the four cases the taxonomy
  /// distinguishes.
  RotationAmount get _amount => rotationAmountOf(circling);

  @override
  OpError? checkPreconditions(Formation formation) {
    if (_amount.landsInWave) {
      final across = firstPairAcrossTheSet(
        formation,
        whoPairsInSet(formation, who),
      );
      if (across != null) {
        return OpError(
          ErrorKind.unsupportedParam,
          'do_si_do circling: $circling lands in a wave, which is defined for '
          'a pair along the set; ${across.a} and ${across.b} are across it, '
          'and the across-the-set quarter is deferred',
        );
      }
    }
    for (final band in handsFourBands(formation)) {
      final pairs = resolveWhoPairs(
        formation,
        who,
        topRow: band.topRow,
        bottomRow: band.bottomRow,
      );
      if (pairs.isEmpty && formation.dancersInRow(band.topRow).isNotEmpty) {
        return OpError(
          ErrorKind.whoMismatch,
          'no ${who.key} pair in the hands four at rows '
          '${band.topRow}/${band.bottomRow}',
        );
      }
    }
    return null;
  }

  @override
  Result<Formation, OpError> perform(Formation formation) {
    if (_amount == RotationAmount.whole) return Ok(formation);
    if (_amount.landsInWave) {
      return Ok(
        quarterTurnIntoWave(
          formation,
          whoPairsInSet(formation, who),
          hand: shoulder,
          afterHalfTurn: _amount == RotationAmount.threeQuarter,
        ),
      );
    }

    final changes = <DancerId, DancerState>{};
    for (final band in handsFourBands(formation)) {
      final pairs = resolveWhoPairs(
        formation,
        who,
        topRow: band.topRow,
        bottomRow: band.bottomRow,
      );
      for (final pair in pairs) {
        final stateA = formation.stateOf(pair.a);
        final stateB = formation.stateOf(pair.b);
        changes[pair.a] = stateA.copyWith(position: stateB.position);
        changes[pair.b] = stateB.copyWith(position: stateA.position);
      }
    }
    return Ok(formation.withUpdates(changes));
  }

  @override
  bool operator ==(Object other) =>
      other is DoSiDo &&
      other.who == who &&
      other.circling == circling &&
      other.shoulder == shoulder;

  @override
  int get hashCode => Object.hash(name, who, circling, shoulder);

  @override
  String toString() => 'do_si_do(${who.key}, $circling, ${shoulder.key})';
}
