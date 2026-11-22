import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

// `shadows`, as ruled by the user on 2026-11-22: the dancer of the opposite
// role and the same couple number in a neighbouring hands four -- your
// partner's counterpart one grouping up or down. Numbers are read as they
// stand, so they toggle at the ends of the set, and at an end where a couple
// is not out its shadow is its neighbour. A figure naming shadows pairs
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
    // Two hands four with the 2s of the upper one and the 1s of the lower one
    // having traded places, so each row holds one couple and B stands beside
    // D, both 2s.
    final formation = duple([
      'L1-A . . . R1-A',
      'L2-B . . . R2-B',
      'R2-D . . . L2-D',
      'R1-C . . . L1-C',
    ]);

    test('opposite role, different couple, same number', () {
      expect(
        whoMatches(formation, lark('B'), robin('D'), WhoSet.shadows),
        isTrue,
      );
      expect(
        whoMatches(formation, lark('A'), robin('C'), WhoSet.shadows),
        isTrue,
      );
    });

    test('a partner is not a shadow', () {
      expect(
        whoMatches(formation, lark('B'), robin('B'), WhoSet.shadows),
        isFalse,
      );
    });

    test('a neighbour (the other number) is not a shadow', () {
      expect(
        whoMatches(formation, lark('A'), robin('B'), WhoSet.shadows),
        isFalse,
      );
    });

    test('a same-role dancer of the same number is not a shadow', () {
      expect(
        whoMatches(formation, lark('B'), lark('D'), WhoSet.shadows),
        isFalse,
      );
    });

    test('at an end, a couple that is not out has its neighbour as shadow', () {
      // A has turned round at the top and taken the 2s' number, so it now
      // shares a number with its neighbours B: B is its shadow, not its
      // neighbour, until it is back in the set.
      final atTheTop = duple([
        'R2-A . . . L2-A',
        'L2-B . . . R2-B',
        'L1-C . . . R1-C',
        'L2-D . . . R2-D',
      ]);

      expect(
        whoMatches(atTheTop, lark('A'), robin('B'), WhoSet.shadows),
        isTrue,
      );
      expect(
        whoMatches(atTheTop, lark('A'), robin('B'), WhoSet.neighbors),
        isFalse,
      );
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
      // B and D (both 2s) stand together across the settled boundary, in
      // rows 1 and 2; no settled band holds a pair of the same number.
      final input = duple([
        'L1-A . . . R1-A',
        'L2-B . . . R2-B',
        'R2-D . . . L2-D',
        'R1-C . . . L1-C',
      ]);

      final after = applyOk(
        const Allemande(who: WhoSet.shadows, turn: 0.5),
        input,
      );

      expect(bandRows(after), bandRows(input));
      expect(waitingOutRows(after), isEmpty);
      for (final (a, b) in [(lark('B'), robin('D')), (robin('B'), lark('D'))]) {
        expect(at(after, a), at(input, b), reason: '$a takes $b\'s place');
        expect(at(after, b), at(input, a), reason: '$b takes $a\'s place');
      }
      // A and C are at the ends while the set is one phase over, so the
      // figure leaves them where they stand.
      for (final id in [lark('A'), robin('A'), lark('C'), robin('C')]) {
        expect(at(after, id), at(input, id), reason: '$id');
      }
    });

    test('refused when no phase has shadows standing together', () {
      final error = applyErr(
        const Swing(who: WhoSet.shadows),
        startingFormation(FormationType.dupleImproper, handsFour: 2),
      );

      expect(error.kind, ErrorKind.whoMismatch);
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
    });

    test('refused when it also names a distance set', () {
      final error = applyErr(
        const MadRobin(who: WhoSet.shadows, whom: WhoSet.nextNeighbors),
        startingFormation(FormationType.dupleImproper, handsFour: 3),
      );

      expect(error.kind, ErrorKind.unresolvableDancerSet);
      expect(error.message, contains('shadows and nextNeighbors'));
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
