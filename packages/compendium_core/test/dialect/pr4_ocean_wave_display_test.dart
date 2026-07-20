import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Parity PR4 (issue #290 ocean-wave family) — Part A display renders.
///
/// `form_a_short_wave` and `pass_the_ocean` gain fuller DISPLAY base lines
/// (product wording that intentionally diverges from ContraDB's `words()`;
/// these are our #290 splits with no ContraDB analog). The renders are gated
/// behind `!forCanonical`, so `renderCanonical` stays byte-stable — the FTS /
/// dedupe invariant. Center hand is derived from the `centerHand` param
/// (default 'right'); the side hand is its OPPOSITE (right<->left), never
/// hardcoded — mirroring ContraDB's `sside_hand = stringParamHand(!center_hand)`.
void main() {
  final renderer = FigureRenderer(contraTaxonomy);
  final d = Dialect.canonical;

  group('canonical byte-stability (Part B is the only reindex change)', () {
    test('form_a_short_wave canonical stays "form a wave"', () {
      expect(
        renderer.renderCanonical(Figure(move: 'form_a_short_wave')),
        'form a wave',
      );
    });

    test('pass_the_ocean canonical stays "pass the ocean"', () {
      expect(
        renderer.renderCanonical(Figure(move: 'pass_the_ocean')),
        'pass the ocean',
      );
    });

    test('canonical is param-invariant for both split moves', () {
      // Setting every structured param to a non-default must NOT perturb the
      // canonical text (otherwise dedupe/FTS for these moves would shift — the
      // thing PR4 Part A explicitly must not do).
      const params = {
        'dir': 'rightDiagonal',
        'balance': true,
        'center': 'role1s',
        'centerHand': 'left',
        'sides': 'partners',
        'beats': 8,
      };
      expect(
        renderer.renderCanonical(
          Figure(move: 'form_a_short_wave', params: params),
        ),
        'form a wave',
      );
      expect(
        renderer.renderCanonical(
          Figure(move: 'pass_the_ocean', params: params),
        ),
        'pass the ocean',
      );
    });
  });

  group('display base line is !forCanonical-gated', () {
    test('display diverges from canonical for both moves', () {
      for (final id in const ['form_a_short_wave', 'pass_the_ocean']) {
        final figure = Figure(move: id);
        expect(
          renderer.render(figure, d),
          isNot(renderer.renderCanonical(figure)),
          reason: '$id display should be the fuller product line',
        );
      }
    });
  });

  group('form_a_short_wave display', () {
    test('default (centerHand right -> side left)', () {
      expect(
        renderer.render(Figure(move: 'form_a_short_wave'), d),
        'form a short wave - role2s by the right in the center, '
        'neighbor by the left on the sides',
      );
    });

    test('centerHand left flips the derived side hand to right', () {
      expect(
        renderer.render(
          Figure(move: 'form_a_short_wave', params: {'centerHand': 'left'}),
          d,
        ),
        'form a short wave - role2s by the left in the center, '
        'neighbor by the right on the sides',
      );
    });

    test('short wave has no balance clause even when balance is set', () {
      // The authored product spec gives the balance clause to pass_the_ocean
      // only; the short wave line stays identical.
      expect(
        renderer.render(
          Figure(move: 'form_a_short_wave', params: {'balance': true}),
          d,
        ),
        renderer.render(Figure(move: 'form_a_short_wave'), d),
      );
    });

    test('missing center subject leaves no dangling connective', () {
      final out = renderer.render(
        Figure(move: 'form_a_short_wave', params: {'center': null}),
        d,
      );
      expect(out, startsWith('form a short wave - by the right in the center'));
      expect(out, isNot(contains('  ')));
      expect(out, isNot(contains('- ,')));
    });
  });

  group('pass_the_ocean display', () {
    test('default (centerHand right -> side left)', () {
      expect(
        renderer.render(Figure(move: 'pass_the_ocean'), d),
        'pass through to an ocean wave - role2s catch right hands in the '
        'center, neighbor take left hands on the sides',
      );
    });

    test('balance appends a trailing " and balance" clause', () {
      expect(
        renderer.render(
          Figure(move: 'pass_the_ocean', params: {'balance': true}),
          d,
        ),
        'pass through to an ocean wave - role2s catch right hands in the '
        'center, neighbor take left hands on the sides and balance',
      );
    });

    test('non-default dir surfaces the diagonal word + indefinite article', () {
      expect(
        renderer.render(
          Figure(move: 'pass_the_ocean', params: {'dir': 'rightDiagonal'}),
          d,
        ),
        'pass through to a right diagonal ocean wave - role2s catch right '
        'hands in the center, neighbor take left hands on the sides',
      );
    });

    test('the "across" dir default is silent (no diagonal word)', () {
      expect(
        renderer.render(
          Figure(move: 'pass_the_ocean', params: {'dir': 'across'}),
          d,
        ),
        renderer.render(Figure(move: 'pass_the_ocean'), d),
      );
    });

    test('centerHand left flips the derived side hand to right', () {
      expect(
        renderer.render(
          Figure(move: 'pass_the_ocean', params: {'centerHand': 'left'}),
          d,
        ),
        'pass through to an ocean wave - role2s catch left hands in the '
        'center, neighbor take right hands on the sides',
      );
    });

    test('unknown "*" centerHand is surfaced, never blank-dropped', () {
      final out = renderer.render(
        Figure(move: 'pass_the_ocean', params: {'centerHand': '*'}),
        d,
      );
      expect(out, contains('catch * hands'));
      expect(out, contains('take * hands'));
      expect(out, isNot(contains('  ')));
    });

    test('full param combo renders every token coherently', () {
      expect(
        renderer.render(
          Figure(
            move: 'pass_the_ocean',
            params: const {
              'dir': 'rightDiagonal',
              'balance': true,
              'center': 'role1s',
              'centerHand': 'left',
              'sides': 'partners',
              'beats': 8,
            },
          ),
          d,
        ),
        'pass through to a right diagonal ocean wave - role1s catch left '
        'hands in the center, partner take right hands on the sides and '
        'balance',
      );
    });

    test('renderSummary passes the display line through without double '
        'balance', () {
      expect(
        renderer.renderSummary(
          Figure(move: 'pass_the_ocean', params: {'balance': true}),
          d,
        ),
        renderer.render(
          Figure(move: 'pass_the_ocean', params: {'balance': true}),
          d,
        ),
      );
    });
  });
}
