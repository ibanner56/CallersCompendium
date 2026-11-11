// Taxonomy v39 (#2120): a figure 8 or poussette fraction of `other` states
// its amount in the sibling `amount` param, and an `other` that states none
// reads as an unstated amount instead of the bare token "other".
import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  final renderer = FigureRenderer(contraTaxonomy);
  final larks = Dialect.larksRobins;

  Figure figure8(Map<String, Object?> params) =>
      Figure(move: 'figure_8', params: {'where': 'none', ...params});
  Figure poussette(Map<String, Object?> params) =>
      Figure(move: 'poussette', params: params);

  test('contraTaxonomyVersion is 39', () {
    expect(contraTaxonomyVersion, 39);
  });

  group('the amount param', () {
    for (final move in ['figure_8', 'poussette']) {
      test('$move declares a sentinel-defaulted rotation amount', () {
        final spec = contraTaxonomy.resolve(move)!.params[fractionAmountParam]!;
        expect(spec.kind, ParamKind.rotation);
        expect(spec.defaultValue, ParamVocab.unspecified);
        expect(spec.validate(1.5), isTrue);
        expect(spec.validate(ParamVocab.unspecified), isTrue);
        expect(spec.validate(3), isFalse);
        expect(spec.validate('1/3'), isFalse);
      });

      test('$move with other and an amount validates cleanly', () {
        final issues = contraTaxonomy.validateFigure(
          Figure(move: move, params: {'fraction': 'other', 'amount': 1.5}),
        );
        expect(issues.where((i) => i.code != 'atypical_beats'), isEmpty);
      });
    }

    test('fractionParamsForAmount names a named amount and keeps others', () {
      expect(fractionParamsForAmount(0.25), {'fraction': 'quarter'});
      expect(fractionParamsForAmount(0.5), {'fraction': 'half'});
      expect(fractionParamsForAmount(0.75), {'fraction': 'threeQuarter'});
      expect(fractionParamsForAmount(1), {'fraction': 'full'});
      expect(fractionParamsForAmount(1.0), {'fraction': 'full'});
      expect(fractionParamsForAmount(1.5), {
        'fraction': 'other',
        'amount': 1.5,
      });
      expect(fractionParamsForAmount(2.5), {
        'fraction': 'other',
        'amount': 2.5,
      });
      // Outside the quarter-step domain: nothing storable.
      expect(fractionParamsForAmount(0.4), isNull);
      expect(fractionParamsForAmount(3), isNull);
    });

    test('statedFractionAmount reads the amount only while other', () {
      expect(statedFractionAmount({'fraction': 'other', 'amount': 1.5}), 1.5);
      expect(statedFractionAmount({'fraction': 'half', 'amount': 1.5}), isNull);
      expect(statedFractionAmount({'fraction': 'other'}), isNull);
      expect(
        statedFractionAmount({
          'fraction': 'other',
          'amount': ParamVocab.unspecified,
        }),
        isNull,
      );
    });
  });

  group('beats', () {
    int beats(Map<String, Object?> params) =>
        contraTaxonomy.effectiveParams(figure8(params))['beats']! as int;

    test('a figure 8 amount derives 16 beats per full figure', () {
      expect(beats({'fraction': 'half'}), 8);
      expect(beats({'fraction': 'full'}), 16);
      expect(beats({'fraction': 'other', 'amount': 1.5}), 24);
      expect(beats({'fraction': 'other', 'amount': 2}), 32);
    });

    test('an amount left behind by a named fraction derives nothing', () {
      expect(beats({'fraction': 'half', 'amount': 2}), 8);
    });

    test('an unstated amount keeps the flat default', () {
      expect(beats({'fraction': 'other'}), 8);
    });

    test('the derived count is not flagged as atypical', () {
      final issues = contraTaxonomy.validateFigure(
        figure8({'fraction': 'other', 'amount': 1.5, 'beats': 24}),
      );
      expect(issues.map((i) => i.code), isNot(contains('atypical_beats')));
      final off = contraTaxonomy.validateFigure(
        figure8({'fraction': 'other', 'amount': 1.5, 'beats': 20}),
      );
      expect(off.map((i) => i.code), contains('atypical_beats'));
    });
  });

  group('canonical text', () {
    test('an amount is written in place of the fraction', () {
      expect(
        renderer.renderCanonical(figure8({'fraction': 'other', 'amount': 1.5})),
        'ones 1½ figure 8',
      );
      expect(
        renderer.renderCanonical(poussette({'fraction': 'other', 'amount': 2})),
        'role1s poussette neighbors two clockwise',
      );
    });

    test('an other with no amount reads as unstated, not "other"', () {
      expect(
        renderer.renderCanonical(figure8({'fraction': 'other'})),
        'ones unstated amount figure 8',
      );
    });

    test('a stale amount under a named fraction is not rendered', () {
      expect(
        renderer.renderCanonical(figure8({'fraction': 'half', 'amount': 2})),
        'ones half figure 8',
      );
    });
  });

  group('display', () {
    test('figure 8 shows the amount', () {
      expect(
        renderer.render(figure8({'fraction': 'other', 'amount': 1.5}), larks),
        'ones 1½ figure 8',
      );
      expect(
        renderer.render(
          figure8({'fraction': 'other', 'amount': 1.5}),
          larks,
          decimals: true,
        ),
        'ones 1.5 figure 8',
      );
      expect(
        renderer.renderVerbose(
          figure8({'fraction': 'other', 'amount': 1.5}),
          larks,
        ),
        'ones one and a half figure 8',
      );
    });

    test('figure 8 with no amount says it is unstated', () {
      expect(
        renderer.render(figure8({'fraction': 'other'}), larks),
        'ones an unstated amount of figure 8',
      );
    });

    test('poussette shows the amount', () {
      expect(
        renderer.render(poussette({'fraction': 'other', 'amount': 1.5}), larks),
        startsWith('1½ poussette - '),
      );
      expect(
        renderer.render(poussette({'fraction': 'other'}), larks),
        startsWith('an unstated amount of poussette - '),
      );
    });

    test('poussette verbose spells the named fractions out', () {
      expect(
        renderer.renderVerbose(poussette({'fraction': 'threeQuarter'}), larks),
        startsWith('three quarters poussette - '),
      );
    });
  });
}
