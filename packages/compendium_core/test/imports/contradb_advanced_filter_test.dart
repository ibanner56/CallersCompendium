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
      expect(expression(FigureFilter.leaf('do_si_do')), ['figure', 'do si do']);
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
      // The live importer reads ContraDB's `form an ocean wave` as
      // `form_short_waves` (not `pass_the_ocean`).
      expect(expression(FigureFilter.leaf('form_short_waves')), [
        'figure',
        'form an ocean wave',
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

  group('refused rather than approximated', () {
    test('tags', () {
      expect(refusal(const TagFilter('t1')), ContraDbAdvancedUnsupported.tag);
      expect(refusal(const UntaggedFilter()), ContraDbAdvancedUnsupported.tag);
    });

    test('figure parameters and sections', () {
      expect(
        refusal(FigureFilter.leaf('swing', params: {'beats': 8})),
        ContraDbAdvancedUnsupported.figureDetail,
      );
      expect(
        refusal(FigureFilter.leaf('swing', section: 'A1')),
        ContraDbAdvancedUnsupported.figureDetail,
      );
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
        // `pass_the_ocean` is ContraDB's `pass through` with an ocean-wave
        // parameter, not a figure of its own.
        'pass_the_ocean',
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
      // Aliases: the Collection stores them resolved (`see_saw` is a
      // `do_si_do`), and ContraDB's alias filters add parameter constraints
      // the Collection's alias leaf does not have.
      // `custom` / `star_promenade`: the importer sends unrecognised and
      // declined lines to the Collection's `custom`, so the two sets differ.
      for (final id in [
        'see_saw',
        'swat_the_flea',
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
          ThenFilter(
            FigureLeaf('swing', params: {'beats': 8}),
            FigureLeaf('chain'),
          ),
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
}
