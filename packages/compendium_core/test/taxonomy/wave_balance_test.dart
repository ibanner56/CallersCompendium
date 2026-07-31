import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Issue #295 (subsuming #296) — wave-formation balance.
///
/// Taxonomy v21 renames `form_a_short_wave` to `form_short_waves`, gives
/// `form_long_waves` the `whom` / `hand` / `balance` params The Caller's Box
/// states, and surfaces both moves' balance on the DISPLAY path (issue #296)
/// while `renderCanonical` stays byte-stable.
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);
  final d = Dialect.canonical;

  group('taxonomy v21 rename', () {
    test('form_short_waves resolves and the old id is gone', () {
      expect(tax.resolve('form_short_waves')?.id, 'form_short_waves');
      expect(tax.resolve('form_a_short_wave'), isNull);
      expect(tax.aliases['form_a_short_wave'], isNull);
    });

    test('its display label is "form short waves"', () {
      expect(tax.resolve('form_short_waves')!.displayName, 'form short waves');
    });

    test('the pre-rename label stays searchable', () {
      expect(
        tax.resolve('form_short_waves')!.searchKeywords,
        contains('form a wave'),
      );
    });

    test('the renamed move keeps the split param set', () {
      final def = tax.resolve('form_short_waves')!;
      expect(
        def.params.keys,
        containsAll(<String>[
          'dir',
          'balance',
          'center',
          'centerHand',
          'sides',
          'beats',
        ]),
      );
      expect(def.params['passThru'], isNull);
      expect(tax.validateFigure(Figure(move: 'form_short_waves')), isEmpty);
    });
  });

  group('taxonomy v21 form_long_waves params', () {
    test('gains whom / hand / balance, all defaulting to "states nothing"', () {
      final def = tax.resolve('form_long_waves')!;
      expect(def.params['whom']!.defaultValue, ParamVocab.unspecified);
      expect(def.params['hand']!.defaultValue, ParamVocab.unspecified);
      expect(def.params['balance']!.defaultValue, isFalse);
      // `who` keeps its ContraDB meaning (the pair that faces IN).
      expect(def.params['who']!.defaultValue, 'role1s');
    });

    test('validates across the new domains', () {
      expect(
        tax.validateFigure(
          Figure(
            move: 'form_long_waves',
            params: const {
              'who': 'role2s',
              'whom': 'nextNeighbors',
              'hand': 'left',
              'balance': true,
              'beats': 4,
            },
          ),
        ),
        isEmpty,
      );
    });

    test('rejects a hand outside right/left/unspecified', () {
      expect(
        tax.validateFigure(
          Figure(move: 'form_long_waves', params: const {'hand': 'sideways'}),
        ),
        isNotEmpty,
      );
    });

    test('a balance-a-wave line\'s 4 beats is not flagged as atypical', () {
      expect(
        tax.validateFigure(
          Figure(move: 'form_long_waves', params: const {'beats': 4}),
        ),
        isEmpty,
      );
    });
  });

  group('canonical text is byte-stable (renderCanonical)', () {
    test('form_short_waves canonical ignores every param', () {
      const params = {
        'dir': 'rightDiagonal',
        'balance': true,
        'center': 'role1s',
        'centerHand': 'left',
        'sides': 'partners',
        'beats': 8,
      };
      expect(
        renderer.renderCanonical(Figure(move: 'form_short_waves')),
        'form short waves',
      );
      expect(
        renderer.renderCanonical(
          Figure(move: 'form_short_waves', params: params),
        ),
        'form short waves',
      );
    });

    test('form_long_waves canonical is unchanged by the new params', () {
      final bare = renderer.renderCanonical(Figure(move: 'form_long_waves'));
      expect(bare, 'role1s form long waves');
      expect(
        renderer.renderCanonical(
          Figure(
            move: 'form_long_waves',
            params: const {
              'whom': 'neighbors',
              'hand': 'right',
              'balance': true,
            },
          ),
        ),
        bare,
      );
    });
  });

  group('form_long_waves display (#295/#296)', () {
    test('unset whom/hand render exactly as before the change', () {
      expect(
        renderer.render(Figure(move: 'form_long_waves'), d),
        'form long waves - role1s facing in, role2s facing out',
      );
    });

    test('a stated pair + hand adds the hold clause', () {
      expect(
        renderer.render(
          Figure(
            move: 'form_long_waves',
            params: const {
              'who': 'role2s',
              'whom': 'neighbors',
              'hand': 'right',
            },
          ),
          d,
        ),
        'form long waves - neighbor by the right, role2s facing in, '
        'role1s facing out',
      );
    });

    test('a half-stated hold (pair without hand) drops the whole clause', () {
      expect(
        renderer.render(
          Figure(move: 'form_long_waves', params: const {'whom': 'neighbors'}),
          d,
        ),
        'form long waves - role1s facing in, role2s facing out',
      );
    });

    test('a set balance appends " - and balance"', () {
      expect(
        renderer.render(
          Figure(
            move: 'form_long_waves',
            params: const {
              'who': 'role2s',
              'whom': 'neighbors',
              'hand': 'left',
              'balance': true,
            },
          ),
          d,
        ),
        'form long waves - neighbor by the left, role2s facing in, '
        'role1s facing out - and balance',
      );
    });

    test('an explicit balance:false renders no clause', () {
      expect(
        renderer.render(
          Figure(move: 'form_long_waves', params: const {'balance': false}),
          d,
        ),
        isNot(contains('balance')),
      );
    });

    test('a wildcard balance stays visible rather than being dropped', () {
      expect(
        renderer.render(
          Figure(move: 'form_long_waves', params: const {'balance': '*'}),
          d,
        ),
        endsWith(' - and *'),
      );
    });
  });

  group('form_short_waves display balance (#296)', () {
    test('no balance renders no clause', () {
      expect(
        renderer.render(Figure(move: 'form_short_waves'), d),
        'form short waves - role2s by the right in the center, '
        'neighbor by the left on the sides',
      );
    });

    test('a set balance appends " - and balance"', () {
      expect(
        renderer.render(
          Figure(move: 'form_short_waves', params: const {'balance': true}),
          d,
        ),
        'form short waves - role2s by the right in the center, '
        'neighbor by the left on the sides - and balance',
      );
    });
  });

  group('renderSummary surfaces the balance exactly once (#296)', () {
    for (final move in const ['form_short_waves', 'form_long_waves']) {
      test('$move summary carries one balance clause', () {
        final summary = renderer.renderSummary(
          Figure(move: move, params: const {'balance': true}),
          d,
        );
        expect(summary, contains('and balance'));
        // The generic "balance &" prefix must NOT also fire — these moves
        // render their own balance in the base line.
        expect(summary, isNot(startsWith('balance')));
        expect('and balance'.allMatches(summary).length, 1);
      });

      test('$move summary is unchanged without a balance', () {
        expect(
          renderer.renderSummary(Figure(move: move), d),
          isNot(contains('balance')),
        );
      });
    }
  });
}
