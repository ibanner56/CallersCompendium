import 'dart:convert';
import 'dart:io';

import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

/// The Baby Rose — `test/golden/the_baby_rose.json`, a single-progression
/// Duple Improper dance, built as typed objects.
///
/// Constructed by hand rather than parsed because the JSON registry is P7;
/// the figure list here mirrors the fixture's `operations` array exactly.
Dance theBabyRose() => const Dance(
  name: 'The Baby Rose',
  formation: FormationType.dupleImproper,
  success: ProgressionCriterion(),
  figures: [
    OperationInvocation(
      Swing(
        who: WhoSet.neighbors,
        prefix: 'balance',
        where: SwingWhere.sides,
        face: FaceDirection.towardSet,
      ),
    ),
    OperationInvocation(Circle(turn: CircleDirection.left, places: 3)),
    OperationInvocation(DoSiDo(who: WhoSet.partners, circling: 1)),
    OperationInvocation(
      Swing(
        who: WhoSet.partners,
        prefix: 'balance',
        where: SwingWhere.sides,
        face: FaceDirection.towardSet,
      ),
    ),
    OperationInvocation(Chain(who: WhoSet.role2s, dir: ChainDirection.across)),
    OperationInvocation(
      Star(hand: Hand.left, places: 4, grip: 'wrist_grip'),
      progression: true,
    ),
  ],
);

/// The Judge — `test/golden/the_judge.json`, a single-progression Becket CW
/// dance whose chain reaches diagonally (hence three hands four).
Dance theJudge() => const Dance(
  name: 'The Judge',
  formation: FormationType.becketCw,
  success: ProgressionCriterion(),
  figures: [
    OperationInvocation(Circle(turn: CircleDirection.left, places: 3)),
    OperationInvocation(
      Swing(
        who: WhoSet.neighbors,
        where: SwingWhere.sides,
        face: FaceDirection.towardSet,
      ),
    ),
    OperationInvocation(RightLeftThrough()),
    OperationInvocation(
      Chain(who: WhoSet.role2s, dir: ChainDirection.leftDiagonal),
    ),
    OperationInvocation(Petronella()),
    OperationInvocation(Petronella(), progression: true),
    OperationInvocation(
      Swing(
        who: WhoSet.partners,
        prefix: 'balance',
        where: SwingWhere.sides,
        face: FaceDirection.towardSet,
      ),
    ),
  ],
);

/// Runs a dance and reports the per-figure trace when it does not compile, so a
/// failure names the step that diverged rather than just the end state.
void expectCompiles(Dance dance, List<String> expectedTrace) {
  final result = compile(dance);
  if (result is! Compiled) {
    var state = dance.instantiate();
    var progressions = 0;
    final buffer = StringBuffer('${dance.name} did not compile: $result\n');
    buffer.writeln('start: ${state.toRolesNotation()}');
    for (var i = 0; i < dance.figures.length; i++) {
      // Threaded as the engine threads it, so the trace cannot disagree with
      // the compile it is explaining on a dance that names a distance after
      // progressing.
      final step = dance.figures[i].apply(state, progressions: progressions);
      if (step is! Ok<Formation, OpError>) {
        buffer.writeln('op $i ${dance.figures[i]}: $step');
        break;
      }
      state = step.value;
      if (dance.figures[i].progression) progressions++;
      final want = i < expectedTrace.length ? expectedTrace[i] : '(none)';
      buffer.writeln(
        'op $i ${dance.figures[i]}\n'
        '   got  ${state.toRolesNotation()}\n'
        '   want $want',
      );
    }
    fail(buffer.toString());
  }
}

void main() {
  group('The Baby Rose (Duple Improper, single progression)', () {
    test('needs the base two hands four', () {
      expect(theBabyRose().requiredHandsFour, 2);
    });

    test('compiles', () {
      expectCompiles(theBabyRose(), const [
        '[L2-B . . . R2-B, R1-A . . . L1-A, L2-D . . . R2-D, R1-C . . . L1-C]',
        '[R2-B . . . L1-A, L2-B . . . R1-A, R2-D . . . L1-C, L2-D . . . R1-C]',
        '[R2-B . . . L1-A, L2-B . . . R1-A, R2-D . . . L1-C, L2-D . . . R1-C]',
        '[L2-B . . . R1-A, R2-B . . . L1-A, L2-D . . . R1-C, R2-D . . . L1-C]',
        '[L2-B . . . R2-B, R1-A . . . L1-A, L2-D . . . R2-D, R1-C . . . L1-C]',
        '[R1-B . . . L1-B, R1-A . . . L1-A, L2-D . . . R2-D, L2-C . . . R2-C]',
      ]);
    });

    test('lands exactly on the fixture final state', () {
      final result = compile(theBabyRose()) as Compiled;
      expect(result.finalFormation.toRolesNotation(), [
        'R1-B . . . L1-B',
        'R1-A . . . L1-A',
        'L2-D . . . R2-D',
        'L2-C . . . R2-C',
      ]);
    });

    test('every intermediate state matches the fixture trace', () {
      // test/golden/the_baby_rose.json -> trace
      const trace = [
        [
          'L2-B . . . R2-B',
          'R1-A . . . L1-A',
          'L2-D . . . R2-D',
          'R1-C . . . L1-C',
        ],
        [
          'R2-B . . . L1-A',
          'L2-B . . . R1-A',
          'R2-D . . . L1-C',
          'L2-D . . . R1-C',
        ],
        [
          'R2-B . . . L1-A',
          'L2-B . . . R1-A',
          'R2-D . . . L1-C',
          'L2-D . . . R1-C',
        ],
        [
          'L2-B . . . R1-A',
          'R2-B . . . L1-A',
          'L2-D . . . R1-C',
          'R2-D . . . L1-C',
        ],
        [
          'L2-B . . . R2-B',
          'R1-A . . . L1-A',
          'L2-D . . . R2-D',
          'R1-C . . . L1-C',
        ],
        [
          'R1-B . . . L1-B',
          'R1-A . . . L1-A',
          'L2-D . . . R2-D',
          'L2-C . . . R2-C',
        ],
      ];
      final dance = theBabyRose();
      var state = dance.instantiate();
      for (var i = 0; i < dance.figures.length; i++) {
        state = (dance.figures[i].apply(state) as Ok<Formation, OpError>).value;
        expect(
          state.toRolesNotation(),
          trace[i],
          reason: 'op $i (${dance.figures[i]})',
        );
      }
    });
  });

  group('The Judge (Becket CW, single progression)', () {
    test('the diagonal chain buys a third hands four', () {
      expect(theJudge().requiredHandsFour, 3);
    });

    test('compiles', () {
      expectCompiles(theJudge(), const []);
    });

    test('lands exactly on the fixture final state', () {
      final result = compile(theJudge()) as Compiled;
      expect(result.finalFormation.toRolesNotation(), [
        'R1-B . . . L1-B',
        'L2-D . . . R1-A',
        'R2-D . . . L1-A',
        'L2-F . . . R1-C',
        'R2-F . . . L1-C',
        'L2-E . . . R2-E',
      ]);
    });

    test('every intermediate state matches the fixture trace', () {
      // test/golden/the_judge.json -> trace
      const trace = [
        [
          'R1-A . . . L1-A',
          'L2-B . . . R2-B',
          'R1-C . . . L1-C',
          'L2-D . . . R2-D',
          'R1-E . . . L1-E',
          'L2-F . . . R2-F',
        ],
        [
          'L2-B . . . R2-B',
          'R1-A . . . L1-A',
          'L2-D . . . R2-D',
          'R1-C . . . L1-C',
          'L2-F . . . R2-F',
          'R1-E . . . L1-E',
        ],
        [
          'L1-A . . . R1-A',
          'R2-B . . . L2-B',
          'L1-C . . . R1-C',
          'R2-D . . . L2-D',
          'L1-E . . . R1-E',
          'R2-F . . . L2-F',
        ],
        [
          'L1-A . . . R2-D',
          'R2-B . . . L2-B',
          'L1-C . . . R2-F',
          'R1-A . . . L2-D',
          'L1-E . . . R1-E',
          'R1-C . . . L2-F',
        ],
        [
          'R2-D . . . L2-B',
          'L1-A . . . R2-B',
          'R2-F . . . L2-D',
          'L1-C . . . R1-A',
          'R1-E . . . L2-F',
          'L1-E . . . R1-C',
        ],
        [
          'R1-B . . . L1-B',
          'R2-D . . . L1-A',
          'L2-D . . . R1-A',
          'R2-F . . . L1-C',
          'L2-F . . . R1-C',
          'L2-E . . . R2-E',
        ],
        [
          'R1-B . . . L1-B',
          'L2-D . . . R1-A',
          'R2-D . . . L1-A',
          'L2-F . . . R1-C',
          'R2-F . . . L1-C',
          'L2-E . . . R2-E',
        ],
      ];
      final dance = theJudge();
      var state = dance.instantiate();
      for (var i = 0; i < dance.figures.length; i++) {
        state = (dance.figures[i].apply(state) as Ok<Formation, OpError>).value;
        expect(
          state.toRolesNotation(),
          trace[i],
          reason: 'op $i (${dance.figures[i]})',
        );
      }
    });
  });

  group('compile outcomes', () {
    test(
      'a dance that runs but lands elsewhere is a Mismatch, not an error',
      () {
        // Claim a double progression but perform the single the dance really
        // dances: every figure runs, and the set lands one grouping short of
        // the oracle. Dropping the flag entirely would refuse up front instead
        // (`unperformedProgression`), which is a different outcome.
        final dance = Dance(
          name: 'The Baby Rose, claiming double',
          formation: FormationType.dupleImproper,
          success: const ProgressionCriterion(count: 2),
          figures: theBabyRose().figures,
        );
        final result = compile(dance);
        expect(result, isA<Mismatch>());
        expect(result.isSuccess, isFalse);
        final mismatch = result as Mismatch;
        expect(mismatch.actual, isNot(mismatch.expected));
      },
    );

    test('a failed precondition short-circuits and names the figure', () {
      final dance = Dance(
        formation: FormationType.dupleImproper,
        success: const ProgressionCriterion(),
        figures: const [
          // Column-mates at the DI start are neighbours, not partners.
          OperationInvocation(Swing(who: WhoSet.partners)),
          OperationInvocation(
            Circle(turn: CircleDirection.left, places: 1),
            progression: true,
          ),
        ],
      );
      final result = compile(dance);
      expect(result, isA<CompileError>());
      final error = result as CompileError;
      expect(error.opIndex, 0);
      expect(error.opName, 'swing');
      expect(error.kind, ErrorKind.whoMismatch);
    });

    test('an empty figure list cannot perform the progression it claims', () {
      final result = compile(
        const Dance(
          formation: FormationType.dupleImproper,
          success: ProgressionCriterion(),
          figures: [],
        ),
      );
      final error = result as CompileError;
      expect(error.kind, ErrorKind.unperformedProgression);
      // The fault belongs to the figure list, not to any figure in it.
      expect(error.opIndex, isNull);
      expect(error.opName, isNull);
      // And it renders without claiming a figure it cannot name.
      expect(error.toString(), isNot(contains('#')));
    });

    test('compiling twice gives the same answer', () {
      final first = compile(theJudge()) as Compiled;
      final second = compile(theJudge()) as Compiled;
      expect(first.finalFormation, second.finalFormation);
    });
  });

  group('the fixture files drive the same compiles', () {
    // The dances above are built as typed objects so the engine is tested
    // independently of the parser. These tests close the loop: the same dances
    // read from disk, in the real dance-record format, must reach the same
    // place. A drift between the two — a misread parameter, a default that
    // does not match the taxonomy's — shows up here rather than in production.
    Dance parseFixture(String path) {
      final result = parseDanceJson(File(path).readAsStringSync());
      return switch (result) {
        Ok(:final value) => value,
        Err(:final error) => fail('$path did not parse: $error'),
      };
    }

    Formation finalStateOf(Dance dance) {
      final result = compile(dance);
      if (result is! Compiled) fail('${dance.name} did not compile: $result');
      return result.finalFormation;
    }

    test('The Baby Rose', () {
      final parsed = parseFixture('test/golden/the_baby_rose.json');

      expect(parsed.name, 'The Baby Rose');
      expect(parsed.formation, FormationType.dupleImproper);
      expect(parsed.requiredHandsFour, theBabyRose().requiredHandsFour);
      expect(finalStateOf(parsed), finalStateOf(theBabyRose()));
    });

    test('The Judge', () {
      final parsed = parseFixture('test/golden/the_judge.json');

      expect(parsed.name, 'The Judge');
      expect(parsed.formation, FormationType.becketCw);
      expect(parsed.requiredHandsFour, theJudge().requiredHandsFour);
      expect(finalStateOf(parsed), finalStateOf(theJudge()));
    });

    test('The Baby Rose, verbatim from the upstream compendium', () {
      // The record exactly as it is exported upstream, with none of the
      // hand-added parameters the curated fixture carries: no do_si_do
      // shoulder, no chain dir, no star grip. It has to reach the same place,
      // which is what proves the parser's defaults match the taxonomy's rather
      // than only working when every field is spelled out.
      final parsed = parseFixture('test/golden/the_baby_rose_upstream.json');

      expect(parsed.name, 'The Baby Rose');
      expect(parsed.formation, FormationType.dupleImproper);
      expect(parsed.requiredHandsFour, theBabyRose().requiredHandsFour);
      expect(finalStateOf(parsed), finalStateOf(theBabyRose()));
      expect(compile(parsed).isSuccess, isTrue);
    });

    test('Sleepless at Pinewoods reaches out to N4 and walks back', () {
      // The dance that settled the reaching model. Its A1 is a grand right and
      // left out to the fourth neighbours and back in again -- the first
      // record to *chain* reaching figures, and the one that disproved the
      // earlier "the re-band sticks if the figure moved somebody" rule, which
      // cannot retrace: the N4 allemande is a whole turn that moves nobody, so
      // a history-based rule would undo its step out and send the return leg
      // onward instead of back.
      final parsed = parseFixture('test/golden/sleepless_at_pinewoods.json');

      expect(parsed.name, 'Sleepless at Pinewoods');
      expect(parsed.formation, FormationType.dupleImproper);
      expect(compile(parsed).isSuccess, isTrue);
    });

    test("Becky's Brouhaha reaches back to the previous neighbours", () {
      // The first worked example of a set reached *against* the direction of
      // travel. Its A1 boxes the gnat with the neighbours and pulls by, which
      // returns everyone to their own row facing the way they came, so the
      // couple behind is standing in front of them.
      //
      // The allemande that meets them is a *whole turn*, so it puts nobody
      // anywhere new -- this compile would pass whether or not the direction
      // resolved correctly. The assertion carrying the weight is the flipped
      // one below.
      final parsed = parseFixture('test/golden/beckys_brouhaha.json');

      expect(parsed.name, "Becky's Brouhaha");
      expect(compile(parsed).isSuccess, isTrue);
    });

    test('Jet Lag swings the previous neighbours, and it shows', () {
      // The same A1 shape as Becky's, but it *swings* the previous neighbours
      // instead of allemanding them a whole turn, so the resolution has a
      // visible effect on where people end up rather than only on whether the
      // figure was refused.
      final parsed = parseFixture('test/golden/jet_lag.json');

      expect(parsed.name, 'Jet Lag');
      expect(compile(parsed).isSuccess, isTrue);
    });

    test('and both refuse if the direction of the reach is flipped', () {
      // What proves the sign is load-bearing. Reaching stands the same two
      // couples together whichever way it is named; only the sign says whether
      // that is the meeting the choreographer wrote or a mistake. Flip it and
      // both dances refuse rather than quietly dancing the wrong couples.
      for (final path in [
        'test/golden/beckys_brouhaha.json',
        'test/golden/jet_lag.json',
      ]) {
        final flipped = File(
          path,
        ).readAsStringSync().replaceAll('"prevNeighbors"', '"nextNeighbors"');
        final result = switch (parseDanceJson(flipped)) {
          Ok(:final value) => compile(value),
          Err(:final error) => fail('$path did not parse: $error'),
        };

        expect(
          (result as CompileError).kind,
          ErrorKind.whoMismatch,
          reason: path,
        );
      }
    });

    test('reaching to N4 sizes the set, and does not stack', () {
      // Five hands four: the base two, plus the three the fourth neighbours
      // reach. Reach is *transient* -- a figure steps out and steps back -- so
      // the six reaching figures in A1 do not each demand their own room. An
      // earlier version summed them and asked for eleven.
      final parsed = parseFixture('test/golden/sleepless_at_pinewoods.json');

      expect(parsed.requiredHandsFour, 5);
    });

    test('Sleepless at Pinewoods, verbatim from the upstream compendium', () {
      // The Caller's Box record flags no figure as the progression, though it
      // declares a single-progression dance. That is a gap in the source, not
      // a dance that fails to progress: progression is never inferred from the
      // matrix, so the compiler refuses it up front rather than running all
      // eleven figures and blaming the choreography for the mismatch. The
      // curated fixture differs from this one by exactly that one flag.
      final parsed = parseFixture(
        'test/golden/sleepless_at_pinewoods_upstream.json',
      );
      final result = compile(parsed);

      final error = result as CompileError;
      expect(error.kind, ErrorKind.unperformedProgression);
      expect(error.opIndex, isNull);
    });

    // The batch below widens the corpus past the handful of dances the model
    // was built on. Each one is a real imported record, and between them they
    // exercise every figure the registry claims to support outside the
    // deferred list. A dance that merely *compiles* is a weak assertion on its
    // own -- these are here so that a change to any figure's rule has to
    // survive choreography written by someone who had never heard of this
    // compiler.
    const straightforward = <String, ({String file, FormationType formation})>{
      'Harmony Supper Line': (
        file: 'harmony_supper_line',
        formation: FormationType.dupleImproper,
      ),
      'Cinnamon Rolls': (
        file: 'cinnamon_rolls',
        formation: FormationType.becketCw,
      ),
      'A Crafty Wave': (
        file: 'a_crafty_wave',
        formation: FormationType.dupleImproper,
      ),
      'Heartbeat Contra': (
        file: 'heartbeat_contra',
        formation: FormationType.dupleImproper,
      ),
      'Frederick Contra': (
        file: 'frederick_contra',
        formation: FormationType.dupleImproper,
      ),
      'Mirror, Mirror': (
        file: 'mirror_mirror',
        formation: FormationType.dupleImproper,
      ),
    };

    straightforward.forEach((name, dance) {
      test('$name compiles from its imported record', () {
        final parsed = parseFixture('test/golden/${dance.file}.json');

        expect(parsed.name, name);
        expect(parsed.formation, dance.formation);
        // None of these reaches along the set, so none needs room to reach
        // into: the base two hands four is the whole requirement.
        expect(parsed.requiredHandsFour, 2);
        expect(compile(parsed).isSuccess, isTrue, reason: '$name did not land');
      });
    });

    test('Airpants circles three places and then passes through', () {
      // The dance that caught the missing Flexible-facing contract. A circle
      // leaves its dancers mid-ring, so their absolute facing is undetermined
      // until something resolves it -- which is exactly what the pass through
      // that follows does. While `circle` carried each dancer's *previous*
      // facing forward instead, everyone still faced across the set when the
      // pass through asked them to travel along it, and the dance was refused
      // for a facing it should never have been holding.
      final parsed = parseFixture('test/golden/airpants.json');

      expect(parsed.name, 'Airpants');
      expect(compile(parsed).isSuccess, isTrue);
    });

    test('and its closing do si do needs no room to reach', () {
      // The distance-named sets are fixed at the *start* of the dance. Airpants
      // progresses at the pass through and only then dances with the next
      // neighbours -- who, by that point, are the couple it is already standing
      // with. So the reach is spent, not outstanding, and the set does not have
      // to be sized with a spare grouping for it to travel into.
      //
      // Read the other way -- as a reach measured from wherever the dance
      // happens to be standing -- this dance asks for three hands four and then
      // refuses, because it goes looking one grouping past the couple it means.
      final parsed = parseFixture('test/golden/airpants.json');

      expect(parsed.requiredHandsFour, 2);
    });

    test('and naming a further set instead is refused', () {
      // What keeps the rule honest. If the closing figure genuinely reached
      // past the couple in front of it, the record would say so and the
      // compiler would have to find them a grouping further along. Substituting
      // the set one place further out has to be rejected rather than quietly
      // danced, or the absolute reading would be indistinguishable from no
      // reading at all.
      final further = File(
        'test/golden/airpants.json',
      ).readAsStringSync().replaceAll('"nextNeighbors"', '"thirdNeighbors"');
      final result = switch (parseDanceJson(further)) {
        Ok(:final value) => compile(value),
        Err(:final error) => fail('Airpants did not parse: $error'),
      };

      expect((result as CompileError).kind, ErrorKind.whoMismatch);
    });

    test('The Nice Combination compiles once its stray flag is gone', () {
      // The imported record flags *two* figures as the progression -- the A1
      // neighbour swing as well as the closing star -- while declaring a single
      // progression. The swing flag is a notation artifact of the same kind
      // already found in Becky's Brouhaha, and the curated fixture drops it.
      final parsed = parseFixture('test/golden/the_nice_combination.json');

      expect(parsed.name, 'The Nice Combination');
      expect(
        parsed.figures.where((figure) => figure.progression),
        hasLength(1),
      );
      expect(compile(parsed).isSuccess, isTrue);
    });

    test('and putting that flag back lands it one place along', () {
      // Why the artifact had to be removed rather than tolerated. A second
      // progression is not a harmless annotation: it advances the set again, so
      // the dance ends a whole grouping past where a single-progression
      // criterion says it should. It still *runs* -- this is a Mismatch, not a
      // refusal -- which is precisely what makes the stray flag worth pinning.
      final record =
          jsonDecode(
                File(
                  'test/golden/the_nice_combination.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      ((record['figures'] as List).first
              as Map<String, dynamic>)['progression'] =
          true;

      final result = switch (parseDanceJson(jsonEncode(record))) {
        Ok(:final value) => compile(value),
        Err(:final error) => fail('The Nice Combination did not parse: $error'),
      };

      expect(result, isA<Mismatch>());
    });

    test('Poetry in Motion compiles to a single progression', () {
      // The imported record carried `turn: 1.25` on the A2 allemande, which is
      // a notation fault in the source rather than a real figure -- user-ruled
      // to 1.5, so the neighbours trade and the dance runs clean end to end.
      final parsed = parseFixture('test/golden/poetry_in_motion.json');

      expect(parsed.name, 'Poetry in Motion');
      expectCompiles(parsed, const []);
    });

    test('and it lands on the progressed state', () {
      // Every couple moves one rank -- 1s down, 2s up -- and the two that run
      // off the ends turn around and change number: B reaches the top as a 1s
      // couple and E the bottom as a 2s.
      final result = compile(parseFixture('test/golden/poetry_in_motion.json'));

      expect((result as Compiled).finalFormation.toRolesNotation(), const [
        'R1-B . . . L1-B',
        'R1-A . . . L1-A',
        'L2-D . . . R2-D',
        'R1-C . . . L1-C',
        'L2-F . . . R2-F',
        'L2-E . . . R2-E',
      ]);
    });

    test('and it is sized for the reach its A2 names', () {
      // The counterpart to Airpants. This dance names its next neighbours in
      // A2, *before* anything has progressed, so the reach is real and the set
      // has to be big enough to hold the grouping it reaches into.
      final parsed = parseFixture('test/golden/poetry_in_motion.json');

      expect(parsed.requiredHandsFour, 3);
    });

    test('United We Dance slides its long waves both ways', () {
      // The long-wave half of the `rory_o_more` evidence. These dancers face
      // *across* the hall, so the side each of them steps toward is a rank
      // rather than a column, and the slide carries them along the set -- each
      // pair trading ranks within its hands four -- where the short-wave slide
      // carries them across it. One rule, read against each dancer's own
      // facing, covers both.
      final parsed = parseFixture('test/golden/united_we_dance.json');

      expect(parsed.name, 'United We Dance');
      expect(parsed.figures[1].name, 'rory_o_more');
      expectCompiles(parsed, const []);
    });

    test('and its two slides are inverses, so the wave comes back', () {
      // What makes the pair of slides more than decoration: the dance would
      // still compile if both were no-ops, so the assertion that matters is
      // that the first one *moved* people and the second put them back.
      final parsed = parseFixture('test/golden/united_we_dance.json');
      var state = parsed.instantiate();
      for (var i = 0; i <= 2; i++) {
        state =
            (parsed.figures[i].apply(state) as Ok<Formation, OpError>).value;
        if (i == 1) {
          // Ranks traded within each hands four.
          expect(state.toRolesNotation(), const [
            'L2-B . . . R2-B',
            'R1-A . . . L1-A',
            'L2-D . . . R2-D',
            'R1-C . . . L1-C',
          ]);
        }
      }
      expect(state.toRolesNotation(), const [
        'R1-A . . . L1-A',
        'L2-B . . . R2-B',
        'R1-C . . . L1-C',
        'L2-D . . . R2-D',
      ]);
    });

    test('and the slide it cannot take is refused, not silently held', () {
      // The grid boundary is the whole handedness rule. Sliding left first
      // would walk the top rank off the top of the set, and a figure that
      // quietly moved nobody instead is the one outcome this compiler refuses
      // to produce.
      final parsed = parseFixture('test/golden/united_we_dance.json');
      final waves =
          (parsed.figures[0].apply(parsed.instantiate())
                  as Ok<Formation, OpError>)
              .value;

      expect(
        const RoryOMore(slide: Hand.left).apply(waves),
        isA<Err<Formation, OpError>>(),
      );
    });

    test('and its upstream record, whose shape this compiler cannot name', () {
      // The source declares `"shape": "other"`. That is not refused: the shape
      // vocabulary is owned upstream and grows, and this dance's own A1 forms
      // the long waves it dances in, so the arrangement is established by the
      // figure list rather than by the declaration. The record is read as the
      // base formation, warned about, and reaches the same state as the
      // curated twin -- which is what makes the fallback a reading rather than
      // a guess.
      final upstream = parseFixture(
        'test/golden/united_we_dance_upstream.json',
      );
      final result = compile(upstream);

      expect(upstream.formation, FormationType.dupleImproper);
      expect(
        result.warnings.map((warning) => warning.kind),
        contains(WarningKind.unrecognizedFormation),
      );
      expect(result.isSuccess, isTrue);
      expect(
        (result as Compiled).finalFormation.toRolesNotation(),
        (compile(parseFixture('test/golden/united_we_dance.json')) as Compiled)
            .finalFormation
            .toRolesNotation(),
      );
    });

    test('Apples and Caramel slides its short waves and ends in one', () {
      // The short-wave half of the evidence, and the first golden dance to
      // *finish* standing in a wave: its last figure is a quarter-turn do-si-do
      // "to short waves", so the dancers end offset at c1/c3 rather than on the
      // side lines. The progression oracle walks a settled set, so the
      // comparison is made against the settled projection (§8.5.4) -- the wave
      // is where the dance left them, not a different progression.
      final parsed = parseFixture('test/golden/apples_and_caramel.json');

      expect(parsed.name, 'Apples and Caramel');
      expect(parsed.figures[1].name, 'rory_o_more');
      expectCompiles(parsed, const []);
    });

    test('and the wave it ends in is the one it started from', () {
      // Which is what makes the dance a loop: the A1 forms exactly the wave the
      // B2 lands in, so the offsets are the same on both ends.
      final parsed = parseFixture('test/golden/apples_and_caramel.json');
      final opened =
          (parsed.figures[0].apply(parsed.instantiate())
                  as Ok<Formation, OpError>)
              .value;
      final result = compile(parsed) as Compiled;

      expect(opened.toRolesNotation().take(2), const [
        '. R1-A . . L1-A',
        'L2-B . . R2-B .',
      ]);
      expect(result.finalFormation.toRolesNotation(), const [
        'R1-B . . . L1-B',
        '. R1-A . . L1-A',
        'L2-D . . R2-D .',
        'L2-C . . . R2-C',
      ]);
    });

    test('March for Andrea progresses on the B1 California twirl', () {
      // The imported record flags nothing, so on its own it is refused for an
      // unperformed progression; the curated fixture marks the twirl that
      // carries the couples on.
      //
      // It also carried the dance's one real data fault. Its `roll_away` named
      // `nextNeighbors` as `who`, which is *actor context* and has no
      // positional effect, leaving `whom` on its `partners` default -- so the
      // wrong pair traded, and the dance finished with the two active couples
      // mirrored left-for-right. `who: role1s, whom: nextNeighbors` is the
      // figure as called. The distinction is easy to lose in a record and
      // silent when lost, which is why it is worth a golden.
      final parsed = parseFixture('test/golden/march_for_andrea.json');

      expect(parsed.name, 'March for Andrea {alternate}');
      expect(parsed.formation, FormationType.becketCw);
      expect(parsed.figures[6].name, 'california_twirl');
      expect(parsed.figures[6].progression, isTrue);
      expect(compile(parsed).isSuccess, isTrue);
    });

    test('and its roll away needs no room, having already progressed', () {
      // The first Becket record to name a distance set. It names it *after*
      // the progression, so under the absolute reading the gap is already
      // closed and the figure is danced in place -- which is why a Becket
      // dance with a `nextNeighbors` figure still sizes to the base two.
      final parsed = parseFixture('test/golden/march_for_andrea.json');

      expect(parsed.requiredHandsFour, 2);
    });

    // The first record in the golden set to call a hey, and so the first
    // standing check that the weave lands where a full one should. Everything
    // before it is setup the hey depends on: the pass through carries the
    // couples on, the role2s allemande and the short wave set the hey's
    // starting hands, and the partner allemande three quarters puts each
    // dancer on the shoulder the first pass wants.
    //
    // The imported record called the hey a half. The Caller's Box source
    // gives it sixteen beats and seven named passes, which is a full hey --
    // and the record's own `beats: 16` already disagreed with its `length`.
    // The fixture carries the length the source describes.
    test('Last Hey weaves a full hey and lands progressed', () {
      final parsed = parseFixture('test/golden/last_hey.json');

      expect(parsed.name, 'Last Hey');
      expect(parsed.formation, FormationType.becketCw);
      expect(parsed.figures[6].name, 'hey');
      expect(parsed.figures[2].progression, isTrue);
      expect(
        compile(parsed).isSuccess,
        isTrue,
        reason: 'Last Hey did not land',
      );
    });

    test("and the record's second pass is the one the weave derives", () {
      // The record's pass list opens (WL;N2R;...), so its `pass2` is the N2
      // side pass -- a centre dancer meeting an end dancer after the centres
      // have crossed, not the two ends meeting each other. Read as the ends
      // pair it contradicts the geometry, and the dance still compiles but
      // carries a spurious anchor warning, so the absence of one is the
      // assertion here.
      final parsed = parseFixture('test/golden/last_hey.json');

      expect(
        compile(parsed).warnings.map((w) => w.kind),
        isNot(contains(WarningKind.anchorMismatch)),
      );
    });

    test('and a half hey in its place lands the centre couples crossed', () {
      // A *full* hey is a positional identity: every dancer weaves a complete
      // figure of eight and finishes where they began, which is why removing
      // it from this dance would also compile. The assertion that the hey is
      // being danced at all therefore has to come from the other side --
      // shorten it to a half and the two centre couples finish on each
      // other's side of the set, and the dance no longer lands.
      final parsed = parseFixture('test/golden/last_hey.json');
      final hey = parsed.figures[6].operation as HeyForFour;
      final halved = Dance(
        name: parsed.name,
        formation: parsed.formation,
        success: parsed.success,
        figures: [
          ...parsed.figures.take(6),
          OperationInvocation(
            HeyForFour(
              length: HeyLength.half,
              pass1: hey.pass1,
              shoulder: hey.shoulder,
              pass2: hey.pass2,
            ),
          ),
          ...parsed.figures.skip(7),
        ],
      );

      expect(compile(halved), isA<Mismatch>());
    });

    test('and the hey reaches no further than the base two hands four', () {
      // A hey travels the length of the minor set but never past it, so a
      // Becket dance that calls one still sizes to the base two.
      final parsed = parseFixture('test/golden/last_hey.json');

      expect(parsed.requiredHandsFour, 2);
    });
  });
}
