import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The gate and the courtesy turn read back from the app's own display
/// wording (#2121), and the lines the import readers already decide keep
/// their reading.
void main() {
  Figure typed(String line) {
    final figures = parseFreeTextFigureEntry(line);
    expect(figures, hasLength(1), reason: line);
    return figures.single;
  }

  Figure imported(String line) {
    final figures = parseFigureLinesFanOut(line);
    expect(figures, hasLength(1), reason: line);
    return figures.single;
  }

  group('gate', () {
    test('reads each displayed slot', () {
      expect(typed('gate counterclockwise').params, {
        'direction': 'counterclockwise',
      });
      expect(typed('gate to face up the hall').params, {'endFacing': 'up'});
      expect(typed('gate, role1s forward').params, {'whom': 'role1s'});
      expect(typed('neighbor gate, role1s forward').params, {
        'pair': 'neighbors',
        'whom': 'role1s',
      });
      expect(typed('ones gate neighbors to face into the set').params, {
        'who': 'ones',
        'whom': 'neighbors',
        'endFacing': 'in',
      });
      expect(typed('neighbor mirror gate ¾').params, {
        'pair': 'neighbors',
        'direction': 'mirror',
        'travel': 0.75,
      });
    });

    test('the forward clause comes before the facing, as displayed', () {
      expect(typed('gate, ones forward to face up the hall').params, {
        'whom': 'ones',
        'endFacing': 'up',
      });
      expect(
        typed(
          'neighbor gate clockwise ¾, ones forward to face up the hall',
        ).params,
        {
          'pair': 'neighbors',
          'direction': 'clockwise',
          'travel': 0.75,
          'whom': 'ones',
          'endFacing': 'up',
        },
      );
    });

    test('a subject the display names reads by name', () {
      expect(typed('third corners gate').params, {'who': 'thirdCorners'});
      expect(typed('same roles gate').params, {'who': 'sameRoles'});
    });

    test('an import keeps a gate that states too little as text', () {
      for (final line in [
        'gate',
        'Partner gate',
        'Partner gate counterclockwise',
        'Partner gate 3/4',
      ]) {
        expect(imported(line).isCustom, isTrue, reason: line);
      }
    });
  });

  group('courtesy turn', () {
    test('reads the displayed ending facing', () {
      final f = typed('partner courtesy turn clockwise to face second shadow');
      expect(f.move, 'courtesy_turn');
      expect(f.params, {
        'who': 'partners',
        'direction': 'clockwise',
        'endFacing': 'secondShadows',
      });
    });

    test('free text reads a second dancer as whom; an import does not', () {
      // The maintainer's decision (2026-11-06, recorded in #2121's Status):
      // the display's own wording reads back, and an import still leaves
      // `whom` out unless a source states it.
      expect(typed('partner courtesy turn role1s clockwise').params, {
        'who': 'partners',
        'whom': 'role1s',
        'direction': 'clockwise',
      });
      expect(
        typed(
          'partner courtesy turn third corners to face second shadow',
        ).params,
        {
          'who': 'partners',
          'whom': 'thirdCorners',
          'endFacing': 'secondShadows',
        },
      );
      expect(imported('partner courtesy turn role1s').isCustom, isTrue);
      expect(imported('ones courtesy turn twos').isCustom, isTrue);
    });
  });
}
