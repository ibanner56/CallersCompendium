import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

/// The near miss the comparison accepts (user-ruled 2026-11-24): a dance that
/// ends with every dancer in the expected row but up to one column to the side,
/// for instance in a wave rather than on the side lines, still compiles, with
/// [WarningKind.endedColumnOffset].
void main() {
  Formation set(List<String> rows) =>
      parseRolesNotation(rows, type: FormationType.dupleImproper);

  final expected = set(['L1-A . . . R1-A', 'L2-B . . . R2-B']);

  test('a dancer one column in from the side line is accepted', () {
    final wave = set(['L1-A . . R1-A .', '. L2-B . . R2-B']);
    expect(endsWithinOneColumn(wave, expected), isTrue);
  });

  test('a dancer two columns off is not', () {
    final far = set(['L1-A . . . R1-A', '. . L2-B . R2-B']);
    expect(endsWithinOneColumn(far, expected), isFalse);
  });

  test('a dancer in the wrong row is not, however close', () {
    final swapped = set(['L2-B . . . R1-A', 'L1-A . . . R2-B']);
    expect(endsWithinOneColumn(swapped, expected), isFalse);
  });

  test('a couple with the wrong number is not, in the right places', () {
    // A couple at an end whose change-over never ran: only the column is
    // relaxed, never the number.
    final renumbered = set(['L2-A . . . R2-A', 'L1-B . . . R1-B']);
    expect(endsWithinOneColumn(renumbered, expected), isFalse);
  });

  test('two dancers trading places in a row are not', () {
    final wide = set(['L1-A R1-A . L2-B R2-B']);
    final traded = set(['R1-A L1-A . R2-B L2-B']);
    expect(endsWithinOneColumn(traded, wide), isFalse);
  });

  test('the exact match is within it too', () {
    expect(endsWithinOneColumn(expected, expected), isTrue);
  });

  group('the end check compile makes', () {
    // A waiting couple out at the end of the set is outside every hands
    // four, so the wave settling leaves its offsets alone: the near miss is
    // left for the tolerance to judge.
    final withWaiting = set([
      'L1-A . . . R1-A',
      'L2-B . . . R2-B',
      'L1-C . . . R1-C',
    ]);

    test('a near miss compiles, with one warning naming who is off', () {
      final offset = set([
        'L1-A . . . R1-A',
        'L2-B . . . R2-B',
        '. L1-C . . R1-C',
      ]);
      const carried = Warning(WarningKind.heldProgressionUnfinished);
      final result = judgeEnd(offset, withWaiting, warnings: [carried]);
      expect(result, isA<Compiled>());
      expect(result.warnings.first, same(carried));
      final added = result.warnings.skip(1).toList();
      expect(added, hasLength(1));
      expect(added.single.kind, WarningKind.endedColumnOffset);
      final lark = offset.dancerAt(const Position(2, 1))!;
      expect(added.single.detail, 'one column off: $lark');
    });

    test('an exact end compiles with no warning added', () {
      final result = judgeEnd(withWaiting, withWaiting);
      expect(result, isA<Compiled>());
      expect(result.warnings, isEmpty);
    });

    test('an end two columns off is a mismatch', () {
      final far = set([
        'L1-A . . . R1-A',
        'L2-B . . . R2-B',
        '. . L1-C . R1-C',
      ]);
      expect(judgeEnd(far, withWaiting), isA<Mismatch>());
    });
  });
}
