import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

// The hands fours follow the dancers (user-ruled 2026-11-24). A figure naming
// partners finds its grouping by where they stand, never by moving anyone,
// and the set stays grouped that way afterwards (limiting it to partners is
// the agent's call). An end couple with nobody at the named distance swings
// each other.

Formation becket(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.becketCw);

List<List<int>> bandRows(Formation formation) => [
  for (final band in handsFourBands(formation)) [band.topRow, band.bottomRow],
];

void main() {
  group('a figure naming partners finds them one band phase over', () {
    // Three hands four of a Becket set in which every couple further in
    // stands one row lower than the grouping the set is in: in the bands
    // (0,1) (2,3) (4,5) no column pair is a couple, one phase over every one
    // is. The rows at the ends are the couples that would wait out there.
    final input = becket([
      'L1-A . . . R1-A',
      'L1-C . . . L2-D',
      'R1-C . . . R2-D',
      'L1-E . . . L2-F',
      'R1-E . . . R2-F',
      'L2-B . . . R2-B',
    ]);

    test('the set is not grouped with the partners to begin with', () {
      expect(bandRows(input), [
        [0, 1],
        [2, 3],
        [4, 5],
      ]);
    });

    test('the swing is danced where the partners stand', () {
      final result = const Swing(who: WhoSet.partners).apply(input);

      expect(result, isA<Ok<Formation, OpError>>(), reason: '$result');
      final after = (result as Ok<Formation, OpError>).value;
      expect(bandRows(after), [
        [1, 2],
        [3, 4],
      ], reason: 'the set stays grouped with the dancers');
      expect(waitingOutRows(after), [0, 5]);
    });

    test('nobody changes rows to find a partner', () {
      final after =
          (const Swing(who: WhoSet.partners).apply(input)
                  as Ok<Formation, OpError>)
              .value;
      for (final id in input.dancers.keys) {
        final rowBefore = input.stateOf(id).position.row;
        final rowAfter = after.stateOf(id).position.row;
        // A swing on the side places the couple within its own two rows.
        expect(
          (rowAfter - rowBefore).abs(),
          lessThanOrEqualTo(1),
          reason: '$id',
        );
        expect(
          after.stateOf(id).position.col,
          input.stateOf(id).position.col,
          reason: '$id',
        );
      }
    });

    test('with partners in neither phase, the current refusal is reported', () {
      final scrambled = becket([
        'L1-A . . . R1-C',
        'L1-C . . . R1-A',
        'L2-B . . . R2-D',
        'L2-D . . . R2-B',
      ]);
      final result = const Swing(who: WhoSet.partners).apply(scrambled);

      expect(result, isA<Err<Formation, OpError>>(), reason: '$result');
      final error = (result as Err<Formation, OpError>).error;
      expect(error.kind, ErrorKind.whoMismatch);
      // L-A and L-C are the column-0 pair in the grouping the set is in.
      expect(error.message, contains('L-A and L-C'));
    });
  });

  group('an end couple with no next neighbours swings each other', () {
    // Becket, three hands four. In each end hands four the west column pair
    // is a couple (B at the top, E at the bottom), with nobody beyond them;
    // every other column pair is a next-neighbour pair.
    final input = becket([
      'L2-B . . . R1-A',
      'R2-B . . . L2-D',
      'L1-A . . . R1-C',
      'R2-D . . . L2-F',
      'L1-E . . . L1-C',
      'R1-E . . . R2-F',
    ]);

    test('the end couples pass the swing check', () {
      expect(
        const Swing(who: WhoSet.nextNeighbors).checkPreconditions(input),
        isNull,
      );
    });

    test('a couple further in is still refused', () {
      // Put a couple in the middle hands four's west column.
      final middleCouple = becket([
        'L2-B . . . R1-A',
        'R2-B . . . L2-D',
        'L1-C . . . R2-D',
        'R1-C . . . L2-F',
        'L1-E . . . L1-A',
        'R1-E . . . R2-F',
      ]);
      final error = const Swing(
        who: WhoSet.nextNeighbors,
      ).checkPreconditions(middleCouple);

      expect(error?.kind, ErrorKind.whoMismatch);
      expect(error?.message, contains('L-C and R-C'));
    });

    test('an end couple travelling into the set is still refused', () {
      // The top couple are 1s on the west line of a clockwise Becket, so
      // they travel down, toward next neighbours they do have.
      final intoTheSet = becket([
        'L1-B . . . R1-A',
        'R1-B . . . L2-D',
        'L1-A . . . R2-C',
        'R2-D . . . L2-F',
        'L1-E . . . L2-C',
        'R1-E . . . R2-F',
      ]);
      final error = const Swing(
        who: WhoSet.nextNeighbors,
      ).checkPreconditions(intoTheSet);

      expect(error?.kind, ErrorKind.whoMismatch);
      expect(error?.message, contains('L-B and R-B'));
    });

    test('the swing runs once a progression has spent the distance', () {
      // Until then the cross-hands-four check in Operation.apply refuses the
      // end couple first: they did not start a grouping apart.
      expect(
        const Swing(who: WhoSet.nextNeighbors).apply(input, progressions: 1),
        isA<Ok<Formation, OpError>>(),
      );
      expect(
        const Swing(who: WhoSet.nextNeighbors).apply(input),
        isA<Err<Formation, OpError>>(),
      );
    });

    test('the end couple is not let through when the swing names no '
        'distance', () {
      // Naming neighbours, not a distance set, the end couple is refused.
      expect(
        const Swing(who: WhoSet.neighbors).checkPreconditions(input)?.kind,
        ErrorKind.whoMismatch,
      );
    });
  });
}
