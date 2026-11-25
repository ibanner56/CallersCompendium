// `shift` (taxonomy v40): one named group sidesteps one place, with fuzzy
// travel so that shifting dancers never run into anyone (Hudson, 2026-11-24;
// staying put when the place is taken is the agent's call, 2026-11-25).
import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

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

DancerId at(Formation f, int row, int col) => f.dancerAt(Position(row, col))!;

/// Two hands fours in long lines, everyone facing in across the set.
Formation twoBands() {
  final lines = di([
    'L1-A . . . R1-A',
    'R2-B . . . L2-B',
    'L1-C . . . R1-C',
    'R2-D . . . L2-D',
  ]);
  return lines.withUpdates({
    for (final MapEntry(key: id, value: state) in lines.dancers.entries)
      id: state.copyWith(
        facing: state.col == 0 ? Facing.acrossEast : Facing.acrossWest,
      ),
  });
}

/// "Women allemande right 3/4": each hands four's Robins, on a diagonal,
/// turn into the centre line, leaving the Larks room along the sides.
Formation robinsInTheCentre() =>
    applyOk(const Allemande(who: WhoSet.role2s, turn: 0.75), twoBands());

Formation faced(Formation f, Map<DancerId, Facing> facings) => f.withUpdates({
  for (final MapEntry(key: id, value: facing) in facings.entries)
    id: f.stateOf(id).copyWith(facing: facing),
});

void main() {
  group('a shift left steps along the side the dancer faces from', () {
    test('a west Lark goes up and an east Lark goes down', () {
      final after = applyOk(const Shift(), robinsInTheCentre());
      expect(after.toRolesNotation(), [
        'L1-A . R1-A . .',
        'L1-C . R2-B . .',
        '. . R1-C . L2-B',
        '. . R2-D . L2-D',
      ]);
    });

    test('a shift right is the mirror', () {
      final after = applyOk(
        const Shift(direction: 'right'),
        robinsInTheCentre(),
      );
      // L1-A steps down into r1, L2-D up into r2; L2-B and L1-C would step
      // off the set's ends, so they stay.
      expect(at(after, 1, 0).toString(), 'L-A');
      expect(at(after, 2, 4).toString(), 'L-D');
    });

    test('the centre wave it shifts around is kept', () {
      final before = robinsInTheCentre();
      final after = applyOk(const Shift(), before);
      for (final row in [0, 1, 2, 3]) {
        expect(
          after.stateOf(at(before, row, 2)),
          before.stateOf(at(before, row, 2)),
        );
      }
    });
  });

  group('travel is fuzzy: a dancer whose place is taken stays', () {
    test('blocked by a dancer standing there', () {
      // From the side lines every Lark's place is held by a Robin.
      final before = twoBands();
      expect(applyOk(const Shift(), before), before);
    });

    test('at the end of the set', () {
      final after = applyOk(const Shift(), robinsInTheCentre());
      expect(at(after, 0, 0).toString(), 'L-A');
      expect(at(after, 3, 4).toString(), 'L-D');
    });

    test('two shifting into each other\'s cells both stay', () {
      // The Robins' centre long wave: R2-B (r1) faces west and R1-C (r2)
      // east, so each one's left is the other's cell. Swapping would walk
      // them through each other.
      final before = robinsInTheCentre();
      final after = applyOk(const Shift(who: WhoSet.role2s), before);
      expect(after.dancerAt(const Position(1, 2)), at(before, 1, 2));
      expect(after.dancerAt(const Position(2, 2)), at(before, 2, 2));
    });

    test('two shifting into one cell both stay', () {
      final start = twoBands();
      // L1-A (r0) faces west and L1-C (r2) east, so both step to r1, c0 --
      // which R2-B leaves by shifting too.
      final before = faced(start, {
        at(start, 0, 0): Facing.acrossWest,
        at(start, 2, 0): Facing.acrossEast,
      });
      final after = applyOk(
        const Shift(who: WhoSet.everyone, direction: 'down'),
        before,
      );
      expect(after.dancerAt(const Position(0, 0)), at(before, 0, 0));
      final both = applyOk(const Shift(who: WhoSet.everyone), before);
      expect(both.dancerAt(const Position(0, 0)), at(before, 0, 0));
      expect(both.dancerAt(const Position(2, 0)), at(before, 2, 0));
    });

    test('dancers waiting out at an end do not shift', () {
      final before = markWaitingOut(robinsInTheCentre(), rows: [3]);
      final after = applyOk(const Shift(direction: 'right'), before);
      expect(at(after, 3, 4).toString(), 'L-D');
    });
  });

  test('a shift left by a dancer facing along the set is deferred', () {
    final start = twoBands();
    final error = applyErr(
      const Shift(),
      faced(start, {at(start, 0, 0): Facing.down}),
    );
    expect(error.kind, ErrorKind.unsupportedParam);
    expect(error.detail, contains('deferred'));
  });

  test('beside an allemande in a meanwhile, it steps around the turn', () {
    final after = applyOk(
      const Meanwhile([Allemande(who: WhoSet.role2s, turn: 0.75), Shift()]),
      twoBands(),
    );
    expect(after, applyOk(const Shift(), robinsInTheCentre()));
  });

  test('a shifter beside a wave never leaves it unable to settle', () {
    // Neighbours ¼ into short waves, then the Larks shift up the hall: the
    // next figure settles the waves into the side lines, which must find
    // their cells free.
    final waves = applyOk(
      const Allemande(who: WhoSet.neighbors, turn: 0.25),
      twoBands(),
    );
    var checked = 0;
    for (final who in [WhoSet.role1s, WhoSet.role2s]) {
      for (final direction in ['up', 'down']) {
        final result = Shift(who: who, direction: direction).apply(waves);
        if (result case Ok(:final value)) {
          checked++;
          expect(
            () => const Swing(who: WhoSet.partners).apply(value),
            returnsNormally,
            reason: '$who $direction',
          );
        }
      }
    }
    expect(checked, greaterThan(0));
  });

  test('a meanwhile refuses a dancer its shift and another part both move', () {
    final error = applyErr(
      const Meanwhile([
        Allemande(who: WhoSet.role2s, turn: 0.75),
        Shift(who: WhoSet.role2s, direction: 'down'),
      ]),
      // Room below, so the Robins' shift is not stopped by fuzzy travel.
      di(['L1-A . . . R1-A', 'R2-B . . . L2-B', '. . . . .', '. . . . .']),
    );
    expect(error.kind, ErrorKind.unresolvableDancerSet);
  });

  test('two shift parts of a meanwhile step together, in either order', () {
    // Two hands fours in lines with two empty rows below: stepping down one
    // part at a time, the first part would be blocked by the second's dancers
    // still standing where it steps.
    final lines = di([
      'L1-A . . . R1-A',
      'R2-B . . . L2-B',
      'L1-C . . . R1-C',
      'R2-D . . . L2-D',
      '. . . . .',
      '. . . . .',
    ]);
    const larks = Shift(direction: 'down');
    const robins = Shift(who: WhoSet.role2s, direction: 'down');
    final together = applyOk(const Meanwhile([larks, robins]), lines);
    expect(applyOk(const Meanwhile([robins, larks]), lines), together);
    expect(
      together,
      applyOk(const Shift(who: WhoSet.everyone, direction: 'down'), lines),
    );
    expect(together.dancerAt(const Position(0, 0)), isNull);
  });
}
