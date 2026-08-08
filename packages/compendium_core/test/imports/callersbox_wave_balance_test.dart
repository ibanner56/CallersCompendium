import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Issue #295 — The Caller's Box balance-a-wave lines.
///
/// TCB writes "balance an existing wave" as its own figure line
/// (`(4) Balance wave of four (NR,WL)`), the single largest custom bucket in
/// the 24k-dance corpus. Such a line maps onto the wave-FORMATION move carrying
/// its `balance` flag — a 1-line → 1-figure mapping that never emits an extra
/// 0-beat form figure and never steals a balance the existing cross-line folds
/// should claim.
///
/// Wordings and annotation shapes below are verbatim corpus samples.
Future<List<Figure>> _figuresFor(List<String> lines) async {
  final payload = jsonEncode({
    'ID': '42',
    'Name': 'Test Dance',
    'Permission': 'full',
    'phrases': [
      {'name': 'A1', 'figures': lines},
    ],
  });
  final adapter = CallersBoxAdapter();
  final discovered = await adapter.discover(ImportRequest(payload: payload));
  final raw = await adapter.fetch(discovered.single);
  return adapter.parse(raw).dance.figures;
}

int _totalBeats(List<Figure> figures) => figures.fold(0, (a, f) => a + f.beats);

void main() {
  group('wave-forming recognizer (TCB "form wave of four")', () {
    List<Figure> parse(String text, {int beats = 0}) =>
        parseFigureLines(text, beats: beats, frontEnd: tcbFigureFrontEnd);

    for (final wording in const [
      'form wave of four',
      'Form a wave of four',
      'form a wave',
      'form short waves',
    ]) {
      test('"$wording" structures as form_short_waves', () {
        final figures = parse(wording, beats: 4);
        expect(figures, hasLength(1));
        expect(figures.single.move, 'form_short_waves');
      });
    }

    test('a "with <dancer>" tail sets the sides pair', () {
      final figure = parse('form wave of four with N2', beats: 4).single;
      expect(figure.move, 'form_short_waves');
      expect(figure.params['sides'], 'nextNeighbors');
    });

    test('a "with <unknown>" tail stays custom rather than guessing', () {
      expect(
        parse('form wave of four with phantom shadow').single.isCustom,
        isTrue,
      );
    });

    for (final wording in const [
      'form wave of two',
      'form wave of six',
      'form new wave, all facing other direction',
      'form diagonal wave of four',
      'form intersecting waves of four',
      'form interlocking long waves',
    ]) {
      test('"$wording" stays custom (unmodeled formation)', () {
        expect(parse(wording).single.isCustom, isTrue);
      });
    }

    test('a `;` compound with a wave-forming clause now structures both', () {
      final figures = parse('Circle right 3/4; form wave of four', beats: 8);
      expect(figures.map((f) => f.move), ['circle', 'form_short_waves']);
      // Option A beats distribution: the source total rides on clause 1.
      expect(_totalBeats(figures), 8);
    });
  });

  group('implicit prior forming — the balance line becomes the form figure', () {
    test('Balance wave of four (NR,WL) decodes centre/sides/hands', () async {
      final figures = await _figuresFor([
        '(6) Neighbor allemande right 1/2',
        '(4) Balance wave of four (NR,WL)',
      ]);
      expect(figures, hasLength(2));
      expect(figures[1].move, 'form_short_waves');
      expect(figures[1].params['balance'], isTrue);
      // The relationship code is the SIDES pair, the role code the CENTRE, and
      // the stated hands are opposite (centerHand tracks the role code).
      expect(figures[1].params['sides'], 'neighbors');
      expect(figures[1].params['center'], 'role2s');
      expect(figures[1].params['centerHand'], 'left');
      // The balance line keeps its own beats: nothing is summed or invented.
      expect(figures[1].params['beats'], 4);
      expect(_totalBeats(figures), 10);
    });

    test(
      'Balance long wave (NL, women face in) decodes whom/hand/who',
      () async {
        final figures = await _figuresFor([
          '(6) Neighbor allemande left 1 & 1/4',
          '(4) Balance long wave (NL, women face in)',
        ]);
        expect(figures, hasLength(2));
        expect(figures[1].move, 'form_long_waves');
        expect(figures[1].params['balance'], isTrue);
        expect(figures[1].params['whom'], 'neighbors');
        expect(figures[1].params['hand'], 'left');
        // `who` is the facing-IN role, matching ContraDB's own subject.
        expect(figures[1].params['who'], 'role2s');
        expect(figures[1].params['beats'], 4);
        expect(_totalBeats(figures), 10);
      },
    );

    test('the N-suffixed and shadow codes decode too', () async {
      final figures = await _figuresFor([
        '(6) Women allemande left 1/2',
        '(4) Balance wave of four (N2R,WL)',
        '(6) Men allemande left 1/2',
        '(4) Balance long wave (SR, men face in)',
      ]);
      expect(figures[1].params['sides'], 'nextNeighbors');
      expect(figures[3].move, 'form_long_waves');
      expect(figures[3].params['whom'], 'shadows');
      expect(figures[3].params['hand'], 'right');
      expect(figures[3].params['who'], 'role1s');
    });

    test('an unannotated balance falls back to the MoveDef defaults', () async {
      final figures = await _figuresFor([
        '(6) Neighbor allemande right 1/2',
        '(4) Balance wave of four',
      ]);
      expect(figures[1].move, 'form_short_waves');
      expect(figures[1].params['balance'], isTrue);
      expect(figures[1].params.containsKey('center'), isFalse);
    });
  });

  group('explicit prior forming — exactly ONE form figure results', () {
    test('a formed wave + its balance merge, summing beats', () async {
      final figures = await _figuresFor([
        '(8) Circle right 3/4; form wave of four',
        '(4) Balance wave of four (NL,MR)',
      ]);
      // circle + ONE form figure — never two form figures.
      expect(figures.map((f) => f.move), ['circle', 'form_short_waves']);
      expect(figures[1].params['balance'], isTrue);
      expect(figures[1].params['beats'], 4); // 0 (form clause) + 4 (balance)
      // The balance line's annotation enriches the merged figure rather than
      // being discarded.
      expect(figures[1].params['sides'], 'neighbors');
      expect(figures[1].params['center'], 'role1s');
      expect(figures[1].params['centerHand'], 'right');
      expect(_totalBeats(figures), 12);
    });

    test(
      'the forming line\'s own params win over the balance annotation',
      () async {
        final figures = await _figuresFor([
          '(8) Circle right 3/4; form wave of four with N2',
          '(4) Balance wave of four (NR,WL)',
        ]);
        expect(figures, hasLength(2));
        // `sides` came from the forming line and is NOT overwritten.
        expect(figures[1].params['sides'], 'nextNeighbors');
        expect(figures[1].params['center'], 'role2s');
        expect(_totalBeats(figures), 12);
      },
    );

    test(
      'pass the ocean + a balance wave still merges, now with hands',
      () async {
        final figures = await _figuresFor([
          '(4) Pass the ocean',
          '(4) Balance wave of four (NR,WL)',
        ]);
        expect(figures, hasLength(1));
        expect(figures.single.move, 'pass_the_ocean');
        expect(figures.single.params['balance'], isTrue);
        expect(figures.single.params['beats'], 8);
        expect(figures.single.params['centerHand'], 'left');
        expect(_totalBeats(figures), 8);
      },
    );

    test('an UNSTRUCTURED forming line blocks the promotion', () async {
      // The source already states a forming we could not model; promoting the
      // balance beside it would double the formation, so both stay custom.
      final figures = await _figuresFor([
        '(4) form new wave, all facing other direction',
        '(4) Balance wave of four (NR,WL)',
      ]);
      expect(figures, hasLength(2));
      expect(figures.every((f) => f.isCustom), isTrue);
      expect(_totalBeats(figures), 8);
    });
  });

  group('an unmodeled formation qualifier is never folded away', () {
    // `_isBalanceWaveLine` used to accept ANY "balance … wave …" line, so a
    // balance naming a formation the taxonomy cannot represent folded into a
    // preceding wave move and the qualifier ("interlocking" / "intersecting" /
    // "circular") was silently dropped — the merged figure then asserted a
    // balance of a wave that is not the one the source named. 33 corpus lines
    // hit this. The fold and the promotion now refuse the same wordings.
    test(
      'the real TCB case: Gypsy Star B1 keeps its interlocking text',
      () async {
        // Verbatim from dance 2463 — the ONLY plural "form long waves" line in
        // the whole corpus, and the reason this guard exists.
        final figures = await _figuresFor([
          '(6) Facing star clockwise 1/2 (MR, WL, free hand to partner); '
              'form long waves in center',
          '(4) Balance interlocking long waves in center',
        ]);
        expect(figures, hasLength(3));
        expect(figures[1].move, 'form_long_waves');
        expect(figures[1].params.containsKey('balance'), isFalse);
        expect(figures[2].isCustom, isTrue);
        expect(
          figures[2].params['text'],
          contains('interlocking'),
          reason: 'the unmodeled formation word must survive verbatim',
        );
        expect(_totalBeats(figures), 10);
      },
    );

    for (final line in const [
      '(4) Balance interlocking long waves',
      '(4) Balance intersecting waves of four (C2R,ML)',
      '(4) Balance circular wave',
    ]) {
      test('"$line" does not fold into a preceding pass the ocean', () async {
        final figures = await _figuresFor(['(4) Pass the ocean', line]);
        expect(figures, hasLength(2));
        expect(figures[0].move, 'pass_the_ocean');
        expect(figures[0].params.containsKey('balance'), isFalse);
        expect(figures[1].isCustom, isTrue);
        // Beats are untouched either way — the fold summed them, and not
        // folding leaves the same two counts in place.
        expect(_totalBeats(figures), 8);
      });
    }

    test(
      'an ordinary balance wave still folds (the guard is narrow)',
      () async {
        final figures = await _figuresFor([
          '(4) Pass the ocean',
          '(4) Balance wave of four (NR,WL)',
        ]);
        expect(figures, hasLength(1));
        expect(figures.single.params['balance'], isTrue);
        expect(_totalBeats(figures), 8);
      },
    );
  });

  group('the existing forward balance-merge keeps its balances', () {
    const forwardCases = <String, String>{
      '(12) Neighbor swing': 'swing',
      '(4) Petronella': 'petronella',
      '(4) Rory O\'More right': 'rory_o_more',
      '(4) Neighbor box the gnat': 'box_the_gnat',
      '(4) Neighbor swat the flea': 'swat_the_flea',
      '(4) Circulate: women cross, men loop right': 'box_circulate',
    };
    forwardCases.forEach((line, move) {
      test('a balance wave before "$line" folds FORWARD into $move', () async {
        final figures = await _figuresFor([
          '(4) Balance wave of four (NR,WL)',
          line,
        ]);
        expect(
          figures,
          hasLength(1),
          reason: 'the balance must be claimed by the following move',
        );
        expect(figures.single.move, move);
        expect(figures.single.isCustom, isFalse);
        // No wave-formation figure was fabricated in its place.
        expect(figures.single.move, isNot(startsWith('form_')));
      });
    });

    test('a long-wave balance also folds forward', () async {
      final figures = await _figuresFor([
        '(4) Balance long wave (NR, women face in)',
        '(12) Partner swing',
      ]);
      expect(figures, hasLength(1));
      expect(figures.single.move, 'swing');
      expect(figures.single.params['prefix'], 'balance');
      expect(figures.single.params['beats'], 16);
    });
  });

  group('dancer-qualified balance folds when who agrees, stays custom when not',
      () {
    // Issue #872: "Men balance long wave in center" (dancer-qualified) must fold
    // into the preceding wave exactly like the bare form does.
    test(
      'dance 18878 A1: Men walk forward → form long wave + Men balance → '
      'single form_a_long_wave beats=8, no trailing custom',
      () async {
        final figures = await _figuresFor([
          '(4) Men walk forward; form long wave in center',
          '(4) Men balance long wave in center',
        ]);
        // One wave figure — NO trailing custom balance.
        expect(figures, hasLength(1));
        expect(figures.single.move, 'form_a_long_wave');
        expect(figures.single.params['balance'], isTrue);
        // Beats are summed: 4 (form) + 4 (balance).
        expect(figures.single.params['beats'], 8);
        expect(_totalBeats(figures), 8);
      },
    );

    test(
      'a dancer-qualified balance folds when the wave has no who (null waveWho)',
      () async {
        // pass_the_ocean has no `who` param (waveWho is null), so the mismatch
        // guard short-circuits and the fold proceeds regardless of the balance
        // line's dancer prefix.
        final figures = await _figuresFor([
          '(4) Pass the ocean',
          '(4) Women balance wave of four',
        ]);
        expect(figures, hasLength(1));
        expect(figures.single.move, 'pass_the_ocean');
        expect(figures.single.params['balance'], isTrue);
        expect(figures.single.params['beats'], 8);
        expect(_totalBeats(figures), 8);
      },
    );

    test(
      'a dancer-qualified balance whose prefix DISAGREES with the wave who '
      'does NOT fold, stays custom',
      () async {
        // form_a_long_wave{who: role1s} followed by "Women balance long wave":
        // balance prefix is role2s, wave who is role1s — mismatch → no fold.
        final figures = await _figuresFor([
          '(4) Men walk forward; form long wave in center',
          '(4) Women balance long wave in center',
        ]);
        expect(figures, hasLength(2));
        expect(figures[0].move, 'form_a_long_wave');
        expect(figures[0].params.containsKey('balance'), isFalse);
        expect(figures[1].isCustom, isTrue);
        expect(
          figures[1].params['text'],
          contains('balance'),
          reason: 'the balance line must survive as-is',
        );
        expect(_totalBeats(figures), 8);
      },
    );

    test(
      'bare Balance long wave … still folds unchanged (predicate not narrowed)',
      () async {
        final figures = await _figuresFor([
          '(4) Pass the ocean',
          '(4) Balance wave of four (NR,WL)',
        ]);
        expect(figures, hasLength(1));
        expect(figures.single.params['balance'], isTrue);
        expect(figures.single.params['beats'], 8);
      },
    );

    test(
      'a dancer-qualified balance with an unmodeled qualifier stays custom',
      () async {
        final figures = await _figuresFor([
          '(4) Pass the ocean',
          '(4) Men balance interlocking long waves in center',
        ]);
        expect(figures, hasLength(2));
        expect(figures[0].params.containsKey('balance'), isFalse);
        expect(figures[1].isCustom, isTrue);
        expect(figures[1].params['text'], contains('interlocking'));
        expect(_totalBeats(figures), 8);
      },
    );
  });

  group('conservative negatives — these stay custom', () {
    const negatives = <String>[
      // Wave sizes with no faithful model.
      '(4) Balance wave of two (PR)',
      '(4) Balance wave of three (twos+threes face in)',
      '(4) Balance wave of six (PR,NL)',
      '(4) Balance wave of eight (OR,SRNL)',
      // Exotic formations.
      '(4) Balance intersecting waves of four (C2R,ML)',
      '(4) Balance interlocking long waves in center',
      '(4) Balance circular wave',
      // Ambiguous / undecodable annotations.
      '(4) Balance wave of four (PL,?R)',
      '(4) Balance wave of four (SRNL,1R)',
      '(4) Balance long wave (N2R,N1L, women face in)',
      '(4) Balance long wave (SR, someone face in)',
      '(4) Balance long wave (1R)',
      '(4) Balance long wave for all in center',
      '(4) Balance long wave',
      // A bare dancer balance is not a wave balance at all.
      '(4) Neighbor balance',
    ];
    for (final line in negatives) {
      test('"$line" is not promoted', () async {
        final figures = await _figuresFor([
          line,
          '(12) Long lines forward & back',
        ]);
        expect(figures.first.move, isNot(startsWith('form_')));
      });
    }
  });

  group('beat totals never drift', () {
    test('sections land identically for both adjacency cases', () async {
      final figures = await _figuresFor([
        // A1: implicit case (allemande leaves the dancers in a wave).
        '(6) Neighbor allemande left 1 & 1/4',
        '(4) Balance long wave (NL, women face in)',
        '(6) Partner swing',
        // A2: explicit case (a formed wave then its balance).
        '(8) Circle right 3/4; form wave of four',
        '(4) Balance wave of four (NL,MR)',
        '(4) Neighbor swing',
        '(16) Long lines forward & back',
        '(16) Ladies chain',
      ]);
      final issues = <ValidationIssue>[];
      final sections = deriveSections(
        figures,
        PhraseStructure.standard,
        issues: issues,
      );
      expect(_totalBeats(figures), 64);
      expect(issues, isEmpty);
      expect(sections, hasLength(figures.length));
    });
  });
}
