import '../model/figure.dart';
import '../taxonomy/contra_taxonomy.dart';
import '../taxonomy/param_types.dart';
import '../taxonomy/taxonomy.dart';
import '../validation/validation.dart';
import 'figure_text_scrub.dart';
import 'structured_draft.dart';

/// Upper bound on a COMBINED [Figure.note] built by [combineFigureNotes].
///
/// Import text is untrusted (OWASP): each contributing part is already bounded
/// by its own producer (an annotation run by `_annotationRe`'s `{0,120}`, a
/// note-eligible `;` clause by `kMaxClauseNote`), so this only ever bites a
/// hostile line that stacks many parts. Generous by design — the longest
/// combined note the whole Caller's Box mirror produces is under 60 characters.
const int kMaxFigureNote = 400;

/// Combines two figure notes so that NEITHER is silently dropped.
///
/// Notes arrive from two independent producers and a figure can legitimately
/// carry both: a recognizer's own note (`chain`'s `to partner` target,
/// `right_left_through`'s `same-role`) and a note the caller layers on (a
/// CallersBox `()`/`[]` annotation, or a `;`-clause the splitter could not
/// structure). Resolving that with `existing ?? added` — as this code did
/// before — silently discards one of them; measured over the Caller's Box
/// mirror, that collision is live on 40 lines (`chain` 38, `courtesy_turn` 2,
/// e.g. `Ladies chain to partner; face down`).
///
/// [existing] LEADS the joined result: it is the recognizer's own note, which
/// is load-bearing choreography (`to partner` names the chain's target), while
/// [added] is commentary layered on afterwards. Blank/absent parts are dropped,
/// an [added] identical to [existing] is not duplicated, and the joined result
/// is truncated on a RUNE boundary to [kMaxFigureNote].
///
/// Only the JOINED result is truncated — a lone note passes through unchanged,
/// so this is provably behaviour-preserving everywhere a single note is in play.
/// Matches the `'; '` join and "original first" ordering of
/// `reparse_custom_figures.dart`'s note merge, so a figure's note reads the same
/// however it was assembled. Never throws.
String? combineFigureNotes(String? existing, String? added) {
  final left = _blankToNull(existing);
  final right = _blankToNull(added);
  if (left == null) return right;
  if (right == null || right == left) return left;
  return truncateOnRuneBoundary('$left; $right', kMaxFigureNote);
}

String? _blankToNull(String? s) {
  final trimmed = s?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// Truncates [text] to at most [maxLength] UTF-16 code units, cutting only on a
/// RUNE boundary.
///
/// `String.substring` cuts code units, so a naive cut can split a surrogate pair
/// and leave a lone surrogate in stored text. Shared by every bounded free-text
/// field the importers build (annotation notes, combined figure notes) so the
/// rune-safety rule has exactly one implementation. Never throws.
///
/// Walks runes with a [RuneIterator] and stops at the limit rather than
/// materialising `text.runes.toList()`. The list form is O(n) in the FULL input
/// length, which defeats the point of a bound on untrusted import text: a
/// hostile note would pay the whole allocation before being truncated. This form
/// is O([maxLength]) regardless of how long [text] is (OWASP).
String truncateOnRuneBoundary(String text, int maxLength) {
  if (maxLength <= 0) return '';
  if (text.length <= maxLength) return text;
  // `end` accumulates the code-unit length of the runes accepted so far, which
  // is exactly the safe cut point because runes are visited in order.
  var end = 0;
  final runes = RuneIterator(text);
  while (runes.moveNext()) {
    final next = end + (runes.current > 0xFFFF ? 2 : 1);
    if (next > maxLength) break;
    end = next;
  }
  return text.substring(0, end);
}

/// A move recognised by a source-specific front-end pre-recognizer: the taxonomy
/// [moveId] plus the params/note extracted from the text (never including
/// `beats`, which [parseFigureLine] layers on from the source line).
///
/// This is the public counterpart of the parser's internal recognizer result,
/// used by a [FigureFrontEnd]'s pre-recognizers (e.g. the CallersBox hey
/// decoder in `callersbox_figure_dialect.dart`) so they can live outside this
/// file without exposing the private recognizer machinery. [parseFigureLine]
/// validates it against the taxonomy exactly like an internal match, so an
/// invalid front-end match still degrades to a custom figure.
class FigureMatch {
  const FigureMatch(
    this.moveId, {
    this.params = const {},
    this.note,
    this.assumedSubject = false,
  });

  final String moveId;
  final Map<String, Object?> params;

  /// Optional free-text note preserved from the source when a detail cannot be
  /// expressed as a structured param.
  final String? note;

  /// Whether the subject in [params] was DEFAULTED (not stated by the source);
  /// propagated to [Figure.assumedSubject] (#460).
  final bool assumedSubject;
}

/// The source-specific seam feeding the canonical single-line recognizer. Each
/// free-text source (adapter) supplies its own front-end so `figure_parser.dart`
/// stays a source-neutral core with no `source == X` branches: the front-end
/// carries the dialect-specific handling that must NOT leak across sources.
///
/// Two hooks, applied in the same order the parser used to hard-code them:
/// - [preRecognizers] run FIRST, on the RAW scrubbed text (before `_normalize`),
///   so a recognizer whose structured payload lives inside parentheses (the TCB
///   hey pass list) reads it before annotations are stripped. The first non-null
///   result wins.
/// - [recognitionNormalize] runs inside `_normalize`, on the lowercased text,
///   for RECOGNITION only (e.g. the TCB `()`/`[]` annotation strip). The custom
///   fallback uses the un-normalized scrubbed text, so anything the hook removes
///   still survives verbatim on an unrecognised line.
///
/// [canonicalFigureFrontEnd] is the neutral default (no pre-recognizers, no
/// normalization) — the ContraDB-aligned canonical dialect. Concrete source
/// front-ends (`tcbFigureFrontEnd`, `contraDbHtmlFigureFrontEnd`,
/// `callersCompanionFigureFrontEnd`) are defined next to their adapters and are
/// independently callable, so a future free-text fan-out can select among them.
class FigureFrontEnd {
  const FigureFrontEnd({
    this.preRecognizers = const [],
    this.recognitionNormalize,
    this.declineToCustom,
  });

  /// Source-specific recognizers run before the shared ones, on raw scrubbed
  /// text. First non-null result wins.
  final List<FigureMatch? Function(String scrubbed)> preRecognizers;

  /// Optional recognition-only normalization applied to the lowercased text
  /// inside `_normalize` (does not affect the stored custom-fallback text).
  final String Function(String)? recognitionNormalize;

  /// Optional source-specific veto: when it returns true for a line, that line
  /// goes STRAIGHT to the custom fallback, skipping both the pre-recognizers
  /// and the shared ones.
  ///
  /// This exists because "delete the recognizer" is NOT how a front-end
  /// declines a move (taxonomy v26, #843). The shared recognizers in
  /// `figure_parser.dart` are source-neutral by design, so a grammar this
  /// front-end removes from its own dialect file can still be claimed by the
  /// shared layer — which is exactly what happened to ContraDB's
  /// `star promenade`, whose `who` means the CENTER role there and the pick-up
  /// relationship everywhere else. Structuring it would assert the wrong
  /// dancers, so it must not structure AT ALL for this source.
  ///
  /// Use sparingly, and only where a source's wording means something
  /// materially different from the shared reading. When it fires the line takes
  /// the custom fallback with `CustomOrigin.importGap` — the same outcome as
  /// any unrecognised line — carrying the SCRUBBED text.
  ///
  /// Scrubbed, not verbatim: [scrubFigureText] has already canonicalized role
  /// terms by then, so `Gentlespoons star promenade right 1` is stored as
  /// `role1s star promenade right 1`. That is a user-visible difference, and it
  /// applies to every custom figure, not just this path. What IS preserved
  /// against the structured reading is everything `recognitionNormalize`
  /// removes — annotations and the like — which is the precise sense in which
  /// [recognitionNormalize] and [parseFigureLine] use the word "verbatim".
  final bool Function(String scrubbed)? declineToCustom;
}

/// The neutral canonical front-end: no source-specific handling. This is the
/// ContraDB-aligned baseline the shared recognizer targets.
const FigureFrontEnd canonicalFigureFrontEnd = FigureFrontEnd();

/// Parses a single free-text figure line into a structured taxonomy [Figure]
/// when it can do so *confidently*, and otherwise degrades to a [customFigure]
/// carrying the (scrubbed) text. This is the ONE parser every free-text import
/// adapter routes its figure lines through, so a line reads the same no matter
/// which source it came from.
///
/// ## Contract
/// - **Parse-never-fails.** Unrecognised text ALWAYS becomes a custom figure;
///   the parser never throws and never drops text (`docs/design/imports.md`).
///   Any unexpected error while recognising falls back to custom.
/// - **Conservative matching.** A line is only structured when it maps cleanly
///   onto exactly one taxonomy move AND the whole line is accounted for — any
///   leftover, unexplained prose forces the custom fallback. A wrong structured
///   match silently misrepresents choreography, which is worse than an honest
///   custom figure: when in doubt, custom.
/// - **Validated.** Every candidate structured figure is checked against
///   [taxonomy]; if it produces any error-severity [ValidationIssue] (unknown
///   move/param, out-of-domain value) it is discarded in favour of custom.
///   Atypical-beat *warnings* are allowed through (source beats are preserved).
///
/// The parser runs AFTER [scrub] (dialect canonicalization + the
/// `gypsy → shoulder round` safety net), so gendered role terms have already
/// become canonical `role1`/`role2` tokens by the time recognition runs.
///
/// Returns `null` only when the line is empty after scrubbing (nothing to
/// store) — callers skip those, matching the previous per-adapter behaviour.
///
/// [beats] and [progression] come from the source line and are preserved on the
/// resulting figure (structured or custom). Section labels (e.g. `A1`) are NOT
/// stored in the figure text: they are derived from cumulative beats by the
/// domain model (`deriveSections`) and the beat count is already a structured
/// field, so embedding `'$label: $text'` would duplicate structured data that
/// can drift out of sync. Both the structured and custom paths therefore carry
/// clean text only.
Figure? parseFigureLine(
  String rawText, {
  int beats = 0,
  bool progression = false,
  Taxonomy? taxonomy,
  String Function(String)? scrub,
  FigureFrontEnd frontEnd = canonicalFigureFrontEnd,
}) {
  final scrubFn = scrub ?? scrubFigureText;
  final tax = taxonomy ?? contraTaxonomy;
  // Negative beats are meaningless; normalise to 0 (treated as absent) so the
  // parse-never-fails contract holds even for malformed source beats —
  // `customFigure` throws on a negative beat count.
  final safeBeats = beats < 0 ? 0 : beats;

  final scrubbed = scrubFn(rawText);
  if (scrubbed.isEmpty) return null;

  Figure fallback() => customFigure(
    scrubbed,
    beats: safeBeats,
    progression: progression,
    origin: CustomOrigin.importGap,
  );

  try {
    // A source-specific veto runs BEFORE any recognizer, including this
    // front-end's own pre-recognizers: the point is that the line must not
    // structure at all for this source. Inside the try so a throwing predicate
    // degrades to custom like everything else (parse-never-fails).
    if (frontEnd.declineToCustom?.call(scrubbed) ?? false) return fallback();
    final match = _recognize(scrubbed, frontEnd);
    if (match == null) return fallback();

    final params = <String, Object?>{
      ...match.params,
      if (safeBeats > 0) 'beats': safeBeats,
    };
    final candidate = Figure(
      move: match.moveId,
      params: params,
      note: match.note,
      progression: progression,
      assumedSubject: match.assumedSubject,
    );
    final hasError = tax
        .validateFigure(candidate)
        .any((i) => i.severity == ValidationSeverity.error);
    return hasError ? fallback() : candidate;
  } catch (_) {
    return fallback();
  }
}

/// A recognised move: its taxonomy [moveId] and the params extracted from the
/// text (never including `beats`, which the caller layers on from the source).
class _Match {
  const _Match(
    this.moveId, [
    this.params = const {},
    this.note,
    this.assumedSubject = false,
  ]);
  final String moveId;
  final Map<String, Object?> params;

  /// Optional free-text note preserved from the source when a detail cannot be
  /// expressed as a structured param (e.g. chain's "to neighbor" target).
  final String? note;

  /// Whether the subject in [params] (`who`) was DEFAULTED by the recognizer
  /// because the source line omitted it, rather than stated by the source. The
  /// caller propagates this to [Figure.assumedSubject] so the defaulted subject
  /// renders as a non-authoritative assumption, never as fabricated fact (#460).
  final bool assumedSubject;
}

/// Resolves [text] to EXACTLY ONE canonical dancer-set token, or `null` when it
/// names none, names more than one, or carries any other word.
///
/// The strict "nothing left over" rule is what makes this safe to point at
/// source fragments a recognizer did not itself consume: a phrase we only
/// partly understand resolves to `null` rather than to its first dancer word.
/// Exposed for front-ends that must read a dancer out of source text the shared
/// grammar never sees — the CallersBox gate annotation (`(ones forward)`) is
/// stripped before `_normalize`, so its pre-recognizer resolves the dancer here
/// instead of duplicating [_dancerWords].
///
/// Runs on POST-SCRUB text, so gendered terms have already become `role1`/
/// `role2` tokens. Never throws.
String? resolveDancerSetPhrase(String text) {
  final w = _normalize(text, null);
  if (w.isEmpty) return null;
  final token = _takeDancer(w);
  if (token == null) return null;
  _dropFiller(w);
  return w.isEmpty ? token : null;
}

/// Attempts to recognise [scrubbed] as one covered move using ONLY the shared,
/// source-neutral recognizers — no front-end pre-recognizers, so it can never
/// recurse back into a caller.
///
/// Exists for front-ends that must PRE-PROCESS a line and then delegate: the
/// CallersBox gate pre-recognizer lifts the `(ones forward)` annotation out
/// before `_normalize` would drop it, then hands the remainder here rather than
/// duplicating the gate grammar. [recognitionNormalize] is applied exactly as
/// `_normalize` would apply a front-end's own hook.
///
/// Returns `null` when no shared recognizer accounts for the whole line.
FigureMatch? recognizeSharedFigureLine(
  String scrubbed, {
  String Function(String)? recognitionNormalize,
}) {
  final words = _normalize(scrubbed, recognitionNormalize);
  if (words.isEmpty) return null;
  for (final recognizer in _recognizers) {
    final match = recognizer(List<String>.of(words));
    if (match != null) {
      return FigureMatch(
        match.moveId,
        params: match.params,
        note: match.note,
        assumedSubject: match.assumedSubject,
      );
    }
  }
  return null;
}

/// Attempts to recognise [scrubbed] as one covered move. Returns `null` when no
/// recognizer accounts for the whole line (→ custom fallback).
_Match? _recognize(String scrubbed, FigureFrontEnd frontEnd) {
  // Source-specific pre-recognizers (supplied by the caller's front-end) run
  // FIRST and on the RAW scrubbed text, not the normalized word list: a move
  // whose structured payload lives INSIDE parentheses (the TCB hey pass list)
  // must read it before `_normalize`'s annotation strip removes it. The
  // canonical core carries none of these, so it stays source-neutral. Each is
  // highly specific (e.g. the hey decoder requires the `hey` anchor plus a fully
  // decodable pass list and rejects `dolphin hey`), so running them ahead of the
  // generic recognizers cannot shadow them.
  for (final pre in frontEnd.preRecognizers) {
    final m = pre(scrubbed);
    if (m != null) {
      return _Match(m.moveId, m.params, m.note, m.assumedSubject);
    }
  }

  final words = _normalize(scrubbed, frontEnd.recognitionNormalize);
  if (words.isEmpty) return null;

  for (final recognizer in _recognizers) {
    final match = recognizer(List<String>.of(words));
    if (match != null) return match;
  }
  return null;
}

/// Lowercases, applies the front-end's optional recognition-only normalization
/// (e.g. the CallersBox `()`/`[]` annotation strip), maps `&`→`and` and
/// `thru`→`through`, folds the common unicode halves/quarters, strips
/// surrounding punctuation, and splits into words.
///
/// [recognitionNormalize] affects RECOGNITION only: a structured match does NOT
/// retain whatever it removed, but the *custom fallback* runs on the
/// un-normalized scrubbed text, so a line that fails recognition keeps that
/// content verbatim in the custom figure (e.g. a TCB annotation survives).
List<String> _normalize(
  String text,
  String Function(String)? recognitionNormalize,
) {
  var s = text.toLowerCase();
  if (recognitionNormalize != null) s = recognitionNormalize(s);
  s = s
      .replaceAll('&', ' and ')
      .replaceAll('½', ' 1/2 ')
      .replaceAll('¼', ' 1/4 ')
      .replaceAll('¾', ' 3/4 ');
  final words = s
      .split(RegExp(r'\s+'))
      .map(_stripEdgePunct)
      .where((w) => w.isNotEmpty)
      .map((w) => w == 'thru' ? 'through' : w)
      .toList();
  return words;
}

String _stripEdgePunct(String w) =>
    w.replaceAll(RegExp(r'^[.,;:!]+'), '').replaceAll(RegExp(r'[.,;:!]+$'), '');

/// Splits [t] on the FIRST top-level (bracket-depth-0, outside any `()`/`[]`)
/// whole-word match of [word], returning exactly two trimmed pieces
/// `[before, after]`, or `null` when [word] has no top-level match.
///
/// This is the word-boundary counterpart of `hasTopLevelSeparator`/
/// `_splitTopLevel` in `callersbox_figure_dialect.dart` (which match a
/// literal character run, e.g. `||`/`;`): a connective WORD — ContraDB's
/// `while`/`whiles` (#591, part of the #572 "meanwhile" epic) — needs a word
/// boundary rather than a literal-substring match, because `while` is itself
/// a substring of `whiles` and a naive literal split would cut `whiles`
/// mid-word. Shared here (rather than duplicating the bracket-depth scan a
/// third time) since both dialect files already import this module.
///
/// Only the FIRST top-level match splits — a two-sided line is what every
/// surveyed source phrasing produces (no dialect chains two "while"s in one
/// line), so this always yields exactly 2 pieces when it returns non-null,
/// which is exactly what [Figure.meanwhile] needs at minimum. `()`/`[]`
/// content is treated as opaque, so a connective word inside an annotation
/// is never treated as a clause boundary.
///
/// Linear in `t.length` (a single forward scan tracks bracket depth
/// incrementally alongside the match stream), NOT per-match — [t] is
/// untrusted import text (OWASP #591), and rescanning from the start of the
/// string for every match would be O(length × matches), a CPU-cost lever an
/// adversarial line with many repeated `while`/`whiles` occurrences could
/// pull.
List<String>? splitTopLevelOnWord(String t, RegExp word) {
  final matches = word.allMatches(t).iterator;
  if (!matches.moveNext()) return null;
  var depth = 0;
  for (var i = 0; i <= t.length; i++) {
    // `allMatches` yields matches in ascending, non-overlapping start order,
    // so once a match's start is behind the scan position it is resolved
    // and the iterator advances — each character and each match is visited
    // at most once.
    while (matches.current.start == i) {
      if (depth == 0) {
        final m = matches.current;
        return [t.substring(0, m.start).trim(), t.substring(m.end).trim()];
      }
      if (!matches.moveNext()) return null;
    }
    if (i == t.length) break;
    final c = t.codeUnitAt(i);
    if (c == 0x28 || c == 0x5B) {
      depth++;
    } else if ((c == 0x29 || c == 0x5D) && depth > 0) {
      depth--;
    }
  }
  return null;
}

// --- Shared token vocabularies ----------------------------------------------

/// Single words → canonical dancer-set token. Post-scrub, gendered terms are
/// already `role1`/`role2`; this maps relationship words + those tokens.
const Map<String, String> _dancerWords = {
  'neighbor': 'neighbors',
  'neighbors': 'neighbors',
  'partner': 'partners',
  'partners': 'partners',
  'role1': 'role1s',
  'role1s': 'role1s',
  'role2': 'role2s',
  'role2s': 'role2s',
  'everyone': 'everyone',
  'ones': 'ones',
  'twos': 'twos',
  // Tier B: TCB writes "Shadow allemande"; taxonomy supports `shadows`.
  'shadow': 'shadows',
  'shadows': 'shadows',
  // Tier B: TCB N-prefix relationship shorthand ("N2 neighbor", "N1", …).
  // Ni maps to the taxonomy's pair dancer-set convention.
  'n0': 'prevNeighbors',
  'n1': 'neighbors',
  'n2': 'nextNeighbors',
  'n3': 'thirdNeighbors',
  'n4': 'fourthNeighbors',
  // Tier B: TCB P-prefix partner-series shorthand ("P1 partner", "P2 partner",
  // …). P/P1 = current partner; P0 = previous; P2–P5 = successive next
  // partners (taxonomy v24, issue #732). P6+ and P-n have no taxonomy token
  // and are absent from this map so they decline the whole line to custom.
  'p': 'partners',
  'p1': 'partners',
  'p0': 'prevPartners',
  'p2': 'nextPartners',
  'p3': 'thirdPartners',
  'p4': 'fourthPartners',
  'p5': 'fifthPartners',
  // TCB explicit-dancer codes map to the single-dancer identities: M/W are the
  // roles, 1 = the active couple (ones), 2 = the inactive couple (twos). So
  // M1 = active role1 (onesRole1), W1 = active role2 (onesRole2), M2 = inactive
  // role1 (twosRole1), W2 = inactive role2 (twosRole2). Bare codes only —
  // line-order annotations like "(M1-W2-M2-W1)" are stripped before recognition.
  'm1': 'onesRole1',
  'w1': 'onesRole2',
  'm2': 'twosRole1',
  'w2': 'twosRole2',
};

/// Filler words that carry no structural meaning and may be dropped anywhere.
const Set<String> _filler = {'your', 'the', 'a', 'an'};

// --- Small word-list helpers ------------------------------------------------

/// Removes all leading/embedded [_filler] words in place.
void _dropFiller(List<String> w) => w.removeWhere(_filler.contains);

/// Removes the first occurrence of the consecutive [phrase] found anywhere in
/// [w] and returns true; returns false (leaving [w] untouched) if absent.
bool _consumePhrase(List<String> w, List<String> phrase) {
  for (var i = 0; i + phrase.length <= w.length; i++) {
    var hit = true;
    for (var j = 0; j < phrase.length; j++) {
      if (w[i + j] != phrase[j]) {
        hit = false;
        break;
      }
    }
    if (hit) {
      w.removeRange(i, i + phrase.length);
      return true;
    }
  }
  return false;
}

/// Removes and returns the first dancer-set word found, or null.
String? _takeDancer(List<String> w) {
  for (var i = 0; i < w.length; i++) {
    final token = _dancerWords[w[i]];
    if (token != null) {
      final raw = w.removeAt(i);
      // TCB pairs the N-prefix with a redundant "neighbor(s)" word
      // ("N2 neighbor"); drop it so the pair reads as one dancer set rather
      // than leaving "neighbor" as unexplained leftover → custom.
      if (raw.length == 2 &&
          raw.startsWith('n') &&
          i < w.length &&
          (w[i] == 'neighbor' || w[i] == 'neighbors')) {
        w.removeAt(i);
      }
      // TCB pairs the P-prefix with a redundant "partner(s)" word
      // ("P2 partner swing"); drop it for the same reason.
      if (_pSeriesCodes.contains(raw) &&
          i < w.length &&
          (w[i] == 'partner' || w[i] == 'partners')) {
        w.removeAt(i);
      }
      return token;
    }
  }
  return null;
}

/// Like [_takeDancer] but ONLY matches a dancer set at the FRONT of [w].
/// Recognizers whose grammar requires a *leading* dancer ("Ones turn contra
/// corners", "Men give-and-take partner") use this so an unattested word order
/// where the dancer appears later in the line (e.g. "turn contra corners ones")
/// is NOT structured — it falls through to custom instead.
String? _takeLeadingDancer(List<String> w) {
  if (w.isEmpty) return null;
  final token = _dancerWords[w[0]];
  if (token == null) return null;
  final raw = w.removeAt(0);
  // Mirror _takeDancer's "N2 neighbor" pair absorption for the leading slot.
  if (raw.length == 2 &&
      raw.startsWith('n') &&
      w.isNotEmpty &&
      (w[0] == 'neighbor' || w[0] == 'neighbors')) {
    w.removeAt(0);
  }
  // Mirror _takeDancer's "P2 partner" pair absorption for the leading slot.
  if (_pSeriesCodes.contains(raw) &&
      w.isNotEmpty &&
      (w[0] == 'partner' || w[0] == 'partners')) {
    w.removeAt(0);
  }
  return token;
}

/// Removes and returns the first `left`/`right` word found, or null.
String? _takeSide(List<String> w) {
  for (var i = 0; i < w.length; i++) {
    if (w[i] == 'left' || w[i] == 'right') {
      final side = w.removeAt(i);
      return side;
    }
  }
  return null;
}

/// TCB N-prefix neighbor tags (`N0`..`N4`). Used to absorb a trailing numeric
/// neighbor qualifier ("with neighbor N2", "chain to neighbor N2") that would
/// otherwise be left over and force the custom fallback.
const Set<String> _neighborNumbers = {'n0', 'n1', 'n2', 'n3', 'n4'};

/// TCB P-prefix partner tags that have taxonomy tokens (`P`/`P0`–`P5`; taxonomy
/// v24, issue #732). Used to identify the subset of [_dancerWords] keys whose
/// "P2 partner" pair absorption should fire — membership is a taxonomy fact, not
/// a spelling heuristic. `partner` and `partners` also start with `p` in
/// [_dancerWords] but must NOT trigger the absorption.
const Set<String> _pSeriesCodes = {'p', 'p0', 'p1', 'p2', 'p3', 'p4', 'p5'};

/// Removes the first [_neighborNumbers] token from [w] and returns it, or null.
String? _takeNeighborNumber(List<String> w) {
  for (var i = 0; i < w.length; i++) {
    if (_neighborNumbers.contains(w[i])) return w.removeAt(i);
  }
  return null;
}

/// Takes a TCB relationship target, resolving an N-tag written in EITHER word
/// order. [_takeDancer] already absorbs the prefix form ("N2 neighbor butterfly
/// whirl clockwise"); TCB also writes the SUFFIX form ("Mad robin clockwise
/// around neighbor N2"), where a plain [_takeDancer] would match "neighbor"
/// first and resolve the very same relationship to `neighbors` instead of
/// `nextNeighbors`. Scanning for the `neighbor(s) N<i>` pair first makes both
/// orders agree. Falls back to [_takeDancer] when no such pair is present.
String? _takeRelationship(List<String> w) {
  for (var i = 0; i + 1 < w.length; i++) {
    if ((w[i] == 'neighbor' || w[i] == 'neighbors') &&
        _neighborNumbers.contains(w[i + 1])) {
      final tag = w[i + 1];
      w.removeRange(i, i + 2);
      return _dancerWords[tag];
    }
  }
  return _takeDancer(w);
}

/// Removes a rotation-direction word from anywhere in [w] and returns the
/// canonical `clockwise`/`counterclockwise` token, or null when the line states
/// none. Shared by every move whose TCB line states a spin direction (`orbit`,
/// `mad_robin`, `butterfly_whirl`).
///
/// The counter-forms are tested FIRST: `_consumePhrase(['clockwise'])` would
/// otherwise match the second half of a two-token "counter clockwise" and leave
/// a stray "counter" behind, inverting the direction (the recognizer would then
/// reject the line for leftover text — safe, but needlessly lossy).
///
/// Distinct from [_takeGateDirection], which additionally admits TCB's
/// gate-only `mirror` value and therefore cannot be shared.
String? _takeSpinDirection(List<String> w) {
  if (_consumePhrase(w, ['counterclockwise']) ||
      _consumePhrase(w, ['counter', 'clockwise']) ||
      _consumePhrase(w, ['anticlockwise']) ||
      _consumePhrase(w, ['ccw'])) {
    return 'counterclockwise';
  }
  if (_consumePhrase(w, ['clockwise']) || _consumePhrase(w, ['cw'])) {
    return 'clockwise';
  }
  return null;
}

/// Whether the consecutive [phrase] occurs anywhere in [w], WITHOUT consuming.
bool _hasPhrase(List<String> w, List<String> phrase) =>
    _phraseIndex(w, phrase) != -1;

/// Index of the first occurrence of the consecutive [phrase] in [w], or -1.
/// Does NOT consume. Recognizers use this when a later clause's position must
/// be checked RELATIVE to an anchor phrase before anything is removed.
int _phraseIndex(List<String> w, List<String> phrase) {
  for (var i = 0; i + phrase.length <= w.length; i++) {
    var hit = true;
    for (var j = 0; j < phrase.length; j++) {
      if (w[i + j] != phrase[j]) {
        hit = false;
        break;
      }
    }
    if (hit) return i;
  }
  return -1;
}

/// Consumes a LEADING "on [the] left/right diagonal" clause (TCB writes it as a
/// prefix, e.g. "On left diagonal, ladies chain to neighbor"; the comma is
/// stripped by `_normalize`) and returns the canonical `dir` value
/// `leftDiagonal`/`rightDiagonal`, or null when absent. Only fires at the FRONT
/// so the "left" in "on left diagonal" is never confused with a later figure
/// token (e.g. the "left" of "right and left through").
String? _takeDiagonal(List<String> w) {
  if (w.isEmpty || w[0] != 'on') return null;
  var i = 1;
  if (i < w.length && w[i] == 'the') i++;
  if (i + 1 < w.length &&
      (w[i] == 'left' || w[i] == 'right') &&
      w[i + 1] == 'diagonal') {
    final side = w[i];
    w.removeRange(0, i + 2);
    return side == 'left' ? 'leftDiagonal' : 'rightDiagonal';
  }
  return null;
}

/// Recognises a rotation amount (allemande/do si do/shoulder round `turn`).
/// Consumes the token(s) and returns turns in 0.25..2.5, or null if none.
double? _takeRotation(List<String> w) {
  const single = {
    'once': 1.0,
    '1x': 1.0,
    '1': 1.0,
    'twice': 2.0,
    '2x': 2.0,
    '2': 2.0,
    '1/4': 0.25,
    '1/2': 0.5,
    '3/4': 0.75,
    '1.25': 1.25,
    '1.5': 1.5,
    '1.75': 1.75,
    '2.5': 2.5,
  };
  for (var i = 0; i < w.length; i++) {
    // Two-token "1 1/2" / "1 1/4" / "1 3/4" forms.
    if (i + 1 < w.length && w[i] == '1') {
      const combo = {'1/4': 1.25, '1/2': 1.5, '3/4': 1.75};
      // Three-token "1 and 1/2" form: TCB writes "1 & 1/2" and `_normalize`
      // maps `&`→"and", so bridge the intervening "and".
      if (w[i + 1] == 'and' && i + 2 < w.length) {
        final v3 = combo[w[i + 2]];
        if (v3 != null) {
          w.removeRange(i, i + 3);
          return v3;
        }
      }
      final v = combo[w[i + 1]];
      if (v != null) {
        w.removeRange(i, i + 2);
        return v;
      }
    }
    final v = single[w[i]];
    if (v != null) {
      w.removeAt(i);
      return v;
    }
  }
  return null;
}

/// Recognises circle/star travel and returns a `places` count (1..10), or null.
/// Handles `N places`, quarter fractions, and "once"/"all the way"/"halfway".
int? _takePlaces(List<String> w) {
  // "N places" (or "N place").
  for (var i = 0; i + 1 < w.length; i++) {
    if (w[i + 1] == 'places' || w[i + 1] == 'place') {
      final n = int.tryParse(w[i]);
      if (n != null && n >= 1 && n <= 10) {
        w.removeRange(i, i + 2);
        return n;
      }
    }
  }
  // Compound "N & 1/4|1/2|3/4" turn amount (TCB writes "1 & 1/2"; `_normalize`
  // maps `&`→"and"). `places` is an integer quarter-count (a full turn is 4),
  // so places = N*4 + fractionPlaces. Only quarter fractions land on a whole
  // place; eighth-turns ("1 & 1/8", "7/8") have no integer place and are left
  // for the custom fallback — the place count is never rounded or fabricated.
  const quarterPlaces = {'1/4': 1, '2/4': 2, '1/2': 2, '3/4': 3};
  for (var i = 0; i + 1 < w.length; i++) {
    final whole = int.tryParse(w[i]);
    if (whole == null || whole < 1) continue;
    // Bridge the "and" that `_normalize` leaves between whole and fraction.
    final fracIdx = w[i + 1] == 'and' ? i + 2 : i + 1;
    if (fracIdx >= w.length) continue;
    final frac = quarterPlaces[w[fracIdx]];
    if (frac == null) continue;
    final places = whole * 4 + frac;
    if (places < 1 || places > 10) continue;
    var end = fracIdx + 1;
    if (end < w.length && (w[end] == 'places' || w[end] == 'place')) end++;
    w.removeRange(i, end);
    return places;
  }
  const byToken = {
    '1/4': 1,
    '2/4': 2,
    '1/2': 2,
    '3/4': 3,
    '4/4': 4,
    'once': 4,
    '1x': 4,
    '1': 4,
    'full': 4,
    'round': 4,
    'halfway': 2,
    'half': 2,
    'twice': 8,
    '2x': 8,
  };
  for (var i = 0; i < w.length; i++) {
    final v = byToken[w[i]];
    if (v != null) {
      w.removeAt(i);
      return v;
    }
  }
  // "all the way" / "all the way around" / bare "all around".
  if (_consumePhrase(w, ['all', 'the', 'way']) || _consumePhrase(w, ['all'])) {
    _consumePhrase(w, ['around']);
    return 4;
  }
  return null;
}

// --- Per-move recognizers ----------------------------------------------------
//
// Each recognizer works on a mutable copy of the word list, consuming the
// tokens it understands. It returns a [_Match] ONLY when the list is empty
// afterwards (the whole line is accounted for); otherwise it returns null and
// the next recognizer — or the custom fallback — takes over.

typedef _Recognizer = _Match? Function(List<String> words);

final List<_Recognizer> _recognizers = [
  _swing,
  _petronella,
  _balanceTheRing,
  _balance,
  _shoulderRound,
  _allemande,
  _doSiDo,
  _revolvingDoor,
  _boxTheGnat,
  _boxCirculate,
  _circle,
  // Must precede _starPromenade / _star so the shared "star" lead phrase
  // resolves "star through" to this move before the bare-star recognizers.
  _starThrough,
  // _facingStar leads with the distinct phrase "facing star" (not "star …"), so
  // it is not affected by the bare-star ordering below; it is grouped with the
  // star family here purely for locality.
  _facingStar,
  // Must precede _star so the shared "star" lead phrase resolves to the more
  // specific "star promenade" move before the bare-star recognizer.
  _starPromenade,
  _star,
  _chain,
  // Taxonomy v23: TCB's standalone `courtesy turn`. Anchors on the two-word
  // `courtesy turn` phrase, which no other recognizer consumes, so its position
  // here is for locality (next to `chain`, its choreographic neighbour) rather
  // than correctness. Conservative — any leftover token declines to custom,
  // which is what keeps every chain-embedded courtesy turn whole-custom.
  _courtesyTurn,
  _rightLeftThrough,
  // Order among these three is not correctness-critical: each recognizer runs on
  // its own copy of the word list, and "pass the ocean" contains no "through" so
  // _passThrough never matches (or partially consumes) it. They are placed
  // together here purely for locality. _formShortWaves sits between the two
  // "pass …" recognizers and is independent of both (its lead word is "form").
  _passTheOcean,
  _formShortWaves,
  // Long-wave forms lead with "form … long wave(s)"; the "long" token keeps
  // them disjoint from `_formShortWaves` ("form a wave" / "form short wave"),
  // so relative order is not correctness-critical.
  _formLongWave,
  _passThrough,
  // #733: TCB's "Walk forward to <dancer>" → the same `pass_through` move.
  // Leading-anchored on "walk forward to", a phrase no other recognizer
  // consumes, so its position here is for locality (next to `_passThrough`,
  // the move it resolves to) rather than correctness.
  _walkForwardTo,
  _promenade,
  _shift,
  _longLines,
  _slice,
  _turnAlone,
  _contraCorners,
  _giveAndTake,
  _poussette,
  // Issue #295: standalone `orbit` (TCB "Men orbit clockwise 1/2"). A distinct
  // anchor word ("orbit"), so it neither shadows nor is shadowed by any other
  // recognizer. Conservative: the rotation direction and amount must both be
  // stated (never defaulted), so a bare "orbit" degrades to a custom figure.
  // With this in place the TCB `||` and ContraDB `while` fan-outs represent the
  // combined "X allemande while Y orbits" as meanwhile[allemande, orbit].
  _orbit,
  // Issue #295: TCB's `mad robin` and `butterfly whirl`. Each anchors on a
  // distinct multi-word lead phrase ("mad robin" / "butterfly whirl") that no
  // other recognizer consumes, so they neither shadow nor are shadowed. Both
  // require the direction TCB always states, so a bare "mad robin" or
  // "butterfly whirl" (ContraDB's own phrasing) still degrades to custom here —
  // ContraDB lines are recognized by `contradb_figure_dialect.dart` instead.
  _madRobin,
  _butterflyWhirl,
  // Additive TCB-attested moves (issue #553, Gap 1). Each is conservative
  // (leftover token → null → custom) and anchors on a distinct lead phrase, so
  // none shadows or is shadowed by the recognizers above.
  _rollAway,
  _crossTrails,
  _figure8,
  // "Men/Women/Neighbor trade" and "trade by [the] left/right [shoulder]"
  // (issue #945) → pass_by (the pair change places). Still excludes
  // "trade the wave"/"trade the line" internally, which corpus evidence shows
  // are distinct, unmodelled whole-wave/whole-line constructions.
  _tradePassBy,
  // "Men pass left" / "Women cross by right" → pass_by (who + shoulder). Placed
  // after the "pass …" family (_passTheOcean/_passThrough) and _crossTrails; it
  // requires an explicit side and empty leftover, so it declines "pass through",
  // "pass the ocean", and "cross trail through" and never shadows them.
  _passCrossBy,
  // The unified gate (taxonomy v22; was `rotation_gate`, issue #294). Structures
  // ONLY a gate line that fully resolves to (pair, direction, turn) — the TCB
  // shape. The ContraDB shape (`<who> gate <whom> to face <dir>`) is handled by
  // the ContraDB dialect's own `_gate`, which fills different slots on the same
  // move. Anything that doesn't resolve stays custom; the ending facing is never
  // parsed here and never derived (see gate_facing.dart).
  _gate,
  _californiaTwirl,
  _weaveTheLine,
  _squareThrough,
  _pullBy,
  // Appended at the lowest precedence. End placement is safe because these
  // recognisers are conservative (any leftover token → null → custom) and no
  // earlier recogniser consumes their move anchors (`rory`/`o'more`, `hall`);
  // a leading dancer set alone (e.g. "Ones …", "Everyone …") never triggers an
  // earlier recogniser either, so they neither shadow nor are shadowed. They
  // emit only what a single line states, and set the neutral value for the
  // cross-line params (`balance: false` on rory, `ender: 'none'` on the halls)
  // EXPLICITLY — the CallersBox cross-line merge fills the real value later.
  _roryOMore,
  _downTheHall,
  _upTheHall,
];

_Match? _swing(List<String> w) {
  final who = _takeDancer(w);
  String prefix = 'none';
  if (_consumePhrase(w, ['balance', 'and'])) {
    prefix = 'balance';
  } else if (_consumePhrase(w, ['meltdown'])) {
    prefix = 'meltdown';
  }
  if (!_consumePhrase(w, ['swing'])) return null;
  final who2 = who ?? _takeDancer(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match(
    'swing',
    {'who': who2 ?? 'partners', if (prefix != 'none') 'prefix': prefix},
    null,
    who2 == null,
  );
}

_Match? _petronella(List<String> w) {
  // Optional leading "balance and" (petronella's balance flag defaults true).
  _consumePhrase(w, ['balance', 'and']);
  if (!_consumePhrase(w, ['petronella'])) return null;
  // Optional trailing descriptor.
  _consumePhrase(w, ['turn']);
  _consumePhrase(w, ['spin']);
  _consumePhrase(w, ['twirl']);
  _dropFiller(w);
  return w.isEmpty ? const _Match('petronella') : null;
}

_Match? _balanceTheRing(List<String> w) {
  // Accept "balance the ring" and TCB's "balance ring" (no "the").
  if (!_consumePhrase(w, ['balance', 'the', 'ring']) &&
      !_consumePhrase(w, ['balance', 'ring'])) {
    return null;
  }
  _dropFiller(w);
  return w.isEmpty ? const _Match('balance_the_ring') : null;
}

_Match? _balance(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['balance'])) return null;
  final who2 = who ?? _takeDancer(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('balance', {'who': who2 ?? 'neighbors'}, null, who2 == null);
}

_Match? _shoulderRound(List<String> w) {
  final who = _takeDancer(w);
  final side = _takeSide(w); // leading "left shoulder round"
  if (!_consumePhrase(w, ['shoulder', 'round'])) return null;
  final who2 = who ?? _takeDancer(w);
  final side2 = side ?? _takeSide(w);
  final turn = _takeRotation(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match(
    'shoulder_round',
    {'who': who2 ?? 'neighbors', 'shoulder': ?side2, 'turn': ?turn},
    null,
    who2 == null,
  );
}

_Match? _allemande(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['allemande'])) return null;
  final who2 = who ?? _takeDancer(w);
  final hand = _takeSide(w);
  final turn = _takeRotation(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match(
    'allemande',
    {'who': who2 ?? 'neighbors', 'hand': ?hand, 'turn': ?turn},
    null,
    who2 == null,
  );
}

_Match? _doSiDo(List<String> w) {
  final who = _takeDancer(w);
  final seeSaw = _consumePhrase(w, ['see', 'saw']);
  final isDoSiDo =
      _consumePhrase(w, ['do', 'si', 'do']) ||
      _consumePhrase(w, ['do', 'sa', 'do']) ||
      _consumePhrase(w, ['dosido']);
  if (!seeSaw && !isDoSiDo) return null;
  final who2 = who ?? _takeDancer(w);
  final turn = _takeRotation(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  final moveId = seeSaw ? 'see_saw' : 'do_si_do';
  return _Match(
    moveId,
    {'who': who2 ?? 'neighbors', 'turn': ?turn},
    null,
    who2 == null,
  );
}

_Match? _revolvingDoor(List<String> w) {
  // Optional leading dancer set, then the two-word anchor. TCB writes the
  // compound parent as a bare "Revolving door"; ContraDB may qualify it
  // ("ladles revolving door right partners"). Only parsed tokens are emitted —
  // absent who/hand/whom fall to the taxonomy defaults, never fabricated.
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['revolving', 'door'])) return null;
  final who2 = who ?? _takeDancer(w);
  final hand = _takeSide(w);
  final whom = _takeDancer(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('revolving_door', {'who': ?who2, 'hand': ?hand, 'whom': ?whom});
}

_Match? _boxTheGnat(List<String> w) {
  final who = _takeDancer(w);
  final swat = _consumePhrase(w, ['swat', 'the', 'flea']);
  final box = _consumePhrase(w, ['box', 'the', 'gnat']);
  if (!swat && !box) return null;
  final who2 = who ?? _takeDancer(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  final moveId = swat ? 'swat_the_flea' : 'box_the_gnat';
  return _Match(moveId, {'who': who2 ?? 'partners'}, null, who2 == null);
}

// ContraDB `box circulate`. A single "box circulate" line states no balance, so
// the `balance` flag is left absent (neutral); the CallersBox cross-line merge
// folds a preceding balance line in as true. `hand` stays on the taxonomy
// default (ContraDB right_hand_spin) — TCB does not write it inline.
_Match? _boxCirculate(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['box', 'circulate'])) return null;
  final who2 = who ?? _takeDancer(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match(
    'box_circulate',
    {'who': who2 ?? 'partners'},
    null,
    who2 == null,
  );
}

// Takes a TCB rotation-gate direction token (clockwise/cw, counterclockwise/ccw
// /anticlockwise, or mirror) from anywhere in [w], returning the canonical
// `direction` choice token, or null if none is present.
String? _takeGateDirection(List<String> w) {
  for (var i = 0; i < w.length; i++) {
    switch (w[i]) {
      case 'clockwise':
      case 'cw':
        w.removeAt(i);
        return 'clockwise';
      case 'counterclockwise':
      case 'anticlockwise':
      case 'ccw':
        w.removeAt(i);
        return 'counterclockwise';
      case 'mirror':
        w.removeAt(i);
        return 'mirror';
    }
  }
  return null;
}

// The unified gate (taxonomy v22; was the TCB-only `rotation_gate`, issue
// #294). Structures a TCB gate line ONLY when it fully resolves to
// (pair, direction, turn): the `gate` anchor, a rotation direction, and a turn
// fraction, with nothing left over. A bare "gate", a missing direction or
// fraction, adversarial tokens, or trailing prose all yield null so the line
// degrades to a faithful custom figure (never a throw, never a fabricated
// facing).
//
// The subject goes to `pair`, NOT `who`. TCB's "Neighbor gate…" / "Partner
// gate…" names the pairing you gate WITH; ContraDB's `who` names the side that
// extends a hand and BACKS UP (libfigure `figure.js:844`, and `chooser.js:114`
// shows its domain admits only role-sides — never `neighbors`/`partners`).
// Writing TCB's subject into `who` would reinterpret every imported TCB gate as
// a claim about which side moves.
//
// The ending facing is NOT parsed and NOT derived: TCB never states one for a
// gate, so `face` stays `unspecified` for the user to fill in. (Before v22 it
// was derived from a nominal `in` start orientation and was wrong after any
// orientation-changing figure — see gate_facing.dart.)
//
// The `(ones forward)`/`(NR)` parentheticals are dropped by `_normalize` for
// recognition; the TCB front-end's `_gateAnnotation` pre-recognizer runs first
// and preserves them verbatim as the figure's note, so nothing is lost. Beats
// are layered on from the source line (variable 2/3/4/6/8), not here.
_Match? _gate(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['gate'])) return null;
  final who2 = who ?? _takeDancer(w);
  final direction = _takeGateDirection(w);
  if (direction == null) return null;
  final turn = _takeRotation(w);
  if (turn == null) return null;
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match(
    'gate',
    {'pair': who2 ?? 'neighbors', 'direction': direction, 'turn': turn},
    null,
    who2 == null,
  );
}

// `star through`: mirrors california_twirl — who only, no `balance` param,
// and it does NOT take part in the balance cross-line merge (v12 dropped it
// from the merge set to match california_twirl). No inline
// hand — star through's handedness is role-fixed. `_normalize` maps thru →
// through, so "star thru" reaches here too. Ordered before the bare-star
// recognizers so the shared "star" lead resolves here first.
_Match? _starThrough(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['star', 'through'])) return null;
  final who2 = who ?? _takeDancer(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match(
    'star_through',
    {'who': who2 ?? 'partners'},
    null,
    who2 == null,
  );
}

_Match? _circle(List<String> w) {
  if (!_consumePhrase(w, ['circle'])) return null;
  final turn = _takeSide(w); // circle `turn` is left/right
  final places = _takePlaces(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('circle', {'turn': ?turn, 'places': ?places});
}

/// Tier A: TCB writes "Facing star clockwise 3/4" / "Facing star clockwise 1"
/// (e.g. "… free hand to partner" dances). A facing star is an inherently
/// four-person figure, so TCB never names the dancers — `who` is set EXPLICITLY
/// to `everyone` (the whole set), never a fabricated pair/`ones` default. Both
/// the rotation direction (clockwise / counterclockwise) AND the turn-amount
/// ("3/4" -> 3 places, "1"/full -> 4 places) are load-bearing choreography (they
/// determine who you end up facing) and MUST be stated in-line; if either is
/// missing the line stays CUSTOM (never default `turn`/`places`). The ornamental
/// hand-hold annotation ("(MR, WL, free hand to partner)") and the "[with N2]"
/// bracket are stripped by `_normalize`. "Women walk forward; form facing star"
/// / "form facing star" do not LEAD with "facing star" and carry no direction or
/// amount, so they stay custom.
_Match? _facingStar(List<String> w) {
  // Leading-anchored: the line must START with "facing star" (after optional
  // framing filler); a mid-line "facing star" is left for the custom fallback.
  const framing = {'the', 'a', 'an'};
  var i = 0;
  while (i < w.length && framing.contains(w[i])) {
    i++;
  }
  if (i + 2 > w.length || w[i] != 'facing' || w[i + 1] != 'star') return null;
  w.removeRange(0, i + 2);
  // Direction MUST be stated (never defaulted).
  String? spin;
  if (_consumePhrase(w, ['clockwise'])) {
    spin = 'clockwise';
  } else if (_consumePhrase(w, ['counterclockwise'])) {
    spin = 'counterclockwise';
  }
  if (spin == null) return null;
  // Turn-amount MUST be stated ("3/4" -> 3, "1"/full -> 4). Never defaulted.
  final places = _takePlaces(w);
  if (places == null) return null;
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('facing_star', {
    'who': 'everyone',
    'turn': spin,
    'places': places,
  });
}

_Match? _star(List<String> w) {
  if (!_consumePhrase(w, ['star'])) return null;
  final hand = _takeSide(w);
  final places = _takePlaces(w);
  // TCB writes "Hands-across star right/left"; recognise the grip qualifier
  // (hyphenated single token or two words). It carries no render token.
  final grip =
      _consumePhrase(w, ['hands-across']) ||
          _consumePhrase(w, ['hands', 'across'])
      ? 'handsAcross'
      : null;
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('star', {'hand': ?hand, 'places': ?places, 'grip': ?grip});
}

_Match? _chain(List<String> w) {
  // Optional leading "on left/right diagonal" → the diagonal `dir`.
  final diag = _takeDiagonal(w);
  // TCB writes "Ladies chain to neighbor/partner" exclusively. Preserve the
  // "to <dancer>" target as a Figure NOTE rather than folding it into `who`
  // (which would misrepresent the chaining set). Capture it FIRST so its
  // dancer isn't consumed as the chaining set by the _takeDancer calls below.
  String? note;
  final toIdx = w.indexOf('to');
  if (toIdx != -1 &&
      toIdx + 1 < w.length &&
      _dancerWords.containsKey(w[toIdx + 1])) {
    // Absorb an optional trailing N-tag ("chain to neighbor N2") into the note
    // so the numeric qualifier does not survive as leftover → custom.
    var end = toIdx + 2;
    var noteText = 'to ${w[toIdx + 1]}';
    if (end < w.length && _neighborNumbers.contains(w[end])) {
      noteText = '$noteText ${w[end]}';
      end++;
    }
    note = noteText;
    w.removeRange(toIdx, end);
  }
  final who = _takeDancer(w);
  // v28 (#976): "<actor> do a <side>-hand <ladies|gents> chain". The token
  // immediately before `chain` here — already normalized to `role1s`/`role2s`
  // by `canonicalize.dart`'s legacy role synonyms, same as [who] above — is
  // ALWAYS "ladies" or "gents" across all 126 corpus lines that use this
  // construction (issue #976 §2.4), REGARDLESS of the actual actor (e.g.
  // "Women do a left-hand gents chain to partner"): it is TCB's fixed
  // idiomatic name for the two chain hand-patterns, not a second, independent
  // role statement. So it is consumed here but never read into a param —
  // [who] (the actor read above, BEFORE "do a") is the real `who`. Matched as
  // a strict, contiguous shape (not a general scan), since that is the only
  // shape attested; a partial/non-matching "do a" survives as leftover and
  // falls through to the plain-chain path below, which then declines it via
  // the ordinary "leftover tokens → custom" rule.
  String? statedHand;
  for (var i = 0; i + 4 < w.length; i++) {
    if (w[i] != 'do' || w[i + 1] != 'a') continue;
    final handTok = w[i + 2];
    final roleTok = w[i + 3];
    final hand = handTok == 'left-hand'
        ? 'left'
        : handTok == 'right-hand'
        ? 'right'
        : null;
    if (hand != null &&
        (roleTok == 'role1s' || roleTok == 'role2s') &&
        w[i + 4] == 'chain') {
      statedHand = hand;
      w.removeRange(i, i + 5);
    }
    break;
  }
  if (statedHand == null && !_consumePhrase(w, ['chain'])) return null;
  final who2 = who ?? _takeDancer(w);
  // Optional direction (a leading diagonal wins over a trailing across/along).
  String? dir = diag;
  if (dir == null) {
    if (_consumePhrase(w, ['across'])) {
      dir = 'across';
    } else if (_consumePhrase(w, ['along'])) {
      dir = 'along';
    }
  }
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  // chain's `who` domain is role1s/role2s only. An explicit dancer set outside
  // that domain (e.g. "partners chain") must NOT be silently dropped to the
  // taxonomy default — that would misrepresent the source — so reject the
  // match and let it fall back to custom. No explicit dancer → leave `who`
  // unset so the taxonomy default (role2s) applies.
  if (who2 != null && who2 != 'role1s' && who2 != 'role2s') return null;
  // v28 (#976): populate `hand` ONLY when a role token was actually read for
  // `who` (`who2 != null`) — never when `who` is left unset for the taxonomy
  // default to fill at read time, per #976 §6.1.3: deriving a hand from OUR
  // default rather than the source would be fabrication. When `who` IS
  // known, an explicitly stated hand (the "do a" construction) is used
  // as-is, even when it contradicts the role-implied side (a deliberate
  // "women do a left-hand gents chain"); otherwise the role-implied side
  // (`chainHandForWho`) is written explicitly, matching every other write
  // site (#976 §6.1) so search/canonical stay consistent regardless of which
  // site wrote the figure.
  final hand = who2 == null ? null : (statedHand ?? chainHandForWho(who2));
  return _Match('chain', {'who': ?who2, 'hand': ?hand, 'dir': ?dir}, note);
}

// The Caller's Box's standalone courtesy turn (taxonomy v23). Grammar:
//
//   <dancer>? "courtesy turn" <dancer>? <clockwise|counterclockwise>?
//                                                      ("face" <dancer>)?
//
// Read the two `<dancer>?` slots carefully: they are ALTERNATIVE POSITIONS FOR
// THE SAME VALUE (`who`), not two different params. TCB writes the subject
// before the anchor ("Partner courtesy turn"); the post-anchor position exists
// only as a fallback for a line that omits it. **`whom` is never emitted by
// this recognizer**, and that is deliberate: no corpus line writes the
// two-dancer form `<X> courtesy turn <Y>`, so filling `whom` would invent a
// reading no source states. A line that DOES name two dancers
// ("ones courtesy turn twos") therefore leaves one of them over and declines to
// `custom` — the honest outcome, not a gap. `whom` exists on the MoveDef for
// manual authoring only (the maintainer's ruling: "left out by default unless
// it actually shows up in parsing data").
//
// Lives in the SHARED core rather than the TCB dialect because the grammar is
// source-neutral — nothing in it is TCB-only notation. (ContraDB will never
// exercise it: libfigure models no courtesy turn at all.)
//
// Placement in `_recognizers` is not correctness-critical. The `courtesy turn`
// anchor phrase is consumed by no other recognizer, and every recognizer runs
// on its own copy of the word list, so this neither shadows nor is shadowed;
// it sits next to `_chain` purely for locality, since the two are choreographic
// neighbours and the chain interaction below is the thing a reader will look
// for here.
//
// Conservative, per the whole-line contract: any leftover token declines the
// line to `custom`. That single rule is what keeps every unmodelable corpus
// wording honest, WITHOUT a word of exclusion logic:
//   * a chain that also names a courtesy turn — `Ladies chain to partner with
//     double courtesy turn`, `[W1+W2] Ladies chain, with half courtesy turn in
//     center`, `Right and left through with partner with double courtesy
//     turn`, `Neighbor promenade across with double courtesy turn` (30 corpus
//     lines) — leaves `chain`/`with`/`double`/`half` over and stays whole
//     `custom`. It must: emitting a standalone courtesy turn alongside the
//     chain would double-count both the figure and its beats, and neither our
//     `chain` nor ContraDB's has a slot for the qualifier to ride in.
//   * `Partner arky courtesy turn` (7 lines) leaves `arky` over. "Arky" means
//     the roles are reversed and we have no model for that, so structuring the
//     rest would silently drop real choreography.
//   * `Phantom partner`, `P1/P2/P4 partner`, `Next corner`, `Opposite
//     neighbor`, `Bottom couple`, `Fives`, `Left-end partner and right-end
//     partner` all leave their unmappable qualifier over. Those dancers are
//     deliberately unmapped (see docs/research/callersbox.md) and must decline,
//     not be approximated onto a token that means someone else.
//   * `Partner courtesy turn without hands`, `Partner courtesy turn 3/4`,
//     `Partner courtesy turn 1 // partner courtesy turn 2` leave a modifier or
//     a rotation amount over. The move has no `turn` param — the maintainer's
//     four-slot ruling gives it none — so an amount-bearing line stays custom
//     rather than losing the amount.
_Match? _courtesyTurn(List<String> w) {
  // Locate the anchor WITHOUT consuming it, so the ending-facing clause can be
  // required to FOLLOW it (see `_takeFacingDancer`).
  final anchor = _phraseIndex(w, ['courtesy', 'turn']);
  if (anchor == -1) return null;
  // Capture the ending-facing clause before any `_takeDancer` runs, so its
  // dancer can never be mistaken for the subject — the same ordering guard
  // `_chain` uses for its "to <dancer>" note. Without it, `courtesy turn face
  // N2` would resolve `who: nextNeighbors`, inverting the line's meaning.
  final endFacing = _takeFacingDancer(w, after: anchor + 2);
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['courtesy', 'turn'])) return null;
  final who2 = who ?? _takeDancer(w);
  // Emitted only when the line STATES it. Omitted otherwise, so the taxonomy's
  // `clockwise` default applies without the figure claiming the source said so.
  // Every one of the 10 corpus lines that states a direction says `clockwise`;
  // `counterclockwise` is accepted for authoring parity and is unattested.
  final direction = _takeSpinDirection(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match(
    'courtesy_turn',
    {
      'who': who2 ?? 'partners',
      'direction': ?direction,
      'endFacing': ?endFacing,
    },
    null,
    who2 == null,
  );
}

/// Consumes a TRAILING `face <dancer>` clause — one that begins at or after
/// [after], the index just past the `courtesy turn` anchor — and returns the
/// canonical dancer token, or null when absent. TCB writes it as `Partner
/// courtesy turn, face N2`; the comma is stripped by `_normalize`, so `face`
/// and the dancer arrive as adjacent words.
///
/// The [after] bound is load-bearing, not defensive tidiness. Scanning the
/// whole list would let a `face` clause that PRECEDES the move name be lifted
/// out before the main parse runs, so an unattested word order like `face N2
/// courtesy turn` would structure as though it were the attested one. No source
/// writes the facing first, and this file's settled posture on unattested word
/// order is to DECLINE rather than to normalise it into a reading the source
/// never expressed (cf. `_takeLeadingDancer`, which exists for exactly this
/// reason). With the bound, such a line leaves `face`/`n2` over and correctly
/// falls to `custom`.
///
/// The value is a **DANCER**, not a cardinal facing: all 13 attested lines say
/// `face N0`/`N2`/`N3`. TCB does also write cardinal facings (`Ones courtesy
/// turn; face down`), but always after a `;`, and the all-or-nothing
/// `;`-compound rule keeps those lines whole-custom before they reach any
/// recognizer. Requiring the very next word to be a dancer is what keeps it
/// that way if that ever changes: `face down` resolves no dancer, so it is left
/// as leftover and declines the line.
String? _takeFacingDancer(List<String> w, {required int after}) {
  // The scan STARTS at `after` (the index just past the anchor) rather than
  // searching the whole list and rejecting an early hit on the following line.
  // The bound IS the contract, so it belongs in the search call: a guard on the
  // next line is invisible to every cheap check — a grep for the bare search, an
  // eye-skim, a reviewer scanning a diff hunk — and reading such a search as
  // unbounded is then a reasonable, wrong conclusion. (Deliberately phrased
  // without quoting the unbounded form: writing it here, even as an example,
  // would put the very string back into the file and re-create the false grep
  // hit this exists to remove.)
  final i = w.indexOf('face', after);
  if (i == -1 || i + 1 >= w.length) return null;
  final token = _dancerWords[w[i + 1]];
  if (token == null) return null;
  // Absorb TCB's redundant "N2 neighbor" pairing, mirroring `_takeDancer`.
  var end = i + 2;
  if (w[i + 1].length == 2 &&
      w[i + 1].startsWith('n') &&
      end < w.length &&
      (w[end] == 'neighbor' || w[end] == 'neighbors')) {
    end++;
  }
  w.removeRange(i, end);
  return token;
}

_Match? _rightLeftThrough(List<String> w) {
  // Optional leading "on left/right diagonal" and/or "same-role" qualifier.
  final diag = _takeDiagonal(w);
  final sameRole =
      _consumePhrase(w, ['same-role']) || _consumePhrase(w, ['same', 'role']);
  final ok =
      _consumePhrase(w, ['right', 'left', 'through']) ||
      _consumePhrase(w, ['right', 'and', 'left', 'through']);
  if (!ok) return null;
  String? dir = diag;
  if (dir == null) {
    if (_consumePhrase(w, ['across'])) {
      dir = 'across';
    } else if (_consumePhrase(w, ['along'])) {
      dir = 'along';
    }
  }
  // TCB writes "...right and left through with partner/neighbor" exclusively;
  // consume the trailing "with <dancer>" qualifier (no structured slot), plus
  // an optional numeric neighbor tag ("with neighbor N2").
  if (_consumePhrase(w, ['with'])) {
    _takeDancer(w);
    _takeNeighborNumber(w);
  }
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  // right_left_through has no same-role slot, so the same-role variant is
  // preserved as a note (the move + dir still structure faithfully).
  return _Match('right_left_through', {
    'dir': ?dir,
  }, sameRole ? 'same-role' : null);
}

_Match? _passThrough(List<String> w) {
  if (!_consumePhrase(w, ['pass', 'through'])) return null;
  String? dir;
  if (_consumePhrase(w, ['across'])) {
    dir = 'across';
  } else if (_consumePhrase(w, ['along'])) {
    dir = 'along';
  }
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('pass_through', {'dir': ?dir});
}

/// Tier B (#733): TCB writes "Walk forward to N2" / "… to shadow" / "… to N1"
/// / "… to partner" / "… to N0" / "… to N3" — a **pass through**. (Line counts
/// and the population they are measured over live in the `walk forward` census
/// in `docs/research/callersbox.md`; they are not repeated here, where they
/// would drift silently the next time the mirror is re-pulled and could not
/// state their own population filter.)
///
/// `to <dancer>` names the DESTINATION you arrive at, not a dancer you pass:
/// you walk forward past your current neighbour and finish facing the named
/// one. That is the standard contra progression, which is why the next line so
/// often dances WITH that dancer (`(4) Walk forward to N1` / `(12) N1 neighbor
/// swing`) — "walk forward to N2" then "<figure> with N2" is the same
/// choreography as "pass through (from N1 to N2)" then "<figure> with N2".
///
/// `pass_through` has no destination param, so the destination is preserved
/// VERBATIM as the figure's note (`to n2`), the same shape [_chain] uses for
/// its `to <dancer>` target (maintainer ruling on #729: parse the recognized
/// figure, preserve the remainder as a note). This is what keeps `to n0` /
/// `to n1` / `to shadow` — which are NOT the ordinary progression target —
/// recoverable instead of flattened into an undifferentiated pass through.
///
/// Deliberately narrow (prefer-custom):
/// - The line must LEAD with "walk forward to". A stated subject ("Women walk
///   forward to N2") is DECLINED: `pass_through` has no `who` slot, so
///   structuring it would silently drop the role.
/// - `dir` and `shoulder` are NEVER written. `pass_through` declares
///   `along`/`right` as its own taxonomy defaults; writing either here would
///   assert a direction and a shoulder the source did not state.
/// - The destination must resolve to exactly one dancer set. A non-dancer
///   destination ("to center", "to next star", "to second person"), a qualified
///   one ("to shadow S1", "to same-role neighbor") or any other leftover token
///   declines to custom — as does every walk-forward line carrying a travel
///   qualifier ("walk forward on left diagonal to N1"), which never reaches the
///   leading anchor.
_Match? _walkForwardTo(List<String> w) {
  if (w.length < 4 || w[0] != 'walk' || w[1] != 'forward' || w[2] != 'to') {
    return null;
  }
  final dest = w[3];
  if (!_dancerWords.containsKey(dest)) return null;
  var end = 4;
  var note = 'to $dest';
  // Absorb an optional trailing N-tag ("to neighbor N2") exactly as `_chain`
  // does, so the numeric qualifier does not survive as leftover → custom.
  if (end < w.length && _neighborNumbers.contains(w[end])) {
    note = '$note ${w[end]}';
    end++;
  }
  w.removeRange(0, end);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('pass_through', const {}, note);
}

// "pass the ocean" — the pass-through-to-an-ocean-wave figure (issue #290).
// Distinct from `pass_through`: the pass-through is intrinsic and the figure
// ends in a wave. A bare line states no balance/hands, so only the move id
// (plus an optional direction) is emitted; the MoveDef defaults supply the
// rest. "the" is filler, so "pass ocean" is accepted too. Deliberately does
// NOT recognise the legacy "form an ocean wave" phrasing — that stays custom
// here (the ContraDB adapter now maps it to pass_the_ocean; the legacy move
// was removed at v14).
_Match? _passTheOcean(List<String> w) {
  if (!_consumePhrase(w, ['pass', 'the', 'ocean']) &&
      !_consumePhrase(w, ['pass', 'ocean'])) {
    return null;
  }
  String? dir;
  if (_consumePhrase(w, ['across'])) {
    dir = 'across';
  }
  _dropFiller(w);
  return w.isEmpty ? _Match('pass_the_ocean', {'dir': ?dir}) : null;
}

// "form a wave" / "form short waves" / "form a short wave" / "form (a) wave of
// four" — the default short-wave case (issue #290; the "of four" wordings and
// the `with <dancer>` tail added at #295, TCB's dominant phrasings at ~1,000
// corpus clauses). Conservative: only the move id, an optional direction and an
// explicitly-stated `sides` pair are emitted; the rest come from defaults.
//
// Does not match the long-wave lines ("form a long wave", "form long waves") —
// their tokens are never consecutive with these phrases — so it neither shadows
// nor is shadowed. Waves of a DIFFERENT size ("form wave of two/three/six"),
// and the qualified formations TCB writes as "form NEW wave …", "form DIAGONAL
// wave of four", "form INTERSECTING/INTERLOCKING waves" all leave an
// unexplained token behind, so they still fall to custom (prefer-custom): the
// leading qualifier is never consumed and "of two/three/…" never matches.
_Match? _formShortWaves(List<String> w) {
  if (!_consumePhrase(w, ['form', 'a', 'wave', 'of', 'four']) &&
      !_consumePhrase(w, ['form', 'wave', 'of', 'four']) &&
      !_consumePhrase(w, ['form', 'a', 'wave']) &&
      !_consumePhrase(w, ['form', 'wave']) &&
      !_consumePhrase(w, ['form', 'a', 'short', 'wave']) &&
      !_consumePhrase(w, ['form', 'short', 'wave']) &&
      !_consumePhrase(w, ['form', 'short', 'waves'])) {
    return null;
  }
  String? dir;
  if (_consumePhrase(w, ['across'])) {
    dir = 'across';
  }
  // TCB names the pair on the ENDS of the wave as a "with <dancer>" tail
  // ("form wave of four with N2" / "… with shadow") — that is the `sides` pair.
  // Only consumed when the "with" is actually present, so no pair is invented.
  String? sides;
  if (_consumePhrase(w, ['with'])) {
    sides = _takeDancer(w);
    if (sides == null) return null; // "with <unknown>" -> custom.
  }
  _dropFiller(w);
  return w.isEmpty
      ? _Match('form_short_waves', {'dir': ?dir, 'sides': ?sides})
      : null;
}

_Match? _promenade(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['promenade'])) return null;
  final who2 = who ?? _takeDancer(w);
  // Consume an optional trailing direction (promenade's `dir` param). Prior to
  // this it was never consumed, so any directed promenade fell to custom.
  String? dir;
  if (_consumePhrase(w, ['across'])) {
    dir = 'across';
  } else if (_consumePhrase(w, ['along'])) {
    dir = 'along';
  }
  final turn = _takeSpinDirection(w);
  _consumePhrase(w, ['around', 'the', 'major', 'set']);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('promenade', {'who': ?who2, 'dir': ?dir, 'turn': ?turn});
}

/// Tier B: TCB writes "Shift left/right" *and* "Slide left/right" for a slide
/// along the set (the Becket slide to the next couple). Both are the same
/// `slide_along_set` move; TCB's "Slide right (past N)" spells the passed dancer
/// in a `(past …)` annotation, which `_normalize` strips (all 25 surveyed
/// "Slide" lines are this Becket slide, never a progression/other sense). A
/// direction is required — a bare "shift"/"slide" is too ambiguous → custom.
_Match? _shift(List<String> w) {
  if (!_consumePhrase(w, ['shift']) && !_consumePhrase(w, ['slide'])) {
    return null;
  }
  final slide = _takeSide(w);
  _dropFiller(w);
  if (slide == null || w.isNotEmpty) return null;
  return _Match('slide_along_set', {'slide': slide});
}

/// Tier A: TCB writes "Men give-and-take partner" / "Men give-and-take
/// neighbor" (hyphenated; TCB never spells the "give & take only" variant, so
/// `give` stays on its `true` default). The LEADING role is the giver (`who`,
/// restricted to role1s/role2s) and the TRAILING relationship is the target
/// (`whom`). Both are stated in-text — nothing is defaulted from an annotation.
/// The giver must LEAD and must be role1s/role2s, and the target must be
/// present; anything else (no leading role, a giver outside role1s/role2s, a
/// missing target, or leftover tokens) is rejected → custom rather than
/// structuring an unattested word order or dropping choreography.
_Match? _giveAndTake(List<String> w) {
  final who = _takeLeadingDancer(w); // leading giver role (must lead)
  final isGiveTake =
      _consumePhrase(w, ['give-and-take']) ||
      _consumePhrase(w, ['give', 'and', 'take']);
  if (!isGiveTake) return null;
  final whom = _takeLeadingDancer(w); // target relationship (leads remainder)
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  // The giver's domain is role1s/role2s only, and the target must be stated;
  // otherwise fall back to custom (never coerce a default giver/target).
  if (who != 'role1s' && who != 'role2s') return null;
  if (whom == null) return null;
  return _Match('give_and_take', {'who': who, 'whom': whom});
}

/// Tier A: TCB writes "Ones/Twos turn contra corners" (16 beats) — it ALWAYS
/// names the turning couple and uses the identifying "turn" lead word. The
/// LEADING dancer set maps to `who`; both the leading couple and the "turn"
/// keyword are REQUIRED. TCB never spells the embedded turning figure inline,
/// so contra_corners' `custom` text stays empty (its taxonomy default). A bare
/// "contra corners", a missing "turn", a dancer that does not lead, or any
/// leftover token all force the custom fallback (defaulting `who` would
/// fabricate the couple).
_Match? _contraCorners(List<String> w) {
  final who = _takeLeadingDancer(w);
  if (who == null) return null; // couple must be stated and lead
  if (!_consumePhrase(w, ['turn'])) return null; // identifying "turn" keyword
  if (!_consumePhrase(w, ['contra', 'corners'])) return null;
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('contra_corners', {'who': who});
}

_Match? _longLines(List<String> w) {
  // TCB writes "In long lines, ..." exclusively; consume the leading "in".
  _consumePhrase(w, ['in']);
  if (!_consumePhrase(w, ['long', 'lines'])) return null;
  // Accept only the canonical "[go] forward and back" descriptor, or bare
  // "long lines"; a partial "forward"/"back"/"and" alone is NOT enough — it
  // would leave the phrase half-described, so it falls through to custom.
  _consumePhrase(w, ['go']);
  _consumePhrase(w, ['forward', 'and', 'back']);
  _dropFiller(w);
  return w.isEmpty ? const _Match('long_lines') : null;
}

/// Tier A: TCB writes "Slice left/right" (dance id 1860 "Power Surge"). The
/// direction maps to the `slice` choice param; `by`/`return` stay on their
/// taxonomy defaults. A side is required — a bare "slice" is too ambiguous, so
/// it falls to custom.
_Match? _slice(List<String> w) {
  if (!_consumePhrase(w, ['slice'])) return null;
  final side = _takeSide(w);
  _dropFiller(w);
  if (side == null || w.isNotEmpty) return null;
  return _Match('slice', {'slice': side});
}

/// Tier A: TCB writes "Turn alone" / "Ones turn alone" (dance ids 25, 2). An
/// optional dancer set (before or after "turn alone") maps to `who`; otherwise
/// the taxonomy default (everyone) applies.
_Match? _turnAlone(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['turn', 'alone'])) return null;
  final who2 = who ?? _takeDancer(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('turn_alone', {'who': ?who2});
}

/// Tier A: TCB writes "Partner poussette clockwise 1/2" (dance id 488 "Rough
/// Ride"). The spin word maps to `turn` (spinDirection) and the fraction to
/// `half`. Anything else left over (e.g. "draw", or a non-half fraction like
/// "9/16") forces the custom fallback.
_Match? _poussette(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['poussette'])) return null;
  final who2 = who ?? _takeDancer(w);
  String? spin;
  if (_consumePhrase(w, ['clockwise'])) {
    spin = 'clockwise';
  } else if (_consumePhrase(w, ['counterclockwise'])) {
    spin = 'counterclockwise';
  }
  String? frac;
  if (_consumePhrase(w, ['1/2'])) {
    frac = 'half';
  } else if (_consumePhrase(w, ['full']) || _consumePhrase(w, ['1'])) {
    frac = 'full';
  }
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('poussette', {'who': ?who2, 'turn': ?spin, 'half': ?frac});
}

/// Issue #295: standalone `orbit` — TCB writes "Men orbit clockwise 1/2" /
/// "Women orbit counterclockwise 1/2". Conservative whole-line recognition:
/// the rotation direction (`turn`, reusing `ParamKind.spinDirection`) and the
/// turn amount (`amount`) must BOTH be stated; a bare "orbit", a missing
/// direction or amount, or any leftover token yields null so the line degrades
/// to a faithful custom figure. An optional trailing "around" (the ContraDB
/// combined-side phrasing "… orbit clockwise ½ around") is consumed as filler
/// so the recognizer still fully accounts for the line. Only `who` falls back
/// to a default (flagged as an assumed subject), never the direction/amount.
_Match? _orbit(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['orbit'])) return null;
  final who2 = who ?? _takeDancer(w);
  final spin = _takeSpinDirection(w);
  if (spin == null) return null; // an orbit always states its direction
  final amount = _takeRotation(w);
  if (amount == null) return null; // the amount is never fabricated
  _consumePhrase(w, ['around']); // optional ContraDB-side trailing token
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match(
    'orbit',
    {'who': who2 ?? 'ones', 'turn': spin, 'amount': amount},
    null,
    who2 == null,
  );
}

/// Issue #295: TCB's `mad robin`. TCB writes the figure with detail ContraDB
/// does not model — "Mad robin clockwise around neighbor", "Mad robin
/// counterclockwise around partner", "Mad robin clockwise 1 & 1/2 around
/// neighbor N2" — and states BOTH facts on every surveyed line (24/24 in a
/// 5,147-line sample), so both are REQUIRED here:
/// - the rotation `direction` (TCB glossary: "a clockwise mad robin begins with
///   the left-hand person going in front"), and
/// - the "around `<whom>`" target (TCB glossary: "you travel in an oval around
///   the person at your side… **Who you go around is listed**").
///
/// `whom` is deliberately NOT folded into `who`: ContraDB's `who` names which
/// pair steps IN FRONT (`madRobinWords` renders "`<who>` in front"), a different
/// concept, so reusing it would invert the meaning of every ContraDB import.
/// TCB never states the in-front role, so `who` is left unset and the match is
/// flagged as an assumed subject (#460).
///
/// A rotation amount is optional (TCB states one on 2/24 lines) and maps to the
/// existing `turn` — ContraDB's `circling`/`once_around` angle. A missing
/// direction, a missing "around `<target>`", or ANY leftover token yields null so
/// the line degrades to a faithful custom figure.
_Match? _madRobin(List<String> w) {
  if (!_consumePhrase(w, ['mad', 'robin'])) return null;
  final direction = _takeSpinDirection(w);
  if (direction == null) return null; // TCB always states the direction
  final turn = _takeRotation(w);
  if (!_consumePhrase(w, ['around'])) return null;
  final whom = _takeRelationship(w);
  if (whom == null) return null; // and always states what you go around
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match(
    'mad_robin',
    {'direction': direction, 'turn': ?turn, 'whom': whom},
    null,
    // TCB never names the in-front role, so `who` falls back to the taxonomy
    // default and must be surfaced as assumed rather than as source fact.
    true,
  );
}

/// Issue #295: TCB's `butterfly whirl` — "Partner butterfly whirl
/// counterclockwise", "N2 neighbor butterfly whirl clockwise". TCB's glossary
/// defines the figure as "two people … rotate clockwise or counterclockwise
/// about a common center", and states BOTH the pair and the direction on every
/// surveyed line (18/18), so both are required here. ContraDB models `beats`
/// alone, so its own recognizer (`contradb_figure_dialect.dart`) is unchanged
/// and keeps asserting neither.
///
/// There is deliberately NO rotation-amount slot: TCB states an amount on 4/18
/// lines ("… counterclockwise 1 & 1/2"), but neither ContraDB nor the TCB
/// glossary models one, so those lines correctly stay custom (prefer-custom)
/// rather than having the amount silently dropped from a structured figure.
_Match? _butterflyWhirl(List<String> w) {
  final who = _takeRelationship(w);
  if (!_consumePhrase(w, ['butterfly', 'whirl'])) return null;
  final who2 = who ?? _takeRelationship(w);
  if (who2 == null) return null; // TCB always names the whirling pair
  final direction = _takeSpinDirection(w);
  if (direction == null) return null; // … and always states the direction
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('butterfly_whirl', {'who': who2, 'direction': direction});
}

/// Tier A: TCB writes "Partner California twirl" (dance id 11 "Hocus Pocus").
_Match? _californiaTwirl(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['california', 'twirl'])) return null;
  final who2 = who ?? _takeDancer(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('california_twirl', {'who': ?who2});
}

// "Weave the line" is a caller synonym for the existing (ContraDB-sourced)
// `zig_zag` move (ratified in D4). It carries no separate turn/ender on the
// line, so those stay at zig_zag's inherent taxonomy defaults (there is no
// cross-line turn/ender fold for zig_zag). An optional leading/trailing dancer
// set maps to `who`; any other leftover token forces the custom fallback.
_Match? _weaveTheLine(List<String> w) {
  if (!_consumePhrase(w, ['weave', 'the', 'line'])) return null;
  // TCB writes "Weave the line with partner (L;R to N2)": the pass list is an
  // annotation (dropped by `_normalize`), and "with <dancer>" names the set —
  // consume the optional "with" so the dancer resolves to `who` instead of
  // leaving a stray "with" that would force custom.
  _consumePhrase(w, ['with']);
  final who = _takeDancer(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('zig_zag', {'who': ?who});
}

/// Tier A: TCB writes "Partner star promenade 1/2" (dance id 30 "Mad Gypsy").
/// The optional dancer set maps to `who` — the dancer you PICK UP on the side
/// (taxonomy v26, #843) — and a rotation amount to `turn`.
///
/// **A stated hand is consumed and DISCARDED here, on purpose.** `star_promenade`
/// declared a `hand` until v26, and prose like "Neighbor star promenade right
/// 1/2" set it. The owner ruled (2026-08-06) that rendering the hand beside the
/// subject implies a right-hand connection with the neighbor when the
/// connection is between the two dancers in the CENTER, so the param was
/// removed. The side is still EATEN rather than left in `w`, because an
/// unconsumed token forces the whole line to the custom fallback and would
/// regress every "star promenade right" line from structured to custom.
///
/// TCB's `(WR)`/`(ML)` annotations state the center pair. `_normalize` strips
/// them before this runs, so they are picked up earlier by
/// `_starPromenadeAnnotation` in `callersbox_figure_dialect.dart`, which
/// preserves them as a note. Must precede `_star` in `_recognizers` so the
/// shared "star" lead phrase resolves to this more specific move first.
_Match? _starPromenade(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['star', 'promenade'])) return null;
  final who2 = who ?? _takeDancer(w);
  _takeSide(w); // consumed, then discarded — see the doc comment above.
  final turn = _takeRotation(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('star_promenade', {'who': ?who2, 'turn': ?turn});
}

/// Tier A: TCB writes "Square through 3" / "Square through 4" (dance id 322
/// "Whim's Gym"). Only a digit count is consumed (TCB never spells the count
/// out); the word form "square through four" stays custom. A bare "square
/// through" uses the taxonomy default (4 places).
_Match? _squareThrough(List<String> w) {
  if (!_consumePhrase(w, ['square', 'through'])) return null;
  int? places;
  for (var i = 0; i < w.length; i++) {
    final n = int.tryParse(w[i]);
    if (n != null && n >= 1 && n <= 10) {
      w.removeAt(i);
      places = n;
      break;
    }
  }
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('square_through', {'places': ?places});
}

/// Tier A: TCB writes "Men pull by left" / "Partner pull by left" (dance ids
/// 481, 467). A named dancer set maps to `pull_by_dancers` (with hand); a form
/// with only a spatial direction (or bare) maps to `pull_by_direction`. TCB's
/// attested pull-bys all name a dancer, so the direction branch is defensive.
_Match? _pullBy(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['pull', 'by'])) return null;
  final who2 = who ?? _takeDancer(w);
  final hand = _takeSide(w);
  if (who2 != null) {
    // Dancer form → pull_by_dancers, which has NO direction slot. Do NOT
    // consume across/along here: leaving it as leftover makes a
    // "<dancer> pull by <hand> across" line fall to custom rather than
    // silently dropping the direction (which pull_by_dancers can't carry).
    _dropFiller(w);
    if (w.isNotEmpty) return null;
    return _Match('pull_by_dancers', {'who': who2, 'hand': ?hand});
  }
  // Direction-only (or bare) form → pull_by_direction.
  String? dir;
  if (_consumePhrase(w, ['across'])) {
    dir = 'across';
  } else if (_consumePhrase(w, ['along'])) {
    dir = 'along';
  }
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('pull_by_direction', {'dir': ?dir, 'hand': ?hand});
}

/// Tier B: TCB writes "Neighbor roll away" / "Partner roll away (W roll R, M
/// side-step L)" — the styling parenthetical is dropped by `_normalize`. The
/// stated relationship maps to `who` (matching the canonical ContraDB order
/// "gentlespoons roll away neighbors with a half sashay …", where the dancer
/// before "roll away" is `who` and a dancer after it is `whom`). "with a half
/// sashay" sets the `halfSashay` flag. roll_away has NO direction slot, so a
/// trailing across/along (canonical spelling; TCB's is a stripped annotation)
/// is consumed and not represented — the taxonomy deliberately omits it.
_Match? _rollAway(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['roll', 'away'])) return null;
  final who2 = who ?? _takeDancer(w);
  final whom = _takeDancer(w);
  final half =
      _consumePhrase(w, ['with', 'a', 'half', 'sashay']) ||
      _consumePhrase(w, ['with', 'half', 'sashay']) ||
      _consumePhrase(w, ['half', 'sashay']);
  _consumePhrase(w, ['across']);
  _consumePhrase(w, ['along']);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match(
    'roll_away',
    {'who': ?who2, 'whom': ?whom, if (half) 'halfSashay': true},
    null,
    who2 == null,
  );
}

/// Tier B: TCB writes "Cross trail through (PR;NL)" — the pass-list annotation
/// is dropped by `_normalize`, leaving the bare figure. An optional leading
/// dancer maps to `who`, a following dancer to `who2`, and across/along to
/// `dir`; all else falls to the taxonomy defaults. "cross trail" (no "through")
/// and the plural "cross trails" are accepted too.
_Match? _crossTrails(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['cross', 'trail', 'through']) &&
      !_consumePhrase(w, ['cross', 'trails']) &&
      !_consumePhrase(w, ['cross', 'trail'])) {
    return null;
  }
  final who2 = who ?? _takeDancer(w);
  String? dir;
  if (_consumePhrase(w, ['across'])) {
    dir = 'across';
  } else if (_consumePhrase(w, ['along'])) {
    dir = 'along';
  }
  final second = _takeDancer(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('cross_trails', {'who': ?who2, 'dir': ?dir, 'who2': ?second});
}

/// Tier B: TCB writes "Ones figure eight 1/2 up" / "Twos figure eight down".
/// The dancer maps to `who`; the fraction to `half`
/// (1/2→half, 1/4→quarter, 3/4→threeQuarter, 1|full→full); and the TCB
/// direction vocabulary up/down maps to the taxonomy's above/below (`across`
/// passes through unchanged). Anything left over → custom.
_Match? _figure8(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['figure', '8']) &&
      !_consumePhrase(w, ['figure', 'eight'])) {
    return null;
  }
  final who2 = who ?? _takeDancer(w);
  String? half;
  if (_consumePhrase(w, ['1/2'])) {
    half = 'half';
  } else if (_consumePhrase(w, ['1/4'])) {
    half = 'quarter';
  } else if (_consumePhrase(w, ['3/4'])) {
    half = 'threeQuarter';
  } else if (_consumePhrase(w, ['1']) ||
      _consumePhrase(w, ['full']) ||
      _consumePhrase(w, ['once'])) {
    half = 'full';
  }
  String? dir;
  if (_consumePhrase(w, ['up']) || _consumePhrase(w, ['above'])) {
    dir = 'above';
  } else if (_consumePhrase(w, ['down']) || _consumePhrase(w, ['below'])) {
    dir = 'below';
  } else if (_consumePhrase(w, ['across'])) {
    dir = 'across';
  }
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match(
    'figure_8',
    {'who': ?who2, 'half': ?half, 'dir': ?dir},
    null,
    who2 == null,
  );
}

/// Tier B: TCB writes "Form long waves" / "Form (a) long wave [in center]".
/// The plural maps to `form_long_waves`; the singular to `form_a_long_wave`.
/// An optional leading dancer maps to `who`; a trailing "in (the) center"
/// locator (a formation cue, not a structured slot) is consumed. TCB almost
/// always writes these inside a `;`-compound ("Star left 1; form long wave"),
/// which the fan-out splits — this recognizer structures the wave clause so the
/// whole compound can succeed when the other clause structures too.
_Match? _formLongWave(List<String> w) {
  String? consumeLongWave() {
    if (_consumePhrase(w, ['form', 'long', 'waves']) ||
        _consumePhrase(w, ['form', 'a', 'long', 'waves'])) {
      return 'form_long_waves';
    }
    if (_consumePhrase(w, ['form', 'a', 'long', 'wave']) ||
        _consumePhrase(w, ['form', 'long', 'wave'])) {
      return 'form_a_long_wave';
    }
    return null;
  }

  final who = _takeDancer(w);
  final moveId = consumeLongWave();
  if (moveId == null) return null;
  final who2 = who ?? _takeDancer(w);
  // Optional "in (the) center" formation locator.
  _consumePhrase(w, ['in', 'the', 'center']) ||
      _consumePhrase(w, ['in', 'center']);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match(moveId, {'who': ?who2}, null, who2 == null);
}

/// Tier B: TCB writes "Men trade" / "Women trade" / "Neighbor trade" — a trade
/// is a pass-by (the pair change places passing right shoulders), so it maps to
/// `pass_by` with the stated `who` and the taxonomy's default right shoulder
/// (an explicit "left/right [shoulder]" overrides), and likewise "trade by
/// [the] left/right [shoulder(s)]" (issue #945, defect C — the owner ruled
/// this is the MWSD "Trade By" call and should structure; a corpus scan of
/// ~24k dances found 709 `trade by` occurrences and zero instances of `trade
/// by the` used any other way). `trade the wave` / `trade the line` remain
/// excluded: corpus evidence supports them as distinct, unmodelled
/// whole-wave/line constructions rather than a two-dancer pass-by.
_Match? _tradePassBy(List<String> w) {
  if (_hasPhrase(w, ['trade', 'the', 'wave']) ||
      _hasPhrase(w, ['trade', 'the', 'line'])) {
    return null;
  }
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['trade'])) return null;
  final who2 = who ?? _takeDancer(w);
  // "trade by" is consumed here (rather than folded into a shoulder phrase)
  // because a leftover `by` with no side word (e.g. a bare "trade by") must
  // still structure, matching the plain "trade" case above.
  _consumePhrase(w, ['by']);
  final shoulder = _takeSide(w);
  _consumePhrase(w, ['shoulder']);
  _consumePhrase(w, ['shoulders']);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match(
    'pass_by',
    {'who': ?who2, 'shoulder': ?shoulder},
    null,
    who2 == null,
  );
}

/// Tier B: TCB writes "Men pass left" / "Women pass right" / "Men cross by
/// right" / "Partner pass right" — all a pass-by, unified onto `pass_by` with
/// the stated `who` and the left/right `shoulder`. A side is REQUIRED: a bare
/// "pass"/"cross by" is left for the more specific pass recognizers
/// ("pass through", "pass the ocean", "cross trail through") and otherwise
/// falls to custom, so this never mis-claims them (each declines here because a
/// side is absent and/or tokens are left over).
_Match? _passCrossBy(List<String> w) {
  final who = _takeDancer(w);
  final ok = _consumePhrase(w, ['pass']) || _consumePhrase(w, ['cross', 'by']);
  if (!ok) return null;
  final who2 = who ?? _takeDancer(w);
  final shoulder = _takeSide(w);
  if (shoulder == null) return null;
  _consumePhrase(w, ['shoulder']);
  _consumePhrase(w, ['shoulders']);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match(
    'pass_by',
    {'who': ?who2, 'shoulder': shoulder},
    null,
    who2 == null,
  );
}

/// Tier A: TCB writes "Rory O'More" (dance ids 6, 39), optionally with a slide
/// direction ("Rory O'More right"). An optional dancer set maps to `who` and a
/// left/right to `slide`; both fall to the taxonomy default when absent. The
/// surname is accepted in the common apostrophe spellings (`o'more` with an
/// ASCII apostrophe, `o’more` with U+2019, or `omore`) and is optional (a bare
/// "Rory" is unambiguous). Rarer apostrophe codepoints are not recognised and
/// fall to custom via the leftover-token guard.
///
/// We emit `balance: false` EXPLICITLY for import fidelity. TCB writes the
/// balance as a SEPARATE preceding line (ratified D1: "balance(4)+rory(4)"), so
/// a standalone rory LINE is the 4-beat unbalanced slide — it does NOT carry a
/// balance. Rory's MoveDef defaults `balance: true`, so DO NOT restore that
/// default here: inheriting it would fabricate a balance the line never stated
/// (and `false`→4 beats matches rory's paramBeats). PR3b's cross-line merge
/// flips this to `true` when a preceding balance line exists.
///
/// Trailing structure ("Rory O'More and swing") leaves leftover tokens, so it
/// falls to custom. An out-of-domain `who` (e.g. "neighbors", not in Rory's
/// dancer choices) is rejected by validation → custom.
_Match? _roryOMore(List<String> w) {
  final who = _takeDancer(w);
  final slide = _takeSide(w);
  if (!_consumePhrase(w, ['rory'])) return null;
  // Optional "O'More" surname token, in the common apostrophe spellings.
  const surnames = {"o'more", 'o\u2019more', 'omore'};
  if (w.isNotEmpty && surnames.contains(w.first)) w.removeAt(0);
  final who2 = who ?? _takeDancer(w);
  final slide2 = slide ?? _takeSide(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('rory_o_more', {
    'who': ?who2,
    'slide': ?slide2,
    'balance': false,
  });
}

/// Consumes an optional LEADING "[In] [a] [cozy] line of four" formation clause
/// that TCB puts before a down/up-the-hall figure (across the corpus:
/// "In a line of four, go down the hall (M1-W2-M2-W1)"). A line of four is the
/// DEFAULT formation for a hall figure, so — exactly like the stripped
/// dancer-order annotation "(M1-W2-M2-W1)" — dropping it does not change the
/// move (down_the_hall/up_the_hall carry no formation param). The clause is
/// stripped ONLY when it leads the line: every token before "line of four" must
/// be part of the allowed framing (in / a / an / the / cozy). A "line of four"
/// that appears mid-line (belonging to some other construction) is left in
/// place, so the recognizer never structures a line it wasn't meant to cover.
void _consumeLineOfFour(List<String> w) {
  const framing = {'in', 'a', 'an', 'the', 'cozy'};
  var i = 0;
  while (i < w.length && framing.contains(w[i])) {
    i++;
  }
  if (i + 3 <= w.length &&
      w[i] == 'line' &&
      w[i + 1] == 'of' &&
      w[i + 2] == 'four') {
    w.removeRange(0, i + 3);
  }
}

/// Tier A: TCB writes "Go down the hall" / "Down the hall" (dance ids 10945,
/// 11239, 12001), and frames a foursome as "In a line of four, go down the
/// hall" — the optional leading formation clause is consumed by
/// [_consumeLineOfFour] (a line of four is the default hall formation). An
/// optional leading "go" and an optional dancer set are also consumed, and the
/// "the" is optional so the shorter alias "down hall" is accepted. A TRAILING
/// descriptor that changes the move — "and back" (forward-then-backward) or a
/// "four in line" that is not the leading "line of four" clause — is left as
/// leftover, so those lines stay custom.
///
/// We emit `ender: 'none'` EXPLICITLY for import fidelity. TCB writes the ender
/// as a SEPARATE following line (the bend-the-line cross-line proof, ids
/// 10945/11239/12001), so a bare hall line states no ender. down_the_hall's
/// MoveDef defaults `ender: 'turnCouple'`, so DO NOT restore that default here:
/// inheriting it would assert a turn the line never stated and double-count the
/// ender when it IS on the next line. `none` = "ender not determined on this
/// line"; PR3b's cross-line merge upgrades `none`→`bendTheLine`.
_Match? _downTheHall(List<String> w) {
  _consumeLineOfFour(w);
  final who = _takeDancer(w);
  // "Ones lead down" (the actives lead down the center) — TCB's shorthand for
  // a hall figure whose `moving` set is the center couple.
  final lead = _consumePhrase(w, ['lead']);
  _consumePhrase(w, ['go']);
  final hall =
      _consumePhrase(w, ['down', 'the', 'hall']) ||
      _consumePhrase(w, ['down', 'hall']);
  String? moving;
  if (!hall) {
    if (_consumePhrase(w, ['down', 'the', 'outside']) ||
        _consumePhrase(w, ['down', 'outside'])) {
      // "Ones go down outside" → the outside dancers travel down.
      moving = 'outsides';
    } else if (lead && _consumePhrase(w, ['down'])) {
      moving = 'center';
    } else {
      return null;
    }
  }
  final who2 = who ?? _takeDancer(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('down_the_hall', {
    'who': ?who2,
    'moving': ?moving,
    'ender': 'none',
  });
}

/// Tier A: TCB writes "Go up the hall" / "Up the hall". Mirror of
/// [_downTheHall]; same conservative descriptor handling and the same optional
/// "the" (so "up hall" is accepted). Emits `ender: 'none'` explicitly for the
/// same reason (up_the_hall's MoveDef defaults `circle`; DO NOT restore that
/// default here — PR3b's merge sets the real ender).
_Match? _upTheHall(List<String> w) {
  _consumeLineOfFour(w);
  final who = _takeDancer(w);
  final lead = _consumePhrase(w, ['lead']);
  _consumePhrase(w, ['go']);
  final hall =
      _consumePhrase(w, ['up', 'the', 'hall']) ||
      _consumePhrase(w, ['up', 'hall']);
  String? moving;
  if (!hall) {
    if (_consumePhrase(w, ['up', 'the', 'outside']) ||
        _consumePhrase(w, ['up', 'outside'])) {
      moving = 'outsides';
    } else if (lead && _consumePhrase(w, ['up'])) {
      moving = 'center';
    } else {
      return null;
    }
  }
  final who2 = who ?? _takeDancer(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('up_the_hall', {
    'who': ?who2,
    'moving': ?moving,
    'ender': 'none',
  });
}
