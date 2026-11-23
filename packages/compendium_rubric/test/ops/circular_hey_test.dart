import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

/// Partners are row-mates, neighbours column-mates (`docs/taxonomy.md`).
const List<String> base = ['R1-A . . . L1-A', 'L2-B . . . R2-B'];
const List<String> rowSwap = ['L2-B . . . R2-B', 'R1-A . . . L1-A'];
const List<String> colSwap = ['L1-A . . . R1-A', 'R2-B . . . L2-B'];
const List<String> diagonal = ['R2-B . . . L2-B', 'L1-A . . . R1-A'];

Formation applyOk(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$op failed: $result');
  return (result as Ok<Formation, OpError>).value;
}

void main() {
  group('circular_hey: each change swaps the pair passing', () {
    // Neighbours stand along the set, so they pass along first (a row swap),
    // then the other pair across (a column swap), alternating.
    final cases = <int, List<String>>{
      1: rowSwap,
      2: diagonal,
      3: colSwap,
      4: base,
      5: rowSwap,
    };
    for (final entry in cases.entries) {
      test('neighbours first, ${entry.key} change(s)', () {
        expect(
          applyOk(CircularHey(changes: entry.key), di(base)).toRolesNotation(),
          entry.value,
        );
      });
    }

    test('partners first pass across, so one change is the column swap', () {
      expect(
        applyOk(
          const CircularHey(who: WhoSet.partners, changes: 1),
          di(base),
        ).toRolesNotation(),
        colSwap,
      );
      expect(
        applyOk(
          const CircularHey(who: WhoSet.partners, changes: 3),
          di(base),
        ).toRolesNotation(),
        rowSwap,
      );
    });

    test('shoulder, who2 and where move nobody', () {
      final plain = applyOk(const CircularHey(changes: 3), di(base));
      final dressed = applyOk(
        const CircularHey(
          changes: 3,
          shoulder: Hand.left,
          who2: WhoSet.partners,
          where: Direction.along,
        ),
        di(base),
      );
      expect(dressed.toRolesNotation(), plain.toRolesNotation());
    });

    test('in Becket, neighbours stand across, so they pass across first', () {
      final becket = parseRolesNotation(const [
        'L2-B . . . R1-A',
        'R2-B . . . L1-A',
      ], type: FormationType.becketCw);
      expect(applyOk(const CircularHey(changes: 1), becket).toRolesNotation(), [
        'R1-A . . . L2-B',
        'L1-A . . . R2-B',
      ]);
    });
  });

  group('circular_hey refuses a ring it cannot read', () {
    test('a who naming no pair in the hands four', () {
      final error = const CircularHey(
        who: WhoSet.ones,
      ).checkPreconditions(di(base));
      expect(error?.kind, ErrorKind.unresolvableDancerSet);
    });
  });

  test('is progression-eligible, and not its own progression', () {
    expect(const CircularHey().progressionEligible, isTrue);
    expect(const CircularHey().isItsOwnProgression, isFalse);
  });
}
