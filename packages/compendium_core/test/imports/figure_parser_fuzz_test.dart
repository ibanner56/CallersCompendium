import 'dart:math';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Deterministic property/fuzz test for the import FIGURE parse chokepoint
/// ([parseFigureLine] / [parseFigureLines] / [scrubFigureText]) — the ONE path
/// every free-text adapter (plaintext CallersBox, ContraDB HTML, the Caller's
/// Companion text/`.USR` figure text) routes its lines through.
///
/// ## Why this exists (OWASP A04 Insecure Design — untrusted input)
/// Imported figure text is **untrusted** (it originates from shared/community
/// files). The parser's published contract is **parse-never-fails**: it MUST
/// NOT throw on arbitrary/garbage input — unrecognised text degrades to a
/// custom figure and nothing is dropped. A launch-readiness audit ran a
/// throwaway 200k-iteration harness that found 0 throws; this converts that
/// into a **committed, seeded, bounded** property test so the invariant is
/// guarded in CI forever.
///
/// ## Determinism / CI cost
/// The generator is driven by a single fixed-seed [Random], so every run
/// explores the exact same inputs — no wall-clock or environment dependence and
/// nothing flaky. The iteration count is bounded small enough to stay CI-fast
/// (a few thousand), deliberately NOT the audit's 200k. A failure prints the
/// seed + iteration + the offending input's code units so it is trivially
/// reproducible.
void main() {
  group('parseFigureLine — parse-never-fails property (seeded fuzz)', () {
    test('never throws and always returns a well-formed structure', () {
      final rng = Random(_seed);
      for (var i = 0; i < _iterations; i++) {
        final raw = _randomFigureLine(rng);
        final beats = _randomBeats(rng);
        final progression = rng.nextBool();
        _checkSingle(raw, beats: beats, progression: progression, iteration: i);
      }
    });

    test('holds on a hand-picked adversarial corpus', () {
      for (var i = 0; i < _adversarialCorpus.length; i++) {
        // Exercise each adversarial string across a few beat/progression shapes
        // (0, a normal count, an atypically large count, and a negative count),
        // since beats feed the structured-vs-custom decision and the
        // negative-beat normalisation.
        for (final beats in const [0, 16, 999, -5]) {
          _checkSingle(
            _adversarialCorpus[i],
            beats: beats,
            progression: beats.isEven,
            iteration: i,
            label: 'adversarial',
          );
        }
      }
    });
  });

  group('parseFigureLines — compound split never-fails property', () {
    test('never throws; every clause is a well-formed figure', () {
      final rng = Random(_seed ^ 0x1234);
      for (var i = 0; i < _iterations; i++) {
        // Bias toward strings that contain clause separators so the top-level
        // `;` split, the `||` simultaneity guard, and the bracket-depth logic
        // are actually exercised (not just the single-line fast path).
        final raw = _randomCompoundLine(rng);
        final beats = _randomBeats(rng);
        final progression = rng.nextBool();
        _checkMulti(raw, beats: beats, progression: progression, iteration: i);
      }
    });
  });

  group('scrubFigureText — never throws, always trimmed', () {
    test('arbitrary garbage scrubs to a clean trimmed string', () {
      final rng = Random(_seed ^ 0x7f7f);
      for (var i = 0; i < _iterations; i++) {
        final raw = _randomFigureLine(rng);
        final String scrubbed;
        try {
          scrubbed = scrubFigureText(raw);
        } catch (e, st) {
          fail(_repro(raw, i, 'scrub', 'scrubFigureText threw: $e\n$st'));
        }
        // The scrub always trims and collapses whitespace, so the result never
        // has surrounding whitespace regardless of input.
        if (scrubbed.trim() != scrubbed) {
          fail(_repro(raw, i, 'scrub', 'result was not trimmed'));
        }
      }
    });
  });
}

// --- Invariant checks ------------------------------------------------------

/// Runs [parseFigureLine] on [raw] and asserts every parse-never-fails
/// invariant, attributing any failure to a reproducible ([iteration], input).
void _checkSingle(
  String raw, {
  required int beats,
  required bool progression,
  required int iteration,
  String label = 'single',
}) {
  final Figure? result;
  try {
    result = parseFigureLine(raw, beats: beats, progression: progression);
  } catch (e, st) {
    fail(_repro(raw, iteration, label, 'parseFigureLine threw: $e\n$st'));
  }

  // Contract: returns null IFF the text is empty after scrubbing. The parser
  // scrubs with the same pure [scrubFigureText], so this equivalence is exact.
  final emptyAfterScrub = scrubFigureText(raw).isEmpty;
  if (emptyAfterScrub) {
    if (result != null) {
      fail(_repro(raw, iteration, label, 'expected null (empty after scrub)'));
    }
    return;
  }
  if (result == null) {
    fail(_repro(raw, iteration, label, 'expected a figure (non-empty scrub)'));
  }
  _assertWellFormed(result, raw, iteration, label);
}

/// Runs [parseFigureLines] on [raw] and asserts it never throws and that every
/// returned clause is a well-formed figure.
void _checkMulti(
  String raw, {
  required int beats,
  required bool progression,
  required int iteration,
}) {
  final List<Figure> result;
  try {
    result = parseFigureLines(raw, beats: beats, progression: progression);
  } catch (e, st) {
    fail(_repro(raw, iteration, 'multi', 'parseFigureLines threw: $e\n$st'));
  }
  for (final f in result) {
    _assertWellFormed(f, raw, iteration, 'multi');
  }
}

/// The shared "well-formed structure" invariant for any figure the parser
/// returns.
void _assertWellFormed(Figure f, String raw, int iteration, String label) {
  // Beats are always non-negative (negative source beats are normalised to 0).
  if (f.beats < 0) {
    fail(_repro(raw, iteration, label, 'negative beats leaked through'));
  }

  if (f.isCustom) {
    // A custom fallback always carries the (non-empty) scrubbed text verbatim.
    final text = f.params['text'];
    if (text is! String) {
      fail(_repro(raw, iteration, label, 'custom figure missing text'));
    }
    if (text.isEmpty) {
      fail(_repro(raw, iteration, label, 'custom text was empty'));
    }
  } else if (f.isMeanwhile) {
    // A `meanwhile` container (#591/#572) is a STRUCTURAL id like `custom` —
    // deliberately unregistered in the taxonomy, so it never validates and
    // must not be run through it. Its structural invariants are checked
    // directly instead, then each side is recursively asserted well-formed
    // (a side is an ordinary structured-or-custom figure, never itself a
    // meanwhile — flat-only).
    if (f.subFigures.length < 2 || f.subFigures.length > kMaxMeanwhileSides) {
      fail(
        _repro(
          raw,
          iteration,
          label,
          'meanwhile container had ${f.subFigures.length} sides '
          '(must be 2..$kMaxMeanwhileSides)',
        ),
      );
    }
    for (final side in f.subFigures) {
      if (side.isMeanwhile) {
        fail(_repro(raw, iteration, label, 'meanwhile nested a meanwhile'));
      }
      _assertWellFormed(side, raw, iteration, label);
    }
  } else {
    // A STRUCTURED figure is only ever returned when it validates with no
    // error-severity issue (the parser falls back to custom otherwise), so this
    // must hold for every structured result the fuzzer can produce.
    final errors = contraTaxonomy
        .validateFigure(f)
        .where((issue) => issue.severity == ValidationSeverity.error)
        .toList();
    if (errors.isNotEmpty) {
      fail(
        _repro(
          raw,
          iteration,
          label,
          'structured figure "${f.move}" failed validation: $errors',
        ),
      );
    }
  }
}

// --- Reproducibility -------------------------------------------------------

/// A reproducible failure description: the seed, the iteration, and the exact
/// input rendered as code units (so a failing case can be reconstructed with
/// `String.fromCharCodes([...])` even when it contains invisible/garbage bytes).
String _repro(String raw, int iteration, String label, String what) {
  final units = raw.codeUnits.join(', ');
  return 'seed=0x${_seed.toRadixString(16)} $label #$iteration: $what\n'
      'input.length=${raw.length}\n'
      'input.codeUnits=[$units]';
}

// --- Generators ------------------------------------------------------------

/// Fixed seed → deterministic, reproducible exploration (mirrors the seeded
/// benchmarks). Changing it re-rolls the corpus, so keep it stable.
const int _seed = 0x5139;

/// Bounded iteration count: large enough to be a meaningful property sweep,
/// small enough to keep `dart test` fast. NOT the audit's throwaway 200k.
const int _iterations = 4000;

/// Real contra move / role vocabulary, so a fraction of generated lines land
/// on (or near) the recognizer's structured path instead of always degrading
/// to custom — exercising the validate-or-fallback branch too.
const List<String> _vocab = [
  'balance',
  'swing',
  'circle',
  'left',
  'right',
  'star',
  'allemande',
  'do si do',
  'do-si-do',
  'dosido',
  'gypsy',
  'gyre',
  'chain',
  'courtesy turn',
  'face',
  'arky',
  'ladies',
  'gentlemen',
  'neighbor',
  'neighbors',
  'partner',
  'partners',
  'forward',
  'back',
  'long lines',
  'hey',
  'half hey',
  'half',
  'petronella',
  'promenade',
  'pass through',
  'california twirl',
  'box the gnat',
  'roll away',
  'ring',
  'shoulder round',
  'wave',
  'ocean wave',
  'and',
  '&',
  'the',
  'once',
  'twice',
  '1/2',
  '3/4',
  '1',
  '2',
  '3',
  '4',
  'places',
  'and swing',
  'once and a half',
];

/// Structural punctuation the split/scrub logic treats specially.
const List<String> _punct = [
  ';',
  ';;',
  '||',
  '|',
  '(',
  ')',
  '[',
  ']',
  '&',
  '/',
  ':',
  ',',
  '.',
  '-',
  '(PR)',
  '(PR;WL;NR;ML)',
  '()',
  '[]',
];

/// Whitespace variants (collapsed by the scrub).
const List<String> _whitespace = [
  ' ',
  '  ',
  '\t',
  '\n',
  '\r',
  '\r\n',
  '\u00a0',
];

/// Invisible / format / bidi-override code points the sanitizer strips — an
/// attacker might smuggle these mid-token to defeat move normalisation.
const List<int> _sneakyChars = [
  0x200b, // zero-width space
  0x200c, // zero-width non-joiner
  0x200d, // zero-width joiner
  0x202a, 0x202b, 0x202c, 0x202d, 0x202e, // bidi embeddings/overrides
  0x2066, 0x2067, 0x2068, 0x2069, // bidi isolates
  0xfeff, // BOM / zero-width no-break space
  0x00ad, // soft hyphen
];

String _randomFigureLine(Random rng) {
  final chunks = rng.nextInt(20); // 0..19 chunks (0 => empty line)
  final buf = StringBuffer();
  for (var i = 0; i < chunks; i++) {
    buf.write(_randomChunk(rng));
  }
  return buf.toString();
}

/// Like [_randomFigureLine] but strongly biased toward clause separators so the
/// compound-splitting paths are hit often.
String _randomCompoundLine(Random rng) {
  final clauses = 1 + rng.nextInt(4);
  final parts = <String>[];
  for (var i = 0; i < clauses; i++) {
    parts.add(_randomFigureLine(rng));
  }
  final sep = switch (rng.nextInt(5)) {
    0 => '; ',
    1 => ';',
    2 => ' || ',
    3 => ';;',
    _ => ' & ',
  };
  return parts.join(sep);
}

String _randomChunk(Random rng) {
  switch (rng.nextInt(6)) {
    case 0:
      return _vocab[rng.nextInt(_vocab.length)];
    case 1:
      return _punct[rng.nextInt(_punct.length)];
    case 2:
      return _whitespace[rng.nextInt(_whitespace.length)];
    case 3:
      return String.fromCharCode(
        _sneakyChars[rng.nextInt(_sneakyChars.length)],
      );
    case 4:
      return _randomNoise(rng);
    default:
      // A run of random ASCII printables + occasional structural punctuation
      // wedged against a vocab word (e.g. `swing(neighbors`), to fuzz the
      // tokeniser's boundary handling.
      return '${_vocab[rng.nextInt(_vocab.length)]}'
          '${_punct[rng.nextInt(_punct.length)]}'
          '${_asciiRun(rng)}';
  }
}

/// A run of arbitrary code points, including C0/C1 controls, astral-plane
/// characters, and lone surrogates — the harshest input for the scrub +
/// tokeniser. All values are within the valid [String.fromCharCode] domain
/// (0..0x10FFFF); values in 0xD800..0xDFFF intentionally yield unpaired
/// surrogates to prove they don't crash the parser.
String _randomNoise(Random rng) {
  final len = rng.nextInt(8);
  final units = <int>[];
  for (var i = 0; i < len; i++) {
    switch (rng.nextInt(5)) {
      case 0:
        units.add(rng.nextInt(0x20)); // C0 controls
      case 1:
        units.add(0x80 + rng.nextInt(0x20)); // C1 controls
      case 2:
        units.add(0xd800 + rng.nextInt(0x800)); // lone surrogate
      case 3:
        units.add(rng.nextInt(0x110000)); // any code point (incl. astral)
      default:
        units.add(0x20 + rng.nextInt(0x5f)); // ASCII printable
    }
  }
  return String.fromCharCodes(units);
}

String _asciiRun(Random rng) {
  final len = rng.nextInt(10);
  return String.fromCharCodes([
    for (var i = 0; i < len; i++) 0x20 + rng.nextInt(0x5f),
  ]);
}

/// Beat counts spanning the normal domain, the atypical-but-valid range, huge
/// values (which force a matched move back to custom), and negatives (which
/// must be normalised to 0 rather than throwing).
int _randomBeats(Random rng) => switch (rng.nextInt(6)) {
  0 => 0,
  1 => rng.nextInt(65), // 0..64 (the valid taxonomy domain)
  2 => 65 + rng.nextInt(1000), // atypically large → structured falls to custom
  3 => -1 - rng.nextInt(100), // negative → normalised to 0
  4 => 1 << 30, // very large
  _ => rng.nextInt(33),
};

/// Hand-authored adversarial inputs: real display-spoofing / lossy-split
/// hazards the generator might under-sample.
final List<String> _adversarialCorpus = [
  '',
  '   ',
  '\t\n\r ',
  '\u200b\u200c\u200d', // only zero-width chars → empty after sanitize
  '\u202egnirts a', // bidi override
  'gy\u200bpsy', // ZWSP smuggled mid-word to defeat gypsy normalisation
  'do\u00ad-si-do', // soft hyphen inside do-si-do
  'A;;B', // degenerate separator run
  'A; ;B',
  'A;',
  ';A',
  'A || B',
  'balance || swing || circle',
  'swing (PR;WL;NR;ML) neighbors', // bracketed pass-list must not split
  'circle left 3/4 [note (nested (deep))]',
  '((((((((((', // unbalanced brackets
  '))))))))))',
  '(((((((((())))))))))',
  'neighbors balance & swing; partners balance & swing; long lines forward & back',
  'a b c d e f g h i j k l m n o p q r s t u v w x y z',
  '💃🕺💃🕺 swing 💃', // astral-plane emoji around a real move
  'balance\u0000swing', // embedded NUL
  '\uFEFFcircle left', // leading BOM
  'shoulder round once and a half',
  // Taxonomy v23 `courtesy_turn`: the recognizer reads a trailing
  // `face <dancer>` clause by INDEX before taking the subject, so a line whose
  // `face` is last, doubled, or followed by a non-dancer must still degrade
  // cleanly rather than index past the end of the word list.
  'courtesy turn face',
  'partner courtesy turn face',
  'face courtesy turn face n2 face',
  'courtesy turn, face ',
  'n2 n3 n0 courtesy turn face n2 n3 n0',
  'partner courtesy turn clockwise counterclockwise clockwise',
  // Repeated annotations: the note reader is capped, so a long run must not
  // inflate the note or slow the parse.
  'partner courtesy turn ${'(x)' * 200}',
];
