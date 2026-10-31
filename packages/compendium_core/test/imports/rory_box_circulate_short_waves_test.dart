import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// #1975: Caller's Companion's `Balance wave and slide to the right` is one
/// Rory O'More, `Wave balance, circulate` one box circulate, and `make short
/// waves` form short waves, a zero-count figure without its balance.
void main() {
  final readers = {
    'import': (String line) => parseFigureLinesFanOut(line, beats: 8),
    'free-text entry': (String line) => parseFreeTextFigureEntry('(8) $line'),
  };

  for (final MapEntry(key: path, value: read) in readers.entries) {
    group(path, () {
      Figure single(String line) {
        final figures = read(line);
        expect(figures, hasLength(1), reason: line);
        return figures.single;
      }

      test('balance and slide is one balanced Rory O\'More', () {
        // Maintainer decision 11 on #1975.
        for (final (line, slide) in [
          ('Balance wave and slide to the right', 'right'),
          ('Balance wave and slide to the left', 'left'),
          ('Balance wave of 4 and slide to the right', 'right'),
          ('Balance and slide left', 'left'),
        ]) {
          final f = single(line);
          expect(f.move, 'rory_o_more', reason: line);
          expect(f.params['balance'], isTrue, reason: line);
          expect(f.params['slide'], slide, reason: line);
          expect(f.note, isNull, reason: line);
        }
      });

      test('a bracket after it is the note', () {
        final f = single('Balance wave and slide to the left (past Shadow)');
        expect(f.move, 'rory_o_more');
        expect(f.note, 'past Shadow');
      });

      test('a role that slides keeps the line text', () {
        // Maintainer decision on #1975.
        for (final line in [
          'Balance wave and Larks slide to the right',
          'Balance wave and Robins slide to the right',
        ]) {
          expect(single(line).move, isNot('rory_o_more'), reason: line);
        }
      });

      test('wave balance and circulate is one balanced box circulate', () {
        // Maintainer decision 2 on #1975.
        for (final line in [
          'Wave balance, circulate',
          'Wave balance, box circulate',
          'Balance the wave, circulate',
        ]) {
          final f = single(line);
          expect(f.move, 'box_circulate', reason: line);
          expect(f.params['balance'], isTrue, reason: line);
        }
      });

      test('a bracket says who crosses and which way they loop', () {
        final crossed = single('Wave balance, circulate (Larks cross)');
        expect(crossed.move, 'box_circulate');
        expect(crossed.params['who'], 'role1s');
        expect(crossed.note, 'role1s cross');

        final looped = single(
          'Wave balance, circulate (Robins cross, Larks loop R)',
        );
        expect(looped.params['who'], 'role2s');
        expect(looped.params['hand'], 'right');

        // The loopers must be the other role, as in The Caller's Box, and the
        // crossers one of a pair.
        for (final line in [
          'Wave balance, circulate (Larks cross, Larks loop R)',
          'Wave balance, circulate (Neighbors cross)',
        ]) {
          expect(single(line).move, isNot('box_circulate'), reason: line);
        }
      });

      test('a balance after the circulate is not a balanced one', () {
        for (final line in [
          'Box circulate, balance the wave',
          'Circulate, wave balance',
        ]) {
          final f = single(line);
          expect(
            f.move == 'box_circulate' && f.params['balance'] == true,
            isFalse,
            reason: line,
          );
        }
      });

      test('a circulate around the set is not a box circulate', () {
        // Maintainer decision on #1975, however the count is written.
        for (final line in [
          'Wave balance, Circulate 8 (Robins L-sh circulate, '
              'Larks R-sh circulate around the set)',
          'Wave balance, Circulate (Robins L-sh circulate, '
              'Larks R-sh circulate around the set)',
        ]) {
          expect(single(line).move, isNot('box_circulate'), reason: line);
        }
      });

      test('make short waves is form short waves', () {
        // Maintainer decision on #1975: all three wordings.
        for (final line in [
          'make short waves',
          'Make short wave',
          'make wave of 4',
          'make a wave of four',
        ]) {
          final f = single(line);
          expect(f.move, 'form_short_waves', reason: line);
          expect(f.params.containsKey('balance'), isFalse, reason: line);
        }
      });

      test('other make wordings are not read', () {
        for (final line in ['make a wave', 'make diagonal wave of 4']) {
          expect(single(line).isCustom, isTrue, reason: line);
        }
      });
    });
  }

  test('a long wave is the Rory O\'More\'s note on import', () {
    // Maintainer decision on #1975.
    final f = parseFigureLinesFanOut(
      'Balance long wave and slide to the right',
      beats: 8,
    ).single;
    expect(f.move, 'rory_o_more');
    expect(f.params['balance'], isTrue);
    expect(f.note, 'long wave');
  });

  group('a closing form short waves on a Caller\'s Companion line', () {
    test('takes no beats, leaving the line to the figure before it', () async {
      // Maintainer decision on #1975: form short waves is a zero-count
      // figure without its balance.
      for (final (line, first, beats) in [
        ('(8) Circle Left 3/4, make short waves', 'circle', 8),
        ('(8) New Neighbor Do-si-do 1 1/4, make wave of 4', 'do_si_do', 8),
        (
          '(4) Robins allemande Left 3/4, make wave of 4 (RH to N)',
          'allemande',
          4,
        ),
      ]) {
        final figures = await _ccFigures(line);
        expect(figures.map((f) => f.move), [
          first,
          'form_short_waves',
        ], reason: line);
        expect(figures.first.params['beats'], beats, reason: line);
        expect(
          contraTaxonomy.effectiveParams(figures.last)['beats'],
          0,
          reason: line,
        );
      }
    });

    test('a zero-count figure before the last takes none', () async {
      // Pins the result; the split gave such a figure 0 before #1975 too, so
      // this guards the taxonomy's 0 rather than the beat sharing.
      final figures = await _ccFigures(
        '(8) make short waves, Neighbor allemande Right 1.5',
      );
      expect(figures.map((f) => f.move), ['form_short_waves', 'allemande']);
      expect(figures.first.params.containsKey('beats'), isFalse);
      expect(figures.last.params['beats'], 8);
    });
  });
}

/// The figures a Caller's Companion text export imports for one body line.
Future<List<Figure>> _ccFigures(String line) async {
  final adapter = CallersCompanionTextAdapter();
  final discovered = await adapter.discover(
    ImportRequest(payload: 'Test Dance\nType: Contra\n\nA1   $line\n'),
  );
  final draft = adapter.parse(await adapter.fetch(discovered.single));
  return switch (draft.dance.figuresSource) {
    DecodedFigures(:final figures) => figures,
    UnreadableFigures() => throw StateError('figures did not decode'),
  };
}
