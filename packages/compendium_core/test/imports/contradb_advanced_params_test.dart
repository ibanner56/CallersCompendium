// Figure parameters in the ContraDB Advanced translation.
//
// The positions and value spellings under test come from reading ContraDB's
// `figure.js` / `param.js` and checking the value mappings against the importer
// on rendered figure lines. Nothing here runs ContraDB; the opt-in
// `tool/check_contradb_translation_live.dart` sends the same shapes and shows
// ContraDB accepts them, not that the dances it returns are the right ones.
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/imports/contradb_advanced_params.dart';
import 'package:test/test.dart';

/// The last formal's index for each ContraDB figure: its `beats`, which is the
/// final parameter of every figure that has one. From `figure.js`.
const Map<String, int> _lastFormal = {
  'allemande': 3,
  'allemande orbit': 4,
  'arch & dive': 1,
  'balance': 1,
  'balance the ring': 0,
  'box circulate': 3,
  'box the gnat': 3,
  'butterfly whirl': 0,
  'California twirl': 1,
  'chain': 3,
  'circle': 2,
  'contra corners': 2,
  'cross trails': 4,
  'do si do': 3,
  'dolphin hey': 3,
  'down the hall': 4,
  'up the hall': 4,
  'facing star': 3,
  'figure 8': 4,
  'form a long wave': 4,
  'form long waves': 1,
  'gate': 3,
  'give & take': 3,
  'gyre': 3,
  'hey': 9,
  'long lines': 1,
  'mad robin': 2,
  'pass by': 2,
  'pass through': 2,
  'petronella': 1,
  'poussette': 4,
  'promenade': 3,
  'pull by dancers': 3,
  'pull by direction': 3,
  'revolving door': 3,
  'right left through': 1,
  'roll away': 3,
  "Rory O'More": 3,
  'see saw': 3,
  'slice': 3,
  'slide along set': 1,
  'square through': 5,
  'stand still': 0,
  'star': 3,
  'swat the flea': 3,
  'swing': 2,
  'turn alone': 2,
  'zig zag': 3,
};

void main() {
  ContraDbAdvancedExpression translate(DanceFilter filter) {
    final result = translateDanceFilterToContraDb(filter);
    expect(result, isA<ContraDbAdvancedExpression>(), reason: '$result');
    return result as ContraDbAdvancedExpression;
  }

  List<Object?> leaf(String move, Map<String, Object?> params) =>
      translate(FigureFilter.leaf(move, params: params)).expression;

  Set<String> ignoredBy(String move, Map<String, Object?> params) =>
      translate(FigureFilter.leaf(move, params: params)).ignoredParams;

  List<String> figureNames(Object? expression) => [
    if (expression is List<Object?>)
      if (expression.isNotEmpty && expression.first == 'figure')
        expression[1] as String
      else
        for (final part in expression.skip(1)) ...figureNames(part),
  ];

  group('the parameter table, checked as a whole', () {
    final table = contraDbParamTable.toList();

    // The app params a move has, resolving an alias to its target move.
    Set<String> appParams(String move) {
      final direct = contraTaxonomy.moves[move];
      if (direct != null) return direct.params.keys.toSet();
      return contraTaxonomy
          .moves[contraTaxonomy.aliases[move]!.targetMove]!
          .params
          .keys
          .toSet();
    }

    test('it covers exactly the moves the plain table translates', () {
      expect(
        table.map((row) => row.move).toSet(),
        contraDbTranslatableMoveIds.toSet(),
      );
    });

    test(
      'every position is inside the ContraDB figure (more raises there)',
      () {
        for (final row in table) {
          final last = _lastFormal[row.figure];
          expect(last, isNotNull, reason: '${row.figure} has no formal count');
          for (final entry in row.positions.entries) {
            expect(
              entry.value,
              lessThanOrEqualTo(last!),
              reason: '${row.figure}.${entry.key} is at ${entry.value}',
            );
          }
          // No two params share a position.
          expect(
            row.positions.values.toSet().length,
            row.positions.length,
            reason: '${row.figure} reuses a position',
          );
        }
      },
    );

    test('beats is the last formal, except on the orbit figure, which has '
        'none', () {
      for (final row in table) {
        if (row.figure == 'allemande orbit') {
          expect(row.positions.containsKey('beats'), isFalse);
        } else {
          expect(
            row.positions['beats'],
            _lastFormal[row.figure],
            reason: '${row.figure} beats',
          );
        }
      }
    });

    test('every mapped param is a real param of its move', () {
      for (final row in table) {
        final real = appParams(row.move);
        for (final name in row.positions.keys) {
          expect(real, contains(name), reason: '${row.move}.$name');
        }
      }
    });

    test('the params left out are exactly the documented ones', () {
      // A new taxonomy param, or a mapping removed, changes this on purpose:
      // map it exactly, or add it here with the reason it has no ContraDB
      // counterpart.
      final mapped = <String, Set<String>>{};
      for (final row in table) {
        (mapped[row.move] ??= {}).addAll(row.positions.keys);
      }
      final leftOut = <String, List<String>>{};
      for (final move in mapped.keys.toList()..sort()) {
        final missing = appParams(move).difference(mapped[move]!).toList()
          ..sort();
        if (missing.isNotEmpty) leftOut[move] = missing;
      }
      expect(leftOut, const {
        // ContraDB has no such param, or the importer never sets it (it sees
        // only the rendered prose), so no ContraDB value corresponds.
        'balance': ['hand'],
        'butterfly_whirl': ['direction', 'who'],
        'circle': ['singleFile'],
        'contra_corners': ['custom'],
        // ContraDB's half_or_full stops at full, so an amount past it has
        // no ContraDB value (#2120); it has no double figure 8 either.
        'figure_8': ['amount', 'double', 'lead'],
        'form_long_waves': ['balance', 'whom', 'whomHand'],
        'gate': ['direction', 'pair', 'travel'],
        'hey': ['meetTarget', 'pass2'],
        // The alias pins it to long lines, the only formation ContraDB has
        // (taxonomy v39); any other is a `forward_and_back`, which ContraDB
        // does not define.
        'long_lines': ['formation'],
        'mad_robin': ['direction', 'whom'],
        'poussette': ['amount'],
        'promenade': ['destination', 'singleFile'],
        'roll_away': ['halfSashay'],
        'slice': ['by', 'return'],
        'swing': ['endFacing'],
        'turn_alone': ['custom'],
        'zig_zag': ['ender'],
      });
    });

    test('a leaf with params names only figures the plain leaf names', () {
      for (final move in contraDbTranslatableMoveIds) {
        final plain = figureNames(leaf(move, const {}));
        final withBeats = figureNames(leaf(move, const {'beats': 8}));
        expect(plain.toSet().containsAll(withBeats), isTrue, reason: move);
      }
    });
  });

  group('translated parameters', () {
    test('who and beats go to their positions, with * between', () {
      expect(leaf('swing', {'who': 'partners', 'beats': 16}), [
        'figure',
        'swing',
        'partners',
        '*',
        16,
      ]);
      expect(leaf('swing', {'prefix': 'meltdown'}), [
        'figure',
        'swing',
        '*',
        'meltdown',
      ]);
    });

    test('dancer sets use the strings ContraDB stores', () {
      for (final pair in const {
        'role1s': 'gentlespoons',
        'role2s': 'ladles',
        'ones': 'ones',
        'twos': 'twos',
        'partners': 'partners',
        'everyone': 'everyone',
        'sameRoles': 'same roles',
        'firstCorners': 'first corners',
        'secondCorners': 'second corners',
        'centers': 'centers',
        'neighbors': 'neighbors',
        'shadows': 'shadows',
      }.entries) {
        expect(leaf('pass_by', {'who': pair.key}), [
          'figure',
          'pass by',
          pair.value,
        ]);
      }
    });

    test('dancer values ContraDB can only store under another category are '
        'left out, never sent', () {
      for (final value in const [
        'prevNeighbors',
        'nextNeighbors',
        'thirdNeighbors',
        'fourthNeighbors',
        'secondShadows',
      ]) {
        final result = translate(
          FigureFilter.leaf('pass_by', params: {'who': value, 'beats': 2}),
        );
        // The beats is still applied; the dancer is named as left out.
        expect(result.expression, ['figure', 'pass by', '*', '*', 2]);
        expect(result.ignoredParams, {'pass_by.who'}, reason: value);
      }
    });

    test('hands and shoulders: right is true, left false', () {
      expect(leaf('chain', {'hand': 'left'}), ['figure', 'chain', '*', false]);
      expect(leaf('pass_by', {'shoulder': 'right'}), [
        'figure',
        'pass by',
        '*',
        true,
      ]);
    });

    test('rotations are degrees and places are 90 per place', () {
      expect(leaf('mad_robin', {'travel': 1.5}), [
        'figure',
        'mad robin',
        '*',
        540,
      ]);
      expect(leaf('circle', {'direction': 'left', 'places': 4}), [
        'figure',
        'circle',
        true,
        360,
      ]);
      // Not a quarter turn, or not a whole number of places: left out.
      expect(ignoredBy('mad_robin', {'travel': 1.3}), {'mad_robin.travel'});
      expect(ignoredBy('circle', {'places': 11}), {'circle.places'});
      expect(leaf('square_through', {'places': 3}), [
        'figure',
        'square through',
        '*',
        '*',
        '*',
        '*',
        270,
      ]);
      expect(ignoredBy('square_through', {'places': 5}), {
        'square_through.places',
      });
    });

    test('booleans and beats must be real booleans and whole counts', () {
      expect(leaf('petronella', {'balance': false, 'beats': 8}), [
        'figure',
        'petronella',
        false,
        8,
      ]);
      expect(ignoredBy('petronella', {'beats': 8.5}), {'petronella.beats'});
      expect(ignoredBy('petronella', {'beats': 0}), {'petronella.beats'});
    });

    test(
      'poussette clockwise is ContraDB\'s true, as the importer reads it',
      () {
        expect(leaf('poussette', {'direction': 'clockwise'}), [
          'figure',
          'poussette',
          '*',
          '*',
          '*',
          true,
        ]);
        expect(leaf('poussette', {'direction': 'counterclockwise'}), [
          'figure',
          'poussette',
          '*',
          '*',
          '*',
          false,
        ]);
      },
    );

    test('a free-text formal is filled with an empty string, not *', () {
      expect(leaf('contra_corners', {'beats': 16}), [
        'figure',
        'contra corners',
        '*',
        '',
        16,
      ]);
      expect(leaf('turn_alone', {'beats': 4}), [
        'figure',
        'turn alone',
        '*',
        '',
        4,
      ]);
    });

    test('figure 8 above is both stored spellings, so it is an or', () {
      expect(leaf('figure_8', {'where': 'above'}), [
        'or',
        ['figure', 'figure 8', '*', ''],
        ['figure', 'figure 8', '*', 'above'],
      ]);
      expect(leaf('figure_8', {'where': 'below', 'fraction': 'full'}), [
        'figure',
        'figure 8',
        '*',
        'below',
        '*',
        1.0,
      ]);
    });

    test('a hey ricochet is only ever true; its position is its slot', () {
      expect(leaf('hey', {'rico2': true, 'beats': 8}), [
        'figure',
        'hey',
        '*',
        '*',
        '*',
        '*',
        '*',
        '*',
        true,
        '*',
        '*',
        8,
      ]);
      expect(ignoredBy('hey', {'rico1': false}), {'hey.rico1'});
    });
  });

  group('aliases and their targets', () {
    test('an alias leaf with params pins its own parameter', () {
      // ContraDB drops the alias pin once a filter has parameters.
      expect(leaf('see_saw', {'who': 'neighbors'}), [
        'figure',
        'see saw',
        'neighbors',
        false,
      ]);
      expect(leaf('swat_the_flea', {'beats': 4}), [
        'figure',
        'swat the flea',
        '*',
        '*',
        false,
        4,
      ]);
    });

    test('an alias leaf with nothing to apply is the plain alias', () {
      expect(leaf('see_saw', {'shoulder': 'right'}), ['figure', 'see saw']);
    });

    test('a target move keeps excluding its alias, with its params', () {
      expect(leaf('do_si_do', {'travel': 1.5}), [
        '&',
        ['figure', 'do si do', '*', '*', 540],
        [
          'not',
          ['figure', 'see saw'],
        ],
      ]);
      expect(leaf('box_the_gnat', {'balance': true}), [
        '&',
        ['figure', 'box the gnat', '*', true],
        [
          'not',
          ['figure', 'swat the flea'],
        ],
      ]);
    });

    test('a swat the flea balance is only exact when false', () {
      expect(ignoredBy('swat_the_flea', {'balance': true}), {
        'swat_the_flea.balance',
      });
    });
  });

  group('allemande and pull by, which are two ContraDB figures each', () {
    test('an allemande with a pair is searched as an orbit too, without '
        'beats', () {
      expect(
        leaf('allemande', {
          'who': 'role2s',
          'hand': 'left',
          'travel': 1.5,
          'beats': 8,
        }),
        [
          'or',
          ['figure', 'allemande', 'ladles', false, 540, 8],
          ['figure', 'allemande orbit', 'ladles', false, 540],
        ],
      );
    });

    test(
      'no orbit for a beats other than 8, or a dancer that is not a pair',
      () {
        expect(leaf('allemande', {'who': 'role2s', 'beats': 16}), [
          'figure',
          'allemande',
          'ladles',
          '*',
          '*',
          16,
        ]);
        expect(leaf('allemande', {'who': 'neighbors', 'travel': 1.0}), [
          'figure',
          'allemande',
          'neighbors',
          '*',
          360,
        ]);
      },
    );

    test('pull by with a who is only the dancers figure', () {
      expect(leaf('pull_by', {'who': 'neighbors', 'balance': true}), [
        'figure',
        'pull by dancers',
        'neighbors',
        true,
      ]);
    });

    test('pull by across is only the direction figure', () {
      expect(leaf('pull_by', {'where': 'across', 'hand': 'left'}), [
        'figure',
        'pull by direction',
        '*',
        'across',
        false,
      ]);
    });

    test(
      'pull by with neither is either figure, each at its own positions',
      () {
        expect(leaf('pull_by', {'hand': 'right', 'beats': 2}), [
          'or',
          ['figure', 'pull by dancers', '*', '*', true, 2],
          ['figure', 'pull by direction', '*', '*', true, 2],
        ]);
      },
    );
  });

  group('what is left out is reported, never a refusal', () {
    test('a param ContraDB has no counterpart for is named and the rest '
        'applied', () {
      final result = translate(
        FigureFilter.leaf(
          'swing',
          params: {'who': 'partners', 'endFacing': 'out', 'beats': 16},
        ),
      );
      expect(result.expression, ['figure', 'swing', 'partners', '*', 16]);
      expect(result.ignoredParams, {'swing.endFacing'});
    });

    test('a figure whose params are all left out is searched plain', () {
      final result = translate(
        FigureFilter.leaf('swing', params: {'endFacing': 'out'}),
      );
      expect(result.expression, ['figure', 'swing']);
      expect(result.ignoredParams, {'swing.endFacing'});
    });

    test('unspecified is "not set", so it is not reported', () {
      expect(ignoredBy('chain', {'hand': 'unspecified'}), isEmpty);
    });

    test('a name the move does not have is reported', () {
      expect(ignoredBy('swing', {'nonsense': 1}), {'swing.nonsense'});
    });

    test('left-out params are collected across the whole tree', () {
      final result = translate(
        AndFilter([
          FigureFilter.leaf('swing', params: {'endFacing': 'out'}),
          NotFilter(
            FigureFilter.leaf('gate', params: {'direction': 'up', 'beats': 8}),
          ),
        ]),
      );
      expect(result.ignoredParams, {'swing.endFacing', 'gate.direction'});
    });

    test('a phrase section is still refused: ContraDB has none', () {
      final result = translateDanceFilterToContraDb(
        FigureFilter.leaf('swing', params: {'beats': 8}, section: 'A1'),
      );
      expect(result, isA<ContraDbAdvancedRefused>());
      expect(
        (result as ContraDbAdvancedRefused).reason,
        ContraDbAdvancedUnsupported.figureDetail,
      );
    });

    test('a move outside the table is still refused, params or not', () {
      final result = translateDanceFilterToContraDb(
        FigureFilter.leaf('meltdown_swing', params: {'beats': 8}),
      );
      expect(
        (result as ContraDbAdvancedRefused).reason,
        ContraDbAdvancedUnsupported.figureName,
      );
    });
  });
}
