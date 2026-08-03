import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

/// Roadmap 2.4a — PR5 "hey/wave family" (final slice): pass_by, hey,
/// dolphin_hey, form_long_waves, form_a_long_wave. (The wave family also
/// introduced `form_an_ocean_wave`, later split by #290 into
/// `form_short_waves` / `pass_the_ocean` and removed from the taxonomy at v14
/// — see ocean_wave_split_test.dart.) No new ParamKind; the reduced-but-
/// structured hey model + wave formations.
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);

  const newMoves = [
    'pass_by',
    'hey',
    'dolphin_hey',
    'form_long_waves',
    'form_a_long_wave',
  ];

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
  });

  group('canonical rendering (golden)', () {
    final cases = <String, Figure>{
      'neighbors pass by': Figure(move: 'pass_by'),
      'role2s hey right': Figure(move: 'hey'),
      'ones dolphin hey right': Figure(move: 'dolphin_hey'),
      'role1s form long waves': Figure(move: 'form_long_waves'),
      'role2s form a long wave': Figure(move: 'form_a_long_wave'),
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
          tax.validateFigure(testFigure(move: 'hey', params: {'length': length})),
          isEmpty,
          reason: "'$length' should be a valid hey length",
        );
      }
    });

    test('default length is half', () {
      final defaults = tax.effectiveParams(Figure(move: 'hey'));
      expect(defaults['length'], 'half');
    });

    test('length is surfaced before pass2 in the entry-form field order', () {
      // The dance-entry form renders params in MoveDef.params insertion order
      // (figure_list_editor _buildParams: first 3 inline, rest behind "More
      // options"). `length` is almost always set; `pass2` rarely is, so it must
      // sit ahead of `pass2` — and within the inline first-3 group.
      final keys = tax.resolve('hey')!.params.keys.toList();
      final lengthIdx = keys.indexOf('length');
      final pass2Idx = keys.indexOf('pass2');
      expect(
        lengthIdx,
        lessThan(pass2Idx),
        reason: 'length must precede pass2',
      );
      expect(
        lengthIdx,
        lessThan(3),
        reason: 'length must be in the inline first-3 fields',
      );
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
          final figure = testFigure(move: 'hey', params: {'length': length});
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
          testFigure(move: 'hey', params: {'length': length}),
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
              .validateFigure(invalidTestFigure(move: 'hey', params: {'pass2': d}, reason: 'asserts validateFigure REJECTS a single-dancer identity for pass2, which must name a pair'))
              .any((i) => i.code == 'invalid_param_value'),
          isTrue,
          reason: '$d is a single dancer, not a valid pass2 pair',
        );
      }
    });

    test('all four ricochet flags are present and boolean', () {
      for (final r in ['rico1', 'rico2', 'rico3', 'rico4']) {
        expect(
          tax.validateFigure(testFigure(move: 'hey', params: {r: true})),
          isEmpty,
          reason: '$r should be a valid flag',
        );
        expect(
          tax
              .validateFigure(invalidTestFigure(move: 'hey', params: {r: 'yes'}, reason: 'asserts validateFigure REJECTS a non-boolean value for a flag param'))
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
          tax.validateFigure(testFigure(move: 'dolphin_hey', params: {'whom': d})),
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

    test('form_a_long_wave accepts any beats (param-dependent, unencoded)', () {
      expect(
        tax.validateFigure(
          Figure(move: 'form_a_long_wave', params: {'beats': 8}),
        ),
        isEmpty,
      );
    });
  });

  group('dialect round-trip unaffected', () {
    test('hey pass1 role token maps under dialect; canonical round-trips', () {
      // PR3 rewrote the hey DISPLAY into ContraDB's fuller clause; the dialect
      // still maps the pass1 role token (role2s -> robins).
      final display = renderer.render(Figure(move: 'hey'), Dialect.larksRobins);
      expect(
        display,
        'robins start a half hey - rights in center, lefts on ends',
      );
      // The canonical text (the dedupe/FTS key) is unchanged and still
      // round-trips through canonicalizeText.
      final canonical = renderer.renderCanonical(Figure(move: 'hey'));
      expect(canonical, 'role2s hey right');
      expect(
        canonicalizeText(canonical, Dialect.larksRobins),
        'role2s hey right',
      );
    });
  });
}
