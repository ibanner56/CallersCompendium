import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation applyOk(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$op failed: $result');
  return (result as Ok<Formation, OpError>).value;
}

/// [rows] with every dancer on a side line facing across into the set.
Formation facingIn(List<String> rows) {
  final start = parseRolesNotation(rows, type: FormationType.dupleImproper);
  return start.withUpdates({
    for (final entry in start.dancers.entries)
      entry.key: entry.value.copyWith(
        facing: entry.value.position.col == 0
            ? Facing.acrossEast
            : Facing.acrossWest,
      ),
  });
}

Facing facingAt(Formation f, int row, int col) =>
    f.stateOf(f.dancerAt(Position(row, col))!).facing;

/// The facing of every dancer, row by row, west line then east line.
List<Facing> facings(Formation f) => [
  for (var row = 0; row < f.rowCount; row++) ...[
    facingAt(f, row, 0),
    facingAt(f, row, kColumnCount - 1),
  ],
];

void main() {
  group('a half turn along a side line keeps travelling across the set', () {
    test('allemande left 1 1/2 with N2: the robins face in, the larks out', () {
      // User-ruled 2026-11-24, note on Heather's Hop Redux (Caller's Box
      // #10172): "R2-D should be facing in (along with all the other robins)
      // because of the allemande left", and L1-A facing out. These are the
      // N2 pairs there: the robin above the lark on both lines.
      final turned = applyOk(
        const Allemande(hand: Hand.left, turn: 1.5),
        facingIn(['R1-A . . . L1-A', 'L2-B . . . R2-B']),
      );
      expect(turned.toRolesNotation(), ['L2-B . . . R2-B', 'R1-A . . . L1-A']);
      expect(facings(turned), [
        Facing.acrossWest, // L2-B, west line: out
        Facing.acrossWest, // R2-B, east line: in
        Facing.acrossEast, // R1-A, west line: in
        Facing.acrossEast, // L1-A, east line: out
      ]);
    });

    test('the turn decides it, not the role: the larks can face in', () {
      // Agent's call: the rule is the turn's direction. A left turn wheels
      // counter-clockwise, so whoever finishes up the set is still moving
      // west and whoever finishes below is moving east, whatever their role.
      final turned = applyOk(
        const Allemande(hand: Hand.left, turn: 0.5),
        facingIn(['L2-B . . . R2-B', 'R1-A . . . L1-A']),
      );
      expect(turned.toRolesNotation(), ['R1-A . . . L1-A', 'L2-B . . . R2-B']);
      expect(facings(turned), [
        Facing.acrossWest, // R1-A, up the west line: out
        Facing.acrossWest, // L1-A, up the east line: in
        Facing.acrossEast, // L2-B, down the west line: in
        Facing.acrossEast, // R2-B, down the east line: out
      ]);
    });

    test('an allemande right is the mirror', () {
      final turned = applyOk(
        const Allemande(hand: Hand.right, turn: 0.5),
        facingIn(['L2-B . . . R2-B', 'R1-A . . . L1-A']),
      );
      expect(facings(turned), [
        Facing.acrossEast,
        Facing.acrossEast,
        Facing.acrossWest,
        Facing.acrossWest,
      ]);
    });

    test('a Flexible facing stays Flexible', () {
      final start = facingIn(['L2-B . . . R2-B', 'R1-A . . . L1-A']);
      final flexible = start.withUpdates({
        for (final entry in start.dancers.entries)
          entry.key: entry.value.copyWith(facing: Facing.flexible),
      });
      final turned = applyOk(
        const Allemande(hand: Hand.left, turn: 0.5),
        flexible,
      );
      expect(facings(turned), everyElement(Facing.flexible));
    });

    test('a pair across the set still reverses', () {
      final start = facingIn(['L2-B . . . R2-B', 'R1-A . . . L1-A']);
      final turned = applyOk(
        const Allemande(who: WhoSet.partners, hand: Hand.left, turn: 0.5),
        start,
      );
      expect(turned.toRolesNotation(), ['R2-B . . . L2-B', 'L1-A . . . R1-A']);
      // Each reverses the way it faced, so having crossed it faces in again.
      expect(facings(turned), [
        Facing.acrossEast,
        Facing.acrossWest,
        Facing.acrossEast,
        Facing.acrossWest,
      ]);
    });
  });
}
