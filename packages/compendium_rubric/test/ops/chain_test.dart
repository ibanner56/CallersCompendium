import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation becket(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.becketCw);

Formation applyOk(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$op failed: $result');
  return (result as Ok<Formation, OpError>).value;
}

void main() {
  group('RightLeftThrough', () {
    test('matches the taxonomy worked example', () {
      final after = applyOk(
        const RightLeftThrough(),
        parseRolesNotation(const [
          'L2-B . . . R2-B',
          'R1-A . . . L1-A',
        ], type: FormationType.dupleImproper),
      );
      expect(after.toRolesNotation(), ['L1-A . . . R1-A', 'R2-B . . . L2-B']);
    });

    test('reproduces The Judge op 3 across all three hands four', () {
      // trace.after_2_swing_neighbor -> trace.after_3_right_left_through
      final after = applyOk(
        const RightLeftThrough(),
        becket(const [
          'L2-B . . . R2-B',
          'R1-A . . . L1-A',
          'L2-D . . . R2-D',
          'R1-C . . . L1-C',
          'L2-F . . . R2-F',
          'R1-E . . . L1-E',
        ]),
      );
      expect(after.toRolesNotation(), [
        'L1-A . . . R1-A',
        'R2-B . . . L2-B',
        'L1-C . . . R1-C',
        'R2-D . . . L2-D',
        'L1-E . . . R1-E',
        'R2-F . . . L2-F',
      ]);
    });

    test('applying it twice returns the set to where it started', () {
      final start = becket(const ['L2-B . . . R2-B', 'R1-A . . . L1-A']);
      const op = RightLeftThrough();
      expect(applyOk(op, applyOk(op, start)).toMatrix(), start.toMatrix());
    });

    test('dancers finish facing into the set', () {
      final after = applyOk(
        const RightLeftThrough(),
        becket(const ['L2-B . . . R2-B', 'R1-A . . . L1-A']),
      );
      expect(
        after.stateOf(after.dancerAt(const Position(0, 0))!).facing,
        Facing.acrossEast,
      );
      expect(
        after.stateOf(after.dancerAt(const Position(0, 4))!).facing,
        Facing.acrossWest,
      );
    });

    test('dir:along is deferred, not approximated', () {
      final result = const RightLeftThrough(
        dir: 'along',
      ).apply(becket(const ['L2-B . . . R2-B', 'R1-A . . . L1-A']));
      expect(
        (result as Err<Formation, OpError>).error.kind,
        ErrorKind.unsupportedParam,
      );
    });
  });

  group('Chain', () {
    // trace.after_3_right_left_through, the input The Judge's chain sees.
    Formation judgeOp4Input() => becket(const [
      'L1-A . . . R1-A',
      'R2-B . . . L2-B',
      'L1-C . . . R1-C',
      'R2-D . . . L2-D',
      'L1-E . . . R1-E',
      'R2-F . . . L2-F',
    ]);

    test('reproduces The Judge op 4 (robins, left_diagonal) exactly', () {
      final after = applyOk(
        const Chain(who: WhoSet.role2s, dir: ChainDirection.leftDiagonal),
        judgeOp4Input(),
      );
      expect(after.toRolesNotation(), [
        'L1-A . . . R2-D',
        'R2-B . . . L2-B',
        'L1-C . . . R2-F',
        'R1-A . . . L2-D',
        'L1-E . . . R1-E',
        'R1-C . . . L2-F',
      ]);
    });

    test('after an across chain, a diagonal chain pairs by where dancers '
        'stand', () {
      // The Glass Goddess (Caller's Box #15677): a ladies chain across, then
      // on the right diagonal to the shadow. The across chain has put the
      // #1 robins on the west line, so pairing by couple number would chain
      // on the other diagonal (user-ruled 2026-11-23).
      final after = applyOk(
        const Chain(who: WhoSet.role2s, dir: ChainDirection.rightDiagonal),
        becket(const [
          'L2-B . . . R2-B',
          'R1-A . . . L1-A',
          'L2-D . . . R2-D',
          'R1-C . . . L1-C',
          'L2-F . . . R2-F',
          'R1-E . . . L1-E',
        ]),
      );
      expect(after.toRolesNotation(), [
        'L2-B . . . R2-B',
        'R2-D . . . L1-A',
        'L2-D . . . R1-A',
        'R2-F . . . L1-C',
        'L2-F . . . R1-C',
        'R1-E . . . L1-E',
      ]);
    });

    test('across pairs by line when the numbers name no pair', () {
      // After a diagonal chain both robins of a hands four can carry one
      // number; facing each other across the set they still chain.
      final after = applyOk(
        const Chain(who: WhoSet.role2s),
        becket(const ['L2-B . . . R1-A', 'R1-C . . . L2-D']),
      );
      expect(after.toRolesNotation(), ['L2-B . . . R1-C', 'R1-A . . . L2-D']);
    });

    test('a diagonal with two chaining dancers on one line is refused', () {
      final result = const Chain(
        who: WhoSet.role2s,
        dir: ChainDirection.leftDiagonal,
      ).apply(becket(const ['R2-B . . . L1-A', 'R1-A . . . L2-B']));
      expect(
        (result as Err<Formation, OpError>).error.kind,
        ErrorKind.unresolvableDancerSet,
      );
    });

    test('the top grouping\'s #2 has nothing above, so it stays put', () {
      final before = judgeOp4Input();
      final after = applyOk(
        const Chain(who: WhoSet.role2s, dir: ChainDirection.leftDiagonal),
        before,
      );
      const seat = Position(1, 0);
      expect(after.dancerAt(seat), before.dancerAt(seat));
    });

    test('no dancer is swapped twice', () {
      final before = judgeOp4Input();
      final after = applyOk(
        const Chain(who: WhoSet.role2s, dir: ChainDirection.leftDiagonal),
        before,
      );
      // Exactly four dancers move: two initiator #2s and their two receivers.
      final moved = before.dancers.keys
          .where(
            (id) => after.stateOf(id).position != before.stateOf(id).position,
          )
          .toList();
      expect(moved.length, 4);
    });

    test('across trades the two chaining dancers within each hands four', () {
      final after = applyOk(const Chain(who: WhoSet.role2s), judgeOp4Input());
      expect(after.toRolesNotation(), [
        'L1-A . . . R2-B',
        'R1-A . . . L2-B',
        'L1-C . . . R2-D',
        'R1-C . . . L2-D',
        'L1-E . . . R2-F',
        'R1-E . . . L2-F',
      ]);
    });

    test('chaining the other role moves the other set of dancers', () {
      final after = applyOk(const Chain(who: WhoSet.role1s), judgeOp4Input());
      // The larks trade; the robins are untouched.
      expect(after.toRolesNotation()[0], 'L2-B . . . R1-A');
    });

    test('a diagonal contributes one extra hands four', () {
      expect(
        const Chain(
          who: WhoSet.role2s,
          dir: ChainDirection.leftDiagonal,
        ).hands4Contribution,
        1,
      );
      expect(const Chain(who: WhoSet.role2s).hands4Contribution, 0);
    });

    test('dir:along and non-role who are reported as unsupported', () {
      final along = const Chain(
        who: WhoSet.role2s,
        dir: ChainDirection.along,
      ).apply(judgeOp4Input());
      expect(
        (along as Err<Formation, OpError>).error.kind,
        ErrorKind.unsupportedParam,
      );
      final badWho = const Chain(who: WhoSet.partners).apply(judgeOp4Input());
      expect(
        (badWho as Err<Formation, OpError>).error.kind,
        ErrorKind.unsupportedParam,
      );
    });
  });

  group('Chain across waiting-out ends', () {
    // The case the taxonomy singles out: a waiting couple participates as its
    // own single-couple grouping.
    Formation setWithEndsOut() => markWaitingOut(
      startingFormation(FormationType.dupleImproper, handsFour: 3),
      rows: [0, 5],
    );

    test('waiting rows become single-couple groupings', () {
      final groupings = groupingsDownTheSet(setWithEndsOut());
      expect(groupings.map((g) => g.rows), [
        [0],
        [1, 2],
        [3, 4],
        [5],
      ]);
      expect(groupings.map((g) => g.isWaiting), [true, false, false, true]);
    });

    // In this set the top waiting robin stands on the west line and the
    // bottom one on the east line. Pairing is by where they stand
    // (user-ruled 2026-11-23): from the west line the right diagonal runs
    // down the set, from the east line up it.
    DancerId waitingRobin(Formation set, int row) =>
        set.dancersInRow(row).firstWhere((id) => id.role == Role.robin);

    test('a waiting couple at the top takes part on a right_diagonal', () {
      final before = setWithEndsOut();
      final robin = waitingRobin(before, 0);
      expect(before.stateOf(robin).position.col, 0);
      final after = applyOk(
        const Chain(who: WhoSet.role2s, dir: ChainDirection.rightDiagonal),
        before,
      );
      expect(
        after.stateOf(robin).position,
        isNot(before.stateOf(robin).position),
        reason: 'the waiting couple must take part as its own grouping',
      );
    });

    test('a waiting couple at the bottom takes part on a right_diagonal', () {
      final before = setWithEndsOut();
      final robin = waitingRobin(before, 5);
      expect(before.stateOf(robin).position.col, kColumnCount - 1);
      final after = applyOk(
        const Chain(who: WhoSet.role2s, dir: ChainDirection.rightDiagonal),
        before,
      );
      expect(
        after.stateOf(robin).position,
        isNot(before.stateOf(robin).position),
      );
    });

    test('a waiting dancer whose diagonal leads out of the set stays', () {
      final before = setWithEndsOut();
      final after = applyOk(
        const Chain(who: WhoSet.role2s, dir: ChainDirection.leftDiagonal),
        before,
      );
      for (final row in [0, 5]) {
        final robin = waitingRobin(before, row);
        expect(
          after.stateOf(robin).position,
          before.stateOf(robin).position,
          reason: '$robin',
        );
      }
    });

    test('waiting-out state itself is untouched by the chain', () {
      final before = setWithEndsOut();
      final after = applyOk(
        const Chain(who: WhoSet.role2s, dir: ChainDirection.leftDiagonal),
        before,
      );
      for (final id in before.dancers.keys) {
        expect(
          after.stateOf(id).waitingOut,
          before.stateOf(id).waitingOut,
          reason: '$id',
        );
      }
    });
  });
}
