import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

/// The base input every worked example in `docs/taxonomy.md` is stated against.
Formation base() => di(const ['R1-A . . . L1-A', 'L2-B . . . R2-B']);

Formation applyOk(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$op failed: $result');
  return (result as Ok<Formation, OpError>).value;
}

OpError applyErr(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Err<Formation, OpError>>(), reason: '$op passed: $result');
  return (result as Err<Formation, OpError>).error;
}

void main() {
  group('down_the_hall — the taxonomy worked examples', () {
    test('the gather is the swing where:sides rule verbatim', () {
      final after = applyOk(const DownTheHall(ender: HallEnder.none), base());
      expect(after.toRolesNotation(), ['R1-A L2-B . R2-B L1-A', '. . . . .']);
      expect(after.dancers.values.map((d) => d.facing).toSet(), {Facing.down});
    });

    test('turnCouple swaps each column pair and reverses facing', () {
      final after = applyOk(
        const DownTheHall(ender: HallEnder.turnCouple),
        base(),
      );
      expect(after.toRolesNotation(), ['. . . . .', 'L2-B R1-A . L1-A R2-B']);
      expect(after.dancers.values.map((d) => d.facing).toSet(), {Facing.up});
    });

    test('turnCouple self-renormalizes: it is swing where:sides face:up', () {
      final viaHall = applyOk(
        const DownTheHall(ender: HallEnder.turnCouple),
        base(),
      );
      final viaSwing = applyOk(
        const Swing(who: WhoSet.neighbors, face: FaceDirection.up),
        base(),
      );
      expect(viaHall.toRolesNotation(), viaSwing.toRolesNotation());
    });

    test('turnAlone preserves slots, leaving the line inverted', () {
      final after = applyOk(
        const DownTheHall(ender: HallEnder.turnAlone),
        base(),
      );
      expect(after.toRolesNotation(), ['. . . . .', 'R1-A L2-B . R2-B L1-A']);
      expect(after.dancers.values.map((d) => d.facing).toSet(), {Facing.up});
    });

    test('slidingDoors swaps the two halves of the line', () {
      final after = applyOk(
        const DownTheHall(ender: HallEnder.slidingDoors),
        base(),
      );
      expect(after.toRolesNotation(), ['. . . . .', 'R2-B L1-A . R1-A L2-B']);
      expect(after.dancers.values.map((d) => d.facing).toSet(), {Facing.up});
    });

    test('bendTheLine folds ends toward travel and centers away', () {
      final after = applyOk(
        const DownTheHall(ender: HallEnder.bendTheLine),
        base(),
      );
      expect(after.toRolesNotation(), ['L2-B . . . R2-B', 'R1-A . . . L1-A']);
    });

    test('bendTheLine lands on the canonical across-in ring', () {
      final viaHall = applyOk(
        const DownTheHall(ender: HallEnder.bendTheLine),
        base(),
      );
      final viaSwing = applyOk(
        const Swing(who: WhoSet.neighbors, face: FaceDirection.towardSet),
        base(),
      );
      expect(viaHall.toRolesNotation(), viaSwing.toRolesNotation());
      for (final entry in viaHall.dancers.entries) {
        expect(entry.value.facing, viaSwing.stateOf(entry.key).facing);
      }
    });

    test('circle is a synonym of bendTheLine', () {
      final bend = applyOk(
        const DownTheHall(ender: HallEnder.bendTheLine),
        base(),
      );
      final circle = applyOk(
        const DownTheHall(ender: HallEnder.circle),
        base(),
      );
      expect(circle.toRolesNotation(), bend.toRolesNotation());
    });

    test('facing:backward gathers into the lower row - facing, not travel', () {
      final after = applyOk(
        const DownTheHall(facing: HallFacing.backward, ender: HallEnder.none),
        base(),
      );
      expect(after.toRolesNotation(), ['. . . . .', 'L2-B R1-A . L1-A R2-B']);
      expect(after.dancers.values.map((d) => d.facing).toSet(), {Facing.up});
    });

    test('facing:backward still bends its ends toward travel', () {
      final after = applyOk(
        const DownTheHall(
          facing: HallFacing.backward,
          ender: HallEnder.bendTheLine,
        ),
        base(),
      );
      // Line is [L2-B, R1-A, _, L1-A, R2-B]; travel is still Down, so the ends
      // L2-B and R2-B land in the lower row.
      expect(after.toRolesNotation(), ['R1-A . . . L1-A', 'L2-B . . . R2-B']);
    });
  });

  group('up_the_hall', () {
    test('the gather is swing where:sides face:up', () {
      final after = applyOk(const UpTheHall(ender: HallEnder.none), base());
      expect(after.toRolesNotation(), ['. . . . .', 'L2-B R1-A . L1-A R2-B']);
    });

    test('bendTheLine places the ends in the upper row', () {
      final after = applyOk(const UpTheHall(), base());
      expect(after.toRolesNotation(), ['L2-B . . . R2-B', 'R1-A . . . L1-A']);
    });

    test('it defaults to the circle ender, unlike down_the_hall', () {
      expect(const UpTheHall().ender, HallEnder.circle);
      expect(const DownTheHall().ender, HallEnder.turnCouple);
    });
  });

  group('hall figures — the conditional gather', () {
    test('down, turn alone, come back does not undo itself', () {
      final down = applyOk(
        const DownTheHall(ender: HallEnder.turnAlone),
        base(),
      );
      final back = applyOk(const UpTheHall(ender: HallEnder.none), down);
      // The line stays inverted: an existing line is passed through untouched
      // rather than re-normalized.
      expect(back.toRolesNotation(), ['. . . . .', 'R1-A L2-B . R2-B L1-A']);
    });

    test('an existing line keeps its slot order through a second hall', () {
      final down = applyOk(
        const DownTheHall(ender: HallEnder.slidingDoors),
        base(),
      );
      final back = applyOk(const UpTheHall(ender: HallEnder.none), down);
      expect(back.toRolesNotation(), down.toRolesNotation());
    });
  });

  group('hall figures — deferred parameters', () {
    test('moving:center is refused rather than approximated', () {
      final error = applyErr(
        const DownTheHall(moving: HallMoving.center),
        base(),
      );
      expect(error.kind, ErrorKind.unsupportedParam);
    });

    test('the four unimplemented enders are refused', () {
      for (final ender in [
        HallEnder.cozy,
        HallEnder.cloverleaf,
        HallEnder.threadNeedle,
        HallEnder.rightHandHigh,
      ]) {
        final error = applyErr(DownTheHall(ender: ender), base());
        expect(error.kind, ErrorKind.unsupportedParam, reason: ender.key);
      }
    });

    test('a scoping narrower than the whole hands four is refused', () {
      final error = applyErr(const DownTheHall(who: WhoSet.ones), base());
      expect(error.kind, ErrorKind.unsupportedParam);
    });
  });

  group('give_and_take — the taxonomy worked example', () {
    test('larks give and take their partner', () {
      final after = applyOk(const GiveAndTake(), base());
      expect(after.toRolesNotation(), ['L2-B . . . R1-A', 'R2-B . . . L1-A']);
    });

    test('robins taking lands the couples on the robins side', () {
      final after = applyOk(const GiveAndTake(who: WhoSet.role2s), base());
      expect(after.toRolesNotation(), ['L1-A . . . R2-B', 'R1-A . . . L2-B']);
    });

    test('take-only is the same permutation', () {
      final give = applyOk(const GiveAndTake(), base());
      final take = applyOk(const GiveAndTake(give: false), base());
      expect(take.toRolesNotation(), give.toRolesNotation());
    });

    test('a pair standing along the set is refused', () {
      final stacked = applyOk(
        const Swing(who: WhoSet.neighbors, face: FaceDirection.towardSet),
        base(),
      );
      final error = applyErr(
        const GiveAndTake(whom: WhoSet.neighbors),
        stacked,
      );
      expect(error.kind, ErrorKind.unresolvableDancerSet);
    });
  });

  group('gate — the taxonomy worked example', () {
    test('a half gate by shared column swaps each column pair', () {
      final after = applyOk(const Gate(turn: 0.5), base());
      expect(after.toRolesNotation(), ['L2-B . . . R2-B', 'R1-A . . . L1-A']);
    });

    test('a half gate inverts facing when none is stated', () {
      final before = base();
      final after = applyOk(const Gate(turn: 0.5), before);
      for (final entry in after.dancers.entries) {
        expect(entry.value.facing, before.stateOf(entry.key).facing.reversed);
      }
    });

    test('a stated face is authoritative over the relative rule', () {
      final after = applyOk(
        const Gate(turn: 0.5, face: GateFace.towardSet),
        base(),
      );
      expect(
        after.stateOf(after.dancerAt(const Position(0, 0))!).facing,
        Facing.acrossEast,
      );
      expect(
        after.stateOf(after.dancerAt(const Position(0, 4))!).facing,
        Facing.acrossWest,
      );
    });

    test('a whole gate leaves everyone home', () {
      final after = applyOk(const Gate(turn: 1), base());
      expect(after.toRolesNotation(), base().toRolesNotation());
    });

    test('an unspecified turn is refused rather than guessed', () {
      final error = applyErr(const Gate(), base());
      expect(error.kind, ErrorKind.unsupportedParam);
    });

    test('a quarter gate is deferred', () {
      final error = applyErr(const Gate(turn: 0.25), base());
      expect(error.kind, ErrorKind.unsupportedParam);
    });
  });

  group('figure_8', () {
    test('a half swaps the actives within their own row', () {
      final after = applyOk(const FigureEight(), base());
      expect(after.toRolesNotation(), ['L1-A . . . R1-A', 'L2-B . . . R2-B']);
    });

    test('the twos swap when they are the actives', () {
      final after = applyOk(const FigureEight(who: WhoSet.twos), base());
      expect(after.toRolesNotation(), ['R1-A . . . L1-A', 'R2-B . . . L2-B']);
    });

    test('a full weave is the identity', () {
      final after = applyOk(const FigureEight(half: TurnFraction.full), base());
      expect(after.toRolesNotation(), base().toRolesNotation());
    });

    test('dir:across is deferred', () {
      final error = applyErr(
        const FigureEight(dir: FigureEightDir.across),
        base(),
      );
      expect(error.kind, ErrorKind.unsupportedParam);
    });

    test('dir is styling: above and below land where none does', () {
      final plain = applyOk(const FigureEight(), base());
      for (final dir in const [FigureEightDir.above, FigureEightDir.below]) {
        final after = applyOk(FigureEight(dir: dir), base());
        expect(
          after.toRolesNotation(),
          plain.toRolesNotation(),
          reason: '$dir',
        );
      }
    });

    test('a quarter weave is refused rather than rounded', () {
      for (final half in const [
        TurnFraction.quarter,
        TurnFraction.threeQuarter,
        TurnFraction.other,
      ]) {
        final error = applyErr(FigureEight(half: half), base());
        expect(error.kind, ErrorKind.unsupportedParam, reason: '$half');
        expect(error.message, contains('half or a full weave'));
      }
    });

    test('an incomplete hands four has no still centre to weave around', () {
      // A line of four empties one row of the band, so there is no stationary
      // couple left standing for the actives to trace their loop about.
      final line = applyOk(const DownTheHall(ender: HallEnder.none), base());
      final error = applyErr(const FigureEight(), line);
      expect(error.kind, ErrorKind.unresolvableDancerSet);
      expect(error.message, contains('not full'));
    });
  });

  group('the oneSidedHall lint', () {
    Dance danceOf(List<Operation> figures) => Dance(
      formation: FormationType.dupleImproper,
      success: const ProgressionCriterion(count: 1),
      figures: [for (final figure in figures) OperationInvocation(figure)],
    );

    List<Warning> warningsFor(List<Operation> figures) =>
        compile(danceOf(figures)).warnings;

    test('a hall figure with no return is flagged', () {
      final warnings = warningsFor([const DownTheHall()]);

      expect(warnings, hasLength(1));
      expect(warnings.single.kind, WarningKind.oneSidedHall);
      expect(warnings.single.opIndex, 0);
      expect(warnings.single.message, contains('down_the_hall'));
    });

    test('a matched pair is not flagged, even when far apart', () {
      expect(
        warningsFor([
          const DownTheHall(),
          const Circle(turn: CircleDirection.left, places: 4),
          const UpTheHall(),
        ]),
        isEmpty,
      );
    });

    test('forwardThenBackward completes the trip inside one figure', () {
      expect(
        warningsFor([
          const DownTheHall(facing: HallFacing.forwardThenBackward),
        ]),
        isEmpty,
      );
    });

    test('the unmatched figure is named, not merely counted', () {
      final warnings = warningsFor([
        const DownTheHall(),
        const UpTheHall(),
        const UpTheHall(),
      ]);

      expect(warnings, hasLength(1));
      expect(warnings.single.opIndex, 2);
      expect(warnings.single.message, contains('up_the_hall'));
    });

    test('a dance with no hall figures is silent', () {
      expect(warningsFor([const Petronella()]), isEmpty);
    });
  });

  group('the hallFacingConflict lint', () {
    /// A band left standing as a line of four facing down the hall.
    Formation lineFacingDown() =>
        applyOk(const DownTheHall(ender: HallEnder.none), base());

    test('travelling against an existing line\'s facing is flagged', () {
      final warnings = const UpTheHall().lint(lineFacingDown()).toList();

      expect(warnings, hasLength(1));
      expect(warnings.single.kind, WarningKind.hallFacingConflict);
      expect(warnings.single.message, contains('up_the_hall'));
      expect(warnings.single.message, contains('down'));
    });

    test('the figure still runs; facing wins mechanically', () {
      final after = applyOk(
        const UpTheHall(ender: HallEnder.none),
        lineFacingDown(),
      );
      expect(after.dancers.values.map((d) => d.facing).toSet(), {Facing.up});
    });

    test('travelling with an existing line\'s facing is silent', () {
      expect(const DownTheHall().lint(lineFacingDown()), isEmpty);
    });

    test('facing:backward wants the line facing against its travel', () {
      // The line faces down, so `up_the_hall facing:backward` -- which backs up
      // the hall -- is exactly what the dancers are already set up for.
      expect(
        const UpTheHall(facing: HallFacing.backward).lint(lineFacingDown()),
        isEmpty,
      );
      expect(
        const DownTheHall(facing: HallFacing.backward).lint(lineFacingDown()),
        hasLength(1),
      );
    });

    test('a band standing across the set has no travel facing to conflict', () {
      // The ordinary case: phase 1 gathers the band into a line itself.
      expect(const UpTheHall().lint(base()), isEmpty);
      expect(const DownTheHall().lint(base()), isEmpty);
    });

    test('the engine stamps the warning with the figure index', () {
      final warnings = compile(
        Dance(
          formation: FormationType.dupleImproper,
          success: const ProgressionCriterion(count: 1),
          figures: [
            OperationInvocation(const DownTheHall(ender: HallEnder.none)),
            OperationInvocation(const UpTheHall(), progression: true),
          ],
        ),
      ).warnings.where((w) => w.kind == WarningKind.hallFacingConflict);

      expect(warnings, hasLength(1));
      expect(warnings.single.opIndex, 1);
    });
  });
}
