import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Tests for the relocated CallersBox/TCB figure-text front-end
/// (`callersbox_figure_dialect.dart`) and the seam it plugs into.
///
/// The exhaustive TCB grammar assertions (every hey pass-list shape, every
/// annotation/`;`-compound case) live in `figure_parser_test.dart`, which now
/// binds to [tcbFigureFrontEnd]. This suite instead pins the RELOCATION itself:
/// the narrowed canonical core does NOT carry the TCB idioms, the TCB front-end
/// re-adds them (byte-identical to the pre-split behavior), and the other two
/// source front-ends are the neutral canonical dialect for now.
void main() {
  group('tcbFigureFrontEnd — hey pass-list decoder (relocated)', () {
    test('decodes a TCB hey pass list into a structured hey', () {
      final f = parseFigureLine(
        'Hey 1/2 (WR;PL;MR;N2L~)',
        frontEnd: tcbFigureFrontEnd,
      );
      expect(f, isNotNull);
      expect(f!.isCustom, isFalse);
      expect(f.move, 'hey');
      expect(f.params['length'], 'half');
      expect(f.params['pass1'], 'role2s'); // WR -> W = role2s
      expect(f.params['shoulder'], 'right');
      expect(f.params['pass2'], 'partners'); // PL -> P
    });

    test('the canonical core does NOT decode a hey pass list (→ custom)', () {
      // Without the front-end the pass list is just a parenthetical annotation
      // no recognizer accounts for, so the whole line stays an honest custom.
      final f = parseFigureLine('Hey 1/2 (WR;PL;MR;N2L~)');
      expect(f, isNotNull);
      expect(f!.isCustom, isTrue);
    });
  });

  group('tcbFigureFrontEnd — ()/[] recognition-only annotation strip', () {
    test('strips a TCB param annotation for recognition', () {
      final f = parseFigureLine(
        'Pass through (NR)',
        frontEnd: tcbFigureFrontEnd,
      );
      expect(f, isNotNull);
      expect(f!.isCustom, isFalse);
      expect(f.move, 'pass_through');
    });

    test('the canonical core keeps the annotation → line stays custom', () {
      final f = parseFigureLine('Pass through (NR)');
      expect(f, isNotNull);
      expect(f!.isCustom, isTrue);
      // The annotation survives verbatim on the custom fallback (unchanged).
      expect(f.params['text'], contains('(NR)'));
    });

    test('the strip is recognition-only: an unrecognised TCB line keeps '
        'its annotation verbatim even under the front-end', () {
      // "spin the top" is not a covered move, so even with the front-end the
      // line falls to custom carrying the full annotated text.
      final f = parseFigureLine(
        'Spin the top (NR)',
        frontEnd: tcbFigureFrontEnd,
      );
      expect(f!.isCustom, isTrue);
      expect(f.params['text'], contains('(NR)'));
    });
  });

  group('parseFigureLines — `;`-compound splitter (relocated)', () {
    test('splits a top-level `;` compound into one figure per clause', () {
      final fs = parseFigureLines(
        'Circle left 3/4; turn alone',
        beats: 8,
        frontEnd: tcbFigureFrontEnd,
      );
      expect(fs.map((f) => f.move), ['circle', 'turn_alone']);
      expect(fs.every((f) => !f.isCustom), isTrue);
      // Lossless beats: the source total rides on the first clause only.
      expect(fs.first.params['beats'], 8);
      expect(fs.last.params.containsKey('beats'), isFalse);
    });

    test('the front-end flows through to each clause (all-or-nothing)', () {
      // First clause needs the TCB annotation strip. With the front-end both
      // clauses structure; without it the first clause fails and the whole
      // line collapses to a single custom figure.
      const line = 'Pass through (NR); turn alone';
      final tcb = parseFigureLines(line, beats: 8, frontEnd: tcbFigureFrontEnd);
      expect(tcb.map((f) => f.move), ['pass_through', 'turn_alone']);

      final canonical = parseFigureLines(line, beats: 8);
      expect(canonical, hasLength(1));
      expect(canonical.single.isCustom, isTrue);
    });

    test('a line with no top-level `;` yields the single-line result', () {
      final fs = parseFigureLines('Neighbor swing', beats: 16);
      expect(fs, hasLength(1));
      expect(fs.single.move, 'swing');
    });

    test('a top-level `||` (simultaneity) stays whole-custom', () {
      final fs = parseFigureLines(
        'Balance || swing',
        frontEnd: tcbFigureFrontEnd,
      );
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isTrue);
    });
  });

  group('adapter front-ends are independently-callable', () {
    test('ContraDB-HTML and CallersCompanion front-ends are canonical/neutral '
        'for now', () {
      // Named, independently-callable seams so a future free-text fan-out can
      // select them; both are the neutral canonical dialect in this PR.
      expect(
        identical(contraDbHtmlFigureFrontEnd, canonicalFigureFrontEnd),
        isTrue,
      );
      expect(
        identical(callersCompanionFigureFrontEnd, canonicalFigureFrontEnd),
        isTrue,
      );
    });

    test('the neutral front-ends leave TCB notation unstructured', () {
      for (final frontEnd in [
        contraDbHtmlFigureFrontEnd,
        callersCompanionFigureFrontEnd,
      ]) {
        expect(
          parseFigureLine('Hey 1/2 (WR;PL)', frontEnd: frontEnd)!.isCustom,
          isTrue,
        );
        expect(
          parseFigureLine('Pass through (NR)', frontEnd: frontEnd)!.isCustom,
          isTrue,
        );
      }
    });
  });
}
