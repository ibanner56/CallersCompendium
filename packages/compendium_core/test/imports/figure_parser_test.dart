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
      // box_circulate (v11, ContraDB-sourced). A standalone line states no
      // balance, so `balance` is left absent (the CallersBox merge folds a
      // preceding balance line in as true); `hand`/`who` fall to MoveDef
      // defaults.
      'Box circulate': (move: 'box_circulate', params: {'who': 'partners'}),
      'Partners box circulate': (
        move: 'box_circulate',
        params: {'who': 'partners'},
      ),
      'Neighbors box circulate': (
        move: 'box_circulate',
        params: {'who': 'neighbors'},
      ),
      // star_through (v12): mirrors california_twirl — who + beats only, no
      // balance param.
      'Star through': (move: 'star_through', params: {'who': 'partners'}),
      'Neighbors star through': (
        move: 'star_through',
        params: {'who': 'neighbors'},
      ),
      // "star thru" folds to "star through" in _normalize.
      'Star thru': (move: 'star_through', params: {'who': 'partners'}),
      // "Weave the line" is a D4-ratified synonym for the existing zig_zag move.
      'Weave the line': (move: 'zig_zag', params: {}),
      'Partners weave the line': (move: 'zig_zag', params: {'who': 'partners'}),
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
      // TCB "Rory O'More" (dance ids 6, 39). A standalone line is the unbalanced
      // 4-beat slide, so the recogniser emits `balance: false` EXPLICITLY (TCB
      // writes the balance as a separate preceding line; PR3b's merge flips it).
      "Rory O'More": (move: 'rory_o_more', params: {'balance': false}),
      "Rory O'More right": (
        move: 'rory_o_more',
        params: {'slide': 'right', 'balance': false},
      ),
      "Rory O'More left": (
        move: 'rory_o_more',
        params: {'slide': 'left', 'balance': false},
      ),
      "Ones Rory O'More": (
        move: 'rory_o_more',
        params: {'who': 'ones', 'balance': false},
      ),
      // A bare "Rory" is unambiguous shorthand for Rory O'More.
      'Rory': (move: 'rory_o_more', params: {'balance': false}),
      // TCB "Go down the hall" / "Down the hall" (dance ids 10945, 11239,
      // 12001). A bare hall line states no ender, so the recogniser emits
      // `ender: 'none'` EXPLICITLY; the bend-the-line merge upgrades it later.
      'Go down the hall': (move: 'down_the_hall', params: {'ender': 'none'}),
      'Down the hall': (move: 'down_the_hall', params: {'ender': 'none'}),
      // The "the" is optional, so the shorter alias parses the same.
      'Down hall': (move: 'down_the_hall', params: {'ender': 'none'}),
      'Everyone down the hall': (
        move: 'down_the_hall',
        params: {'who': 'everyone', 'ender': 'none'},
      ),
      'Go up the hall': (move: 'up_the_hall', params: {'ender': 'none'}),
      'Up the hall': (move: 'up_the_hall', params: {'ender': 'none'}),
      'Up hall': (move: 'up_the_hall', params: {'ender': 'none'}),
      // TCB frames a foursome as "In a line of four, go down/up the hall
      // (M1-W2-M2-W1)": the "(…)" dancer-order annotation is stripped by
      // normalization, and the leading "In a line of four" formation clause is
      // consumed (a line of four is the default hall formation, so dropping it
      // does not change the move). "cozy" is an accepted qualifier.
      'In a line of four, go down the hall (M1-W2-M2-W1)': (
        move: 'down_the_hall',
        params: {'ender': 'none'},
      ),
      'In a line of four, go up the hall (W2-W1-M1-M2)': (
        move: 'up_the_hall',
        params: {'ender': 'none'},
      ),
      'In a cozy line of four, go up the hall (M1-W2-M2-W1)': (
        move: 'up_the_hall',
        params: {'ender': 'none'},
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

    test('a bare "Rory O\'More" line validates and renders on defaults', () {
      // The recogniser emits `balance: false` explicitly — a standalone rory
      // line is the unbalanced slide; TCB writes the balance as a separate
      // preceding line (PR3b's merge flips it to true). `balance` is a
      // structured param, not a render token, so it never appears in the
      // canonical rendering; `slide`/`who` fall to their MoveDef defaults.
      final f = parseFigureLine("Rory O'More");
      expect(f!.isCustom, isFalse);
      expect(f.move, 'rory_o_more');
      expect(f.params['balance'], false);
      final rendered = FigureRenderer(contraTaxonomy).renderCanonical(f);
      expect(rendered, "everyone Rory O'More right");
    });

    test('down/up the hall emit ender: none (merge sets it later)', () {
      // The ender is a separate following line in TCB; a bare hall line states
      // no ender, so we emit the neutral `none` rather than inheriting the
      // MoveDef default (turnCouple/circle). PR3b upgrades none→bendTheLine.
      final down = parseFigureLine('Go down the hall');
      expect(down!.move, 'down_the_hall');
      expect(down.params['ender'], 'none');
      final up = parseFigureLine('Up the hall');
      expect(up!.move, 'up_the_hall');
      expect(up.params['ender'], 'none');
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
      // "contra corners" IS recognised now, but only with an explicit turning
      // couple ("Ones/Twos turn contra corners"). A bare "contra corners" names
      // no couple, and defaulting `who` would fabricate one, so it stays custom.
      'contra corners',
      // Dropped from PR5 (no ContraDB source) — must stay custom, never
      // fabricated into a structured move.
      'Grand right and left',
      'Grand right & left',
      'Flutterwheel',
      'Flutter wheel',
      // A bare "circulate" without the "box" anchor is not box_circulate.
      'circulate',
      // box_circulate with trailing prose it cannot consume stays custom.
      'box circulate and swing',
      // "star through" with trailing prose it cannot consume stays custom.
      'star through the door',
      // "weave the ring" is a DIFFERENT figure (backlog, out of scope) and must
      // NOT be swept into the weave-the-line → zig_zag alias.
      'weave the ring',
      // weave the line with trailing prose it cannot consume stays custom.
      'weave the line and swing',
      // "down/up the hall" IS recognised now, but a descriptor that changes the
      // move leaves leftover tokens, so these near-misses stay custom:
      //   "four in line" (a formation detail the taxonomy can't carry) and
      //   "and back" (forward-then-backward, a distinct `facing`).
      'down the hall four in line',
      'go down the hall and back',
      'up the hall and back',
      // The "In a line of four" hall prefix is only consumed when it LEADS the
      // line. A non-leading "line of four" (an unattested trailing form) is not
      // stripped, so leftover tokens keep the line custom.
      'go down the hall in a line of four',
      // The leading "In a line of four" hall prefix IS consumed now, but the
      // "forward and back" formation variants are DELIBERATELY excluded: a big
      // ring and lines-of-four are distinct formations from long lines, so
      // folding them into `long_lines` would assert a formation the source did
      // not state. They stay custom pending a source-justified model.
      'In a big ring, go forward and back',
      'In lines of four, go forward and back',
      // "Rory O'More" IS recognised now, but trailing structure (a second move)
      // or an out-of-domain dancer set forces custom:
      "Rory O'More and swing",
      'balance and Rory O\'More',
      // "neighbors" is not one of Rory O'More's dancer-set choices, so the
      // candidate fails validation and degrades to custom.
      "Neighbor Rory O'More",
      // "square through" spelled out (TCB uses a digit count) stays custom.
      'square through four',
      // gate: intentionally stays custom. Every surveyed TCB gate (62 lines)
      // carries a clockwise/counterclockwise/mirror qualifier + turn fraction;
      // ContraDB gate is facing-only (up/down/in/out, fixed 8 beats). The
      // domains are DISJOINT (0/62 TCB lines map to `face`), so a `_gate`
      // recognizer would match nothing or fabricate a `face` value the line
      // never stated. For import fidelity it stays custom (dance id 519).
      'N2 neighbor gate counterclockwise 1/2',
      // A poussette with an unmappable leftover ("draw") stays custom.
      'Neighbor draw poussette clockwise 1/2',
      // A dancer-named pull-by with a trailing direction: pull_by_dancers has
      // no direction slot, so rather than silently drop "across" the line must
      // fall to custom (the direction is only valid on the direction-only form).
      'Men pull by left across',
      // Partial long-lines descriptors are not the canonical "forward and
      // back", so they degrade to custom rather than a half-described figure.
      'long lines back',
      'long lines forward',
      // --- hey (PR4): stays custom when the pass list can't be decoded ------
      // Bare "hey for four" carries no pass list (no pass1/shoulder source).
      'hey 1/2',
      'full hey',
      'hey',
      // dolphin hey is a different move — never matched by the hey recognizer.
      'dolphin hey (WR;PL)',
      // Trailing extra move after a decodable pass list.
      'Hey 1/2 (WR;PL) and swing',
      // An unmappable people code in the pass list.
      'Hey 1/2 (XR;PL)',
      // Non-alternating shoulders (both right) — malformed/ambiguous.
      'Hey 1/2 (WR;PR)',
      // Neighbor/partner ricochet is not representable.
      'Hey (ML;N ricochet;ML;PR)',
      // A ricochet at an even position (only odd positions are center passes).
      'Hey (ML;M ricochet;WL;PR)',
      // A ricochet whose slot the hey length can't reach: a half hey has at
      // most two same-role passes, so a ricochet at the 3rd (pos5) -> rico3 is
      // unreachable -> custom.
      'Hey 1/2 (ML;PR;WL;PR;M ricochet)',
      // Length bound (finer per-length cap): the effective length caps the
      // reachable rico slot (1/4->rico1, 1/2->rico2, 3/4->rico3, full->rico4).
      // A pos5 ricochet is rico3, above a half hey's max of rico2 -> custom.
      'Hey 1/2 (ML;NR;WL;PR;M ricochet;PR;WL)',
      // A half hey with all-four ricochet positions: rico3/rico4 exceed max2.
      'Hey 1/2 (M ricochet;NR;W ricochet;PR;M ricochet;NR;W ricochet;PR)',
      // Unspecified length defaults to half, so a pos5 ricochet (rico3) still
      // exceeds max2 -> custom (we never infer length from the pass count).
      'Hey (ML;NR;WL;PR;M ricochet;PR;WL)',
      // 3/4 caps at rico3, so a pos7 ricochet (rico4) exceeds it -> custom.
      'Hey 3/4 (M ricochet;NR;W ricochet;PR;M ricochet;NR;W ricochet;PR)',
    ];

    for (final line in mustStayCustom) {
      test('"$line" stays custom', () {
        final f = parseFigureLine(line);
        expect(f, isNotNull, reason: line);
        expect(f!.isCustom, isTrue, reason: line);
      });
    }
  });

  group('parseFigureLine — hey (TCB pass lists)', () {
    ({String move, Map<String, Object?> params})? parse(String line) {
      final f = parseFigureLine(line);
      if (f == null || f.isCustom) return null;
      return (move: f.move, params: f.params);
    }

    test('decodes the canonical fixture line (~ dropped)', () {
      final f = parseFigureLine('Hey 1/2 (WR;PL;MR;N2L~)');
      expect(f!.isCustom, isFalse);
      expect(f.move, 'hey');
      expect(f.params['length'], 'half');
      expect(f.params['pass1'], 'role2s'); // code1 WR -> W = role2s
      expect(f.params['shoulder'], 'right'); // code1 R
      expect(f.params['pass2'], 'partners'); // code2 PL -> P
      // No ricochet flags are set on a plain hey.
      for (final r in ['rico1', 'rico2', 'rico3', 'rico4']) {
        expect(f.params[r], isNull, reason: r);
      }
    });

    test('length decodes from the fraction (all four + default)', () {
      expect(parse('Hey 1/4 (WR;PL)')!.params['length'], 'lessThanHalf');
      expect(parse('Hey 1/2 (WR;PL)')!.params['length'], 'half');
      expect(parse('Hey 3/4 (WR;PL)')!.params['length'], 'betweenHalfAndFull');
      expect(parse('Full hey (WR;PL)')!.params['length'], 'full');
      expect(parse('Whole hey (WR;PL)')!.params['length'], 'full');
      // Unspecified length defaults to half.
      expect(parse('Hey (WR;PL)')!.params['length'], 'half');
      // Unicode ½ folds to 1/2.
      expect(parse('Hey ½ (WR;PL)')!.params['length'], 'half');
    });

    test('pass1/shoulder/pass2 come from the first two codes', () {
      final p = parse('Hey (ML;PR)')!;
      expect(p.params['pass1'], 'role1s'); // M
      expect(p.params['shoulder'], 'left'); // code1 L
      expect(p.params['pass2'], 'partners'); // P
    });

    test('shoulder alternates by position parity across four codes', () {
      // WR;PL;MR;N2L => R,L,R,L is consistent (base = right at odd positions).
      final p = parse('Hey 1/2 (WR;PL;MR;N2L)')!;
      expect(p.params['shoulder'], 'right');
    });

    test('a lone code leaves pass2 unspecified (MoveDef default applies)', () {
      final f = parseFigureLine('Hey (WR)');
      expect(f!.isCustom, isFalse);
      expect(f.params.containsKey('pass2'), isFalse);
      expect(contraTaxonomy.effectiveParams(f)['pass2'], 'unspecified');
    });

    test('ricochet maps by odd pass position (pos3 -> rico2)', () {
      final p = parse('Hey (ML;PR;W ricochet)')!;
      expect(p.params['rico2'], true);
      expect(p.params['pass1'], 'role1s');
      expect(p.params['pass2'], 'partners');
      expect(p.params['shoulder'], 'left');
      for (final r in ['rico1', 'rico3', 'rico4']) {
        expect(p.params[r], isNull, reason: r);
      }
    });

    test('ricochet at pos5 maps to rico3 (full hey reaches it)', () {
      final p = parse('Full hey (ML;NR;WL;PR;M ricochet;PR;WL)')!;
      expect(p.params['rico3'], true);
      expect(p.params['rico1'], isNull);
    });

    test('betweenHalfAndFull (3/4) reaches rico3 but not rico4', () {
      // 3/4 caps at rico3: a pos5 ricochet (rico3) is reachable...
      final p = parse('Hey 3/4 (ML;NR;WL;PR;M ricochet;PR;WL)')!;
      expect(p.params['rico3'], true);
      // ...but a pos7 ricochet (rico4) exceeds the cap -> custom (null here).
      expect(
        parse(
          'Hey 3/4 (M ricochet;NR;W ricochet;PR;M ricochet;NR;W ricochet;PR)',
        ),
        isNull,
      );
    });

    test('all four ricochets set rico1-4 (full hey)', () {
      final p = parse(
        'Full hey (M ricochet;NR;W ricochet;PR;M ricochet;NR;W ricochet;PR)',
      )!;
      expect(p.params['rico1'], true);
      expect(p.params['rico2'], true);
      expect(p.params['rico3'], true);
      expect(p.params['rico4'], true);
      expect(p.params['pass1'], 'role1s'); // pos1 M ricochet
      expect(p.params['pass2'], 'neighbors'); // pos2 NR
      expect(p.params['shoulder'], 'left'); // pos2 even, R => base left
    });

    // Real TCB fixtures (dances 16101 / 10394): "Ricochet hey" names the
    // variant, the ricochet lands at pass position 3 => rico2.
    test('real TCB fixture: Ricochet hey 1/2 (ML;PR;W ricochet)', () {
      final f = parseFigureLine('Ricochet hey 1/2 (ML;PR;W ricochet)');
      expect(f!.isCustom, isFalse);
      expect(f.move, 'hey');
      expect(f.params['length'], 'half');
      expect(f.params['pass1'], 'role1s'); // ML
      expect(f.params['shoulder'], 'left'); // code1 L
      expect(f.params['pass2'], 'partners'); // PR
      expect(f.params['rico2'], true);
      for (final r in ['rico1', 'rico3', 'rico4']) {
        expect(f.params[r], isNull, reason: r);
      }
    });

    test(
      'real TCB fixture: Ricochet hey 1/2 (WR;PL;M ricochet;PL~) — ~ dropped',
      () {
        final f = parseFigureLine('Ricochet hey 1/2 (WR;PL;M ricochet;PL~)');
        expect(f!.isCustom, isFalse);
        expect(f.move, 'hey');
        expect(f.params['length'], 'half');
        expect(f.params['pass1'], 'role2s'); // WR
        expect(f.params['shoulder'], 'right'); // code1 R
        expect(f.params['pass2'], 'partners'); // PL
        expect(f.params['rico2'], true); // M ricochet at pos3
        for (final r in ['rico1', 'rico3', 'rico4']) {
          expect(f.params[r], isNull, reason: r);
        }
      },
    );
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
      // 19. slide → slide_along_set (TCB "Slide left/right (past N)" — the
      //     Becket slide; the "(past …)" annotation is stripped). Same move as
      //     "Shift left/right".
      'Slide right (past N)': (
        move: 'slide_along_set',
        params: {'slide': 'right'},
      ),
      'Slide left (past P)': (
        move: 'slide_along_set',
        params: {'slide': 'left'},
      ),
      // 20. contra_corners (TCB "Ones/Twos turn contra corners", 16 beats).
      'Ones turn contra corners': (
        move: 'contra_corners',
        params: {'who': 'ones'},
      ),
      'Twos turn contra corners': (
        move: 'contra_corners',
        params: {'who': 'twos'},
      ),
      // 21. give_and_take (TCB "Men give-and-take partner/neighbor",
      //     hyphenated). Leading role = giver (`who`), trailing relationship =
      //     target (`whom`); both stated in-text.
      'Men give-and-take partner': (
        move: 'give_and_take',
        params: {'who': 'role1s', 'whom': 'partners'},
      ),
      'Men give-and-take neighbor': (
        move: 'give_and_take',
        params: {'who': 'role1s', 'whom': 'neighbors'},
      ),
      // Space-separated spelling is accepted too, with the role2 giver.
      'Women give and take neighbor': (
        move: 'give_and_take',
        params: {'who': 'role2s', 'whom': 'neighbors'},
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

    // give_and_take's giver domain is role1s/role2s. A give-and-take with no
    // leading role would misread its target as the giver, so it falls back to
    // custom rather than fabricating a giver.
    test('"give-and-take partner" (no leading role) → custom', () {
      final f = parseFigureLine('give-and-take partner');
      expect(f!.isCustom, isTrue);
    });

    // A give-and-take whose leading dancer is outside role1s/role2s is rejected
    // rather than silently coerced to the default giver.
    test('"Neighbor give-and-take partner" (bad giver domain) → custom', () {
      final f = parseFigureLine('Neighbor give-and-take partner');
      expect(f!.isCustom, isTrue);
    });

    // The giver must LEAD: an unattested order where the role appears after the
    // move ("give-and-take men partner") is not structured.
    test('"give-and-take men partner" (giver not leading) → custom', () {
      final f = parseFigureLine('give-and-take men partner');
      expect(f!.isCustom, isTrue);
    });

    // give-and-take requires a stated target; a bare giver + move is rejected.
    test('"Men give-and-take" (no target) → custom', () {
      final f = parseFigureLine('Men give-and-take');
      expect(f!.isCustom, isTrue);
    });

    // contra_corners requires the turning couple to LEAD: a trailing dancer set
    // ("turn contra corners ones") is an unattested order → custom.
    test('"turn contra corners ones" (couple not leading) → custom', () {
      final f = parseFigureLine('turn contra corners ones');
      expect(f!.isCustom, isTrue);
    });

    // contra_corners requires the identifying "turn" keyword.
    test('"Ones contra corners" (no "turn") → custom', () {
      final f = parseFigureLine('Ones contra corners');
      expect(f!.isCustom, isTrue);
    });
  });
}
