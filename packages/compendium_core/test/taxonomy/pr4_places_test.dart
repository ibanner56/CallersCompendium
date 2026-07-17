import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

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
        final defaults = tax.effectiveParams(Figure(move: id));
        expect(
          tax.validateFigure(Figure(move: id, params: defaults)),
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
      // star grip 'none' is structured, not rendered.
      'star right 4 places': Figure(move: 'star'),
      'ones facing star clockwise 3 places': Figure(move: 'facing_star'),
      'partners square through 4 places': Figure(move: 'square_through'),
    };
    cases.forEach((expected, figure) {
      test('"$expected"', () {
        expect(renderer.renderCanonical(figure), expected);
      });
    });

    test('star renders hand + places but omits an unspecified grip', () {
      expect(
        renderer.renderCanonical(
          Figure(move: 'star', params: {'hand': 'left', 'grip': 'wristGrip'}),
        ),
        // grip is structured, not a render token.
        'star left 4 places',
      );
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
            .validateFigure(Figure(move: 'circle', params: {'places': 0}))
            .any((i) => i.code == 'invalid_param_value'),
        isTrue,
      );
    });

    test('star grip is restricted to its choice domain', () {
      expect(
        tax
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
}
