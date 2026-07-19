import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Roadmap 2.4a — PR2 "dancer-interaction" moves: gate, give_and_take,
/// pull_by_dancers, pull_by_direction, cross_trails, plus the roll_away `whom`
/// extension. All reuse the existing ParamKind set (no new vocabulary).
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);
  final larks = Dialect.larksRobins;

  const newMoves = [
    'gate',
    'give_and_take',
    'pull_by_dancers',
    'pull_by_direction',
    'cross_trails',
  ];

  group('registration & defaults', () {
    for (final id in [...newMoves, 'roll_away']) {
      test('$id resolves and validates with all defaults populated', () {
        expect(tax.resolve(id)?.id, id, reason: '$id should be registered');
        // validateFigure only checks explicitly-provided params, so populate
        // the figure with effectiveParams to actually validate the defaults.
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
      'ones gate neighbors up': Figure(move: 'gate'),
      'role1s give & take partners': Figure(move: 'give_and_take'),
      'neighbors pull by right': Figure(move: 'pull_by_dancers'),
      'pull by along right': Figure(move: 'pull_by_direction'),
      'partners cross trails across neighbors': Figure(move: 'cross_trails'),
      // roll_away now renders its added whom target.
      'neighbors roll away partners': Figure(move: 'roll_away'),
    };
    cases.forEach((expected, figure) {
      test('"$expected"', () {
        expect(renderer.renderCanonical(figure), expected);
      });
    });

    test('gate renders a non-default face', () {
      expect(
        renderer.renderCanonical(
          Figure(move: 'gate', params: {'face': 'down'}),
        ),
        'ones gate neighbors down',
      );
    });

    test('roll_away renders an overridden whom', () {
      expect(
        renderer.renderCanonical(
          Figure(move: 'roll_away', params: {'whom': 'neighbors'}),
        ),
        'neighbors roll away neighbors',
      );
    });
  });

  group('dialect rendering + canonicalize round-trip', () {
    test('give_and_take role token maps to Larks and round-trips', () {
      final display = renderer.render(Figure(move: 'give_and_take'), larks);
      expect(display, 'larks give & take partner');
      // The role token survives the render→canonicalize round-trip.
      expect(canonicalizeText(display, larks), contains('role1s'));
    });
  });

  group('goodBeats warnings', () {
    test('gate warns on atypical beats', () {
      final issues = tax.validateFigure(
        Figure(move: 'gate', params: {'beats': 6}),
      );
      expect(issues.single.code, 'atypical_beats');
      expect(issues.single.severity, ValidationSeverity.warning);
    });

    test('give_and_take accepts both 4 and 8 without warning', () {
      expect(
        tax.validateFigure(Figure(move: 'give_and_take', params: {'beats': 4})),
        isEmpty,
      );
      expect(
        tax.validateFigure(Figure(move: 'give_and_take', params: {'beats': 8})),
        isEmpty,
      );
    });

    test('pull_by_dancers accepts 2 and 4 without warning', () {
      for (final b in [2, 4]) {
        expect(
          tax.validateFigure(
            Figure(move: 'pull_by_dancers', params: {'beats': b}),
          ),
          isEmpty,
          reason: '$b beats should be typical',
        );
      }
    });
  });

  group('param domains', () {
    test('gate rejects an out-of-domain face', () {
      expect(
        tax
            .validateFigure(Figure(move: 'gate', params: {'face': 'sideways'}))
            .any((i) => i.code == 'invalid_param_value'),
        isTrue,
      );
    });

    test('give_and_take restricts who to a role', () {
      expect(
        tax
            .validateFigure(
              Figure(move: 'give_and_take', params: {'who': 'partners'}),
            )
            .any((i) => i.code == 'invalid_param_value'),
        isTrue,
        reason: 'who is narrowed to role1s/role2s',
      );
      expect(
        tax.validateFigure(
          Figure(move: 'give_and_take', params: {'who': 'role2s'}),
        ),
        isEmpty,
      );
    });

    test('give_and_take accepts the take-only flag', () {
      expect(
        tax.validateFigure(
          Figure(move: 'give_and_take', params: {'give': false}),
        ),
        isEmpty,
      );
    });
  });
}
