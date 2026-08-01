import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Issue #729 — annotation preservation for `chain`, `promenade` and
/// `right_left_through`.
///
/// The same gap `_gateAnnotation`/`_courtesyTurnAnnotation` (taxonomy v22/v23)
/// and `_walkForwardAnnotation` (#733) already closed for `gate`,
/// `courtesy_turn` and `pass_through`: `_stripAnnotations` drops `()`/`[]`
/// content before recognition, so a structured `chain`/`promenade`/
/// `right_left_through` used to SILENTLY LOSE a trailing qualifier — including
/// the two wordings that motivated this issue, where the lost qualifier
/// NEGATES a courtesy turn ("(without courtesy turn)") rather than merely
/// adding one.
///
/// **Locked design ruling (owner, #729), not re-litigated here:**
/// preserve-as-note for EVERY qualifier, additive or negating. No
/// `courtesyTurn` taxonomy flag, no decline-to-custom for the negating form —
/// the structured figure keeps asserting the un-negated choreography, and the
/// contradicting words live in the note. See the doc comment on
/// `_chainAnnotation` in `callersbox_figure_dialect.dart` for the full
/// reasoning and the measured corpus impact.
///
/// `chain` and `right_left_through` already emit their own recognizer note
/// (`to <dancer>` / `same-role`), so these two exercise the note-COMBINE path
/// (`_withAnnotationNote`); `promenade` has no note of its own and exercises
/// the plain add.
List<Figure> _parse(String text, {int beats = 0}) =>
    parseFigureLines(text, beats: beats, frontEnd: tcbFigureFrontEnd);

Figure _single(String text, {int beats = 0}) =>
    _parse(text, beats: beats).single;

/// Mirrors the package-private `_maxAnnotationNote` bound in
/// `callersbox_figure_dialect.dart` so the surrogate-pair test below can
/// state its own expectations without reaching into library internals. Kept
/// as a literal (not imported) deliberately — if the production bound ever
/// changes, this test should be re-derived against the new value rather than
/// silently tracking it.
const int _maxAnnotationNoteForTest = 200;

/// True iff every UTF-16 surrogate in [s] is correctly paired: every high
/// surrogate (0xD800-0xDBFF) is immediately followed by a low surrogate
/// (0xDC00-0xDFFF), and every low surrogate is immediately preceded by a
/// high one. A string with a LONE surrogate (from a naive, non-rune-aware
/// truncation) fails this check.
///
/// Neither `note.codeUnits` alone (which only catches a lone LOW surrogate,
/// missing a lone HIGH one left dangling at the very end of a truncated
/// string — precisely the shape a truncation cut produces) nor
/// `String.fromCharCodes(s.runes) == s` (which round-trips a malformed
/// string with a lone surrogate right back to itself, because `.runes`
/// surfaces an unpaired surrogate as its own code point) actually detects
/// this; both were verified empirically to pass on a deliberately malformed
/// string before being replaced by this check.
bool _isProperlySurrogatePaired(String s) {
  final units = s.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    final isHigh = unit >= 0xD800 && unit <= 0xDBFF;
    final isLow = unit >= 0xDC00 && unit <= 0xDFFF;
    if (isHigh) {
      final next = i + 1 < units.length ? units[i + 1] : null;
      if (next == null || next < 0xDC00 || next > 0xDFFF) return false;
    } else if (isLow) {
      final prev = i > 0 ? units[i - 1] : null;
      if (prev == null || prev < 0xD800 || prev > 0xDBFF) return false;
    }
  }
  return true;
}

void main() {
  group('#729 — chain: annotation combines with the "to <dancer>" note', () {
    test('the issue\'s own example line', () {
      final f = _single(
        'Ladies chain to partner (optional double courtesy turn)',
        beats: 8,
      );
      expect(f.move, 'chain');
      expect(f.params['who'], 'role2s');
      expect(f.note, 'to partner; optional double courtesy turn');
    });

    test('recognizer note leads; annotation trails', () {
      final f = _single(
        '[Groups of four] Ladies chain to neighbor (along the set)',
        beats: 8,
      );
      expect(f.move, 'chain');
      expect(f.note, 'to neighbor; Groups of four; along the set');
    });

    test('a numeric neighbor tag on the destination is untouched', () {
      final f = _single(
        'Ladies chain to neighbor N2 (optional courtesy turn)',
        beats: 8,
      );
      expect(f.move, 'chain');
      expect(f.note, 'to neighbor n2; optional courtesy turn');
    });

    test('no annotation → note is unchanged (plain destination only)', () {
      final f = _single('Ladies chain to partner', beats: 8);
      expect(f.move, 'chain');
      expect(f.note, 'to partner');
    });

    test('an annotation with no destination note is the annotation alone', () {
      final f = _single('Ladies chain (along the set)', beats: 8);
      expect(f.move, 'chain');
      // "Ladies" itself is a subject ("role2s"), consumed by chain's own
      // grammar — separate from the destination note this group is about.
      expect(f.params['who'], 'role2s');
      expect(f.note, 'along the set');
    });
  });

  group('#729 — promenade: annotation adds a note (no collision)', () {
    test('the issue\'s own example lines', () {
      for (final who in ['Partner', 'Neighbor']) {
        final f = _single(
          '$who promenade across (without courtesy turn)',
          beats: 8,
        );
        expect(f.move, 'promenade', reason: who);
        expect(f.note, 'without courtesy turn', reason: who);
      }
    });

    test('multiple annotations join in source order', () {
      final f = _single(
        '[Ones and twos] Partner promenade across (without courtesy turn)',
        beats: 8,
      );
      expect(f.move, 'promenade');
      expect(f.note, 'Ones and twos; without courtesy turn');
    });

    test('an un-annotated promenade carries no note', () {
      final f = _single('Partner promenade across', beats: 8);
      expect(f.move, 'promenade');
      expect(f.note, isNull);
    });
  });

  group('#729 — right_left_through: annotation combines with the "same-role" '
      'note', () {
    test('a bracketed subject combines with same-role, leading it', () {
      final f = _single(
        '[Ones and twos] Same-role right and left through with neighbor',
        beats: 8,
      );
      expect(f.move, 'right_left_through');
      expect(f.note, 'same-role; Ones and twos');
    });

    test('"right left through" (no "and") is the same anchor', () {
      final f = _single(
        '[Ones and twos] Same-role right left through with neighbor',
        beats: 8,
      );
      expect(f.move, 'right_left_through');
      expect(f.note, 'same-role; Ones and twos');
    });

    test('no same-role qualifier → note is the annotation alone', () {
      final f = _single(
        '[Ones and twos] Right and left through with neighbor',
        beats: 8,
      );
      expect(f.move, 'right_left_through');
      expect(f.note, 'Ones and twos');
    });

    test('no annotation → same-role note is unchanged', () {
      final f = _single(
        'Same-role right and left through with neighbor',
        beats: 8,
      );
      expect(f.move, 'right_left_through');
      expect(f.note, 'same-role');
    });
  });

  group('#729 — ordinary annotated lines are untouched', () {
    test('a TCB shorthand code has no special-case exclusion for chain — it '
        'becomes the note verbatim, unlike hey\'s own pass-list decoder', () {
      final f = _single('Ladies chain (NR)', beats: 8);
      expect(f.move, 'chain');
      expect(f.note, 'NR');
    });

    test('dir params are not disturbed by an added annotation', () {
      final f = _single(
        'Right and left through across (along the set)',
        beats: 8,
      );
      expect(f.move, 'right_left_through');
      expect(f.params['dir'], 'across');
      expect(f.note, 'along the set');
    });
  });

  group('#729 — bounds and rune-safety (OWASP: untrusted import input)', () {
    test('a long qualifier truncates without amputating the leading note', () {
      final qualifier = 'a' * 100;
      final f = _single(
        'Ladies chain to partner ($qualifier) ($qualifier) ($qualifier)',
        beats: 8,
      );
      expect(f.move, 'chain');
      expect(f.note, startsWith('to partner; '));
      expect(f.note!.length, lessThanOrEqualTo(kMaxFigureNote));
    });

    test('an over-long single parenthetical takes the stripped path', () {
      final f = _single(
        'Ladies chain to partner (${'very long qualifier ' * 40})',
        beats: 8,
      );
      expect(f.move, 'chain');
      expect(f.note, 'to partner');
    });

    test('the shared _maxAnnotations bound applies to chain too', () {
      final many = List.generate(10, (i) => '(q$i)').join(' ');
      final f = _single('Ladies chain to partner $many', beats: 8);
      expect(f.move, 'chain');
      // 8 kept (the shared cap) plus the leading destination note.
      expect(f.note!.split('; '), hasLength(9));
    });

    test('a purely-numeric annotation is skipped, not treated as prose', () {
      final f = _single('Partner promenade across (4)', beats: 8);
      expect(f.move, 'promenade');
      expect(f.note, isNull);
    });

    test('a truncated annotation note never splits a surrogate pair (mid-emoji '
        'truncation via the shared _maxAnnotationNote bound)', () {
      // Two annotations (regex per-run cap is 120 UTF-16 units; neither
      // approaches it) are deliberately sized so their `_joinAnnotations`
      // join — 118 + '; '.length(2) + 85 = 205 units — crosses the shared
      // `_maxAnnotationNote` (200) bound with a 💃 (U+1F483, a surrogate
      // pair) straddling the cut: 79 filler chars into the second
      // annotation puts the emoji's high surrogate at joined-string index
      // 199 and its low surrogate at 200 — exactly where a naive
      // `substring(0, 200)` would cut, and exactly where a mid-emoji split
      // would land if truncation were not rune-safe.
      const body1Len = 118;
      const filler2Len = 79;
      final emoji = '\u{1F483}';
      final body1 = 'a' * body1Len;
      final body2 = '${'b' * filler2Len}${emoji}tail';
      final line = 'Ladies chain to partner ($body1) ($body2)';

      // Control: prove the hazard is real by reconstructing the identical
      // pre-truncation join and confirming a NAIVE `substring` truncation
      // (not rune-aware) actually splits the pair here — i.e. this input
      // would fail the assertions below against a naive implementation.
      final joined = '$body1; $body2';
      expect(joined.length, greaterThan(_maxAnnotationNoteForTest));
      final naiveCut = joined.substring(0, _maxAnnotationNoteForTest);
      expect(
        _isProperlySurrogatePaired(naiveCut),
        isFalse,
        reason:
            'test input does not actually straddle a surrogate pair at '
            'the truncation boundary — fix the offsets above',
      );

      final f = _single(line, beats: 8);
      expect(f.move, 'chain');
      final note = f.note ?? '';
      expect(note.length, lessThanOrEqualTo(kMaxFigureNote));
      expect(_isProperlySurrogatePaired(note), isTrue, reason: 'note: $note');
    });

    test('a single annotation far exceeding the per-run capture bound is '
        'dropped whole (never partially captured mid-emoji)', () {
      // `_annotationRe`'s `{0,120}` bounds each PAREN RUN, not the overall
      // note: 300 emoji (600 UTF-16 units) never matches the regex at all
      // (no possible backtrack lands the closing `)` within 120 units), so
      // this annotation is dropped in its entirety — the line still
      // structures via the ordinary annotation-stripped path, keeping only
      // `chain`'s own recognizer note.
      final line = 'Ladies chain to partner (${'\u{1F483}' * 300})';
      final f = _single(line, beats: 8);
      expect(f.move, 'chain');
      expect(f.note, 'to partner');
    });

    test('an unterminated annotation never throws', () {
      for (final line in const [
        'Ladies chain to partner (optional courtesy turn',
        'Ladies chain to partner [[[[',
        'Partner promenade across ()',
        'Right and left through with partner (',
      ]) {
        expect(
          () => parseFigureLine(line, beats: 8, frontEnd: tcbFigureFrontEnd),
          returnsNormally,
          reason: line,
        );
      }
    });

    test('a pathological annotation run is bounded and never throws', () {
      final line = 'Ladies chain to partner ${'(x)' * 5000}';
      final f = parseFigureLine(line, beats: 8, frontEnd: tcbFigureFrontEnd);
      expect(f, isNotNull);
      expect((f!.note ?? '').length, lessThanOrEqualTo(kMaxFigureNote));
    });
  });

  group('#729 — front-end vs canonical core', () {
    test('the canonical core does not strip the annotation at all → the whole '
        'line stays custom (the qualifier survives verbatim either way)', () {
      // Without the TCB front-end, `_stripAnnotations` never runs at all —
      // not just the three new pre-recognizers — so the parenthetical is
      // literal, unconsumed text and the whole line stays custom, exactly
      // as it did before #729. This issue changes nothing about the
      // canonical (non-TCB) reading.
      final f = parseFigureLine(
        'Ladies chain to partner (optional double courtesy turn)',
        beats: 8,
      )!;
      expect(f.isCustom, isTrue);
      expect(f.params['text'], contains('optional double courtesy turn'));
    });

    test('a dialect-rendered role token in a preserved note', () {
      // Annotation extraction runs on the post-scrub text, so a gendered
      // source word already arrives as the canonical role token — matching
      // the existing `gate` precedent (`gate_test.dart`'s "role2s are posts"),
      // not a new concern this issue introduces.
      final f = _single('Ladies chain to partner (women pass right)', beats: 8);
      expect(f.move, 'chain');
      expect(f.note, contains('role2s pass right'));
    });
  });
}
