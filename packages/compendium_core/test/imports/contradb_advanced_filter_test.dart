import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// [translateDanceFilterToContraDb] maps the Advanced builder's filter tree onto
/// ContraDB's `filter_dances.rb` array language. Expected shapes below follow
/// that source's operators: `and`/`or`/`no` are dance-level, `&` is figurewise
/// and, `not` is figurewise not.
void main() {
  List<Object?> expression(DanceFilter filter) {
    final result = translateDanceFilterToContraDb(filter);
    expect(result, isA<ContraDbAdvancedExpression>(), reason: '$result');
    return (result as ContraDbAdvancedExpression).expression;
  }

  ContraDbAdvancedUnsupported refusal(DanceFilter filter) {
    final result = translateDanceFilterToContraDb(filter);
    expect(result, isA<ContraDbAdvancedRefused>(), reason: '$result');
    return (result as ContraDbAdvancedRefused).reason;
  }

  group('supported', () {
    test('a single figure', () {
      expect(expression(FigureFilter.leaf('swing')), ['figure', 'swing']);
    });

    test('resolves the Collection\'s move ids to ContraDB spelling', () {
      // The builder emits taxonomy ids (`FigureLeaf.move`), not display names;
      // ContraDB's `figure` operator is an exact, case-sensitive key.
      expect(expression(FigureFilter.leaf('california_twirl')), [
        'figure',
        'California twirl',
      ]);
      expect(expression(FigureFilter.leaf('rory_o_more')), [
        'figure',
        "Rory O'More",
      ]);
      expect(expression(FigureFilter.leaf('arch_and_dive')), [
        'figure',
        'arch & dive',
      ]);
      expect(expression(FigureFilter.leaf('give_and_take')), [
        'figure',
        'give & take',
      ]);
      expect(expression(FigureFilter.leaf('shoulder_round')), [
        'figure',
        'gyre',
      ]);
    });

    test('the Collection keeps an alias apart from its target move', () {
      // The importer stores a see saw as `see_saw`, not as a `do_si_do`
      // (likewise swat the flea / box the gnat), while ContraDB stores both
      // as the target move and answers `see saw` with an alias filter (the
      // target move with the alias's pinned parameter). So the Collection's
      // `do_si_do` is ContraDB's `do si do` minus its `see saw`.
      expect(expression(FigureFilter.leaf('see_saw')), ['figure', 'see saw']);
      expect(expression(FigureFilter.leaf('swat_the_flea')), [
        'figure',
        'swat the flea',
      ]);
      expect(expression(FigureFilter.leaf('do_si_do')), [
        '&',
        ['figure', 'do si do'],
        [
          'not',
          ['figure', 'see saw'],
        ],
      ]);
      expect(expression(FigureFilter.leaf('box_the_gnat')), [
        '&',
        ['figure', 'box the gnat'],
        [
          'not',
          ['figure', 'swat the flea'],
        ],
      ]);
    });

    test('a Collection move that is two ContraDB moves becomes their or', () {
      // The importer folds both `pull by dancers` and `pull by direction` into
      // `pull_by`, so the Collection's `pull_by` is exactly their union.
      expect(expression(FigureFilter.leaf('pull_by')), [
        'or',
        ['figure', 'pull by dancers'],
        ['figure', 'pull by direction'],
      ]);
    });

    test('all of → and, any of → or', () {
      final a = FigureFilter.leaf('swing');
      final b = FigureFilter.leaf('chain');
      expect(expression(AndFilter([a, b])), [
        'and',
        ['figure', 'swing'],
        ['figure', 'chain'],
      ]);
      expect(expression(OrFilter([a, b])), [
        'or',
        ['figure', 'swing'],
        ['figure', 'chain'],
      ]);
    });

    test('none of → no', () {
      expect(
        expression(
          NotFilter(
            OrFilter([FigureFilter.leaf('swing'), FigureFilter.leaf('chain')]),
          ),
        ),
        [
          'no',
          [
            'or',
            ['figure', 'swing'],
            ['figure', 'chain'],
          ],
        ],
      );
    });

    test('nested groups', () {
      expect(
        expression(
          AndFilter([
            FigureFilter.leaf('swing'),
            NotFilter(FigureFilter.leaf('chain')),
          ]),
        ),
        [
          'and',
          ['figure', 'swing'],
          [
            'no',
            ['figure', 'chain'],
          ],
        ],
      );
    });

    test('figure groups on one figure row: and → &, or → or', () {
      expect(
        expression(
          FigureFilter(FigureAnd([FigureLeaf('swing'), FigureLeaf('balance')])),
        ),
        [
          '&',
          ['figure', 'swing'],
          ['figure', 'balance'],
        ],
      );
      expect(
        expression(
          FigureFilter(FigureOr([FigureLeaf('swing'), FigureLeaf('balance')])),
        ),
        [
          'or',
          ['figure', 'swing'],
          ['figure', 'balance'],
        ],
      );
    });

    test('a top-level figure not means "no figure matches" → no', () {
      expect(expression(FigureFilter(FigureNot(FigureLeaf('swing')))), [
        'no',
        ['figure', 'swing'],
      ]);
    });

    test('a figure not inside a figure group is figurewise → not', () {
      expect(
        expression(
          FigureFilter(
            FigureAnd([FigureLeaf('swing'), FigureNot(FigureLeaf('balance'))]),
          ),
        ),
        [
          '&',
          ['figure', 'swing'],
          [
            'not',
            ['figure', 'balance'],
          ],
        ],
      );
    });

    test('any figure is ContraDB\'s wildcard, alone and as a then operand', () {
      expect(expression(FigureFilter(anyFigure)), ['figure', '*']);
      expect(expression(ThenFilter(anyFigure, FigureLeaf('swing'))), [
        'then',
        ['figure', '*'],
        ['figure', 'swing'],
      ]);
      expect(expression(ThenFilter(FigureLeaf('swing'), anyFigure)), [
        'then',
        ['figure', 'swing'],
        ['figure', '*'],
      ]);
      // "No figure at all", and a figurewise not of any figure.
      expect(expression(FigureFilter(FigureNot(anyFigure))), [
        'no',
        ['figure', '*'],
      ]);
      expect(
        expression(FigureFilter(FigureAnd([anyFigure, FigureLeaf('swing')]))),
        [
          '&',
          ['figure', '*'],
          ['figure', 'swing'],
        ],
      );
    });

    test('then: the second immediately follows the first', () {
      expect(expression(ThenFilter(FigureLeaf('swing'), FigureLeaf('chain'))), [
        'then',
        ['figure', 'swing'],
        ['figure', 'chain'],
      ]);
    });

    test('then operands are row-level: groups and a figure not', () {
      expect(
        expression(
          ThenFilter(
            FigureOr([FigureLeaf('swing'), FigureLeaf('balance')]),
            FigureNot(FigureLeaf('chain')),
          ),
        ),
        [
          'then',
          [
            'or',
            ['figure', 'swing'],
            ['figure', 'balance'],
          ],
          [
            'not',
            ['figure', 'chain'],
          ],
        ],
      );
    });

    test('a then inside a dance-level group', () {
      expect(
        expression(
          AndFilter([
            FigureFilter.leaf('hey'),
            ThenFilter(FigureLeaf('swing'), FigureLeaf('chain')),
          ]),
        ),
        [
          'and',
          ['figure', 'hey'],
          [
            'then',
            ['figure', 'swing'],
            ['figure', 'chain'],
          ],
        ],
      );
    });

    test('the expression is JSON-encodable', () {
      final body = buildContraDbFilterBody(
        expression(
          AndFilter([
            FigureFilter.leaf('swing'),
            NotFilter(FigureFilter.leaf('chain')),
          ]),
        ),
      );
      expect(jsonDecode(body)['filter'], isA<List<Object?>>());
    });
  });

  group('allemande under a figure-level not', () {
    const orbitOr = [
      'or',
      ['figure', 'allemande'],
      ['figure', 'allemande orbit'],
    ];

    test('drops the orbit branch, which the local `not` still matches', () {
      // Locally an `allemande orbit` is `meanwhile[allemande, orbit]`: its
      // orbit row is not an allemande, so the group matches `not allemande`.
      // ContraDB must not rule that figure out, so `not` takes the plain move.
      expect(
        expression(
          ThenFilter(FigureNot(FigureLeaf('allemande')), FigureLeaf('swing')),
        ),
        [
          'then',
          [
            'not',
            ['figure', 'allemande'],
          ],
          ['figure', 'swing'],
        ],
      );
    });

    test('with parameters, keeps only the allemande branch', () {
      final positive = expression(
        FigureFilter.leaf('allemande', params: const {'hand': 'right'}),
      );
      expect(positive.first, 'or', reason: '$positive');
      final negated = expression(
        ThenFilter(
          FigureNot(FigureLeaf('allemande', params: const {'hand': 'right'})),
          FigureLeaf('swing'),
        ),
      );
      expect(negated[1], ['not', positive[1]]);
    });

    test('a positive or doubly negated allemande still asks for the orbit', () {
      expect(expression(FigureFilter.leaf('allemande')), orbitOr);
      expect(
        expression(
          ThenFilter(
            FigureNot(FigureNot(FigureLeaf('allemande'))),
            FigureLeaf('swing'),
          ),
        )[1],
        [
          'not',
          ['not', orbitOr],
        ],
      );
      // The dance-level "no figure is an allemande" is a positive figure
      // question under `no`, so it asks for both.
      expect(expression(FigureFilter(FigureNot(FigureLeaf('allemande')))), [
        'no',
        orbitOr,
      ]);
    });
  });

  group('refused rather than approximated', () {
    test('tags', () {
      expect(refusal(const TagFilter('t1')), ContraDbAdvancedUnsupported.tag);
      expect(refusal(const UntaggedFilter()), ContraDbAdvancedUnsupported.tag);
    });

    test('a phrase section, which ContraDB cannot express', () {
      expect(
        refusal(FigureFilter.leaf('swing', section: 'A1')),
        ContraDbAdvancedUnsupported.figureDetail,
      );
      // Even with params that would otherwise translate.
      expect(
        refusal(
          FigureFilter.leaf('swing', params: {'beats': 8}, section: 'A1'),
        ),
        ContraDbAdvancedUnsupported.figureDetail,
      );
    });

    test('figure parameters are no longer a reason to refuse', () {
      final result = translateDanceFilterToContraDb(
        FigureFilter.leaf('swing', params: {'beats': 8}),
      );
      expect(result, isA<ContraDbAdvancedExpression>());
    });

    test('a move ContraDB does not define', () {
      expect(
        refusal(FigureFilter.leaf('not a real move')),
        ContraDbAdvancedUnsupported.figureName,
      );
      // A partial name is not a move either.
      expect(
        refusal(FigureFilter.leaf('swin')),
        ContraDbAdvancedUnsupported.figureName,
      );
      // Collection-only moves have no ContraDB figure at all.
      for (final id in [
        'two_hand_turn',
        'courtesy_turn',
        'star_through',
        'turn_as_couples',
        'orbit',
        'circular_hey',
        'starburst',
        // ContraDB has long lines only; `long_lines` (its alias) maps to it.
        'forward_and_back',
        // Each is a subset of ContraDB's single `form an ocean wave`.
        'pass_the_ocean',
        'form_short_waves',
      ]) {
        expect(
          refusal(FigureFilter.leaf(id)),
          ContraDbAdvancedUnsupported.figureName,
          reason: id,
        );
      }
    });

    test('a display name or ContraDB spelling is not a Collection move id', () {
      // The Collection resolves a typed name through the active dialect; this
      // translator never sees the dialect, so only exact ids are trusted.
      for (final name in ['do si do', 'Do Si Do', 'California Twirl', 'gyre']) {
        expect(
          refusal(FigureFilter.leaf(name)),
          ContraDbAdvancedUnsupported.figureName,
          reason: name,
        );
      }
    });

    test('moves whose ContraDB meaning differs or is lossy', () {
      // `meltdown_swing`: the importer stores a meltdown swing as a `swing`
      // with `prefix: meltdown`, so a leaf for the alias id matches nothing.
      // `custom` / `star_promenade`: the importer sends unrecognised and
      // declined lines to the Collection's `custom`, so the two sets differ.
      for (final id in [
        'meltdown_swing',
        'custom',
        'star_promenade',
        'allemande_orbit',
      ]) {
        expect(
          refusal(FigureFilter.leaf(id)),
          ContraDbAdvancedUnsupported.figureName,
          reason: id,
        );
      }
    });

    test('local-only conditions', () {
      expect(
        refusal(const MixerFilter(true)),
        ContraDbAdvancedUnsupported.other,
      );
      expect(
        refusal(StatusFilter(DanceStatus.values.first)),
        ContraDbAdvancedUnsupported.other,
      );
    });

    test('a then with an operand ContraDB cannot express is refused', () {
      expect(
        refusal(
          ThenFilter(FigureLeaf('swing', section: 'A1'), FigureLeaf('chain')),
        ),
        ContraDbAdvancedUnsupported.figureDetail,
      );
      expect(
        refusal(ThenFilter(FigureLeaf('swing'), FigureLeaf('swin'))),
        ContraDbAdvancedUnsupported.figureName,
      );
    });

    test('one unsupported operand refuses the whole tree', () {
      expect(
        refusal(AndFilter([FigureFilter.leaf('swing'), const TagFilter('t1')])),
        ContraDbAdvancedUnsupported.tag,
      );
      expect(
        refusal(
          NotFilter(
            OrFilter([FigureFilter.leaf('swing'), FigureFilter.leaf('swin')]),
          ),
        ),
        ContraDbAdvancedUnsupported.figureName,
      );
    });

    test('empty groups are refused', () {
      expect(refusal(const AndFilter([])), ContraDbAdvancedUnsupported.other);
      expect(refusal(const OrFilter([])), ContraDbAdvancedUnsupported.other);
    });
  });

  group('buildContraDbFilterBody', () {
    test('serializes the expression with default paging', () {
      final decoded = jsonDecode(buildContraDbFilterBody(['figure', 'swing']));
      expect(decoded, {
        'filter': ['figure', 'swing'],
        'count': contraDbSearchCount,
        'offset': 0,
        'sort_by': 'titleA',
      });
    });

    test('rejects an empty expression', () {
      expect(() => buildContraDbFilterBody([]), throwsArgumentError);
    });
  });

  group('the move table, checked as a whole', () {
    // Every other assertion here copies one entry. These check the table's
    // shape, so a typo or a stray entry cannot slip through unasserted.
    // The table's own keys, so a misspelt or stale one is visited (walking the
    // taxonomy instead would never reach a key that matches nothing in it).
    final tableIds = contraDbTranslatableMoveIds.toList();
    final translated = <String, Object?>{};
    for (final id in tableIds) {
      final t = translateDanceFilterToContraDb(FigureFilter.leaf(id));
      if (t is ContraDbAdvancedExpression) translated[id] = t.expression;
    }
    // `see_saw` and `swat_the_flea` are aliases, not entries of `moves`.
    final knownIds = {
      ...contraTaxonomy.moves.keys,
      ...contraTaxonomy.aliases.keys,
    };

    List<String> figureNames(Object? expression) => [
      if (expression is List<Object?>)
        if (expression.isNotEmpty && expression.first == 'figure')
          expression[1] as String
        else
          for (final part in expression.skip(1)) ...figureNames(part),
    ];

    test('every table key is a Collection move or alias, and translates', () {
      expect(tableIds.length, greaterThan(30));
      expect(
        tableIds.where((id) => !knownIds.contains(id)),
        isEmpty,
        reason: 'a key that is not a Collection move id is never asked about',
      );
      expect(translated.keys.toSet(), tableIds.toSet(), reason: 'refused');
    });

    test('the moves left out of the table are exactly the documented ones', () {
      // A rename or a new taxonomy move changes this set on purpose, so it is
      // decided (map it exactly, or refuse it) rather than defaulting to refused.
      final leftOut = knownIds.difference(tableIds.toSet()).toList()..sort();
      expect(leftOut, const [
        'circular_hey',
        'courtesy_turn',
        'custom',
        'form_short_waves',
        'forward_and_back',
        'meltdown_swing',
        'orbit',
        'pass_the_ocean',
        'pull_by_dancers',
        'pull_by_direction',
        'star_promenade',
        'star_through',
        'starburst',
        'turn_as_couples',
        'two_hand_turn',
      ]);
    });

    test('every name it asks for is a real ContraDB figure name', () {
      for (final entry in translated.entries) {
        final names = figureNames(entry.value);
        expect(names, isNotEmpty, reason: entry.key);
        for (final name in names) {
          expect(
            canonicalContraDbFigureQuery(name),
            name,
            reason: '${entry.key} asks for "$name"',
          );
        }
      }
    });

    test('see saw and swat the flea are asked for by their own moves only', () {
      for (final entry in translated.entries) {
        final names = figureNames(entry.value);
        if (entry.key != 'see_saw') {
          // do_si_do names it only inside `not`, to exclude it.
          expect(
            names.where((n) => n == 'see saw').length,
            entry.key == 'do_si_do' ? 1 : 0,
            reason: entry.key,
          );
        }
        if (entry.key != 'swat_the_flea') {
          expect(
            names.where((n) => n == 'swat the flea').length,
            entry.key == 'box_the_gnat' ? 1 : 0,
            reason: entry.key,
          );
        }
      }
    });

    test(
      'moves that cannot be exact are refused, each for the right reason',
      () {
        for (final id in const [
          'meltdown_swing',
          'star_promenade',
          'allemande_orbit',
          'pass_the_ocean',
          'form_short_waves',
          'custom',
        ]) {
          final t = translateDanceFilterToContraDb(FigureFilter.leaf(id));
          expect(t, isA<ContraDbAdvancedRefused>(), reason: id);
          expect(
            (t as ContraDbAdvancedRefused).reason,
            ContraDbAdvancedUnsupported.figureName,
            reason: id,
          );
        }
      },
    );
  });
}
