import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

Formation becket(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.becketCw);

void main() {
  group('ring rotation (taxonomy: circle / star / petronella)', () {
    // The one worked example the taxonomy gives for petronella, which is also
    // the definition of a one-place counter-clockwise ring step.
    final example = di(const ['R1-A . . . L1-A', 'L2-B . . . R2-B']);

    test('one place counter-clockwise matches the taxonomy example', () {
      final after = rotateHandsFourRings(example, steps: 1);
      expect(after.toRolesNotation(), ['L1-A . . . R2-B', 'R1-A . . . L2-B']);
    });

    test('a full turn is the identity', () {
      for (final steps in [4, -4, 8]) {
        expect(
          rotateHandsFourRings(example, steps: steps).toMatrix(),
          example.toMatrix(),
          reason: 'steps=$steps',
        );
      }
    });

    test('opposite directions undo each other', () {
      final there = rotateHandsFourRings(example, steps: 3);
      expect(
        rotateHandsFourRings(there, steps: -3).toMatrix(),
        example.toMatrix(),
      );
    });

    test('every complete band rotates, and identity is preserved', () {
      final start = startingFormation(
        FormationType.dupleImproper,
        handsFour: 3,
      );
      final after = rotateHandsFourRings(start, steps: 1);
      expect(after.dancers.keys.toSet(), start.dancers.keys.toSet());
      for (final id in start.dancers.keys) {
        // Numbers and facing ride along with the dancer; only position moves.
        expect(after.stateOf(id).number, start.stateOf(id).number);
        expect(after.stateOf(id).facing, start.stateOf(id).facing);
      }
      expect(after.toMatrix(), isNot(start.toMatrix()));
    });

    test('a band standing out does not rotate', () {
      final formation = markWaitingOut(
        di(const [
          'R1-B . . . L1-B',
          'R1-A . . . L1-A',
          'L2-D . . . R2-D',
          'L2-C . . . R2-C',
        ]),
        rows: [0, 3],
      );
      final after = rotateHandsFourRings(formation, steps: 1);
      // Rows 0 and 3 are out of every band, so their dancers must not move.
      for (final row in [0, 3]) {
        for (final id in formation.dancersInRow(row)) {
          expect(after.stateOf(id).position, formation.stateOf(id).position);
        }
      }
      expect(after.dancersInRow(1), isNot(formation.dancersInRow(1)));
    });

    test('an incomplete band is skipped rather than corrupted', () {
      // A line of four: the band is real but its corner ring is not filled.
      final formation = di(const ['R1-A L1-A . L2-B R2-B', '. . . . .']);
      expect(
        rotateHandsFourRings(formation, steps: 1).toMatrix(),
        formation.toMatrix(),
      );
    });
  });

  group('Circle', () {
    test('left is clockwise, right is counter-clockwise', () {
      final start = di(const ['R1-A . . . L1-A', 'L2-B . . . R2-B']);
      final right = const Circle(
        turn: CircleDirection.right,
        places: 1,
      ).apply(start).valueOrNull!;
      final left = const Circle(
        turn: CircleDirection.left,
        places: 1,
      ).apply(start).valueOrNull!;
      expect(right.toRolesNotation(), ['L1-A . . . R2-B', 'R1-A . . . L2-B']);
      expect(left.toRolesNotation(), ['L2-B . . . R1-A', 'R2-B . . . L1-A']);
    });

    test('places 4 is a full turn and changes nothing', () {
      final start = startingFormation(
        FormationType.dupleImproper,
        handsFour: 2,
      );
      final after = const Circle(
        turn: CircleDirection.left,
        places: 4,
      ).apply(start).valueOrNull!;
      expect(after.toMatrix(), start.toMatrix());
    });

    test("reproduces The Baby Rose's op 2 exactly", () {
      // after_1_swing -> after_2_circle, with `turn: left, places: 3`.
      final after = const Circle(turn: CircleDirection.left, places: 3)
          .apply(
            di(const [
              'L2-B . . . R2-B',
              'R1-A . . . L1-A',
              'L2-D . . . R2-D',
              'R1-C . . . L1-C',
            ]),
          )
          .valueOrNull!;
      expect(after.toRolesNotation(), [
        'R2-B . . . L1-A',
        'L2-B . . . R1-A',
        'R2-D . . . L1-C',
        'L2-D . . . R1-C',
      ]);
    });

    test('singleFile is styling and cannot change the end state', () {
      final start = startingFormation(
        FormationType.dupleImproper,
        handsFour: 2,
      );
      const plain = Circle(turn: CircleDirection.right, places: 2);
      const single = Circle(
        turn: CircleDirection.right,
        places: 2,
        singleFile: true,
      );
      expect(
        single.apply(start).valueOrNull!.toMatrix(),
        plain.apply(start).valueOrNull!.toMatrix(),
      );
    });

    test('a part turn leaves everyone facing nowhere in particular', () {
      // The taxonomy's "facing (output): Flexible" contract, which the figure
      // did not honour until a real dance depended on it. A dancer part way
      // round a ring is still holding it; which way that has them pointing in
      // the hall is not determined until the next figure says. Carrying their
      // *previous* facing forward instead is a quiet lie, and it is the kind
      // that survives to be believed, because most dances follow a circle with
      // something positional that never asks.
      final start = startingFormation(
        FormationType.dupleImproper,
        handsFour: 2,
      );
      final after = const Circle(
        turn: CircleDirection.left,
        places: 3,
      ).apply(start).valueOrNull!;

      expect(
        after.dancers.values.map((state) => state.facing),
        everyElement(Facing.flexible),
      );
    });

    test('but a full turn puts nobody anywhere new, so it settles nothing', () {
      // Identity means identity. A dance that circles all the way round has
      // moved no one, so there is no new facing to resolve and no reason for
      // the figure to discard what the dancers already had.
      final start = startingFormation(
        FormationType.dupleImproper,
        handsFour: 2,
      );
      final after = const Circle(
        turn: CircleDirection.left,
        places: 4,
      ).apply(start).valueOrNull!;

      expect(
        after.dancers.values.map((state) => state.facing),
        isNot(contains(Facing.flexible)),
      );
    });

    test('and a star loosens facing the same way', () {
      final start = startingFormation(
        FormationType.dupleImproper,
        handsFour: 2,
      );
      final after = const Star(
        hand: Hand.left,
        places: 3,
      ).apply(start).valueOrNull!;

      expect(
        after.dancers.values.map((state) => state.facing),
        everyElement(Facing.flexible),
      );
    });
  });

  group('Star', () {
    test(
      'the left hand in turns counter-clockwise, the right hand clockwise',
      () {
        final start = di(const ['R1-A . . . L1-A', 'L2-B . . . R2-B']);
        expect(
          const Star(
            hand: Hand.left,
            places: 1,
          ).apply(start).valueOrNull!.toRolesNotation(),
          const Circle(
            turn: CircleDirection.right,
            places: 1,
          ).apply(start).valueOrNull!.toRolesNotation(),
        );
        expect(
          const Star(
            hand: Hand.right,
            places: 1,
          ).apply(start).valueOrNull!.toRolesNotation(),
          const Circle(
            turn: CircleDirection.left,
            places: 1,
          ).apply(start).valueOrNull!.toRolesNotation(),
        );
      },
    );

    test('grip never affects the end state', () {
      final start = startingFormation(
        FormationType.dupleImproper,
        handsFour: 2,
      );
      expect(
        const Star(
          hand: Hand.left,
          places: 3,
          grip: 'wrist_grip',
        ).apply(start).valueOrNull!.toMatrix(),
        const Star(
          hand: Hand.left,
          places: 3,
          grip: 'hands_across',
        ).apply(start).valueOrNull!.toMatrix(),
      );
    });

    test("The Baby Rose's closing star is a full turn, so the identity", () {
      final afterChain = di(const [
        'L2-B . . . R2-B',
        'R1-A . . . L1-A',
        'L2-D . . . R2-D',
        'R1-C . . . L1-C',
      ]);
      final after = const Star(
        hand: Hand.left,
        places: 4,
        grip: 'wrist_grip',
      ).apply(afterChain).valueOrNull!;
      expect(after.toMatrix(), afterChain.toMatrix());
    });

    test("with the progression, it lands on The Baby Rose's expected state", () {
      // The full op 6: the star's own transform (identity here) followed by the
      // §10.2 end-normalization, which is what the progression flag triggers.
      final result =
          const OperationInvocation(
            Star(hand: Hand.left, places: 4, grip: 'wrist_grip'),
            progression: true,
          ).apply(
            di(const [
              'L2-B . . . R2-B',
              'R1-A . . . L1-A',
              'L2-D . . . R2-D',
              'R1-C . . . L1-C',
            ]),
          );
      expect(result.valueOrNull!.toRolesNotation(), [
        'R1-B . . . L1-B',
        'R1-A . . . L1-A',
        'L2-D . . . R2-D',
        'L2-C . . . R2-C',
      ]);
      expect(result.valueOrNull!.toMatrix(), [
        [18, 0, 0, 0, 17],
        [10, 0, 0, 0, 9],
        [69, 0, 0, 0, 70],
        [37, 0, 0, 0, 38],
      ]);
    });
  });

  group('Petronella', () {
    test('is exactly circle right one place', () {
      final start = becket(const [
        'R2-D . . . L2-B',
        'L1-A . . . R2-B',
        'R2-F . . . L2-D',
        'L1-C . . . R1-A',
        'R1-E . . . L2-F',
        'L1-E . . . R1-C',
      ]);
      expect(
        const Petronella().apply(start).valueOrNull!.toRolesNotation(),
        const Circle(
          turn: CircleDirection.right,
          places: 1,
        ).apply(start).valueOrNull!.toRolesNotation(),
      );
    });

    test('the balance lead-in has no end-state effect', () {
      final start = startingFormation(FormationType.becketCw, handsFour: 3);
      expect(
        const Petronella(balance: true).apply(start).valueOrNull!.toMatrix(),
        const Petronella(balance: false).apply(start).valueOrNull!.toMatrix(),
      );
    });

    test('carries role, number and couple identity with each dancer', () {
      final start = startingFormation(
        FormationType.dupleImproper,
        handsFour: 2,
      );
      final after = const Petronella().apply(start).valueOrNull!;
      expect(after.dancers.keys.toSet(), start.dancers.keys.toSet());
      for (final id in start.dancers.keys) {
        expect(after.stateOf(id).number, start.stateOf(id).number);
      }
    });
  });
}
