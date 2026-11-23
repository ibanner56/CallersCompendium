import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

const List<String> base = ['R1-A . . . L1-A', 'L2-B . . . R2-B'];
const List<String> onesBelow = ['L2-B . . . R2-B', 'R1-A . . . L1-A'];

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

HallFigure down(WhoSet who, HallEnder ender) =>
    DownTheHall(who: who, moving: HallMoving.center, ender: ender);
HallFigure up(WhoSet who, HallEnder ender) =>
    UpTheHall(who: who, moving: HallMoving.center, ender: ender);

/// The lead out of a round trip, which dances the whole trip.
HallFigure trip(HallFigure out, HallFigure back) => out.pairedWith(back);

void main() {
  group('a lead out and straight back (user-ruled 2026-11-23)', () {
    test('nobody else moves, and the leaders end where they started', () {
      final start = di(base);
      final after = applyOk(
        trip(
          down(WhoSet.ones, HallEnder.turnAlone),
          up(WhoSet.ones, HallEnder.none),
        ),
        start,
      );
      expect(after.toRolesNotation(), base);
      for (final entry in start.dancers.entries) {
        final isOne = entry.value.number == CoupleNumber.one;
        expect(
          after.stateOf(entry.key).facing,
          isOne ? Facing.up : entry.value.facing,
          reason: '${entry.key}',
        );
      }
    });

    test('leaders with nobody to pass still go out and back', () {
      // On its own a lead down from the bottom of the hands four is refused,
      // because the cast-like lead has nobody to pass; out and back it is not.
      expect(
        refusal(down(WhoSet.ones, HallEnder.turnAlone), di(onesBelow)).kind,
        ErrorKind.unresolvableDancerSet,
      );
      expect(
        applyOk(
          trip(
            down(WhoSet.ones, HallEnder.turnAlone),
            up(WhoSet.ones, HallEnder.none),
          ),
          di(onesBelow),
        ).toRolesNotation(),
        onesBelow,
      );
    });

    test('a couple turn on the way trades the leaders with their partners', () {
      expect(
        applyOk(
          trip(
            down(WhoSet.ones, HallEnder.turnCouple),
            up(WhoSet.ones, HallEnder.none),
          ),
          di(base),
        ).toRolesNotation(),
        ['L1-A . . . R1-A', 'L2-B . . . R2-B'],
      );
    });

    test('up and back down is a round trip too', () {
      expect(
        applyOk(
          trip(
            up(WhoSet.twos, HallEnder.turnAlone),
            down(WhoSet.twos, HallEnder.none),
          ),
          di(base),
        ).toRolesNotation(),
        base,
      );
    });

    test('in Becket the ones share a column and still go out and back', () {
      const becket = ['L2-B . . . R1-A', 'R2-B . . . L1-A'];
      final start = parseRolesNotation(becket, type: FormationType.becketCw);
      expect(
        applyOk(
          trip(
            down(WhoSet.ones, HallEnder.turnAlone),
            up(WhoSet.ones, HallEnder.none),
          ),
          start,
        ).toRolesNotation(),
        becket,
      );
    });

    test('a band standing as a line of four is refused', () {
      final line = applyOk(const DownTheHall(ender: HallEnder.none), di(base));
      final error = refusal(
        trip(
          down(WhoSet.ones, HallEnder.none),
          up(WhoSet.ones, HallEnder.none),
        ),
        line,
      );
      expect(error.kind, ErrorKind.unresolvableDancerSet);
      expect(error.message, contains('line of four'));
    });

    test('the lead back moves nobody: the lead out danced it', () {
      final back = up(WhoSet.ones, HallEnder.none).asReturnLeg;
      expect(back.checkPreconditions(di(onesBelow)), isNull);
      expect(applyOk(back, di(onesBelow)).toMatrix(), di(onesBelow).toMatrix());
      expect(back, isNot(up(WhoSet.ones, HallEnder.none)));
    });

    test('only an opposite lead by the same leaders pairs', () {
      final out = down(WhoSet.ones, HallEnder.turnAlone);
      expect(
        HallFigure.areRoundTrip(out, up(WhoSet.ones, HallEnder.none)),
        isTrue,
      );
      expect(
        HallFigure.areRoundTrip(out, up(WhoSet.twos, HallEnder.none)),
        isFalse,
      );
      expect(
        HallFigure.areRoundTrip(out, down(WhoSet.ones, HallEnder.none)),
        isFalse,
      );
      expect(HallFigure.areRoundTrip(out, const UpTheHall()), isFalse);
      // A lead back whose own ender a round trip does not take stays
      // unpaired, so it is refused at its own line.
      expect(
        HallFigure.areRoundTrip(
          out,
          const UpTheHall(who: WhoSet.ones, moving: HallMoving.center),
        ),
        isFalse,
      );
    });
  });

  group('a round trip refuses what the ruling leaves open', () {
    final cases = <String, Operation>{
      'partners as leaders': trip(
        down(WhoSet.partners, HallEnder.none),
        up(WhoSet.partners, HallEnder.none),
      ),
      'a trade led by a role set': trip(
        down(WhoSet.role1s, HallEnder.turnCouple),
        up(WhoSet.role1s, HallEnder.none),
      ),
      'moving:all': const DownTheHall(
        who: WhoSet.ones,
        ender: HallEnder.none,
      ).pairedWith(up(WhoSet.ones, HallEnder.none)),
      'a line-reshaping ender': trip(
        down(WhoSet.ones, HallEnder.none),
        up(WhoSet.ones, HallEnder.bendTheLine),
      ),
    };
    for (final entry in cases.entries) {
      test('${entry.key} is deferred', () {
        expect(refusal(entry.value, di(base)).kind, ErrorKind.unsupportedParam);
      });
    }
  });

  group('the parser pairs a lead out with the lead back that follows it', () {
    Dance parse(List<Map<String, Object?>> figures) {
      final result = parseDance({
        'title': 't',
        'formation': {'shape': 'dupleImproper'},
        'progression': 'single',
        'figures': figures,
      });
      expect(result, isA<Ok<Dance, DanceParseError>>(), reason: '$result');
      return (result as Ok<Dance, DanceParseError>).value;
    }

    const leadDown = {
      'move': 'down_the_hall',
      'params': {'who': 'ones', 'moving': 'center', 'ender': 'turnAlone'},
    };
    const leadUp = {
      'move': 'up_the_hall',
      'params': {'who': 'ones', 'moving': 'center', 'ender': 'none'},
    };

    test(
      'adjacent: the first dances the trip, the second is its lead back',
      () {
        final dance = parse([leadDown, leadUp]);
        final out = dance.figures[0].operation as HallFigure;
        final back = dance.figures[1].operation as HallFigure;
        expect(out.returnLeg, isNotNull);
        expect(back.isReturnLeg, isTrue);
      },
    );

    test('a figure in between keeps each lead on its own', () {
      final dance = parse([
        leadDown,
        {
          'move': 'balance',
          'params': {'who': 'ones'},
        },
        leadUp,
      ]);
      final out = dance.figures[0].operation as HallFigure;
      final back = dance.figures[2].operation as HallFigure;
      expect(out.returnLeg, isNull);
      expect(back.isReturnLeg, isFalse);
    });
  });
}
