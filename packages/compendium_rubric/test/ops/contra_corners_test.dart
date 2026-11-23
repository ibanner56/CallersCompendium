import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

/// Partners are row-mates, neighbours column-mates (`docs/taxonomy.md`).
const List<String> base = ['R1-A . . . L1-A', 'L2-B . . . R2-B'];

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
  group('contra_corners (user-ruled 2026-11-22)', () {
    test('the ones end in their partner\'s place; the corners end home', () {
      expect(applyOk(const ContraCorners(), di(base)).toRolesNotation(), [
        'L1-A . . . R1-A',
        'L2-B . . . R2-B',
      ]);
    });

    test('twos active swap instead, and the ones stay home', () {
      expect(
        applyOk(
          const ContraCorners(who: WhoSet.twos),
          di(base),
        ).toRolesNotation(),
        ['R1-A . . . L1-A', 'R2-B . . . L2-B'],
      );
    });

    test('the variation note changes no landing', () {
      expect(
        applyOk(const ContraCorners(custom: 'same-role'), di(base)),
        applyOk(const ContraCorners(), di(base)),
      );
    });

    test('actives standing along the set have no partner across', () {
      // The ones share a column here, not a row.
      final error = applyErr(
        const ContraCorners(),
        di(const ['R1-A . . . L2-B', 'L1-A . . . R2-B']),
      );
      expect(error.kind, ErrorKind.unresolvableDancerSet);
    });

    test('a who naming two pairs has no single active couple', () {
      final error = applyErr(
        const ContraCorners(who: WhoSet.partners),
        di(base),
      );
      expect(error.kind, ErrorKind.unresolvableDancerSet);
    });
  });
}
