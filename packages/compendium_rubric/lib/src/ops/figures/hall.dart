part of '../operation.dart';

/// Which part of the line travels.
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
/// For the whole hands four, travel is positionally inert, so this parameter's
/// whole job is to set the **ending facing** — and, through it, the row the
/// line normalizes into. A lead by part of the set takes only `forward`.
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
/// **For the whole hands four, travel is positionally inert.** Going down the
/// hall is not a matrix transformation; it is a movement of the entire matrix,
/// and so produces no displacement. Every real state change here comes from the
/// two phases either side of it — the **gather** that forms the line and the
/// **ender** that reshapes it. A lead by part of the set is different: it
/// displaces dancers and never gathers (see [_leadPlan]).
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
    this.returnLeg,
    this.isReturnLeg = false,
  });

  /// The lead back that immediately follows this lead out, when the two are
  /// danced as one round trip (see [pairedWith]). `null` otherwise.
  final HallFigure? returnLeg;

  /// Whether this is the lead back of a round trip, whose movement the lead
  /// out already danced (see [pairedWith]).
  final bool isReturnLeg;

  /// This figure with [returnLeg] as its lead back, or marked as a lead back
  /// when [isReturnLeg]; the other parameters are copied unchanged.
  HallFigure _withLegs({HallFigure? returnLeg, bool isReturnLeg = false});

  /// Whether [out] and [back] are a lead out immediately followed by a lead
  /// back: the same leaders, led by part of the set, travelling opposite ways,
  /// each leg with parameters a round trip takes.
  ///
  /// A leg whose own `moving`, `facing` or `ender` a round trip does not take
  /// is left unpaired, so it is refused at its own line rather than at its
  /// partner's.
  static bool areRoundTrip(Operation out, Operation back) =>
      out is HallFigure &&
      back is HallFigure &&
      out._ledByPart &&
      back._ledByPart &&
      out.returnLeg == null &&
      !out.isReturnLeg &&
      back.returnLeg == null &&
      !back.isReturnLeg &&
      out.who == back.who &&
      out.travel != back.travel &&
      out._roundTripLegError(out.name) == null &&
      back._roundTripLegError(back.name) == null;

  /// Why this leg's own parameters are outside what a round trip takes, or
  /// `null` (see [_roundTripLeaders]).
  OpError? _roundTripLegError(String label) {
    if (moving == HallMoving.all) {
      return OpError(
        ErrorKind.unsupportedParam,
        '$label: $name moving:all is deferred: part of the set leads, so it '
        'travels down the center or the outsides',
      );
    }
    if (facing != HallFacing.forward) {
      return OpError(
        ErrorKind.unsupportedParam,
        '$label: $name facing:${facing.key} is deferred',
      );
    }
    if (ender != HallEnder.none &&
        ender != HallEnder.turnAlone &&
        ender != HallEnder.turnCouple) {
      return OpError(
        ErrorKind.unsupportedParam,
        '$label: $name ender:${ender.key} is deferred',
      );
    }
    return null;
  }

  /// The lead out of a round trip whose lead back is [back].
  ///
  /// **User-ruled (2026-11-23):** a lead down immediately followed by a lead
  /// back up (or the reverse) does not move the other dancers. They stay in
  /// place, and the leaders return to where they started, or to their
  /// partner's place if the leaders traded on the way. The lead out dances the
  /// whole round trip; the lead back ([asReturnLeg]) then moves nobody. Both
  /// keep their own line in the dance, so diagnostics still point at the
  /// figure the record names.
  HallFigure pairedWith(HallFigure back) => _withLegs(returnLeg: back);

  /// This figure as the lead back of a round trip (see [pairedWith]).
  HallFigure get asReturnLeg => _withLegs(isReturnLeg: true);

  /// Which dancers travel: the whole hands four, or leaders named by
  /// membership (see [_leadPlan]).
  final WhoSet who;

  /// Which part of the line travels. For the whole hands four only
  /// [HallMoving.all] is implemented; a partial lead takes `center` or
  /// `outsides`.
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

  /// A partial lead moves dancers along the set, as [Cast] does, and is
  /// eligible as [Cast] is; the line of four is inert and is not.
  @override
  bool get progressionEligible => _ledByPart;

  /// The facing the line finishes the *travel* on, before any ender.
  Facing get _travelEndFacing =>
      facing == HallFacing.backward ? travel.reversed : travel;

  /// The [FaceDirection] the gather normalizes against.
  FaceDirection get _gatherFace =>
      _travelEndFacing == Facing.down ? FaceDirection.down : FaceDirection.up;

  /// Whether part of the set leads, rather than the whole hands four.
  bool get _ledByPart => who != WhoSet.everyone;

  /// The leaders and the dancers they pass, for a figure [_ledByPart].
  ///
  /// **User-ruled (2026-11-23):** "ones lead down/up" moves the set the way a
  /// [Cast] does: the leaders move along the set and each dancer they pass
  /// steps one place the other way. A hall figure carries no count (the
  /// Caller's Box import drops "past N1;N2"), so the leaders go **one place**, to the other end of their own hands four; that
  /// is the reading the ruling was asked on. That example ("ones lead down,
  /// turn alone, lead up, cast off") now parses as a round trip (see
  /// [pairedWith]); the one-place reading applies to a lead that is not
  /// immediately followed by its lead back, such as "ones lead down, cast up".
  ///
  /// What falls outside these limits is refused as deferred
  /// ([ErrorKind.unsupportedParam]) rather than guessed. The limits are the
  /// agent's call, not ruled, except where marked:
  ///
  /// - `who` must name leaders by membership (`ones`, `twos`, `role1s`,
  ///   `role2s`); a pair relation such as `partners` stays deferred.
  /// - `moving` must be `center` (between the dancers passed) or `outsides`
  ///   (behind them). That both move the set the same way, since on the grid
  ///   they pass the same dancers, is user-ruled (2026-11-23).
  /// - `facing` must be `forward`.
  /// - The ender must be `none` or `turnAlone`. A `turnCouple` ender would
  ///   decide which side of the set each leader ends on, which is a
  ///   choreography question not yet asked; the others reshape a line of four
  ///   that a partial lead does not form.
  Result<List<DancerPair>, OpError> _leadPlan(Formation formation) {
    if (!_passerMemberships.contains(who)) {
      return Err(
        OpError(
          ErrorKind.unsupportedParam,
          '$name led by ${who.key} is deferred: only the whole hands four, or '
          'leaders named by membership (ones, twos, role1s, role2s), is built',
        ),
      );
    }
    if (moving == HallMoving.all) {
      return Err(
        OpError(
          ErrorKind.unsupportedParam,
          '$name who:${who.key} moving:all is deferred: part of the set '
          'leads, so it travels down the center or the outsides',
        ),
      );
    }
    if (facing != HallFacing.forward) {
      return Err(
        OpError(
          ErrorKind.unsupportedParam,
          '$name who:${who.key} facing:${facing.key} is deferred',
        ),
      );
    }
    if (ender != HallEnder.none && ender != HallEnder.turnAlone) {
      return Err(
        OpError(
          ErrorKind.unsupportedParam,
          '$name who:${who.key} ender:${ender.key} is deferred',
        ),
      );
    }
    for (final band in handsFourBands(formation)) {
      if (lineOfFourRow(formation, band) == null) continue;
      return Err(
        OpError(
          ErrorKind.unresolvableDancerSet,
          '$name who:${who.key} needs the hands four standing in its two '
          'rows, but rows ${band.topRow}/${band.bottomRow} stand as a line '
          'of four',
        ),
      );
    }
    return _onePlacePasses(
      formation,
      who,
      step: travel == Facing.down ? 1 : -1,
      figure: name,
      label: '$name who:${who.key}',
      passer: 'pass',
    );
  }

  /// Moves the leaders one place and steps the passed dancers back one.
  ///
  /// Leaders finish facing the way they travelled, or the other way after a
  /// `turnAlone`. The dancers passed end with flexible facing, as in [Cast]:
  /// they step along to make room.
  Result<Formation, OpError> _performLead(Formation formation) =>
      _leadPlan(formation).map((pairs) {
        final leaderFacing = ender == HallEnder.turnAlone
            ? travel.reversed
            : travel;
        // A leader is the one whose destination lies along its travel.
        final leaderDestinations = {
          for (final pair in pairs) formation.stateOf(pair.b).position,
        };
        return swapPairs(
          formation,
          pairs,
          facing: (before, after, other) => leaderDestinations.contains(after)
              ? leaderFacing
              : Facing.flexible,
        );
      });

  /// Whether a round trip trades the leaders: each `turnCouple` ender wheels
  /// the couple, so an odd number of them leaves each leader on the side their
  /// partner started on.
  bool _roundTripTrades(HallFigure back) =>
      [ender, back.ender].where((e) => e == HallEnder.turnCouple).length.isOdd;

  /// The leaders of a round trip, checked against what the ruling covers.
  ///
  /// Refused as deferred ([ErrorKind.unsupportedParam]) rather than guessed,
  /// each the agent's call: leaders not named by membership; `moving: all`;
  /// `facing` other than `forward`; an ender other than `none`, `turnAlone`
  /// or `turnCouple`; a trade led by a role set, which names no couple to
  /// trade. A trade whose leader has no leading partner in its hands four is
  /// [ErrorKind.unresolvableDancerSet].
  Result<List<DancerId>, OpError> _roundTripLeaders(
    Formation formation,
    HallFigure back,
  ) {
    final label = '$name then ${back.name} who:${who.key}';
    if (!_passerMemberships.contains(who)) {
      return Err(
        OpError(
          ErrorKind.unsupportedParam,
          '$label is deferred: only leaders named by membership (ones, twos, '
          'role1s, role2s) are built',
        ),
      );
    }
    for (final leg in [this, back]) {
      if (leg._roundTripLegError(label) case final error?) return Err(error);
    }
    final trades = _roundTripTrades(back);
    if (trades && who != WhoSet.ones && who != WhoSet.twos) {
      return Err(
        OpError(
          ErrorKind.unsupportedParam,
          '$label trades the leaders with a turnCouple, but ${who.key} names '
          'no couple to trade; deferred',
        ),
      );
    }
    final leaders = <DancerId>[];
    for (final band in handsFourBands(formation)) {
      if (lineOfFourRow(formation, band) != null) {
        return Err(
          OpError(
            ErrorKind.unresolvableDancerSet,
            '$label needs the hands four standing in its two rows, but rows '
            '${band.topRow}/${band.bottomRow} stand as a line of four',
          ),
        );
      }
      final inBand = [
        ...formation.dancersInRow(band.topRow),
        ...formation.dancersInRow(band.bottomRow),
      ];
      final bandLeaders = [
        for (final id in inBand)
          if (whoIncludes(formation, id, who)) id,
      ];
      if (trades) {
        for (final id in bandLeaders) {
          final partner = bandLeaders.where(
            (other) => other != id && other.coupleIndex == id.coupleIndex,
          );
          if (partner.length != 1) {
            return Err(
              OpError(
                ErrorKind.unresolvableDancerSet,
                '$label trades the leaders with a turnCouple, but $id has no '
                'leading partner in the hands four at rows '
                '${band.topRow}-${band.bottomRow}',
              ),
            );
          }
        }
      }
      leaders.addAll(bandLeaders);
    }
    if (leaders.isEmpty) {
      return Err(
        OpError(
          ErrorKind.unresolvableDancerSet,
          '$label: no ${who.key} stands in an active hands four',
        ),
      );
    }
    return Ok(leaders);
  }

  /// Dances a lead out and its lead [back] as one round trip: nobody else
  /// moves, and the leaders end where they started, or traded with their
  /// partner (see [pairedWith]).
  ///
  /// Leaders finish facing the way the lead back travelled, reversed when it
  /// ended with a turn *(agent's call: the facing is the lead back's own)*.
  Result<Formation, OpError> _performRoundTrip(
    Formation formation,
    HallFigure back,
  ) => _roundTripLeaders(formation, back).map((leaders) {
    final turned =
        back.ender == HallEnder.turnAlone || back.ender == HallEnder.turnCouple;
    final facing = turned ? back.travel.reversed : back.travel;
    final trades = _roundTripTrades(back);
    final changes = <DancerId, DancerState>{};
    for (final id in leaders) {
      var position = formation.stateOf(id).position;
      if (trades) {
        final partner = leaders.firstWhere(
          (other) => other != id && other.coupleIndex == id.coupleIndex,
        );
        position = formation.stateOf(partner).position;
      }
      changes[id] = formation
          .stateOf(id)
          .copyWith(position: position, facing: facing);
    }
    return formation.withUpdates(changes);
  });

  @override
  OpError? checkPreconditions(Formation formation) {
    if (isReturnLeg) return null;
    if (returnLeg case final back?) {
      return switch (_roundTripLeaders(formation, back)) {
        Ok() => null,
        Err(:final error) => error,
      };
    }
    if (_ledByPart) {
      return switch (_leadPlan(formation)) {
        Ok() => null,
        Err(:final error) => error,
      };
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
    // A partial lead forms no line of four and gathers nobody.
    if (_ledByPart || isReturnLeg) return const [];
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
    if (isReturnLeg) return Ok(formation);
    if (returnLeg case final back?) return _performRoundTrip(formation, back);
    if (_ledByPart) return _performLead(formation);

    // Phase 1 - gather. A couple already facing the other along the hall
    // walks forward into the middle of that couple's row; every other band
    // gathers by `swing where:sides` verbatim. The swing is self-limiting: a
    // band already standing as a line has no side column holding two dancers,
    // so the swing leaves it alone and the conditionality falls out.
    final gathered = Swing(
      who: WhoSet.everyone,
      face: _gatherFace,
    ).apply(_stepIntoLine(formation));
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

  /// The gather for a band in which one couple faces the other along the
  /// hall, as the ones do after swinging in their own row: the facing couple
  /// walks forward into the middle of the other couple's row, each beside the
  /// dancer on their own side, and the line faces [_gatherFace].
  ///
  /// So "Ones swing" then "in a line of four, go down the hall" lines up
  /// twos on the ends and ones in the middle: from the improper start the
  /// line is `L2-B R1-A . L1-A R2-B` in the twos' row *(user-ruled
  /// 2026-11-23, the maintainer's own grid)*. The same walk applies to the
  /// twos after their own-row swing *(agent's call: the mirror case)*.
  ///
  /// A band qualifies only when one row holds a couple (partners) alone on
  /// the two side lines, both facing the other row and the line's ending
  /// facing ([_gatherFace], which is against the travel for `backward`), and
  /// the other row holds a pair alone on the side lines. The pair's facing
  /// is not checked; walkers whose facing is flexible never qualify. Every
  /// other band is left for the swing gather.
  Formation _stepIntoLine(Formation formation) {
    final changes = <DancerId, DancerState>{};
    final facing = _gatherFace == FaceDirection.down ? Facing.down : Facing.up;
    for (final band in handsFourBands(formation)) {
      for (final (from, to) in [
        (band.topRow, band.bottomRow),
        (band.bottomRow, band.topRow),
      ]) {
        final toward = to > from ? Facing.down : Facing.up;
        // Only the couple already facing the way the line will face walks.
        if (toward != facing) continue;
        final walkers = _sidePair(formation, from);
        final standers = _sidePair(formation, to);
        if (walkers == null || standers == null) continue;
        if (formation.stateOf(walkers.west).facing != toward ||
            formation.stateOf(walkers.east).facing != toward) {
          continue;
        }
        if (!whoMatches(
          formation,
          walkers.west,
          walkers.east,
          WhoSet.partners,
        )) {
          continue;
        }
        changes[walkers.west] = formation
            .stateOf(walkers.west)
            .copyWith(position: Position(to, 1), facing: facing);
        changes[walkers.east] = formation
            .stateOf(walkers.east)
            .copyWith(position: Position(to, kColumnCount - 2), facing: facing);
        for (final id in [standers.west, standers.east]) {
          changes[id] = formation.stateOf(id).copyWith(facing: facing);
        }
        break;
      }
    }
    return changes.isEmpty ? formation : formation.withUpdates(changes);
  }

  /// The two dancers alone in [row], one on each side line, or `null`.
  static ({DancerId west, DancerId east})? _sidePair(
    Formation formation,
    int row,
  ) {
    if (formation.dancersInRow(row).length != 2) return null;
    final west = formation.dancerAt(Position(row, 0));
    final east = formation.dancerAt(Position(row, kColumnCount - 1));
    if (west == null || east == null) return null;
    return (west: west, east: east);
  }

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is HallFigure &&
      other.who == who &&
      other.moving == moving &&
      other.facing == facing &&
      other.ender == ender &&
      other.returnLeg == returnLeg &&
      other.isReturnLeg == isReturnLeg;

  @override
  int get hashCode =>
      Object.hash(name, who, moving, facing, ender, returnLeg, isReturnLeg);

  @override
  String toString() {
    final base = _ledByPart
        ? '$name(${who.key}, ${moving.key}, ${facing.key}, ender: ${ender.key})'
        : '$name(${facing.key}, ender: ${ender.key})';
    if (isReturnLeg) return '$base [lead back]';
    if (returnLeg != null) return '$base [round trip]';
    return base;
  }
}

/// `down_the_hall` — the line travels **down** the hall.
final class DownTheHall extends HallFigure {
  const DownTheHall({
    super.who = WhoSet.everyone,
    super.moving = HallMoving.all,
    super.facing = HallFacing.forward,
    super.ender = HallEnder.turnCouple,
    super.returnLeg,
    super.isReturnLeg,
  });

  @override
  DownTheHall _withLegs({HallFigure? returnLeg, bool isReturnLeg = false}) =>
      DownTheHall(
        who: who,
        moving: moving,
        facing: facing,
        ender: ender,
        returnLeg: returnLeg,
        isReturnLeg: isReturnLeg,
      );

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
    super.returnLeg,
    super.isReturnLeg,
  });

  @override
  UpTheHall _withLegs({HallFigure? returnLeg, bool isReturnLeg = false}) =>
      UpTheHall(
        who: who,
        moving: moving,
        facing: facing,
        ender: ender,
        returnLeg: returnLeg,
        isReturnLeg: isReturnLeg,
      );

  @override
  String get name => 'up_the_hall';

  @override
  Facing get travel => Facing.up;
}
