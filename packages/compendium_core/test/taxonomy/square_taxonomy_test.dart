import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// ADR-007 §7.1's traditional core, without the `sq_` prefix.
const _coreCalls = {
  'swing', 'promenade', 'hand_turn', 'circle', 'forward_and_back',
  'pass_through', 'chain', 'star', 'balance', 'do_si_do', 'separate',
  'right_left_through', 'lead', 'face', 'pass_by', 'pull_by', 'hey',
  'turn_alone', 'shoulder_round', //
};

final _square = shippedTaxonomies.forForm(DanceForm.square);
final _renderer = FigureRenderer(_square);

String _canonical(Figure figure) => _renderer.renderCanonical(figure);
String _shown(Figure figure) => _renderer.render(figure, Dialect.larksRobins);
int? _beats(String move, [Map<String, Object?> params = const {}]) =>
    _square.effectiveParams(testFigure(move: move, params: params))['beats']
        as int?;

void main() {
  group('the registry', () {
    test('holds exactly ADR-007 §7.1\'s calls, each prefixed', () {
      expect(squareTaxonomy.form, DanceForm.square);
      expect(squareTaxonomy.moves.keys.toSet(), {
        for (final id in _coreCalls) 'sq_$id',
      });
      for (final id in squareTaxonomy.aliases.keys) {
        expect(id, startsWith(squareMovePrefix));
      }
    });

    test('a call whose name a contra move shares keeps contra\'s stem '
        '(ADR-007 §5.1)', () {
      for (final stem in [
        'swing',
        'promenade',
        'circle',
        'forward_and_back',
        'pass_through',
        'chain',
        'star',
        'balance',
        'do_si_do',
        'right_left_through',
        'pass_by',
        'pull_by',
        'hey',
        'turn_alone',
        'shoulder_round',
      ]) {
        // `pass_by` is a contra alias since taxonomy v40, a name of its own.
        final contraName =
            contraTaxonomy.moves[stem]?.displayName ??
            contraTaxonomy.aliases[stem]?.displayName;
        expect(contraName, isNotNull, reason: stem);
        expect(
          squareTaxonomy.moves['sq_$stem']?.displayName,
          contraName,
          reason: stem,
        );
      }
    });

    test('an unstated who, whom, hand or amount is unspecified (§5.7)', () {
      const unstated = {'who', 'whom', 'hand', 'travel', 'fraction', 'size'};
      for (final MapEntry(key: id, value: def)
          in squareTaxonomy.moves.entries) {
        for (final MapEntry(key: name, value: spec) in def.params.entries) {
          if (!unstated.contains(name)) continue;
          expect(
            spec.defaultValue,
            ParamVocab.unspecified,
            reason: '$id.$name',
          );
        }
      }
    });

    test('no selector names a role with a gendered word (§5.5)', () {
      const gendered = [
        'gent', 'lady', 'ladies', 'man', 'men', 'woman', 'women', //
        'boy', 'girl',
      ];
      for (final token in [
        ...squareSelectors,
        ...squareRoleSelectorWords.values,
      ]) {
        for (final word in gendered) {
          expect(token.toLowerCase(), isNot(contains(word)), reason: token);
        }
      }
    });

    test('every program label names a square move or alias', () {
      for (final id in squareCallPrograms.keys) {
        expect(
          squareTaxonomy.moves.containsKey(id) ||
              squareTaxonomy.aliases.containsKey(id),
          isTrue,
          reason: id,
        );
      }
      expect(squareCallPrograms['sq_see_saw'], CallerlabProgram.plus);
      expect(squareCallPrograms, isNot(contains('sq_hey')));
    });

    test('no square keyword is a phrase another form\'s text uses', () {
      // A keyword the square taxonomy adds to the search over every form
      // rewrites that phrase wherever it is searched. A phrase contra's or
      // English text already says, such as "single file" (contra's single
      // file promenade and circle), would then find the wrong dances.
      final withoutSquares = TaxonomyRegistry(
        base: contraTaxonomy,
        forms: [ecdTaxonomy],
      ).anyForm;
      String words(String token) => token
          .replaceAllMapped(RegExp('[A-Z]'), (m) => ' ${m[0]}')
          .toLowerCase()
          .trim();
      final phrases = <String>{};
      for (final taxonomy in [contraTaxonomy, ecdTaxonomy]) {
        for (final move in taxonomy.moves.values) {
          phrases.add(move.renderTemplate.toLowerCase());
          for (final spec in move.params.values) {
            for (final choice in spec.choices ?? const <String>[]) {
              phrases.add(words(choice));
            }
          }
        }
      }
      for (final (id, keywords) in [
        for (final m in squareTaxonomy.moves.values) (m.id, m.searchKeywords),
        for (final a in squareTaxonomy.aliases.values) (a.id, a.searchKeywords),
      ]) {
        for (final keyword in keywords) {
          final word = keyword.toLowerCase();
          if (canonicalizeMoveSearchText(word, withoutSquares) != word) {
            continue; // Another form already rewrites it the same way.
          }
          for (final phrase in phrases) {
            expect(
              phrase.contains(word),
              isFalse,
              reason: '$id: "$keyword" is in another form\'s "$phrase"',
            );
          }
        }
      }
    });

    test('no square name or keyword rewrites another form\'s search', () {
      // A search over every form rewrites a name or keyword to its move's
      // name (canonicalizeMoveSearchText), so a square keyword that is
      // another form's name would turn an English "arm turn" into a square
      // "hand turn".
      final others = <String, Set<String>>{};
      for (final taxonomy in [contraTaxonomy, ecdTaxonomy]) {
        for (final (name, keywords) in [
          for (final m in taxonomy.moves.values)
            (m.displayName, m.searchKeywords),
          for (final a in taxonomy.aliases.values)
            (a.displayName, a.searchKeywords),
        ]) {
          for (final word in [name, ...keywords]) {
            (others[word.toLowerCase()] ??= {}).add(name);
          }
        }
      }
      for (final (id, name, keywords) in [
        for (final m in squareTaxonomy.moves.values)
          (m.id, m.displayName, m.searchKeywords),
        for (final a in squareTaxonomy.aliases.values)
          (a.id, a.displayName, a.searchKeywords),
      ]) {
        for (final word in [name, ...keywords]) {
          // Every other form that uses the word must read it as this name.
          for (final theirs in others[word.toLowerCase()] ?? const <String>{}) {
            expect(theirs, name, reason: '$id: "$word"');
          }
        }
      }
    });

    test('a square dance resolves only squares and contra, not ECD', () {
      expect(_square.resolve('sq_allemande_left')?.id, 'sq_hand_turn');
      expect(_square.resolve('swing')?.id, 'swing');
      expect(_square.resolve('ecd_set'), isNull);
      expect(contraTaxonomy.resolve('sq_swing'), isNull);
    });
  });

  group('default beats follow the held squares (§7.1)', () {
    test('a swing is 8, or 16 with a balance', () {
      expect(_beats('sq_swing'), 8);
      expect(_beats('sq_swing', {'prefix': 'balance'}), 16);
    });

    test('a circle\'s beats follow its size and how far it goes', () {
      expect(_beats('sq_circle'), 8);
      expect(_beats('sq_circle', {'size': 'eight', 'fraction': 'full'}), 16);
      expect(_beats('sq_circle', {'size': 'eight', 'fraction': 'half'}), 8);
      expect(_beats('sq_circle', {'size': 'four', 'fraction': 'half'}), 4);
      // Parkes's three-quarter circle of four is 8, not CALLERLAB's 6.
      expect(
        _beats('sq_circle', {'size': 'four', 'fraction': 'threeQuarter'}),
        8,
      );
      // A stated count always wins.
      expect(
        _beats('sq_circle', {'size': 'eight', 'fraction': 'full', 'beats': 12}),
        12,
      );
    });

    test('a promenade to a destination is 16; part way is less', () {
      expect(_beats('sq_promenade', {'destination': 'home'}), 16);
      expect(_beats('sq_promenade', {'fraction': 'half'}), 8);
      expect(_beats('sq_promenade', {'fraction': 'threeQuarter'}), 12);
    });

    test('a chain across is 8, three quarters 10 and over and back 16; a '
        'right and left through with a full courtesy turn is 12', () {
      expect(_beats('sq_chain'), 8);
      expect(_beats('sq_chain', {'fraction': 'half'}), 8);
      expect(
        _beats('sq_chain', {'four': true, 'fraction': 'threeQuarter'}),
        10,
      );
      expect(_beats('sq_chain', {'fraction': 'full'}), 16);
      expect(_beats('sq_right_left_through'), 8);
      expect(_beats('sq_right_left_through', {'fullTurn': true}), 12);
    });

    test('a forward and back is always 8 in New England', () {
      expect(_beats('sq_forward_and_back'), 8);
      expect(_beats('sq_star', {'fraction': 'threeQuarter'}), 6);
      expect(_beats('sq_hey'), 16);
      expect(_beats('sq_face'), 0);
    });
  });

  group('validation', () {
    test('a held square\'s line validates', () {
      for (final figure in [
        Figure(move: 'sq_swing', params: {'who': 'heads', 'whom': 'opposites'}),
        Figure(
          move: 'sq_circle',
          params: {
            'who': 'heads',
            'size': 'four',
            'direction': 'left',
            'fraction': 'threeQuarter',
            'beats': 8,
          },
        ),
        Figure(
          move: 'sq_allemande_left',
          params: {'who': 'everyone', 'whom': 'corners', 'beats': 8},
        ),
        Figure(
          move: 'sq_promenade',
          params: {'who': 'headRole1s', 'destination': 'role2Place'},
        ),
      ]) {
        expect(
          _square
              .validateFigure(figure)
              .where((i) => i.severity == ValidationSeverity.error),
          isEmpty,
          reason: figure.move,
        );
      }
    });

    test('a contra-only selector is not a square selector', () {
      final issues = _square.validateFigure(
        invalidTestFigure(
          move: 'sq_swing',
          params: {'who': 'neighbors'},
          reason: 'neighbors is a contra selector, not a square one',
        ),
      );
      expect(
        issues.where((i) => i.severity == ValidationSeverity.error),
        isNotEmpty,
      );
    });

    test('a count the sources use is not flagged', () {
      for (final beats in [8, 12, 14, 16]) {
        expect(
          _square
              .validateFigure(
                testFigure(move: 'sq_swing', params: {'beats': beats}),
              )
              .map((i) => i.code),
          isNot(contains('atypical_beats')),
          reason: '$beats',
        );
      }
    });
  });

  group('rendering', () {
    test('canonical text keeps role tokens and says nothing unstated', () {
      expect(
        _canonical(
          Figure(
            move: 'sq_swing',
            params: {'who': 'heads', 'whom': 'opposites'},
          ),
        ),
        'heads swing opposites',
      );
      expect(
        _canonical(Figure(move: 'sq_forward_and_back')),
        'forward and back',
      );
      expect(
        _canonical(
          Figure(
            move: 'sq_promenade',
            params: {'who': 'headRole1s', 'destination': 'role2Place'},
          ),
        ),
        "head role1s promenade role2's place",
      );
    });

    test('a role a selector names shows the dialect\'s role term', () {
      expect(
        _shown(
          Figure(
            move: 'sq_promenade',
            params: {'who': 'headRole1s', 'destination': 'role2Place'},
          ),
        ),
        "head larks promenade robin's place",
      );
      expect(
        FigureRenderer.displayToken(
          'rightHandRole2',
          squareTaxonomy.moves['sq_swing']!.params['whom'],
          Dialect.larksRobins,
        ),
        'right-hand robin',
      );
    });

    test('a separate reads whom it goes around; a chain how far', () {
      expect(
        _canonical(
          Figure(
            move: 'sq_separate',
            params: {
              'who': 'heads',
              'around': 'aroundOne',
              'into': 'intoALine',
            },
          ),
        ),
        'heads separate around one into a line',
      );
      expect(
        _canonical(
          Figure(
            move: 'sq_chain',
            params: {
              'who': 'role2s',
              'four': true,
              'fraction': 'threeQuarter',
              'courtesy': 'powerTurn',
            },
          ),
        ),
        'four role2s chain three quarter power turn',
      );
      expect(
        _canonical(
          Figure(
            move: 'sq_circle',
            params: {'who': 'everyone', 'size': 'three', 'direction': 'left'},
          ),
        ),
        'everyone circle three left',
      );
      expect(
        _canonical(
          Figure(
            move: 'sq_star',
            params: {'who': 'heads', 'hand': 'right', 'size': 'three'},
          ),
        ),
        'heads right star three',
      );
    });

    test('an allemande alias reads by its own name', () {
      expect(
        _canonical(
          Figure(
            move: 'sq_allemande_left',
            params: {'who': 'everyone', 'whom': 'corners'},
          ),
        ),
        'everyone allemande left corners',
      );
    });

    test('a balance before a swing reads as contra\'s does', () {
      expect(
        _canonical(
          Figure(
            move: 'sq_swing',
            params: {'prefix': 'balance', 'whom': 'corners'},
          ),
        ),
        'balance & swing corners',
      );
    });
  });
}
