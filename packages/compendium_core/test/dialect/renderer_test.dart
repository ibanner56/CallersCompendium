import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

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
        testFigure(move: 'allemande', params: {'turn': t}),
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
    Figure swing(String prefix) => testFigure(
      move: 'swing',
      params: {'who': 'neighbors', 'prefix': prefix},
    );

    test('none renders no prefix word', () {
      expect(
        renderer.render(swing('none'), Dialect.canonical),
        'neighbor swing',
      );
      expect(
        renderer.renderVerbose(swing('none'), Dialect.canonical),
        'neighbor swing',
      );
    });

    test('balance renders "balance & swing" / verbose "balance and swing"', () {
      expect(
        renderer.render(swing('balance'), Dialect.canonical),
        'neighbor balance & swing',
      );
      expect(
        renderer.renderVerbose(swing('balance'), Dialect.canonical),
        'neighbor balance and swing',
      );
    });

    test('meltdown renders "meltdown swing" (visual and verbose)', () {
      expect(
        renderer.render(swing('meltdown'), Dialect.canonical),
        'neighbor meltdown swing',
      );
      expect(
        renderer.renderVerbose(swing('meltdown'), Dialect.canonical),
        'neighbor meltdown swing',
      );
    });

    test('default swing (prefix omitted → none) is unchanged', () {
      expect(
        renderer.render(
          Figure(move: 'swing', params: {'who': 'partners'}),
          Dialect.canonical,
        ),
        'partner swing',
      );
    });

    test('meltdown_swing alias does not double the prefix word', () {
      // The alias display name already conveys the prefix; the pinned param
      // must not render a second time.
      expect(
        renderer.render(Figure(move: 'meltdown_swing'), Dialect.canonical),
        'partner meltdown swing',
      );
      expect(
        renderer.renderVerbose(
          Figure(move: 'meltdown_swing'),
          Dialect.canonical,
        ),
        'partner meltdown swing',
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
          testFigure(move: customMove, params: {'text': 'weave the ring'}),
        ),
        'weave the ring',
      );
    });

    test('blank custom text falls back to the move name', () {
      expect(renderer.renderCanonical(testFigure(move: customMove)), 'custom');
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
      expect(renderer.render(Figure(move: 'chain'), larks), 'robins chain');
    });

    test('non-role dancers are untouched by role dialect', () {
      expect(
        renderer.render(
          Figure(move: 'swing', params: {'who': 'partners'}),
          larks,
        ),
        'partner swing',
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
        'partner left shoulder round once',
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
      expect(renderer.render(Figure(move: 'chain'), dialect), 'robins chain');
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
        'next neighbor swing',
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
        // invalid-fixture: move is deliberately outside the taxonomy — fall back to the raw move id rather than losing data
        renderer.renderCanonical(Figure(move: 'mystery_move')),
        'mystery_move',
      );
    });

    test('render/renderSummary degrade to raw id, params intact (#358)', () {
      // invalid-fixture: move is deliberately outside the taxonomy — render/renderSummary degrade to raw id, params intact (#358)
      final figure = Figure(
        move: 'future_move',
        params: {'beats': 12, 'flavor': 'spicy'},
      );
      expect(renderer.render(figure, larks), 'future_move');
      expect(renderer.renderSummary(figure, larks), 'future_move');
      expect(renderer.renderVerbose(figure, larks), 'future_move');
      // The best-effort render must not throw or mutate the stored params.
      expect(figure.params, {'beats': 12, 'flavor': 'spicy'});
    });
  });

  group('verbose (spoken-friendly) rendering', () {
    test('spells out mixed-turn rotations, no glyphs', () {
      expect(
        renderer.renderVerbose(
          Figure(move: 'allemande', params: {'hand': 'left', 'turn': 1.5}),
          larks,
        ),
        'neighbor allemande left one and a half times',
      );
      expect(
        renderer.renderVerbose(
          Figure(move: 'allemande', params: {'turn': 1.25}),
          larks,
        ),
        'neighbor allemande right one and a quarter times',
      );
      expect(
        renderer.renderVerbose(
          Figure(move: 'allemande', params: {'turn': 1.75}),
          larks,
        ),
        'neighbor allemande right one and three quarters times',
      );
      expect(
        renderer.renderVerbose(
          Figure(move: 'allemande', params: {'turn': 2.5}),
          larks,
        ),
        'neighbor allemande right two and a half times',
      );
    });

    test('keeps caller words for whole turns', () {
      expect(
        renderer.renderVerbose(
          Figure(move: 'do_si_do', params: {'who': 'partners'}),
          larks,
        ),
        'partner do si do once',
      );
      expect(
        renderer.renderVerbose(
          Figure(move: 'allemande', params: {'turn': 2}),
          larks,
        ),
        'neighbor allemande right twice',
      );
    });

    test('describes partial single turns as travel around the ring', () {
      String r(num t) => renderer.renderVerbose(
        testFigure(move: 'allemande', params: {'turn': t}),
        larks,
      );
      expect(r(0.25), endsWith('a quarter of the way'));
      expect(r(0.5), endsWith('halfway'));
      expect(r(0.75), endsWith('three quarters of the way'));
    });

    test('output carries no notation glyphs', () {
      for (final t in [0.25, 0.5, 0.75, 1, 1.5, 2, 2.5]) {
        final out = renderer.renderVerbose(
          testFigure(move: 'allemande', params: {'turn': t}),
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
        'robins chain',
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
          testFigure(move: customMove, params: {'text': 'weave the ring'}),
          larks,
        ),
        'weave the ring',
      );
      expect(
        // invalid-fixture: move is deliberately outside the taxonomy — custom free text and unknown moves match render
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

  // Issue #832. The four single-dancer identities are COMPOUND tokens, so the
  // whole-token `roleTokens` membership test never matched them and their
  // embedded role was never substituted: every display path fell through to
  // `_humanize` and read "twos role2". The right construction already existed
  // (`_singleDancerLabel`) but was wired to one caller, and it matched its
  // regex before consulting `Dialect.dancers`, so a substitution was ignored.
  group('single-dancer identities (#832)', () {
    const singleDancers = ParamVocab.singleDancers;
    final leads = Dialect.leadsFollows;
    // A dialect that rewords ONE identity, to prove a substitution beats the
    // `<ordinal> <role term>` default rather than being ignored — the exact
    // preference the reporter asked for ("robin two", not "second robin").
    final reworded = Dialect(
      name: 'Reworded',
      roles: const {'role1': RoleTerm('lark'), 'role2': RoleTerm('robin')},
      dancers: const {'twosRole2': 'robin two'},
    );
    const dancerSpec = ParamSpec(ParamKind.dancerSet, defaultValue: 'role1s');

    group('displayToken — the people picker / facet label path', () {
      // The whole vocabulary under every shipped dialect: a test pinning only
      // the reported `twosRole2` would pass while the general bug survived.
      const expected = {
        'onesRole1': ['first role1', 'first lark', 'first lead'],
        'onesRole2': ['first role2', 'first robin', 'first follow'],
        'twosRole1': ['second role1', 'second lark', 'second lead'],
        'twosRole2': ['second role2', 'second robin', 'second follow'],
      };
      for (final token in singleDancers) {
        test('$token under every shipped dialect', () {
          final want = expected[token]!;
          expect(
            FigureRenderer.displayToken(token, dancerSpec, Dialect.canonical),
            want[0],
          );
          expect(
            FigureRenderer.displayToken(token, dancerSpec, larks),
            want[1],
          );
          expect(
            FigureRenderer.displayToken(token, dancerSpec, leads),
            want[2],
          );
        });
      }

      test('a dialect substitution wins over the default', () {
        expect(
          FigureRenderer.displayToken('twosRole2', dancerSpec, reworded),
          'robin two',
        );
        // …and only for the token it names.
        expect(
          FigureRenderer.displayToken('twosRole1', dancerSpec, reworded),
          'second lark',
        );
      });

      test('not spec-gated: the label is right with no spec to hand', () {
        // Unlike the `dialect.dancers` lookup, which needs a dancer-kind spec,
        // these four are a closed structural vocabulary — like the role tokens
        // above, they read correctly whatever the caller has.
        expect(
          FigureRenderer.displayToken('twosRole2', null, larks),
          'second robin',
        );
        const shoulderSpec = ParamSpec(
          ParamKind.shoulder,
          defaultValue: 'right',
        );
        expect(
          FigureRenderer.displayToken('twosRole2', shoulderSpec, larks),
          'second robin',
        );
      });

      test('near-miss tokens still humanize rather than blanking', () {
        // OWASP / tolerant decode: unknown or malformed input must stay
        // VISIBLE. The helper returns null for a non-match so the caller's
        // `_humanize` fallback survives.
        expect(
          FigureRenderer.displayToken('twosRole3', dancerSpec, larks),
          'twos role3',
        );
        expect(
          FigureRenderer.displayToken('onesRole', dancerSpec, larks),
          'ones role',
        );
        expect(
          FigureRenderer.displayToken('threesRole1', dancerSpec, larks),
          'threes role1',
        );
        // Case-sensitive: the canonical token is camelCase.
        expect(
          FigureRenderer.displayToken('twosrole2', dancerSpec, larks),
          'twosrole2',
        );
      });

      test('non-compound dancer vocabulary is unaffected', () {
        expect(
          FigureRenderer.displayToken('role1s', dancerSpec, larks),
          'larks',
        );
        expect(
          FigureRenderer.displayToken('partners', dancerSpec, larks),
          'partners',
        );
        expect(
          FigureRenderer.displayToken('centers', dancerSpec, larks),
          'centers',
        );
      });
    });

    group('singleDancerDefaultTerm — the dialect editor row label', () {
      test('is the default, DELIBERATELY ignoring dialect.dancers', () {
        // The editor labels the row for the token being overridden, so it must
        // show the default wording rather than echoing the substitution the
        // user is typing into the adjacent field.
        expect(
          FigureRenderer.singleDancerDefaultTerm('twosRole2', reworded),
          'second robin',
        );
        expect(
          FigureRenderer.singleDancerDefaultTerm('twosRole2', larks),
          'second robin',
        );
      });

      test('is null for every non-identity token, so callers can chain it', () {
        for (final token in [
          'role1s',
          'partners',
          'centers',
          'twosRole3',
          'rightDiagonal',
          '',
        ]) {
          expect(
            FigureRenderer.singleDancerDefaultTerm(token, larks),
            isNull,
            reason: '$token is not a single-dancer identity',
          );
        }
      });
    });

    group('rendered figures', () {
      // `_renderValue` (template path): figure_8 renders `{who} {move} {half}`.
      final templateFigure = Figure(
        move: 'figure_8',
        params: {'who': 'twosRole2'},
      );
      // `_displayDancer` (display base-line path): swing has a base renderer.
      final baseLineFigure = Figure(
        move: 'swing',
        params: {'who': 'twosRole2'},
      );
      // `_singleDancerLabel`: the one site that was already correct, but which
      // ignored `dialect.dancers`.
      final dolphinFigure = Figure(
        move: 'dolphin_hey',
        params: {'whom': 'twosRole2'},
      );

      test('template path reads the dialect term', () {
        expect(
          renderer.render(templateFigure, larks),
          'second robin figure 8 half',
        );
        expect(
          renderer.render(templateFigure, leads),
          'second follow figure 8 half',
        );
      });

      test('base-line path reads the dialect term', () {
        expect(renderer.render(baseLineFigure, larks), 'second robin swing');
        expect(renderer.render(baseLineFigure, leads), 'second follow swing');
      });

      test('dolphin_hey now honours a substitution too', () {
        expect(
          renderer.render(dolphinFigure, larks),
          'dolphin hey - start with ones passing second robin by right '
          'shoulders',
        );
        expect(
          renderer.render(dolphinFigure, reworded),
          'dolphin hey - start with ones passing robin two by right shoulders',
        );
      });

      test('a substitution wins on the template and base-line paths', () {
        expect(
          renderer.render(templateFigure, reworded),
          'robin two figure 8 half',
        );
        expect(renderer.render(baseLineFigure, reworded), 'robin two swing');
      });

      test('verbose and summary agree with the terse render', () {
        for (final f in [templateFigure, baseLineFigure, dolphinFigure]) {
          expect(renderer.renderVerbose(f, larks), contains('second robin'));
          expect(renderer.renderSummary(f, larks), contains('second robin'));
        }
      });

      // THE property that keeps this a display fix instead of a migration:
      // canonicalText feeds `dance_fts`, the `dance_figures` projection and the
      // dedupe key, so it must stay byte-for-byte identical. The display branch
      // is gated on `!forCanonical` precisely for this.
      test('canonical render is BYTE-IDENTICAL (no migration)', () {
        expect(
          renderer.renderCanonical(templateFigure),
          'twos role2 figure 8 half',
        );
        expect(renderer.renderCanonical(baseLineFigure), 'twos role2 swing');
        expect(
          renderer.renderCanonical(dolphinFigure),
          'ones dolphin hey right',
        );
      });

      test('canonical render ignores a dialect substitution as well', () {
        // renderCanonical always passes Dialect.canonical, but assert the
        // property directly: no dialect wording may reach the stored text.
        for (final f in [templateFigure, baseLineFigure]) {
          expect(renderer.renderCanonical(f), isNot(contains('robin')));
          expect(renderer.renderCanonical(f), isNot(contains('second')));
        }
      });

      test('the display path under the canonical dialect uses the default', () {
        // `render(figure, Dialect.canonical)` legitimately diverges from
        // `renderCanonical(figure)` — documented on renderCanonical — and here
        // it reads the canonical-vocabulary default rather than the raw token.
        expect(
          renderer.render(baseLineFigure, Dialect.canonical),
          'second role2 swing',
        );
      });
    });

    // `_displayGroup` is guarded by an allow-list: `hey.meetTarget` declares
    // `choices` that exclude the identities, so this path is LATENT today, not
    // live. It is one taxonomy edit from live — the guard falls back to the
    // full `ParamVocab.dancerSets` for any MoveDef that omits `choices` — and
    // leaving it inconsistent with its sibling `_displayDancer` is exactly how
    // this bug class propagated in the first place. Exercised through the
    // documented fallback rather than left unproven.
    group('_displayGroup (latent: guarded by an allow-list today)', () {
      final heyDef = contraTaxonomy.resolve('hey')!;
      final unnarrowedHey = MoveDef(
        id: heyDef.id,
        displayName: heyDef.displayName,
        params: {
          for (final e in heyDef.params.entries)
            e.key: e.key == 'meetTarget'
                // Drop ONLY the `choices` narrowing, so the renderer takes its
                // `?? ParamVocab.dancerSets` fallback — which admits the four.
                ? ParamSpec(e.value.kind, defaultValue: e.value.defaultValue)
                : e.value,
        },
        renderTemplate: heyDef.renderTemplate,
        searchKeywords: heyDef.searchKeywords,
        goodBeats: heyDef.goodBeats,
        paramBeats: heyDef.paramBeats,
      );
      final unnarrowed = FigureRenderer(
        Taxonomy(
          version: contraTaxonomy.version,
          form: contraTaxonomy.form,
          moves: [
            for (final m in contraTaxonomy.moves.values)
              m.id == heyDef.id ? unnarrowedHey : m,
          ],
          aliases: contraTaxonomy.aliases.values.toList(),
        ),
      );
      final figure = invalidTestFigure(
        move: 'hey',
        params: {'meetTarget': 'twosRole2', 'length': 'lessThanHalf'},
        reason:
            'hey.meetTarget narrows its choices to the group dancer sets under '
            'the live taxonomy, so a single-dancer identity is out of domain '
            'there; this exercises the renderer against a MoveDef that omits '
            'the narrowing, which is the shape its allow-list fallback exists '
            'to handle.',
      );

      test('reads the dialect term, not the humanized token', () {
        expect(unnarrowed.render(figure, larks), contains('second robin meet'));
        expect(unnarrowed.render(figure, larks), isNot(contains('twos role2')));
      });

      test('honours a substitution', () {
        expect(unnarrowed.render(figure, reworded), contains('robin two meet'));
      });

      test('the live taxonomy still degrades an out-of-domain target', () {
        // The allow-list is why this is latent: under the shipped taxonomy the
        // same figure never reaches the branch at all.
        expect(renderer.render(figure, larks), contains('until someone meets'));
      });
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
          'down the hall and turn as a couple',
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
          'down the hall and bend into a ring',
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
          testFigure(move: 'down_the_hall', params: {'ender': ender}),
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
          'up the hall and bend into a ring',
        );
      });
    });

    group('hey length', () {
      // PR3 moved the hey length into the display base line (see the PR3 group
      // + `_displayBaseRenderers['hey']`); `_summarySuffix` no longer appends a
      // parenthetical, so the summary now equals the full base line.
      String s(String length) => renderer.renderSummary(
        testFigure(move: 'hey', params: {'length': length}),
        d,
      );
      test('half (default) names the length inline', () {
        expect(
          renderer.renderSummary(Figure(move: 'hey'), d),
          'role2s start a half hey - rights in center, lefts on ends',
        );
      });
      test('full names the length inline', () {
        expect(
          s('full'),
          'role2s start a full hey - rights in center, lefts on ends',
        );
      });
      test('lessThanHalf reads "until someone meets"', () {
        expect(
          s('lessThanHalf'),
          'role2s start a hey - rights in center, lefts on ends - until someone meets',
        );
      });
      test('betweenHalfAndFull reads the second-time clause', () {
        expect(
          s('betweenHalfAndFull'),
          'role2s start a hey - rights in center, lefts on ends - until someone meets the second time',
        );
      });
      // issue #576: a set `meetTarget` names WHICH pair you run until you meet.
      String sTarget(
        String length,
        String meetTarget,
      ) => renderer.renderSummary(
        invalidTestFigure(
          move: 'hey',
          params: {'length': length, 'meetTarget': meetTarget},
          reason:
              'callers pass an out-of-domain meetTarget to prove the renderer surfaces it rather than blanking it',
        ),
        d,
      );
      test('lessThanHalf names the meetTarget pair (bare "meet")', () {
        expect(
          sTarget('lessThanHalf', 'partners'),
          'role2s start a hey - rights in center, lefts on ends - until partners meet',
        );
      });
      test('betweenHalfAndFull names the meetTarget pair + second time', () {
        expect(
          sTarget('betweenHalfAndFull', 'partners'),
          'role2s start a hey - rights in center, lefts on ends - until partners meet the second time',
        );
      });
      test('meetTarget unspecified keeps the generic "someone" clause', () {
        expect(
          sTarget('lessThanHalf', 'unspecified'),
          'role2s start a hey - rights in center, lefts on ends - until someone meets',
        );
      });
      test('meetTarget is ignored for non-partial lengths (half/full)', () {
        expect(
          sTarget('half', 'partners'),
          'role2s start a half hey - rights in center, lefts on ends',
        );
        expect(
          sTarget('full', 'partners'),
          'role2s start a full hey - rights in center, lefts on ends',
        );
      });
      test(
        'an out-of-domain meetTarget falls back to "someone" (allow-list)',
        () {
          expect(
            sTarget('lessThanHalf', 'bogusToken'),
            'role2s start a hey - rights in center, lefts on ends - until someone meets',
          );
        },
      );
      test('summary equals the base line (no appended clause)', () {
        for (final length in [
          'half',
          'full',
          'lessThanHalf',
          'betweenHalfAndFull',
        ]) {
          final f = testFigure(move: 'hey', params: {'length': length});
          expect(renderer.renderSummary(f, d), renderer.render(f, d));
          expect(
            renderer.renderSummary(f, d, verbose: true),
            renderer.render(f, d),
          );
        }
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
          'zig left zag right with partner into a ring',
        );
      });
      test('allemande reads the comma-prefixed catching-hands clause', () {
        expect(
          renderer.renderSummary(
            Figure(move: 'zig_zag', params: {'ender': 'allemande'}),
            d,
          ),
          'zig left zag right with partner, trailing two catching hands',
        );
      });
    });

    group('balance flag prefix (ContraDB "balance &")', () {
      test(
        'petronella (leading, default balance) → "balance & petronella"',
        () {
          expect(
            renderer.renderSummary(Figure(move: 'petronella'), d),
            'balance & petronella',
          );
        },
      );
      test('petronella balance:false drops the prefix', () {
        final f = Figure(move: 'petronella', params: {'balance': false});
        expect(renderer.renderSummary(f, d), 'petronella');
        expect(renderer.renderSummary(f, d), renderer.render(f, d));
      });
      test('pull_by_direction (leading) surfaces balance when set', () {
        final f = Figure(move: 'pull_by_direction', params: {'balance': true});
        expect(renderer.renderSummary(f, d), 'balance & pull by right');
        // default (balance:false) is untouched.
        final g = Figure(move: 'pull_by_direction');
        expect(renderer.renderSummary(g, d), renderer.render(g, d));
      });
      test('rory_o_more (leading, balance before subject)', () {
        expect(
          renderer.renderSummary(Figure(move: 'rory_o_more'), d),
          'balance & Rory O\'More right',
        );
        final f = Figure(move: 'rory_o_more', params: {'balance': false});
        expect(renderer.renderSummary(f, d), renderer.render(f, d));
      });
      test('box_circulate (leading) surfaces balance when set', () {
        final f = Figure(move: 'box_circulate', params: {'balance': true});
        expect(
          renderer.renderSummary(f, d),
          'balance & box circulate - partner cross while others loop right',
        );
        expect(
          renderer.renderSummary(f, d, verbose: true),
          'balance and box circulate - partner cross while others loop right',
        );
      });
      test('box_circulate shows balance BY DEFAULT (unset balance)', () {
        // Ratified decision: ContraDB models box circulate with a default-true
        // balance, so an unset balance surfaces the prefix in display. The
        // taxonomy default stays false so renderCanonical is byte-stable.
        final f = Figure(move: 'box_circulate');
        expect(
          renderer.renderSummary(f, d),
          'balance & box circulate - partner cross while others loop right',
        );
        expect(
          renderer.renderSummary(f, d, verbose: true),
          'balance and box circulate - partner cross while others loop right',
        );
        // canonical is untouched by the display default.
        expect(renderer.renderCanonical(f), 'partners box circulate');
      });
      test('box_circulate explicit balance:false suppresses the prefix', () {
        final f = Figure(move: 'box_circulate', params: {'balance': false});
        expect(
          renderer.renderSummary(f, d),
          'box circulate - partner cross while others loop right',
        );
        expect(renderer.renderSummary(f, d), renderer.render(f, d));
      });
      test('pull_by_dancers (after-who) inserts balance before the move', () {
        final f = Figure(move: 'pull_by_dancers', params: {'balance': true});
        expect(
          renderer.renderSummary(f, d),
          'neighbor balance & pull by right',
        );
        expect(
          renderer.renderSummary(f, d, verbose: true),
          'neighbor balance and pull by right',
        );
        final g = Figure(move: 'pull_by_dancers');
        expect(renderer.renderSummary(g, d), renderer.render(g, d));
      });
      test('verbose expands the connective to "balance and"', () {
        expect(
          renderer.renderSummary(Figure(move: 'petronella'), d, verbose: true),
          'balance and petronella',
        );
      });
      test(
        'star_through carries no balance summary (not ContraDB-sourced)',
        () {
          // star_through is a CallersBox extension not modeled by ContraDB and,
          // as of taxonomy v12, its MoveDef declares no `balance` param (it
          // mirrors california_twirl). A plain star_through therefore never
          // surfaces a balance prefix — renderSummary matches render exactly.
          final f = Figure(move: 'star_through', params: {'who': 'partners'});
          expect(renderer.renderSummary(f, d), 'partner star through');
          expect(renderer.renderSummary(f, d), renderer.render(f, d));
        },
      );
      test('box_the_gnat (after-who) surfaces balance when set', () {
        // Our terse '{who} {move}' template omits the hand regardless of
        // balance, so adding "balance &" is a strict improvement, not a new
        // divergence (the hand omission is pre-existing base behavior).
        final f = Figure(move: 'box_the_gnat', params: {'balance': true});
        expect(renderer.renderSummary(f, d), 'partner balance & box the gnat');
        expect(
          renderer.renderSummary(f, d, verbose: true),
          'partner balance and box the gnat',
        );
        final g = Figure(move: 'box_the_gnat', params: {'balance': false});
        expect(renderer.renderSummary(g, d), renderer.render(g, d));
      });
      test('swat_the_flea (alias, after-who) surfaces balance', () {
        // The alias renders under its own name, so the connective must splice
        // before the RENDERED alias name ("swat the flea"), not the target's.
        final f = Figure(move: 'swat_the_flea', params: {'balance': true});
        expect(renderer.renderSummary(f, d), 'partner balance & swat the flea');
        expect(
          renderer.renderSummary(f, d, verbose: true),
          'partner balance and swat the flea',
        );
        final g = Figure(move: 'swat_the_flea', params: {'balance': false});
        expect(renderer.renderSummary(g, d), renderer.render(g, d));
      });
      test('square_through (excluded) carries NO balance prefix', () {
        final f = Figure(move: 'square_through');
        expect(renderer.renderSummary(f, d), renderer.render(f, d));
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
      expect(renderer.renderSummary(f, d), 'partner balance & swing');
    });

    test('summary is dialect-aware via its base render', () {
      // The move/role tokens still honor the dialect. PR3 moved the hey length
      // into the base line, so the summary now equals the (dialect-aware) base
      // render with no appended clause.
      final f = Figure(move: 'hey', params: {'length': 'full'});
      final larksSummary = renderer.renderSummary(f, Dialect.larksRobins);
      expect(larksSummary, renderer.render(f, Dialect.larksRobins));
      expect(larksSummary, startsWith('robins '));
    });
  });

  // PR1: DISPLAY parity with ContraDB `libfigure` (silenced default
  // direction/facing, omitted default subject, singularized positional dancer
  // sets, shoulder_round shoulder injection). The display path may diverge from
  // renderCanonical; renderCanonical (search/dedupe text) must stay unchanged.
  group('PR1 display parity (ContraDB libfigure)', () {
    final d = Dialect.canonical;

    group('renderCanonical is unchanged (the invariant)', () {
      // Every touched move: canonical keeps the plural subjects and the
      // silenced default tokens (dir/facing) that the display path drops.
      final cases = <String, Figure>{
        'pass through along': Figure(move: 'pass_through'),
        'right left through across': Figure(move: 'right_left_through'),
        'role2s chain across': Figure(move: 'chain'),
        // v30 (#989): canonical now always includes `turn` too (unless it's
        // the `unspecified` sentinel), matching the pre-existing rule for
        // `dir` — a concrete default is never silenced in canonical.
        'partners promenade counterclockwise across': Figure(move: 'promenade'),
        'pull by along right': Figure(move: 'pull_by_direction'),
        'everyone down the hall forward': Figure(move: 'down_the_hall'),
        'everyone up the hall forward': Figure(move: 'up_the_hall'),
        'everyone turn alone': Figure(move: 'turn_alone'),
        'everyone Rory O\'More right': Figure(move: 'rory_o_more'),
        // v26 (#843): `hand` was removed from star_promenade, so the canonical
        // render no longer carries it.
        'role1s star promenade ½': Figure(move: 'star_promenade'),
        'neighbors shoulder round once': Figure(move: 'shoulder_round'),
      };
      cases.forEach((expected, figure) {
        test('"$expected"', () {
          expect(renderer.renderCanonical(figure), expected);
        });
      });
    });

    group('silence default set-direction / facing', () {
      // ContraDB stringParamSetDirectionSilencingDefault / march_forward.
      test('pass_through drops the default "along"', () {
        expect(
          renderer.render(Figure(move: 'pass_through'), d),
          'pass through',
        );
      });
      test('pass_through keeps a non-default direction', () {
        expect(
          renderer.render(
            Figure(move: 'pass_through', params: {'dir': 'across'}),
            d,
          ),
          'pass through across',
        );
      });
      test('right_left_through drops the default "across"', () {
        expect(
          renderer.render(Figure(move: 'right_left_through'), d),
          'right left through',
        );
      });
      test(
        'chain drops the default "across" (subject role term kept plural)',
        () {
          expect(renderer.render(Figure(move: 'chain'), d), 'role2s chain');
          expect(
            renderer.render(Figure(move: 'chain'), Dialect.larksRobins),
            'robins chain',
          );
        },
      );
      test('chain keeps a non-default direction', () {
        expect(
          renderer.render(Figure(move: 'chain', params: {'dir': 'along'}), d),
          'role2s chain along',
        );
      });
      group('chain hand (#976)', () {
        // The role1s/role2s -> left/right table, cited to ContraDB
        // figure.js:256-263 chainChange. Silencing hides the hand exactly
        // when it agrees with the role word already in the text; a hand
        // that contradicts the role word must still render, hyphenated,
        // and before the move name (figure.js:266-278, live-curled
        // wording confirmed against contradb.com/dances/2107).
        test(
          'a pre-existing chain with no stored hand renders byte-identically '
          '(canonical too)',
          () {
            // Guards the "absent key" branch of the silencing check
            // (`rawHand is! String`, `renderer.dart`): a chain stored before
            // this release has no `hand` key at all (not even the
            // `unspecified` sentinel), and that absence must silence
            // identically to an explicit sentinel, on BOTH paths — this is
            // what keeps import-date irrelevant to a bare `role2s chain`'s
            // FTS/dedupe text. A direct assertion on the spec itself (the
            // sentinel is a real choice, and IS the default) lives in the
            // taxonomy test below, since rendering does not consult
            // `ParamSpec.choices` at all.
            expect(renderer.render(Figure(move: 'chain'), d), 'role2s chain');
            expect(
              renderer.renderCanonical(Figure(move: 'chain')),
              'role2s chain across',
            );
          },
        );
        test("chain.hand's spec genuinely declares the unspecified sentinel "
            'both as a choice and as the default', () {
          // Falsifies the claim the test above can only describe, not
          // enforce: rendering never reads `ParamSpec.choices`, so a
          // regression that dropped `ParamVocab.unspecified` from
          // chain.hand's `choices` (or changed its `defaultValue`) would
          // leave every render-level assertion above green. This test
          // reads the spec directly instead.
          final handSpec = contraTaxonomy.resolve('chain')!.params['hand']!;
          expect(handSpec.choices, contains(ParamVocab.unspecified));
          expect(handSpec.defaultValue, ParamVocab.unspecified);
        });
        test('a role-implied hand renders identically to an unstated hand '
            '(canonical too) — the newly-imported byte-identity guard', () {
          // Guards against making the silencing display-only: a bare
          // "ladies chain" imported today must produce the same
          // canonical/FTS text as an identical dance imported before
          // this release, or dedupe/search would diverge by import date.
          final withHand = Figure(
            move: 'chain',
            params: {'who': 'role2s', 'hand': 'right'},
          );
          final withoutHand = Figure(move: 'chain', params: {'who': 'role2s'});
          expect(renderer.render(withHand, d), renderer.render(withoutHand, d));
          expect(
            renderer.renderCanonical(withHand),
            renderer.renderCanonical(withoutHand),
          );
          expect(renderer.render(withHand, d), 'role2s chain');
          expect(renderer.renderCanonical(withHand), 'role2s chain across');

          final role1Hand = Figure(
            move: 'chain',
            params: {'who': 'role1s', 'hand': 'left'},
          );
          final role1NoHand = Figure(move: 'chain', params: {'who': 'role1s'});
          expect(
            renderer.render(role1Hand, d),
            renderer.render(role1NoHand, d),
          );
          expect(renderer.render(role1Hand, d), 'role1s chain');
        });
        test('silencing is role-relative, not spec-default-relative: a '
            'deliberate right-hand gents chain still renders', () {
          // Guards against reusing the _silencedDefaultParams shape, which
          // compares a stored value against the param's fixed SPEC default
          // (`unspecified` for chain.hand) rather than a sibling param:
          // role1s's implied side is "left", so a stated "right" contradicts
          // it and must survive — together with the role2s/"right" case
          // above (which DOES silence), this pins down that the comparison
          // is against the per-figure role-implied side, not any fixed
          // value.
          final deliberateRightForRole1 = Figure(
            move: 'chain',
            params: {'who': 'role1s', 'hand': 'right'},
          );
          expect(
            renderer.render(deliberateRightForRole1, d),
            'role1s right-hand chain',
          );
          expect(
            renderer.renderCanonical(deliberateRightForRole1),
            'role1s right-hand chain across',
          );
        });
        test('a contradicting hand is hyphenated and sits before the move, '
            'not after it and not bare', () {
          // Guards template order/wording: ContraDB's chainWords is
          // words(sdiag, swho, thand, smove) — hand before move — and
          // emits shand + "-hand", not a bare side.
          final leftForRole2 = Figure(
            move: 'chain',
            params: {'who': 'role2s', 'hand': 'left'},
          );
          expect(renderer.render(leftForRole2, d), 'role2s left-hand chain');
          expect(
            renderer.renderCanonical(leftForRole2),
            'role2s left-hand chain across',
          );
        });
      });
      test('promenade drops the default "across"', () {
        expect(
          renderer.render(Figure(move: 'promenade'), d),
          'partner promenade',
        );
      });
      test('promenade keeps a non-default direction and gains '
          'the default turn "counterclockwise"', () {
        expect(
          renderer.render(
            Figure(move: 'promenade', params: {'dir': 'along'}),
            d,
          ),
          'partner promenade counterclockwise along',
        );
      });
      test('promenade keeps a non-default direction and drops '
          'turn for directions without turns', () {
        expect(
          renderer.render(Figure(move: 'promenade', params: {'dir': 'up'}), d),
          'partner promenade up',
        );
      });
      test('promenade gains target when set', () {
        expect(
          renderer.render(
            Figure(
              move: 'promenade',
              params: {
                'dir': 'along',
                'destination': 'next neighbors',
                'turn': 'clockwise',
              },
            ),
            d,
          ),
          'partner promenade clockwise along to next neighbors',
        );
      });
      test('pull_by_direction drops the default "along"', () {
        expect(
          renderer.render(Figure(move: 'pull_by_direction'), d),
          'pull by right',
        );
      });
      test('pull_by_direction keeps a non-default direction', () {
        expect(
          renderer.render(
            Figure(move: 'pull_by_direction', params: {'dir': 'across'}),
            d,
          ),
          'pull by across right',
        );
      });
      test('down_the_hall drops the default "forward" facing', () {
        // Base render (no ender clause) omits the silenced facing.
        expect(
          renderer.render(
            Figure(move: 'down_the_hall', params: {'ender': 'none'}),
            d,
          ),
          'down the hall',
        );
      });
      test('down_the_hall keeps a non-default facing', () {
        expect(
          renderer.render(
            Figure(
              move: 'down_the_hall',
              params: {'ender': 'none', 'facing': 'backward'},
            ),
            d,
          ),
          'down the hall backward',
        );
      });
    });

    group('omit default subject', () {
      // ContraDB upOrDownTheHallWords (who === "everyone" ? "" : swho) and the
      // per-move subject omission; star_promenade omits its role subject.
      test('down_the_hall summary omits everyone + forward', () {
        expect(
          renderer.renderSummary(Figure(move: 'down_the_hall'), d),
          'down the hall and turn as a couple',
        );
      });
      test('up_the_hall summary omits everyone + forward', () {
        expect(
          renderer.renderSummary(Figure(move: 'up_the_hall'), d),
          'up the hall and bend into a ring',
        );
      });
      test('turn_alone omits the default everyone', () {
        expect(renderer.render(Figure(move: 'turn_alone'), d), 'turn alone');
      });
      test('rory_o_more summary omits everyone (balance leads)', () {
        expect(
          renderer.renderSummary(Figure(move: 'rory_o_more'), d),
          'balance & Rory O\'More right',
        );
      });
      test('star_promenade omits the default role1s subject', () {
        expect(
          renderer.render(Figure(move: 'star_promenade'), d),
          'star promenade ½',
        );
      });
      test('a non-default subject still renders (down_the_hall)', () {
        expect(
          renderer.render(
            Figure(
              move: 'down_the_hall',
              params: {'who': 'ones', 'ender': 'none'},
            ),
            d,
          ),
          'ones down the hall',
        );
      });
      test('a non-default subject still renders (star_promenade)', () {
        expect(
          renderer.render(
            Figure(move: 'star_promenade', params: {'who': 'role2s'}),
            d,
          ),
          'role2s star promenade ½',
        );
      });
    });

    group('singularize positional dancer sets (role tokens untouched)', () {
      test('partners → partner', () {
        expect(
          renderer.render(
            Figure(move: 'swing', params: {'who': 'partners'}),
            d,
          ),
          'partner swing',
        );
      });
      test('neighbors → neighbor', () {
        expect(
          renderer.render(
            Figure(move: 'swing', params: {'who': 'neighbors'}),
            d,
          ),
          'neighbor swing',
        );
      });
      test('shadows → shadow', () {
        expect(
          renderer.render(Figure(move: 'swing', params: {'who': 'shadows'}), d),
          'shadow swing',
        );
      });
      test('nextNeighbors → next neighbor', () {
        expect(
          renderer.render(
            Figure(move: 'swing', params: {'who': 'nextNeighbors'}),
            d,
          ),
          'next neighbor swing',
        );
      });
      // Mixer partner-series tokens (issue #732, v24).
      // Falsification target: removing one entry from `_singularDancerSets`
      // (e.g. `'nextPartners': 'next partner'`) causes that test to fail
      // because `_humanize('nextPartners')` returns 'next partners' (plural),
      // not 'next partner' — the `_singularDancerSets` map is the only route
      // to the correct singular form.
      test('prevPartners → prev partner', () {
        expect(
          renderer.render(
            Figure(move: 'swing', params: {'who': 'prevPartners'}),
            d,
          ),
          'prev partner swing',
        );
      });
      test('nextPartners → next partner', () {
        expect(
          renderer.render(
            Figure(move: 'swing', params: {'who': 'nextPartners'}),
            d,
          ),
          'next partner swing',
        );
      });
      test('thirdPartners → third partner', () {
        expect(
          renderer.render(
            Figure(move: 'swing', params: {'who': 'thirdPartners'}),
            d,
          ),
          'third partner swing',
        );
      });
      test('fourthPartners → fourth partner', () {
        expect(
          renderer.render(
            Figure(move: 'swing', params: {'who': 'fourthPartners'}),
            d,
          ),
          'fourth partner swing',
        );
      });
      test('fifthPartners → fifth partner', () {
        expect(
          renderer.render(
            Figure(move: 'swing', params: {'who': 'fifthPartners'}),
            d,
          ),
          'fifth partner swing',
        );
      });
      test('role tokens are NOT singularized (stay plural role terms)', () {
        expect(
          renderer.render(Figure(move: 'swing', params: {'who': 'role1s'}), d),
          'role1s swing',
        );
        expect(
          renderer.render(
            Figure(move: 'swing', params: {'who': 'role1s'}),
            Dialect.larksRobins,
          ),
          'larks swing',
        );
      });
      test('ones/everyone are NOT singularized', () {
        expect(
          renderer.render(Figure(move: 'swing', params: {'who': 'ones'}), d),
          'ones swing',
        );
      });
    });

    group('shoulder_round renders the shoulder in display', () {
      // ContraDB gyreWords expands %S to the shoulder side.
      test('default: neighbor right shoulder round once', () {
        expect(
          renderer.render(Figure(move: 'shoulder_round'), d),
          'neighbor right shoulder round once',
        );
      });
      test('non-default shoulder still renders', () {
        expect(
          renderer.render(
            Figure(move: 'shoulder_round', params: {'shoulder': 'left'}),
            d,
          ),
          'neighbor left shoulder round once',
        );
      });
      test('verbose keeps the injected shoulder', () {
        expect(
          renderer.renderVerbose(Figure(move: 'shoulder_round'), d),
          'neighbor right shoulder round once',
        );
      });
    });

    // Issue #873: pass_by and pass_through shoulder rendering.
    group(
      'pass_by renders the shoulder at every value (ContraDB figureGenericWords)',
      () {
        // ContraDB always emits the shoulder for pass by (figureGenericWords).
        // Word forms from ContraDB `stringParamShoulders`: "right shoulders" /
        // "left shoulders" / "* shoulders".
        test('default right: neighbor pass by right shoulders', () {
          expect(
            renderer.render(Figure(move: 'pass_by'), d),
            'neighbor pass by right shoulders',
          );
        });
        test('left: neighbor pass by left shoulders', () {
          expect(
            renderer.render(
              Figure(move: 'pass_by', params: {'shoulder': 'left'}),
              d,
            ),
            'neighbor pass by left shoulders',
          );
        });
        // invalid-fixture: value is deliberately out of domain — pass_by surfaces an unknown shoulder value via the %S expansion rather than blanking it
        test('wildcard: neighbor pass by * shoulders', () {
          expect(
            renderer.render(
              Figure(move: 'pass_by', params: {'shoulder': '*'}),
              d,
            ),
            'neighbor pass by * shoulders',
          );
        });
        test('verbose output matches terse', () {
          expect(
            renderer.renderVerbose(Figure(move: 'pass_by'), d),
            'neighbor pass by right shoulders',
          );
        });
      },
    );

    group('pass_by canonical is byte-identical regardless of shoulder', () {
      // The canonical render uses the bare renderTemplate ({who} {move}) —
      // the shoulder override is display-only.
      test('default right shoulder: canonical unchanged', () {
        expect(
          renderer.renderCanonical(Figure(move: 'pass_by')),
          'neighbors pass by',
        );
      });
      test('left shoulder: canonical unchanged', () {
        expect(
          renderer.renderCanonical(
            Figure(move: 'pass_by', params: {'shoulder': 'left'}),
          ),
          'neighbors pass by',
        );
      });
      // invalid-fixture: value is deliberately out of domain — pass_by canonical keeps bare display name regardless of shoulder
      test('wildcard shoulder: canonical unchanged', () {
        expect(
          renderer.renderCanonical(
            Figure(move: 'pass_by', params: {'shoulder': '*'}),
          ),
          'neighbors pass by',
        );
      });
    });

    group(
      'pass_through renders shoulder only for non-right values (ContraDB passThroughWords)',
      () {
        // ContraDB: right shoulder is implicit (suppressed); left and * are
        // rendered explicitly. The default "along" direction continues to be
        // silenced on all paths.
        test('default (right shoulder + along dir): pass through', () {
          expect(
            renderer.render(Figure(move: 'pass_through'), d),
            'pass through',
          );
        });
        test(
          'left shoulder suppresses dir default: pass through left shoulders',
          () {
            expect(
              renderer.render(
                Figure(move: 'pass_through', params: {'shoulder': 'left'}),
                d,
              ),
              'pass through left shoulders',
            );
          },
        );
        // invalid-fixture: value is deliberately out of domain — pass_through surfaces an unknown shoulder value rather than blanking it
        test('wildcard shoulder: pass through * shoulders', () {
          expect(
            renderer.render(
              Figure(move: 'pass_through', params: {'shoulder': '*'}),
              d,
            ),
            'pass through * shoulders',
          );
        });
        test('non-default dir still renders (right shoulder suppressed)', () {
          expect(
            renderer.render(
              Figure(move: 'pass_through', params: {'dir': 'across'}),
              d,
            ),
            'pass through across',
          );
        });
        test('left shoulder + non-default dir: both render', () {
          expect(
            renderer.render(
              Figure(
                move: 'pass_through',
                params: {'shoulder': 'left', 'dir': 'across'},
              ),
              d,
            ),
            'pass through left shoulders across',
          );
        });
        test('verbose output matches terse', () {
          expect(
            renderer.renderVerbose(
              Figure(move: 'pass_through', params: {'shoulder': 'left'}),
              d,
            ),
            'pass through left shoulders',
          );
        });
      },
    );

    group('pass_through canonical is byte-identical regardless of shoulder', () {
      // The canonical render keeps expanding {move} {dir} — the base renderer
      // is display-only.
      test('default: canonical unchanged', () {
        expect(
          renderer.renderCanonical(Figure(move: 'pass_through')),
          'pass through along',
        );
      });
      test('left shoulder: canonical unchanged', () {
        expect(
          renderer.renderCanonical(
            Figure(move: 'pass_through', params: {'shoulder': 'left'}),
          ),
          'pass through along',
        );
      });
      // invalid-fixture: value is deliberately out of domain — pass_through canonical keeps bare {move} {dir} expansion regardless of shoulder
      test('wildcard shoulder: canonical unchanged', () {
        expect(
          renderer.renderCanonical(
            Figure(move: 'pass_through', params: {'shoulder': '*'}),
          ),
          'pass through along',
        );
      });
      test('non-default dir: canonical unchanged', () {
        expect(
          renderer.renderCanonical(
            Figure(move: 'pass_through', params: {'dir': 'across'}),
          ),
          'pass through across',
        );
      });
    });
  });

  group('PR2 display parity — idioms & adopted ContraDB wording', () {
    final d = Dialect.canonical;

    group('renderCanonical is unchanged (the invariant)', () {
      // Every touched move: canonical keeps its OLD template expansion (plural
      // subjects, template word order) that the PR2 display reword replaces.
      final cases = <String, Figure>{
        'partners zig zag left': Figure(move: 'zig_zag'),
        'slice left couple straight': Figure(move: 'slice'),
        'ones mad robin once': Figure(move: 'mad_robin'),
        'role2s revolving door right partners': Figure(move: 'revolving_door'),
        'partners box circulate': Figure(move: 'box_circulate'),
        // Explicit-param variants prove the display reword never leaks into
        // the search/dedupe text.
        'partners zig zag right': Figure(
          move: 'zig_zag',
          params: {'turn': 'right'},
        ),
        'neighbors zig zag left': Figure(
          move: 'zig_zag',
          params: {'who': 'neighbors'},
        ),
        'slice left dancer none': Figure(
          move: 'slice',
          params: {'by': 'dancer', 'return': 'none'},
        ),
        'slice right couple diagonal': Figure(
          move: 'slice',
          params: {'slice': 'right', 'return': 'diagonal'},
        ),
        'ones mad robin 1½': Figure(move: 'mad_robin', params: {'turn': 1.5}),
        'role2s revolving door left partners': Figure(
          move: 'revolving_door',
          params: {'hand': 'left'},
        ),
      };
      cases.forEach((expected, figure) {
        test('"$expected"', () {
          expect(renderer.renderCanonical(figure), expected);
          // Exercising display + summary must never disturb canonical.
          renderer.render(figure, d);
          renderer.renderSummary(figure, d);
          renderer.renderSummary(figure, d, verbose: true);
          expect(renderer.renderCanonical(figure), expected);
        });
      });
    });

    group('zig_zag ("with <subject>" suffix)', () {
      test('default reads "zig left zag right with partner"', () {
        expect(
          renderer.render(Figure(move: 'zig_zag'), d),
          'zig left zag right with partner',
        );
      });
      test('turn=right mirrors the direction words', () {
        expect(
          renderer.render(
            Figure(move: 'zig_zag', params: {'turn': 'right'}),
            d,
          ),
          'zig right zag left with partner',
        );
      });
      test('non-default subject is singularized in the suffix', () {
        expect(
          renderer.render(
            Figure(move: 'zig_zag', params: {'who': 'neighbors'}),
            d,
          ),
          'zig left zag right with neighbor',
        );
      });
      test('subject role term is dialect-aware', () {
        expect(
          renderer.render(Figure(move: 'zig_zag'), Dialect.larksRobins),
          'zig left zag right with partner',
        );
      });
    });

    group('slice (ContraDB generic-words label reword)', () {
      test('default reads "slice left and straight back"', () {
        expect(
          renderer.render(Figure(move: 'slice'), d),
          'slice left and straight back',
        );
      });
      test('by dancer reads "one dancer"', () {
        expect(
          renderer.render(Figure(move: 'slice', params: {'by': 'dancer'}), d),
          'slice left one dancer and straight back',
        );
      });
      test('return none drops the "…back" clause', () {
        expect(
          renderer.render(Figure(move: 'slice', params: {'return': 'none'}), d),
          'slice left',
        );
      });
      test('return diagonal reads "and diagonal back"', () {
        expect(
          renderer.render(
            Figure(move: 'slice', params: {'return': 'diagonal'}),
            d,
          ),
          'slice left and diagonal back',
        );
      });
      test('slide right renders the direction', () {
        expect(
          renderer.render(Figure(move: 'slice', params: {'slice': 'right'}), d),
          'slice right and straight back',
        );
      });
    });

    group('mad_robin (base-line reorder)', () {
      test('default reads "mad robin, ones in front"', () {
        expect(
          renderer.render(Figure(move: 'mad_robin'), d),
          'mad robin, ones in front',
        );
      });
      test('non-default turn adds the "<turn> around" clause', () {
        expect(
          renderer.render(Figure(move: 'mad_robin', params: {'turn': 1.5}), d),
          'mad robin 1½ around, ones in front',
        );
      });
      test('non-default subject is singularized', () {
        expect(
          renderer.render(
            Figure(move: 'mad_robin', params: {'who': 'neighbors'}),
            d,
          ),
          'mad robin, neighbor in front',
        );
      });
    });

    group('revolving_door (ContraDB wording verbatim)', () {
      test('default base line under canonical', () {
        expect(
          renderer.render(Figure(move: 'revolving_door'), d),
          'revolving door - role2s take right hands and drop off partner on other side',
        );
      });
      test('roles map under a dialect; whom singularized', () {
        expect(
          renderer.render(Figure(move: 'revolving_door'), Dialect.larksRobins),
          'revolving door - robins take right hands and drop off partner on other side',
        );
      });
      test('explicit hand renders in the "take <hand> hands" slot', () {
        expect(
          renderer.render(
            Figure(move: 'revolving_door', params: {'hand': 'left'}),
            d,
          ),
          'revolving door - role2s take left hands and drop off partner on other side',
        );
      });
      test('summary does not append a duplicate drop-off clause', () {
        final f = Figure(move: 'revolving_door');
        expect(renderer.renderSummary(f, d), renderer.render(f, d));
      });
    });

    group('robust to unexpected / uncoerced param values (no silent drops)', () {
      // Taxonomy.effectiveParams passes raw values through without coercion, so
      // the display base renderers must surface unexpected non-null values via
      // best-effort humanize rather than blank them out (OWASP: never silently
      // hide untrusted/imported input) — and never emit a dangling connective.
      test('zig_zag surfaces an unknown subject in the "with" suffix', () {
        expect(
          renderer.render(
            // invalid-fixture: value is deliberately out of domain — zig_zag surfaces an unknown subject in the "with" suffix
            Figure(move: 'zig_zag', params: {'who': 'someImportedGroup'}),
            d,
          ),
          'zig left zag right with some imported group',
        );
      });
      test('zig_zag drops the "with" suffix for an empty subject', () {
        expect(
          // invalid-fixture: value is deliberately out of domain — zig_zag drops the "with" suffix for an empty subject
          renderer.render(Figure(move: 'zig_zag', params: {'who': ''}), d),
          'zig left zag right',
        );
      });
      test('slice surfaces unknown by/return values instead of blanking', () {
        expect(
          renderer.render(
            // invalid-fixture: value is deliberately out of domain — slice surfaces unknown by/return values instead of blanking
            Figure(
              move: 'slice',
              params: {'by': 'wholeSet', 'return': 'loopBack'},
            ),
            d,
          ),
          'slice left whole set loop back',
        );
      });
      test('mad_robin surfaces an unknown subject, no dangling comma', () {
        expect(
          renderer.render(
            // invalid-fixture: value is deliberately out of domain — mad_robin surfaces an unknown subject, no dangling comma
            Figure(move: 'mad_robin', params: {'who': 'oddDancers'}),
            d,
          ),
          'mad robin, odd dancers in front',
        );
        // An empty subject omits the comma clause entirely.
        expect(
          // invalid-fixture: value is deliberately out of domain — mad_robin surfaces an unknown subject, no dangling comma
          renderer.render(Figure(move: 'mad_robin', params: {'who': ''}), d),
          'mad robin',
        );
      });
      test('revolving_door surfaces unknown who/whom/hand values', () {
        expect(
          renderer.render(
            // invalid-fixture: value is deliberately out of domain — revolving_door surfaces unknown who/whom/hand values
            Figure(
              move: 'revolving_door',
              params: {
                'who': 'oddLeaders',
                'hand': 'either',
                'whom': 'someFolks',
              },
            ),
            d,
          ),
          'revolving door - odd leaders take either hands and drop off some folks on other side',
        );
      });
    });
  });

  group('PR3 display parity — terse-by-design clauses (adopt ContraDB)', () {
    final d = Dialect.canonical;
    final larks = Dialect.larksRobins;

    group('renderCanonical is unchanged (the invariant)', () {
      // Every touched move keeps its OLD canonical template expansion — the
      // byte-stable dedupe/FTS key — that the PR3 display reword replaces.
      final cases = <String, Figure>{
        'partners box circulate': Figure(move: 'box_circulate'),
        'partners cross trails across neighbors': Figure(move: 'cross_trails'),
        'ones poussette neighbors half clockwise': Figure(move: 'poussette'),
        'ones facing star clockwise 3 places': Figure(move: 'facing_star'),
        'partners square through 4 places': Figure(move: 'square_through'),
        'role2s hey right': Figure(move: 'hey'),
        'ones dolphin hey right': Figure(move: 'dolphin_hey'),
        'role1s form long waves': Figure(move: 'form_long_waves'),
        'role2s form a long wave': Figure(move: 'form_a_long_wave'),
        // Explicit-param variants prove the display reword never leaks into the
        // search/dedupe text.
        'partners cross trails along neighbors': Figure(
          move: 'cross_trails',
          params: {'dir': 'along'},
        ),
        'ones poussette neighbors full counterclockwise': Figure(
          move: 'poussette',
          params: {'half': 'full', 'turn': 'counterclockwise'},
        ),
        'ones facing star counterclockwise 3 places': Figure(
          move: 'facing_star',
          params: {'turn': 'counterclockwise'},
        ),
        'partners square through 2 places': Figure(
          move: 'square_through',
          params: {'places': 2},
        ),
      };
      cases.forEach((expected, figure) {
        test('"$expected"', () {
          expect(renderer.renderCanonical(figure), expected);
          // Exercising display + summary must never disturb canonical.
          renderer.render(figure, d);
          renderer.render(figure, larks);
          renderer.renderSummary(figure, d);
          renderer.renderSummary(figure, d, verbose: true);
          expect(renderer.renderCanonical(figure), expected);
        });
      });
    });

    group(
      'box_circulate (ContraDB boxCirculateWords; PR2 balance preserved)',
      () {
        test('default base line carries the cross/loop clause, no balance', () {
          expect(
            renderer.render(Figure(move: 'box_circulate'), d),
            'box circulate - partner cross while others loop right',
          );
        });
        test('summary still prepends the (default-shown) balance', () {
          expect(
            renderer.renderSummary(Figure(move: 'box_circulate'), d),
            'balance & box circulate - partner cross while others loop right',
          );
        });
        test('explicit balance:false suppresses the summary prefix', () {
          expect(
            renderer.renderSummary(
              Figure(move: 'box_circulate', params: {'balance': false}),
              d,
            ),
            'box circulate - partner cross while others loop right',
          );
        });
      },
    );

    group('orbit (issue #295 first-class move)', () {
      test('default renders who + direction + amount', () {
        expect(
          renderer.render(Figure(move: 'orbit'), d),
          'ones orbit clockwise ½',
        );
      });
      test('counterclockwise direction', () {
        expect(
          renderer.render(
            Figure(move: 'orbit', params: {'turn': 'counterclockwise'}),
            d,
          ),
          'ones orbit counterclockwise ½',
        );
      });
      test('verbose spells the amount out', () {
        expect(
          renderer.renderVerbose(Figure(move: 'orbit'), d),
          'ones orbit clockwise halfway',
        );
      });
    });

    group('cross_trails (ContraDB crossTrailsWords)', () {
      test('default: second dir/shoulder are the structural inverse', () {
        expect(
          renderer.render(Figure(move: 'cross_trails'), d),
          'cross trails - partner across the set right shoulders, neighbor along the set left shoulders',
        );
      });
      test('dir=along mirrors to "across the set" for the second pair', () {
        expect(
          renderer.render(
            Figure(move: 'cross_trails', params: {'dir': 'along'}),
            d,
          ),
          'cross trails - partner along the set right shoulders, neighbor across the set left shoulders',
        );
      });
    });

    group('poussette (ContraDB poussetteWords)', () {
      test('default: half + clockwise -> "back then left"', () {
        expect(
          renderer.render(Figure(move: 'poussette'), d),
          'half poussette - ones pull neighbor back then left',
        );
      });
      test('full + counterclockwise -> "back then right"', () {
        expect(
          renderer.render(
            Figure(
              move: 'poussette',
              params: {'half': 'full', 'turn': 'counterclockwise'},
            ),
            d,
          ),
          'full poussette - ones pull neighbor back then right',
        );
      });
    });

    group('facing_star (ContraDB facingStarWords)', () {
      test('default: hand derived from the turn (clockwise -> left)', () {
        expect(
          renderer.render(Figure(move: 'facing_star'), d),
          'facing star clockwise 3 places with ones putting their left hands in and backing up',
        );
      });
      test('counterclockwise derives the right hand', () {
        expect(
          renderer.render(
            Figure(move: 'facing_star', params: {'turn': 'counterclockwise'}),
            d,
          ),
          'facing star counterclockwise 3 places with ones putting their right hands in and backing up',
        );
      });
    });

    group('square_through (ContraDB squareThroughWords)', () {
      test('default (4 places): embedded balance + "then repeat" tail', () {
        expect(
          renderer.render(Figure(move: 'square_through'), d),
          'square through four - partner balance & pull by right, then neighbor pull by left, then repeat',
        );
      });
      test('2 places: no tail', () {
        expect(
          renderer.render(
            Figure(move: 'square_through', params: {'places': 2}),
            d,
          ),
          'square through two - partner balance & pull by right, then neighbor pull by left',
        );
      });
      test('3 places: repeats the first (balance &) pull', () {
        expect(
          renderer.render(
            Figure(move: 'square_through', params: {'places': 3}),
            d,
          ),
          'square through three - partner balance & pull by right, then neighbor pull by left, then partner balance & pull by right',
        );
      });
      test('balance:false drops the embedded balance', () {
        expect(
          renderer.render(
            Figure(move: 'square_through', params: {'balance': false}),
            d,
          ),
          'square through four - partner pull by right, then neighbor pull by left, then repeat',
        );
      });
      test('verbose spells the embedded balance as "balance and"', () {
        expect(
          renderer.renderVerbose(Figure(move: 'square_through'), d),
          'square through four - partner balance and pull by right, then neighbor pull by left, then repeat',
        );
      });
    });

    group('hey (ContraDB heyWords; summary length no longer duplicated)', () {
      test(
        'default: half hey with terse shoulders + center/ends placement',
        () {
          expect(
            renderer.render(Figure(move: 'hey'), d),
            'role2s start a half hey - rights in center, lefts on ends',
          );
        },
      );
      test('full hey', () {
        expect(
          renderer.render(Figure(move: 'hey', params: {'length': 'full'}), d),
          'role2s start a full hey - rights in center, lefts on ends',
        );
      });
      test('lessThanHalf appends "until someone meets"', () {
        expect(
          renderer.render(
            Figure(move: 'hey', params: {'length': 'lessThanHalf'}),
            d,
          ),
          'role2s start a hey - rights in center, lefts on ends - until someone meets',
        );
      });
      test('betweenHalfAndFull appends "…the second time"', () {
        expect(
          renderer.render(
            Figure(move: 'hey', params: {'length': 'betweenHalfAndFull'}),
            d,
          ),
          'role2s start a hey - rights in center, lefts on ends - until someone meets the second time',
        );
      });
      test('partial hey with a meetTarget names the pair (issue #576)', () {
        expect(
          renderer.render(
            Figure(
              move: 'hey',
              params: {'length': 'lessThanHalf', 'meetTarget': 'neighbors'},
            ),
            d,
          ),
          'role2s start a hey - rights in center, lefts on ends - until neighbors meet',
        );
      });
      test('a ricochet flag adds the ricochet clause', () {
        expect(
          renderer.render(Figure(move: 'hey', params: {'rico1': true}), d),
          'role2s start a half hey - rights in center, lefts on ends - role2s ricochet',
        );
      });
      test('odd ricochet flag references the inverted pair, with timing', () {
        // rico2 (index 1, odd) -> the other pair; a non-half length adds
        // "first time" (i & 2 == 0).
        expect(
          renderer.render(
            Figure(move: 'hey', params: {'rico2': true, 'length': 'full'}),
            larks,
          ),
          'robins start a full hey - rights in center, lefts on ends - larks ricochet first time',
        );
      });
      test('summary no longer appends a duplicate length clause', () {
        final f = Figure(move: 'hey');
        expect(renderer.renderSummary(f, d), renderer.render(f, d));
      });
    });

    group('dolphin_hey (ContraDB dolphinHeyWords; single-dancer whom)', () {
      test('default: "whom" renders as a single dancer under a dialect', () {
        expect(
          renderer.render(Figure(move: 'dolphin_hey'), larks),
          'dolphin hey - start with ones passing first lark by right shoulders',
        );
      });
      test('canonical dialect uses the plain role token', () {
        expect(
          renderer.render(Figure(move: 'dolphin_hey'), d),
          'dolphin hey - start with ones passing first role1 by right shoulders',
        );
      });
    });

    group('form_long_waves (ContraDB formLongWavesWords)', () {
      test('default: who faces in, the other pair faces out', () {
        expect(
          renderer.render(Figure(move: 'form_long_waves'), larks),
          'form long waves - larks facing in, robins facing out',
        );
      });
    });

    group('form_a_long_wave (ContraDB formALongWaveWords)', () {
      test('default (in + balance)', () {
        expect(
          renderer.render(Figure(move: 'form_a_long_wave'), larks),
          'robins dance in to a long wave in the center - balance the wave',
        );
      });
      test('out only (+ balance) -> "dance out & balance"', () {
        expect(
          renderer.render(
            Figure(
              move: 'form_a_long_wave',
              params: {'in': false, 'out': true},
            ),
            larks,
          ),
          'larks dance out & balance',
        );
      });
      test('out + in -> "<other> dance out while <who> dance in…"', () {
        expect(
          renderer.render(
            Figure(move: 'form_a_long_wave', params: {'in': true, 'out': true}),
            larks,
          ),
          'larks dance out while robins dance in to a long wave in the center - balance the wave',
        );
      });
      test('neither in nor out -> the move-name form', () {
        expect(
          renderer.render(
            Figure(
              move: 'form_a_long_wave',
              params: {'in': false, 'out': false, 'balance': false},
            ),
            larks,
          ),
          'robins form a long wave in the center',
        );
      });
    });

    group('robust to unexpected / uncoerced param values (no silent drops)', () {
      // The display base renderers must surface unexpected non-null values via
      // best-effort humanize rather than blank them out (OWASP: never silently
      // hide untrusted/imported input) — and never emit a dangling connective.
      test('square_through places outside {2,3,4} degrade, never throw', () {
        expect(
          renderer.render(
            Figure(move: 'square_through', params: {'places': 6}),
            d,
          ),
          'square through 6 - partner balance & pull by right, then neighbor pull by left',
        );
      });
      test('cross_trails surfaces an unknown subject (structural clause kept)', () {
        // ContraDB always emits both dir/shoulder clauses; an empty second
        // subject leaves the (still meaningful) structural clause, and the
        // unknown first subject is humanized rather than dropped.
        expect(
          renderer.render(
            // invalid-fixture: value is deliberately out of domain — cross_trails surfaces an unknown subject (structural clause kept)
            Figure(
              move: 'cross_trails',
              params: {'who': 'someImportedGroup', 'who2': ''},
            ),
            d,
          ),
          'cross trails - some imported group across the set right shoulders, along the set left shoulders',
        );
      });
      test('poussette drops the direction clause for an unknown turn', () {
        expect(
          renderer.render(
            // invalid-fixture: value is deliberately out of domain — poussette drops the direction clause for an unknown turn
            Figure(move: 'poussette', params: {'turn': 'sideways'}),
            d,
          ),
          'half poussette - ones pull neighbor',
        );
      });
      test('hey surfaces an unknown shoulder rather than blanking', () {
        expect(
          renderer.render(
            // invalid-fixture: value is deliberately out of domain — hey surfaces an unknown shoulder rather than blanking
            Figure(move: 'hey', params: {'shoulder': 'eitherSide'}),
            d,
          ),
          'role2s start a half hey - either side in center, either side on ends',
        );
      });
      test('form_a_long_wave surfaces an unknown subject', () {
        expect(
          renderer.render(
            // invalid-fixture: value is deliberately out of domain — form_a_long_wave surfaces an unknown subject
            Figure(
              move: 'form_a_long_wave',
              params: {'who': 'oddDancers', 'balance': false},
            ),
            d,
          ),
          'odd dancers dance in to a long wave in the center',
        );
      });
      test('form_a_long_wave out-only surfaces a wildcard balance', () {
        // The out-only branch must surface '*' (like the sibling branches'
        // maybeBalance) instead of collapsing it into a concrete "& balance".
        expect(
          renderer.render(
            // invalid-fixture: value is deliberately out of domain — form_a_long_wave out-only surfaces a wildcard balance
            Figure(
              move: 'form_a_long_wave',
              params: {'in': false, 'out': true, 'balance': '*'},
            ),
            d,
          ),
          'role1s dance out & *',
        );
      });
      test('form_a_long_wave out-only omits balance for false/unexpected', () {
        expect(
          renderer.render(
            // invalid-fixture: value is deliberately out of domain — form_a_long_wave out-only omits balance for false/unexpected
            Figure(
              move: 'form_a_long_wave',
              params: {'in': false, 'out': true, 'balance': 'maybe'},
            ),
            d,
          ),
          'role1s dance out',
        );
      });
    });
  });

  group('decimals display flag (#368)', () {
    Figure allemande(num turn) => invalidTestFigure(
      move: 'allemande',
      params: {'turn': turn},
      reason:
          'the decimals-display sweep uses turn values beyond the taxonomy domain',
    );

    test('renders turn amounts as leading-zero decimals when opted in', () {
      String d(num t) => renderer.render(allemande(t), larks, decimals: true);
      expect(d(0.25), endsWith('0.25'));
      expect(d(0.5), endsWith('0.5'));
      expect(d(0.75), endsWith('0.75'));
      expect(d(1.5), endsWith('1.5'));
      expect(d(1.75), endsWith('1.75'));
    });

    test('whole turns render as plain numbers (no once/twice) in decimals', () {
      expect(
        renderer.render(allemande(1), larks, decimals: true),
        endsWith('1'),
      );
      expect(
        renderer.render(allemande(2), larks, decimals: true),
        endsWith('2'),
      );
      expect(
        renderer.render(allemande(3), larks, decimals: true),
        endsWith('3'),
      );
    });

    test('default (flag off) keeps fraction glyphs / caller words', () {
      expect(renderer.render(allemande(0.75), larks), endsWith('¾'));
      expect(renderer.render(allemande(1), larks), endsWith('once'));
      expect(renderer.render(allemande(2), larks), endsWith('twice'));
      expect(renderer.render(allemande(1.5), larks), endsWith('1½'));
    });

    test('renderSummary honors the decimals flag', () {
      expect(
        renderer.renderSummary(allemande(0.75), larks, decimals: true),
        endsWith('0.75'),
      );
    });

    test('canonical text stays byte-stable (glyphs), never decimal', () {
      // The dedupe/FTS invariant: renderCanonical must not expose decimals.
      expect(renderer.renderCanonical(allemande(0.75)), contains('¾'));
      expect(
        renderer.renderCanonical(allemande(0.75)),
        isNot(contains('0.75')),
      );
      expect(renderer.renderCanonical(allemande(1.5)), contains('1½'));
    });

    test('verbose (spoken) path is unaffected by decimals — Option A', () {
      // decimals is visual-only; the spoken form keeps word fractions even
      // when the flag rides through the same render call.
      final verbose = renderer.renderSummary(
        allemande(0.75),
        larks,
        verbose: true,
        decimals: true,
      );
      expect(verbose, contains('three quarters'));
      expect(verbose, isNot(contains('0.75')));
    });

    test('composes with the merged gate turn fraction (#294)', () {
      final f = Figure(
        move: 'gate',
        params: {
          'pair': 'partners',
          'direction': 'counterclockwise',
          'turn': 0.75,
          'beats': 6,
        },
      );
      expect(
        renderer.render(f, Dialect.canonical, decimals: true),
        'partner gate counterclockwise 0.75',
      );
      // Untouched default keeps the glyph.
      expect(renderer.render(f, Dialect.canonical), endsWith('¾'));
    });

    test('composes with orbit amount', () {
      expect(
        renderer.render(
          Figure(move: 'orbit'),
          Dialect.canonical,
          decimals: true,
        ),
        'ones orbit clockwise 0.5',
      );
    });

    test('composes with mad_robin turn', () {
      expect(
        renderer.render(
          Figure(move: 'mad_robin', params: {'turn': 1.5}),
          Dialect.canonical,
          decimals: true,
        ),
        'mad robin 1.5 around, ones in front',
      );
    });
  });

  // Issue #460 — a parser-assumed subject renders a non-authoritative
  // "(assumed)" marker in every DISPLAY path, while the canonical (search/
  // dedupe) render and every explicit-subject figure stay byte-for-byte stable.
  group('assumed-subject marker (#460)', () {
    // Template path (allemande) + base-renderer path (the merged gate).
    Figure allemande({required bool assumed}) => Figure(
      move: 'allemande',
      params: {'who': 'neighbors', 'hand': 'left', 'turn': 1.5},
      assumedSubject: assumed,
    );
    Figure gate({required bool assumed}) => Figure(
      move: 'gate',
      params: {
        'pair': 'partners',
        'direction': 'counterclockwise',
        'turn': 0.75,
      },
      assumedSubject: assumed,
    );

    test('template move: marker follows the subject in every display path', () {
      final f = allemande(assumed: true);
      expect(
        renderer.render(f, Dialect.canonical),
        'neighbor (assumed) allemande left 1½',
      );
      expect(
        renderer.renderSummary(f, Dialect.canonical),
        'neighbor (assumed) allemande left 1½',
      );
      expect(
        renderer.renderVerbose(f, Dialect.canonical),
        'neighbor (assumed) allemande left one and a half times',
      );
    });

    test('base-renderer move (gate): marker follows the subject', () {
      final f = gate(assumed: true);
      expect(
        renderer.render(f, Dialect.canonical),
        'partner (assumed) gate counterclockwise ¾',
      );
      expect(
        renderer.renderSummary(f, Dialect.canonical),
        'partner (assumed) gate counterclockwise ¾',
      );
    });

    test('the marker is dialect-aware — it trails the substituted subject', () {
      // role subject → dialect role term, marker still immediately after it.
      final f = Figure(
        move: 'swing',
        params: {'who': 'role1s'},
        assumedSubject: true,
      );
      expect(renderer.render(f, larks), 'larks (assumed) swing');
      // dancer substitution likewise.
      final dialect = larks.copyWith(dancers: {'neighbors': 'the others'});
      final n = Figure(
        move: 'swing',
        params: {'who': 'neighbors'},
        assumedSubject: true,
      );
      expect(renderer.render(n, dialect), 'the others (assumed) swing');
    });

    test('canonical render NEVER carries the marker (byte-stable index)', () {
      // The dedupe/FTS text must stay identical whether or not the subject was
      // assumed, so an assumed import never forks the search index.
      expect(
        renderer.renderCanonical(allemande(assumed: true)),
        renderer.renderCanonical(allemande(assumed: false)),
      );
      expect(
        renderer.renderCanonical(allemande(assumed: true)),
        'neighbors allemande left 1½',
      );
      expect(
        renderer.renderCanonical(gate(assumed: true)),
        renderer.renderCanonical(gate(assumed: false)),
      );
    });

    test('explicit subject is byte-identical to a marker-free render', () {
      // assumedSubject:false must produce EXACTLY today's output in every path
      // (no regression) — the marker is strictly additive to the assumed case.
      for (final dialect in [Dialect.canonical, larks]) {
        expect(
          renderer.render(allemande(assumed: false), dialect),
          renderer.render(
            Figure(
              move: 'allemande',
              params: {'who': 'neighbors', 'hand': 'left', 'turn': 1.5},
            ),
            dialect,
          ),
        );
        expect(
          renderer.renderVerbose(gate(assumed: false), dialect),
          renderer.renderVerbose(
            Figure(
              move: 'gate',
              params: {
                'pair': 'partners',
                'direction': 'counterclockwise',
                'turn': 0.75,
              },
            ),
            dialect,
          ),
        );
        expect(
          renderer.render(allemande(assumed: false), dialect),
          isNot(contains('(assumed)')),
        );
      }
    });

    test('renderSummary balance splice keeps the marker (box_the_gnat)', () {
      // box_the_gnat places its balance prefix afterWho; the summary splice must
      // not drop the marker the base render already inserted.
      final f = Figure(
        move: 'box_the_gnat',
        params: {'who': 'partners', 'balance': true},
        assumedSubject: true,
      );
      final summary = renderer.renderSummary(f, Dialect.canonical);
      expect(summary, contains('(assumed)'));
      expect(summary, contains('balance'));
    });

    test('marker splices at the true subject even when a custom dialect repeats '
        'the subject word in the move name (indexOf regression #460)', () {
      // A custom move substitution that opens with the subject word would fool
      // a naive line-search into marking the MOVE NAME and leaving the real
      // subject authoritative. box_circulate renders its move name BEFORE the
      // subject, so it is the canonical trap: `moves: {box_circulate:
      // 'partner circulate'}` yields "partner circulate - partner cross …",
      // where a `line.indexOf('partner')` finds the move-name "partner" first.
      final dialect = Dialect(
        name: 'Trap',
        moves: const {'box_circulate': 'partner circulate'},
      );
      final assumed = Figure(
        move: 'box_circulate',
        params: {'who': 'partners', 'hand': 'right'},
        assumedSubject: true,
      );
      final out = renderer.render(assumed, dialect);
      // The move name is intact — the marker did NOT land inside it …
      expect(out, contains('partner circulate -'));
      expect(out, isNot(startsWith('partner (assumed) circulate')));
      // … and the marker trails the ACTUAL subject token instead.
      expect(out, contains('partner (assumed) cross'));
      // Exactly one marker (no residue, no double-marking).
      expect('(assumed)'.allMatches(out).length, 1);

      // The explicit-subject counterpart is unchanged and marker-free.
      final statedOut = renderer.render(
        Figure(
          move: 'box_circulate',
          params: {'who': 'partners', 'hand': 'right'},
        ),
        dialect,
      );
      expect(statedOut, isNot(contains('(assumed)')));
      expect(statedOut, startsWith('partner circulate -'));
    });
  });
}
