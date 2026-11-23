import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

/// The duple improper hands four, as in `docs/taxonomy.md`.
Formation base() => di(const ['R1-A . . . L1-A', 'L2-B . . . R2-B']);

Formation applyOk(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$op failed: $result');
  return (result as Ok<Formation, OpError>).value;
}

OpError applyErr(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Err<Formation, OpError>>(), reason: '$op passed: $result');
  return (result as Err<Formation, OpError>).error;
}

Facing facingAt(Formation f, int row, int col) =>
    f.stateOf(f.dancerAt(Position(row, col))!).facing;

/// The line of four facing down the hall, ones on the ends.
Formation lineDown() =>
    applyOk(const DownTheHall(ender: HallEnder.none), base());

void main() {
  group('a fractional mirror gate turns each side pair as a unit', () {
    test('from the ring, ones forward 1¼: a line facing the way they walk', () {
      final after = applyOk(
        const Gate(
          pair: WhoSet.neighbors,
          direction: GateDirection.mirror,
          whom: WhoSet.ones,
          turn: 1.25,
        ),
        base(),
      );
      // The ones walk forward from the top row, so the line faces down with
      // the ones in the centre; nobody changes side of the set.
      expect(after.toRolesNotation(), ['L2-B R1-A . L1-A R2-B', '. . . . .']);
      expect(after.dancers.values.map((d) => d.facing).toSet(), {Facing.down});
    });

    test('naming who backs up reads the same as naming who walks forward', () {
      final byWhom = applyOk(
        const Gate(
          direction: GateDirection.mirror,
          whom: WhoSet.ones,
          turn: 1.25,
        ),
        base(),
      );
      final byWho = applyOk(
        const Gate(
          direction: GateDirection.mirror,
          who: WhoSet.twos,
          turn: 1.25,
        ),
        base(),
      );
      expect(byWho.toRolesNotation(), byWhom.toRolesNotation());
    });

    test('three quarters is a quarter the other way round', () {
      final after = applyOk(
        const Gate(
          direction: GateDirection.mirror,
          whom: WhoSet.ones,
          turn: 0.75,
        ),
        base(),
      );
      // Walking forward three quarters carries the ones round to the ends,
      // and the line faces up.
      expect(after.toRolesNotation(), ['. . . . .', 'R1-A L2-B . R2-B L1-A']);
      expect(after.dancers.values.map((d) => d.facing).toSet(), {Facing.up});
    });

    test('from a line, ends forward 1¼: back into the ring, facing in', () {
      final after = applyOk(
        const Gate(
          pair: WhoSet.neighbors,
          direction: GateDirection.mirror,
          whom: WhoSet.ones,
          turn: 1.25,
        ),
        lineDown(),
      );
      // The ones are the ends of the down-facing line: they walk forward, down
      // the hall, and finish below the twos.
      expect(after.toRolesNotation(), ['L2-B . . . R2-B', 'R1-A . . . L1-A']);
      expect(facingAt(after, 0, 0), Facing.acrossEast);
      expect(facingAt(after, 1, 0), Facing.acrossEast);
      expect(facingAt(after, 0, 4), Facing.acrossWest);
      expect(facingAt(after, 1, 4), Facing.acrossWest);
    });

    test('a same-sense gate from the ring would make a two-faced line', () {
      final error = applyErr(
        const Gate(
          pair: WhoSet.neighbors,
          direction: GateDirection.clockwise,
          turn: 1.25,
        ),
        base(),
      );
      expect(error.kind, ErrorKind.unsupportedParam);
      expect(error.detail, contains('two-faced line'));
    });

    test('a mirror gate that names nobody walking forward is refused', () {
      final error = applyErr(
        const Gate(direction: GateDirection.mirror, turn: 1.25),
        base(),
      );
      expect(error.kind, ErrorKind.unresolvableDancerSet);
      expect(error.detail, contains('walk forward'));
    });

    test('a fractional gate with no direction is refused', () {
      final error = applyErr(const Gate(turn: 0.25), base());
      expect(error.kind, ErrorKind.unsupportedParam);
      expect(error.detail, contains('needs a direction'));
    });

    test('a stated pairing other than the side pairs is refused', () {
      final error = applyErr(
        const Gate(
          pair: WhoSet.partners,
          direction: GateDirection.mirror,
          whom: WhoSet.ones,
          turn: 1.25,
        ),
        base(),
      );
      expect(error.kind, ErrorKind.whoMismatch);
    });
  });

  group('a stated face on a fractional gate', () {
    const out = Gate(
      direction: GateDirection.mirror,
      whom: WhoSet.ones,
      turn: 1.25,
      face: GateFace.down,
    );

    test('agreeing with the turn, it is accepted', () {
      final after = applyOk(out, base());
      expect(after.dancers.values.map((d) => d.facing).toSet(), {Facing.down});
    });

    test('disagreeing with the turn, it is refused', () {
      final error = applyErr(
        const Gate(
          direction: GateDirection.mirror,
          whom: WhoSet.ones,
          turn: 1.25,
          face: GateFace.up,
        ),
        base(),
      );
      expect(error.kind, ErrorKind.unsupportedParam);
      expect(error.detail, contains('face:up disagrees'));
    });
  });

  group('a bare hand cast closes a line of four like bend the line', () {
    test('it lands where the bendTheLine ender does', () {
      final viaGate = applyOk(const Gate(), lineDown());
      final viaBend = applyOk(
        const DownTheHall(ender: HallEnder.bendTheLine),
        base(),
      );
      expect(viaGate.toRolesNotation(), viaBend.toRolesNotation());
      for (final id in viaGate.dancers.keys) {
        expect(
          viaGate.stateOf(id).facing,
          viaBend.stateOf(id).facing,
          reason: '$id',
        );
      }
    });

    test('from the ring there is no line to close, so it is refused', () {
      final error = applyErr(const Gate(), base());
      expect(error.kind, ErrorKind.unsupportedParam);
      expect(error.detail, contains('needs a stated turn'));
    });
  });
}
