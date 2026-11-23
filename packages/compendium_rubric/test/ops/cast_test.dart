import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

const List<String> base = ['R1-A . . . L1-A', 'L2-B . . . R2-B'];

Formation applyOk(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$op failed: $result');
  return (result as Ok<Formation, OpError>).value;
}

OpError refusal(Operation op, Formation input) {
  final error = op.checkPreconditions(input);
  expect(error, isNotNull, reason: '$op should refuse');
  return error!;
}

void main() {
  group('cast (user-ruled 2026-11-23): casters move N, passed step 1', () {
    test('ones cast down one: ones and twos trade rows', () {
      expect(
        applyOk(
          const Cast(
            who: WhoSet.ones,
            direction: CastDirection.down,
            places: 1,
          ),
          di(base),
        ).toRolesNotation(),
        ['L2-B . . . R2-B', 'R1-A . . . L1-A'],
      );
    });

    test('ones cast up one from below the twos', () {
      expect(
        applyOk(
          const Cast(who: WhoSet.ones, direction: CastDirection.up, places: 1),
          di(const ['L2-B . . . R2-B', 'R1-A . . . L1-A']),
        ).toRolesNotation(),
        base,
      );
    });

    test('ones cast up two: they pass two couples, who each step down one', () {
      final input = di(const [
        'L2-B . . . R2-B',
        'L2-D . . . R2-D',
        'R1-A . . . L1-A',
        '. . . . .',
      ]);
      final after = const Cast(
        who: WhoSet.ones,
        direction: CastDirection.up,
        places: 2,
      ).perform(input);
      expect(after, isA<Ok<Formation, OpError>>(), reason: '$after');
      expect((after as Ok<Formation, OpError>).value.toRolesNotation(), [
        'R1-A . . . L1-A',
        'L2-B . . . R2-B',
        'L2-D . . . R2-D',
        '. . . . .',
      ]);
    });

    test('two casters passing the same dancers are refused, not guessed', () {
      // Every ones couple casting down two in an ordinary duple set: A would
      // pass B and C, but C is casting too.
      final error =
          const Cast(
            who: WhoSet.ones,
            direction: CastDirection.down,
            places: 2,
          ).checkPreconditions(
            di(const [
              'R1-A . . . L1-A',
              'L2-B . . . R2-B',
              'R1-C . . . L1-C',
              'L2-D . . . R2-D',
            ]),
          );
      expect(error?.kind, ErrorKind.unresolvableDancerSet);
    });

    test('casting dancers end with flexible facing; passed dancers too', () {
      final before = startingFormation(
        FormationType.dupleImproper,
        handsFour: 1,
      );
      final after = applyOk(
        const Cast(who: WhoSet.ones, direction: CastDirection.down, places: 1),
        before,
      );
      for (final state in after.dancers.values) {
        expect(state.facing, Facing.flexible);
      }
    });

    test('whom is descriptive', () {
      expect(
        applyOk(
          const Cast(
            who: WhoSet.ones,
            direction: CastDirection.down,
            places: 1,
            whom: WhoSet.neighbors,
          ),
          di(base),
        ).toRolesNotation(),
        ['L2-B . . . R2-B', 'R1-A . . . L1-A'],
      );
    });
  });

  group('cast refuses what the ruling leaves open', () {
    for (final direction in [CastDirection.left, CastDirection.right, null]) {
      test('direction ${direction?.key ?? 'unstated'} is deferred', () {
        expect(
          refusal(
            Cast(who: WhoSet.ones, direction: direction, places: 1),
            di(base),
          ).kind,
          ErrorKind.unsupportedParam,
        );
      });
    }

    test('no caster named is deferred', () {
      expect(
        refusal(
          const Cast(direction: CastDirection.down, places: 1),
          di(base),
        ).kind,
        ErrorKind.unsupportedParam,
      );
    });

    test('no number of places is deferred', () {
      expect(
        refusal(
          const Cast(who: WhoSet.ones, direction: CastDirection.down),
          di(base),
        ).kind,
        ErrorKind.unsupportedParam,
      );
    });

    test('a stated destination is deferred', () {
      expect(
        refusal(
          const Cast(
            who: WhoSet.ones,
            direction: CastDirection.up,
            places: 1,
            destination: 'place',
          ),
          di(base),
        ).kind,
        ErrorKind.unsupportedParam,
      );
    });

    test('a pair relation such as partners names no casters', () {
      expect(
        refusal(
          const Cast(
            who: WhoSet.partners,
            direction: CastDirection.down,
            places: 1,
          ),
          di(base),
        ).kind,
        ErrorKind.unresolvableDancerSet,
      );
    });

    test('nobody to cast around at the end of the set', () {
      expect(
        refusal(
          const Cast(
            who: WhoSet.twos,
            direction: CastDirection.down,
            places: 1,
          ),
          di(base),
        ).kind,
        ErrorKind.unresolvableDancerSet,
      );
    });
  });

  test('is progression-eligible, and not its own progression', () {
    expect(const Cast().progressionEligible, isTrue);
    expect(const Cast().isItsOwnProgression, isFalse);
  });
}
