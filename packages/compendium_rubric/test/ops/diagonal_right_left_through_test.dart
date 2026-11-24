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
        // have no one on their diagonal and stay, taking their end's number.
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
    test('Becket CCW: the couples left at the ends change number', () {
      final ccw = parseRolesNotation([
        'L1-A . . . R2-B',
        'R1-A . . . L2-B',
        'L1-C . . . R2-D',
        'R1-C . . . L2-D',
        'L1-E . . . R2-F',
        'R1-E . . . L2-F',
      ], type: FormationType.becketCcw);
      final after = applyOk(const RightLeftThrough(dir: 'leftDiagonal'), ccw);
      expect(after.toRolesNotation(), [
        'L2-A . . . R1-C',
        'R2-A . . . L1-C',
        'L2-B . . . R1-E',
        'R2-B . . . L1-E',
        'L2-D . . . R1-F',
        'R2-D . . . L1-F',
      ]);
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
