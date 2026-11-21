import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// #1975: Caller's Companion's "Half Hey, Robins start right shoulder" names
/// the hey's length, the pair that starts and the first shoulder. Both the
/// import fan-out and the editor's free-text entry read it.
void main() {
  final readers = {
    'import': (String line) => parseFigureLinesFanOut(line, beats: 8),
    'free-text entry': (String line) => parseFreeTextFigureEntry(line),
  };

  for (final MapEntry(key: path, value: read) in readers.entries) {
    group(path, () {
      Figure hey(String line) {
        final figures = read(line);
        expect(figures, hasLength(1), reason: line);
        expect(figures.single.move, 'hey', reason: line);
        return figures.single;
      }

      void expectHey(String line, Map<String, Object?> params, {String? note}) {
        final f = hey(line);
        for (final e in params.entries) {
          expect(f.params[e.key], e.value, reason: '$line: ${e.key}');
        }
        expect(f.note, note, reason: line);
      }

      void expectCustom(String line) {
        expect(read(line).single.isCustom, isTrue, reason: line);
      }

      test('the starting pair, the shoulder and the length', () {
        expectHey('Half Hey, Robins start right shoulder', {
          'pass1': 'role2s',
          'shoulder': 'right',
          'length': 'half',
        });
        expectHey('Full Hey, Partner start left shoulders', {
          'pass1': 'partners',
          'shoulder': 'left',
          'length': 'full',
        });
        expectHey('1/2 Hey, Neighbor start Right shoulder', {
          'pass1': 'neighbors',
          'length': 'half',
        });
      });

      test('a quarter and three-quarter hey are the partial lengths', () {
        expectHey('1/4 Hey, Robins start right shoulder', {
          'length': 'lessThanHalf',
        });
        expectHey('3/4 Hey - Neighbor start Right shoulder', {
          'length': 'betweenHalfAndFull',
          'pass1': 'neighbors',
        });
      });

      test('a bracketed pass list is kept as the note', () {
        expectHey('1/4 Hey, Partner start Right shoulder (PR, Larks L)', {
          'length': 'lessThanHalf',
          'pass1': 'partners',
        }, note: 'PR, role1s L');
      });

      test('a leading diagonal is where, not the shoulder', () {
        expectHey('Left diagonal Half Hey, Robins start right shoulder', {
          'where': 'leftDiagonal',
          'shoulder': 'right',
        });
        expectHey('Right diagonal Full Hey, Larks start left shoulder', {
          'where': 'rightDiagonal',
          'shoulder': 'left',
        });
      });

      test('a ricochet on a half hey is the ricochetting role\'s slot', () {
        expectHey('Half Hey, Larks start left shoulder, Robins ricochet', {
          'pass1': 'role1s',
          'rico1': null,
          'rico2': true,
        });
        expectHey('Half Hey, Larks start left shoulder, Larks ricochet', {
          'rico1': true,
          'rico2': null,
        });
      });

      test('any other ricochet stays custom', () {
        expectCustom('Full Hey, Larks start left shoulder, Robins ricochet');
        expectCustom('Half Hey, Partner start left shoulder, Robins ricochet');
        expectCustom('Half Hey, Larks start left shoulder, Neighbor ricochet');
      });

      test('"start" wording without a length stays custom', () {
        // The half-hey default could contradict the line's beats.
        expectCustom('Hey, Robins start right shoulder');
        expectCustom('Hey - Robins start right shoulder');
      });

      test('"starts" reads as "start"', () {
        expectHey('Full Hey, Neighbor starts Right shoulder', {
          'pass1': 'neighbors',
          'length': 'full',
        });
      });

      test('a different figure named after a hey stays custom', () {
        expectCustom(
          'Half Hey w/ Hands (Dixie Grand), Partner start R-hand pull by',
        );
      });

      test('the older "start by" phrasing still reads', () {
        expectHey('half hey, ladies start by the right', {
          'pass1': 'role2s',
          'shoulder': 'right',
        });
      });
    });
  }
}
