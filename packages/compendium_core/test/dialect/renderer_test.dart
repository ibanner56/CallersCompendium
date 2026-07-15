import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  final renderer = FigureRenderer(contraTaxonomy);
  final larks = Dialect.larksRobins;

  group('canonical rendering (golden)', () {
    final cases = <String, Figure>{
      'partners swing': Figure(move: 'swing', params: {'who': 'partners'}),
      'neighbors allemande right once': Figure(move: 'allemande'),
      'neighbors allemande left 1½': Figure(
        move: 'allemande',
        params: {'hand': 'left', 'turn': 1.5},
      ),
      'partners do si do once': Figure(
        move: 'do_si_do',
        params: {'who': 'partners'},
      ),
      'balance the ring': Figure(move: 'balance_the_ring'),
      'pass through across': Figure(
        move: 'pass_through',
        params: {'dir': 'across'},
      ),
      'role2s chain across': Figure(move: 'chain'),
      // Role tokens stay canonical (no dialect) in canonical rendering.
      'role1s swing': Figure(move: 'swing', params: {'who': 'role1s'}),
    };

    cases.forEach((expected, figure) {
      test('"$expected"', () {
        expect(renderer.renderCanonical(figure), expected);
      });
    });

    test('quarter-turn rotation words', () {
      String r(num t) => renderer.renderCanonical(
        Figure(move: 'allemande', params: {'turn': t}),
      );
      expect(r(0.5), contains('½'));
      expect(r(0.75), contains('¾'));
      expect(r(2), contains('twice'));
      expect(r(2.5), endsWith('2½'));
    });
  });

  group('aliases render under their own name', () {
    test('see saw, not do si do', () {
      expect(
        renderer.renderCanonical(Figure(move: 'see_saw')),
        'neighbors see saw once',
      );
    });

    test('meltdown swing', () {
      expect(
        renderer.renderCanonical(Figure(move: 'meltdown_swing')),
        'partners meltdown swing',
      );
    });
  });

  group('custom figures', () {
    test('render their (dialect-processed) free text', () {
      expect(
        renderer.renderCanonical(
          Figure(move: customMove, params: {'text': 'weave the ring'}),
        ),
        'weave the ring',
      );
    });

    test('blank custom text falls back to the move name', () {
      expect(renderer.renderCanonical(Figure(move: customMove)), 'custom');
    });
  });

  group('display rendering applies dialect', () {
    test('role tokens map to dialect terms', () {
      expect(
        renderer.render(
          Figure(move: 'swing', params: {'who': 'role1s'}),
          larks,
        ),
        'Larks swing',
      );
      expect(
        renderer.render(Figure(move: 'chain'), larks),
        'Robins chain across',
      );
    });

    test('non-role dancers are untouched by role dialect', () {
      expect(
        renderer.render(
          Figure(move: 'swing', params: {'who': 'partners'}),
          larks,
        ),
        'partners swing',
      );
    });

    test('move-name substitution with %S injects the shoulder side', () {
      final dialect = larks.copyWith(
        moves: {'shoulder_round': '%S shoulder round'},
      );
      expect(
        renderer.render(
          Figure(
            move: 'shoulder_round',
            params: {'who': 'partners', 'shoulder': 'left'},
          ),
          dialect,
        ),
        'partners left shoulder round once',
      );
    });

    test('canonical dialect renders role tokens as themselves', () {
      expect(
        renderer.render(
          Figure(move: 'swing', params: {'who': 'role2s'}),
          Dialect.canonical,
        ),
        'role2s swing',
      );
    });

    test('a dancer token renders its substitution', () {
      final dialect = larks.copyWith(dancers: {'partners': 'sweethearts'});
      expect(
        renderer.render(
          Figure(move: 'swing', params: {'who': 'partners'}),
          dialect,
        ),
        'sweethearts swing',
      );
    });

    test('dancer substitution does not touch role tokens', () {
      // role1s flows through role-term substitution, not dancer substitution,
      // even when a dancers entry for it is (incorrectly) present.
      final dialect = larks.copyWith(dancers: {'role1s': 'SHOULD_NOT_SHOW'});
      expect(
        renderer.render(
          Figure(move: 'swing', params: {'who': 'role1s'}),
          dialect,
        ),
        'Larks swing',
      );
    });

    test('dancer substitution and role substitution coexist', () {
      final dialect = larks.copyWith(dancers: {'neighbors': 'the others'});
      // neighbors -> dancer substitution; chain's role2s -> role term.
      expect(
        renderer.render(Figure(move: 'chain'), dialect),
        'Robins chain across',
      );
      expect(
        renderer.render(
          Figure(move: 'swing', params: {'who': 'neighbors'}),
          dialect,
        ),
        'the others swing',
      );
    });

    test('an unmapped dancer token falls back to humanized text', () {
      final dialect = larks.copyWith(dancers: {'neighbors': 'the others'});
      expect(
        renderer.render(
          Figure(move: 'swing', params: {'who': 'nextNeighbors'}),
          dialect,
        ),
        'next neighbors swing',
      );
    });
  });

  group('free-text rendering', () {
    test('substitutes role terms with case preservation', () {
      expect(
        renderer.renderFreeText('the role1s lead', larks),
        'the Larks lead',
      );
      expect(renderer.renderFreeText('ROLE1S first', larks), 'LARKS first');
    });

    test('leaves unrelated prose untouched', () {
      expect(
        renderer.renderFreeText('swing your neighbor', larks),
        'swing your neighbor',
      );
    });
  });

  group('unknown moves', () {
    test('fall back to the raw move id rather than losing data', () {
      expect(
        renderer.renderCanonical(Figure(move: 'mystery_move')),
        'mystery_move',
      );
    });
  });

  group('verbose (spoken-friendly) rendering', () {
    test('spells out mixed-turn rotations, no glyphs', () {
      expect(
        renderer.renderVerbose(
          Figure(move: 'allemande', params: {'hand': 'left', 'turn': 1.5}),
          larks,
        ),
        'neighbors allemande left one and a half times',
      );
      expect(
        renderer.renderVerbose(
          Figure(move: 'allemande', params: {'turn': 1.25}),
          larks,
        ),
        'neighbors allemande right one and a quarter times',
      );
      expect(
        renderer.renderVerbose(
          Figure(move: 'allemande', params: {'turn': 1.75}),
          larks,
        ),
        'neighbors allemande right one and three quarters times',
      );
      expect(
        renderer.renderVerbose(
          Figure(move: 'allemande', params: {'turn': 2.5}),
          larks,
        ),
        'neighbors allemande right two and a half times',
      );
    });

    test('keeps caller words for whole turns', () {
      expect(
        renderer.renderVerbose(
          Figure(move: 'do_si_do', params: {'who': 'partners'}),
          larks,
        ),
        'partners do si do once',
      );
      expect(
        renderer.renderVerbose(
          Figure(move: 'allemande', params: {'turn': 2}),
          larks,
        ),
        'neighbors allemande right twice',
      );
    });

    test('describes partial single turns as travel around the ring', () {
      String r(num t) => renderer.renderVerbose(
        Figure(move: 'allemande', params: {'turn': t}),
        larks,
      );
      expect(r(0.25), endsWith('a quarter of the way'));
      expect(r(0.5), endsWith('halfway'));
      expect(r(0.75), endsWith('three quarters of the way'));
    });

    test('output carries no notation glyphs', () {
      for (final t in [0.25, 0.5, 0.75, 1, 1.5, 2, 2.5]) {
        final out = renderer.renderVerbose(
          Figure(move: 'allemande', params: {'turn': t}),
          larks,
        );
        expect(
          RegExp('[¼½¾]').hasMatch(out),
          isFalse,
          reason: 'verbose "$out" must not contain a fraction glyph',
        );
      }
    });

    test('is dialect-aware: role and dancer terms map like display', () {
      expect(
        renderer.renderVerbose(
          Figure(move: 'swing', params: {'who': 'role1s'}),
          larks,
        ),
        'Larks swing',
      );
      expect(
        renderer.renderVerbose(Figure(move: 'chain'), larks),
        'Robins chain across',
      );
    });

    test('spells out fraction params without camelCase', () {
      expect(
        renderer.renderVerbose(
          Figure(move: 'figure_8', params: {'half': 'threeQuarter'}),
          larks,
        ),
        'ones figure 8 three quarters',
      );
      expect(
        renderer.renderVerbose(
          Figure(move: 'figure_8', params: {'half': 'full'}),
          larks,
        ),
        'ones figure 8 the whole way',
      );
    });

    test('custom free text and unknown moves match render', () {
      expect(
        renderer.renderVerbose(
          Figure(move: customMove, params: {'text': 'weave the ring'}),
          larks,
        ),
        'weave the ring',
      );
      expect(
        renderer.renderVerbose(Figure(move: 'mystery_move'), larks),
        'mystery_move',
      );
    });
  });
}
