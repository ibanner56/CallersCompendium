import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

Formation becket(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.becketCw);

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
  // The two worked grids of `docs/fundamentals.md` §8.5.1, which are the oracle
  // for every short-wave assertion here.
  final start = di(const [
    'R1-A . . . L1-A',
    'L2-B . . . R2-B',
    'R1-C . . . L1-C',
    'L2-D . . . R2-D',
  ]);

  // §8.5.1 names a wave by the hand the *facing pairs* give; `centerHand` names
  // the centre join, which alternation makes the opposite one. So the doc's
  // "right-hand wave" is `centerHand: left` -- and it sends the Robins in.
  const rightHandWave = FormShortWaves(
    centerHand: Hand.left,
    center: WhoSet.role2s,
  );
  const leftHandWave = FormShortWaves(
    centerHand: Hand.right,
    center: WhoSet.role1s,
  );

  group('form_short_waves: the §8.5.1 worked grids', () {
    test('a right-hand wave sends everyone to their own left', () {
      final after = applyOk(rightHandWave, start);

      expect(after.toRolesNotation(), [
        '. R1-A . . L1-A',
        'L2-B . . R2-B .',
        '. R1-C . . L1-C',
        'L2-D . . R2-D .',
      ]);
    });

    test('a left-hand wave is the exact mirror', () {
      final after = applyOk(leftHandWave, start);

      expect(after.toRolesNotation(), [
        'R1-A . . L1-A .',
        '. L2-B . . R2-B',
        'R1-C . . L1-C .',
        '. L2-D . . R2-D',
      ]);
    });

    test('rows never change and c2 is never occupied', () {
      for (final wave in [rightHandWave, leftHandWave]) {
        final after = applyOk(wave, start);
        for (final entry in after.dancers.entries) {
          expect(
            entry.value.row,
            start.stateOf(entry.key).row,
            reason: '$entry moved rows on $wave',
          );
          expect(entry.value.col, isNot(2), reason: '$entry stood on c2');
        }
      }
    });

    test('the facing pairs end concretely alternating', () {
      final after = applyOk(rightHandWave, start);
      for (final entry in after.dancers.entries) {
        expect(
          entry.value.facing,
          entry.value.row.isEven ? Facing.down : Facing.up,
          reason: '$entry',
        );
      }
    });
  });

  group('form_short_waves: the one bit of geometry', () {
    test('an absent centerHand is derived from the centre pair named', () {
      // No hand stated, and Robins named in the middle: only the right-hand
      // outer join puts them there, so that is the wave built.
      final after = applyOk(const FormShortWaves(center: WhoSet.role2s), start);

      expect(after.toRolesNotation().first, '. R1-A . . L1-A');
    });

    test('a stated centerHand governs, and center is checked against it', () {
      // This is the baseline's own default pair, and it is geometrically
      // impossible from a raw duple-improper start: a right-hand centre join
      // means a left-hand outer join, which sends the Larks in, not the Robins.
      final error = applyErr(
        const FormShortWaves(centerHand: Hand.right, center: WhoSet.role2s),
        start,
      );

      expect(error.kind, ErrorKind.whoMismatch);
      expect(error.message, contains('disagree'));
    });

    test('sides is checked against the pairs actually facing off', () {
      final error = applyErr(
        const FormShortWaves(
          centerHand: Hand.left,
          center: WhoSet.role2s,
          sides: WhoSet.partners,
        ),
        start,
      );

      expect(error.kind, ErrorKind.whoMismatch);
      expect(error.message, contains('face to face'));
    });

    test('the offset is read from facing, not from role', () {
      // Turning a band around and asking for the same wave lands the same
      // arrangement, because the figure faces the band the way the wave needs
      // before reading the offset -- which is exactly why the corpus can carry
      // both (neighbor right, robin left) and (neighbor right, lark left).
      final flipped = start.withUpdates({
        for (final id in start.dancersInRow(0))
          id: start.stateOf(id).copyWith(facing: Facing.up),
        for (final id in start.dancersInRow(1))
          id: start.stateOf(id).copyWith(facing: Facing.down),
      });

      expect(
        applyOk(rightHandWave, flipped).toRolesNotation(),
        applyOk(rightHandWave, start).toRolesNotation(),
      );
    });

    test('a band facing the wrong way warns rather than refusing', () {
      final flipped = start.withUpdates({
        for (final id in start.dancersInRow(0))
          id: start.stateOf(id).copyWith(facing: Facing.up),
      });

      final warnings = rightHandWave.lint(flipped);

      expect(warnings, isNotEmpty);
      expect(warnings.first.kind, WarningKind.facingPrecondition);
    });
  });

  group('form_short_waves: refusals', () {
    test('a diagonal wave is unsupported', () {
      final error = applyErr(
        const FormShortWaves(dir: Direction.rightDiagonal),
        start,
      );
      expect(error.kind, ErrorKind.unsupportedParam);
    });

    test('the formation label does not gate the figure; the dancers do', () {
      // A Becket dance that has manoeuvred into an along-facing arrangement is
      // standing exactly as this figure expects, so it forms waves like any
      // other set. What is read is where the dancers are, not what the dance
      // is called -- `formation.type` is fixed when the dance is loaded and
      // never tracks where a figure has since left people standing.
      final wave = applyOk(
        rightHandWave,
        becket(const ['R1-A . . . L1-A', 'L2-B . . . R2-B']),
      );

      expect(wave.toRolesNotation(), ['. R1-A . . L1-A', 'L2-B . . R2-B .']);
    });

    test('an incomplete set has no hands four to build a wave in', () {
      final error = applyErr(
        const FormShortWaves(),
        di(const ['R1-A . . . L1-A', '. . . . .']),
      );
      expect(error.kind, ErrorKind.unresolvableDancerSet);
    });
  });

  group('form_long_waves: the side waves', () {
    test('nobody moves', () {
      final after = applyOk(const FormLongWaves(), start);
      expect(after.toRolesNotation(), start.toRolesNotation());
    });

    test('who faces in and everyone else faces out, alternating', () {
      final after = applyOk(const FormLongWaves(), start);

      for (final entry in after.dancers.entries) {
        final inward = entry.value.col == 0
            ? Facing.acrossEast
            : Facing.acrossWest;
        final isLark = entry.key.role == Role.lark;
        expect(
          entry.value.facing,
          isLark ? inward : inward.reversed,
          reason: '$entry',
        );
      }
    });

    test('naming the other pair inverts every facing', () {
      final ones = applyOk(const FormLongWaves(), start);
      final twos = applyOk(const FormLongWaves(who: WhoSet.role2s), start);

      for (final entry in twos.dancers.entries) {
        expect(
          entry.value.facing,
          ones.stateOf(entry.key).facing.reversed,
          reason: '$entry',
        );
      }
    });

    test('it settles a short wave on the way in', () {
      final wave = applyOk(rightHandWave, start);
      final after = applyOk(const FormLongWaves(), wave);

      expect(after.toRolesNotation(), start.toRolesNotation());
    });
  });

  group('form_long_waves: whom and hand as anchors', () {
    // In a long wave you hold the dancers *beside* you along your own line,
    // and which side each of your hands is on follows from your facing --
    // which `who` fixes. So naming the hold says the same thing naming the
    // pair does, and the two can be checked against each other.
    //
    // The worked case: from a duple-improper start with the robins facing in,
    // every dancer's right-hand partner is the dancer they share a hands four
    // with. Robins in <=> neighbours by the right.
    const robinsIn = FormLongWaves(who: WhoSet.role2s);
    const heldByTheRight = FormLongWaves(
      whom: WhoSet.neighbors,
      hand: Hand.right,
    );

    test('the hold alone resolves which pair faces in', () {
      // No `who` at all. The baseline would default it to role1s; the anchors
      // say otherwise, and they are right.
      expect(heldByTheRight.resolvedWho(start), WhoSet.role2s);
      expect(
        applyOk(heldByTheRight, start).toRolesNotation(),
        applyOk(robinsIn, start).toRolesNotation(),
      );
      for (final entry in applyOk(heldByTheRight, start).dancers.entries) {
        expect(
          entry.value.facing,
          applyOk(robinsIn, start).stateOf(entry.key).facing,
          reason: '$entry',
        );
      }
    });

    test('and it agrees with the same figure that states both', () {
      const both = FormLongWaves(
        who: WhoSet.role2s,
        whom: WhoSet.neighbors,
        hand: Hand.right,
      );
      expect(both.lint(start), isEmpty);
      expect(both.resolvedWho(start), WhoSet.role2s);
    });

    test('a hold the wave cannot offer is a warning, not a refusal', () {
      // `nextNeighbors` reaches a grouping along the set. Nobody in a long
      // wave is holding hands across that gap -- the dancer beside you is in
      // your own hands four -- so this is impossible from here.
      const impossible = FormLongWaves(
        who: WhoSet.role2s,
        whom: WhoSet.nextNeighbors,
        hand: Hand.right,
      );
      final warnings = impossible.lint(start).toList();

      expect(warnings, hasLength(1));
      expect(warnings.single.kind, WarningKind.anchorMismatch);
      expect(warnings.single.message, contains('nextNeighbors'));
      // The figure never needed the anchor, so the wave is unchanged by it.
      expect(
        applyOk(impossible, start).toRolesNotation(),
        applyOk(robinsIn, start).toRolesNotation(),
      );
      for (final entry in applyOk(impossible, start).dancers.entries) {
        expect(
          entry.value.facing,
          applyOk(robinsIn, start).stateOf(entry.key).facing,
          reason: 'the anchor changed the wave it was only describing: $entry',
        );
      }
    });

    test('naming the other pair makes the same hold wrong', () {
      // The corroboration is real rather than vacuous: `neighbors` by the
      // right is true of the robins-in wave and false of its inverse, so the
      // check discriminates.
      const larksIn = FormLongWaves(
        who: WhoSet.role1s,
        whom: WhoSet.neighbors,
        hand: Hand.right,
      );

      expect(robinsIn.lint(start), isEmpty);
      expect(larksIn.lint(start).map((warning) => warning.kind), [
        WarningKind.anchorMismatch,
      ]);
    });

    test(
      'an anchor that fits neither pair falls back rather than guessing',
      () {
        // Both candidates fail, so there is nothing to resolve. Reading it as
        // either pair would be inventing choreography out of a notation fault;
        // the canonical pair is used and the fault is reported.
        const unfittable = FormLongWaves(
          whom: WhoSet.nextNeighbors,
          hand: Hand.right,
        );

        expect(unfittable.resolvedWho(start), WhoSet.role1s);
        expect(unfittable.lint(start).map((warning) => warning.kind), [
          WarningKind.anchorMismatch,
        ]);
      },
    );

    test('and a figure stating no anchors is never warned about', () {
      expect(const FormLongWaves().lint(start), isEmpty);
      expect(const FormLongWaves().resolvedWho(start), WhoSet.role1s);
      expect(
        const FormLongWaves(hand: Hand.left).lint(start),
        isEmpty,
        reason: 'a hand with no whom asserts nothing that can be falsified',
      );
    });

    test('the anchors do not size the set', () {
      // They used to: `whom` was reported as a dancer set, so naming a
      // distance made the dance ask for a bigger set -- for a figure where
      // nobody moves. An anchor describes the hold, it does not reach for it.
      const reaching = FormLongWaves(
        whom: WhoSet.fourthNeighbors,
        hand: Hand.right,
      );

      expect(reaching.reachAfter(0), 0);
      expect(reaching.dancerSets, isEmpty);
    });
  });

  group('form_a_long_wave: the centre wave', () {
    test('it matches the §8.5.5 worked grid', () {
      final after = applyOk(const FormALongWave(who: WhoSet.role1s), start);

      expect(after.toRolesNotation(), [
        'R1-A . L1-A . .',
        '. . L2-B . R2-B',
        'R1-C . L1-C . .',
        '. . L2-D . R2-D',
      ]);
    });

    test('each mover faces the way they walked, alternating down the set', () {
      final after = applyOk(const FormALongWave(who: WhoSet.role1s), start);

      expect(
        after.stateOf(after.dancerAt(const Position(0, 2))!).facing,
        Facing.acrossWest,
      );
      expect(
        after.stateOf(after.dancerAt(const Position(1, 2))!).facing,
        Facing.acrossEast,
      );
    });

    test('the holders keep their line and their facing', () {
      final after = applyOk(const FormALongWave(who: WhoSet.role1s), start);

      for (final entry in after.dancers.entries) {
        if (entry.value.col == 2) continue;
        expect(entry.value.position, start.stateOf(entry.key).position);
        expect(entry.value.facing, start.stateOf(entry.key).facing);
      }
    });

    test('stepping out is the settling rule, and needs no code of its own', () {
      final centre = applyOk(const FormALongWave(who: WhoSet.role1s), start);
      final after = applyOk(
        const FormALongWave(who: WhoSet.role1s, stepsIn: false, stepsOut: true),
        centre,
      );

      expect(after.toRolesNotation(), start.toRolesNotation());
    });

    test('the other role can take the centre straight over', () {
      final larks = applyOk(const FormALongWave(who: WhoSet.role1s), start);
      final robins = applyOk(const FormALongWave(), larks);

      expect(robins.toRolesNotation(), [
        '. . R1-A . L1-A',
        'L2-B . R2-B . .',
        '. . R1-C . L1-C',
        'L2-D . R2-D . .',
      ]);
    });

    test('a rank that cannot seat the wave is refused, not approximated', () {
      final error = applyErr(
        const FormALongWave(who: WhoSet.role1s),
        di(const ['R1-A . . . L1-A', 'L2-B . . . R2-B', 'R1-C . . . .']),
      );

      expect(error.kind, ErrorKind.unresolvableDancerSet);
      expect(error.message, contains('room for one'));
    });
  });

  group('leaving a wave (§8.5.4)', () {
    test('an ordinary figure settles the offsets before it runs', () {
      final wave = applyOk(rightHandWave, start);
      final after = applyOk(const PassThrough(dir: Direction.across), wave);

      expect(after.toRolesNotation(), [
        'L1-A . . . R1-A',
        'R2-B . . . L2-B',
        'L1-C . . . R1-C',
        'R2-D . . . L2-D',
      ]);
    });

    test('a figure danceable in a wave leaves it standing', () {
      final wave = applyOk(rightHandWave, start);

      for (final identity in <Operation>[const Balance(), const StandStill()]) {
        expect(
          applyOk(identity, wave).toRolesNotation(),
          wave.toRolesNotation(),
          reason: '$identity disturbed the wave',
        );
      }
    });

    test('a figure needing another shape settles the wave first', () {
      final wave = applyOk(rightHandWave, start);

      // Moving nobody is not enough to hold a wave: a ring balance needs hands
      // joined all the way round and long lines are danced in the side lines,
      // so the dancers come out of the wave before either can begin.
      for (final needsShape in <Operation>[
        const BalanceTheRing(),
        const LongLines(),
      ]) {
        expect(
          applyOk(needsShape, wave).toRolesNotation(),
          start.toRolesNotation(),
          reason: '$needsShape danced from a wave it cannot be danced in',
        );
      }
    });

    test('forming short waves twice re-forms rather than compounding', () {
      final once = applyOk(rightHandWave, start);
      final twice = applyOk(rightHandWave, once);

      expect(twice.toRolesNotation(), once.toRolesNotation());
    });

    test('switching hands mid-wave settles first, then offsets the other '
        'way', () {
      final right = applyOk(rightHandWave, start);
      final left = applyOk(leftHandWave, right);

      expect(
        left.toRolesNotation(),
        applyOk(leftHandWave, start).toRolesNotation(),
      );
    });

    test('a line of four is left alone', () {
      // Both shapes use {c0, c1, c3, c4}; the line fills one row and empties
      // the other, and that is what tells them apart.
      final line = di(const ['R1-A L1-A . L2-B R2-B', '. . . . .']);

      expect(applyOk(const StandStill(), line).toRolesNotation(), [
        'R1-A L1-A . L2-B R2-B',
        '. . . . .',
      ]);
    });
  });
}
