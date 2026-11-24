import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

/// Heather's Hop Redux (Caller's Box #10172), as the bridge reads it: the
/// chains' "to partner" and "to neighbor N2" are not carried.
Map<String, Object?> heathersHop({String chainDir = 'across'}) => {
  'title': "Heather's Hop Redux",
  'form': 'contra',
  'formation': {'shape': 'dupleProper'},
  'progression': 'double',
  'figures': [
    {
      'move': 'swing',
      'params': {'who': 'ones'},
    },
    {
      'move': 'shoulder_round',
      'params': {'who': 'ones', 'shoulder': 'right', 'travel': 1.0},
    },
    {
      'move': 'swing',
      'params': {'who': 'neighbors', 'prefix': 'balance'},
    },
    {
      'move': 'allemande',
      'params': {'who': 'nextNeighbors', 'hand': 'left', 'travel': 1.5},
    },
    {
      'move': 'chain',
      'params': {'who': 'role2s', 'dir': chainDir},
    },
    {
      'move': 'chain',
      'params': {'who': 'role2s', 'dir': chainDir},
    },
    {
      'move': 'figure_8',
      'params': {'who': 'ones', 'fraction': 'half', 'where': 'above'},
      'progression': true,
    },
  ],
};

/// The figure index of the N2 allemande, and of the two chains after it.
const _allemande = 3;
const _firstChain = 4;
const _secondChain = 5;

/// Folds [record] and returns the formation after every figure.
List<Formation> trace(Map<String, Object?> record, {int? upTo}) {
  final dance = (parseDance(record) as Ok<Dance, DanceParseError>).value;
  final fold = FigureFold();
  var state = dance.instantiate();
  final after = <Formation>[];
  final last = upTo ?? dance.figures.length - 1;
  for (var i = 0; i <= last; i++) {
    final step = fold.step(dance.figures[i], state, index: i);
    expect(step, isA<Ok<Formation, OpError>>(), reason: 'figure $i: $step');
    state = (step as Ok<Formation, OpError>).value;
    after.add(state);
  }
  return after;
}

/// Where the robin of couple [letter] stands in [f].
Position robin(Formation f, String letter) => f
    .stateOf(
      f.dancers.keys.singleWhere(
        (id) => id.role == Role.robin && id.coupleLetter == letter,
      ),
    )
    .position;

void main() {
  group('a chain across straight after an N2 figure chains with N2', () {
    test('R1-A and R2-D swap in the first chain', () {
      // User-ruled 2026-11-24, note on #10172: "R1-A and R2-D should be the
      // ones who swap in the chain", and on #10173 "mapped forward through
      // the remainder of the other pairs of robins".
      final after = trace(heathersHop(), upTo: _firstChain);
      final before = after[_allemande];
      final chained = after[_firstChain];
      expect(robin(chained, 'A'), robin(before, 'D'));
      expect(robin(chained, 'D'), robin(before, 'A'));
      expect(robin(chained, 'C'), robin(before, 'F'));
      expect(robin(chained, 'F'), robin(before, 'C'));
    });

    test('the chain straight after it follows too, chaining them back', () {
      final after = trace(heathersHop(), upTo: _secondChain);
      expect(robin(after[_secondChain], 'A'), robin(after[_allemande], 'A'));
      expect(robin(after[_secondChain], 'D'), robin(after[_allemande], 'D'));
    });

    test('the set is handed back in the phase it was in', () {
      final after = trace(heathersHop(), upTo: _secondChain);
      bool anyOut(Formation f) => f.dancers.values.any((d) => d.waitingOut);
      expect(anyOut(after[_allemande]), isFalse);
      expect(anyOut(after[_firstChain]), isFalse);
      expect(anyOut(after[_secondChain]), isFalse);
    });
  });
}
