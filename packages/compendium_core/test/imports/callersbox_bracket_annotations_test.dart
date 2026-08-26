import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

List<Figure> _parse(String text, {int beats = 0}) =>
    parseFigureLines(text, beats: beats, frontEnd: tcbFigureFrontEnd);

Figure _single(String text, {int beats = 0}) =>
    _parse(text, beats: beats).single;

void main() {
  group('#744 — square-bracket annotations', () {
    test('a resolved leading dancer fills an empty declared who slot', () {
      final figure = _single('[Men] Revolving door', beats: 8);

      expect(figure.isCustom, isFalse);
      expect(figure.move, 'revolving_door');
      expect(figure.params['who'], 'role1s');
      expect(figure.note, isNull);
    });

    test('a resolved bracket never overwrites an explicit grammar subject', () {
      final figure = _single('[women] Men do si do', beats: 8);

      expect(figure.isCustom, isFalse);
      expect(figure.move, 'do_si_do');
      expect(figure.params['who'], 'role1s');
      expect(figure.note, 'role2s');
    });

    test(
      'an explicit grammar subject wins over a bracketed dancer description',
      () {
        final figure = _single('Men do si do [All four]', beats: 8);

        expect(figure.isCustom, isFalse);
        expect(figure.move, 'do_si_do');
        expect(figure.params['who'], 'role1s');
        expect(figure.note, 'All four');
      },
    );

    test(
      'a clause-final with-body is retained after role canonicalization',
      () {
        final figure = _single('Neighbor swing [with women]', beats: 8);

        expect(figure.isCustom, isFalse);
        expect(figure.move, 'swing');
        expect(figure.note, 'with role2s');
      },
    );

    test('a bracket note renders its canonical role in the active dialect', () {
      final figure = _single('Neighbor swing [with women]', beats: 8);
      final renderer = FigureRenderer(contraTaxonomy);

      expect(
        renderer.renderFreeText(figure.note!, Dialect.larksRobins),
        'with robins',
      );
    });

    test('square and parenthetical annotations combine on one figure', () {
      final figure = _single('Men do si do [All four] (in center)', beats: 8);

      expect(figure.isCustom, isFalse);
      expect(figure.params['who'], 'role1s');
      expect(figure.note, 'All four; in center');
    });

    test(
      'a clause-final bracket remains attached before a semicolon split',
      () {
        final figures = _parse(
          'Neighbor swing [with women]; circle left',
          beats: 8,
        );

        expect(figures, hasLength(2));
        expect(figures.first.move, 'swing');
        expect(figures.first.note, 'with role2s');
        expect(figures.last.move, 'circle');
        expect(figures.last.note, isNull);
      },
    );

    test('a nested role-set descriptor does not become a note', () {
      final figure = _single(
        '[Heads (ones+fours)] Pass through across (NR)',
        beats: 8,
      );

      expect(figure.isCustom, isFalse);
      expect(figure.move, 'pass_through');
      expect(figure.note, isNull);
    });

    test('a non-duple compound dancer phrase stays custom', () {
      final figure = _single('[Ones and twos] do si do', beats: 8);

      expect(figure.isCustom, isTrue);
      expect(figure.params['text'], contains('Ones and twos'));
    });
  });
}
