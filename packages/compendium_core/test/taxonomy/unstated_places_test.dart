import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// Taxonomy v39: a circle's or star's `places` may be left unstated. The
/// [ParamVocab.unspecified] sentinel is valid there, renders as nothing in
/// every render path, and is still refused by the other places params.
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);
  const unstated = ParamVocab.unspecified;

  Figure fig(String move, Map<String, Object?> params) =>
      testFigure(move: move, params: params);

  group('which places params admit "not stated"', () {
    for (final id in ['circle', 'star']) {
      test('$id.places does, and keeps its numeric default', () {
        final spec = tax.resolve(id)!.params['places']!;
        expect(spec.validate(unstated), isTrue);
        expect(spec.defaultValue, isA<int>());
        expect(tax.validateFigure(fig(id, {'places': unstated})), isEmpty);
        expect(
          paramDomain(spec),
          containsAll(<Object>[1, 10, unstated]),
          reason: 'the domain lists the sentinel beside the counts',
        );
      });
    }

    for (final id in ['facing_star', 'square_through', 'circular_hey']) {
      test('$id does not', () {
        final def = tax.resolve(id)!;
        final name = id == 'circular_hey' ? 'changes' : 'places';
        final spec = def.params[name]!;
        expect(spec.kind, ParamKind.places);
        expect(spec.validate(unstated), isFalse);
        expect(paramDomain(spec), isNot(contains(unstated)));
      });
    }

    test('a bare places spec still refuses the sentinel and other text', () {
      const spec = ParamSpec(ParamKind.places, defaultValue: 3);
      expect(spec.validate(unstated), isFalse);
      const opted = ParamSpec(
        ParamKind.places,
        defaultValue: 3,
        choices: [unstated],
      );
      expect(opted.validate('3'), isFalse);
      expect(opted.validate('none'), isFalse);
      expect(opted.validate(0), isFalse);
      expect(opted.validate(4), isTrue);
    });
  });

  group('an unstated distance renders as nothing', () {
    test('circle', () {
      final f = fig('circle', {'direction': 'left', 'places': unstated});
      expect(renderer.render(f, Dialect.canonical), 'circle left');
      expect(renderer.renderVerbose(f, Dialect.canonical), 'circle left');
      expect(renderer.renderCanonical(f), 'circle left');
    });

    test('single file circle', () {
      final f = fig('circle', {
        'direction': 'right',
        'places': unstated,
        'singleFile': true,
      });
      expect(renderer.render(f, Dialect.canonical), 'single file circle right');
      expect(
        renderer.renderCanonical(f),
        'single file promenade right (circle, counterclockwise)',
      );
    });

    test('star, with and without a grip', () {
      final plain = fig('star', {'hand': 'right', 'places': unstated});
      expect(renderer.render(plain, Dialect.canonical), 'star right');
      expect(renderer.renderCanonical(plain), 'star right');
      final grip = fig('star', {
        'hand': 'left',
        'places': unstated,
        'grip': 'wristGrip',
      });
      expect(
        renderer.render(grip, Dialect.canonical),
        'star left - wrist grip',
        reason: 'no dangling dash where the count would follow',
      );
      expect(renderer.renderCanonical(grip), 'star left - wrist grip');
      expect(
        renderer.render(
          fig('star', {'hand': 'left', 'places': 3, 'grip': 'handsAcross'}),
          Dialect.canonical,
        ),
        'star left - hands across - 3 places',
        reason: 'a stated count keeps the dash before it',
      );
    });

    test('a stated or omitted count is unchanged', () {
      expect(
        renderer.render(fig('circle', {'places': 4}), Dialect.canonical),
        'circle left 4 places',
      );
      expect(
        renderer.render(fig('star', const {}), Dialect.canonical),
        'star left 4 places',
        reason: 'an omitted places still means the default',
      );
    });
  });

  test(
    'no reader produces the sentinel: a line with no count omits places',
    () {
      for (final line in ['circle left', 'star right']) {
        final f = parseFigureLine(line)!;
        expect(f.params.containsKey('places'), isFalse, reason: line);
      }
    },
  );

  test('a snippet signature with an unstated places describes itself', () {
    final f = fig('circle', {'direction': 'left', 'places': unstated});
    final signature = figureSnippetSignature(f, tax)!;
    expect(signature, contains('places=unspecified'));
    expect(
      describeFigureSignature(signature, tax, renderer, Dialect.canonical),
      'circle left',
    );
  });
}
