import '../model/figure.dart';
import '../taxonomy/contra_taxonomy.dart';
import '../taxonomy/taxonomy.dart';
import '../validation/validation.dart';
import 'figure_text_scrub.dart';
import 'structured_draft.dart';

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
}) {
  final scrubFn = scrub ?? scrubFigureText;
  final tax = taxonomy ?? contraTaxonomy;
  // Negative beats are meaningless; normalise to 0 (treated as absent) so the
  // parse-never-fails contract holds even for malformed source beats —
  // `customFigure` throws on a negative beat count.
  final safeBeats = beats < 0 ? 0 : beats;

  final scrubbed = scrubFn(rawText);
  if (scrubbed.isEmpty) return null;

  Figure fallback() =>
      customFigure(scrubbed, beats: safeBeats, progression: progression);

  try {
    final match = _recognize(scrubbed);
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
    );
    final hasError = tax
        .validateFigure(candidate)
        .any((i) => i.severity == ValidationSeverity.error);
    return hasError ? fallback() : candidate;
  } catch (_) {
    return fallback();
  }
}

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
/// - **`||` (simultaneity) stays custom.** Any line containing a top-level `||`
///   (`A || B`) is left whole-custom: the model cannot represent two moves at
///   once, so structuring it would fabricate a relationship.
/// - **Lossless beats.** [deriveSections] sums each figure's `beats`
///   cumulatively to place section labels, so a split MUST preserve the source
///   line's TOTAL beats exactly — no more (double-count) and no less (section
///   underflow/drift). The source states only one combined total for the whole
///   compound (never per-move beats), so that total rides on the FIRST clause
///   and the remaining clauses are beats-absent. The cumulative beat total is
///   then byte-identical to the un-split compound, and nothing the source
///   actually stated is dropped or invented.
List<Figure> parseFigureLines(
  String rawText, {
  int beats = 0,
  bool progression = false,
  Taxonomy? taxonomy,
  String Function(String)? scrub,
}) {
  Figure? whole() => parseFigureLine(
    rawText,
    beats: beats,
    progression: progression,
    taxonomy: taxonomy,
    scrub: scrub,
  );

  List<Figure> wholeAsList() {
    final f = whole();
    return f == null ? const [] : [f];
  }

  // Simultaneity is not modelled → keep the whole line custom (never split).
  if (_hasTopLevel(rawText, '||')) return wholeAsList();

  final clauses = _splitTopLevel(rawText, ';');
  if (clauses.length < 2) return wholeAsList();
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
    );
    // All-or-nothing: any clause that fails to structure (null/empty or custom)
    // collapses the whole line back to a single custom figure.
    if (f == null || f.isCustom) return wholeAsList();
    parsed.add(f);
  }
  return parsed;
}

/// Whether [sep] occurs at bracket depth 0 in [t] (outside any `()`/`[]`). Used
/// to find genuine clause separators while ignoring separators inside CallersBox
/// annotations like a hey's `(PR;WL;NR;ML)` pass list.
bool _hasTopLevel(String t, String sep) {
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

/// A recognised move: its taxonomy [moveId] and the params extracted from the
/// text (never including `beats`, which the caller layers on from the source).
class _Match {
  const _Match(this.moveId, [this.params = const {}, this.note]);
  final String moveId;
  final Map<String, Object?> params;

  /// Optional free-text note preserved from the source when a detail cannot be
  /// expressed as a structured param (e.g. chain's "to neighbor" target).
  final String? note;
}

/// Attempts to recognise [scrubbed] as one covered move. Returns `null` when no
/// recognizer accounts for the whole line (→ custom fallback).
_Match? _recognize(String scrubbed) {
  // The hey recognizer runs FIRST and on the RAW scrubbed text, not the
  // normalized word list: a TCB hey carries its structured payload (the pass
  // list) INSIDE parentheses, which `_normalize` strips as a non-structural
  // annotation for every other move. `_hey` is highly specific — it requires
  // the `hey` anchor plus a fully decodable pass list and rejects `dolphin
  // hey` — so running it ahead of the generic recognizers cannot shadow them.
  final hey = _hey(scrubbed);
  if (hey != null) return hey;

  final words = _normalize(scrubbed);
  if (words.isEmpty) return null;

  for (final recognizer in _recognizers) {
    final match = recognizer(List<String>.of(words));
    if (match != null) return match;
  }
  return null;
}

/// Lowercases, strips `()`/`[]` parenthetical annotations (TCB appends shoulder
/// / param notes like `(NR)` or `(W1-M2-W2-M1)`), maps `&`→`and` and
/// `thru`→`through`, folds the common unicode halves/quarters, strips
/// surrounding punctuation, and splits into words.
///
/// The annotation strip is for RECOGNITION only, so a structured match does
/// NOT retain the bracketed text — the value it carried (e.g. shoulder/param
/// hints) is not part of the taxonomy figure. The annotation only survives on
/// the *custom fallback*, which runs on the un-normalized scrubbed text: a line
/// that fails recognition keeps its annotation verbatim in the custom figure.
List<String> _normalize(String text) {
  var s = text.toLowerCase();
  // Drop bracketed/parenthesized annotations for RECOGNITION only. This trims
  // them from the structured match; the custom fallback path operates on the
  // original scrubbed text, so an *unrecognized* line still keeps its
  // annotation.
  s = s
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
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
  _rightLeftThrough,
  _passThrough,
  _promenade,
  _shift,
  _longLines,
  _slice,
  _turnAlone,
  _contraCorners,
  _giveAndTake,
  _poussette,
  // No `_gate` recognizer — deliberately. TCB gate = clockwise or
  // counterclockwise or mirror + turn fraction (+ optional which-pair-forward
  // note); ContraDB gate = facing up/down/in/out, fixed 8 beats. The domains are
  // disjoint (0/62 surveyed TCB gate lines map to `face`), so a recognizer would
  // match nothing or fabricate a `face` the line never stated. For import
  // fidelity, TCB gate stays custom until a source-backed model exists.
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
  return _Match('swing', {
    'who': who2 ?? 'partners',
    if (prefix != 'none') 'prefix': prefix,
  });
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
  return _Match('balance', {'who': who2 ?? 'neighbors'});
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
  return _Match('shoulder_round', {
    'who': who2 ?? 'neighbors',
    'shoulder': ?side2,
    'turn': ?turn,
  });
}

_Match? _allemande(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['allemande'])) return null;
  final who2 = who ?? _takeDancer(w);
  final hand = _takeSide(w);
  final turn = _takeRotation(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('allemande', {
    'who': who2 ?? 'neighbors',
    'hand': ?hand,
    'turn': ?turn,
  });
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
  return _Match(moveId, {'who': who2 ?? 'neighbors', 'turn': ?turn});
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
  return _Match(moveId, {'who': who2 ?? 'partners'});
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
  return _Match('box_circulate', {'who': who2 ?? 'partners'});
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
  return _Match('star_through', {'who': who2 ?? 'partners'});
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
  // TCB writes "Ladies chain to neighbor/partner" exclusively. Preserve the
  // "to <dancer>" target as a Figure NOTE rather than folding it into `who`
  // (which would misrepresent the chaining set). Capture it FIRST so its
  // dancer isn't consumed as the chaining set by the _takeDancer calls below.
  String? note;
  final toIdx = w.indexOf('to');
  if (toIdx != -1 &&
      toIdx + 1 < w.length &&
      _dancerWords.containsKey(w[toIdx + 1])) {
    note = 'to ${w[toIdx + 1]}';
    w.removeRange(toIdx, toIdx + 2);
  }
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['chain'])) return null;
  final who2 = who ?? _takeDancer(w);
  // Optional direction.
  String? dir;
  if (_consumePhrase(w, ['across'])) {
    dir = 'across';
  } else if (_consumePhrase(w, ['along'])) {
    dir = 'along';
  }
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  // chain's `who` domain is role1s/role2s only. An explicit dancer set outside
  // that domain (e.g. "partners chain") must NOT be silently dropped to the
  // taxonomy default — that would misrepresent the source — so reject the
  // match and let it fall back to custom. No explicit dancer → leave `who`
  // unset so the taxonomy default (role2s) applies.
  if (who2 != null && who2 != 'role1s' && who2 != 'role2s') return null;
  return _Match('chain', {'who': ?who2, 'dir': ?dir}, note);
}

_Match? _rightLeftThrough(List<String> w) {
  final ok =
      _consumePhrase(w, ['right', 'left', 'through']) ||
      _consumePhrase(w, ['right', 'and', 'left', 'through']);
  if (!ok) return null;
  String? dir;
  if (_consumePhrase(w, ['across'])) {
    dir = 'across';
  } else if (_consumePhrase(w, ['along'])) {
    dir = 'along';
  }
  // TCB writes "...right and left through with partner/neighbor" exclusively;
  // consume the trailing "with <dancer>" qualifier (no structured slot).
  if (_consumePhrase(w, ['with'])) {
    _takeDancer(w);
  }
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('right_left_through', {'dir': ?dir});
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
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('promenade', {'who': ?who2, 'dir': ?dir});
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
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['weave', 'the', 'line'])) return null;
  final who2 = who ?? _takeDancer(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('zig_zag', {'who': ?who2});
}

/// Tier A: TCB writes "Partner star promenade 1/2" (dance id 30 "Mad Gypsy").
/// The optional dancer set maps to `who`, an explicit hand to `hand`, and a
/// rotation amount to `turn`. TCB's "(WL)"/"(WR)" hand annotations are stripped
/// by `_normalize`, so the hand there stays on the taxonomy default. Must
/// precede `_star` in `_recognizers` so the shared "star" lead phrase resolves
/// to this more specific move first.
_Match? _starPromenade(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['star', 'promenade'])) return null;
  final who2 = who ?? _takeDancer(w);
  final hand = _takeSide(w);
  final turn = _takeRotation(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('star_promenade', {'who': ?who2, 'hand': ?hand, 'turn': ?turn});
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
  _consumePhrase(w, ['go']);
  if (!_consumePhrase(w, ['down', 'the', 'hall']) &&
      !_consumePhrase(w, ['down', 'hall'])) {
    return null;
  }
  final who2 = who ?? _takeDancer(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('down_the_hall', {'who': ?who2, 'ender': 'none'});
}

/// Tier A: TCB writes "Go up the hall" / "Up the hall". Mirror of
/// [_downTheHall]; same conservative descriptor handling and the same optional
/// "the" (so "up hall" is accepted). Emits `ender: 'none'` explicitly for the
/// same reason (up_the_hall's MoveDef defaults `circle`; DO NOT restore that
/// default here — PR3b's merge sets the real ender).
_Match? _upTheHall(List<String> w) {
  _consumeLineOfFour(w);
  final who = _takeDancer(w);
  _consumePhrase(w, ['go']);
  if (!_consumePhrase(w, ['up', 'the', 'hall']) &&
      !_consumePhrase(w, ['up', 'hall'])) {
    return null;
  }
  final who2 = who ?? _takeDancer(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('up_the_hall', {'who': ?who2, 'ender': 'none'});
}

// --- Hey (TCB pass-list) recognizer ------------------------------------------
//
// TCB writes heys as an optional fraction plus a `;`-separated pass list inside
// parentheses: "Hey 1/2 (WR;PL;MR;N2L~)", "Full hey (ML;PR)". This is the ONE
// recognizer that reads parenthetical content, because the pass list is the
// hey's structured payload rather than a droppable annotation (see the note in
// `_recognize`). It decodes onto the existing `hey` MoveDef:
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
/// (they are not word-boundary role terms), so map them here.
const Map<String, String> _heyPeople = {
  'm': 'role1s',
  'w': 'role2s',
  'p': 'partners',
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

_Match? _hey(String scrubbed) {
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

  // The non-paren remainder must be exactly {hey, optional fraction, filler};
  // anything else (a trailing move, a second parenthetical, ...) -> custom.
  final outWords = outside
      .replaceAll('½', ' 1/2 ')
      .replaceAll('¼', ' 1/4 ')
      .replaceAll('¾', ' 3/4 ')
      .split(RegExp(r'\s+'))
      .map(_stripEdgePunct)
      .where((w) => w.isNotEmpty)
      .toList();

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

  final params = <String, Object?>{'length': length};
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
      final who = _heyPeople[people];
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
    final who = _heyPeople[cell.substring(0, cell.length - 1)];
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
  return _Match('hey', params);
}
