import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// #1975, taxonomy v38: third corners and opposites are dancer sets, and the
/// corners and opposites sit below the neighbour series in the picker. The
/// figure reader names them the way the maintainer decided; both the import
/// fan-out and the editor's free-text entry read them.
void main() {
  test('the corners and opposites follow the neighbour series, in order', () {
    final sets = ParamVocab.pairDancerSets;
    final after = sets.indexOf('fourthNeighbors') + 1;
    expect(sets.sublist(after, after + 4), [
      'firstCorners',
      'secondCorners',
      'thirdCorners',
      'opposites',
    ]);
  });

  final readers = {
    'import': (String line) => parseFigureLinesFanOut(line, beats: 8),
    'free-text entry': (String line) => parseFreeTextFigureEntry(line),
  };

  for (final MapEntry(key: path, value: read) in readers.entries) {
    group(path, () {
      void expectWho(String line, String move, String who) {
        final figures = read(line);
        expect(figures, hasLength(1), reason: line);
        expect(figures.single.move, move, reason: line);
        expect(figures.single.params['who'], who, reason: line);
      }

      test('"third corner" is the third corners', () {
        expectWho('Third corner swing', 'swing', 'thirdCorners');
        expectWho('3rd corner allemande left', 'allemande', 'thirdCorners');
      });

      test('Corner 1, 2 and 3 are The Caller\'s Box C1, C2 and C3', () {
        expectWho('Corner 1 allemande Left 1.5', 'allemande', 'firstCorners');
        expectWho('Corner 2 swing', 'swing', 'opposites');
        expectWho('Corner 3 swing', 'swing', 'thirdCorners');
        expect(
          read('Corner 1 allemande Left 1.5').single.params['travel'],
          1.5,
        );
        // Any other number after a corner names no dancer set.
        expect(read('Corner 5 swing').single.isCustom, isTrue);
      });

      test('a mixed number after a corner is still the amount', () {
        for (final line in [
          'Allemande left corner 1 1/2',
          'Allemande left corner 1½',
        ]) {
          final f = read(line).single;
          expect(f.params['who'], 'firstCorners', reason: line);
          expect(f.params['travel'], 1.5, reason: line);
        }
      });

      test('opposites roll away is a roll away with them', () {
        final f = read('Opposite roll away').single;
        expect(f.move, 'roll_away');
        expect(f.params['whom'], 'opposites');
      });

      test('"opposite" is the opposites', () {
        expectWho('Opposite balance and swing', 'swing', 'opposites');
        expectWho('Opposites swing', 'swing', 'opposites');
      });

      // A non-regression pin, not a test of the guard alone: today the
      // described word is never read, so each line stays text even without
      // `_oppositeDescribes`.
      test('"opposite" describing a role, side, direction, way or hand is not '
          'a dancer', () {
        for (final line in [
          'Straight across, opposite role pull by L, face in',
          'opposite side swing',
          'swing, face the opposite direction',
          'turn the opposite way',
          'opposite hand allemande',
        ]) {
          expect(
            read(line).map((f) => f.params['who']),
            isNot(contains('opposites')),
            reason: line,
          );
        }
      });
    });
  }

  group('The Caller\'s Box side runs and waves', () {
    Figure? tcb(String line) =>
        parseFigureLine(line, beats: 4, frontEnd: tcbFigureFrontEnd);

    test('a side run names the corner sets', () {
      final f = tcb('Cross trails (C1R;C2L)')!;
      expect(f.params['who'], 'firstCorners');
      expect(f.params['who2'], 'opposites');
    });

    test('a corner a slot cannot hold is not approximated', () {
      // `form_long_waves.who` is an invertible pair; opposites are not one,
      // so the run declines and the defaults stay, as before v38.
      for (final line in ['Form long waves (C2R)', 'Form long waves (C3L)']) {
        final f = tcb(line)!;
        expect(f.move, 'form_long_waves', reason: line);
        expect(f.params.containsKey('who'), isFalse, reason: line);
      }
    });
  });
}
