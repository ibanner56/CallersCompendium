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

  group('renderSummary surfaces ContraDB secondary params', () {
    final d = Dialect.canonical;

    group('renderCanonical is unchanged (byte-identical)', () {
      // renderSummary must never leak into the search/dedupe canonical text.
      final cases = <String, Figure>{
        'everyone down the hall forward': Figure(move: 'down_the_hall'),
        'everyone up the hall forward': Figure(move: 'up_the_hall'),
        'role2s hey right': Figure(move: 'hey'),
        'partners zig zag left': Figure(move: 'zig_zag'),
        'petronella': Figure(move: 'petronella'),
        'everyone Rory O\'More right': Figure(move: 'rory_o_more'),
        'pull by along right': Figure(
          move: 'pull_by_direction',
          params: {'balance': true},
        ),
        'partners box circulate': Figure(
          move: 'box_circulate',
          params: {'balance': true},
        ),
        'partners box the gnat': Figure(
          move: 'box_the_gnat',
          params: {'balance': true},
        ),
        'partners swat the flea': Figure(
          move: 'swat_the_flea',
          params: {'balance': true},
        ),
        'partners star through': Figure(
          move: 'star_through',
          params: {'balance': true},
        ),
        'neighbors pull by right': Figure(
          move: 'pull_by_dancers',
          params: {'balance': true},
        ),
        'long lines': Figure(move: 'long_lines'),
      };
      cases.forEach((expected, figure) {
        test('"$expected"', () {
          expect(renderer.renderCanonical(figure), expected);
          // Exercising the display summary (both flavors) must not disturb the
          // canonical text that feeds search/dedupe.
          renderer.renderSummary(figure, d);
          renderer.renderSummary(figure, d, verbose: true);
          expect(renderer.renderCanonical(figure), expected);
        });
      });

      test('summary never mutates the canonical render', () {
        final figures = [
          Figure(move: 'down_the_hall', params: {'ender': 'circle'}),
          Figure(move: 'hey', params: {'length': 'full'}),
          Figure(move: 'zig_zag', params: {'ender': 'allemande'}),
        ];
        for (final f in figures) {
          final before = renderer.renderCanonical(f);
          renderer.renderSummary(f, d);
          expect(renderer.renderCanonical(f), before);
        }
      });
    });

    group('down/up-the-hall ender', () {
      test('default turn-couple ender is surfaced', () {
        expect(
          renderer.renderSummary(Figure(move: 'down_the_hall'), d),
          'everyone down the hall forward and turn as a couple',
        );
      });

      test('none ender adds no clause', () {
        final f = Figure(move: 'down_the_hall', params: {'ender': 'none'});
        expect(renderer.renderSummary(f, d), renderer.render(f, d));
      });

      test('circle ender reads "bend into a ring" (not "circle")', () {
        final f = Figure(move: 'down_the_hall', params: {'ender': 'circle'});
        expect(
          renderer.renderSummary(f, d),
          'everyone down the hall forward and bend into a ring',
        );
      });

      test('bendTheLine (CallersBox-origin) reads "bend the line"', () {
        final f = Figure(
          move: 'down_the_hall',
          params: {'ender': 'bendTheLine'},
        );
        expect(renderer.renderSummary(f, d), endsWith('and bend the line'));
      });

      test('every hall ender maps to its ContraDB string', () {
        String s(String ender) => renderer.renderSummary(
          Figure(move: 'down_the_hall', params: {'ender': ender}),
          d,
        );
        expect(s('turnAlone'), endsWith('and turn alone'));
        expect(s('cozy'), endsWith('and form a cozy line'));
        expect(s('cloverleaf'), endsWith('and bend into a cloverleaf'));
        expect(s('threadNeedle'), endsWith('and thread the needle'));
        expect(
          s('rightHandHigh'),
          endsWith('and right hand high, left hand low'),
        );
        expect(s('slidingDoors'), endsWith('and slide doors'));
      });

      test('up the hall default circle ender is surfaced', () {
        expect(
          renderer.renderSummary(Figure(move: 'up_the_hall'), d),
          'everyone up the hall forward and bend into a ring',
        );
      });
    });

    group('hey length', () {
      String s(String length) => renderer.renderSummary(
        Figure(move: 'hey', params: {'length': length}),
        d,
      );
      test('half (default) shows a compact "(half)" on screen', () {
        expect(
          renderer.renderSummary(Figure(move: 'hey'), d),
          'role2s hey right (half)',
        );
      });
      test('full shows "(full)" on screen', () {
        expect(s('full'), 'role2s hey right (full)');
      });
      test('lessThanHalf reads "until someone meets"', () {
        expect(s('lessThanHalf'), 'role2s hey right until someone meets');
      });
      test('betweenHalfAndFull reads the second-time clause', () {
        expect(
          s('betweenHalfAndFull'),
          'role2s hey right until someone meets the second time',
        );
      });
      test('verbose expands half/full to the spoken "hey" comma clause', () {
        final half = Figure(move: 'hey');
        final full = Figure(move: 'hey', params: {'length': 'full'});
        expect(
          renderer.renderSummary(half, d, verbose: true),
          'role2s hey right, half hey',
        );
        expect(
          renderer.renderSummary(full, d, verbose: true),
          'role2s hey right, full hey',
        );
      });
      test('verbose "until…" clauses match the visible ones', () {
        final f = Figure(move: 'hey', params: {'length': 'lessThanHalf'});
        expect(
          renderer.renderSummary(f, d, verbose: true),
          renderer.renderSummary(f, d),
        );
      });
    });

    group('zig-zag ender', () {
      test('none (default) adds no clause', () {
        final f = Figure(move: 'zig_zag');
        expect(renderer.renderSummary(f, d), renderer.render(f, d));
      });
      test('ring reads "into a ring"', () {
        expect(
          renderer.renderSummary(
            Figure(move: 'zig_zag', params: {'ender': 'ring'}),
            d,
          ),
          'partners zig zag left into a ring',
        );
      });
      test('allemande reads the comma-prefixed catching-hands clause', () {
        expect(
          renderer.renderSummary(
            Figure(move: 'zig_zag', params: {'ender': 'allemande'}),
            d,
          ),
          'partners zig zag left, trailing two catching hands',
        );
      });
    });

    group('balance flag prefix (ContraDB "balance &")', () {
      test('petronella (default balance) → "balance & petronella"', () {
        expect(
          renderer.renderSummary(Figure(move: 'petronella'), d),
          'balance & petronella',
        );
      });
      test('petronella balance:false drops the prefix', () {
        final f = Figure(move: 'petronella', params: {'balance': false});
        expect(renderer.renderSummary(f, d), 'petronella');
        expect(renderer.renderSummary(f, d), renderer.render(f, d));
      });
      test('pull_by_direction surfaces balance when set', () {
        final f = Figure(move: 'pull_by_direction', params: {'balance': true});
        expect(renderer.renderSummary(f, d), 'balance & pull by along right');
        // default (balance:false) is untouched.
        final g = Figure(move: 'pull_by_direction');
        expect(renderer.renderSummary(g, d), renderer.render(g, d));
      });
      test('rory_o_more inserts balance before the move name', () {
        // Our base render keeps the "everyone" subject first, so the connective
        // lands before the move name ("everyone balance & …"); ContraDB's exact
        // "balance & everyone …" order is not reachable from our base line.
        expect(
          renderer.renderSummary(Figure(move: 'rory_o_more'), d),
          'everyone balance & Rory O\'More right',
        );
        final f = Figure(move: 'rory_o_more', params: {'balance': false});
        expect(renderer.renderSummary(f, d), renderer.render(f, d));
      });
      test('box_circulate surfaces balance before the move name', () {
        final f = Figure(move: 'box_circulate', params: {'balance': true});
        expect(
          renderer.renderSummary(f, d),
          'partners balance & box circulate',
        );
        expect(
          renderer.renderSummary(f, d, verbose: true),
          'partners balance and box circulate',
        );
      });
      test('box_circulate default (balance:false) is unchanged', () {
        final f = Figure(move: 'box_circulate');
        expect(renderer.renderSummary(f, d), 'partners box circulate');
        expect(renderer.renderSummary(f, d), renderer.render(f, d));
      });
      test('pull_by_dancers inserts balance before the move name', () {
        final f = Figure(move: 'pull_by_dancers', params: {'balance': true});
        expect(
          renderer.renderSummary(f, d),
          'neighbors balance & pull by right',
        );
        expect(
          renderer.renderSummary(f, d, verbose: true),
          'neighbors balance and pull by right',
        );
        final g = Figure(move: 'pull_by_dancers');
        expect(renderer.renderSummary(g, d), renderer.render(g, d));
      });
      test('box_the_gnat surfaces balance (hand omitted, as base render)', () {
        // Our terse template is '{who} {move}', so the hand never shows in the
        // base line — the balance prefix is a pure addition, not a fabrication.
        final f = Figure(move: 'box_the_gnat', params: {'balance': true});
        expect(renderer.renderSummary(f, d), 'partners balance & box the gnat');
        final g = Figure(move: 'box_the_gnat', params: {'balance': false});
        expect(renderer.renderSummary(g, d), renderer.render(g, d));
      });
      test('swat_the_flea (alias) surfaces balance before its own name', () {
        // The alias renders under its own display name, and the connective is
        // spliced before "swat the flea" (not the target "box the gnat").
        final f = Figure(move: 'swat_the_flea', params: {'balance': true});
        expect(
          renderer.renderSummary(f, d),
          'partners balance & swat the flea',
        );
      });
      test('star_through surfaces balance (CallersBox connective)', () {
        // star_through is a CallersBox extension not modeled by ContraDB; the
        // "balance &" here is our own generic connective, not ContraDB wording.
        final f = Figure(move: 'star_through', params: {'balance': true});
        expect(renderer.renderSummary(f, d), 'partners balance & star through');
        final g = Figure(move: 'star_through', params: {'balance': false});
        expect(renderer.renderSummary(g, d), 'partners star through');
        expect(renderer.renderSummary(g, d), renderer.render(g, d));
      });
      test('verbose expands the connective to "balance and"', () {
        expect(
          renderer.renderSummary(Figure(move: 'petronella'), d, verbose: true),
          'balance and petronella',
        );
      });
      test('balance prefix still applies when the dialect renames the move', () {
        // The move name is matched AS RENDERED (post dialect substitution), so a
        // dialect that renames a balance move still gets the connective spliced
        // before the substituted name rather than silently dropping it.
        final renamed = Dialect.canonical.copyWith(
          moves: {'petronella': 'spin the top'},
        );
        expect(
          renderer.renderSummary(Figure(move: 'petronella'), renamed),
          'balance & spin the top',
        );
      });
      test('square_through (embedded balance) carries NO prefix', () {
        // ContraDB folds balance into square_through's pull-by breakdown, so a
        // leading prefix would fabricate wording it never emits.
        final f = Figure(move: 'square_through');
        expect(renderer.renderSummary(f, d), renderer.render(f, d));
      });
      test('wave-forming moves (embedded balance) carry NO prefix', () {
        for (final id in ['form_a_long_wave', 'form_an_ocean_wave']) {
          final f = Figure(move: id, params: {'balance': true});
          expect(renderer.renderSummary(f, d), renderer.render(f, d));
        }
      });
    });

    group('long_lines goBack direction', () {
      test('default (goBack:true) reads "forward & back"', () {
        expect(
          renderer.renderSummary(Figure(move: 'long_lines'), d),
          'long lines forward & back',
        );
      });
      test('goBack:false reads "forward"', () {
        final f = Figure(move: 'long_lines', params: {'goBack': false});
        expect(renderer.renderSummary(f, d), 'long lines forward');
      });
      test('verbose swaps "&" for the spoken "and"', () {
        expect(
          renderer.renderSummary(Figure(move: 'long_lines'), d, verbose: true),
          'long lines forward and back',
        );
        // "forward" has no connective, so both paths match.
        final f = Figure(move: 'long_lines', params: {'goBack': false});
        expect(
          renderer.renderSummary(f, d, verbose: true),
          renderer.renderSummary(f, d),
        );
      });
    });

    test('moves without surfaced secondary params are unchanged', () {
      // swing already carries its prefix via the render template.
      final f = Figure(move: 'swing', params: {'prefix': 'balance'});
      expect(renderer.renderSummary(f, d), renderer.render(f, d));
      expect(renderer.renderSummary(f, d), 'partners balance & swing');
    });

    test('summary is dialect-aware via its base render', () {
      // The move/role tokens still honor the dialect; the appended ender is
      // fixed structural vocabulary.
      final f = Figure(move: 'hey', params: {'length': 'full'});
      final larksSummary = renderer.renderSummary(f, Dialect.larksRobins);
      expect(larksSummary, endsWith(' (full)'));
      expect(larksSummary, startsWith(renderer.render(f, Dialect.larksRobins)));
    });
  });
}
