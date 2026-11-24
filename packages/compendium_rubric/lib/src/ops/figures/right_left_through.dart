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
/// `dir: across` trades within each hands four; the diagonals trade with the
/// next hands four along ([_diagonalPlan]). `along` is deferred and raises
/// [ErrorKind.unsupportedParam].
final class RightLeftThrough extends Operation {
  const RightLeftThrough({this.dir = 'across'});

  /// The direction of the trade: `across`, `leftDiagonal` or `rightDiagonal`.
  final String dir;

  @override
  String get name => 'right_left_through';

  bool get _isDiagonal => dir == 'leftDiagonal' || dir == 'rightDiagonal';

  /// A diagonal reaches one hands four further, as a diagonal chain does.
  @override
  int get hands4Contribution => _isDiagonal ? 1 : 0;

  @override
  bool get progressionEligible => true;

  /// A diagonal trade **is** a Becket progression: every traded couple has
  /// already moved on to the next couple, so a progression flag on it names
  /// movement the figure has made rather than asking for more, as it does for
  /// `slide_along_set`.
  @override
  bool get isItsOwnProgression => _isDiagonal;

  /// A flagged diagonal trade spends **two** progressions: each traded couple
  /// ends facing the couple two hands fours from where it started, as after
  /// two slides. *(Agent's call, 2026-11-24, after the user-ruled diagonal
  /// `slice`: "diagonal is double".)* It is still danced as one step; only the
  /// count that distance-named figures read advances by two.
  ///
  /// That is the count for a trade that carries couples **forward**, the way
  /// the formation progresses (Becket CW `leftDiagonal`, CCW `rightDiagonal`),
  /// which is every flagged diagonal in the corpus measured. A flagged trade
  /// the other way would carry them back, and is counted the same: deferred,
  /// with no dance to check it against.
  @override
  int get progressionsSpent => _isDiagonal ? 2 : 1;

  @override
  OpError? checkPreconditions(Formation formation) {
    if (_isDiagonal) return _diagonalPlan(formation).errorOrNull;
    if (dir != 'across') {
      return OpError(
        ErrorKind.unsupportedParam,
        'right_left_through supports dir:across and the diagonals; dir:$dir '
        'is deferred',
      );
    }
    return null;
  }

  @override
  Result<Formation, OpError> perform(Formation formation) {
    if (!_isDiagonal) return Ok(_tradeDiagonallyFacingIn(formation));
    return switch (_diagonalPlan(formation)) {
      Ok(:final value) => Ok(formation.withUpdates(value)),
      Err(:final error) => Err(error),
    };
  }

  /// Where a diagonal right and left through puts everyone.
  ///
  /// The couple standing on the west line (c0) of each grouping trades places
  /// with the couple on the east line (c4) of the grouping above, for
  /// `leftDiagonal`, or below, for `rightDiagonal` — the groupings a diagonal
  /// chain pairs. Each couple crosses as a unit and courtesy-turns, a rigid
  /// wheel, so whoever crossed in the top row lands in the bottom one, as the
  /// across trade does, and both face back into the set. *(Agent's call,
  /// 2026-11-24, pairing by line as the user-ruled diagonal chain does.)*
  ///
  /// A couple with no grouping on its diagonal, at an end of the set, stays
  /// where it is and comes back in as the other of its own number, facing in
  /// (see below; fundamentals §10.2.2, the diagonal-trade exception). A set
  /// with couples already waiting out is refused as deferred: which line a
  /// waiting couple would trade from is unruled.
  Result<Map<DancerId, DancerState>, OpError> _diagonalPlan(
    Formation formation,
  ) {
    final groupings = groupingsDownTheSet(formation);
    if (groupings.any((g) => g.isWaiting)) {
      return Err(
        OpError(
          ErrorKind.unsupportedParam,
          'right_left_through dir:$dir with couples waiting out at the ends '
          'is deferred',
        ),
      );
    }
    final changes = <DancerId, DancerState>{};
    List<DancerId>? lineOf(Grouping g, int col) {
      final top = formation.dancerAt(Position(g.rows.first, col));
      final bottom = formation.dancerAt(Position(g.rows.last, col));
      if (top == null || bottom == null) return null;
      return [top, bottom];
    }

    for (var i = 0; i < groupings.length; i++) {
      final target = dir == 'leftDiagonal' ? i - 1 : i + 1;
      if (target < 0 || target >= groupings.length) continue;
      final west = lineOf(groupings[i], 0);
      final east = lineOf(groupings[target], kColumnCount - 1);
      if (west == null || east == null) {
        return Err(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'right_left_through dir:$dir trades a couple on each side line, '
            'but rows ${groupings[i].rows} or ${groupings[target].rows} have '
            'no couple standing on the line it crosses from',
          ),
        );
      }
      void land(List<DancerId> couple, Grouping to, int col) {
        // The wheel turns the couple end for end: top lands bottom.
        final rows = [to.rows.last, to.rows.first];
        for (var k = 0; k < 2; k++) {
          changes[couple[k]] = formation
              .stateOf(couple[k])
              .copyWith(
                position: Position(rows[k], col),
                facing: col == 0 ? Facing.acrossEast : Facing.acrossWest,
              );
        }
      }

      land(west, groupings[target], kColumnCount - 1);
      land(east, groupings[i], 0);
    }

    // The couple left at each end with no one on its diagonal has, for that
    // moment, stood out at the end. Everyone else in its hands four has
    // traded lines around it, so it comes back in as the other of its own
    // number, facing into the set, and its hands four again holds one #1 and
    // one #2 couple (fundamentals §10.2.2, the diagonal-trade exception).
    // This happens flagged or not: the trade moves the couples either way.
    // *(Agent's call, 2026-11-24.)* A line that is not one couple keeps its
    // numbers, as an end row that is not one couple does (§10.2.1).
    for (final (index, col) in [
      (0, dir == 'leftDiagonal' ? 0 : kColumnCount - 1),
      (groupings.length - 1, dir == 'leftDiagonal' ? kColumnCount - 1 : 0),
    ]) {
      if (groupings.isEmpty) break;
      final grouping = groupings[index];
      final line = lineOf(grouping, col);
      if (line == null || changes.containsKey(line.first)) continue;
      if (line[0].coupleIndex != line[1].coupleIndex) continue;
      for (final id in line) {
        final state = formation.stateOf(id);
        changes[id] = state.copyWith(
          number: state.number.flipped,
          facing: col == 0 ? Facing.acrossEast : Facing.acrossWest,
        );
      }
    }
    return Ok(changes);
  }

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
