// Hand-computed expectations for the reference evaluator, each derived from the
// Ruby in `filter_dances.rb` / `search_match.rb` (not from running this port).
// They pin the quirks the parity suite depends on, so a slip in the port cannot
// make "Collection == reference" pass by being wrong the same way twice.
import 'package:test/test.dart';

import 'contradb_reference.dart';

ContraDbDance d(List<String> moves) => ContraDbDance(id: 'x', moves: moves);
List<Object?> fig(String m) => ['figure', m];
bool matches(List<Object?> f, List<String> moves) => danceMatches(f, d(moves));

void main() {
  test('figure finds one patch per matching index', () {
    expect(matchingFigures(fig('chain'), d(['chain', 'swing', 'chain'])), {
      SearchMatch(0, 3),
      SearchMatch(2, 3),
    });
    expect(matchingFigures(fig('chain'), d(['swing'])), isNull);
  });

  group('then abuts: adjacency by index, wrapping last -> first', () {
    final then = ['then', fig('chain'), fig('swing')];
    test(
      'adjacent in order',
      () => expect(matches(then, ['chain', 'swing', 'star']), isTrue),
    );
    test(
      'not adjacent',
      () => expect(matches(then, ['chain', 'star', 'swing']), isFalse),
    );
    test('the other order is not adjacent', () {
      // chain at 2, swing at 0, one figure after chain: (2 + 1) % 4 != 0.
      expect(matches(then, ['swing', 'star', 'chain', 'balance']), isFalse);
    });
    test('wraps from the last figure to the first', () {
      // chain is the last figure, swing the first: (2 + 1) % 3 == 0.
      expect(matches(then, ['swing', 'star', 'chain']), isTrue);
      expect(matches(then, ['swing', 'chain']), isTrue); // chain(1) -> swing(0)
      expect(matches(then, ['swing', 'star', 'balance', 'chain']), isTrue);
    });
    test('a one-figure dance abuts itself', () {
      // (last + 1) % 1 == first, so `then(chain, chain)` matches a lone chain.
      expect(matches(['then', fig('chain'), fig('chain')], ['chain']), isTrue);
    });
    test('three operands chain through abutting patches', () {
      final t3 = ['then', fig('chain'), fig('swing'), fig('star')];
      expect(matches(t3, ['gate', 'chain', 'swing', 'star']), isTrue);
      expect(matches(t3, ['chain', 'swing', 'gate', 'star']), isFalse);
    });
    test('no figures: never matches', () => expect(matches(then, []), isFalse));
  });

  group('empty sets are truthy', () {
    test('no X on a zero-figure dance matches', () {
      expect(matches(['no', fig('chain')], []), isTrue);
    });
    test('no X returns every one-figure patch', () {
      expect(matchingFigures(['no', fig('chain')], d(['swing', 'star'])), {
        SearchMatch(0, 2),
        SearchMatch(1, 2),
      });
    });
    test(
      'and of figures that never share an index is an empty, truthy set',
      () {
        final f = ['and', fig('chain'), fig('swing')];
        expect(matchingFigures(f, d(['chain', 'swing'])), <SearchMatch>{});
        expect(matches(f, ['chain', 'swing']), isTrue);
      },
    );
    test('figurewise & of the same figures is nil, so it does not match', () {
      expect(
        matches(['&', fig('chain'), fig('swing')], ['chain', 'swing']),
        isFalse,
      );
      expect(
        matches(
          [
            '&',
            fig('chain'),
            ['not', fig('swing')],
          ],
          ['chain', 'swing'],
        ),
        isTrue,
      );
    });
  });

  group('figurewise not', () {
    test('selects the other figures', () {
      expect(matchingFigures(['not', fig('chain')], d(['chain', 'swing'])), {
        SearchMatch(1, 2),
      });
    });
    test('nil when every figure matches, or there are none', () {
      expect(matches(['not', fig('chain')], ['chain']), isFalse);
      expect(matches(['not', fig('chain')], []), isFalse);
    });
  });

  group('or', () {
    test('unions, and is nil only when every branch is nil', () {
      expect(
        matchingFigures([
          'or',
          fig('chain'),
          fig('swing'),
        ], d(['chain', 'swing'])),
        {SearchMatch(0, 2), SearchMatch(1, 2)},
      );
      expect(matches(['or', fig('chain'), fig('swing')], ['star']), isFalse);
    });
    test('an empty or matches nothing; an empty and matches everything', () {
      expect(matches(['or'], ['chain']), isFalse);
      expect(matches(['and'], []), isTrue);
    });
  });

  group('an undefined move raises, but only on a dance that has figures', () {
    test('raises', () {
      expect(
        () => matches(fig('nope'), ['chain']),
        throwsA(isA<ContraDbReferenceError>()),
      );
    });
    test('a zero-figure dance never reaches the lookup', () {
      expect(matches(fig('nope'), []), isFalse);
    });
  });

  test('an alias filter selects the target move carrying the alias', () {
    final dance = ContraDbDance(
      id: 'x',
      moves: ['do si do', 'do si do'],
      aliases: ['see saw', null],
    );
    expect(matchingFigures(fig('see saw'), dance), {SearchMatch(0, 2)});
    expect(matchingFigures(fig('do si do'), dance), {
      SearchMatch(0, 2),
      SearchMatch(1, 2),
    });
  });

  test('an unknown operator raises', () {
    expect(
      () => matches(['bogus'], ['chain']),
      throwsA(isA<ContraDbReferenceError>()),
    );
  });
}
