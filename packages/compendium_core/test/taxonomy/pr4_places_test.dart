import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

/// Roadmap 2.4a — PR4 "places family": circle, star, facing_star,
/// square_through, plus the new `ParamKind.places` engine type (int 1..10,
/// rendered "N places").
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);

  const newMoves = ['circle', 'star', 'facing_star', 'square_through'];

  group('ParamKind.places domain', () {
    const spec = ParamSpec(ParamKind.places, defaultValue: 4);

    test('accepts ints 1..10', () {
      for (var p = 1; p <= 10; p++) {
        expect(spec.validate(p), isTrue, reason: '$p places should be valid');
      }
    });

    test('rejects out-of-range and non-int values', () {
      expect(spec.validate(0), isFalse);
      expect(spec.validate(11), isFalse);
      expect(spec.validate(-1), isFalse);
      expect(spec.validate(4.0), isFalse, reason: 'must be an int');
      expect(spec.validate('4'), isFalse);
    });
  });

  group('registration & defaults', () {
    for (final id in newMoves) {
      test('$id resolves and validates with all defaults populated', () {
        expect(tax.resolve(id)?.id, id, reason: '$id should be registered');
        final defaults = tax.effectiveParams(testFigure(move: id));
        expect(
          tax.validateFigure(testFigure(move: id, params: defaults)),
          isEmpty,
          reason: '$id default param values must all be in-domain',
        );
      });
    }

    test('box_circulate is registered but carries no places param (v11)', () {
      final def = tax.resolve('box_circulate');
      expect(def, isNotNull, reason: 'box_circulate added in v11');
      expect(
        def!.params.containsKey('places'),
        isFalse,
        reason:
            'ContraDB lists box circulate under places for angle display '
            'only; it takes no places param',
      );
    });
  });

  group('places rendering ("N places", singular "1 place")', () {
    test('circle default renders 4 places', () {
      expect(
        renderer.renderCanonical(Figure(move: 'circle')),
        'circle left 4 places',
      );
    });

    test('singular place', () {
      expect(
        renderer.renderCanonical(Figure(move: 'circle', params: {'places': 1})),
        'circle left 1 place',
      );
    });

    test('plural places (non-default count)', () {
      expect(
        renderer.renderCanonical(
          Figure(move: 'circle', params: {'places': 3, 'turn': 'right'}),
        ),
        'circle right 3 places',
      );
    });
  });

  group('canonical rendering (golden)', () {
    final cases = <String, Figure>{
      'circle left 4 places': Figure(move: 'circle'),
      // star grip 'none' emits no grip clause in any render path.
      'star right 4 places': Figure(move: 'star'),
      'ones facing star clockwise 3 places': Figure(move: 'facing_star'),
      'partners square through 4 places': Figure(move: 'square_through'),
    };
    cases.forEach((expected, figure) {
      test('"$expected"', () {
        expect(renderer.renderCanonical(figure), expected);
      });
    });

    test('contraTaxonomyVersion is 29', () {
      // Guard: fails when the version is bumped without updating this test.
      // Update this assertion (and add a new test group documenting the new
      // version's changes) when bumping contraTaxonomyVersion.
      expect(contraTaxonomyVersion, 29);
    });

    test(
      'star renderCanonical includes grip clause (taxonomy v27, issue #749 Gap B)',
      () {
        // Since v27, grip is a canonical render token — it appears in
        // renderCanonical → dance_fts so "wrist grip" / "hands across" are
        // free-text searchable. Red-run target: reverting the canonical
        // renderer for star returns byte-identical output, these tests fail.
        expect(
          renderer.renderCanonical(
            Figure(move: 'star', params: {'hand': 'left', 'grip': 'wristGrip'}),
          ),
          'star left - wrist grip - 4 places',
        );
        expect(
          renderer.renderCanonical(
            Figure(
              move: 'star',
              params: {'hand': 'right', 'grip': 'handsAcross'},
            ),
          ),
          'star right - hands across - 4 places',
        );
        // 'none' grip (default) still omits the clause in canonical.
        expect(
          renderer.renderCanonical(
            Figure(move: 'star', params: {'hand': 'left', 'grip': 'none'}),
          ),
          'star left 4 places',
        );
      },
    );

    test(
      'circle renderCanonical: "single file promenade clockwise N places (circle)" (v27)',
      () {
        // Since v27, singleFile is canonical. The parenthetical "(circle)"
        // retains "circle" in the FTS index.
        expect(
          renderer.renderCanonical(
            testFigure(move: 'circle', params: {'singleFile': true}),
          ),
          'single file promenade clockwise 4 places (circle)',
        );
        // Default (singleFile=false) is unchanged.
        expect(
          renderer.renderCanonical(
            testFigure(move: 'circle', params: {'singleFile': false}),
          ),
          'circle left 4 places',
        );
      },
    );

    test(
      'promenade renderCanonical: "single file promenade {dir}" (v27), with destination (v29)',
      () {
        // Since v27, singleFile is canonical. `who` is dropped; `dir` always
        // present (even the `across` default).
        expect(
          renderer.renderCanonical(
            testFigure(move: 'promenade', params: {'singleFile': true}),
          ),
          'single file promenade across',
        );
        // Explicit `dir:'along'` (ContraDB import) included in canonical key.
        expect(
          renderer.renderCanonical(
            testFigure(
              move: 'promenade',
              params: {'singleFile': true, 'dir': 'along'},
            ),
          ),
          'single file promenade along',
        );
        // v29 (#921): destination appended when stated.
        expect(
          renderer.renderCanonical(
            testFigure(
              move: 'promenade',
              params: {
                'singleFile': true,
                'dir': 'along',
                'destination': 'nextNeighbors',
              },
            ),
          ),
          'single file promenade along to next neighbors',
        );
        // destination:neighbors
        expect(
          renderer.renderCanonical(
            testFigure(
              move: 'promenade',
              params: {
                'singleFile': true,
                'dir': 'along',
                'destination': 'neighbors',
              },
            ),
          ),
          'single file promenade along to neighbors',
        );
        // unspecified destination — same as no destination
        expect(
          renderer.renderCanonical(
            testFigure(
              move: 'promenade',
              params: {
                'singleFile': true,
                'dir': 'along',
                'destination': 'unspecified',
              },
            ),
          ),
          'single file promenade along',
        );
        // Default (singleFile=false) is unchanged.
        expect(
          renderer.renderCanonical(
            testFigure(move: 'promenade', params: {'singleFile': false}),
          ),
          'partners promenade across',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Display rendering: grip and singleFile are shown in render / renderVerbose /
  // renderSummary and in renderCanonical (taxonomy v27, issue #749).
  // ---------------------------------------------------------------------------
  group('display rendering surfaces grip and singleFile (issue #749)', () {
    final d = Dialect.canonical;

    group('star.grip — mirrors ContraDB starWords " - <grip> - " clause', () {
      test('grip: none (default) — no grip clause', () {
        expect(renderer.render(Figure(move: 'star'), d), 'star right 4 places');
      });

      test('grip: wristGrip — "star right - wrist grip - 4 places"', () {
        final f = testFigure(move: 'star', params: {'grip': 'wristGrip'});
        expect(renderer.render(f, d), 'star right - wrist grip - 4 places');
      });

      test('grip: handsAcross — "star right - hands across - 4 places"', () {
        final f = testFigure(move: 'star', params: {'grip': 'handsAcross'});
        expect(renderer.render(f, d), 'star right - hands across - 4 places');
      });

      test('grip shows in renderVerbose and renderSummary too', () {
        final f = testFigure(
          move: 'star',
          params: {'hand': 'left', 'grip': 'handsAcross'},
        );
        expect(
          renderer.renderVerbose(f, d),
          'star left - hands across - 4 places',
        );
        expect(
          renderer.renderSummary(f, d),
          'star left - hands across - 4 places',
        );
      });

      test('grip: none with non-default hand still omits the grip clause', () {
        expect(
          renderer.render(
            testFigure(move: 'star', params: {'hand': 'left', 'grip': 'none'}),
            d,
          ),
          'star left 4 places',
        );
      });
    });

    group('promenade.singleFile — display (issue #749 / #634, updated v27)', () {
      test('singleFile: false — renders normally', () {
        expect(
          renderer.render(Figure(move: 'promenade'), d),
          'partner promenade',
        );
      });

      test(
        'singleFile: true — "single file promenade across" (dir always shown)',
        () {
          final f = testFigure(move: 'promenade', params: {'singleFile': true});
          // `who` is dropped (importer artefact); `dir` always present even
          // at the `across` default (ruling 7, v27).
          expect(renderer.render(f, d), 'single file promenade across');
        },
      );

      test(
        'singleFile: true with dir:along — "single file promenade along"',
        () {
          final f = testFigure(
            move: 'promenade',
            params: {'singleFile': true, 'dir': 'along'},
          );
          expect(renderer.render(f, d), 'single file promenade along');
        },
      );

      test('singleFile: true shows in renderSummary', () {
        final f = testFigure(move: 'promenade', params: {'singleFile': true});
        expect(renderer.renderSummary(f, d), 'single file promenade across');
      });

      test(
        'singleFile: true, destination:nextNeighbors — "single file promenade along to next neighbors"',
        () {
          final f = testFigure(
            move: 'promenade',
            params: {
              'singleFile': true,
              'dir': 'along',
              'destination': 'nextNeighbors',
            },
          );
          expect(
            renderer.render(f, d),
            'single file promenade along to next neighbors',
          );
        },
      );

      test(
        'singleFile: true, destination:neighbors — "single file promenade along to neighbors"',
        () {
          final f = testFigure(
            move: 'promenade',
            params: {
              'singleFile': true,
              'dir': 'along',
              'destination': 'neighbors',
            },
          );
          expect(
            renderer.render(f, d),
            'single file promenade along to neighbors',
          );
        },
      );

      test(
        'singleFile: true, destination:unspecified — no destination clause',
        () {
          final f = testFigure(
            move: 'promenade',
            params: {
              'singleFile': true,
              'dir': 'along',
              'destination': 'unspecified',
            },
          );
          expect(renderer.render(f, d), 'single file promenade along');
        },
      );
    });

    group('circle.singleFile — prefix form (issue #749 / #840, v27)', () {
      test('singleFile: false — renders normally', () {
        expect(
          renderer.render(Figure(move: 'circle'), d),
          'circle left 4 places',
        );
      });

      test(
        'singleFile: true — "single file circle clockwise 4 places" (prefix form)',
        () {
          final f = testFigure(move: 'circle', params: {'singleFile': true});
          // Prefix form replaces the v26 suffix ("circle … - single file").
          // turn:'left' maps to clockwise (contra convention: circle left
          // travels clockwise).
          expect(
            renderer.render(f, d),
            'single file circle clockwise 4 places',
          );
        },
      );

      test('singleFile: true with non-default places', () {
        final f = testFigure(
          move: 'circle',
          params: {'singleFile': true, 'places': 3},
        );
        expect(renderer.render(f, d), 'single file circle clockwise 3 places');
      });

      test('singleFile: true, turn:right — counterclockwise', () {
        final f = testFigure(
          move: 'circle',
          params: {'singleFile': true, 'turn': 'right'},
        );
        expect(
          renderer.render(f, d),
          'single file circle counterclockwise 4 places',
        );
      });

      test('singleFile: true shows in renderSummary', () {
        final f = testFigure(move: 'circle', params: {'singleFile': true});
        expect(
          renderer.renderSummary(f, d),
          'single file circle clockwise 4 places',
        );
      });
    });
  });

  group('goodBeats warnings', () {
    test('circle warns on atypical beats', () {
      final issues = tax.validateFigure(
        Figure(move: 'circle', params: {'beats': 6}),
      );
      expect(issues.single.code, 'atypical_beats');
    });

    test('square_through accepts an atypical place count without error', () {
      // square_through's 2-4 restriction is typical-only, not enforced.
      final issues = tax.validateFigure(
        Figure(move: 'square_through', params: {'places': 8}),
      );
      expect(issues.where((i) => i.code == 'invalid_param_value'), isEmpty);
    });
  });

  group('param domains', () {
    test('circle rejects an out-of-range places value', () {
      expect(
        tax
            // invalid-fixture: value is deliberately out of domain — circle rejects an out-of-range places value
            .validateFigure(Figure(move: 'circle', params: {'places': 0}))
            .any((i) => i.code == 'invalid_param_value'),
        isTrue,
      );
    });

    test('star grip is restricted to its choice domain', () {
      expect(
        tax
            // invalid-fixture: value is deliberately out of domain — star grip is restricted to its choice domain
            .validateFigure(Figure(move: 'star', params: {'grip': 'deathgrip'}))
            .any((i) => i.code == 'invalid_param_value'),
        isTrue,
      );
    });
  });

  group('dialect round-trip unaffected by places moves', () {
    test(
      'circle renders identically under a role dialect (no role tokens)',
      () {
        expect(
          renderer.render(Figure(move: 'circle'), Dialect.larksRobins),
          'circle left 4 places',
        );
      },
    );
  });

  group(
    'dialect substitution applies uniformly to singleFile path (issue #749)',
    () {
      // A dialect that renames 'promenade' must apply on BOTH the ordinary and
      // the singleFile branch — if the singleFile branch returns a hardcoded
      // string before reaching _renderMoveName, the substitution is silently
      // dropped. These tests fail against c68bd58e (hardcoded 'single file
      // promenade') and pass once the branch routes through _renderMoveName.
      final d = Dialect(name: 'Test', moves: const {'promenade': 'walkabout'});

      test('singleFile: true applies Dialect.moves override on move name', () {
        final f = testFigure(move: 'promenade', params: {'singleFile': true});
        // `who` is dropped; `dir` always present (v27 ruling).
        expect(renderer.render(f, d), 'single file walkabout across');
      });

      test('singleFile: false applies Dialect.moves override on move name', () {
        final f = testFigure(move: 'promenade', params: {'singleFile': false});
        expect(renderer.render(f, d), 'partner walkabout');
      });

      test(
        'singleFile: true with explicit non-default who — who is DROPPED (v27)',
        () {
          // Since v27, `who` is always dropped in the singleFile display path
          // (importer artefact; not surfaced even for non-default values).
          final f = testFigure(
            move: 'promenade',
            params: {'singleFile': true, 'who': 'neighbors'},
          );
          expect(renderer.render(f, d), 'single file walkabout across');
        },
      );

      test('singleFile: true with default who (partners) — who dropped', () {
        final f = testFigure(
          move: 'promenade',
          params: {'singleFile': true, 'who': 'partners'},
        );
        expect(renderer.render(f, d), 'single file walkabout across');
      });
    },
  );
}
