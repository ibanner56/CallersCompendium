import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

/// Roadmap 2.4a — PR3 "choice-enum" moves: down_the_hall, up_the_hall, zig_zag,
/// slice, contra_corners, turn_alone, figure_8, poussette, rory_o_more. Adds the
/// `centers` and single-dancer (`onesRole1`/…) dancer-vocab tokens.
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);
  final larks = Dialect.larksRobins;

  const newMoves = [
    'down_the_hall',
    'up_the_hall',
    'zig_zag',
    'slice',
    'contra_corners',
    'turn_alone',
    'figure_8',
    'poussette',
    'rory_o_more',
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
      'everyone down the hall forward': Figure(move: 'down_the_hall'),
      'everyone up the hall forward': Figure(move: 'up_the_hall'),
      'partners zig zag left': Figure(move: 'zig_zag'),
      'slice left couple straight': Figure(move: 'slice'),
      'ones contra corners': Figure(move: 'contra_corners'),
      'everyone turn alone': Figure(move: 'turn_alone'),
      'ones half figure 8': Figure(move: 'figure_8'),
      'ones poussette neighbors half clockwise': Figure(move: 'poussette'),
      "everyone Rory O'More right": Figure(move: 'rory_o_more'),
    };
    cases.forEach((expected, figure) {
      test('"$expected"', () {
        expect(renderer.renderCanonical(figure), expected);
      });
    });

    test('down_the_hall renders a multi-word facing (ender is structured)', () {
      expect(
        renderer.renderCanonical(
          Figure(
            move: 'down_the_hall',
            params: {'facing': 'forwardThenBackward', 'ender': 'threadNeedle'},
          ),
        ),
        // `ender` is not a render token, so it does not appear here.
        'everyone down the hall forward then backward',
      );
    });

    test('figure_8 renders the full variant', () {
      expect(
        renderer.renderCanonical(
          Figure(move: 'figure_8', params: {'half': 'full'}),
        ),
        'ones full figure 8',
      );
    });
  });

  group('new dancer vocab (centers + single-dancer tokens)', () {
    const dancerTokens = [
      'centers',
      'onesRole1',
      'onesRole2',
      'twosRole1',
      'twosRole2',
    ];

    test('are accepted as dancerSet values', () {
      const spec = ParamSpec(ParamKind.dancerSet, defaultValue: 'centers');
      for (final v in dancerTokens) {
        expect(spec.validate(v), isTrue, reason: '$v should be a valid dancer');
      }
    });

    test('are not role tokens and survive canonicalize unchanged', () {
      for (final v in dancerTokens) {
        expect(isRoleToken(v), isFalse);
        // Role-adjacent, but not role tokens: canonicalize must not rewrite them
        // (protects the dialect round-trip property).
        expect(canonicalizeText('$v cross', larks), '$v cross');
      }
    });

    test(
      'rory_o_more accepts centers and figure_8 accepts a single dancer',
      () {
        expect(
          tax.validateFigure(
            Figure(move: 'rory_o_more', params: {'who': 'centers'}),
          ),
          isEmpty,
        );
        expect(
          tax.validateFigure(
            Figure(move: 'figure_8', params: {'lead': 'twosRole1'}),
          ),
          isEmpty,
        );
      },
    );
  });

  group('goodBeats warnings', () {
    test('down_the_hall warns on atypical beats', () {
      final issues = tax.validateFigure(
        Figure(move: 'down_the_hall', params: {'beats': 6}),
      );
      expect(issues.single.code, 'atypical_beats');
    });

    test('figure_8 accepts both 8 (half) and 16 (full)', () {
      for (final b in [8, 16]) {
        expect(
          tax.validateFigure(
            testFigure(move: 'figure_8', params: {'beats': b}),
          ),
          isEmpty,
        );
      }
    });

    test(
      'turn_alone accepts any in-domain beat count (range not enforced)',
      () {
        expect(
          tax.validateFigure(Figure(move: 'turn_alone', params: {'beats': 2})),
          isEmpty,
        );
      },
    );
  });

  group('param domains', () {
    test('down_the_hall rejects an unknown ender', () {
      expect(
        tax
            .validateFigure(
              // invalid-fixture: value is deliberately out of domain — down_the_hall rejects an unknown ender
              Figure(move: 'down_the_hall', params: {'ender': 'boogie'}),
            )
            .any((i) => i.code == 'invalid_param_value'),
        isTrue,
      );
    });

    test('figure_8 lead is restricted to single-dancer tokens', () {
      expect(
        tax
            .validateFigure(
              // invalid-fixture: value is deliberately out of domain — figure_8 lead is restricted to single-dancer tokens
              Figure(move: 'figure_8', params: {'lead': 'partners'}),
            )
            .any((i) => i.code == 'invalid_param_value'),
        isTrue,
      );
    });

    test('rory_o_more who is restricted to its chooser set', () {
      expect(
        tax
            .validateFigure(
              // invalid-fixture: value is deliberately out of domain — rory_o_more who is restricted to its chooser set
              Figure(move: 'rory_o_more', params: {'who': 'shadows'}),
            )
            .any((i) => i.code == 'invalid_param_value'),
        isTrue,
      );
    });

    test('poussette turn accepts a spin direction', () {
      expect(
        tax.validateFigure(
          Figure(move: 'poussette', params: {'turn': 'counterclockwise'}),
        ),
        isEmpty,
      );
    });
  });
}
