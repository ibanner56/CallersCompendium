import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

/// A Becket CW start of three hands fours: each couple on one side line.
Formation becketStart() => parseRolesNotation([
  'L2-B . . . R1-A',
  'R2-B . . . L1-A',
  'L2-D . . . R1-C',
  'R2-D . . . L1-C',
  'L2-F . . . R1-E',
  'R2-F . . . L1-E',
], type: FormationType.becketCw);

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

void main() {
  group('a diagonal right and left through trades with the next couple', () {
    test(
      'left diagonal: each west couple trades with the east couple above',
      () {
        final after = applyOk(
          const RightLeftThrough(dir: 'leftDiagonal'),
          becketStart(),
        );
        // D (west, second hands four) and A (east, first) trade, as do F and C.
        // Each lands end for end and faces in; B at the top and E at the bottom
        // have no one on their diagonal and stay, coming back in as the other
        // of their own number.
        expect(after.toRolesNotation(), [
          'L1-B . . . R2-D',
          'R1-B . . . L2-D',
          'L1-A . . . R2-F',
          'R1-A . . . L2-F',
          'L1-C . . . R2-E',
          'R1-C . . . L2-E',
        ]);
        for (var row = 0; row <= after.lastRow; row++) {
          for (final id in after.dancersInRow(row)) {
            final state = after.stateOf(id);
            if (id.coupleIndex == 1 || id.coupleIndex == 4) continue;
            expect(
              state.facing,
              state.col == 0 ? Facing.acrossEast : Facing.acrossWest,
              reason: '$id faces into the set',
            );
          }
        }
      },
    );

    test(
      'right diagonal: each west couple trades with the east couple below',
      () {
        final after = applyOk(
          const RightLeftThrough(dir: 'rightDiagonal'),
          becketStart(),
        );
        // A at the top and F at the bottom stay and come back in as the
        // other number, so each hands four holds one #1 and one #2 couple.
        expect(after.toRolesNotation(), [
          'L1-C . . . R2-A',
          'R1-C . . . L2-A',
          'L1-E . . . R2-B',
          'R1-E . . . L2-B',
          'L1-F . . . R2-D',
          'R1-F . . . L2-D',
        ]);
      },
    );

    test('a diagonal trade is its own progression; across is not', () {
      const diagonal = RightLeftThrough(dir: 'leftDiagonal');
      const across = RightLeftThrough();
      expect(diagonal.isItsOwnProgression, isTrue);
      expect(diagonal.hands4Contribution, 1);
      expect(across.isItsOwnProgression, isFalse);
      expect(across.hands4Contribution, 0);
    });
  });

  group('the diagonal trade and the progression', () {
    test('Becket CCW from its start: every hands four keeps one #1 and one '
        '#2 couple, the ends facing in', () {
      // The trade never reads the formation type; this pins the CCW start
      // with its forward diagonal, the right one.
      final after = applyOk(
        const RightLeftThrough(dir: 'rightDiagonal'),
        startingFormation(FormationType.becketCcw, handsFour: 3),
      );
      for (final band in handsFourBands(after)) {
        final numbers = [
          for (final row in [band.topRow, band.topRow + 1])
            for (final id in after.dancersInRow(row)) after.stateOf(id).number,
        ];
        expect(numbers.where((n) => n == CoupleNumber.one), hasLength(2));
        expect(numbers.where((n) => n == CoupleNumber.two), hasLength(2));
      }
      for (var row = 0; row <= after.lastRow; row++) {
        for (final id in after.dancersInRow(row)) {
          final state = after.stateOf(id);
          expect(
            state.facing,
            state.col == 0 ? Facing.acrossEast : Facing.acrossWest,
            reason: '$id faces into the set',
          );
        }
      }
    });

    test('a couple at an end facing out turns back in', () {
      final start = becketStart();
      final top = [
        start.dancerAt(const Position(0, 0))!,
        start.dancerAt(const Position(1, 0))!,
      ];
      final facingOut = start.withUpdates({
        for (final id in top)
          id: start.stateOf(id).copyWith(facing: Facing.acrossWest),
      });
      final after = applyOk(
        const RightLeftThrough(dir: 'leftDiagonal'),
        facingOut,
      );
      for (final id in top) {
        expect(after.stateOf(id).facing, Facing.acrossEast, reason: '$id');
      }
    });

    test('a flagged diagonal trade spends two progressions', () {
      // Each couple ends facing the couple two hands fours from its start, so
      // a figure naming the next neighbours afterwards reaches two further.
      expect(
        const OperationInvocation(
          RightLeftThrough(dir: 'rightDiagonal'),
          progression: true,
        ).progressionCount,
        2,
      );
      expect(
        const OperationInvocation(
          RightLeftThrough(),
          progression: true,
        ).progressionCount,
        1,
      );
      expect(
        const OperationInvocation(
          RightLeftThrough(dir: 'rightDiagonal'),
        ).progressionCount,
        0,
      );
      // A container spends what its diagonal trade spends.
      expect(
        const OperationInvocation(
          FiguresInOrder([
            RightLeftThrough(dir: 'leftDiagonal'),
            LongLines(),
          ], name: 'modifier'),
          progression: true,
        ).progressionCount,
        2,
      );
      expect(
        const OperationInvocation(
          Meanwhile([RightLeftThrough(dir: 'leftDiagonal'), LongLines()]),
          progression: true,
        ).progressionCount,
        2,
      );
    });

    test('a flagged diagonal trade is never held for a change-over', () {
      final result = const OperationInvocation(
        RightLeftThrough(dir: 'leftDiagonal'),
        progression: true,
      ).applyHolding(becketStart());
      expect(result, isA<Ok<({Formation formation, bool held}), OpError>>());
      final applied =
          (result as Ok<({Formation formation, bool held}), OpError>).value;
      expect(applied.held, isFalse);
      expect(
        applied.formation.toRolesNotation(),
        applyOk(
          const RightLeftThrough(dir: 'leftDiagonal'),
          becketStart(),
        ).toRolesNotation(),
      );
    });
  });

  group('what the diagonal trade does not cover', () {
    test('a hands four in a line of four is refused', () {
      // The second hands four stands in one row, so neither side line holds
      // a couple to trade.
      final line = parseRolesNotation([
        'L2-B . . . R1-A',
        'R2-B . . . L1-A',
        'L2-D R2-D . L1-C R1-C',
        '. . . . .',
        'L2-F . . . R1-E',
        'R2-F . . . L1-E',
      ], type: FormationType.becketCw);
      final error = applyErr(const RightLeftThrough(dir: 'leftDiagonal'), line);
      expect(error.kind, ErrorKind.unresolvableDancerSet);
    });

    test('couples already waiting out at the ends are deferred', () {
      final slid = applyOk(const SlideAlongSet(), becketStart());
      final error = applyErr(const RightLeftThrough(dir: 'leftDiagonal'), slid);
      expect(error.kind, ErrorKind.unsupportedParam);
      expect(error.detail, contains('waiting out'));
    });
  });
}
