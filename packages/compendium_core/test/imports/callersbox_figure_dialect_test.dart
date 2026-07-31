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

    test('a top-level `||` (simultaneity) fans into a `meanwhile` container '
        '(#591/#572)', () {
      // Both "Balance" and "swing" structure via the TCB front-end, so the
      // line fans into one meanwhile container carrying both sides — no
      // longer a single opaque whole-custom figure.
      final fs = parseFigureLines(
        'Balance || swing',
        beats: 6,
        frontEnd: tcbFigureFrontEnd,
      );
      expect(fs, hasLength(1));
      final container = fs.single;
      expect(container.isCustom, isFalse);
      expect(container.isMeanwhile, isTrue);
      expect(container.subFigures.map((f) => f.move), ['balance', 'swing']);
      expect(container.subFigures.every((f) => !f.isCustom), isTrue);
      // Shared beats ride on the container, never per-side.
      expect(container.params['beats'], 6);
      expect(
        container.subFigures.every((f) => !f.params.containsKey('beats')),
        isTrue,
      );
    });

    test('issue #591\'s own example: "Women allemande left 1 || Men orbit '
        'clockwise ½" fans into a meanwhile container', () {
      // One side structures (allemande); the other stays custom (prefer-
      // custom) — the container is still built either way, and neither
      // subject text is dropped.
      final fs = parseFigureLines(
        'Women allemande left 1 || Men orbit clockwise ½',
        beats: 6,
        frontEnd: tcbFigureFrontEnd,
      );
      expect(fs, hasLength(1));
      final container = fs.single;
      expect(container.isMeanwhile, isTrue);
      expect(container.params['beats'], 6);
      final sides = container.subFigures;
      expect(sides, hasLength(2));
      expect(sides[0].move, 'allemande');
      expect(sides[0].isCustom, isFalse);
      expect(sides[0].params['who'], 'role2s');
      expect(sides[1].isCustom, isTrue);
      expect(sides[1].params['text'], 'role1s orbit clockwise ½');
    });

    test('a security bound: more than kMaxMeanwhileSides top-level `||` '
        'separators safely degrades to the pre-#591 whole-custom fallback '
        '(never throws, never truncates)', () {
      // 7 sides: one more than kMaxMeanwhileSides (6). A hostile/malformed
      // import line can't force an oversized meanwhile container or crash
      // the factory's precondition — it just falls back to today's
      // behaviour, unmodified and undropped.
      final line = List.filled(7, 'Circle left').join(' || ');
      final fs = parseFigureLines(line, beats: 8, frontEnd: tcbFigureFrontEnd);
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isTrue);
      expect(fs.single.isMeanwhile, isFalse);
      expect(fs.single.params['text'], line);
    });

    test('a degenerate leading `||` (empty first side) declines to fan out '
        'and stays whole-custom', () {
      final fs = parseFigureLines(
        '|| swing',
        beats: 4,
        frontEnd: tcbFigureFrontEnd,
      );
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isTrue);
      expect(fs.single.isMeanwhile, isFalse);
    });

    test('a degenerate trailing `||` (empty last side) declines to fan out '
        'and stays whole-custom', () {
      final fs = parseFigureLines(
        'Balance ||',
        beats: 4,
        frontEnd: tcbFigureFrontEnd,
      );
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isTrue);
      expect(fs.single.isMeanwhile, isFalse);
    });

    test('a degenerate empty middle side (`A|| ||B`) declines to fan out '
        'and stays whole-custom', () {
      final fs = parseFigureLines(
        'Balance|| ||swing',
        beats: 4,
        frontEnd: tcbFigureFrontEnd,
      );
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isTrue);
      expect(fs.single.isMeanwhile, isFalse);
    });
  });

  group('adapter front-ends are independently-callable', () {
    test('CallersCompanion stays canonical; ContraDB-HTML is now enriched', () {
      // Named, independently-callable seams so a future free-text fan-out can
      // select them. CallersCompanion is still the neutral canonical dialect;
      // ContraDB-HTML now carries its own dedicated reverse-parsers.
      expect(
        identical(callersCompanionFigureFrontEnd, canonicalFigureFrontEnd),
        isTrue,
      );
      expect(
        identical(contraDbHtmlFigureFrontEnd, canonicalFigureFrontEnd),
        isFalse,
      );
      expect(contraDbHtmlFigureFrontEnd.preRecognizers, isNotEmpty);
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
      }
      // The canonical/CallersCompanion front-end still leaves a bare
      // `Pass through (NR)` unstructured (no ContraDB direction render).
      expect(
        parseFigureLine(
          'Pass through (NR)',
          frontEnd: callersCompanionFigureFrontEnd,
        )!.isCustom,
        isTrue,
      );
      // The ContraDB HTML front-end now recognises a bare `pass through` and
      // keeps the trailing qualifier as a verbatim note (#585): programs render
      // bare pass-throughs (e.g. The Hobbit, Sweet Vicki), so this is a modeled
      // figure rather than custom.
      final passThrough = parseFigureLine(
        'Pass through (NR)',
        frontEnd: contraDbHtmlFigureFrontEnd,
      )!;
      expect(passThrough.isCustom, isFalse);
      expect(passThrough.move, 'pass_through');
      expect(passThrough.note, '(NR)');
    });
  });
}
