import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation becket(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.becketCw);

Formation slide(Formation input, {SlideDirection dir = SlideDirection.left}) {
  final result = SlideAlongSet(slide: dir).apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$result');
  return (result as Ok<Formation, OpError>).value;
}

/// The slide plus the end-normalization a progression-flagged figure triggers.
Formation slideProgressing(
  Formation input, {
  SlideDirection dir = SlideDirection.left,
}) {
  final result = OperationInvocation(
    SlideAlongSet(slide: dir),
    progression: true,
  ).apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$result');
  return (result as Ok<Formation, OpError>).value;
}

/// The rows each hands four is drawn from, as `handsFourBands` sees them.
List<List<int>> bandRows(Formation formation) => [
  for (final band in handsFourBands(formation)) [band.topRow, band.bottomRow],
];

void main() {
  // The canonical two-hands-four Becket start, which every worked example on
  // record is stated against.
  final becketStart = startingFormation(FormationType.becketCw, handsFour: 2);

  group('slide_along_set: the mechanic', () {
    test('slide left carries the west line up and the east line down', () {
      // Nobody rounds an end here, so this isolates the plain column shift.
      final after = slide(becketStart);
      final before = becketStart;

      for (final entry in after.dancers.entries) {
        final from = before.stateOf(entry.key).position;
        final to = entry.value.position;
        if (from.col != to.col) continue; // rounded the end; checked below.
        expect(
          to.row - from.row,
          from.col == Position.westColumn ? -1 : 1,
          reason: '${entry.key} moved wrong',
        );
      }
    });

    test('a dancer pushed off an end rounds it into the other line', () {
      final after = slide(becketStart);

      // L2-B started at the top of the west line, which slide left pushes off
      // the top of the set; L1-C started at the bottom of the east line, which
      // it pushes off the bottom.
      const topOfWest = DancerId(1, Role.lark); // L2-B
      const bottomOfEast = DancerId(2, Role.lark); // L1-C

      expect(becketStart.stateOf(topOfWest).position, const Position(0, 0));
      expect(
        after.stateOf(topOfWest).position,
        const Position(0, Position.eastColumn),
      );

      expect(becketStart.stateOf(bottomOfEast).position, const Position(3, 4));
      expect(
        after.stateOf(bottomOfEast).position,
        const Position(3, Position.westColumn),
      );
    });

    test('rounding the end does not change facing', () {
      final after = slide(becketStart);
      for (final entry in after.dancers.entries) {
        expect(
          entry.value.facing,
          becketStart.stateOf(entry.key).facing,
          reason: 'the slide itself must not rewrite ${entry.key}\'s facing',
        );
      }
    });

    test('slide right is the exact mirror of slide left', () {
      expect(slide(becketStart, dir: SlideDirection.right).toRolesNotation(), [
        'R1-A . . . L1-A',
        'L2-B . . . R1-C',
        'R2-B . . . L1-C',
        'L2-D . . . R2-D',
      ]);
    });

    test('sliding left then right returns the set exactly as it was', () {
      final there = slide(becketStart);
      final back = slide(there, dir: SlideDirection.right);

      expect(back.toRolesNotation(), becketStart.toRolesNotation());
      expect(waitingOutRows(back).toSet(), waitingOutRows(becketStart).toSet());
    });
  });

  group('slide_along_set: re-banding', () {
    test('a slide from a settled set strands both end rows', () {
      expect(waitingOutRows(becketStart), isEmpty);

      final after = slide(becketStart);
      expect(waitingOutRows(after).toSet(), {0, 3});
      expect(bandRows(after), [
        [1, 2],
      ]);
    });

    test('a second slide brings the stranded couples back in', () {
      // The user's third worked example: two consecutive slides. Couples that
      // are already out do not trade places with a fresh pair going out --
      // they become a hands four with whoever has just arrived beside them.
      final once = slideProgressing(becketStart);
      expect(waitingOutRows(once).toSet(), {0, 3});

      final twice = slide(once);
      expect(waitingOutRows(twice), isEmpty);
      expect(bandRows(twice), [
        [0, 1],
        [2, 3],
      ]);
      expect(twice.toRolesNotation(), [
        'L2-D . . . R1-B',
        'R2-D . . . L1-B',
        'L2-C . . . R1-A',
        'R2-C . . . L1-A',
      ]);
    });

    test('out-ness comes from the phase, not from who lands at the end', () {
      // Here neither end row collects a whole couple, yet both are out.
      final after = slide(
        becket(const [
          'L2-B . . . R2-B',
          'R1-A . . . L1-A',
          'L2-D . . . R2-D',
          'R1-C . . . L1-C',
        ]),
      );

      expect(waitingOutRows(after).toSet(), {0, 3});
      expect(after.toRolesNotation().first, 'R1-A . . . L2-B');
    });
  });

  group('slide_along_set: worked examples', () {
    test('example 1 -- Becket, progression-flagged', () {
      final after = slideProgressing(becketStart);

      expect(after.toRolesNotation(), [
        'R1-B . . . L1-B',
        'L2-D . . . R1-A',
        'R2-D . . . L1-A',
        'L2-C . . . R2-C',
      ]);
      expect(waitingOutRows(after).toSet(), {0, 3});
      expect(bandRows(after), [
        [1, 2],
      ]);
    });

    test('example 1 -- the raw slide, before end-normalization', () {
      expect(slide(becketStart).toRolesNotation(), [
        'R2-B . . . L2-B',
        'L2-D . . . R1-A',
        'R2-D . . . L1-A',
        'L1-C . . . R1-C',
      ]);
    });

    test('example 1 -- the couples collected at the ends take end numbers', () {
      final after = slideProgressing(becketStart);

      // Couple B collected at the top, so B is now a 1s couple facing down.
      const larkB = DancerId(1, Role.lark);
      const robinB = DancerId(1, Role.robin);
      expect(after.stateOf(larkB).number, CoupleNumber.one);
      expect(after.stateOf(robinB).number, CoupleNumber.one);
      expect(after.stateOf(larkB).facing, Facing.down);

      // Couple C collected at the bottom, so C is now a 2s couple facing up.
      const larkC = DancerId(2, Role.lark);
      expect(after.stateOf(larkC).number, CoupleNumber.two);
      expect(after.stateOf(larkC).facing, Facing.up);
    });

    test('example 2 -- unflagged, so nothing is renumbered or turned', () {
      final before = becket(const [
        'L2-B . . . R2-B',
        'R1-A . . . L1-A',
        'L2-D . . . R2-D',
        'R1-C . . . L1-C',
      ]);
      final after = slide(before);

      expect(after.toRolesNotation(), [
        'R1-A . . . L2-B',
        'L2-D . . . R2-B',
        'R1-C . . . L1-A',
        'L1-C . . . R2-D',
      ]);

      // The hands four after the slide begins at row 1.
      expect(bandRows(after), [
        [1, 2],
      ]);

      for (final entry in after.dancers.entries) {
        expect(entry.value.number, before.stateOf(entry.key).number);
        expect(entry.value.facing, before.stateOf(entry.key).facing);
      }
    });

    test('example 3 -- a flagged second slide lands the same as an unflagged '
        'one, because neither end row holds a whole couple', () {
      final once = slideProgressing(becketStart);

      expect(
        slideProgressing(once).toRolesNotation(),
        slide(once).toRolesNotation(),
      );
      expect(waitingOutRows(slideProgressing(once)), isEmpty);
    });
  });

  group('slide_along_set: against the section 10.6 oracle', () {
    Dance slideDance(int count) => Dance(
      formation: FormationType.becketCw,
      success: ProgressionCriterion(count: count),
      figures: [
        for (var i = 0; i < count; i++)
          OperationInvocation(const SlideAlongSet(), progression: true),
      ],
    );

    test('one flagged slide is one Becket CW progression', () {
      expect(compile(slideDance(1)), isA<Compiled>());
    });

    test('two flagged slides are a double progression', () {
      expect(compile(slideDance(2)), isA<Compiled>());
    });
  });

  group('slide_along_set: refusals', () {
    test('a line of four has no side lines to slide', () {
      final lineOfFour = becket(const ['R1-A L1-A . L2-B R2-B', '. . . . .']);
      final result = const SlideAlongSet().apply(lineOfFour);

      expect(result, isA<Err<Formation, OpError>>());
      expect(
        (result as Err<Formation, OpError>).error.kind,
        ErrorKind.unresolvableDancerSet,
      );
      expect(result.error.message, contains('centre column'));
    });

    // The other way a dancer lands off the side columns is a wave offset, and
    // that one is *not* a refusal: fundamentals §8.5.4 settles it on the way in,
    // so the slide sees the side lines it needs. The two shapes are told apart
    // by the row count -- a line fills one row and empties the other.
    test('a wave settles out to the sides and slides', () {
      final wave = becket(const ['. R1-A . L1-A .', '. L2-B . R2-B .']);
      final result = const SlideAlongSet().apply(wave);

      expect(result, isA<Ok<Formation, OpError>>());
      expect((result as Ok<Formation, OpError>).value.toRolesNotation(), [
        'L2-B . . . R1-A',
        'R2-B . . . L1-A',
      ]);
    });
  });

  group('slide_along_set: shape', () {
    test('it expands the set by one hands four', () {
      expect(const SlideAlongSet().hands4Contribution, 1);
    });

    test('it may carry the progression flag', () {
      expect(const SlideAlongSet().progressionEligible, isTrue);
    });

    test('direction round-trips through its wire key', () {
      for (final value in SlideDirection.values) {
        expect(SlideDirection.fromKey(value.key), value);
      }
      expect(SlideDirection.fromKey('sideways'), isNull);
    });
  });
}
