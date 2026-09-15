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
