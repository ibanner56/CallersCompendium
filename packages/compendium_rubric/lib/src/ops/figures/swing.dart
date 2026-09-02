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
    for (final band in handsFourBands(formation)) {
      for (final pair in _columnPairs(formation, band)) {
        if (!whoMatches(formation, pair.top, pair.bottom, who)) {
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

  /// The across facing a dancer in [col] takes to satisfy [face].
  Facing _acrossFacingFor(int col) {
    final inward = col == 0 ? Facing.acrossEast : Facing.acrossWest;
    return face == FaceDirection.towardSet ? inward : inward.reversed;
  }

  @override
  Result<Formation, OpError> perform(Formation formation) {
    final changes = <DancerId, DancerState>{};
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
