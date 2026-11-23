import 'dart:convert';

import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

/// Partners are row-mates, neighbours column-mates (`docs/taxonomy.md`).
const List<String> base = ['R1-A . . . L1-A', 'L2-B . . . R2-B'];
const List<String> rowSwap = ['L2-B . . . R2-B', 'R1-A . . . L1-A'];
const List<String> colSwap = ['L1-A . . . R1-A', 'R2-B . . . L2-B'];
const List<String> diagonal = ['R2-B . . . L2-B', 'L1-A . . . R1-A'];

Formation applyOk(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$op failed: $result');
  return (result as Ok<Formation, OpError>).value;
}

void main() {
  group('circular_hey: each change swaps the pair passing', () {
    // Neighbours stand along the set, so they pass along first (a row swap),
    // then the other pair across (a column swap), alternating.
    final cases = <int, List<String>>{
      1: rowSwap,
      2: diagonal,
      3: colSwap,
      4: base,
      5: rowSwap,
    };
    for (final entry in cases.entries) {
      test('neighbours first, ${entry.key} change(s)', () {
        expect(
          applyOk(CircularHey(changes: entry.key), di(base)).toRolesNotation(),
          entry.value,
        );
      });
    }

    test('partners first pass across, so one change is the column swap', () {
      expect(
        applyOk(
          const CircularHey(who: WhoSet.partners, changes: 1),
          di(base),
        ).toRolesNotation(),
        colSwap,
      );
      expect(
        applyOk(
          const CircularHey(who: WhoSet.partners, changes: 3),
          di(base),
        ).toRolesNotation(),
        rowSwap,
      );
    });

    test('shoulder, who2 and where move nobody', () {
      final plain = applyOk(const CircularHey(changes: 3), di(base));
      final dressed = applyOk(
        const CircularHey(
          changes: 3,
          shoulder: Hand.left,
          who2: WhoSet.partners,
          where: Direction.along,
        ),
        di(base),
      );
      expect(dressed.toRolesNotation(), plain.toRolesNotation());
    });

    test('in Becket, neighbours stand across, so they pass across first', () {
      final becket = parseRolesNotation(const [
        'L2-B . . . R1-A',
        'R2-B . . . L1-A',
      ], type: FormationType.becketCw);
      expect(applyOk(const CircularHey(changes: 1), becket).toRolesNotation(), [
        'R1-A . . . L2-B',
        'L1-A . . . R2-B',
      ]);
    });
  });

  group('circular_hey refuses a ring it cannot read', () {
    test('a who naming one pair per hands four', () {
      final error = const CircularHey(
        who: WhoSet.ones,
      ).checkPreconditions(di(base));
      expect(error?.kind, ErrorKind.unresolvableDancerSet);
    });

    test('who: everyone, which names no pairing', () {
      final error = const CircularHey(
        who: WhoSet.everyone,
      ).checkPreconditions(di(base));
      expect(error?.kind, ErrorKind.unresolvableDancerSet);
    });

    test('a who pair standing diagonally', () {
      final error = const CircularHey().checkPreconditions(
        di(const ['R1-A . . . L1-A', 'R2-B . . . L2-B']),
      );
      expect(error?.kind, ErrorKind.unresolvableDancerSet);
      expect(error?.message, contains('diagonally'));
    });

    test('who pairs along the set in one band and across it in another', () {
      final error = const CircularHey().checkPreconditions(
        di(const [
          'R1-A . . . L1-A',
          'L2-B . . . R2-B',
          'R1-C . . . L2-D',
          'L1-C . . . R2-D',
        ]),
      );
      expect(error?.kind, ErrorKind.unresolvableDancerSet);
      expect(error?.message, contains('others across'));
    });

    test('changes below one', () {
      final error = const CircularHey(changes: 0).checkPreconditions(di(base));
      expect(error?.kind, ErrorKind.unsupportedParam);
    });
  });

  group('a stated who2 is checked, not just carried', () {
    test('the other pair of the ring passes second: accepted', () {
      expect(
        const CircularHey(
          changes: 3,
          who2: WhoSet.partners,
        ).checkPreconditions(di(base)),
        isNull,
      );
    });

    test('a who2 that is not the second pair is a whoMismatch', () {
      final error = const CircularHey(
        changes: 3,
        who2: WhoSet.neighbors,
      ).checkPreconditions(di(base));
      expect(error?.kind, ErrorKind.whoMismatch);
    });

    test('a who2 reaching another hands four is deferred', () {
      final error = const CircularHey(
        who: WhoSet.partners,
        changes: 2,
        who2: WhoSet.nextNeighbors,
      ).checkPreconditions(di(base));
      expect(error?.kind, ErrorKind.unsupportedParam);
    });

    test('shadows in who2 is deferred at parse time', () {
      final record = {
        'title': 'who2 probe',
        'formation': {'shape': 'dupleImproper'},
        'progression': 'single',
        'figures': [
          {
            'move': 'circular_hey',
            'params': {'who2': 'shadows'},
          },
        ],
      };
      final result = parseDanceJson(jsonEncode(record));
      expect(result, isA<Err<Dance, DanceParseError>>());
      expect((result as Err<Dance, DanceParseError>).error.deferred, isTrue);
    });
  });

  group('facing', () {
    test('one change keeps facing: everyone walked straight through', () {
      final before = startingFormation(
        FormationType.dupleImproper,
        handsFour: 1,
      );
      final after = applyOk(const CircularHey(changes: 1), before);
      for (final entry in after.dancers.entries) {
        expect(entry.value.facing, before.stateOf(entry.key).facing);
      }
    });

    test('more changes leave facing flexible: each pass turned them', () {
      final before = startingFormation(
        FormationType.dupleImproper,
        handsFour: 1,
      );
      final after = applyOk(const CircularHey(), before);
      for (final state in after.dancers.values) {
        expect(state.facing, Facing.flexible);
      }
    });
  });

  test('nextNeighbors passing first reaches along the set', () {
    // Three hands four after a pass through along, the shape in which each
    // dancer's next neighbours stand beside them (`next_neighbors_test.dart`):
    // A meets D across rows 1-2, and C meets F across rows 3-4.
    final passedThrough = di(const [
      'L2-B . . . R2-B',
      'R1-A . . . L1-A',
      'L2-D . . . R2-D',
      'R1-C . . . L1-C',
      'L2-F . . . R2-F',
      'R1-E . . . L1-E',
    ]);
    final after = applyOk(
      const CircularHey(who: WhoSet.nextNeighbors, changes: 1),
      passedThrough,
    );
    expect(after.toRolesNotation(), [
      'L2-B . . . R2-B',
      'L2-D . . . R2-D',
      'R1-A . . . L1-A',
      'L2-F . . . R2-F',
      'R1-C . . . L1-C',
      'R1-E . . . L1-E',
    ]);
  });

  test('is progression-eligible, and not its own progression', () {
    expect(const CircularHey().progressionEligible, isTrue);
    expect(const CircularHey().isItsOwnProgression, isFalse);
  });
}
