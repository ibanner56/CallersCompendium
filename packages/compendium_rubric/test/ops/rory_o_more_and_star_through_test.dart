import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

/// A settled Duple Improper set of [handsFour] hands four — 1s facing down the
/// hall, 2s facing up, everyone on the side lines.
///
/// Built from the real starting formation rather than from roles notation
/// because `rory_o_more` reads facing, and roles notation defaults every dancer
/// to `flexible`. A wave is *made of* alternating facing, so a fixture that
/// threw facing away could not express one.
Formation start({int handsFour = 1}) =>
    startingFormation(FormationType.dupleImproper, handsFour: handsFour);

Formation ok(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$op failed: $result');
  return (result as Ok<Formation, OpError>).value;
}

OpError err(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Err<Formation, OpError>>(), reason: '$op passed: $result');
  return (result as Err<Formation, OpError>).error;
}

/// The canonical right-hand short wave across the set, reached the way a dance
/// reaches it (`docs/fundamentals.md` §8.5.1).
Formation shortWave() =>
    ok(const FormShortWaves(centerHand: Hand.left), start());

/// Long waves along the two side lines, Robins facing in.
Formation longWaves({int handsFour = 1}) =>
    ok(const FormLongWaves(who: WhoSet.role2s), start(handsFour: handsFour));

const rightSlide = RoryOMore();
const leftSlide = RoryOMore(slide: Hand.left);

void main() {
  group('rory_o_more in a short wave across the set', () {
    // The worked example: the canonical right-hand wave slides right into the
    // mirror wave, and only right. Facing is along the hall here, so each
    // dancer's own side is a column and the slide moves them across.
    test('the canonical wave slides right into the mirror wave', () {
      expect(shortWave().toRolesNotation(), const [
        '. R1-A . . L1-A',
        'L2-B . . R2-B .',
      ]);
      expect(ok(rightSlide, shortWave()).toRolesNotation(), const [
        'R1-A . . L1-A .',
        '. L2-B . . R2-B',
      ]);
    });

    test('and the mirror wave slides left back into it', () {
      final mirror = ok(rightSlide, shortWave());
      expect(
        ok(leftSlide, mirror).toRolesNotation(),
        shortWave().toRolesNotation(),
      );
    });

    // Handedness needs no detection: the slide a wave cannot take is exactly
    // the one that walks a dancer off the matrix.
    test('the canonical wave refuses to slide left', () {
      expect(err(leftSlide, shortWave()).kind, ErrorKind.unresolvableDancerSet);
    });

    test('and the mirror wave refuses to slide right', () {
      final mirror = ok(rightSlide, shortWave());
      expect(err(rightSlide, mirror).kind, ErrorKind.unresolvableDancerSet);
    });

    test('the refusal names the dancer who would leave the set', () {
      expect(err(leftSlide, shortWave()).message, contains('leaves the set'));
    });

    test('a slide leaves every dancer facing the way they were', () {
      final before = shortWave();
      final after = ok(rightSlide, before);
      for (final entry in after.dancers.entries) {
        expect(
          entry.value.facing,
          before.stateOf(entry.key).facing,
          reason: 'the slide turned ${entry.key}',
        );
      }
    });

    test('rows never change — the slide is across the set only', () {
      final before = shortWave();
      final after = ok(rightSlide, before);
      for (final entry in after.dancers.entries) {
        expect(entry.value.row, before.stateOf(entry.key).row);
      }
    });
  });

  group('rory_o_more in long waves along the sides', () {
    // The same rule, and only facing differs: these dancers face across, so
    // their own sides are the ranks and the slide carries them along the set.
    test('sliding right trades ranks within each hands four', () {
      expect(ok(rightSlide, longWaves()).toRolesNotation(), const [
        'L2-B . . . R2-B',
        'R1-A . . . L1-A',
      ]);
    });

    test('and sliding left brings them back', () {
      final slid = ok(rightSlide, longWaves());
      expect(
        ok(leftSlide, slid).toRolesNotation(),
        longWaves().toRolesNotation(),
      );
    });

    test('columns never change — this slide is along the set only', () {
      final before = longWaves(handsFour: 2);
      final after = ok(rightSlide, before);
      for (final entry in after.dancers.entries) {
        expect(entry.value.col, before.stateOf(entry.key).col);
      }
    });

    test(
      'the wave that cannot slide left refuses rather than standing still',
      () {
        expect(
          err(leftSlide, longWaves()).kind,
          ErrorKind.unresolvableDancerSet,
        );
      },
    );
  });

  group('rory_o_more needs a wave', () {
    // User-ruled 2026-11-23: danced from the side lines, facing along the hall,
    // the slide names the wave it is danced from, which is formed first.
    test('from the sides, a slide right forms the right-hand wave first', () {
      expect(
        ok(rightSlide, start()).toRolesNotation(),
        ok(rightSlide, shortWave()).toRolesNotation(),
      );
    });

    test('and a slide left forms the left-hand wave first', () {
      final leftWave = ok(
        const FormShortWaves(center: WhoSet.role1s, centerHand: Hand.right),
        start(),
      );
      expect(
        ok(leftSlide, start()).toRolesNotation(),
        ok(leftSlide, leftWave).toRolesNotation(),
      );
      // The two slides land in different places, so neither test above can
      // pass by both readings forming the same wave.
      expect(
        ok(leftSlide, start()).toRolesNotation(),
        isNot(ok(rightSlide, start()).toRolesNotation()),
      );
    });

    test('a set already in a wave is slid as it stands, not re-formed', () {
      // The canonical right-hand wave cannot slide left; re-forming the
      // left-hand wave first would hide that.
      expect(err(leftSlide, shortWave()).kind, ErrorKind.unresolvableDancerSet);
    });

    test('nobody is turned to make the wave', () {
      // Everyone faces down: the bottom row would have to about-face to join
      // the wave, which no record said, so the slide refuses as before.
      final down = start().withUpdates({
        for (final entry in start().dancers.entries)
          entry.key: entry.value.copyWith(facing: Facing.down),
      });
      expect(err(rightSlide, down).kind, ErrorKind.unresolvableDancerSet);
    });

    test('a couple standing out at an end does not slide or step in', () {
      // §10.3.2: outside every hands four, never taken out of its end row
      // (only a distance swing turns it in place). Rows 0
      // and 3 stand out facing in; the one hands four between them faces
      // across its band, ready for the wave.
      final two = start(handsFour: 2);
      final set = two.withUpdates({
        for (final entry in two.dancers.entries)
          entry.key: entry.value.copyWith(
            waitingOut: entry.value.row == 0 || entry.value.row == 3,
            facing: entry.value.row <= 1 ? Facing.down : Facing.up,
          ),
      });
      expect(handsFourBands(set).map((b) => (b.topRow, b.bottomRow)), [(1, 2)]);
      final slid = ok(rightSlide, set);
      for (final id in set.dancers.keys) {
        final before = set.stateOf(id);
        if (!before.waitingOut) continue;
        expect(slid.stateOf(id), before, reason: '$id is standing out');
      }
      // The hands four itself did dance the figure.
      expect(slid.dancersInRow(1).map((id) => slid.stateOf(id).position.col), [
        0,
        3,
      ]);
    });

    test('dancers on the sides facing across are not given a short wave', () {
      // Facing across, their sides are ranks: the long-wave slide, along the
      // set, with nobody leaving the side lines.
      final slid = ok(rightSlide, longWaves());
      for (final state in slid.dancers.values) {
        expect(state.col, anyOf(0, kColumnCount - 1));
      }
    });

    test('a dancer with no settled facing has no side to slide toward', () {
      final flexible = parseRolesNotation(const [
        '. R1-A . . L1-A',
        'L2-B . . R2-B .',
      ], type: FormationType.dupleImproper);
      expect(err(rightSlide, flexible).kind, ErrorKind.unresolvableDancerSet);
    });
  });

  group('rory_o_more reads the wave rather than settling it away', () {
    // §8.5.4: the figure has no meaning outside a wave, so it preserves the
    // offsets, as `balance`, `stand_still` and a quarter `allemande` do.
    test('it declares that it preserves the wave offsets', () {
      expect(rightSlide.preservesWaveOffsets, isTrue);
      expect(const Balance().preservesWaveOffsets, isTrue);
      expect(const StandStill().preservesWaveOffsets, isTrue);
    });

    test('a figure that settles first would see the columns instead', () {
      // The proof the flag is load-bearing: `pass_through` is handed the
      // settled set, so the wave it was given is gone before it runs.
      expect(ok(const PassThrough(), shortWave()).toRolesNotation(), const [
        'L2-B . . . R2-B',
        'R1-A . . . L1-A',
      ]);
    });
  });

  group('rory_o_more scoped to some of the wave', () {
    test('naming one role slides only that role', () {
      final after = ok(const RoryOMore(who: WhoSet.role1s), shortWave());
      // Each Lark steps toward their own right, which the two of them face
      // opposite ways to find; the Robins hold the cells they were standing in.
      expect(after.toRolesNotation(), const [
        '. R1-A . L1-A .',
        '. L2-B . R2-B .',
      ]);
    });

    test('naming the other role slides the wave back onto the side lines', () {
      expect(
        ok(const RoryOMore(who: WhoSet.role2s), shortWave()).toRolesNotation(),
        const ['R1-A . . . L1-A', 'L2-B . . . R2-B'],
      );
    });

    test('a slide onto a dancer standing still is refused, not overwritten', () {
      // A Lark whose step lands on a Robin who was not named. Formation's own
      // projection would throw on the shared cell; refusing here reports it as
      // the dance error it is.
      final blocked = parseRolesNotation(
        const ['. R1-A L1-A . .', '. L2-B . R2-B .'],
        type: FormationType.dupleImproper,
        defaultFacing: Facing.down,
      );
      final error = err(const RoryOMore(who: WhoSet.role1s), blocked);
      expect(error.kind, ErrorKind.unresolvableDancerSet);
      expect(error.message, contains('cannot share a cell'));
    });
  });

  group('star_through — the couple wheel that finishes facing in', () {
    test('it moves the couple exactly as a california twirl does', () {
      final wheeled = ok(const CaliforniaTwirl(), start());
      final starred = ok(const StarThrough(), start());
      expect(starred.toRolesNotation(), wheeled.toRolesNotation());
    });

    test('but a couple across the set finishes facing into the hands four', () {
      final after = ok(const StarThrough(), start());
      for (final entry in after.dancers.entries) {
        expect(
          entry.value.facing,
          entry.value.row == 0 ? Facing.down : Facing.up,
          reason: '${entry.key} did not finish facing the other rank',
        );
      }
    });

    test('which is where a california twirl would have faced them out', () {
      final before = start();
      final after = ok(const CaliforniaTwirl(), before);
      for (final entry in after.dancers.entries) {
        expect(entry.value.facing, before.stateOf(entry.key).facing.reversed);
      }
    });

    test('both dancers of a couple finish facing the same way', () {
      final after = ok(const StarThrough(), start(handsFour: 2));
      for (final row in [0, 1, 2, 3]) {
        final facings = {
          for (final id in after.dancersInRow(row)) after.stateOf(id).facing,
        };
        expect(facings, hasLength(1), reason: 'rank $row finished split');
      }
    });

    test(
      'a couple along the set finishes facing across, toward the centre',
      () {
        // Column-mates rather than row-mates: the Becket case, reached here by
        // naming the pair the side columns actually hold.
        final after = ok(const StarThrough(who: WhoSet.neighbors), start());
        for (final entry in after.dancers.entries) {
          expect(
            entry.value.facing,
            entry.value.col == 0 ? Facing.acrossEast : Facing.acrossWest,
            reason: '${entry.key} did not finish facing the centre column',
          );
        }
      },
    );

    test('and it still refuses a couple standing diagonally', () {
      final diagonal = parseRolesNotation(const [
        'R1-A . . . .',
        '. . . . L1-A',
      ], type: FormationType.dupleImproper);
      expect(
        err(const StarThrough(), diagonal).kind,
        ErrorKind.unresolvableDancerSet,
      );
    });
  });

  group('pass_the_ocean — the pass across and the wave it lands in', () {
    /// The worked example's entry state: the row-swapped Duple Improper set,
    /// with everyone facing across the hall the way this figure asks for.
    Formation acrossTheSet() =>
        parseRolesNotation(const [
          'L2-B . . . R2-B',
          'R1-A . . . L1-A',
        ], type: FormationType.dupleImproper).mapDancers(
          (id, state) => state.copyWith(
            facing: state.col == 0 ? Facing.acrossEast : Facing.acrossWest,
          ),
        );

    test('everyone crosses over and the set lands in the stated wave', () {
      expect(
        ok(
          const PassTheOcean(centerHand: Hand.left),
          acrossTheSet(),
        ).toRolesNotation(),
        const ['. R2-B . . L2-B', 'L1-A . . R1-A .'],
      );
    });

    test('rows never change across the figure', () {
      final before = acrossTheSet();
      final after = ok(const PassTheOcean(centerHand: Hand.left), before);
      for (final entry in after.dancers.entries) {
        expect(
          entry.value.row,
          before.stateOf(entry.key).row,
          reason: '${entry.key} changed rank',
        );
      }
    });

    test('the stated hand picks the wave, not the way the set arrived', () {
      // The mirror of the case above, from the same entry state. If the offset
      // still followed the facing the dancers walked in with, this would come
      // out identical to it. `center` moves with the hand because the two name
      // the same bit of geometry, and form_short_waves checks them against
      // each other.
      expect(
        ok(
          const PassTheOcean(centerHand: Hand.right, center: WhoSet.role1s),
          acrossTheSet(),
        ).toRolesNotation(),
        const ['R2-B . . L2-B .', '. L1-A . . R1-A'],
      );
    });

    test('the wave it lands in is the one form_short_waves would build', () {
      final passed = ok(
        const PassThrough(dir: Direction.across),
        acrossTheSet(),
      );
      final waved = ok(const FormShortWaves(centerHand: Hand.left), passed);
      expect(
        ok(
          const PassTheOcean(centerHand: Hand.left),
          acrossTheSet(),
        ).toRolesNotation(),
        waved.toRolesNotation(),
      );
    });

    test('an across-facing set draws no warning', () {
      expect(
        const PassTheOcean(centerHand: Hand.left).lint(acrossTheSet()),
        isEmpty,
      );
    });

    test('a set facing along the hall is warned about, never refused', () {
      // Facing is only ever a warning in this compiler. The figure still runs.
      const figure = PassTheOcean(centerHand: Hand.left, center: WhoSet.role1s);
      final along = start();
      final warnings = figure.lint(along);
      expect(warnings, hasLength(1));
      expect(warnings.single.kind, WarningKind.facingPrecondition);
      expect(figure.apply(along), isA<Ok<Formation, OpError>>());
    });
  });
}
