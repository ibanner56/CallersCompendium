import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation duple(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

/// Renders [formation] back into the roles notation, so a worked example can be
/// asserted as the grid it was written down as rather than cell by cell.
List<String> render(Formation formation) => [
  for (var row = 0; row < formation.rowCount; row++)
    [
      for (var col = 0; col < kColumnCount; col++)
        switch (formation.dancerAt(Position(row, col))) {
          null => '.',
          final id =>
            '${id.role == Role.lark ? 'L' : 'R'}'
                '${formation.stateOf(id).number == CoupleNumber.one ? 1 : 2}'
                '-${String.fromCharCode(0x41 + id.coupleIndex)}',
        },
    ].join(' '),
];

/// The rows each hands four is drawn from, as `handsFourBands` sees them.
List<List<int>> bandRows(Formation formation) => [
  for (final band in handsFourBands(formation)) [band.topRow, band.bottomRow],
];

Formation applyOk(Operation op, Formation input, {bool progression = false}) {
  final result = OperationInvocation(op, progression: progression).apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$result');
  return (result as Ok<Formation, OpError>).value;
}

OpError applyErr(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Err<Formation, OpError>>(), reason: '$result');
  return (result as Err<Formation, OpError>).error;
}

void main() {
  // Three hands four of Duple Improper after a `pass_through along`, which
  // swaps the rows within each band. This is the state the worked examples on
  // record are stated against: it is the shape in which each dancer's *next*
  // neighbours are standing beside them, which is the whole precondition for
  // dancing a figure with them.
  //
  //   r0  B alone at the top       r1/r2  A and D as column-mates
  //   r3/r4  C and F               r5     E alone at the bottom
  final passedThrough = duple([
    'L2-B . . . R2-B',
    'R1-A . . . L1-A',
    'L2-D . . . R2-D',
    'R1-C . . . L1-C',
    'L2-F . . . R2-F',
    'R1-E . . . L1-E',
  ]);

  // The same three hands four before the pass through: the ordinary starting
  // shape, in which A's next neighbours (D) are two rows away.
  final start = startingFormation(FormationType.dupleImproper, handsFour: 3);

  group('nextNeighbors: reaching the next grouping', () {
    test('the set is danced in the other phase, which is then handed back', () {
      // A settled set bands (0,1), (2,3), (4,5); reaching one grouping on moves
      // the boundaries to (1,2) and (3,4), which is where A meets D and C meets
      // F. But reaching is transient -- you step out to meet them and step back
      // -- so the phase the figure was handed is the phase it returns.
      expect(bandRows(passedThrough), [
        [0, 1],
        [2, 3],
        [4, 5],
      ]);

      final after = applyOk(
        const Swing(who: WhoSet.nextNeighbors),
        passedThrough,
      );

      expect(waitingOutRows(after), isEmpty);
      expect(bandRows(after), bandRows(passedThrough));
    });

    test('the couples that swing are the ones a grouping apart', () {
      final after = applyOk(
        const Swing(who: WhoSet.nextNeighbors),
        passedThrough,
      );

      int rowOf(int couple, Role role) =>
          after.stateOf(DancerId(couple, role)).position.row;

      // A (0) with D (3) in the upper band, C (2) with F (5) in the lower.
      for (final couple in [0, 3]) {
        for (final role in Role.values) {
          expect(rowOf(couple, role), anyOf(1, 2), reason: 'couple $couple');
        }
      }
      for (final couple in [2, 5]) {
        for (final role in Role.values) {
          expect(rowOf(couple, role), anyOf(3, 4), reason: 'couple $couple');
        }
      }
    });

    test('the couples stranded at the ends are left where they stand', () {
      // B and E are outside every active hands four while the set is reaching,
      // so no figure's transform touches them -- and because the reach is
      // handed back, they are not left marked out afterwards either.
      final after = applyOk(
        const Swing(who: WhoSet.nextNeighbors),
        passedThrough,
      );

      for (final couple in [1, 4]) {
        for (final role in Role.values) {
          final id = DancerId(couple, role);
          expect(
            after.stateOf(id).position,
            passedThrough.stateOf(id).position,
            reason: '$id',
          );
          expect(after.stateOf(id).waitingOut, isFalse, reason: '$id');
        }
      }
    });
  });

  group('nextNeighbors: the worked allemande', () {
    // An allemande 1.5 with the next neighbours, flagged as the progression.
    // `1.5` lands in the half bucket, so it exchanges the pair.
    Formation run({bool progression = false}) => applyOk(
      const Allemande(who: WhoSet.nextNeighbors, turn: 1.5),
      passedThrough,
      progression: progression,
    );

    test('flagged as the progression it reproduces the recorded grid', () {
      expect(render(run(progression: true)), [
        'R1-B . . . L1-B',
        'L2-D . . . R2-D',
        'R1-A . . . L1-A',
        'L2-F . . . R2-F',
        'R1-C . . . L1-C',
        'L2-E . . . R2-E',
      ]);
    });

    test('and leaves the hands four beginning from row 0, nobody out', () {
      final after = run(progression: true);

      expect(waitingOutRows(after), isEmpty);
      expect(bandRows(after), [
        [0, 1],
        [2, 3],
        [4, 5],
      ]);
    });

    test('the ends take their end numbers on the way through', () {
      // B arrives at the top as a #2 couple and leaves it as a #1; E does the
      // reverse at the bottom. That is the end-normalization firing, and it
      // fires even though the double re-band puts them straight back in.
      final after = run(progression: true);

      for (final role in Role.values) {
        expect(
          passedThrough.stateOf(DancerId(1, role)).number,
          CoupleNumber.two,
        );
        expect(after.stateOf(DancerId(1, role)).number, CoupleNumber.one);
        expect(
          passedThrough.stateOf(DancerId(4, role)).number,
          CoupleNumber.one,
        );
        expect(after.stateOf(DancerId(4, role)).number, CoupleNumber.two);
      }
    });

    test('unflagged, the reach is handed back and nobody is left out', () {
      // The contrast that makes the flagged double advance visible: the same
      // figure without the progression flag returns the phase it borrowed.
      final after = run();

      expect(waitingOutRows(after), isEmpty);
      expect(bandRows(after), [
        [0, 1],
        [2, 3],
        [4, 5],
      ]);
    });
  });

  group('nextNeighbors: reaching is transient, not a re-band that sticks', () {
    test('a whole-turn shoulder round leaves the band grid where it was', () {
      // Poetry in Motion's third figure. The point of it is to face the couple
      // you are about to meet, not to travel.
      final after = applyOk(
        const ShoulderRound(who: WhoSet.nextNeighbors),
        passedThrough,
      );

      expect(waitingOutRows(after), isEmpty);
      expect(bandRows(after), bandRows(passedThrough));
      for (final entry in passedThrough.dancers.entries) {
        expect(
          after.stateOf(entry.key).position,
          entry.value.position,
          reason: '${entry.key}',
        );
      }
    });

    test('and so does a half turn, which does move them', () {
      // The old rule toggled the phase and kept it whenever the transform had
      // moved somebody. That cannot retrace: Sleepless at Pinewoods reaches out
      // to the fourth neighbours with a figure that moves nobody, then walks
      // back in, and a history-based rule sends it onward instead. Parity is
      // what makes the return leg land.
      final after = applyOk(
        const ShoulderRound(who: WhoSet.nextNeighbors, turn: 0.5),
        passedThrough,
      );

      expect(waitingOutRows(after), isEmpty);
      expect(bandRows(after), bandRows(passedThrough));
    });
  });

  group('nextNeighbors: refusals', () {
    test('a set whose next neighbours are not yet in position is refused', () {
      // From the ordinary start, re-banding stands B beside C -- who are
      // nobody's next neighbours. The figure is refused rather than danced
      // with whoever happens to be there.
      for (final op in <Operation>[
        const Swing(who: WhoSet.nextNeighbors),
        const Allemande(who: WhoSet.nextNeighbors, turn: 0.5),
        const ShoulderRound(who: WhoSet.nextNeighbors),
        const GiveAndTake(whom: WhoSet.nextNeighbors),
      ]) {
        final error = applyErr(op, start);
        expect(error.kind, ErrorKind.whoMismatch, reason: '$op');
        expect(error.detail, contains('nextNeighbors'), reason: '$op');
      }
    });

    test('the sets reached backward resolve the other way', () {
      // prevNeighbors is refused here, and nextNeighbors is not. The mirror of
      // this pair of assertions is in the prevNeighbors group below, against
      // the state those dances actually reach. Together they prove the sign is
      // load-bearing rather than decorative: each direction refuses exactly
      // where the other one dances.
      final error = applyErr(
        const Swing(who: WhoSet.prevNeighbors),
        passedThrough,
      );

      expect(error.kind, ErrorKind.whoMismatch);
      expect(error.detail, contains('prevNeighbors'));
    });

    test('a couple standing beside the wrong distance away is refused', () {
      // The check that survives travel. B and A started in the same grouping,
      // so whatever else they are to each other they are not third neighbours,
      // and naming them so is refused rather than danced.
      final error = applyErr(
        const Swing(who: WhoSet.thirdNeighbors),
        passedThrough,
      );

      expect(error.kind, ErrorKind.whoMismatch);
      expect(error.detail, contains('started 0 grouping(s) apart'));
    });

    test('a figure naming two different distances is refused', () {
      // Re-banding puts the set into one phase, which can satisfy one
      // distance. Naming two would ask for the figure to be danced in two
      // places at once, so it is refused rather than quietly honouring one.
      final error = applyErr(
        const GiveAndTake(
          who: WhoSet.nextNeighbors,
          whom: WhoSet.thirdNeighbors,
        ),
        passedThrough,
      );

      expect(error.kind, ErrorKind.unresolvableDancerSet);
      expect(error.detail, contains('only be danced in one'));
    });

    test('a set with nowhere to reach is refused', () {
      // A single hands four is one grouping, so there is no next grouping at
      // all; re-banding would strand everyone at an end and leave the figure
      // with no hands four to dance in.
      final tooSmall = startingFormation(
        FormationType.dupleImproper,
        handsFour: 1,
      );

      final error = applyErr(const Swing(who: WhoSet.nextNeighbors), tooSmall);
      expect(error.kind, ErrorKind.unresolvableDancerSet);
      expect(error.detail, contains('nowhere to reach'));
    });

    test('two hands four reach, but not to anyone who is a next neighbour', () {
      // The distinction that matters: this set is big enough for the figure to
      // resolve, and it still refuses -- because reaching stands B beside C,
      // who started in the same grouping and the next one, but travelling in
      // opposite directions. Size and relationship are two separate reasons to
      // refuse and they report differently.
      final settled = startingFormation(
        FormationType.dupleImproper,
        handsFour: 2,
      );

      final error = applyErr(const Swing(who: WhoSet.nextNeighbors), settled);
      expect(error.kind, ErrorKind.whoMismatch);
      expect(error.detail, contains('B and C'));
    });
  });

  group('prevNeighbors: reaching against the direction of travel', () {
    // The shape both worked examples reach. Box the gnat with the neighbours
    // and pull by: the first exchange swaps the pair and turns them to face
    // each other, the second swaps them back and lets them keep walking, so
    // everyone ends in their own row facing the way they came. The couple
    // behind is now standing in front of them.
    Formation reversed() => applyOk(
      const PullByDancers(who: WhoSet.neighbors),
      applyOk(const BoxTheGnat(who: WhoSet.neighbors), start),
    );

    test('the couples that dance are the ones a grouping back', () {
      // B and C swing, and D and E; A and F are the ends and stay put.
      final before = reversed();
      final after = applyOk(const Swing(who: WhoSet.prevNeighbors), before);

      for (final couple in [1, 2, 3, 4]) {
        for (final role in Role.values) {
          final id = DancerId(couple, role);
          expect(after.stateOf(id), isNot(before.stateOf(id)), reason: '$id');
        }
      }
    });

    test('the ends have nobody behind them and are left alone', () {
      // A is a 1s couple in the top grouping, so there is no grouping further
      // up for it to reach; F is the mirror at the bottom. They fall outside
      // every band in the reaching phase, so no transform touches them -- and
      // nothing has to special-case them to arrange it.
      final before = reversed();
      final after = applyOk(const Swing(who: WhoSet.prevNeighbors), before);

      for (final couple in [0, 5]) {
        for (final role in Role.values) {
          final id = DancerId(couple, role);
          expect(after.stateOf(id), before.stateOf(id), reason: '$id');
        }
      }
    });

    test('naming the forward set instead is refused', () {
      // The mirror of the refusal in the nextNeighbors group. Reaching stands
      // B beside C in both states; only the sign says whether that is a
      // meeting or a mistake, so if the sign were ignored both would dance.
      final error = applyErr(
        const Swing(who: WhoSet.nextNeighbors),
        reversed(),
      );

      expect(error.kind, ErrorKind.whoMismatch);
      expect(error.detail, contains('B and C'));
    });

    test('it needs no travel first, unlike reaching forward', () {
      // The asymmetry falls out of the geometry rather than being arranged.
      // The reaching phase bands (1,2), (3,4), ... which pairs a 2s couple
      // with the couple one row below it -- and a 2s couple travels *up*, so
      // the couple below is always the one it has just left. Your previous
      // neighbours are therefore in position from a standing start, while your
      // next neighbours are not: the set has to open up first.
      expect(
        const Swing(who: WhoSet.prevNeighbors).apply(start),
        isA<Ok<Formation, OpError>>(),
      );
      expect(
        const Swing(who: WhoSet.nextNeighbors).apply(start),
        isA<Err<Formation, OpError>>(),
      );
    });
  });

  group('nextNeighbors: the fixture is reachable', () {
    test('a pass through along the set produces the worked-example shape', () {
      // The examples on record are stated against a hand-written grid. This
      // ties that grid to the figure that reaches it, so the fixture cannot
      // quietly drift into a shape no dance can actually get to.
      final after = applyOk(const PassThrough(), start);

      expect(render(after), render(passedThrough));
    });
  });

  group('nextNeighbors: sizing', () {
    test('a figure reaching the next grouping asks for another hands four', () {
      Dance dance(WhoSet who) => Dance(
        formation: FormationType.dupleImproper,
        success: const ProgressionCriterion(),
        figures: [OperationInvocation(Swing(who: who))],
      );

      expect(dance(WhoSet.neighbors).requiredHandsFour, 2);
      expect(dance(WhoSet.nextNeighbors).requiredHandsFour, 3);
    });
  });
}
