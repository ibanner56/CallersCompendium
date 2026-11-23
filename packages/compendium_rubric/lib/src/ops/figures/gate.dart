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
/// and `whom` say which side backs up and which walks forward, and on a whole
/// or half turn are descriptive for the net position. It is `pair` — a third
/// axis — that selects the *gating pairs* there. When `pair` is absent, dancers
/// pair by shared column, the default hands-four adjacency.
///
/// A **fractional** gate differs on both counts: its gating pairs are fixed by
/// the shape (the sides of a ring, or the halves of a line of four), `pair` is
/// only checked against them, and on a `mirror` gate the forward dancer
/// (`whom`, or the one not in `who`) decides the sense (see [_quarterPlan]).
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

  /// The side that extends a hand and backs up — the pivot. Descriptive on a
  /// whole or half turn; on a fractional `mirror` gate it decides the sense
  /// when [whom] is absent. `null` is the upstream `unspecified` sentinel.
  final WhoSet? who;

  /// The side that walks forward. Descriptive on a whole or half turn; on a
  /// fractional `mirror` gate it decides the sense. `null` is `unspecified`.
  final WhoSet? whom;

  /// The pairing the gate is danced with. On a whole or half turn **this
  /// selects the gating pairs**, and `null` falls back to pairing by shared
  /// column. On a fractional gate the shape fixes the pairs and this is only
  /// checked against them.
  final WhoSet? pair;

  /// The rotation sense. No net-position effect at whole or half turns.
  final GateDirection? direction;

  /// The rotation amount, which drives the whole effect.
  ///
  /// `null` is the upstream `unspecified` sentinel, and it is **refused**: the
  /// taxonomy makes the amount the sole determinant of where dancers end, so
  /// assuming one would silently compile a different dance. The one exception
  /// is a bare gate (nothing else stated) standing in a line of four: that is
  /// how a "hand cast" arrives, and it closes the line the way `bendTheLine`
  /// does (user-ruled; see [_isBareHandCast]).
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
    if (face == GateFace.along) {
      return const OpError(
        ErrorKind.unsupportedParam,
        'gate face:along names no single direction across the set and is '
        'deferred',
      );
    }
    if (amount == null && _isBareHandCast) {
      return switch (_quarterPlan(formation)) {
        Ok() => null,
        Err(:final error) => error,
      };
    }
    if (amount == null) {
      return const OpError(
        ErrorKind.unsupportedParam,
        'gate needs a stated turn: the amount is the sole determinant of where '
        'dancers end, so an unspecified one cannot be resolved',
      );
    }
    if (rotationAmountOf(amount).landsInWave) {
      return switch (_quarterPlan(formation)) {
        Ok() => null,
        Err(:final error) => error,
      };
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
    if (turn == null || rotationAmountOf(turn!).landsInWave) {
      return switch (_quarterPlan(formation)) {
        Ok(:final value) => Ok(formation.withUpdates(value)),
        Err(:final error) => Err(error),
      };
    }
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

  /// Where a fractional gate puts every gating dancer.
  ///
  /// Each gating pair turns as a rigid unit about its joined hands, a net
  /// quarter: positions and facings rotate together. A pair standing on a side
  /// of a complete hands four (the two dancers of a side column, taken to be
  /// facing in, as a gate is danced from there) becomes one half of a line of
  /// four, and a half of a line of four becomes a side of the ring.
  ///
  /// The sense of rotation is [direction] when it names one; a `mirror` gate
  /// takes it from the dancer who walks forward ([whom], or the one not in
  /// [who]), each pair turning so that dancer moves the way the pair faces. A
  /// three-quarter gate is a quarter the other way.
  ///
  /// Refused rather than guessed: a band that is neither a complete ring nor a
  /// line of four, gating pairs other than its two sides or two halves, a
  /// `mirror` gate that does not say who walks forward, and a landing whose two
  /// halves would face opposite ways (a two-faced line, which the matrix does
  /// not hold).
  Result<Map<DancerId, DancerState>, OpError> _quarterPlan(
    Formation formation,
  ) {
    final handCast = turn == null;
    final quarters =
        handCast || rotationAmountOf(turn!) == RotationAmount.quarter ? 1 : 3;
    final changes = <DancerId, DancerState>{};
    for (final band in handsFourBands(formation)) {
      final lineRow = lineOfFourRow(formation, band);
      final List<_GateHalf> halves;
      final inBand = [
        ...formation.dancersInRow(band.topRow),
        ...formation.dancersInRow(band.bottomRow),
      ];
      if (inBand.length < 4) {
        // A band short a couple, as at an end of the set, is left where it
        // stands, as a half gate and the ring rotations leave it.
        continue;
      }
      if (lineRow != null &&
          const [
            0,
            1,
            3,
            4,
          ].any((col) => formation.dancerAt(Position(lineRow, col)) == null)) {
        return Err(
          OpError(
            ErrorKind.unresolvableDancerSet,
            '$_label turns a line of four standing on columns 0, 1, 3 and 4, '
            'but the line at row $lineRow stands elsewhere',
          ),
        );
      }
      if (lineRow != null) {
        halves = [
          for (final (west, east) in const [(0, 1), (3, 4)])
            _GateHalf.ofLine(formation, lineRow, west, east),
        ];
      } else if (handCast) {
        return Err(
          OpError(
            ErrorKind.unsupportedParam,
            'gate needs a stated turn: a bare hand cast is read only as '
            'closing a line of four into the ring, and rows ${band.topRow}/'
            '${band.bottomRow} hold no line',
          ),
        );
      } else if (bandIsComplete(formation, band)) {
        halves = [
          for (final col in const [0, kColumnCount - 1])
            _GateHalf.ofSide(formation, band, col),
        ];
      } else {
        return Err(
          OpError(
            ErrorKind.unresolvableDancerSet,
            '$_label turns a complete hands four into a line of four '
            'or a line back into a ring, but rows ${band.topRow}/'
            '${band.bottomRow} hold neither',
          ),
        );
      }

      for (final half in lineRow == null ? const <_GateHalf>[] : halves) {
        final fa = formation.stateOf(half.a).facing;
        final fb = formation.stateOf(half.b).facing;
        if (fa == fb && (fa == Facing.up || fa == Facing.down)) continue;
        return Err(
          OpError(
            ErrorKind.unresolvableDancerSet,
            '$_label turns a line of four by the way each pair faces, side by '
            'side, but ${half.a} faces ${fa.label} and ${half.b} faces '
            '${fb.label}',
          ),
        );
      }

      final stated = pair;
      if (stated != null) {
        for (final half in halves) {
          if (!whoMatches(formation, half.a, half.b, stated)) {
            return Err(
              OpError(
                ErrorKind.whoMismatch,
                '$_label pair:${stated.key} gates the two halves of '
                'the hands four, but ${half.a} and ${half.b} are not '
                '${stated.key}',
              ),
            );
          }
        }
      }

      final landed = <_GateLanding>[];
      for (final half in halves) {
        final sense = _senseFor(formation, half);
        if (sense case Err(:final error)) return Err(error);
        landed.add(
          half.turned((sense as Ok<bool, OpError>).value, quarters, band),
        );
      }
      final facings = {for (final l in landed) l.lineFacing};
      if (facings.length > 1) {
        return Err(
          OpError(
            ErrorKind.unsupportedParam,
            'gate ${direction?.key ?? ''} turn: $turn would leave the two '
            'halves of the hands four at rows ${band.topRow}/${band.bottomRow} '
            'facing opposite ways, a two-faced line, which is deferred',
          ),
        );
      }
      final lineFacing = facings.single;
      final statedFace = face;
      if (statedFace != null) {
        for (final l in landed) {
          for (final MapEntry(key: id, value: spot) in l.dancers.entries) {
            final want = _endFacing(
              formation.stateOf(id),
              Position(band.topRow, spot.col),
              false,
            );
            if (want == spot.facing) continue;
            return Err(
              OpError(
                ErrorKind.unsupportedParam,
                '$_label face:${statedFace.key} disagrees with where the '
                'turn leaves $id facing (${spot.facing.label})',
              ),
            );
          }
        }
      }
      for (final l in landed) {
        for (final MapEntry(key: id, value: (:col, :y, :facing))
            in l.dancers.entries) {
          final row = switch (lineFacing) {
            final f? => lineRowFor(band, f)!,
            null => y > 0 ? band.topRow : band.bottomRow,
          };
          changes[id] = formation
              .stateOf(id)
              .copyWith(position: Position(row, col), facing: facing);
        }
      }
    }
    return Ok(changes);
  }

  /// Whether [half] turns clockwise: [direction] when it names a sense, else
  /// the sense that carries the forward dancer the way the pair faces.
  Result<bool, OpError> _senseFor(Formation formation, _GateHalf half) {
    if (turn == null) return Ok(half.clockwiseMoves(half.end));
    switch (direction) {
      case GateDirection.clockwise:
        return const Ok(true);
      case GateDirection.counterclockwise:
        return const Ok(false);
      case null:
        return Err(
          OpError(
            ErrorKind.unsupportedParam,
            'gate turn: $turn needs a direction: which way the pair turns '
            'decides where a fractional gate lands',
          ),
        );
      case GateDirection.mirror:
        break;
    }
    bool forward(DancerId id) {
      final w = whom;
      if (w != null) return whoIncludes(formation, id, w);
      final b = who;
      if (b != null) return !whoIncludes(formation, id, b);
      return false;
    }

    final walkers = [half.a, half.b].where(forward).toList();
    if (walkers.length != 1) {
      return Err(
        OpError(
          ErrorKind.unresolvableDancerSet,
          'gate mirror turn: $turn needs exactly one dancer of each pair to '
          'walk forward, but ${half.a} and ${half.b} have '
          '${walkers.length} named${whom == null && who == null ? ' (the '
                    'record names neither who backs up nor who walks forward)' : ''}',
        ),
      );
    }
    return Ok(half.clockwiseMoves(walkers.single));
  }

  /// How refusals name this gate: its turn, or "hand cast" when bare.
  String get _label =>
      turn == null ? 'hand cast (a bare gate)' : 'gate turn: $turn';

  /// A gate with nothing stated at all, which is how a bare "hand cast"
  /// arrives: read as closing a line of four the way `bendTheLine` does.
  bool get _isBareHandCast =>
      turn == null &&
      who == null &&
      whom == null &&
      pair == null &&
      direction == null &&
      face == null;

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

/// A unit vector on the floor: `x` toward c4 (East), `y` toward row 0 (up).
typedef _Vec = ({int x, int y});

_Vec _vecOf(Facing facing) => switch (facing) {
  Facing.up => (x: 0, y: 1),
  Facing.down => (x: 0, y: -1),
  Facing.acrossEast => (x: 1, y: 0),
  Facing.acrossWest => (x: -1, y: 0),
  _ => (x: 0, y: 0),
};

Facing _facingOf(_Vec v) => switch (v) {
  (x: 0, y: 1) => Facing.up,
  (x: 0, y: -1) => Facing.down,
  (x: 1, y: 0) => Facing.acrossEast,
  _ => Facing.acrossWest,
};

/// [v] turned a quarter clockwise (seen from above, up the hall at the top).
_Vec _cw(_Vec v) => (x: v.y, y: -v.x);

/// [v] turned a quarter counter-clockwise.
_Vec _ccw(_Vec v) => (x: -v.y, y: v.x);

/// Where one gating dancer lands: a column, which side of the pair's middle
/// along the hall (`y`, for a ring side), and a facing.
typedef _GateSpot = ({int col, int y, Facing facing});

/// One turned half of a hands four.
class _GateLanding {
  const _GateLanding(this.dancers, this.lineFacing);

  final Map<DancerId, _GateSpot> dancers;

  /// The facing of the line this half now belongs to, or `null` when it
  /// landed as a side of the ring.
  final Facing? lineFacing;
}

/// A gating pair as one half of a hands four: either a side of the ring or a
/// half of a line of four, with each dancer's offset from the pair's middle.
class _GateHalf {
  _GateHalf._(this.a, this.b, this.offsets, this.facing, this.westCol);

  /// The two dancers of the side column at [col], facing in.
  factory _GateHalf.ofSide(Formation formation, Band band, int col) {
    final top = formation.dancerAt(Position(band.topRow, col))!;
    final bottom = formation.dancerAt(Position(band.bottomRow, col))!;
    return _GateHalf._(
      top,
      bottom,
      {top: (x: 0, y: 1), bottom: (x: 0, y: -1)},
      acrossFacingInto(col),
      col == 0 ? 0 : kColumnCount - 2,
    );
  }

  /// The two dancers of the line half on columns [west] and [east].
  factory _GateHalf.ofLine(Formation formation, int row, int west, int east) {
    final w = formation.dancerAt(Position(row, west))!;
    final e = formation.dancerAt(Position(row, east))!;
    return _GateHalf._(
      w,
      e,
      {w: (x: -1, y: 0), e: (x: 1, y: 0)},
      formation.stateOf(w).facing,
      west,
    );
  }

  final DancerId a;
  final DancerId b;
  final Map<DancerId, _Vec> offsets;

  /// The way the pair faces, side by side.
  final Facing facing;

  /// The west column of the two this half spans as a line.
  final int westCol;

  /// The dancer of a line half standing at the end of the line.
  DancerId get end => offsets[a]!.x * (westCol == 0 ? 1 : -1) < 0 ? a : b;

  /// Whether turning clockwise carries [walker] the way the pair faces.
  bool clockwiseMoves(DancerId walker) {
    final p = offsets[walker]!;
    final f = _vecOf(facing);
    // The clockwise velocity at p is (p.y, -p.x).
    return p.y * f.x - p.x * f.y > 0;
  }

  _GateLanding turned(bool clockwise, int quarters, Band band) {
    final turn = clockwise ? _cw : _ccw;
    _Vec spin(_Vec v) {
      var out = v;
      for (var i = 0; i < quarters; i++) {
        out = turn(out);
      }
      return out;
    }

    final faced = _facingOf(spin(_vecOf(facing)));
    final dancers = <DancerId, _GateSpot>{};
    var asLine = false;
    for (final MapEntry(key: id, value: p) in offsets.entries) {
      final q = spin(p);
      if (q.x != 0) {
        asLine = true;
        dancers[id] = (
          col: q.x < 0 ? westCol : westCol + 1,
          y: 0,
          facing: faced,
        );
      } else {
        final sideCol = westCol == 0 ? 0 : kColumnCount - 1;
        dancers[id] = (col: sideCol, y: q.y, facing: faced);
      }
    }
    return _GateLanding(dancers, asLine ? faced : null);
  }
}
