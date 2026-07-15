import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Roadmap 2.4a — PR5 "hey/wave family" (final slice): pass_by, hey,
/// dolphin_hey, form_long_waves, form_a_long_wave, form_an_ocean_wave. No new
/// ParamKind; the reduced-but-structured hey model + wave formations.
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);

  const newMoves = [
    'pass_by',
    'hey',
    'dolphin_hey',
    'form_long_waves',
    'form_a_long_wave',
    'form_an_ocean_wave',
  ];

  group('registration & defaults', () {
    for (final id in newMoves) {
      test('$id resolves and validates with all defaults populated', () {
        expect(tax.resolve(id)?.id, id, reason: '$id should be registered');
        final defaults = tax.effectiveParams(Figure(move: id));
        expect(
          tax.validateFigure(Figure(move: id, params: defaults)),
          isEmpty,
          reason: '$id default param values must all be in-domain',
        );
      });
    }
  });

  group('canonical rendering (golden)', () {
    final cases = <String, Figure>{
      'neighbors pass by': Figure(move: 'pass_by'),
      'role2s hey right': Figure(move: 'hey'),
      'ones dolphin hey right': Figure(move: 'dolphin_hey'),
      'role1s form long waves': Figure(move: 'form_long_waves'),
      'role2s form a long wave': Figure(move: 'form_a_long_wave'),
      'form an ocean wave': Figure(move: 'form_an_ocean_wave'),
    };
    cases.forEach((expected, figure) {
      test('"$expected"', () {
        expect(renderer.renderCanonical(figure), expected);
      });
    });

    test(
      'hey renders pass1 + shoulder; ricochet/length/dir stay structured',
      () {
        expect(
          renderer.renderCanonical(
            Figure(
              move: 'hey',
              params: {
                'pass1': 'role1s',
                'shoulder': 'left',
                'length': 'full',
                'rico1': true,
                'dir': 'along',
              },
            ),
          ),
          'role1s hey left',
        );
      },
    );
  });

  group('hey full named-duration length model', () {
    test('all four named ContraDB length values validate', () {
      for (final length in [
        'full',
        'half',
        'lessThanHalf',
        'betweenHalfAndFull',
      ]) {
        expect(
          tax.validateFigure(Figure(move: 'hey', params: {'length': length})),
          isEmpty,
          reason: "'$length' should be a valid hey length",
        );
      }
    });

    test('default length is half', () {
      final defaults = tax.effectiveParams(Figure(move: 'hey'));
      expect(defaults['length'], 'half');
    });

    test('out-of-domain length value is rejected', () {
      expect(
        tax
            .validateFigure(
              Figure(move: 'hey', params: {'length': 'threeQuarters'}),
            )
            .any((i) => i.code == 'invalid_param_value'),
        isTrue,
        reason: 'threeQuarters is not a valid hey length',
      );
    });

    test(
      'figures_json round-trip preserves lessThanHalf and betweenHalfAndFull',
      () {
        for (final length in ['lessThanHalf', 'betweenHalfAndFull']) {
          final figure = Figure(move: 'hey', params: {'length': length});
          expect(
            figureFromJson(figureToJson(figure)),
            figure,
            reason: "'$length' must survive encode/decode round-trip",
          );
        }
      },
    );

    test('length stays structured (not in render template)', () {
      // length values are not in the hey renderTemplate ('{pass1} {move}
      // {shoulder}'), so they never appear in canonical text regardless of value.
      for (final length in [
        'full',
        'half',
        'lessThanHalf',
        'betweenHalfAndFull',
      ]) {
        final canonical = renderer.renderCanonical(
          Figure(move: 'hey', params: {'length': length}),
        );
        expect(
          canonical,
          'role2s hey right',
          reason:
              "'$length' must not surface in canonical text — length is structured-only",
        );
      }
    });

    test('pass2 accepts a pair or the unspecified sentinel', () {
      expect(
        tax.validateFigure(
          Figure(move: 'hey', params: {'pass2': 'unspecified'}),
        ),
        isEmpty,
      );
      expect(
        tax.validateFigure(Figure(move: 'hey', params: {'pass2': 'role1s'})),
        isEmpty,
      );
    });

    test('pass2 rejects a single-dancer identity (must be a pair)', () {
      for (final d in ['onesRole1', 'onesRole2', 'twosRole1', 'twosRole2']) {
        expect(
          tax
              .validateFigure(Figure(move: 'hey', params: {'pass2': d}))
              .any((i) => i.code == 'invalid_param_value'),
          isTrue,
          reason: '$d is a single dancer, not a valid pass2 pair',
        );
      }
    });

    test('all four ricochet flags are present and boolean', () {
      for (final r in ['rico1', 'rico2', 'rico3', 'rico4']) {
        expect(
          tax.validateFigure(Figure(move: 'hey', params: {r: true})),
          isEmpty,
          reason: '$r should be a valid flag',
        );
        expect(
          tax
              .validateFigure(Figure(move: 'hey', params: {r: 'yes'}))
              .any((i) => i.code == 'invalid_param_value'),
          isTrue,
        );
      }
    });

    test('unspecified is hey-scoped, not a general dancer token', () {
      expect(
        tax
            .validateFigure(
              Figure(move: 'swing', params: {'who': 'unspecified'}),
            )
            .any((i) => i.code == 'invalid_param_value'),
        isTrue,
      );
    });
  });

  group('dolphin_hey single-dancer whom', () {
    test('accepts the single-dancer tokens', () {
      for (final d in ['onesRole1', 'onesRole2', 'twosRole1', 'twosRole2']) {
        expect(
          tax.validateFigure(Figure(move: 'dolphin_hey', params: {'whom': d})),
          isEmpty,
          reason: '$d should be a valid dolphin lead',
        );
      }
    });

    test('rejects a pair for whom', () {
      expect(
        tax
            .validateFigure(
              Figure(move: 'dolphin_hey', params: {'whom': 'partners'}),
            )
            .any((i) => i.code == 'invalid_param_value'),
        isTrue,
      );
    });
  });

  group('wave formations', () {
    test('form_long_waves treats 0 beats as typical (formation label)', () {
      expect(
        tax.validateFigure(
          Figure(move: 'form_long_waves', params: {'beats': 0}),
        ),
        isEmpty,
      );
      expect(
        tax
            .validateFigure(
              Figure(move: 'form_long_waves', params: {'beats': 8}),
            )
            .any((i) => i.code == 'atypical_beats'),
        isTrue,
      );
    });

    test('form_a_long_wave carries in/out/balance flags', () {
      expect(
        tax.validateFigure(
          Figure(
            move: 'form_a_long_wave',
            params: {'in': false, 'out': true, 'balance': false},
          ),
        ),
        isEmpty,
      );
    });

    test(
      'form_an_ocean_wave carries pass-through, hands, and center/sides',
      () {
        expect(
          tax.validateFigure(
            Figure(
              move: 'form_an_ocean_wave',
              params: {
                'passThru': false,
                'dir': 'rightDiagonal',
                'centerHand': 'left',
                'center': 'role1s',
                'sides': 'partners',
              },
            ),
          ),
          isEmpty,
        );
      },
    );

    test(
      'form_an_ocean_wave accepts any beats (param-dependent, unencoded)',
      () {
        expect(
          tax.validateFigure(
            Figure(move: 'form_an_ocean_wave', params: {'beats': 8}),
          ),
          isEmpty,
        );
      },
    );
  });

  group('dialect round-trip unaffected', () {
    test('hey pass1 role token maps under dialect and round-trips', () {
      final display = renderer.render(Figure(move: 'hey'), Dialect.larksRobins);
      expect(display, 'Robins hey right');
      expect(
        canonicalizeText(display, Dialect.larksRobins),
        'role2s hey right',
      );
    });
  });
}
