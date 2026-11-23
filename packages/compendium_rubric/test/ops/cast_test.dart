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

    test('a cast of two places is deferred: it leaves its hands four', () {
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
      expect(error?.kind, ErrorKind.unsupportedParam);
    });

    test(
      'in Becket the ones share a column, so they would pass each other',
      () {
        final becket = parseRolesNotation(const [
          'L2-B . . . R1-A',
          'R2-B . . . L1-A',
        ], type: FormationType.becketCw);
        final error = const Cast(
          who: WhoSet.ones,
          direction: CastDirection.down,
          places: 1,
        ).checkPreconditions(becket);
        expect(error?.kind, ErrorKind.unresolvableDancerSet);
        expect(error?.message, contains('casting too'));
      },
    );

    test('every hands four casts, and only inside itself', () {
      expect(
        applyOk(
          const Cast(
            who: WhoSet.ones,
            direction: CastDirection.down,
            places: 1,
          ),
          di(const [
            'R1-A . . . L1-A',
            'L2-B . . . R2-B',
            'R1-C . . . L1-C',
            'L2-D . . . R2-D',
          ]),
        ).toRolesNotation(),
        [
          'L2-B . . . R2-B',
          'R1-A . . . L1-A',
          'L2-D . . . R2-D',
          'R1-C . . . L1-C',
        ],
      );
    });

    test('a couple standing out at an end neither casts nor is passed', () {
      // Cast off as the progression, then dance it again: the second cast
      // happens in the shifted phase, with a couple standing out at each end.
      var state = startingFormation(FormationType.dupleImproper, handsFour: 3);
      const castOff = Cast(
        who: WhoSet.ones,
        direction: CastDirection.down,
        places: 1,
      );
      final first = OperationInvocation(
        castOff,
        progression: true,
      ).apply(state);
      expect(first, isA<Ok<Formation, OpError>>(), reason: '$first');
      state = (first as Ok<Formation, OpError>).value;
      final outBefore = {
        for (final entry in state.dancers.entries)
          if (entry.value.waitingOut) entry.key: entry.value.position,
      };
      expect(outBefore, isNotEmpty);

      final second = const OperationInvocation(castOff).apply(state);
      expect(second, isA<Ok<Formation, OpError>>(), reason: '$second');
      final after = (second as Ok<Formation, OpError>).value;
      for (final entry in outBefore.entries) {
        expect(after.stateOf(entry.key).position, entry.value);
        expect(after.stateOf(entry.key).waitingOut, isTrue);
      }
      for (final band in handsFourBands(after)) {
        expect(band.bottomRow, band.topRow + 1);
      }
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
