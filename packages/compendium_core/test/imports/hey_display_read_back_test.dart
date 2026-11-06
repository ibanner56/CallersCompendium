import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The heys read back from the app's own display wording (#2121). The
/// round-trip ratchet covers each value alone; these pin the clauses it reads
/// and the lines that must still stay text.
void main() {
  Figure only(String line) {
    final figures = parseFreeTextFigureEntry(line);
    expect(figures, hasLength(1), reason: line);
    return figures.single;
  }

  group('hey', () {
    test('reads a direction after the hey', () {
      final f = only(
        'role2s start a half hey on right diagonal - rights in center, lefts '
        'on ends',
      );
      expect(f.params, {
        'pass1': 'role2s',
        'length': 'half',
        'where': 'rightDiagonal',
        'shoulder': 'right',
      });
      expect(f.note, isNull);
    });

    test('reads a partial length from its until clause', () {
      final first = only(
        'role2s start a hey - rights in center, lefts on ends - until someone '
        'meets',
      );
      expect(first.params['length'], 'lessThanHalf');
      expect(first.params, isNot(contains('meetTarget')));
      expect(first.note, isNull);

      final second = only(
        'role2s start a hey - rights in center, lefts on ends - until '
        'partners meet the second time',
      );
      expect(second.params['length'], 'betweenHalfAndFull');
      expect(second.params['meetTarget'], 'partners');
      expect(second.note, isNull);
    });
  });

  group('circular hey', () {
    test('no extent is the full circuit the display leaves unstated', () {
      final f = only('circular hey, neighbors pass right across');
      expect(f.move, 'circular_hey');
      expect(f.params['changes'], 4);
    });

    test('reads a displayed direction', () {
      final f = only('circular hey, neighbors pass left facing up');
      expect(f.params['where'], 'up');
      expect(f.params['shoulder'], 'left');
    });

    test('a line that leaves out more than the extent stays text', () {
      // No direction: only the extent is the display's to leave unstated.
      expect(only('circular hey, neighbors pass right').isCustom, isTrue);
    });
  });

  test('a dolphin hey reads the display\'s singular pair', () {
    final f = only(
      'dolphin hey - start with neighbor passing first role1 by right '
      'shoulders',
    );
    expect(f.move, 'dolphin_hey');
    expect(f.params['who'], 'neighbors');
  });
}
