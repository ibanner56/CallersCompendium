import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

/// Parity PR4 (issue #290 ocean-wave family) — Part A display renders.
///
/// `form_short_waves` and `pass_the_ocean` gain fuller DISPLAY base lines
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
    test('form_short_waves canonical stays "form short waves"', () {
      // v21 (#295) renamed the move, so the canonical text is now the new
      // display name; stored figures are migrated by CompendiumDatabase v19.
      expect(
        renderer.renderCanonical(Figure(move: 'form_short_waves')),
        'form short waves',
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
          testFigure(move: 'form_short_waves', params: params),
        ),
        'form short waves',
      );
      expect(
        renderer.renderCanonical(
          testFigure(move: 'pass_the_ocean', params: params),
        ),
        'pass the ocean',
      );
    });
  });

  group('display base line is !forCanonical-gated', () {
    test('display diverges from canonical for both moves', () {
      for (final id in const ['form_short_waves', 'pass_the_ocean']) {
        final figure = testFigure(move: id);
        expect(
          renderer.render(figure, d),
          isNot(renderer.renderCanonical(figure)),
          reason: '$id display should be the fuller product line',
        );
      }
    });
  });

  group('form_short_waves display', () {
    test('default (centerHand left -> side right)', () {
      expect(
        renderer.render(Figure(move: 'form_short_waves'), d),
        'form short waves - role2s by the left in the center, '
        'neighbor by the right on the sides',
      );
    });

    test('centerHand left flips the derived side hand to right', () {
      expect(
        renderer.render(
          Figure(move: 'form_short_waves', params: {'centerHand': 'left'}),
          d,
        ),
        'form short waves - role2s by the left in the center, '
        'neighbor by the right on the sides',
      );
    });

    test('a set balance appends the " - and balance" clause (#296)', () {
      // v21 (#296): the wave-formation moves now surface their balance on the
      // display path, so the short wave no longer silently drops the flag.
      expect(
        renderer.render(
          Figure(move: 'form_short_waves', params: {'balance': true}),
          d,
        ),
        '${renderer.render(Figure(move: 'form_short_waves'), d)}'
        ' - and balance',
      );
    });

    test('missing center subject leaves no dangling connective', () {
      final out = renderer.render(
        invalidTestFigure(
          move: 'form_short_waves',
          params: {'center': null},
          reason:
              'a null center subject must render without leaving a dangling connective',
        ),
        d,
      );
      expect(out, startsWith('form short waves - by the left in the center'));
      expect(out, isNot(contains('  ')));
      expect(out, isNot(contains('- ,')));
    });
  });

  group('pass_the_ocean display', () {
    test('default (centerHand left -> side right)', () {
      expect(
        renderer.render(Figure(move: 'pass_the_ocean'), d),
        'pass through to an ocean wave - role2s catch left hands in the '
        'center, neighbor take right hands on the sides',
      );
    });

    test('balance appends a trailing " and balance" clause', () {
      expect(
        renderer.render(
          Figure(move: 'pass_the_ocean', params: {'balance': true}),
          d,
        ),
        'pass through to an ocean wave - role2s catch left hands in the '
        'center, neighbor take right hands on the sides and balance',
      );
    });

    test('non-default dir surfaces the diagonal word + indefinite article', () {
      expect(
        renderer.render(
          Figure(move: 'pass_the_ocean', params: {'dir': 'rightDiagonal'}),
          d,
        ),
        'pass through to a right diagonal ocean wave - role2s catch left '
        'hands in the center, neighbor take right hands on the sides',
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

    test('centerHand right flips the derived side hand to left', () {
      expect(
        renderer.render(
          Figure(move: 'pass_the_ocean', params: {'centerHand': 'right'}),
          d,
        ),
        'pass through to an ocean wave - role2s catch right hands in the '
        'center, neighbor take left hands on the sides',
      );
    });

    test('unknown "*" centerHand is surfaced, never blank-dropped', () {
      final out = renderer.render(
        // invalid-fixture: value is deliberately out of domain — unknown "*" centerHand is surfaced, never blank-dropped
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
