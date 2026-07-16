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
      'swing to partner',
      // Moves outside the first-cut coverage.
      'hey for four',
      'down the hall four in line',
      'contra corners',
      // "square through" spelled out (TCB uses a digit count) stays custom.
      'square through four',
      // gate: SKIPPED this PR — every attested TCB gate carries a
      // clockwise/counterclockwise/mirror qualifier + fraction the taxonomy's
      // face (up/down/in/out) param cannot represent (dance id 519).
      'N2 neighbor gate counterclockwise 1/2',
      // A poussette with an unmappable leftover ("draw") stays custom.
      'Neighbor draw poussette clockwise 1/2',
      // Partial long-lines descriptors are not the canonical "forward and
      // back", so they degrade to custom rather than a half-described figure.
      'long lines back',
      'long lines forward',
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

    test(
      'negative beats never break the custom fallback (parse-never-fails)',
      () {
        // `customFigure` throws on a negative beat count, so a malformed source
        // beat must not propagate through the fallback path.
        final f = parseFigureLine('hey for four', beats: -8);
        expect(f, isNotNull);
        expect(f!.isCustom, isTrue);
        expect(_text(f), 'hey for four');
        expect(f.params['beats'], isNull);
      },
    );

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

    test('section labels are never embedded in the figure text', () {
      // Structured: no in-text label (section derives from beats downstream).
      final structured = parseFigureLine('Neighbor swing');
      expect(structured!.isCustom, isFalse);
      expect(structured.params.containsKey('text'), isFalse);
      // Custom: clean scrubbed text only — no `A1:`/`B2:` prefix. The section
      // label and beats are structured fields on the figure; embedding them in
      // the text would duplicate structured data that can drift out of sync.
      final custom = parseFigureLine('hey for four');
      expect(custom!.isCustom, isTrue);
      expect(_text(custom), 'hey for four');
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

  group('parseFigureLine — TCB dialect/formatting normalization', () {
    // Each case cites The Caller's Box (TCB) formatting the existing
    // recognizers previously missed. Structured expectations only.
    final cases = <String, ({String move, Map<String, Object?> params})>{
      // 1. "1 & 1/2" rotation (TCB dance ids 952, 2370, 133 —
      //    "Men allemande left 1 & 1/2"). `&`→"and", bridged to 1.5.
      'Men allemande left 1 & 1/2': (
        move: 'allemande',
        params: {'who': 'role1s', 'hand': 'left', 'turn': 1.5},
      ),
      'Allemande right 1 and 1/4': (
        move: 'allemande',
        params: {'hand': 'right', 'turn': 1.25},
      ),
      // 2. Parenthetical annotations stripped for recognition (TCB appends
      //    "(NR)"/"(PR)" to pass through exclusively).
      'Pass through (NR)': (move: 'pass_through', params: {}),
      // 3. N-prefix dancer mapping (Tier B): "N2 neighbor" → nextNeighbors.
      'N2 neighbor allemande right': (
        move: 'allemande',
        params: {'who': 'nextNeighbors', 'hand': 'right'},
      ),
      'N1 balance': (move: 'balance', params: {'who': 'neighbors'}),
      // 4. shadow → shadows (Tier B).
      'Shadow allemande left': (
        move: 'allemande',
        params: {'who': 'shadows', 'hand': 'left'},
      ),
      // 5. Leading "In" in long lines (TCB writes this exclusively).
      'In long lines, go forward and back': (move: 'long_lines', params: {}),
      // 6. "balance ring" without "the" (TCB).
      'Balance ring': (move: 'balance_the_ring', params: {}),
      // 7. Promenade direction (recognizer previously never consumed it).
      'Promenade across': (move: 'promenade', params: {'dir': 'across'}),
      // 8. right-left-through "with X" (TCB writes this exclusively).
      'Right and left through with partner': (
        move: 'right_left_through',
        params: {},
      ),
      // 10. hands-across star grip (TCB: "Hands-across star right").
      'Hands-across star right': (
        move: 'star',
        params: {'hand': 'right', 'grip': 'handsAcross'},
      ),
      // 11. shift → slide_along_set (Tier B).
      'Shift left': (move: 'slide_along_set', params: {'slide': 'left'}),
      'Shift right': (move: 'slide_along_set', params: {'slide': 'right'}),
      // --- Tier A: recognizers for existing moves TCB writes in missed forms.
      // 12. slice (TCB "Slice left" — dance id 1860 "Power Surge").
      'Slice left': (move: 'slice', params: {'slice': 'left'}),
      'Slice right': (move: 'slice', params: {'slice': 'right'}),
      // 13. turn_alone (TCB "Turn alone" id 25; "Ones turn alone" id 2).
      'Turn alone': (move: 'turn_alone', params: {}),
      'Ones turn alone': (move: 'turn_alone', params: {'who': 'ones'}),
      // 14. poussette (TCB "Partner poussette clockwise 1/2" — id 488
      //     "Rough Ride").
      'Partner poussette clockwise 1/2': (
        move: 'poussette',
        params: {'who': 'partners', 'turn': 'clockwise', 'half': 'half'},
      ),
      // 15. california_twirl (TCB "Partner California twirl" — id 11
      //     "Hocus Pocus").
      'Partner California twirl': (
        move: 'california_twirl',
        params: {'who': 'partners'},
      ),
      // 16. star_promenade (TCB "Partner star promenade 1/2" — id 30
      //     "Mad Gypsy"). Must beat the bare _star/_promenade recognizers.
      'Partner star promenade 1/2': (
        move: 'star_promenade',
        params: {'who': 'partners', 'turn': 0.5},
      ),
      // 17. square_through (TCB "Square through 3" — id 322 "Whim's Gym").
      'Square through 3': (move: 'square_through', params: {'places': 3}),
      'Square through 4': (move: 'square_through', params: {'places': 4}),
      // 18. pull_by dancer form → pull_by_dancers (TCB "Men pull by left"
      //     id 481 "Hard Cider Boys"; "Partner pull by left" id 467).
      'Men pull by left': (
        move: 'pull_by_dancers',
        params: {'who': 'role1s', 'hand': 'left'},
      ),
      'Partner pull by left': (
        move: 'pull_by_dancers',
        params: {'who': 'partners', 'hand': 'left'},
      ),
      'Neighbor pull by right': (
        move: 'pull_by_dancers',
        params: {'who': 'neighbors', 'hand': 'right'},
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

    // 9. chain "to neighbor/partner" → structured chain + Figure NOTE (TCB
    //    writes "Ladies chain to neighbor/partner" exclusively).
    test('"Ladies chain to neighbor" structures + preserves note', () {
      final f = parseFigureLine('Ladies chain to neighbor');
      expect(f!.isCustom, isFalse);
      expect(f.move, 'chain');
      expect(f.params['who'], 'role2s');
      expect(f.note, 'to neighbor');
    });

    test('"Ladies chain to partner" preserves the partner note', () {
      final f = parseFigureLine('Ladies chain to partner');
      expect(f!.move, 'chain');
      expect(f.note, 'to partner');
    });

    // 2. The custom fallback keeps the original parenthetical annotation
    //    (stripping is for RECOGNITION only, so nothing is lost).
    test('unrecognized line keeps its parenthetical annotation in custom '
        'text', () {
      final f = parseFigureLine('hey for four (from the top)');
      expect(f!.isCustom, isTrue);
      expect(_text(f), 'hey for four (from the top)');
    });

    // Tier A: a direction-only pull-by (no named dancer) → pull_by_direction.
    // No such form was found in the scanned TCB sample — every attested TCB
    // pull-by names a dancer (→ pull_by_dancers) — so this synthetic line just
    // guards the defensive direction branch of the _pullBy recognizer.
    test('"Pull by across" (no dancer) → pull_by_direction', () {
      final f = parseFigureLine('Pull by across');
      expect(f!.isCustom, isFalse);
      expect(f.move, 'pull_by_direction');
      expect(f.params['dir'], 'across');
    });
  });
}
