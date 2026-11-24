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
        expect(after.toRolesNotation(), [
          'L1-C . . . R1-A',
          'R1-C . . . L1-A',
          'L1-E . . . R2-B',
          'R1-E . . . L2-B',
          'L2-F . . . R2-D',
          'R2-F . . . L2-D',
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
