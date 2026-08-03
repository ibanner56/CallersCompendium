import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

/// Roadmap 2.4a — PR1 "simple moves": additive ContraDB moves that reuse the
/// existing ParamKind set (no new vocabulary). Each new move must validate at
/// its defaults, render golden canonical text, warn on atypical beats, and
/// leave the dialect round-trip untouched.
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);

  const newMoves = [
    'butterfly_whirl',
    'arch_and_dive',
    'california_twirl',
    'stand_still',
    'slide_along_set',
    'mad_robin',
    'revolving_door',
    'star_promenade',
  ];

  group('registration & defaults', () {
    for (final id in newMoves) {
      test('$id resolves and validates at its defaults', () {
        expect(tax.resolve(id)?.id, id, reason: '$id should be registered');
        expect(
          tax.validateFigure(testFigure(move: id)),
          isEmpty,
          reason: '$id at its default params must produce no issues',
        );
      });
    }
  });

  group('canonical rendering (golden)', () {
    final cases = <String, Figure>{
      'butterfly whirl': Figure(move: 'butterfly_whirl'),
      'ones arch and dive': Figure(move: 'arch_and_dive'),
      'partners California twirl': Figure(move: 'california_twirl'),
      'stand still': Figure(move: 'stand_still'),
      'slide along set left': Figure(move: 'slide_along_set'),
      'ones mad robin once': Figure(move: 'mad_robin'),
      'role2s revolving door right partners': Figure(move: 'revolving_door'),
      'role1s star promenade right ½': Figure(move: 'star_promenade'),
    };
    cases.forEach((expected, figure) {
      test('"$expected"', () {
        expect(renderer.renderCanonical(figure), expected);
      });
    });

    test('slide_along_set renders the right-slide variant', () {
      expect(
        renderer.renderCanonical(
          Figure(move: 'slide_along_set', params: {'slide': 'right'}),
        ),
        'slide along set right',
      );
    });

    test('revolving_door renders its whom target', () {
      expect(
        renderer.renderCanonical(
          Figure(move: 'revolving_door', params: {'whom': 'neighbors'}),
        ),
        'role2s revolving door right neighbors',
      );
    });
  });

  group('display rendering maps role tokens via dialect', () {
    test('star_promenade omits its default role1s subject in display', () {
      // PR1: star_promenade omits its default role subject (ContraDB drops the
      // gentlespoons subject); the hand/turn still render.
      expect(
        renderer.render(Figure(move: 'star_promenade'), Dialect.larksRobins),
        'star promenade right ½',
      );
    });
    test('a non-default role subject still maps under the dialect', () {
      expect(
        renderer.render(
          Figure(move: 'star_promenade', params: {'who': 'role2s'}),
          Dialect.larksRobins,
        ),
        'robins star promenade right ½',
      );
    });
  });

  group('goodBeats warnings', () {
    test('atypical beats is a warning, not an error', () {
      final issues = tax.validateFigure(
        Figure(move: 'butterfly_whirl', params: {'beats': 6}),
      );
      expect(issues.single.code, 'atypical_beats');
      expect(issues.single.severity, ValidationSeverity.warning);
    });

    test('mad_robin accepts both 6 and 8 beats without warning', () {
      expect(
        tax.validateFigure(Figure(move: 'mad_robin', params: {'beats': 6})),
        isEmpty,
      );
      expect(
        tax.validateFigure(Figure(move: 'mad_robin', params: {'beats': 8})),
        isEmpty,
      );
    });

    test('stand_still accepts any in-domain beat count without warning', () {
      expect(
        tax.validateFigure(Figure(move: 'stand_still', params: {'beats': 13})),
        isEmpty,
      );
    });
  });

  group('param domains', () {
    test('slide_along_set rejects an out-of-domain slide value', () {
      expect(
        tax
            .validateFigure(
              Figure(move: 'slide_along_set', params: {'slide': 'sideways'}),
            )
            .any((i) => i.code == 'invalid_param_value'),
        isTrue,
      );
    });

    test('star_promenade rejects a non-quarter rotation', () {
      expect(
        tax
            .validateFigure(
              Figure(move: 'star_promenade', params: {'turn': 0.3}),
            )
            .any((i) => i.code == 'invalid_param_value'),
        isTrue,
      );
    });
  });
}
