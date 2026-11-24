import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation start(FormationType type, {int handsFour = 2}) =>
    startingFormation(type, handsFour: handsFour);

List<String> after(FormationType type, int count, {int handsFour = 2}) =>
    ProgressionCriterion(
      count: count,
    ).expected(start(type, handsFour: handsFour)).toRolesNotation();

void main() {
  group('ProgressionCriterion — Duple Improper', () {
    test('single progression matches the canonical §10.5 example', () {
      // fundamentals.md §10.5: B rises to the top and takes #1, C drops to the
      // bottom and takes #2, A and D become the active hands four. This is also
      // test/golden/the_baby_rose.json -> expected.rolesNotation.
      expect(after(FormationType.dupleImproper, 1), [
        'R1-B . . . L1-B',
        'R1-A . . . L1-A',
        'L2-D . . . R2-D',
        'L2-C . . . R2-C',
      ]);
    });

    test('double progression completes the change-over of §10.3.2', () {
      // The worked table: progression 2 leaves B/D and A/C as the two bands,
      // because B and C are exempt from re-marking and re-enter the set.
      expect(after(FormationType.dupleImproper, 2), [
        'R1-B . . . L1-B',
        'L2-D . . . R2-D',
        'R1-A . . . L1-A',
        'L2-C . . . R2-C',
      ]);
    });

    test('the couples that reach an end are the ones left waiting out', () {
      final result = const ProgressionCriterion().expected(
        start(FormationType.dupleImproper),
      );
      expect(waitingOutRows(result), [0, 3]);
    });

    test('a progression leaves one active hands four in a two-h4 set', () {
      final result = const ProgressionCriterion().expected(
        start(FormationType.dupleImproper),
      );
      expect(handsFourBands(result), [(topRow: 1, bottomRow: 2)]);
    });
  });

  group('ProgressionCriterion — Progressed Improper', () {
    // A Progressed Improper set is Duple Improper with the 1s and 2s swapped
    // within each hands four, and so is its end (Hudson, 2026-11-24: "Double
    // progressed improper takes the normal end state from a double
    // progression and swaps the 1s and 2s within their hands four").
    test(
      'a double is the Duple Improper double, swapped in each hands four',
      () {
        // Duple Improper double, 2 hands four: B, D | A, C (see above).
        expect(after(FormationType.progressedImproper, 2), [
          'L2-D . . . R2-D',
          'R1-B . . . L1-B',
          'L2-C . . . R2-C',
          'R1-A . . . L1-A',
        ]);
        // Duple Improper double, 3 hands four: B, D | A, F | C, E.
        expect(after(FormationType.progressedImproper, 2, handsFour: 3), [
          'L2-D . . . R2-D',
          'R1-B . . . L1-B',
          'L2-F . . . R2-F',
          'R1-A . . . L1-A',
          'L2-E . . . R2-E',
          'R1-C . . . L1-C',
        ]);
      },
    );

    test('an odd count lands where Duple Improper does one round later', () {
      // At an odd count the Duple Improper end has a couple waiting out at
      // each end, and the swap in the hands fours between them gives the same
      // cells as one more Duple Improper round.
      for (final handsFour in [2, 3, 4, 5]) {
        for (final count in [1, 3]) {
          expect(
            ProgressionCriterion(count: count).expected(
              start(FormationType.progressedImproper, handsFour: handsFour),
            ),
            ProgressionCriterion(count: count + 1).expected(
              start(FormationType.dupleImproper, handsFour: handsFour),
            ),
            reason: '$handsFour hands four, $count rounds',
          );
        }
      }
    });

    test(
      'a triple ends with D at the top and F above B, as in Men at Work',
      () {
        // Hudson: "N4 is then fourth neighbors, which would be couples B and F
        // with couple D out at the top." Positions only: the oracle's marks are
        // not compared.
        expect(after(FormationType.progressedImproper, 3, handsFour: 3), [
          'R1-D . . . L1-D',
          'L2-F . . . R2-F',
          'R1-B . . . L1-B',
          'L2-E . . . R2-E',
          'R1-A . . . L1-A',
          'L2-C . . . R2-C',
        ]);
      },
    );
  });

  group('ProgressionCriterion — Becket (fundamentals §10.6 references)', () {
    test('CW + single', () {
      expect(after(FormationType.becketCw, 1), [
        'R1-B . . . L1-B',
        'L2-D . . . R1-A',
        'R2-D . . . L1-A',
        'L2-C . . . R2-C',
      ]);
    });

    test('CW + double restores the full formation', () {
      expect(after(FormationType.becketCw, 2), [
        'L2-D . . . R1-B',
        'R2-D . . . L1-B',
        'L2-C . . . R1-A',
        'R2-C . . . L1-A',
      ]);
    });

    test('CCW + single is the mirror of CW', () {
      expect(after(FormationType.becketCcw, 1), [
        'R2-A . . . L2-A',
        'L2-B . . . R1-C',
        'R2-B . . . L1-C',
        'L1-D . . . R1-D',
      ]);
    });

    test('CCW + double', () {
      expect(after(FormationType.becketCcw, 2), [
        'L2-A . . . R1-C',
        'R2-A . . . L1-C',
        'L2-B . . . R1-D',
        'R2-B . . . L1-D',
      ]);
    });

    test('CW + single on three hands four equals The Judge expected state', () {
      // test/golden/the_judge.json -> expected.rolesNotation
      expect(after(FormationType.becketCw, 1, handsFour: 3), [
        'R1-B . . . L1-B',
        'L2-D . . . R1-A',
        'R2-D . . . L1-A',
        'L2-F . . . R1-C',
        'R2-F . . . L1-C',
        'L2-E . . . R2-E',
      ]);
    });

    test('a waiting Becket couple re-enters on the opposite line', () {
      // B collects across the top row as a #1 after one progression, then
      // stands back up on c4 - the 1s line - for the second (§10.6).
      final once = const ProgressionCriterion().expected(
        start(FormationType.becketCw),
      );
      final twice = const ProgressionCriterion(
        count: 2,
      ).expected(start(FormationType.becketCw));
      final b = once.dancersInRow(0);
      expect(b.length, 2, reason: 'B lies across the end row after one round');
      for (final id in b) {
        expect(twice.stateOf(id).position.col, 4);
        expect(twice.stateOf(id).number, CoupleNumber.one);
      }
    });
  });

  group('ProgressionCriterion — contract', () {
    test(
      'a single progression fits the base set; each round after adds one',
      () {
        expect(const ProgressionCriterion().hands4Contribution, 0);
        expect(const ProgressionCriterion(count: 2).hands4Contribution, 1);
        expect(const ProgressionCriterion(count: 3).hands4Contribution, 2);
      },
    );

    test('the oracle is pure — it never mutates its input', () {
      final input = start(FormationType.dupleImproper);
      final before = input.toMatrix();
      const ProgressionCriterion(count: 3).expected(input);
      expect(input.toMatrix(), before);
    });

    test('applying count rounds equals applying one round count times', () {
      var stepwise = start(FormationType.becketCw);
      for (var i = 0; i < 3; i++) {
        stepwise = const ProgressionCriterion().expected(stepwise);
      }
      expect(
        const ProgressionCriterion(
          count: 3,
        ).expected(start(FormationType.becketCw)).toMatrix(),
        stepwise.toMatrix(),
      );
    });

    test('equality and identity', () {
      expect(
        const ProgressionCriterion(),
        const ProgressionCriterion(count: 1),
      );
      expect(
        const ProgressionCriterion(count: 2),
        isNot(const ProgressionCriterion()),
      );
      expect(const ProgressionCriterion().name, 'progression');
    });
  });
}
