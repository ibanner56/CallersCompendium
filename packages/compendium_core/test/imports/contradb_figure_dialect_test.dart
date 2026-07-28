import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Tests for the ContraDB-HTML figure front-end
/// (`contradb_figure_dialect.dart`, [contraDbHtmlFigureFrontEnd]): the
/// reverse-parsers that map ContraDB's rendered figure prose back to structured
/// taxonomy figures and split off a verbatim note tail.
///
/// Inputs are the actual strings ContraDB renders (default dialect →
/// `gentlespoons`/`ladles`, unicode fractions, `&`); the default
/// [scrubFigureText] runs first (roles → `role1s`/`role2s`), exactly as the live
/// adapter drives it.
Figure _parse(String text) {
  final f = parseFigureLine(text, frontEnd: contraDbHtmlFigureFrontEnd);
  expect(f, isNotNull, reason: 'parse of "$text" returned null');
  return f!;
}

void main() {
  group('contraDbHtmlFigureFrontEnd — structured recognition', () {
    test('plain swing', () {
      final f = _parse('neighbors swing');
      expect(f.isCustom, isFalse);
      expect(f.move, 'swing');
      expect(f.params['who'], 'neighbors');
      expect(f.note, isNull);
    });

    test('balance & swing → swing with balance prefix', () {
      final f = _parse('partners balance & swing');
      expect(f.move, 'swing');
      expect(f.params['who'], 'partners');
      expect(f.params['prefix'], 'balance');
    });

    test('long swing → 16 beats', () {
      final f = _parse('partners long swing');
      expect(f.move, 'swing');
      expect(f.params['who'], 'partners');
      expect(f.params['beats'], 16);
    });

    test('long lines forward & back → goBack true', () {
      final f = _parse('long lines forward & back');
      expect(f.move, 'long_lines');
      expect(f.params['goBack'], isTrue);
    });

    test('long lines forward → goBack false', () {
      final f = _parse('long lines forward');
      expect(f.move, 'long_lines');
      expect(f.params['goBack'], isFalse);
    });

    test('ladles chain → chain role2s', () {
      final f = _parse('ladles chain');
      expect(f.move, 'chain');
      expect(f.params['who'], 'role2s');
    });

    test('circle left 3 places', () {
      final f = _parse('circle left 3 places');
      expect(f.move, 'circle');
      expect(f.params['turn'], 'left');
      expect(f.params['places'], 3);
    });

    test('slide left along set (the canonical-core gap)', () {
      final f = _parse('slide left along set');
      expect(f.isCustom, isFalse);
      expect(f.move, 'slide_along_set');
      expect(f.params['slide'], 'left');
    });

    test('bare balance → everyone', () {
      final f = _parse('balance');
      expect(f.move, 'balance');
      expect(f.params['who'], 'everyone');
    });

    test('subject balance → that subject', () {
      final f = _parse('neighbors balance');
      expect(f.move, 'balance');
      expect(f.params['who'], 'neighbors');
    });

    test('balance the ring is its own move', () {
      final f = _parse('balance the ring');
      expect(f.move, 'balance_the_ring');
    });

    test('do si do (shoulder not rendered)', () {
      final f = _parse('neighbors do si do');
      expect(f.move, 'do_si_do');
      expect(f.params['who'], 'neighbors');
    });

    test('do si do with rotation', () {
      final f = _parse('neighbors do si do 1½');
      expect(f.move, 'do_si_do');
      expect(f.params['turn'], 1.5);
    });

    group('allemande (generic renderer: who allemande hand rotation)', () {
      test('gentlespoons allemande left once', () {
        final f = _parse('gentlespoons allemande left once');
        expect(f.move, 'allemande');
        expect(f.params['who'], 'role1s');
        expect(f.params['hand'], 'left');
        expect(f.params['turn'], 1.0);
      });

      test('next neighbors allemande right ¾', () {
        final f = _parse('next neighbors allemande right ¾');
        expect(f.move, 'allemande');
        expect(f.params['who'], 'nextNeighbors');
        expect(f.params['hand'], 'right');
        expect(f.params['turn'], 0.75);
      });
    });
  });

  group('contraDbHtmlFigureFrontEnd — note splitting (verbatim tail)', () {
    test('allemande with a trailing note keeps the figure and the note', () {
      final f = _parse('ladles allemande right 1½ - don\'t let go');
      expect(f.move, 'allemande');
      expect(f.params['who'], 'role2s');
      expect(f.params['hand'], 'right');
      expect(f.params['turn'], 1.5);
      expect(f.note, "- don't let go");
    });

    test('allemande note without a dash separator', () {
      final f = _parse('neighbors allemande left ¾ to long wavy lines');
      expect(f.move, 'allemande');
      expect(f.params['turn'], 0.75);
      expect(f.note, 'to long wavy lines');
    });

    test('a fully-consumed template has no note', () {
      final f = _parse('neighbors swing');
      expect(f.note, isNull);
    });
  });
}
