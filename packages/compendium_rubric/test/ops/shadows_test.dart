import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

// `shadows`, as ruled by the user on 2026-11-22: the dancer of the opposite
// role and the same couple number in a neighbouring hands four -- your
// partner's counterpart one grouping up or down. Numbers are read as they
// stand, so they toggle at the ends of the set: a couple out at an end is
// the shadow there, and with nobody out the shadow wraps round to the
// neighbour. A figure naming shadows pairs
// whoever is standing together, in whichever band phase they stand together.

Formation duple(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

DancerId lark(String letter) =>
    DancerId(letter.codeUnitAt(0) - 0x41, Role.lark);
DancerId robin(String letter) =>
    DancerId(letter.codeUnitAt(0) - 0x41, Role.robin);

List<List<int>> bandRows(Formation formation) => [
  for (final band in handsFourBands(formation)) [band.topRow, band.bottomRow],
];

Formation applyOk(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$result');
  return (result as Ok<Formation, OpError>).value;
}

OpError applyErr(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Err<Formation, OpError>>(), reason: '$result');
  return (result as Err<Formation, OpError>).error;
}

Position at(Formation formation, DancerId id) => formation.stateOf(id).position;

void main() {
  group('whoMatches: shadows', () {
    // Three hands four with the 2s of the top one and the 1s of the middle
    // one having traded places, so B stands beside D, both 2s.
    final formation = duple([
      'L1-A . . . R1-A',
      'L2-B . . . R2-B',
      'R2-D . . . L2-D',
      'R1-C . . . L1-C',
      'L1-E . . . R1-E',
      'L2-F . . . R2-F',
    ]);

    test('opposite role, different couple, same number', () {
      expect(
        whoMatches(formation, lark('B'), robin('D'), WhoSet.shadows),
        isTrue,
      );
      expect(
        whoMatches(formation, lark('C'), robin('E'), WhoSet.shadows),
        isTrue,
      );
    });

    test('a partner is not a shadow', () {
      expect(
        whoMatches(formation, lark('B'), robin('B'), WhoSet.shadows),
        isFalse,
      );
    });

    test('a neighbour in the middle of the set is not a shadow', () {
      expect(
        whoMatches(formation, lark('D'), robin('C'), WhoSet.shadows),
        isFalse,
      );
    });

    test('a same-role dancer of the same number is not a shadow', () {
      expect(
        whoMatches(formation, lark('B'), lark('D'), WhoSet.shadows),
        isFalse,
      );
    });
  });

  group('whoMatches: shadows at the ends of the set', () {
    // User-ruled 2026-11-22: "If there's a couple out at the top, then that's
    // your shadow. If there's no one out at the top, then it wraps around to
    // your neighbor."

    test('with nobody out at an end, the shadow wraps to the neighbour', () {
      // B has come back in at the top as a 1s couple, with D (2s) as its
      // neighbours and no hands four above it.
      final backIn = duple([
        'L1-B . . . R1-B',
        'R2-D . . . L2-D',
        'L1-A . . . R1-A',
        'R2-C . . . L2-C',
        'L1-F . . . R1-F',
        'R2-E . . . L2-E',
      ]);

      expect(whoMatches(backIn, lark('B'), robin('D'), WhoSet.shadows), isTrue);
      // The same holds at the bottom.
      expect(whoMatches(backIn, lark('F'), robin('E'), WhoSet.shadows), isTrue);
      // But not for the neighbours in the middle.
      expect(
        whoMatches(backIn, lark('A'), robin('C'), WhoSet.shadows),
        isFalse,
      );
    });

    test('with a couple out at an end, that couple is the shadow', () {
      // B is out at the top, having taken the 1s' number, beside A (1s). The
      // hands four below it holds A and its neighbours D.
      final bOut = markWaitingOut(
        duple([
          'L1-B . . . R1-B',
          'R1-A . . . L1-A',
          'L2-D . . . R2-D',
          'R1-C . . . L1-C',
          'L2-F . . . R2-F',
          'L1-E . . . R1-E',
        ]),
        rows: [0, 5],
      );

      expect(whoMatches(bOut, lark('A'), robin('B'), WhoSet.shadows), isTrue);
      // A's neighbours D are not its shadows: A is not at the end of the set,
      // B is.
      expect(whoMatches(bOut, robin('A'), lark('D'), WhoSet.shadows), isFalse);
    });
  });

  group('whoIncludes: shadows', () {
    test('everyone has a shadow, so the set is total', () {
      final formation = startingFormation(
        FormationType.dupleImproper,
        handsFour: 2,
      );
      for (final id in formation.dancers.keys) {
        expect(whoIncludes(formation, id, WhoSet.shadows), isTrue);
      }
    });
  });

  group('a figure naming shadows: choosing the band phase', () {
    test('danced in the phase it was handed when the shadows are there', () {
      // A beside C (both 1s) and B beside D (both 2s), each pair inside one of
      // the settled bands (0,1) and (2,3).
      final input = duple([
        'L1-A . . . R1-A',
        'R1-C . . . L1-C',
        'L2-B . . . R2-B',
        'R2-D . . . L2-D',
      ]);

      final after = applyOk(
        const Allemande(who: WhoSet.shadows, turn: 0.5),
        input,
      );

      expect(bandRows(after), bandRows(input));
      for (final (a, b) in [
        (lark('A'), robin('C')),
        (robin('A'), lark('C')),
        (lark('B'), robin('D')),
        (robin('B'), lark('D')),
      ]) {
        expect(at(after, a), at(input, b), reason: '$a takes $b\'s place');
        expect(at(after, b), at(input, a), reason: '$b takes $a\'s place');
      }
    });

    test('danced one phase over when that is where they stand, then '
        'handed back', () {
      // B and D (both 2s) stand together across the settled boundary in rows
      // 1 and 2, and C and E (both 1s) in rows 3 and 4. The middle settled
      // band, D beside C, holds no shadow pair.
      final input = duple([
        'L1-A . . . R1-A',
        'L2-B . . . R2-B',
        'R2-D . . . L2-D',
        'R1-C . . . L1-C',
        'L1-E . . . R1-E',
        'L2-F . . . R2-F',
      ]);

      final after = applyOk(
        const Allemande(who: WhoSet.shadows, turn: 0.5),
        input,
      );

      expect(bandRows(after), bandRows(input));
      expect(waitingOutRows(after), isEmpty);
      for (final (a, b) in [
        (lark('B'), robin('D')),
        (robin('B'), lark('D')),
        (lark('C'), robin('E')),
        (robin('C'), lark('E')),
      ]) {
        expect(at(after, a), at(input, b), reason: '$a takes $b\'s place');
        expect(at(after, b), at(input, a), reason: '$b takes $a\'s place');
      }
      // A and F are at the ends while the set is one phase over, so the
      // figure leaves them where they stand.
      for (final id in [lark('A'), robin('A'), lark('F'), robin('F')]) {
        expect(at(after, id), at(input, id), reason: '$id');
      }
    });

    test('refused when no phase has shadows standing together', () {
      // An allemande has no who check of its own that could refuse first.
      // Three hands four, because in two every band is at an end, where the
      // shadows wrap to the neighbours.
      final error = applyErr(
        const Allemande(who: WhoSet.shadows, turn: 0.5),
        startingFormation(FormationType.dupleImproper, handsFour: 3),
      );

      expect(error.kind, ErrorKind.whoMismatch);
      expect(error.message, contains('no band phase'));
    });

    test('refused when both phases have shadows standing together', () {
      // Every row a 1s couple: whichever phase, every hands four holds a
      // shadow pair, and choosing between them would be a guess.
      final error = applyErr(
        const Swing(who: WhoSet.shadows),
        duple([
          'L1-A . . . R1-A',
          'R1-C . . . L1-C',
          'L1-E . . . R1-E',
          'R1-G . . . L1-G',
        ]),
      );

      expect(error.kind, ErrorKind.unresolvableDancerSet);
      expect(error.message, contains('both band phases'));
    });
  });

  group('a dance keeps the shadows it first named (user-ruled 2026-11-23)', () {
    // "Once a dance names a shadow, it is the same dancer for the whole
    // dance": the first shadows figure remembers who danced with whom, and a
    // later one that finds shadow pairs in both band phases picks the phase
    // that keeps those pairs together.

    Formation remembering(
      Formation formation,
      List<(DancerId, DancerId)> pairs,
    ) => formation.withUpdates({
      for (final (a, b) in pairs) ...{
        a: formation.stateOf(a).copyWith(shadow: b),
        b: formation.stateOf(b).copyWith(shadow: a),
      },
    });

    // Every row a 1s couple: shadow pairs stand together in both phases.
    final allOnes = duple([
      'L1-A . . . R1-A',
      'R1-C . . . L1-C',
      'L1-E . . . R1-E',
      'R1-G . . . L1-G',
    ]);

    test('the first shadows figure remembers each pair', () {
      final after = applyOk(
        const Allemande(who: WhoSet.shadows, turn: 0.5),
        duple([
          'L1-A . . . R1-A',
          'R1-C . . . L1-C',
          'L2-B . . . R2-B',
          'R2-D . . . L2-D',
        ]),
      );

      expect(after.stateOf(lark('A')).shadow, robin('C'));
      expect(after.stateOf(robin('C')).shadow, lark('A'));
      expect(after.stateOf(robin('B')).shadow, lark('D'));
      expect(after.stateOf(lark('D')).shadow, robin('B'));
    });

    test('a remembered shadow is not replaced', () {
      final input = remembering(
        duple([
          'L1-A . . . R1-A',
          'R1-C . . . L1-C',
          'L2-B . . . R2-B',
          'R2-D . . . L2-D',
        ]),
        [(lark('A'), robin('D'))],
      );
      final after = applyOk(
        const Allemande(who: WhoSet.shadows, turn: 0.5),
        input,
      );

      expect(after.stateOf(lark('A')).shadow, robin('D'));
    });

    test('with both phases possible, the remembered pairs pick the current '
        'one', () {
      final input = remembering(allOnes, [
        (lark('A'), robin('C')),
        (robin('A'), lark('C')),
      ]);
      final after = applyOk(const Swing(who: WhoSet.shadows), input);

      expect(bandRows(after), bandRows(input));
      // The column pairs of the current phase swung: A with C in rows 0-1.
      expect(at(after, lark('A')).row, lessThanOrEqualTo(1));
      expect(at(after, robin('C')).row, lessThanOrEqualTo(1));
    });

    test('with both phases possible, the remembered pairs pick the other '
        'one, which is handed back', () {
      final input = remembering(allOnes, [
        (lark('C'), robin('E')),
        (robin('C'), lark('E')),
      ]);
      final after = applyOk(const Swing(who: WhoSet.shadows), input);

      expect(bandRows(after), bandRows(input));
      // One phase over, A and G stand out at the ends and do not swing.
      for (final id in [lark('A'), robin('A'), lark('G'), robin('G')]) {
        expect(at(after, id), at(input, id), reason: '$id');
      }
    });

    test('without remembered pairs, both phases is still refused', () {
      final error = applyErr(const Swing(who: WhoSet.shadows), allOnes);

      expect(error.kind, ErrorKind.unresolvableDancerSet);
    });

    test('a meanwhile keeps the shadows a part remembers', () {
      // A whole allemande leaves everyone where they stood, and the other
      // part only turns the larks: the memory must survive both.
      final after = applyOk(
        const Meanwhile([
          Allemande(who: WhoSet.shadows, turn: 1),
          TurnAlone(who: WhoSet.role1s),
        ]),
        duple([
          'L1-A . . . R1-A',
          'R1-C . . . L1-C',
          'L2-B . . . R2-B',
          'R2-D . . . L2-D',
        ]),
      );

      expect(after.stateOf(lark('A')).shadow, robin('C'));
      expect(after.stateOf(robin('C')).shadow, lark('A'));
      expect(after.stateOf(lark('D')).shadow, robin('B'));
    });

    test('a figure pairs dancers who remember each other first', () {
      // Lauren's Lagniappe after its left diagonal chain: R1-C has chained up
      // to L1-A, and R1-A, with nobody on her diagonal, went nowhere. With
      // nobody out at the top, the shadow wraps to the neighbour there, so
      // L2-B matches R1-C across the set as well as R1-A beside him. First
      // match first took L2-B with R1-C, leaving partners A unpaired.
      final input = remembering(
        parseRolesNotation([
          'L2-B . . . R1-C',
          'R1-A . . . L1-A',
          'L2-D . . . R1-E',
          'R2-B . . . L1-C',
          'L2-F . . . R1-G',
          'R2-D . . . L1-E',
          'L2-H . . . R2-H',
          'R2-F . . . L1-G',
        ], type: FormationType.becketCcw),
        [
          (lark('A'), robin('C')),
          (lark('D'), robin('B')),
          (lark('C'), robin('E')),
          (lark('F'), robin('D')),
          (lark('E'), robin('G')),
          (lark('H'), robin('F')),
        ],
      );
      final after = applyOk(
        const Allemande(who: WhoSet.shadows, hand: Hand.left, turn: 1.5),
        input,
      );

      expect(at(after, robin('C')), at(input, lark('A')));
      expect(at(after, lark('A')), at(input, robin('C')));
      expect(after.stateOf(lark('B')).shadow, robin('A'));
      expect(after.stateOf(robin('A')).shadow, lark('B'));
    });

    test('a figure is refused when keeping remembered shadows would leave a '
        'couple idle (user-ruled 2026-11-24)', () {
      // At the top with nobody out, A and C remember each other and stand
      // beside each other in one side column, and partners B stand across the
      // set from them. Keeping A with C would leave B with nobody; first match
      // would pair each B across the set and break A and C up. Neither: the
      // figure is refused.
      final input = remembering(
        parseRolesNotation([
          'L2-B . . . R1-C',
          'R2-B . . . L1-A',
          'L2-D . . . R1-E',
          'R1-A . . . L1-C',
          'L2-F . . . R1-G',
          'R2-D . . . L1-E',
          'L2-H . . . R2-H',
          'R2-F . . . L1-G',
        ], type: FormationType.becketCcw),
        [(lark('A'), robin('C'))],
      );

      expect(
        shadowMemoryStrandsDancers(input, topRow: 0, bottomRow: 1),
        isTrue,
      );
      expect(resolveWhoPairs(input, WhoSet.shadows, topRow: 0, bottomRow: 1), [
        (a: robin('C'), b: lark('A')),
      ]);
      final error = applyErr(
        const Allemande(who: WhoSet.shadows, hand: Hand.left, turn: 1.5),
        input,
      );
      expect(error.kind, ErrorKind.unresolvableDancerSet);
      expect(error.detail, contains('rows 0-1'));
    });

    // The ruled case the other way round: the remembered pair beside each
    // other in column 0, partners B across in column 4. First match would
    // pair A with C and strand B here too, so only a comparison against the
    // largest pairing catches it.
    Formation strandedOtherWayRound() => remembering(
      parseRolesNotation([
        'L1-A . . . L2-B',
        'R1-C . . . R2-B',
        'L2-D . . . R1-E',
        'R1-A . . . L1-C',
        'L2-F . . . R1-G',
        'R2-D . . . L1-E',
        'L2-H . . . R2-H',
        'R2-F . . . L1-G',
      ], type: FormationType.becketCcw),
      [(lark('A'), robin('C'))],
    );

    test('the refusal does not depend on which way round the dancers '
        'stand', () {
      final input = strandedOtherWayRound();

      expect(
        shadowMemoryStrandsDancers(input, topRow: 0, bottomRow: 1),
        isTrue,
      );
      final error = applyErr(
        const Allemande(who: WhoSet.shadows, hand: Hand.left, turn: 1.5),
        input,
      );
      expect(error.kind, ErrorKind.unresolvableDancerSet);
      expect(error.detail, contains('rows 0-1'));
    });

    test('a remembered pair across the set from each other is not '
        'refused', () {
      // Train Delay (Caller's Box 14841) at the bottom: E and H remember each
      // other across the set, and partners G stand beside them. Only a pair
      // beside each other, the case ruled on, is checked.
      final input = remembering(
        parseRolesNotation([
          'L2-B . . . R1-A',
          'R2-B . . . L1-A',
          'L2-D . . . R1-C',
          'R2-D . . . L1-C',
          'L2-F . . . R1-G',
          'R2-F . . . L1-G',
          'L1-E . . . R2-H',
          'L2-K . . . R2-K',
        ], type: FormationType.becketCcw),
        [(lark('E'), robin('H'))],
      );

      expect(
        shadowMemoryStrandsDancers(input, topRow: 6, bottomRow: 7),
        isFalse,
      );
    });

    test('a figure that pairs nobody is not refused for it', () {
      // Turning alone asks for no pairs, so nobody is left without one: not
      // in the case ruled on, nor the other way round.
      final ruled = remembering(
        parseRolesNotation([
          'L2-B . . . R1-C',
          'R2-B . . . L1-A',
          'L2-D . . . R1-E',
          'R1-A . . . L1-C',
          'L2-F . . . R1-G',
          'R2-D . . . L1-E',
          'L2-H . . . R2-H',
          'R2-F . . . L1-G',
        ], type: FormationType.becketCcw),
        [(lark('A'), robin('C'))],
      );
      applyOk(const TurnAlone(who: WhoSet.shadows), ruled);
      applyOk(const TurnAlone(who: WhoSet.shadows), strandedOtherWayRound());
    });

    test('a figure that also names a distance set is refused too', () {
      // After one progression the next neighbours are the ones standing
      // there, so the figure is danced in place; the shadows it pairs by
      // `whom` would strand partners B.
      final result = const RollAway(
        who: WhoSet.nextNeighbors,
        whom: WhoSet.shadows,
      ).apply(strandedOtherWayRound(), progressions: 1);

      expect(result, isA<Err<Formation, OpError>>(), reason: '$result');
      final error = (result as Err<Formation, OpError>).error;
      expect(error.kind, ErrorKind.unresolvableDancerSet);
      expect(error.detail, contains('rows 0-1'));
    });

    test('a figure applied inside another reports nothing to it', () {
      // Probing pairs while choosing a band phase, or dancing a figure that
      // pairs nobody, must not refuse an enclosing figure.
      final reported = <int>[];
      final result = watchShadowStrands(
        () =>
            const TurnAlone(who: WhoSet.shadows).apply(strandedOtherWayRound()),
        (topRow, bottomRow) => reported.add(topRow),
      );

      expect(result, isA<Ok<Formation, OpError>>(), reason: '$result');
      expect(reported, isEmpty);
    });

    test('a remembered pair across the set gives way to first match where '
        'that pairs more', () {
      // E and H remember each other across the bottom row, partners K stand
      // in the row above: first match pairs L2-K with R2-H and R2-K with L1-E
      // by the wrap, where keeping E with H would leave K idle.
      final input = remembering(
        parseRolesNotation([
          'L2-B . . . R1-A',
          'R2-B . . . L1-A',
          'L2-D . . . R1-C',
          'R2-D . . . L1-C',
          'L2-F . . . R1-G',
          'R2-F . . . L1-G',
          'L2-K . . . R2-K',
          'L1-E . . . R2-H',
        ], type: FormationType.becketCcw),
        [(lark('E'), robin('H'))],
      );

      expect(
        resolveWhoPairs(input, WhoSet.shadows, topRow: 6, bottomRow: 7),
        hasLength(2),
      );
    });

    test('a dancer keeps the shadow through any change of state', () {
      final state = allOnes.stateOf(lark('A')).copyWith(shadow: robin('C'));

      expect(
        state.copyWith(facing: Facing.up, waitingOut: true).shadow,
        robin('C'),
      );
    });
  });

  group('a figure naming shadows and a distance set', () {
    // A figure can name both, like a square through with the shadows and then
    // the next neighbours. Where you meet your shadows depends on the
    // progression, so nothing ties the two sets together to refuse on
    // (user-ruled 2026-11-22). The agent's call following from it: the
    // distance picks the band phase and the shadows pairing rule is not
    // applied.

    // Three hands four after a pass through along. One phase over, every band
    // holds a 1s couple with its next neighbours, the 2s; no band phase holds
    // a shadow pair, so a figure naming only shadows is refused here.
    final passedThrough = duple([
      'L2-B . . . R2-B',
      'R1-A . . . L1-A',
      'L2-D . . . R2-D',
      'R1-C . . . L1-C',
      'L2-F . . . R2-F',
      'R1-E . . . L1-E',
    ]);

    test('is danced one phase over, where the distance reaches', () {
      expect(
        const MadRobin(who: WhoSet.shadows, turn: 0.5).apply(passedThrough),
        isA<Err<Formation, OpError>>(),
      );

      // A half mad robin swaps the two rows of every band: here (1,2) and
      // (3,4), leaving B and E at the ends untouched.
      final after = applyOk(
        const MadRobin(
          who: WhoSet.shadows,
          whom: WhoSet.nextNeighbors,
          turn: 0.5,
        ),
        passedThrough,
      );

      expect(bandRows(after), bandRows(passedThrough));
      for (final (couple, from, to) in [
        ('B', 0, 0),
        ('A', 1, 2),
        ('D', 2, 1),
        ('C', 3, 4),
        ('F', 4, 3),
        ('E', 5, 5),
      ]) {
        for (final id in [lark(couple), robin(couple)]) {
          expect(at(passedThrough, id).row, from, reason: '$id before');
          expect(at(after, id).row, to, reason: '$id after');
        }
      }
    });

    test('is danced in place once a progression has closed the distance', () {
      // After one progression the next neighbours are the current ones, so
      // the half mad robin swaps the rows of the bands the set was handed.
      final start = startingFormation(
        FormationType.dupleImproper,
        handsFour: 2,
      );

      final result = const MadRobin(
        who: WhoSet.shadows,
        whom: WhoSet.nextNeighbors,
        turn: 0.5,
      ).apply(start, progressions: 1);

      expect(result, isA<Ok<Formation, OpError>>(), reason: '$result');
      final after = (result as Ok<Formation, OpError>).value;
      for (final couple in ['A', 'B', 'C', 'D']) {
        final before = at(start, lark(couple)).row;
        final expected = before.isEven ? before + 1 : before - 1;
        expect(at(after, lark(couple)).row, expected, reason: couple);
      }
    });
  });

  group('sizing', () {
    test('a figure naming shadows asks for a middle hands four', () {
      // With two hands four every band is at an end, where shadows wrap to the
      // neighbours, so the two could never be told apart.
      Dance dance(WhoSet who) => Dance(
        formation: FormationType.dupleImproper,
        success: const ProgressionCriterion(),
        figures: [OperationInvocation(Swing(who: who))],
      );

      expect(dance(WhoSet.neighbors).requiredHandsFour, 2);
      expect(dance(WhoSet.shadows).requiredHandsFour, 3);
    });
  });

  group('parsing', () {
    test('shadows and its singular alias name the set', () {
      expect(WhoSet.fromKey('shadows'), WhoSet.shadows);
      expect(WhoSet.fromKey('shadow'), WhoSet.shadows);
    });

    test('shadows is not a distance set', () {
      expect(WhoSet.shadows.distance, isNull);
      expect(WhoSet.shadows.isCrossHandsFour, isFalse);
    });
  });
}
