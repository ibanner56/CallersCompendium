import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

/// Partners are row-mates, neighbours column-mates (`docs/taxonomy.md`).
const List<String> base = ['R1-A . . . L1-A', 'L2-B . . . R2-B'];
const List<String> rowSwap = ['L2-B . . . R2-B', 'R1-A . . . L1-A'];

Formation applyOk(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$op failed: $result');
  return (result as Ok<Formation, OpError>).value;
}

void main() {
  group('arch_and_dive is the row swap (user-ruled)', () {
    for (final who in [WhoSet.ones, WhoSet.twos]) {
      test('${who.key} arching: the couples trade places along the set', () {
        expect(
          applyOk(ArchAndDive(who: who), di(base)).toRolesNotation(),
          rowSwap,
        );
      });
    }

    test('facing is preserved: both couples walk forward through', () {
      final before = startingFormation(
        FormationType.dupleImproper,
        handsFour: 1,
      );
      final after = applyOk(const ArchAndDive(), before);
      for (final entry in after.dancers.entries) {
        expect(entry.value.facing, before.stateOf(entry.key).facing);
      }
    });

    test('twice is the identity', () {
      expect(
        applyOk(const ArchAndDive(), applyOk(const ArchAndDive(), di(base))),
        di(base),
      );
    });
  });

  test('is progression-eligible, and not its own progression', () {
    expect(const ArchAndDive().progressionEligible, isTrue);
    expect(const ArchAndDive().isItsOwnProgression, isFalse);
  });
}
