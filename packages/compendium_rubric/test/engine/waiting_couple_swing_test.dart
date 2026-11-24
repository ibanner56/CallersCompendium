import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

/// Haven't We Met Before? (Caller's Box #10129), as the bridge reads it, with
/// the progression on figure [flagAt]. Caller's Box flags none; both halves of
/// the hey mark their last pass partial ("~"), and the second is the one that
/// progresses *(user-ruled 2026-11-24)*.
Map<String, Object?> havenNotMet({
  int flagAt = 4,
  String n0 = 'prevNeighbors',
}) {
  final figures = <Map<String, Object?>>[
    {
      'move': 'star',
      'params': {'hand': 'left', 'places': 3},
    },
    {
      'move': 'do_si_do',
      'params': {'who': 'neighbors', 'travel': 1.5},
    },
    {
      'move': 'swing',
      'params': {'who': n0, 'prefix': 'balance'},
    },
    {
      'move': 'hey',
      'params': {
        'length': 'half',
        'pass1': 'role1s',
        'shoulder': 'left',
        'pass2': 'partners',
      },
    },
    {
      'move': 'hey',
      'params': {
        'length': 'half',
        'pass1': 'role1s',
        'shoulder': 'right',
        'pass2': 'partners',
      },
    },
    {
      'move': 'allemande',
      'params': {'who': 'nextNeighbors', 'hand': 'right', 'travel': 1.0},
    },
    {
      'move': 'pass_by',
      'params': {'who': 'role1s', 'shoulder': 'right'},
    },
    {
      'move': 'swing',
      'params': {'who': 'partners'},
    },
  ];
  figures[flagAt] = {...figures[flagAt], 'progression': true};
  return {
    'title': "Haven't We Met Before?",
    'form': 'contra',
    'formation': {'shape': 'becketCw'},
    'progression': 'single',
    'figures': figures,
  };
}

Dance _dance(Map<String, Object?> record) =>
    (parseDance(record) as Ok<Dance, DanceParseError>).value;

/// The formation after figure [upTo] of [record].
Formation _after(Map<String, Object?> record, int upTo) {
  final dance = _dance(record);
  final fold = FigureFold();
  var state = dance.instantiate();
  for (var i = 0; i <= upTo; i++) {
    final step = fold.step(dance.figures[i], state, index: i);
    expect(step, isA<Ok<Formation, OpError>>(), reason: 'figure $i: $step');
    state = (step as Ok<Formation, OpError>).value;
  }
  return state;
}

void main() {
  group('a couple waiting out swings each other on an N0 swing '
      '(user-ruled 2026-11-24)', () {
    test('the couple at the top swaps sides and faces into the set', () {
      final before = _after(havenNotMet(), 1);
      final after = _after(havenNotMet(), 2);
      final top = before.dancersInRow(0).toList();
      // A whole couple across the top row, out of the N0 grouping the swing
      // is danced in (the fold dances it one band phase over).
      expect(top, hasLength(2));
      expect(top.map((id) => id.coupleIndex).toSet(), hasLength(1));
      final normal = normalizeAlongHall(row: 0, facing: Facing.down);
      for (final id in top) {
        final state = after.stateOf(id);
        expect(
          state.position,
          id.role == Role.lark ? normal.lark : normal.robin,
          reason: '$id',
        );
        expect(state.facing, Facing.down, reason: '$id');
      }
    });

    test("Haven't We Met Before? compiles, progressing on the second hey", () {
      expect(compile(_dance(havenNotMet())), isA<Compiled>());
    });

    test('a couple alone at an end but not waiting out is left be', () {
      // Marking the top row out leaves band (1, 2) and the bottom row in none,
      // but its couple is not waiting out. It is turned to face down, crossed, so
      // a swing that normalized it would move it.
      final start = startingFormation(
        FormationType.dupleImproper,
        handsFour: 2,
      );
      final bottom = start.dancersInRow(3).toList();
      final normal = normalizeAlongHall(row: 3, facing: Facing.up);
      final input = start.withUpdates({
        for (final id in start.dancersInRow(0))
          id: start.stateOf(id).copyWith(waitingOut: true),
        for (final id in bottom)
          id: start
              .stateOf(id)
              .copyWith(
                position: id.role == Role.lark ? normal.robin : normal.lark,
                facing: Facing.down,
              ),
      });
      expect(handsFourBands(input).map((b) => b.bottomRow), isNot(contains(3)));
      final after =
          (const Swing(who: WhoSet.prevNeighbors).perform(input)
                  as Ok<Formation, OpError>)
              .value;
      for (final id in bottom) {
        expect(after.stateOf(id), input.stateOf(id), reason: '$id');
      }
    });

    test('at the top of a Duple Proper set they stand crossed', () {
      // As end normalization leaves a proper couple there (topEndCrossed).
      final start = startingFormation(FormationType.dupleProper, handsFour: 3);
      final top = start.dancersInRow(0).toList();
      final waiting = start.withUpdates({
        for (final id in top)
          id: start.stateOf(id).copyWith(waitingOut: true, facing: Facing.up),
      });
      final after =
          (const Swing(who: WhoSet.prevNeighbors).perform(waiting)
                  as Ok<Formation, OpError>)
              .value;
      for (final id in top) {
        expect(
          after.stateOf(id).position.col,
          id.role == Role.lark ? Position.westColumn : Position.eastColumn,
          reason: '$id',
        );
        expect(after.stateOf(id).facing, Facing.down, reason: '$id');
      }
    });

    test('only an N0 swing moves them, and only a couple waiting out', () {
      // Limited to N0 by the maintainer ("go with option A for now").
      final start = _after(havenNotMet(), 1);
      final top = start.dancersInRow(0).toList();
      final waiting = start.withUpdates({
        for (final id in top) id: start.stateOf(id).copyWith(waitingOut: true),
      });
      Formation swung(Formation input, WhoSet who) =>
          (Swing(who: who).perform(input) as Ok<Formation, OpError>).value;
      Iterable<Position> topCells(Formation f) =>
          top.map((id) => f.stateOf(id).position);

      expect(
        topCells(swung(waiting, WhoSet.prevNeighbors)),
        isNot(topCells(waiting)),
      );
      expect(topCells(swung(waiting, WhoSet.nextNeighbors)), topCells(waiting));
      expect(topCells(swung(start, WhoSet.prevNeighbors)), topCells(start));
    });
  });
}
