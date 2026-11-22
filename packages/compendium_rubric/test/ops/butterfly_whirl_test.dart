import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

/// Partners are row-mates, neighbours column-mates (`docs/taxonomy.md`).
const List<String> base = ['R1-A . . . L1-A', 'L2-B . . . R2-B'];

/// Both couples on the diagonal: nobody is beside their partner.
const List<String> diagonal = ['R1-A . . . R2-B', 'L2-B . . . L1-A'];

void main() {
  group('butterfly_whirl moves nobody (user-ruled 2026-11-22)', () {
    for (final op in const [
      ButterflyWhirl(),
      ButterflyWhirl(
        who: WhoSet.partners,
        direction: SpinDirection.counterclockwise,
      ),
      ButterflyWhirl(who: WhoSet.neighbors, direction: SpinDirection.clockwise),
    ]) {
      test('$op lands where it started', () {
        final before = di(base);
        final result = op.apply(before);
        expect(result, isA<Ok<Formation, OpError>>(), reason: '$result');
        expect((result as Ok<Formation, OpError>).value, before);
      });
    }
  });

  group('a named pair must stand side by side', () {
    test('partners on the diagonal are refused', () {
      final result = const ButterflyWhirl(
        who: WhoSet.partners,
      ).apply(di(diagonal));
      expect(result, isA<Err<Formation, OpError>>());
      expect(
        (result as Err<Formation, OpError>).error.kind,
        ErrorKind.unresolvableDancerSet,
      );
    });

    test('an unstated pair names nobody, so there is nothing to check', () {
      final result = const ButterflyWhirl().apply(di(diagonal));
      expect(result, isA<Ok<Formation, OpError>>(), reason: '$result');
    });
  });
}
