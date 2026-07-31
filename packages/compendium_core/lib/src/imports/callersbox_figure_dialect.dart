import '../model/figure.dart';
import '../taxonomy/contra_taxonomy.dart';
import '../taxonomy/taxonomy.dart';
import '../validation/validation.dart';
import 'figure_parser.dart';
import 'figure_text_scrub.dart';

/// The CallersBox / The Caller's Box (TCB) figure-text **front-end**: the
/// source-specific grammar that lowers TCB's free-text dialect toward the
/// canonical single-line recognizer in `figure_parser.dart`.
///
/// This module owns the idioms that are UNAMBIGUOUSLY TCB notation — no other
/// source emits them — so relocating them here out of the shared recognizer is
/// behavior-preserving (the shared core no longer carries a TCB flavor):
/// - the top-level `;`-compound splitter ([parseFigureLines]) plus its
///   bracket-depth guards ([hasTopLevelSeparator]/`_splitTopLevel`), which
///   protect a hey's `(PR;WL;NR)` pass list from the `;` splitter;
/// - the hey pass-list decoder ([tcbFigureFrontEnd]'s pre-recognizer), TCB's
///   `(WR;NL;MR)` notation;
/// - the grand-right-and-left pass-list decoder
///   ([grandRightAndLeftFromPassList]), which reads the SAME people-code
///   notation and lowers TCB's compound shorthand onto a sequence of
///   `pull_by_dancers` figures; and
/// - the `()`/`[]` recognition-only annotation stripper (TCB appends `(NR)` /
///   `(W1-M2-W2-M1)` param/shoulder notes).
///
/// It is exposed as an independently-callable [FigureFrontEnd]
/// ([tcbFigureFrontEnd]) so a future free-text fan-out orchestrator can select
/// it by precedence without any adapter rework. The CallersBox adapter,
/// `free_text_entry`, and `reparse_custom_figures` all bind to it today (they
/// consumed the same TCB-flavored grammar before the relocation, so binding
/// keeps their behavior byte-identical).

/// The CallersBox/TCB front-end: the hey pass-list pre-recognizer plus the
/// `()`/`[]` recognition-only annotation strip. Pass this as the `frontEnd` to
/// [parseFigureLine]/[parseFigureLines] to recognize the full TCB dialect.
final FigureFrontEnd tcbFigureFrontEnd = FigureFrontEnd(
  preRecognizers: [_hey, _circulate],
  recognitionNormalize: _stripAnnotations,
);

/// Parses a compound figure line, splitting it on TOP-LEVEL `;` separators and
/// returning one [Figure] per clause. This is how CallersBox writes "do A; then
/// do B" compounds (e.g. `Pass through across (PR); turn alone`). A line with no
/// top-level `;` yields exactly what [parseFigureLine] would (a single-element
/// list, or an empty list when the line is empty after scrubbing), so callers
/// can route every line through this without changing single-line behaviour.
///
/// Fidelity guards (per the CallersBox dialect rulings):
/// - **All-or-nothing.** Every clause must independently structure to a taxonomy
///   move. If ANY clause degrades to custom (or is empty), the WHOLE line is
///   kept as a single custom figure carrying the original text — never
///   partially structured. Most `;` compounds pair a move with an
///   unstructurable formation/facing note (`…; form a wave of four`, `…; face
///   up`); structuring the move alone would drop the note, and structuring the
///   note would fabricate a move, so those correctly stay whole-custom.
/// - **`||` (simultaneity) fans into a `meanwhile` container (#591/#572).** A
///   line containing a top-level `||` (`A || B`) is split into one side per
///   `||`-clause and wrapped in [Figure.meanwhile] — see
///   [meanwhileFromDoublePipe] for the fidelity rules (shared container
///   beats, prefer-custom sides, side-count bound). Falls back to the
///   pre-#591 whole-custom behaviour only for a malformed/degenerate `||` run
///   or a hostile over-separated line (see [meanwhileFromDoublePipe]).
/// - **Lossless beats.** [deriveSections] sums each figure's `beats`
///   cumulatively to place section labels, so a split MUST preserve the source
///   line's TOTAL beats exactly — no more (double-count) and no less (section
///   underflow/drift). The source states only one combined total for the whole
///   compound (never per-move beats), so that total rides on the FIRST clause
///   and the remaining clauses are beats-absent. The cumulative beat total is
///   then byte-identical to the un-split compound, and nothing the source
///   actually stated is dropped or invented.
/// - **`Grand right and left (<pass list>)` decomposes (#295).** A line with NO
///   top-level separator is offered to [grandRightAndLeftFromPassList], which
///   lowers TCB's compound shorthand into one `pull_by_dancers` figure per
///   stated pass. It is attempted only on that no-separator fall-through, so a
///   line like `Grand right and left (N1R;N2L); face across` keeps its
///   whole-custom reading rather than silently dropping the trailing clause.
List<Figure> parseFigureLines(
  String rawText, {
  int beats = 0,
  bool progression = false,
  Taxonomy? taxonomy,
  String Function(String)? scrub,
  FigureFrontEnd frontEnd = canonicalFigureFrontEnd,
}) {
  Figure? whole() => parseFigureLine(
    rawText,
    beats: beats,
    progression: progression,
    taxonomy: taxonomy,
    scrub: scrub,
    frontEnd: frontEnd,
  );

  List<Figure> wholeAsList() {
    final f = whole();
    return f == null ? const [] : [f];
  }

  // Simultaneity (#591/#572): fan a top-level `||` line out into a
  // `meanwhile` container instead of keeping it whole-custom. Declines (falls
  // back to the pre-#591 whole-custom line) only for a malformed/degenerate
  // `||` run or an over-separated hostile line — see
  // `meanwhileFromDoublePipe` for the guards.
  if (hasTopLevelSeparator(rawText, '||')) {
    final meanwhile = meanwhileFromDoublePipe(
      rawText,
      beats: beats,
      progression: progression,
      taxonomy: taxonomy,
      scrub: scrub,
      frontEnd: frontEnd,
    );
    return meanwhile == null ? wholeAsList() : [meanwhile];
  }

  final clauses = _splitTopLevel(rawText, ';');
  if (clauses.length < 2) {
    // No top-level separator: this is the one place a single line may still fan
    // out into several figures — TCB's `Grand right and left (<pass list>)`
    // shorthand (#295). Declines (→ the ordinary whole-line reading) for any
    // line that is not a fully decodable grand right and left.
    final grandRightAndLeft = grandRightAndLeftFromPassList(
      rawText,
      beats: beats,
      progression: progression,
      taxonomy: taxonomy,
      scrub: scrub,
    );
    return grandRightAndLeft ?? wholeAsList();
  }
  // An empty clause means a malformed / degenerate separator run (`A;;B`,
  // `A; ;B`) or a leading/trailing `;` (`A;`). We do NOT silently drop it — that
  // would be a lossy split. Instead we decline to split and re-parse the whole
  // line: `A;` structures via the normal edge-`;` strip, while a genuinely
  // malformed `A;;B` reaches no recognizer and stays honestly custom.
  if (clauses.any((c) => c.isEmpty)) return wholeAsList();

  final parsed = <Figure>[];
  for (var i = 0; i < clauses.length; i++) {
    // Option A beats distribution: the source's combined total rides on the
    // first clause; every later clause is beats-absent so the cumulative total
    // equals the original compound (no double-count, no section drift).
    final clauseBeats = i == 0 ? beats : 0;
    final f = parseFigureLine(
      clauses[i],
      beats: clauseBeats,
      // Progression is a whole-line marker; conventionally the dance progresses
      // at the end of the sequence, so it rides on the last clause. (CallersBox
      // never sets it, so this is defensive.)
      progression: progression && i == clauses.length - 1,
      taxonomy: taxonomy,
      scrub: scrub,
      frontEnd: frontEnd,
    );
    // All-or-nothing: any clause that fails to structure (null/empty or custom)
    // collapses the whole line back to a single custom figure.
    if (f == null || f.isCustom) return wholeAsList();
    parsed.add(f);
  }
  return parsed;
}

/// Fans a top-level `||` (simultaneity) line out into a [Figure.meanwhile]
/// container (#591, part of the #572 epic): one side per `||`-clause, each
/// parsed independently via [parseFigureLine] and assembled into the
/// container. Public (not `_`-private) because it is shared by both the
/// PLURAL entry point above ([parseFigureLines]) and the SINGULAR reparse/
/// free-text-entry fan-out (`figure_front_end_fan_out.dart`'s
/// `parseFigureLineFanOut`), so an old whole-custom `||` figure gets the same
/// upgrade path a freshly-imported one does. Returns `null` when the line
/// should NOT fan out — the caller then falls back to its pre-#591
/// whole-custom behaviour — for any of:
/// - a malformed/degenerate `||` run (`A||`, `A||||B`) or a leading/trailing
///   `||`, mirroring the `;`-splitter's identical guard just above;
/// - more sides than [kMaxMeanwhileSides] allows — a **security bound**
///   (OWASP #591): a hostile line with many `||` separators degrades safely
///   to the unchanged whole-custom line rather than fanning out unboundedly
///   or throwing;
/// - a side that is empty after scrubbing (defensive; `_splitTopLevel`
///   already trims, so this is a residual guard against a side that is
///   entirely stripped by [scrubFigureText]'s sanitisation).
///
/// Fidelity rules for a successful fan-out:
/// - **Prefer-custom (locked #572 behaviour).** Each side is parsed via the
///   SAME per-side [parseFigureLine]/[frontEnd] used everywhere else, so a
///   side that fails to structure becomes its own custom sub-figure (already
///   scrubbed/sanitised — parity with #444/#611 is automatic, since
///   [parseFigureLine] always scrubs first) — it is kept inside the
///   container, never collapsed back to one whole-line custom.
/// - **Shared container beats.** The source states ONE combined total for
///   the whole `||` line (never per-side), so that total rides on the
///   **container's** `beats` ([Figure.meanwhile]'s `beats` parameter); every
///   side is beats-absent. This keeps [deriveSections]' cumulative beat total
///   byte-identical to the pre-#591 whole-custom line (the container counts
///   once, exactly like the single custom figure it replaces).
/// - **Flat only.** Sides are ordinary (non-meanwhile) figures from
///   [parseFigureLine], so [Figure.meanwhile]'s flat-only precondition can
///   never fail here — no `try/catch` is needed around the factory call.
Figure? meanwhileFromDoublePipe(
  String rawText, {
  required int beats,
  required bool progression,
  required Taxonomy? taxonomy,
  required String Function(String)? scrub,
  required FigureFrontEnd frontEnd,
}) {
  final sides = _splitTopLevel(rawText, '||');
  if (sides.length < 2 ||
      sides.length > kMaxMeanwhileSides ||
      sides.any((s) => s.isEmpty)) {
    return null;
  }
  final safeBeats = beats < 0 ? 0 : beats;
  final figures = <Figure>[];
  for (final side in sides) {
    final f = parseFigureLine(
      side,
      taxonomy: taxonomy,
      scrub: scrub,
      frontEnd: frontEnd,
    );
    // `f` is only `null` when `side` is empty after scrubbing (defensive —
    // decline the fan-out rather than drop a side; the caller's whole-line
    // fallback still preserves the full source text).
    if (f == null) return null;
    figures.add(f);
  }
  // Progression is a whole-line marker; it rides on the container itself
  // (there is no "last clause" — every side happens at once).
  return Figure.meanwhile(
    figures: figures,
    beats: safeBeats,
    progression: progression,
  );
}

/// Whether [sep] occurs at bracket depth 0 in [t] (outside any `()`/`[]`). Used
/// to find genuine clause separators while ignoring separators inside CallersBox
/// annotations like a hey's `(PR;WL;NR;ML)` pass list. Exposed so the CallersBox
/// adapter's compound reader can share the single implementation.
bool hasTopLevelSeparator(String t, String sep) {
  var depth = 0;
  for (var i = 0; i < t.length; i++) {
    final c = t.codeUnitAt(i);
    if (c == 0x28 || c == 0x5B) {
      depth++;
    } else if (c == 0x29 || c == 0x5D) {
      if (depth > 0) depth--;
    } else if (depth == 0 && t.startsWith(sep, i)) {
      return true;
    }
  }
  return false;
}

/// Splits [t] on top-level (bracket-depth-0) occurrences of [sep], trimming each
/// piece. Empty pieces are RETAINED (not dropped) so the caller can detect a
/// malformed/degenerate separator run and decline to split rather than lose a
/// clause. `(…)`/`[…]` annotations are treated as opaque so their internal
/// separators never split a line.
List<String> _splitTopLevel(String t, String sep) {
  final out = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < t.length; i++) {
    final c = t.codeUnitAt(i);
    if (c == 0x28 || c == 0x5B) {
      depth++;
    } else if (c == 0x29 || c == 0x5D) {
      if (depth > 0) depth--;
    } else if (depth == 0 && t.startsWith(sep, i)) {
      out.add(t.substring(start, i));
      start = i + sep.length;
      i += sep.length - 1;
    }
  }
  out.add(t.substring(start));
  return out.map((s) => s.trim()).toList();
}

// --- Recognition-only annotation strip --------------------------------------

/// Drops `()`/`[]` parenthetical annotations for RECOGNITION only (TCB appends
/// shoulder/param notes like `(NR)` or `(W1-M2-W2-M1)`). Applied inside the
/// shared `_normalize` via [FigureFrontEnd.recognitionNormalize], so a structured
/// match does NOT retain the bracketed text while the custom fallback — which
/// runs on the un-normalized scrubbed text — still keeps its annotation verbatim.
String _stripAnnotations(String lowercased) => lowercased
    .replaceAll(RegExp(r'\([^)]*\)'), ' ')
    .replaceAll(RegExp(r'\[[^\]]*\]'), ' ');

// --- Shared primitives the hey decoder needs --------------------------------
//
// Local copies of two trivial, stable primitives from `figure_parser.dart`
// (`_stripEdgePunct`, the filler set): duplicated here so the shared core need
// not widen its public surface for this source-specific decoder. Kept
// byte-identical to the core's definitions.

String _stripEdgePunct(String w) =>
    w.replaceAll(RegExp(r'^[.,;:!]+'), '').replaceAll(RegExp(r'[.,;:!]+$'), '');

const Set<String> _filler = {'your', 'the', 'a', 'an'};

// --- Hey (TCB pass-list) recognizer ------------------------------------------
//
// TCB writes heys as an optional fraction plus a `;`-separated pass list inside
// parentheses: "Hey 1/2 (WR;PL;MR;N2L~)", "Full hey (ML;PR)". This is the ONE
// recognizer that reads parenthetical content, because the pass list is the
// hey's structured payload rather than a droppable annotation. It runs as the
// front-end's pre-recognizer (BEFORE the shared `_normalize` strips the
// parentheses) and decodes onto the existing `hey` MoveDef:
//   * length   <- the fraction (default `half` when unspecified),
//   * pass1     <- the *who* of the 1st pass code,
//   * shoulder  <- the initial-pass shoulder (position-parity base; see below),
//   * pass2     <- the *who* of the 2nd pass code (else the MoveDef default
//                  `unspecified`),
//   * rico1..4  <- ricochet flags, assigned SEQUENTIALLY to the 1st/2nd/3rd/4th
//                  same-role center pass (the odd pass-list positions), capped
//                  by what the hey length can physically reach.
// The `~` partial-last-pass marker is dropped (informational only — not
// representable, ratified). Any token the decoder cannot fully account for
// forces `null` -> the custom fallback (parse-never-fails / prefer-custom).

/// TCB pass-list people codes -> canonical dancer set (TCB glossary, see
/// docs/research/callersbox.md). Post-scrub these compact codes survive intact
/// (they are not word-boundary role terms), so map them here. Shared by the hey
/// decoder ([_hey]) and the grand-right-and-left decoder
/// ([grandRightAndLeftFromPassList]) — TCB uses ONE people-code notation for
/// both, so there is exactly one map.
///
/// A code with no entry here is NOT approximated: the decoder that reads it
/// declines the whole line to custom (prefer-custom / never fabricate). The
/// deliberate omissions, per `Glossary.htm`:
/// - `C1`/`C2`/`C3` — the glossary's *"Corners (square)"* are a DIFFERENT
///   concept from its separate *"First/second corners"* entry ("First corners
///   are man one and woman two"), which is what [ParamVocab]'s
///   `firstCorners`/`secondCorners` model. C1 is "the non-partner next to you",
///   C2 "the person across from you", C3 "the remaining person" — a square/
///   four-face-four relationship the taxonomy has no token for.
/// - `P2`…`P6`, `P0`, `P-n` — a mixer's *future/previous* partners ("The next
///   partner in your direction of progression is P2"); no vocabulary token.
/// - `N5`+, `N-1`, `N-2`, `S3`+, `S-n` — beyond the modelled neighbor/shadow
///   depth.
/// - `Ph*` (phantoms), `TB*` (trail buddy), `SR*` (same-role), and bare `R`/`L`
///   (states a hand but no dancer at all).
const Map<String, String> _tcbPassPeople = {
  'm': 'role1s',
  'w': 'role2s',
  'p': 'partners',
  // Glossary (Partners (mixers)): "Your current partner is P1." So `P1` is the
  // same person the bare `P` names.
  'p1': 'partners',
  'n': 'neighbors',
  'n0': 'prevNeighbors',
  // N1 is the current neighbor (glossary: callersbox.md L51; mirrors the
  // general Tier-B role map's `'n1': 'neighbors'`). Without it, a pass code
  // like `N1L` fails to decode and drops the whole hey to custom (#308).
  'n1': 'neighbors',
  'n2': 'nextNeighbors',
  'n3': 'thirdNeighbors',
  'n4': 'fourthNeighbors',
  's': 'shadows',
  // Glossary (Shadows): "Shadow S1 is the first shadow you encounter one
  // hands-four away from your partner. S2 is one hands-four beyond that" — so
  // `S1` is the bare `S`, and `S2` is the taxonomy's `secondShadows`.
  's1': 'shadows',
  's2': 'secondShadows',
  '1': 'ones',
  '2': 'twos',
};

/// A hey fraction token -> `length`. Absent => `half` (ratified default). The
/// length is read from the FRACTION, not the pass count (officially ambiguous).
const Map<String, String> _heyLength = {
  '1/4': 'lessThanHalf',
  '1/2': 'half',
  '3/4': 'betweenHalfAndFull',
  'full': 'full',
  'whole': 'full',
};

/// The highest reachable ricochet slot for a hey [length]. Ricochets fall on
/// the same-role center passes, and how far a hey progresses caps which ones
/// can occur: each named length reaches one more slot than the previous —
/// `lessThanHalf` → rico1, `half` (incl. the unspecified default) → rico2,
/// `betweenHalfAndFull` → rico3, `full` → rico4 (the "whole" input token is
/// decoded to `full` before it reaches here). A ricochet whose positional slot
/// exceeds this cap is an internal contradiction (e.g. a rico3 in a half hey)
/// and forces the custom fallback — we never infer length from the pass count,
/// so the stated/default length is authoritative.
int _heyMaxRicoSlot(String length) {
  switch (length) {
    case 'lessThanHalf':
      return 1;
    case 'betweenHalfAndFull':
      return 3;
    case 'full':
      return 4;
    case 'half':
    default:
      return 2;
  }
}

String _otherShoulder(String s) => s == 'right' ? 'left' : 'right';

/// TCB writes a single circulate as a colon-headed line whose definition is the
/// component cross/loop path: `Circulate: women cross, men loop right`. TCB
/// never emits the literal "box circulate" and, in the corpus, ~95% of these
/// lines are immediately preceded by a balance (`Balance ring` / `Balance wave
/// of four`), i.e. the balance-and-box-circulate figure. This pre-recognizer
/// maps such a line onto [box_circulate]; the CallersBox cross-line merge then
/// folds a preceding balance line into `balance: true` (box_circulate is a
/// balance-merge target). The definition after the colon is the move's
/// decomposition (not extra choreography), so — mirroring the compound-figure
/// convention — it is preserved verbatim in the figure `note`, never dropped.
///
/// Conservative guards: the head before the colon must be EXACTLY `circulate`
/// (so `box circulate`, `diagonal circulate`, `column circulate 2`, … all
/// decline here and fall through), and the definition must be non-empty. Runs
/// on the scrubbed text (roles already canonicalized) like the other
/// pre-recognizers.
FigureMatch? _circulate(String scrubbed) {
  final colon = scrubbed.indexOf(':');
  if (colon == -1) return null;
  final head = scrubbed.substring(0, colon).trim().toLowerCase();
  final def = scrubbed.substring(colon + 1).trim();
  if (def.isEmpty || head != 'circulate') return null;
  return FigureMatch('box_circulate', note: def);
}

FigureMatch? _hey(String scrubbed) {
  final lower = scrubbed.toLowerCase();
  // dolphin_hey is a DIFFERENT move; never match it here.
  if (lower.contains('dolphin')) return null;

  // A hey is only structured when it carries a parenthetical pass list — that
  // is the sole source of pass1/shoulder. No pass list -> custom.
  final open = lower.indexOf('(');
  if (open == -1) return null;
  final close = lower.indexOf(')', open + 1);
  if (close == -1) return null;
  final passText = lower.substring(open + 1, close);
  final outside = '${lower.substring(0, open)} ${lower.substring(close + 1)}';

  // The non-paren remainder must be exactly {hey, optional fraction,
  // optional leading "on left/right diagonal", filler}; anything else (a
  // trailing move, a second parenthetical, ...) -> custom.
  final outWords = outside
      .replaceAll('½', ' 1/2 ')
      .replaceAll('¼', ' 1/4 ')
      .replaceAll('¾', ' 3/4 ')
      .split(RegExp(r'\s+'))
      .map(_stripEdgePunct)
      .where((w) => w.isNotEmpty)
      .toList();

  // A leading "on [the] left/right diagonal" sets the hey's `dir` (the taxonomy
  // direction domain carries leftDiagonal/rightDiagonal). Consumed up front so
  // its tokens don't trip the strict remainder check below.
  String? dir;
  if (outWords.isNotEmpty && outWords.first == 'on') {
    var i = 1;
    if (i < outWords.length && outWords[i] == 'the') i++;
    if (i + 1 < outWords.length &&
        (outWords[i] == 'left' || outWords[i] == 'right') &&
        outWords[i + 1] == 'diagonal') {
      dir = outWords[i] == 'left' ? 'leftDiagonal' : 'rightDiagonal';
      outWords.removeRange(0, i + 2);
    }
  }

  var sawHey = false;
  var length = 'half';
  var sawFraction = false;
  for (final word in outWords) {
    if (word == 'hey') {
      sawHey = true;
      continue;
    }
    // "Ricochet hey" names the variant; the actual ricochet flags are decoded
    // from the pass list, so a leading/standalone "ricochet" word here carries
    // no extra structure and is ignored.
    if (word == 'ricochet') continue;
    if (_filler.contains(word)) continue;
    final len = _heyLength[word];
    if (len != null) {
      if (sawFraction) return null; // two fractions -> ambiguous
      length = len;
      sawFraction = true;
      continue;
    }
    return null; // unexplained token -> custom
  }
  if (!sawHey) return null;

  final cells = passText.split(';').map((c) => c.trim()).toList();
  if (cells.isEmpty || cells.any((c) => c.isEmpty)) return null;

  final params = <String, Object?>{'length': length, 'dir': ?dir};
  final maxRicoSlot = _heyMaxRicoSlot(length);
  String? shoulderBase; // the shoulder implied at ODD positions.
  String? pass1;
  String? pass2;

  for (var i = 0; i < cells.length; i++) {
    final position = i + 1; // 1-based pass position.
    final cell = cells[i].replaceAll('~', '').trim(); // drop the `~` marker.
    if (cell.isEmpty) return null;

    if (cell.endsWith('ricochet')) {
      final people = cell.substring(0, cell.length - 'ricochet'.length).trim();
      final who = _tcbPassPeople[people];
      // Only center same-role dancers ricochet — never neighbor/partner/etc.
      if (who != 'role1s' && who != 'role2s') return null;
      // The same-role center passes are the odd pass-list positions; enumerate
      // them in order (pos1 = 1st, pos3 = 2nd, ...) to pick the ricochet slot.
      // An even position is not a center pass, so it can't ricochet.
      if (position.isEven) return null;
      final slotIndex = (position + 1) ~/ 2; // 1st/2nd/3rd/4th center pass.
      // The length must physically reach this slot (e.g. a half hey has at
      // most two same-role passes, so rico3/rico4 are unreachable → custom).
      if (slotIndex > maxRicoSlot) return null;
      params['rico$slotIndex'] = true;
      if (position == 1) pass1 = who;
      continue;
    }

    // Normal pass code: a trailing R/L shoulder plus a people-code prefix.
    final shoulderChar = cell[cell.length - 1];
    final shoulder = shoulderChar == 'r'
        ? 'right'
        : shoulderChar == 'l'
        ? 'left'
        : null;
    if (shoulder == null) return null;
    final who = _tcbPassPeople[cell.substring(0, cell.length - 1)];
    if (who == null) return null;

    // Shoulders alternate by position parity: odd positions share the base
    // shoulder, even positions the opposite. Derive the base from the first
    // shouldered code, then require every later code to agree — a pass list
    // that does not alternate is malformed/ambiguous -> custom.
    final impliedBase = position.isOdd ? shoulder : _otherShoulder(shoulder);
    if (shoulderBase == null) {
      shoulderBase = impliedBase;
    } else if (shoulderBase != impliedBase) {
      return null;
    }

    if (position == 1) pass1 = who;
    if (position == 2) pass2 = who;
  }

  if (shoulderBase == null) return null; // no shouldered code -> can't decode.
  if (pass1 == null) return null;

  params['pass1'] = pass1;
  params['shoulder'] = shoulderBase;
  if (pass2 != null) params['pass2'] = pass2;
  return FigureMatch('hey', params: params);
}

// --- Grand right and left (TCB pass-list) decomposition (#295) ---------------

/// Upper bound on the number of passes a `Grand right and left (<pass list>)`
/// line may fan out into.
///
/// The longest attested pass list in the full TCB corpus is 8 passes, so this
/// is generous for real choreography. It exists as a **security bound** (OWASP,
/// mirroring [kMaxMeanwhileSides]): imported figure text is untrusted, and a
/// hostile line carrying hundreds of `;`-separated cells must degrade to the
/// unchanged whole-custom line rather than fanning out unboundedly.
const int kMaxPassListCells = 12;

/// The shorthand name preserved on the FIRST emitted pass. The decomposition
/// represents every fact the pass list states, but "grand right and left" is
/// itself the caller-meaningful name of the figure, so it is kept as a note
/// rather than silently dropped (mirroring the compound-figure convention,
/// which preserves the source decomposition in `Figure.note`).
const String _grandRightAndLeftNote = 'grand right and left';

/// Decomposes TCB's `Grand right and left (<pass list>)` shorthand into one
/// [Figure] per stated pass — a `pull_by_dancers` carrying that pass's dancer
/// (`who`) and stated `hand` — or returns `null` to leave the line alone
/// (→ the caller's ordinary whole-line/custom reading).
///
/// **Why a sequence and not a move (#295).** ContraDB transcribes the SAME
/// choreography as consecutive pull-bys and carries no grand-right-and-left
/// figure at all. *334* by Diane Silver is the decisive side-by-side: TCB
/// #10042 A2 writes `(4) Grand right and left (N3R;N2L)` where ContraDB #3403
/// A2 writes `[2] 3rd neighbors pull by right` + `[2] 2nd neighbors pull by
/// left`. So the shorthand is lowered onto the `pull_by_dancers` move the
/// taxonomy already has — no new taxonomy move, no version bump.
///
/// **Strictness (conservative / prefer-custom).** Runs on the SCRUBBED text
/// before the front-end's annotation strip, like the hey decoder, because the
/// pass list is the structured payload rather than a droppable annotation.
/// Declines — returning `null`, never a partial structuring — when:
/// - there is no `(...)` pass list, or fewer than 2 / more than
///   [kMaxPassListCells] non-empty cells;
/// - the text OUTSIDE the pass list is not exactly the words `grand right and
///   left` (modulo filler). This is what keeps the corpus's genuinely different
///   figures custom: `Progressive grand right and left …` (its own glossary
///   entry), `Same-role grand right and left …`, `… to place`, a `[with N2]`
///   qualifier, a second parenthetical (`(ones and twos begin with neighbor…)`)
///   or any other leftover prose;
/// - any cell is not `<people-code><R|L>` with the people code present in
///   [_tcbPassPeople] — square corners (`C1`..`C3`), mixer partner series
///   (`P2`..`P6`), out-of-range neighbors/shadows, phantoms, trail buddies and
///   bare `R`/`L` (a hand with no dancer) therefore all stay custom rather than
///   being approximated onto a token that means something else;
/// - [beats] does not divide evenly by the pass count. An even split is
///   arithmetic the source corroborates (TCB's 4 beats over 2 passes == ContraDB's
///   2 + 2); an UNEVEN split would invent a per-pass duration nothing states, so
///   the line stays custom instead. Exactly one corpus line hits this
///   (`(8) Grand right and left (N0L;N1R;N2L)`);
/// - any emitted figure fails taxonomy validation (defensive).
///
/// **Lossless beats.** The per-pass share is `beats ~/ passCount` with an exact
/// divisibility precondition, so the emitted figures' beats sum EXACTLY to the
/// source line's total and [deriveSections]' cumulative section placement is
/// unchanged. A beats-absent line (`beats == 0`) divides trivially and yields
/// beats-absent figures.
List<Figure>? grandRightAndLeftFromPassList(
  String rawText, {
  required int beats,
  required bool progression,
  required Taxonomy? taxonomy,
  required String Function(String)? scrub,
}) {
  try {
    final scrubbed = (scrub ?? scrubFigureText)(rawText);
    if (scrubbed.isEmpty) return null;
    final passes = _decodeGrandRightAndLeftPasses(scrubbed);
    if (passes == null) return null;

    final safeBeats = beats < 0 ? 0 : beats;
    if (safeBeats % passes.length != 0) return null;
    final share = safeBeats ~/ passes.length;

    final tax = taxonomy ?? contraTaxonomy;
    final figures = <Figure>[];
    for (var i = 0; i < passes.length; i++) {
      final figure = Figure(
        move: 'pull_by_dancers',
        params: {
          'who': passes[i].who,
          'hand': passes[i].hand,
          if (share > 0) 'beats': share,
        },
        note: i == 0 ? _grandRightAndLeftNote : null,
        // Progression is a whole-line marker; conventionally the dance
        // progresses at the end of the sequence, so it rides on the last pass.
        progression: progression && i == passes.length - 1,
      );
      final hasError = tax
          .validateFigure(figure)
          .any((issue) => issue.severity == ValidationSeverity.error);
      if (hasError) return null;
      figures.add(figure);
    }
    return figures;
  } catch (_) {
    // Parse-never-fails: any unexpected shape leaves the line to the caller's
    // whole-line/custom reading.
    return null;
  }
}

/// One decoded pass: the dancer set met and the hand used.
class _GrandRightAndLeftPass {
  const _GrandRightAndLeftPass(this.who, this.hand);
  final String who;
  final String hand;
}

/// Decodes the pass list of a `Grand right and left (...)` line, or `null` when
/// the line is not an exact, fully-mappable grand right and left. See
/// [grandRightAndLeftFromPassList] for the rules.
List<_GrandRightAndLeftPass>? _decodeGrandRightAndLeftPasses(String scrubbed) {
  final lower = scrubbed.toLowerCase();
  final open = lower.indexOf('(');
  if (open == -1) return null;
  final close = lower.indexOf(')', open + 1);
  if (close == -1) return null;

  // The non-paren remainder must be EXACTLY "grand right and left" (+ filler);
  // a second parenthetical, a `[...]` qualifier or any other prose lands here
  // as unexplained words and declines the whole line.
  final outside = '${lower.substring(0, open)} ${lower.substring(close + 1)}';
  final words = outside
      .split(RegExp(r'\s+'))
      .map(_stripEdgePunct)
      .where((w) => w.isNotEmpty && !_filler.contains(w))
      .toList();
  if (words.length != _grandRightAndLeftWords.length) return null;
  for (var i = 0; i < words.length; i++) {
    if (words[i] != _grandRightAndLeftWords[i]) return null;
  }

  final cells = lower
      .substring(open + 1, close)
      .split(';')
      .map((c) => c.trim())
      .toList();
  if (cells.length < 2 || cells.length > kMaxPassListCells) return null;

  final passes = <_GrandRightAndLeftPass>[];
  for (final cell in cells) {
    if (cell.isEmpty) return null;
    final handChar = cell[cell.length - 1];
    final hand = handChar == 'r'
        ? 'right'
        : handChar == 'l'
        ? 'left'
        : null;
    if (hand == null) return null;
    // A bare `R`/`L` cell states a hand but no dancer, so there is nothing to
    // put in `who` — the empty people code is absent from the map and declines.
    final who = _tcbPassPeople[cell.substring(0, cell.length - 1)];
    if (who == null) return null;
    passes.add(_GrandRightAndLeftPass(who, hand));
  }
  return passes;
}

const List<String> _grandRightAndLeftWords = ['grand', 'right', 'and', 'left'];
