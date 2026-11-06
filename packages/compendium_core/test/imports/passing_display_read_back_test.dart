import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The passing moves read back from the app's own display wording (#2121): a
/// direction after the move, a pair in the singular, the cross trails
/// shoulder clauses and the slice clauses.
void main() {
  Figure only(String line) {
    final figures = parseFreeTextFigureEntry(line);
    expect(figures, hasLength(1), reason: line);
    return figures.single;
  }

  test('a displayed direction after the move is read, not left as a note', () {
    for (final (line, move) in [
      ('pass through on right diagonal', 'pass_through'),
      ('right left through facing up', 'right_left_through'),
      ('role2s chain on left diagonal', 'chain'),
      ('pull by right facing in', 'pull_by'),
    ]) {
      final f = only(line);
      expect(f.move, move, reason: line);
      expect(f.params['where'], isNotNull, reason: line);
      expect(f.note, isNull, reason: line);
    }
  });

  test('a pass by reads the display\'s singular pair with its shoulder', () {
    expect(only('neighbor pass by left shoulders').params, {
      'who': 'neighbors',
      'shoulder': 'left',
    });
    // Without the shoulder the display always writes, an import keeps the
    // line as text, as before.
    expect(parseFigureLinesFanOut('neighbor pass by').single.isCustom, isTrue);
  });

  group('cross trails', () {
    test('reads both pairs, the direction and the shoulder', () {
      final f = only(
        'cross trails - third corners on right diagonal passing left '
        'shoulders, shadow passing right shoulders',
      );
      expect(f.params, {
        'who': 'thirdCorners',
        'where': 'rightDiagonal',
        'shoulder': 'left',
        'who2': 'shadows',
      });
      expect(f.note, isNull);
    });

    test('a second pass by the same shoulder is not read', () {
      final f = only(
        'cross trails - partner across the set passing right shoulders, '
        'neighbor along the set passing right shoulders',
      );
      expect(f.isCustom, isTrue);
    });
  });

  group('slice', () {
    test('reads the increment and the return', () {
      expect(only('slice right one dancer and diagonal back').params, {
        'slice': 'right',
        'by': 'dancer',
        'return': 'diagonal',
      });
    });

    test('a bare slice is not read as returning nowhere', () {
      // Whether ContraDB means `none` by a bare slice is not established.
      expect(only('slice left').params, {'slice': 'left'});
    });
  });
}
