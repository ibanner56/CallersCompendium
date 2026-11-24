part of '../operation.dart';

/// `swing` — two dancers turn around each other and finish as a **normalized
/// couple** (`docs/taxonomy.md`).
///
/// A swing is a *normalizing* figure: the finishing placement is
/// lark-left / robin-right relative to [face], and the pair's own starting
/// arrangement is discarded. Placement is set by `where` × `face`; [who] only
/// **validates** the pairing.
///
/// Only `where: sides` is implemented. It is the case both golden fixtures use,
/// and the one the taxonomy marks *verified*; `where: center` is partly
/// deferred in the spec itself (its not-aligned branch is explicitly
/// incomplete) and raises [ErrorKind.unsupportedParam] rather than guessing.
/// The one exception is "Ones swing" / "Twos swing", the centre swing's
/// aligned case, which the import writes as `where: sides`; see
/// [_ownRowSwing].
final class Swing extends Operation {
  const Swing({
    required this.who,
    this.where = SwingWhere.sides,
    this.face = FaceDirection.towardSet,
    this.prefix = 'none',
  });

  /// The relationship the swinging pairs must stand in. A **precondition**:
  /// the figure swings whoever is physically in position, and this validates
  /// that they are the dancers the caller named.
  final WhoSet who;

  /// Where the swing resolves. Only [SwingWhere.sides] is supported.
  final SwingWhere where;

  /// The finishing facing. Accepts the `endFacing` synonym on input.
  final FaceDirection face;

  /// An optional lead-in (`none` / `balance` / `meltdown`). No end-state
  /// effect — it only changes how long the figure takes.
  final String prefix;

  @override
  String get name => 'swing';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  /// The pairs that actually swing: the dancers standing in each side column.
  ///
  /// Note this is *positional*, not derived from [who]. The taxonomy is
  /// explicit that a swing pairs whoever is physically on each side.
  List<({int col, DancerId top, DancerId bottom})> _columnPairs(
    Formation formation,
    ({int topRow, int bottomRow}) band,
  ) {
    final pairs = <({int col, DancerId top, DancerId bottom})>[];
    for (final col in [0, kColumnCount - 1]) {
      final top = formation.dancerAt(Position(band.topRow, col));
      final bottom = formation.dancerAt(Position(band.bottomRow, col));
      if (top == null || bottom == null) continue;
      pairs.add((col: col, top: top, bottom: bottom));
    }
    return pairs;
  }

  @override
  OpError? checkPreconditions(Formation formation) {
    if (where != SwingWhere.sides) {
      return const OpError(
        ErrorKind.unsupportedParam,
        'swing supports where:sides only; where:center is deferred',
      );
    }
    if (_couplesInTheirRows(formation) != null) {
      if (face == FaceDirection.awayFromSet) {
        return OpError(
          ErrorKind.unsupportedParam,
          'the ${who.key} swing in their own row; face:out there is deferred',
        );
      }
      return null;
    }
    for (final band in handsFourBands(formation)) {
      for (final pair in _columnPairs(formation, band)) {
        if (!whoMatches(formation, pair.top, pair.bottom, who) &&
            !_endCoupleAlone(formation, band, pair.top, pair.bottom)) {
          return OpError(
            ErrorKind.whoMismatch,
            '${pair.top} and ${pair.bottom} are in swing position in column '
            '${pair.col} but are not ${who.key}',
          );
        }
      }
    }
    return null;
  }

  /// Whether [a] and [b] are an end couple with no one at [who]'s distance:
  /// partners standing in swing position in the hands four at an end of the
  /// set, travelling off that end, when the swing names a distance set
  /// (`nextNeighbors`, …). They swing each other *(user-ruled 2026-11-24:
  /// "they swing each other, basically")*. A couple at an end travelling
  /// into the set still has neighbours ahead of it and is not let through.
  /// Applying this to every distance set, and to `swing` alone, is the
  /// agent's call; every couple further in still has to match [who].
  bool _endCoupleAlone(
    Formation formation,
    ({int topRow, int bottomRow}) band,
    DancerId a,
    DancerId b,
  ) {
    if (a.coupleIndex != b.coupleIndex) return false;
    if (!who.isCrossHandsFour) return false;
    final bands = handsFourBands(formation);
    final travel = travelDirection(formation, a);
    return (band == bands.first && travel < 0) ||
        (band == bands.last && travel > 0);
  }

  /// The across facing a dancer in [col] takes to satisfy [face].
  Facing _acrossFacingFor(int col) {
    final inward = col == 0 ? Facing.acrossEast : Facing.acrossWest;
    return face == FaceDirection.towardSet ? inward : inward.reversed;
  }

  /// "Ones swing" / "Twos swing": the couple named, standing across the set
  /// from each other in one row of every hands four, swing there, in that
  /// row, and finish facing the other couple — which after a progression may
  /// be a new one. The ones face **down** the hall toward the twos, the twos
  /// face **up** toward the ones. *(User-ruled 2026-11-23, ones and twos
  /// separately.)*
  ///
  /// This is the taxonomy's `where: center` aligned case, which the import
  /// never names: Caller's Box writes "Ones swing" and the record carries
  /// only `who: ones`. A stated `face: up` or `down` is honoured; the default
  /// `in` has no meaning for a couple standing along the hall, so it takes the
  /// ruled facing. `face: out` is deferred ([checkPreconditions] refuses it).
  Map<DancerId, DancerState>? _ownRowSwing(Formation formation) {
    if (face == FaceDirection.awayFromSet) return null;
    final rows = _couplesInTheirRows(formation);
    if (rows == null) return null;
    final facing = switch (face) {
      FaceDirection.up => Facing.up,
      FaceDirection.down => Facing.down,
      _ => who == WhoSet.twos ? Facing.up : Facing.down,
    };
    final changes = <DancerId, DancerState>{};
    for (final couple in rows) {
      final placement = normalizeAlongHall(row: couple.row, facing: facing);
      changes[couple.lark] = formation
          .stateOf(couple.lark)
          .copyWith(position: placement.lark, facing: facing);
      changes[couple.robin] = formation
          .stateOf(couple.robin)
          .copyWith(position: placement.robin, facing: facing);
    }
    return changes;
  }

  /// The row each active hands four's [who] couple stands in, when [who] is
  /// `ones` or `twos` and every such hands four has them alone in one row, a
  /// lark and a robin on opposite side lines; otherwise `null`, leaving the
  /// side-column swing to run.
  ///
  /// A band with the couple in both rows, or a row shared with other dancers
  /// (a line of four), does not qualify. A couple standing out is outside every
  /// band and does not swing (§10.3.2).
  List<({int row, DancerId lark, DancerId robin})>? _couplesInTheirRows(
    Formation formation,
  ) {
    if (who != WhoSet.ones && who != WhoSet.twos) return null;
    final bands = handsFourBands(formation);
    if (bands.isEmpty) return null;
    final found = <({int row, DancerId lark, DancerId robin})>[];
    for (final band in bands) {
      final rows = <({int row, DancerId lark, DancerId robin})>[];
      for (final row in [band.topRow, band.bottomRow]) {
        final west = formation.dancerAt(Position(row, 0));
        final east = formation.dancerAt(Position(row, kColumnCount - 1));
        if (west == null || east == null) continue;
        if (west.role == east.role) continue;
        if (formation.dancersInRow(row).length != 2) continue;
        if (!whoMatches(formation, west, east, who)) continue;
        final lark = west.role == Role.lark ? west : east;
        rows.add((row: row, lark: lark, robin: lark == west ? east : west));
      }
      if (rows.length != 1) return null;
      found.add(rows.single);
    }
    return found;
  }

  @override
  Result<Formation, OpError> perform(Formation formation) {
    final ownRow = _ownRowSwing(formation);
    if (ownRow != null) return Ok(formation.withUpdates(ownRow));
    final changes = <DancerId, DancerState>{..._waitingCouplesSwing(formation)};
    for (final band in handsFourBands(formation)) {
      for (final pair in _columnPairs(formation, band)) {
        final members = [pair.top, pair.bottom];
        final larkId = members.firstWhere(
          (id) => id.role == Role.lark,
          orElse: () => members.first,
        );
        final robinId = members.firstWhere((id) => id != larkId);

        final placement = face.isAlongHall
            ? _lineOfFourPlacement(band: band, col: pair.col)
            : _sidePlacement(band: band, col: pair.col);
        final facing = face.isAlongHall
            ? (face == FaceDirection.down ? Facing.down : Facing.up)
            : _acrossFacingFor(pair.col);

        changes[larkId] = formation
            .stateOf(larkId)
            .copyWith(position: placement.lark, facing: facing);
        changes[robinId] = formation
            .stateOf(robinId)
            .copyWith(position: placement.robin, facing: facing);
      }
    }
    return Ok(formation.withUpdates(changes));
  }

  /// The couples waiting out at an end of the set when the swing names the
  /// previous neighbours (N0): each has no N0 there, so the partners swing each
  /// other and normalize facing into the set, which swaps their sides
  /// *(user-ruled 2026-11-24, Haven't We Met Before?: "couple waiting out at
  /// the top after N0 balance+swing should still swing and normalize (swap
  /// places)")*.
  ///
  /// Only a whole couple standing alone across its end row, both waiting out
  /// in the grouping the swing is danced in (`FigureFold` may dance it one
  /// band phase over), is moved. Limiting it to `prevNeighbors` is the maintainer's choice
  /// ("go with option A for now"): read for every distance set it compiled
  /// eight more Caller's Box dances and lost four. A stated `face` is not
  /// applied to them.
  Map<DancerId, DancerState> _waitingCouplesSwing(Formation formation) {
    if (who != WhoSet.prevNeighbors) return const {};
    final changes = <DancerId, DancerState>{};
    for (final row in {0, formation.rowCount - 1}) {
      final ids = formation.dancersInRow(row).toList();
      if (ids.length != 2 || ids[0].coupleIndex != ids[1].coupleIndex) {
        continue;
      }
      if (ids.any((id) => !formation.stateOf(id).waitingOut)) continue;
      final facing = row == 0 ? Facing.down : Facing.up;
      final normal = normalizeAlongHall(row: row, facing: facing);
      for (final id in ids) {
        changes[id] = formation
            .stateOf(id)
            .copyWith(
              position: id.role == Role.lark ? normal.lark : normal.robin,
              facing: facing,
            );
      }
    }
    return changes;
  }

  /// `face: in` / `face: out` — the pair stays stacked in its own column.
  CouplePlacement _sidePlacement({
    required ({int topRow, int bottomRow}) band,
    required int col,
  }) => normalizeAcross(
    col: col,
    topRow: band.topRow,
    facing: _acrossFacingFor(col),
  );

  /// `face: up` / `face: down` — the two column pairs collapse into a **line of
  /// four** in a single row (`docs/fundamentals.md` §8.1).
  ///
  /// The west pair fills `{c0,c1}` and the east pair `{c3,c4}`, leaving the
  /// centre column empty. Facing down puts the line in the band's **top** row
  /// and facing up in its **bottom** row, matching the taxonomy's worked
  /// examples. Within a segment the lark stands on the dancers' left: facing
  /// down that is the higher column, facing up the lower.
  CouplePlacement _lineOfFourPlacement({
    required ({int topRow, int bottomRow}) band,
    required int col,
  }) {
    final row = face == FaceDirection.down ? band.topRow : band.bottomRow;
    final lowCol = col == 0 ? 0 : kColumnCount - 2;
    final highCol = lowCol + 1;
    final larkCol = face == FaceDirection.down ? highCol : lowCol;
    final robinCol = face == FaceDirection.down ? lowCol : highCol;
    return (lark: Position(row, larkCol), robin: Position(row, robinCol));
  }

  @override
  bool operator ==(Object other) =>
      other is Swing &&
      other.who == who &&
      other.where == where &&
      other.face == face &&
      other.prefix == prefix;

  @override
  int get hashCode => Object.hash(name, who, where, face, prefix);

  @override
  String toString() => 'swing(${who.key}, ${where.key}, ${face.key})';
}
