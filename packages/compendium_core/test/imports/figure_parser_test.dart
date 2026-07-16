import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The custom-figure text (`customFigure` stores it in `params['text']`).
String _text(Figure f) => f.params['text'] as String;

void main() {
  group('parseFigureLine — parse-never-fails', () {
    test('empty / whitespace-only input returns null (nothing to store)', () {
      expect(parseFigureLine(''), isNull);
      expect(parseFigureLine('   '), isNull);
      expect(parseFigureLine('\t\n '), isNull);
    });

    test('never throws on bizarre input — degrades to custom', () {
      for (final line in <String>[
        '!!!',
        '(((',
        '123 456',
        'a b c d e f g',
        'balance & swing & balance & swing forever',
      ]) {
        final f = parseFigureLine(line);
        expect(f, isNotNull, reason: line);
        expect(f!.isCustom, isTrue, reason: line);
      }
    });
  });

  group('parseFigureLine — structured recognition (real fixture lines)', () {
    // Anchored to real scrubbed figure lines drawn from the CallersBox id=1
    // record, the ContraDB "The Rendezvous" page, and the CC text fixtures.
    final cases = <String, ({String move, Map<String, Object?> params})>{
      // CallersBox id=1 "The Nice Combination".
      'Neighbor balance': (move: 'balance', params: {'who': 'neighbors'}),
      'Neighbor swing': (move: 'swing', params: {'who': 'neighbors'}),
      'Partner swing': (move: 'swing', params: {'who': 'partners'}),
      'Circle left 3/4': (
        move: 'circle',
        params: {'turn': 'left', 'places': 3},
      ),
      'Star left 1': (move: 'star', params: {'hand': 'left', 'places': 4}),
      // ContraDB "The Rendezvous".
      'neighbors balance & swing': (
        move: 'swing',
        params: {'who': 'neighbors', 'prefix': 'balance'},
      ),
      'long lines forward & back': (move: 'long_lines', params: {}),
      'circle left 4 places': (
        move: 'circle',
        params: {'turn': 'left', 'places': 4},
      ),
      // CC text "Simplicity Swing".
      'Partner balance and swing': (
        move: 'swing',
        params: {'who': 'partners', 'prefix': 'balance'},
      ),
      'Ladies chain': (move: 'chain', params: {'who': 'role2s'}),
      // Other covered moves.
      'Balance the ring': (move: 'balance_the_ring', params: {}),
      'Petronella': (move: 'petronella', params: {}),
      'Right left through': (move: 'right_left_through', params: {}),
      'Pass through': (move: 'pass_through', params: {}),
      'Promenade': (move: 'promenade', params: {}),
      'Box the gnat': (move: 'box_the_gnat', params: {'who': 'partners'}),
      'Swat the flea': (move: 'swat_the_flea', params: {'who': 'partners'}),
      'Meltdown swing': (
        move: 'swing',
        params: {'who': 'partners', 'prefix': 'meltdown'},
      ),
      'See saw neighbor': (move: 'see_saw', params: {'who': 'neighbors'}),
      'Do si do neighbor once': (
        move: 'do_si_do',
        params: {'who': 'neighbors', 'turn': 1.0},
      ),
      'Gents allemande left': (
        move: 'allemande',
        params: {'who': 'role1s', 'hand': 'left'},
      ),
    };

    cases.forEach((line, expected) {
      test('"$line" → ${expected.move}', () {
        final f = parseFigureLine(line);
        expect(f, isNotNull, reason: line);
        expect(f!.isCustom, isFalse, reason: line);
        expect(f.move, expected.move, reason: line);
        expected.params.forEach((k, v) {
          expect(f.params[k], v, reason: '$line param $k');
        });
      });
    });

    test('the default scrub runs before recognition (gypsy → shoulder '
        'round)', () {
      final f = parseFigureLine('gypsy your partner');
      expect(f!.move, 'shoulder_round');
      expect(f.params['who'], 'partners');
    });

    test('the default scrub canonicalises gendered role terms', () {
      // "Ladies chain" scrubs to "role2s chain" before the chain recogniser.
      final f = parseFigureLine('Ladies chain');
      expect(f!.move, 'chain');
      expect(f.params['who'], 'role2s');
    });
  });

  group('parseFigureLine — conservative fallback (must stay custom)', () {
    // A wrong structured match misrepresents choreography, so anything the
    // parser cannot fully account for degrades to an honest custom figure.
    const mustStayCustom = <String>[
      // Multiple distinct moves on one line — not split this PR.
      'circle left 3/4, pass through',
      'balance and swing, then circle left',
      // "or" alternatives / conditional prose.
      'ladles do si do 1½ or swing to partner',
      // "chain" with an explicit dancer set outside its role1s/role2s domain
      // must not be silently coerced to the default — it stays custom.
      'partners chain',
      'neighbors chain across',
      // Trailing prose the recogniser cannot consume.
      'chain to neighbor',
      'swing to partner',
      // Moves outside the first-cut coverage.
      'hey for four',
      'down the hall four in line',
      'poussette clockwise',
      'contra corners',
      'square through four',
    ];

    for (final line in mustStayCustom) {
      test('"$line" stays custom', () {
        final f = parseFigureLine(line);
        expect(f, isNotNull, reason: line);
        expect(f!.isCustom, isTrue, reason: line);
      });
    }
  });

  group('parseFigureLine — preservation', () {
    test('source beats are preserved on a structured figure', () {
      final f = parseFigureLine('Neighbor swing', beats: 12);
      expect(f!.move, 'swing');
      expect(f.params['beats'], 12);
    });

    test('non-positive beats are omitted (taxonomy defaults apply later)', () {
      expect(
        parseFigureLine('Neighbor swing', beats: 0)!.params['beats'],
        isNull,
      );
      expect(
        parseFigureLine('Neighbor swing', beats: -4)!.params['beats'],
        isNull,
      );
    });

    test('the progression flag is preserved on structured + custom', () {
      expect(
        parseFigureLine('Neighbor swing', progression: true)!.progression,
        isTrue,
      );
      expect(
        parseFigureLine('hey for four', progression: true)!.progression,
        isTrue,
      );
    });

    test('the section label is applied only on the custom fallback', () {
      // Structured: no in-text label (section derives from beats downstream).
      final structured = parseFigureLine('Neighbor swing', label: 'A1');
      expect(structured!.isCustom, isFalse);
      expect(structured.params.containsKey('text'), isFalse);
      // Custom: the label is prefixed exactly as the adapters did before.
      final custom = parseFigureLine('hey for four', label: 'B2');
      expect(custom!.isCustom, isTrue);
      expect(_text(custom), 'B2: hey for four');
    });

    test('a null/empty label leaves the custom text unprefixed', () {
      expect(_text(parseFigureLine('hey for four')!), 'hey for four');
      expect(
        _text(parseFigureLine('hey for four', label: '')!),
        'hey for four',
      );
    });
  });

  group('parseFigureLine — validation safety net', () {
    test(
      'a structured candidate the taxonomy rejects falls back to custom',
      () {
        // An empty taxonomy makes every recognised move an unknown-move error,
        // so the validated candidate is discarded in favour of custom.
        final empty = Taxonomy(
          version: 1,
          form: DanceForm.contra,
          moves: const [],
        );
        final f = parseFigureLine('Neighbor swing', beats: 8, taxonomy: empty);
        expect(f!.isCustom, isTrue);
        expect(_text(f), 'Neighbor swing');
        expect(f.params['beats'], 8);
      },
    );
  });
}
