import '../domain/couple_number.dart';
import '../domain/dancer.dart';
import '../domain/facing.dart';
import '../domain/formation.dart';
import '../domain/formation_type.dart';
import '../domain/position.dart';
import '../domain/role.dart';

/// The two cells a normalized couple occupies, tagged by role.
typedef CouplePlacement = ({Position lark, Position robin});

/// How a couple is standing relative to the set.
enum CoupleOrientation {
  /// Partners share a row, in different columns — the Duple Improper shape.
  alongHall,

  /// Partners share a column, in adjacent rows — the Becket shape.
  across,

  /// Partners share neither a row nor a column (mid-figure, or an
  /// intentionally scattered state).
  scattered,
}

/// Normalizes a couple standing **along a row**, per `docs/fundamentals.md`
/// §7–§8.
///
/// The Lark takes the side column on their left: facing down that is c4,
/// facing up it is c0. [facing] must be up or down.
CouplePlacement normalizeAlongHall({required int row, required Facing facing}) {
  final larkSide = facing.turnedLeft;
  if (!facing.isAlongHall || !larkSide.isAcross) {
    throw ArgumentError.value(
      facing,
      'facing',
      'along-hall normalization requires an up or down facing',
    );
  }
  final larkCol = larkSide == Facing.acrossEast
      ? Position.eastColumn
      : Position.westColumn;
  final robinCol = larkCol == Position.eastColumn
      ? Position.westColumn
      : Position.eastColumn;
  return (lark: Position(row, larkCol), robin: Position(row, robinCol));
}

/// Normalizes a couple standing **stacked in a column** across the set, per
/// `docs/fundamentals.md` §7–§8.
///
/// The pair occupies [topRow] and `topRow + 1`. The Lark takes the row on
/// their left: facing across-east that is the upper row (toward r0); facing
/// across-west it is the lower row. [facing] must be an across facing.
CouplePlacement normalizeAcross({
  required int col,
  required int topRow,
  required Facing facing,
}) {
  final larkSide = facing.turnedLeft;
  if (!facing.isAcross || !larkSide.isAlongHall) {
    throw ArgumentError.value(
      facing,
      'facing',
      'across normalization requires an across facing',
    );
  }
  final larkRow = larkSide == Facing.up ? topRow : topRow + 1;
  final robinRow = larkRow == topRow ? topRow + 1 : topRow;
  return (lark: Position(larkRow, col), robin: Position(robinRow, col));
}

/// How couple [coupleIndex] is currently standing in [formation].
CoupleOrientation orientationOf(Formation formation, int coupleIndex) {
  final lark = formation.stateOf(DancerId(coupleIndex, Role.lark));
  final robin = formation.stateOf(DancerId(coupleIndex, Role.robin));
  if (lark.row == robin.row) return CoupleOrientation.alongHall;
  if (lark.col == robin.col) return CoupleOrientation.across;
  return CoupleOrientation.scattered;
}

/// A couple's footprint in the matrix, used to read the set from the top down.
typedef CoupleSpan = ({
  int coupleIndex,
  CoupleNumber number,
  int topRow,
  int bottomRow,
});

/// Every couple in [formation], ordered by the topmost row they occupy.
///
/// Ties (two couples starting on the same row, as in Becket) are broken by the
/// couple's westmost column so the ordering is total and deterministic.
List<CoupleSpan> couplesDownTheSet(Formation formation) {
  final byCouple = <int, List<({DancerState state, int col})>>{};
  for (final entry in formation.dancers.entries) {
    byCouple.putIfAbsent(entry.key.coupleIndex, () => []).add((
      state: entry.value,
      col: entry.value.col,
    ));
  }
  final spans = <({CoupleSpan span, int westCol})>[];
  byCouple.forEach((coupleIndex, members) {
    final rows = [for (final m in members) m.state.row]..sort();
    final cols = [for (final m in members) m.col]..sort();
    spans.add((
      span: (
        coupleIndex: coupleIndex,
        number: members.first.state.number,
        topRow: rows.first,
        bottomRow: rows.last,
      ),
      westCol: cols.first,
    ));
  });
  spans.sort((a, b) {
    final byTop = a.span.topRow.compareTo(b.span.topRow);
    if (byTop != 0) return byTop;
    return a.westCol.compareTo(b.westCol);
  });
  return [for (final s in spans) s.span];
}

/// The non-empty rows in which **every** dancer present is waiting out
/// (`docs/fundamentals.md` §10.3).
///
/// A row of dancers who are all standing out is not part of any active hands
/// four. Rows that are merely *empty* are not waiting rows: a line of four
/// (§8.1) leaves the partner row of its band empty, and that band is still
/// very much active.
List<int> waitingOutRows(Formation formation) => [
  for (var row = 0; row < formation.rowCount; row++)
    if (_rowIsEntirelyWaiting(formation, row)) row,
];

bool _rowIsEntirelyWaiting(Formation formation, int row) {
  final occupants = formation.dancersInRow(row);
  if (occupants.isEmpty) return false;
  return occupants.every((id) => formation.stateOf(id).waitingOut);
}

/// The two-row bands that make up the active hands four, top to bottom.
///
/// Derived from **waiting-out state** (`docs/fundamentals.md` §10.3), not from
/// couple numbers or couple orientation. Those earlier signals could only be
/// read on a settled shape, and every state a figure actually sees is
/// mid-dance: both were empirically unresolvable on *every* intermediate state
/// of both golden fixtures. Waiting-out state is carried on the dancer, so it
/// survives whatever shape a figure leaves the set in.
///
/// The rule is also formation-independent — Duple Improper and Becket differ
/// only in how a couple is oriented *within* a band, never in where the bands
/// fall — so there is no longer a formation dispatch here.
///
/// **Total**: unlike the rule it replaces, this can always be evaluated.
List<({int topRow, int bottomRow})> handsFourBands(Formation formation) {
  final waiting = waitingOutRows(formation).toSet();
  final active = [
    for (var row = 0; row < formation.rowCount; row++)
      if (!waiting.contains(row)) row,
  ];
  return [
    for (var i = 0; i + 1 < active.length; i += 2)
      (topRow: active[i], bottomRow: active[i + 1]),
  ];
}

/// The band containing [row], or `null` if that row is waiting out.
({int topRow, int bottomRow})? handsFourBandContaining(
  Formation formation,
  int row,
) {
  for (final band in handsFourBands(formation)) {
    if (band.topRow == row || band.bottomRow == row) return band;
  }
  return null;
}

/// Returns [formation] with every dancer standing in [rows] marked as waiting
/// out (`docs/fundamentals.md` §10.3).
///
/// The marking is **positional**, not couple-based: whoever stands in the row
/// is out, whether or not the two of them are partners. `slide_along_set`
/// depends on that — it re-bands the set, and the pair it strands at an end is
/// frequently not a couple.
Formation markWaitingOut(Formation formation, {required List<int> rows}) =>
    formation.withUpdates({
      for (final row in rows)
        for (final id in formation.dancersInRow(row))
          id: formation.stateOf(id).copyWith(waitingOut: true),
    });

/// Returns [formation] with **every** dancer back in the set.
///
/// Used by `slide_along_set`, which re-bands the whole set in one move: when a
/// slide brings the band grid back into alignment with row 0 there are no end
/// half-bands left, so nobody is out. Clearing wholesale rather than by row is
/// deliberate — a slide moves the standing-out dancers too, so by the time this
/// runs they are no longer in the rows they were marked from, and clearing only
/// the ends would leave dancers marked out while standing in an active band.
///
/// The progression change-over in `applyEndNormalization` does its own,
/// narrower clear; this is not that.
Formation clearWaitingOut(Formation formation) => formation.withUpdates({
  for (final entry in formation.dancers.entries)
    if (entry.value.waitingOut)
      entry.key: entry.value.copyWith(waitingOut: false),
});

/// Whether the band grid currently sits in its **shifted** phase.
///
/// The grid has exactly two phases: *aligned*, where the bands start at row 0
/// (`(0,1)`, `(2,3)`, …) and nobody is out, and *shifted*, where they start at
/// row 1 (`(1,2)`, …) and the top and bottom rows are stranded as half-bands.
/// A set with an end standing out is in the shifted phase by definition.
bool isShiftedBandPhase(Formation formation) {
  final waiting = waitingOutRows(formation).toSet();
  return waiting.contains(0) || waiting.contains(formation.lastRow);
}

/// Returns [formation] with the band grid moved to its **other** phase.
///
/// Toggling is what a figure does when it carries dancers into the grouping
/// beside them: `slide_along_set` moves everyone one row along, and a figure
/// danced with the next neighbours reaches one grouping on. Either way the
/// hands four boundaries fall between different rows than they did, so the set
/// re-bands — a settled set sends its two end rows out, and a set that already
/// has couples out brings them **back in** beside whoever has just arrived.
///
/// The clear is wholesale rather than by row on purpose; see [clearWaitingOut].
///
/// Applying this twice restores the original waiting-out state **provided no
/// dancer moved in between**, since the marking is positional.
Formation toggleBandPhase(Formation formation) => isShiftedBandPhase(formation)
    ? clearWaitingOut(formation)
    : markWaitingOut(formation, rows: [0, formation.lastRow]);

/// Which way [id] travels down the set, in rows: `+1` down the hall, `-1` up.
///
/// The two formations progress along different axes, because their couples lie
/// along different axes (`docs/fundamentals.md` §10.3.1):
///
/// - **Duple Improper** — couples share a *row*, so a couple travels as a unit
///   and its direction is set by its **number**: the 1s go down the hall, the
///   2s go up (§10.4, §10.5).
/// - **Becket** — couples share a *column*, so each **line** shifts as a unit
///   and the direction is set by the Becket sense (§10.6): under CW the c4 line
///   shifts down and the c0 line up; CCW is the mirror.
///
/// This says nothing about whether the dancer *is* travelling right now — only
/// which way "on down the set" points for them. It is what makes "the grouping
/// ahead of you" well defined for both the progression oracle and the
/// cross-hands-four dancer sets.
int travelDirection(Formation formation, DancerId id) {
  final state = formation.stateOf(id);
  if (!formation.type.couplesShareColumn) {
    return state.number == CoupleNumber.one ? 1 : -1;
  }
  final onEastLine = state.position.col == kColumnCount - 1;
  final eastGoesDown = formation.type == FormationType.becketCw;
  return onEastLine == eastGoesDown ? 1 : -1;
}

/// The four corner cells of [band] in **clockwise** order — TL, TR, BR, BL.
///
/// This is the ring `O` that `docs/taxonomy.md` defines the rotation figures
/// over (`circle`, `star`, `petronella`): `[(topRow,c0), (topRow,c4),
/// (botRow,c4), (botRow,c0)]`. The middle columns are never part of it.
List<Position> handsFourRing(({int topRow, int bottomRow}) band) => [
  Position(band.topRow, 0),
  Position(band.topRow, kColumnCount - 1),
  Position(band.bottomRow, kColumnCount - 1),
  Position(band.bottomRow, 0),
];

/// Rotates the dancers around the corner ring of every **complete** hands four.
///
/// [steps] is the taxonomy's ring offset: `new[O[k]] = old[O[(k + steps) % 4]]`.
/// Positive is counter-clockwise (`circle` right, `star` with the left hand in,
/// `petronella`); negative is clockwise (`circle` left, `star` right hand).
///
/// Role, number and couple-identity travel with each dancer — the ring moves
/// *people*, so everything held on [DancerState] follows automatically.
///
/// A band whose four corners are not all occupied is **skipped**: the taxonomy
/// scopes these figures to a complete hands four, and a partly-filled band is a
/// transient shape a later figure is expected to resolve.
Formation rotateHandsFourRings(Formation formation, {required int steps}) {
  final offset = steps % 4;
  if (offset == 0) return formation;

  final changes = <DancerId, DancerState>{};
  for (final band in handsFourBands(formation)) {
    final ring = handsFourRing(band);
    final occupants = [for (final cell in ring) formation.dancerAt(cell)];
    if (occupants.any((id) => id == null)) continue;
    for (var k = 0; k < 4; k++) {
      final mover = occupants[(k + offset) % 4]!;
      changes[mover] = formation.stateOf(mover).movedTo(ring[k]);
    }
  }
  return formation.withUpdates(changes);
}

/// A **grouping** in the taxonomy's sense (`docs/taxonomy.md`, `chain`).
///
/// Either a complete hands four (two rows) or a waiting-out couple at an end
/// of the set (one row). The figures that reach past the active hands four —
/// the diagonal chains especially — are defined over groupings rather than
/// bands, because a waiting couple still participates as its own single-couple
/// grouping even though it belongs to no hands four.
typedef Grouping = ({List<int> rows, bool isWaiting});

/// Every grouping in the set, ordered **top to bottom**.
///
/// Waiting rows become single-row groupings; the rest pair off into bands
/// exactly as [handsFourBands] does. Ordering is by the grouping's topmost row,
/// which is what makes "the grouping above/below" (`left_diagonal` /
/// `right_diagonal`) well defined.
List<Grouping> groupingsDownTheSet(Formation formation) {
  final waiting = waitingOutRows(formation).toSet();
  final groupings = <Grouping>[
    for (final row in waiting) (rows: [row], isWaiting: true),
    for (final band in handsFourBands(formation))
      (rows: [band.topRow, band.bottomRow], isWaiting: false),
  ];
  groupings.sort((a, b) => a.rows.first.compareTo(b.rows.first));
  return groupings;
}

/// The dancers standing in [grouping], in row order.
List<DancerId> dancersInGrouping(Formation formation, Grouping grouping) => [
  for (final row in grouping.rows) ...formation.dancersInRow(row),
];
