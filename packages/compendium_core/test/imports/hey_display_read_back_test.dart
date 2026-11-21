import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// The heys read back from the app's own display wording (#2121). The
/// round-trip ratchet covers each value alone; these pin the clauses it reads
/// and the lines that must still stay text.
void main() {
  final renderer = FigureRenderer(contraTaxonomy);
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

  test('every dancer that starts a hey keeps its ricochets on read-back', () {
    // The renderer names the other pair by [invertPairDancerSet], falling back
    // to "others" for a dancer no pair inverts (`partners`, `neighbors`, a
    // single dancer, `threes` …), so the reader has to accept the same. Every
    // combination of the ricochets a length can reach, so a clause that stops
    // the next one from reading is caught too.
    const reachable = {
      'lessThanHalf': [1],
      'half': [1, 2],
      'betweenHalfAndFull': [1, 2, 3],
      'full': [1, 2, 3, 4],
    };
    final failures = <String>[];
    for (final dialect in Dialect.presets) {
      for (final pass1 in ParamVocab.dancerSets) {
        for (final MapEntry(key: length, value: slots) in reachable.entries) {
          for (var mask = 1; mask < 1 << slots.length; mask++) {
            final figure = testFigure(
              move: 'hey',
              params: {
                'pass1': pass1,
                'length': length,
                for (var b = 0; b < slots.length; b++)
                  if (mask & (1 << b) != 0) 'rico${slots[b]}': true,
              },
            );
            final text = renderer.renderSummary(figure, dialect);
            final read = parseFreeTextFigureEntry(text, dialect: dialect);
            if (read.length != 1 ||
                read.single.params['pass1'] != pass1 ||
                read.single.note != null ||
                renderer.renderSummary(read.single, dialect) != text) {
              failures.add('${dialect.name}: $text');
            }
          }
        }
      }
    }
    expect(
      failures,
      isEmpty,
      reason:
          '${failures.length} lines lost a ricochet:\n${failures.join('\n')}',
    );
  });

  test('an until clause naming a pair the hey cannot meet stays a note', () {
    final f = only(
      'role2s start a hey - rights in center, lefts on ends - until everyone '
      'meet',
    );
    expect(f.move, 'hey');
    expect(f.params, isNot(contains('meetTarget')));
    expect(f.note, '- until everyone meet');
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

    test('the direction is still read after a filler or a second pass', () {
      for (final line in [
        '3/4 circular hey, the neighbors pass right across',
        '3/4 circular hey, neighbors pass right, partners pass left across',
      ]) {
        final f = only(line);
        expect(f.move, 'circular_hey', reason: line);
        expect(f.params['where'], 'across', reason: line);
      }
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
