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

  group('swing prefix modifier', () {
    Figure swing(String prefix) =>
        Figure(move: 'swing', params: {'who': 'neighbors', 'prefix': prefix});

    test('none renders no prefix word', () {
      expect(
        renderer.render(swing('none'), Dialect.canonical),
        'neighbors swing',
      );
      expect(
        renderer.renderVerbose(swing('none'), Dialect.canonical),
        'neighbors swing',
      );
    });

    test('balance renders "balance & swing" / verbose "balance and swing"', () {
      expect(
        renderer.render(swing('balance'), Dialect.canonical),
        'neighbors balance & swing',
      );
      expect(
        renderer.renderVerbose(swing('balance'), Dialect.canonical),
        'neighbors balance and swing',
      );
    });

    test('meltdown renders "meltdown swing" (visual and verbose)', () {
      expect(
        renderer.render(swing('meltdown'), Dialect.canonical),
        'neighbors meltdown swing',
      );
      expect(
        renderer.renderVerbose(swing('meltdown'), Dialect.canonical),
        'neighbors meltdown swing',
      );
    });

    test('default swing (prefix omitted → none) is unchanged', () {
      expect(
        renderer.render(
          Figure(move: 'swing', params: {'who': 'partners'}),
          Dialect.canonical,
        ),
        'partners swing',
      );
    });

    test('meltdown_swing alias does not double the prefix word', () {
      // The alias display name already conveys the prefix; the pinned param
      // must not render a second time.
      expect(
        renderer.render(Figure(move: 'meltdown_swing'), Dialect.canonical),
        'partners meltdown swing',
      );
      expect(
        renderer.renderVerbose(
          Figure(move: 'meltdown_swing'),
          Dialect.canonical,
        ),
        'partners meltdown swing',
      );
    });

    test('prefix coexists with dialect role substitution', () {
      expect(
        renderer.render(
          Figure(move: 'swing', params: {'who': 'role1s', 'prefix': 'balance'}),
          larks,
        ),
        'larks balance & swing',
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
        'larks swing',
      );
      expect(
        renderer.render(Figure(move: 'chain'), larks),
        'robins chain across',
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
        'larks swing',
      );
    });

    test('dancer substitution and role substitution coexist', () {
      final dialect = larks.copyWith(dancers: {'neighbors': 'the others'});
      // neighbors -> dancer substitution; chain's role2s -> role term.
      expect(
        renderer.render(Figure(move: 'chain'), dialect),
        'robins chain across',
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
      // Mid-sentence lowercase source token stays lowercase (the shipped
      // default term is lowercase, and case is carried from the source token).
      expect(
        renderer.renderFreeText('the role1s lead', larks),
        'the larks lead',
      );
      // An UPPER-case source token still uppercases the substitution, and a
      // Title-case source token still Title-cases it — the case comes from the
      // matched context, not the stored (lowercase) term. This is what keeps a
      // sentence-initial role term capitalized when the source carries a capital.
      expect(renderer.renderFreeText('ROLE1S first', larks), 'LARKS first');
      expect(renderer.renderFreeText('Role1s lead', larks), 'Larks lead');
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
        'larks swing',
      );
      expect(
        renderer.renderVerbose(Figure(move: 'chain'), larks),
        'robins chain across',
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

  group('displayToken (editor single-token display)', () {
    final custom = Dialect(
      name: 'Custom',
      roles: const {
        'role1': RoleTerm('Jet'),
        'role2': RoleTerm('Ruby', plural: 'Rubies'),
      },
      dancers: const {'neighbors': 'countras'},
    );
    const dancerSpec = ParamSpec(ParamKind.dancerSet, defaultValue: 'role1s');
    const pairSpec = ParamSpec(ParamKind.dancerPair, defaultValue: 'role1s');
    const shoulderSpec = ParamSpec(ParamKind.shoulder, defaultValue: 'right');

    test('role tokens stay canonical under the canonical dialect', () {
      for (final token in ['role1', 'role2', 'role1s', 'role2s']) {
        expect(
          FigureRenderer.displayToken(token, dancerSpec, Dialect.canonical),
          token,
        );
      }
    });

    test('role tokens use role terms under Larks/Robins', () {
      expect(FigureRenderer.displayToken('role1', dancerSpec, larks), 'lark');
      expect(FigureRenderer.displayToken('role2', dancerSpec, larks), 'robin');
      expect(FigureRenderer.displayToken('role1s', dancerSpec, larks), 'larks');
      expect(
        FigureRenderer.displayToken('role2s', dancerSpec, larks),
        'robins',
      );
    });

    test('role tokens use custom role terms (incl. explicit plural)', () {
      expect(FigureRenderer.displayToken('role1s', dancerSpec, custom), 'Jets');
      expect(FigureRenderer.displayToken('role2s', pairSpec, custom), 'Rubies');
    });

    test('dancer tokens use dialect.dancers, else humanized', () {
      // Substituted under a dialect that maps the token.
      expect(
        FigureRenderer.displayToken('neighbors', dancerSpec, custom),
        'countras',
      );
      // Humanized when unmapped or under canonical.
      expect(
        FigureRenderer.displayToken('neighbors', dancerSpec, Dialect.canonical),
        'neighbors',
      );
      expect(
        FigureRenderer.displayToken('nextNeighbors', dancerSpec, custom),
        'next neighbors',
      );
    });

    test('structural / non-dialect tokens stay humanized', () {
      expect(
        FigureRenderer.displayToken('rightDiagonal', shoulderSpec, larks),
        'right diagonal',
      );
      // No spec at all -> humanized (canonical behavior preserved).
      expect(
        FigureRenderer.displayToken('threeQuarter', null, larks),
        'three quarter',
      );
      // A dancer-set token is NOT role/dancer-substituted through a non-dancer
      // spec, so it humanizes.
      expect(
        FigureRenderer.displayToken('neighbors', shoulderSpec, custom),
        'neighbors',
      );
    });
  });

  group('displayMoveName (editor move display)', () {
    test('plain taxonomy display name under canonical', () {
      expect(
        renderer.displayMoveName('do_si_do', Dialect.canonical),
        'do si do',
      );
      expect(renderer.displayMoveName('swing', Dialect.canonical), 'swing');
    });

    test('applies dialect move substitutions', () {
      final custom = Dialect(name: 'Custom', moves: const {'swing': 'buzz'});
      expect(renderer.displayMoveName('swing', custom), 'buzz');
      // Unmapped moves fall back to the taxonomy display name.
      expect(renderer.displayMoveName('do_si_do', custom), 'do si do');
    });

    test('injects %S from the figure shoulder/hand param', () {
      final custom = Dialect(
        name: 'Custom',
        moves: const {'allemande': '%S hand turn'},
      );
      expect(
        renderer.displayMoveName('allemande', custom, params: {'hand': 'left'}),
        'left hand turn',
      );
      // No side present -> %S collapses to empty and the result is trimmed, so
      // the editor's move field never shows a stray leading space.
      expect(renderer.displayMoveName('allemande', custom), 'hand turn');
    });

    test('unknown move id falls back to the raw id', () {
      expect(
        renderer.displayMoveName('mystery_move', Dialect.canonical),
        'mystery_move',
      );
    });
  });
}
