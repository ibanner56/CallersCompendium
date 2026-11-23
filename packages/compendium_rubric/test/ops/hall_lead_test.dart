import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

const List<String> base = ['R1-A . . . L1-A', 'L2-B . . . R2-B'];
const List<String> traded = ['L2-B . . . R2-B', 'R1-A . . . L1-A'];

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

const leadDown = DownTheHall(
  who: WhoSet.ones,
  moving: HallMoving.center,
  ender: HallEnder.turnAlone,
);
const leadUp = UpTheHall(
  who: WhoSet.ones,
  moving: HallMoving.center,
  ender: HallEnder.none,
);
const castOff = Cast(
  who: WhoSet.ones,
  direction: CastDirection.down,
  places: 1,
);

void main() {
  group('a hall figure led by part of the set (user-ruled 2026-11-23)', () {
    test('ones lead down one place; the twos step up', () {
      final after = applyOk(leadDown, di(base));
      expect(after.toRolesNotation(), traded);
    });

    test('leaders face their travel, or turn alone; the passed are '
        'flexible', () {
      final turned = applyOk(leadDown, di(base));
      final straight = applyOk(
        const DownTheHall(
          who: WhoSet.ones,
          moving: HallMoving.center,
          ender: HallEnder.none,
        ),
        di(base),
      );
      for (final entry in turned.dancers.entries) {
        final isOne = entry.value.number == CoupleNumber.one;
        expect(
          entry.value.facing,
          isOne ? Facing.up : Facing.flexible,
          reason: '${entry.key}',
        );
        expect(
          straight.stateOf(entry.key).facing,
          isOne ? Facing.down : Facing.flexible,
          reason: '${entry.key}',
        );
      }
    });

    test('lead down, turn alone, lead up, cast off: the ones progress '
        'one place, as a cast off alone does', () {
      var state = di(base);
      for (final op in const <Operation>[leadDown, leadUp, castOff]) {
        state = applyOk(op, state);
      }
      expect(state.toRolesNotation(), traded);
      expect(
        state.toRolesNotation(),
        applyOk(castOff, di(base)).toRolesNotation(),
      );
    });

    test('going down the outside passes the same dancers', () {
      final after = applyOk(
        const DownTheHall(
          who: WhoSet.ones,
          moving: HallMoving.outsides,
          ender: HallEnder.none,
        ),
        di(base),
      );
      expect(after.toRolesNotation(), traded);
    });

    test('twos lead up from below the ones', () {
      final after = applyOk(
        const UpTheHall(
          who: WhoSet.twos,
          moving: HallMoving.center,
          ender: HallEnder.none,
        ),
        di(base),
      );
      expect(after.toRolesNotation(), traded);
    });

    test('every hands four leads at once', () {
      expect(
        applyOk(
          leadDown,
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

    test('a couple standing out at an end neither leads nor is passed', () {
      var state = startingFormation(FormationType.dupleImproper, handsFour: 3);
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

      final after = applyOk(leadDown, state);
      for (final entry in outBefore.entries) {
        expect(after.stateOf(entry.key).position, entry.value);
        expect(after.stateOf(entry.key).waitingOut, isTrue);
      }
    });

    test('leading off the end of the hands four is refused', () {
      expect(
        refusal(leadDown, di(traded)).kind,
        ErrorKind.unresolvableDancerSet,
      );
    });

    test(
      'in Becket the ones share a column, so they would pass each other',
      () {
        final becket = parseRolesNotation(const [
          'L2-B . . . R1-A',
          'R2-B . . . L1-A',
        ], type: FormationType.becketCw);
        final error = refusal(leadDown, becket);
        expect(error.kind, ErrorKind.unresolvableDancerSet);
        expect(error.message, contains('moving too'));
      },
    );

    test(
      'a partial lead may carry the progression; a line of four may not',
      () {
        expect(leadDown.progressionEligible, isTrue);
        expect(const DownTheHall().progressionEligible, isFalse);
      },
    );

    test('the hallFacingConflict lint stays silent', () {
      final line = applyOk(const DownTheHall(ender: HallEnder.none), di(base));
      expect(
        const UpTheHall(who: WhoSet.ones, moving: HallMoving.center).lint(line),
        isEmpty,
      );
    });
  });

  group('a partial lead refuses what the ruling leaves open', () {
    final cases = <String, Operation>{
      'partners as leaders': const DownTheHall(
        who: WhoSet.partners,
        moving: HallMoving.center,
        ender: HallEnder.none,
      ),
      'moving:all': const DownTheHall(who: WhoSet.ones, ender: HallEnder.none),
      'facing:backward': const DownTheHall(
        who: WhoSet.ones,
        moving: HallMoving.center,
        facing: HallFacing.backward,
        ender: HallEnder.none,
      ),
      'ender:turnCouple': const DownTheHall(
        who: WhoSet.ones,
        moving: HallMoving.center,
      ),
      'ender:circle': const UpTheHall(
        who: WhoSet.ones,
        moving: HallMoving.center,
      ),
    };
    for (final entry in cases.entries) {
      test('${entry.key} is deferred', () {
        expect(refusal(entry.value, di(base)).kind, ErrorKind.unsupportedParam);
      });
    }
  });
}
