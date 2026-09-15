part of '../operation.dart';

/// The set-relative facings a `gate` can end in.
///
/// `up`/`down` run along the hall and `in`/`out` across the set. `along` is in
/// the upstream vocabulary but names no single direction on its own, so it is
/// accepted on input and refused by the figure rather than being guessed at.
enum GateFace {
  up('up'),
  down('down'),
  towardSet('in'),
  awayFromSet('out'),
  along('along');

  const GateFace(this.key);

  /// The value as it appears in the external JSON.
  final String key;

  static GateFace? fromKey(String key) {
    for (final value in GateFace.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// A gate's rotation sense.
///
/// Not a plain [SpinDirection]: `mirror` names a two-couple gate in which the
/// two roles rotate in **opposite** senses, which has no single spin.
enum GateDirection {
  clockwise('clockwise'),
  counterclockwise('counterclockwise'),
  mirror('mirror');

  const GateDirection(this.key);

  /// The value as it appears in the external JSON.
  final String key;

  static GateDirection? fromKey(String key) {
    for (final value in GateDirection.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// `gate` — two dancers join hands, one backing up while the other walks
/// forward, so the pair orbits about their joined hands.
///
/// Unified in CallersCompendium v22, which folded the former `rotation_gate`
/// into this move; there is deliberately no separate figure for it.
///
/// Three parameters name dancers and they are **not** interchangeable. `who`
/// and `whom` say which side backs up and which walks forward, and are
/// descriptive for the net position. It is `pair` — a third axis — that selects
/// the *gating pairs*. When `pair` is absent, dancers pair by shared column,
/// the default hands-four adjacency.
///
/// The ending facing is **stored data**, not derived. CallersCompendium
/// withdrew its absolute end-facing derivation as unsound: an absolute cardinal
/// cannot be recovered without simulating every preceding figure. When `face`
/// is absent this falls back to a deliberately *relative* rule — a half gate
/// inverts facing, a whole gate leaves it — which is sound precisely because we
/// do track facing through the compile.
final class Gate extends Operation {
  const Gate({
    this.who,
    this.whom,
    this.pair,
    this.direction,
    this.turn,
    this.face,
  });

  /// The side that extends a hand and backs up — the pivot. Descriptive.
  /// `null` is the upstream `unspecified` sentinel.
  final WhoSet? who;

  /// The side that walks forward. Descriptive; `null` is `unspecified`.
  final WhoSet? whom;

  /// The pairing the gate is danced with. **This selects the gating pairs.**
  /// `null` falls back to pairing by shared column.
  final WhoSet? pair;

  /// The rotation sense. No net-position effect at whole or half turns.
  final GateDirection? direction;

  /// The rotation amount, which drives the whole effect.
  ///
  /// `null` is the upstream `unspecified` sentinel, and it is **refused**: the
  /// taxonomy makes the amount the sole determinant of where dancers end, so
  /// assuming one would silently compile a different dance.
  final double? turn;

  /// The ending facing, when the source states one. Authoritative when present.
  final GateFace? face;

  @override
  String get name => 'gate';

  @override
  Iterable<WhoSet?> get dancerSets => [who, whom, pair];

  @override
  bool get progressionEligible => true;

  /// The pairs that gate together.
  ///
  /// A stated [pair] selects them by relationship; otherwise dancers pair by
  /// shared column within each hands four.
  List<DancerPair> _gatingPairs(Formation formation) {
    final stated = pair;
    if (stated != null) return whoPairsInSet(formation, stated);

    final pairs = <DancerPair>[];
    for (final band in handsFourBands(formation)) {
      for (var col = 0; col < kColumnCount; col++) {
        final top = formation.dancerAt(Position(band.topRow, col));
        final bottom = formation.dancerAt(Position(band.bottomRow, col));
        if (top == null || bottom == null) continue;
        pairs.add((a: top, b: bottom));
      }
    }
    return pairs;
  }

  @override
  OpError? checkPreconditions(Formation formation) {
    final amount = turn;
    if (amount == null) {
      return const OpError(
        ErrorKind.unsupportedParam,
        'gate needs a stated turn: the amount is the sole determinant of where '
        'dancers end, so an unspecified one cannot be resolved',
      );
    }
    if (rotationAmountOf(amount).landsInWave) {
      return OpError(
        ErrorKind.unsupportedParam,
        'gate supports whole and half turns; turn: $amount is a fractional '
        'gate, used to get into and out of a line of four, which is deferred',
      );
    }
    if (face == GateFace.along) {
      return const OpError(
        ErrorKind.unsupportedParam,
        'gate face:along names no single direction across the set and is '
        'deferred',
      );
    }

    final pairs = _gatingPairs(formation);
    if (pairs.isEmpty && handsFourBands(formation).isNotEmpty) {
      return OpError(
        ErrorKind.unresolvableDancerSet,
        'gate could not resolve any gating pair'
        '${pair == null ? ' by shared column' : ' for pair:${pair!.key}'}',
      );
    }
    final apart = firstNonAdjacentPair(formation, pairs);
    if (apart == null) return null;
    return OpError(
      ErrorKind.unresolvableDancerSet,
      'gate needs each gating pair adjacent, but ${apart.a} and ${apart.b} '
      'are diagonal',
    );
  }

  /// The facing a dancer landing in [at] finishes with.
  Facing _endFacing(DancerState before, Position at, bool isHalf) =>
      switch (face) {
        GateFace.up => Facing.up,
        GateFace.down => Facing.down,
        GateFace.towardSet => acrossFacingInto(at.col),
        GateFace.awayFromSet => acrossFacingInto(at.col).reversed,
        // Refused in preconditions; unreachable.
        GateFace.along => before.facing,
        null => isHalf ? before.facing.reversed : before.facing,
      };

  @override
  Result<Formation, OpError> perform(Formation formation) {
    final pairs = _gatingPairs(formation);
    final isHalf = rotationAmountOf(turn!) == RotationAmount.half;
    if (isHalf) {
      return Ok(
        swapPairs(
          formation,
          pairs,
          facing: (before, after, other) => _endFacing(before, after, true),
        ),
      );
    }

    final gaters = {
      for (final p in pairs) ...[p.a, p.b],
    };
    return Ok(
      formation.withUpdates({
        for (final id in gaters)
          id: formation
              .stateOf(id)
              .copyWith(
                facing: _endFacing(
                  formation.stateOf(id),
                  formation.stateOf(id).position,
                  false,
                ),
              ),
      }),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Gate &&
      other.who == who &&
      other.whom == whom &&
      other.pair == pair &&
      other.direction == direction &&
      other.turn == turn &&
      other.face == face;

  @override
  int get hashCode => Object.hash(name, who, whom, pair, direction, turn, face);

  @override
  String toString() =>
      'gate(pair: ${pair?.key ?? 'byColumn'}, turn: $turn, '
      'face: ${face?.key ?? 'unspecified'})';
}
