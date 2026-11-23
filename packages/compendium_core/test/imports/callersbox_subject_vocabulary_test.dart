import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../figures_support.dart';

/// The Caller's Box subject vocabulary: same-role neighbors and the S-prefix
/// shadow codes.
///
/// Maintainer rulings these pin:
/// - "Same-role neighbor" (and the older "same-sex neighbor") names the
///   taxonomy's `sameRoles` set.
/// - `S-1` is the bare shadow; `S1` is the bare shadow (glossary); `S2` is
///   `secondShadows`. `S3`+, `S-2`, … have no token and stay custom.
///
/// Every line below is a verbatim corpus wording unless marked otherwise.
void main() {
  Figure parse(String line) =>
      parseFigureLine(line, frontEnd: tcbFigureFrontEnd)!;

  group('same-role neighbor → sameRoles', () {
    const cases = <String, String>{
      'Same-role neighbor allemande left 1 & 1/2': 'allemande',
      'Same-role neighbor allemande left 1': 'allemande',
      'Same-role neighbor do-si-do': 'do_si_do',
      'Same-role neighbor swing': 'swing',
      'Same-role neighbor balance': 'balance',
      '[Twos and threes] Same-role neighbor seesaw': 'see_saw',
    };
    cases.forEach((line, move) {
      test('"$line" structures as $move(who: sameRoles)', () {
        final f = parse(line);
        expect(f.isCustom, isFalse, reason: f.params['text']?.toString());
        expect(f.move, move);
        expect(f.params['who'], 'sameRoles');
      });
    });

    test('allemande keeps its hand and turn amount', () {
      final f = parse('Same-role neighbor allemande left 1 & 1/2');
      expect(f.params['hand'], 'left');
      expect(f.params['travel'], 1.5);
    });

    test('"same-sex neighbor" is the same pairing (not corpus wording)', () {
      final f = parse('Same-sex neighbor swing');
      expect(f.move, 'swing');
      expect(f.params['who'], 'sameRoles');
    });

    test('a [who] bracket survives as the note', () {
      final f = parse(
        'Same-role neighbor allemande left 1 [M with N1, W with N2]',
      );
      expect(f.params['who'], 'sameRoles');
      expect(f.note, 'M with N1, W with N2');
    });

    test('the qualifier alone is not a dancer set', () {
      expect(parse('Same-role person swing').isCustom, isTrue);
    });

    test(
      'an N-prefixed same-role neighbor stays custom (no ordinal token)',
      () {
        final f = parse('N2 same-role neighbor do-si-do');
        expect(f.isCustom, isTrue);
        expect(f.params['text'], contains('N2 same-role neighbor'));
      },
    );

    test('right and left through still carries same-role as a note', () {
      // right_left_through has no who slot; the variant stays a note.
      final f = parse('Same-role right and left through with neighbor');
      expect(f.move, 'right_left_through');
      expect(f.note, 'same-role');
      expect(f.params.containsKey('who'), isFalse);
    });
  });

  group('a per-role turn amount keeps the line custom', () {
    // No move models a per-role amount; structuring would render the
    // allemande's default travel (1½), which neither role dances.
    for (final line in const [
      'Same-role neighbor allemande left (M 1 & 1/2, W 2)',
      'Same-role neighbor allemande left (M 1 & 1/4, W 1 & 3/4)',
      'Same-role neighbor left shoulder round [M with N2, W with N1] '
          '(M 1, W 1 & 1/2)',
      // Not corpus wording: the veto is not subject-specific.
      'Neighbor allemande left (W 2, M 1 & 1/2)',
    ]) {
      test('"$line" stays custom with its text intact', () {
        final f = parse(line);
        expect(f.isCustom, isTrue);
        expect(f.params['text'], contains('M 1'));
      });
    }
  });

  group('an amount alternative takes the first amount (#2331)', () {
    // `(1 or 2)` offers two amounts and either is correct. Maintainer ruling
    // (2026-11-23): the figure takes the first, and the parenthetical stays as
    // the note, so the line says the other also works. Before, the amount fell
    // back to the allemande's default 1½, which the line never offers.
    const cases = <String, (String, num, String)>{
      // Corpus wording (dances 14635, 12070/12071, 3417, 5031).
      'Men allemande right (1 or 2)': ('role1s', 1, '1 or 2'),
      'Neighbor allemande right (1 or 2)': ('neighbors', 1, '1 or 2'),
      'Ones allemande right (1/2 or 1 & 1/2)': ('ones', 0.5, '1/2 or 1 & 1/2'),
      'Partner allemande right (1 or 1 & 1/2, until men face down)': (
        'partners',
        1,
        '1 or 1 & 1/2, until role1s face down',
      ),
      // Not corpus wording: the first amount is a mixed number.
      'Neighbor allemande left (1 & 1/2 or 2)': (
        'neighbors',
        1.5,
        '1 & 1/2 or 2',
      ),
    };
    cases.forEach((line, expected) {
      final (who, travel, note) = expected;
      test('"$line" takes $travel with the choice as the note', () {
        final f = parse(line);
        expect(f.move, 'allemande');
        expect(f.params['who'], who);
        expect(f.params['travel'], travel);
        expect(f.note, note);
      });
    });

    test('a two-hand turn takes the amount too (not corpus wording)', () {
      final f = parse('Partner two-hand turn (1 or 2)');
      expect(f.move, 'two_hand_turn');
      expect(f.params['travel'], 1);
      expect(f.note, '1 or 2');
    });

    for (final line in const [
      // Not corpus wording: a stated amount beside the alternative.
      'Neighbor allemande left 1 (1 or 2)',
      // Corpus wording (dance 10156's right side): a promenade has no amount.
      'C1 corner promenade counterclockwise (3/8 or 5/8)',
      // Not corpus wording: two choices on one line.
      'Neighbor allemande left (1 or 2) (1/2 or 1)',
    ]) {
      test('"$line" has no place for the amount, so stays custom', () {
        final f = parse(line);
        expect(f.isCustom, isTrue);
        expect(f.params['text'], contains(' or '));
      });
    }

    test(
      'through the importer: dance 14635 A2 takes the first amount',
      () async {
        final payload = jsonEncode({
          'ID': '14635',
          'Name': 'Composition 90',
          'Permission': 'full',
          'phrases': [
            {
              'name': 'A2',
              'figures': [
                '(8) Men do a right-hand ladies chain to partner',
                '(8) Men allemande right (1 or 2)',
              ],
            },
          ],
        });
        final adapter = CallersBoxAdapter();
        final discovered = await adapter.discover(
          ImportRequest(payload: payload),
        );
        final raw = await adapter.fetch(discovered.single);
        final figures = figuresOf(adapter.parse(raw).dance);
        expect(figures.last.move, 'allemande');
        expect(figures.last.params['travel'], 1);
        expect(figures.last.note, '1 or 2');
        expect(figures.fold<int>(0, (a, f) => a + f.beats), 16);
      },
    );

    test('a ;-compound holding one structures both clauses, either order', () {
      for (final line in const [
        'Circle right 3/4; Men allemande right (1 or 2)',
        'Men allemande right (1 or 2); face out',
      ]) {
        final figures = parseFigureLines(
          line,
          beats: 8,
          frontEnd: tcbFigureFrontEnd,
        );
        final allemande = figures.firstWhere(
          (f) => f.move == 'allemande',
          orElse: () => fail('$line: ${figures.map((f) => f.move)}'),
        );
        expect(allemande.params['travel'], 1, reason: line);
        // `face out` is one of the clauses TCB keeps as a note.
        expect(allemande.note, startsWith('1 or 2'), reason: line);
      }
    });

    test('typed text takes the first amount too', () {
      // Free-text entry fans out across the readers. ContraDB's reading keeps
      // `(1 or 2)` as its note and takes no amount, so it is not picked.
      for (final line in const [
        'Men allemande right (1 or 2)',
        'Neighbor allemande right (1 or 2)',
      ]) {
        final f = parseFreeTextFigureEntry(line).single;
        expect(f.move, 'allemande', reason: line);
        expect(f.params['travel'], 1, reason: line);
        expect(f.note, '1 or 2', reason: line);
      }
    });
  });

  group('an "or" annotation that is not an amount alternative', () {
    // Controls for the amount-alternative reading (#2331): an annotation that
    // merely contains "or" structures as before, with the words as its note.
    test('"Neighbor allemande right (or LLFB)" structures', () {
      final f = parse('Neighbor allemande right (or LLFB)');
      expect(f.move, 'allemande');
      expect(f.note, 'or LLFB');
    });
  });

  group('S-prefix shadow codes', () {
    const cases = <String, String>{
      'S-1 shadow allemande left 1': 'shadows',
      'S1 shadow allemande left 1': 'shadows',
      'S1 shadow pull by right': 'shadows',
      'S2 shadow swing': 'secondShadows',
      'S2 shadow do-si-do': 'secondShadows',
    };
    cases.forEach((line, who) {
      test('"$line" → who: $who', () {
        final f = parse(line);
        expect(f.isCustom, isFalse, reason: f.params['text']?.toString());
        expect(f.params['who'], who);
      });
    });

    for (final line in const [
      'S3 shadow allemande left 1',
      'S4 shadow swing',
      'S-2 shadow allemande left 1',
    ]) {
      test('"$line" has no token and stays custom', () {
        expect(parse(line).isCustom, isTrue);
      });
    }
  });

  test('N3 neighbor is the third neighbor', () {
    expect(
      parse('N3 neighbor allemande right 1').params['who'],
      'thirdNeighbors',
    );
  });
}
