part of '../operation.dart';

/// Which part of the line travels. Only [HallMoving.all] is implemented.
enum HallMoving {
  all('all'),
  center('center'),
  outsides('outsides');

  const HallMoving(this.key);

  /// The value as it appears in the external JSON.
  final String key;

  static HallMoving? fromKey(String key) {
    for (final value in HallMoving.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// How the line is oriented relative to its travel.
///
/// Travel is positionally inert, so this parameter's whole job is to set the
/// **ending facing** — and, through it, the row the line normalizes into.
enum HallFacing {
  forward('forward'),
  forwardThenBackward('forwardThenBackward'),
  backward('backward');

  const HallFacing(this.key);

  /// The value as it appears in the external JSON.
  final String key;

  static HallFacing? fromKey(String key) {
    for (final value in HallFacing.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// The figure that reshapes or reorients the line at the end of its travel.
///
/// Six of the ten are implemented; the rest are deferred (see the Held table in
/// `docs/taxonomy.md`). [HallEnder.circle] is a **synonym** of
/// [HallEnder.bendTheLine]: as an ender, "circle" says only that the line
/// closes into a ring, which is why it carries no `places` or direction.
enum HallEnder {
  none('none'),
  turnCouple('turnCouple'),
  turnAlone('turnAlone'),
  slidingDoors('slidingDoors'),
  bendTheLine('bendTheLine'),
  circle('circle'),
  cozy('cozy'),
  cloverleaf('cloverleaf'),
  threadNeedle('threadNeedle'),
  rightHandHigh('rightHandHigh');

  const HallEnder(this.key);

  /// The value as it appears in the external JSON.
  final String key;

  /// Whether the line closes into a ring — `bendTheLine` and its synonym.
  bool get closesTheRing =>
      this == HallEnder.bendTheLine || this == HallEnder.circle;

  static HallEnder? fromKey(String key) {
    for (final value in HallEnder.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// `down_the_hall` / `up_the_hall` — the hands four forms a **line of four**
/// and travels along the hall, finishing with an `ender`.
///
/// **Travel is positionally inert.** Going down the hall is not a matrix
/// transformation; it is a movement of the entire matrix, and so produces no
/// displacement. Every real state change here comes from the two phases either
/// side of it — the **gather** that forms the line and the **ender** that
/// reshapes it.
///
/// The gather is *conditional*, and must be. Re-running it on a line that
/// already exists would silently re-normalize it, and a re-normalized line is a
/// different line: `turnAlone` deliberately leaves the line inverted, so an
/// `up_the_hall` that re-gathered would erase the turn and make "down the hall,
/// turn alone, come back" undo itself. An existing line is passed through
/// untouched, inverted or not.
sealed class HallFigure extends Operation {
  const HallFigure({
    required this.who,
    required this.moving,
    required this.facing,
    required this.ender,
  });

  /// Which dancers travel. Only the whole hands four is defined.
  final WhoSet who;

  /// Which part of the line travels. Only [HallMoving.all] is implemented.
  final HallMoving moving;

  /// Orientation relative to travel; sets the ending facing.
  final HallFacing facing;

  /// The figure that ends the travel.
  final HallEnder ender;

  /// The direction the line travels. Inert positionally, but it orients the
  /// [HallEnder.bendTheLine] fold, which places the ends toward travel.
  Facing get travel;

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  /// The facing the line finishes the *travel* on, before any ender.
  Facing get _travelEndFacing =>
      facing == HallFacing.backward ? travel.reversed : travel;

  /// The [FaceDirection] the gather normalizes against.
  FaceDirection get _gatherFace =>
      _travelEndFacing == Facing.down ? FaceDirection.down : FaceDirection.up;

  @override
  OpError? checkPreconditions(Formation formation) {
    if (who != WhoSet.everyone) {
      return OpError(
        ErrorKind.unsupportedParam,
        '$name is defined for the whole hands four; who:${who.key} is '
        'deferred',
      );
    }
    if (moving != HallMoving.all) {
      return OpError(
        ErrorKind.unsupportedParam,
        '$name moving:${moving.key} leaves part of the line behind, producing '
        'a shape that is not a line of four; deferred',
      );
    }
    if (_enderSlots(ender) == null && !ender.closesTheRing) {
      return OpError(
        ErrorKind.unsupportedParam,
        '$name ender:${ender.key} is deferred',
      );
    }

    for (final band in handsFourBands(formation)) {
      if (bandIsComplete(formation, band)) continue;
      if (lineOfFourRow(formation, band) != null) continue;
      return OpError(
        ErrorKind.unresolvableDancerSet,
        '$name needs a complete hands four - two dancers in each side column, '
        'or an existing line of four - but rows ${band.topRow}/'
        '${band.bottomRow} hold neither',
      );
    }
    return null;
  }

  /// The slot permutation an ender applies, or `null` when it does not act by
  /// permuting slots (a deferred ender, or the ring-closing fold).
  ///
  /// Slots read `s0 = c0, s1 = c1, s2 = c3, s3 = c4`. Each entry names the
  /// **source** slot for that destination.
  List<int>? _enderSlots(HallEnder value) => switch (value) {
    HallEnder.none => const [0, 1, 2, 3],
    // Our `turn_as_couples` applied to the line: a rigid couple wheel, so
    // handedness is preserved and the swap alone re-normalizes for the
    // reversed direction.
    HallEnder.turnCouple => const [1, 0, 3, 2],
    // Slots preserved, facing reversed - which necessarily leaves the line
    // inverted. That is physically correct and must not be normalized away.
    HallEnder.turnAlone => const [0, 1, 2, 3],
    HallEnder.slidingDoors => const [2, 3, 0, 1],
    _ => null,
  };

  /// Whether the ender reverses the line's facing.
  bool _reversesFacing(HallEnder value) =>
      value == HallEnder.turnCouple ||
      value == HallEnder.turnAlone ||
      value == HallEnder.slidingDoors;

  /// The columns backing slots `s0..s3`.
  static const List<int> _slotColumns = [
    0,
    1,
    kColumnCount - 2,
    kColumnCount - 1,
  ];

  /// Reads the four dancers of the line in [row], or `null` if it is not one.
  List<DancerId>? _slotsOf(Formation formation, int row) {
    final ids = <DancerId>[];
    for (final col in _slotColumns) {
      final id = formation.dancerAt(Position(row, col));
      if (id == null) return null;
      ids.add(id);
    }
    return ids;
  }

  /// Folds the line into a ring: **ends** to the row toward travel, **centers**
  /// to the other row, each dancer keeping their side of the set.
  ///
  /// The canonical across-in ring falls out as a *consequence* rather than
  /// being imposed — the ends keep their outer columns and the centers move to
  /// the outer columns of the other row, which already satisfies across
  /// normalization.
  Map<DancerId, DancerState> _closeTheRing(
    Formation formation,
    Band band,
    List<DancerId> slots,
  ) {
    final endRow = travel == Facing.down ? band.bottomRow : band.topRow;
    final centerRow = endRow == band.topRow ? band.bottomRow : band.topRow;
    const west = 0;
    const east = kColumnCount - 1;

    final landings = <DancerId, Position>{
      slots[0]: Position(endRow, west),
      slots[1]: Position(centerRow, west),
      slots[2]: Position(centerRow, east),
      slots[3]: Position(endRow, east),
    };
    return {
      for (final entry in landings.entries)
        entry.key: formation
            .stateOf(entry.key)
            .copyWith(
              position: entry.value,
              facing: acrossFacingInto(entry.value.col),
            ),
    };
  }

  /// Warns when an existing line of four is already facing the other way.
  ///
  /// A band standing as a line of four has a settled facing along the hall; if
  /// it disagrees with the facing this figure travels in, the line turns
  /// around on the spot before it moves. Facing wins mechanically — that is
  /// what [perform] does — but the turn is uncalled movement, so it is
  /// reported. It usually means the figure list is missing a turn, or names
  /// the wrong hall direction.
  ///
  /// Compared against [_travelEndFacing] rather than [travel], because a
  /// `facing: backward` figure *wants* the line facing against its travel.
  ///
  /// Only *existing* lines are considered. A band standing across the set is
  /// gathered into a line by phase 1 and has no travel facing to conflict
  /// with, which is the ordinary case. A dancer whose facing is flexible has
  /// nothing to disagree with either.
  @override
  Iterable<Warning> lint(Formation formation) {
    for (final band in handsFourBands(formation)) {
      final row = lineOfFourRow(formation, band);
      if (row == null) continue;
      for (final id in formation.dancersInRow(row)) {
        final facing = formation.stateOf(id).facing;
        if (facing != _travelEndFacing.reversed) continue;
        return [
          Warning(
            WarningKind.hallFacingConflict,
            detail:
                '$name was called on a line of four already facing '
                '${facing.label}; the line turns around before travelling',
          ),
        ];
      }
    }
    return const [];
  }

  @override
  Result<Formation, OpError> perform(Formation formation) {
    // Phase 1 - gather. `swing where:sides` verbatim. It is self-limiting: a
    // band already standing as a line has no side column holding two dancers,
    // so the swing leaves it alone and the conditionality falls out.
    final gathered = Swing(
      who: WhoSet.everyone,
      face: _gatherFace,
    ).apply(formation);
    if (gathered case Err(:final error)) return Err(error);
    final lined = (gathered as Ok<Formation, OpError>).value;

    // Phase 2 - travel. Identity.

    // Phase 3 - ender.
    final endFacing = _reversesFacing(ender)
        ? _travelEndFacing.reversed
        : _travelEndFacing;
    final permutation = _enderSlots(ender);

    final changes = <DancerId, DancerState>{};
    for (final band in handsFourBands(lined)) {
      final row = lineOfFourRow(lined, band);
      if (row == null) continue;
      final slots = _slotsOf(lined, row);
      if (slots == null) continue;

      if (ender.closesTheRing) {
        changes.addAll(_closeTheRing(lined, band, slots));
        continue;
      }

      final destinationRow = lineRowFor(band, endFacing) ?? row;
      for (var slot = 0; slot < _slotColumns.length; slot++) {
        final id = slots[permutation![slot]];
        changes[id] = lined
            .stateOf(id)
            .copyWith(
              position: Position(destinationRow, _slotColumns[slot]),
              facing: endFacing,
            );
      }
    }
    return Ok(lined.withUpdates(changes));
  }

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is HallFigure &&
      other.who == who &&
      other.moving == moving &&
      other.facing == facing &&
      other.ender == ender;

  @override
  int get hashCode => Object.hash(name, who, moving, facing, ender);

  @override
  String toString() => '$name(${facing.key}, ender: ${ender.key})';
}

/// `down_the_hall` — the line travels **down** the hall.
final class DownTheHall extends HallFigure {
  const DownTheHall({
    super.who = WhoSet.everyone,
    super.moving = HallMoving.all,
    super.facing = HallFacing.forward,
    super.ender = HallEnder.turnCouple,
  });

  @override
  String get name => 'down_the_hall';

  @override
  Facing get travel => Facing.down;
}

/// `up_the_hall` — the line travels **up** the hall.
///
/// Mechanically identical to [DownTheHall] in every respect; only the travel
/// direction and the default [HallEnder] differ.
final class UpTheHall extends HallFigure {
  const UpTheHall({
    super.who = WhoSet.everyone,
    super.moving = HallMoving.all,
    super.facing = HallFacing.forward,
    super.ender = HallEnder.circle,
  });

  @override
  String get name => 'up_the_hall';

  @override
  Facing get travel => Facing.up;
}
