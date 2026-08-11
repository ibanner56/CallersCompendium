import '../model/figure.dart';
import '../taxonomy/contra_taxonomy.dart';
import '../taxonomy/move_def.dart';
import '../taxonomy/param_types.dart';
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
///
/// Pre-recognizer order is not correctness-critical: each requires a distinct
/// anchor (`hey` / `circulate:` / `square through <n>` / `balance` / `gate` /
/// `courtesy turn` / `walk forward` / `chain` / `star promenade` / `promenade`
/// / `right (and) left through`) plus a successful resolution to its own move,
/// so no two can claim the same line. The one anchor pair that OVERLAPS —
/// `\bpromenades?\b` matches a `star promenade` line too — is separated by that
/// second condition: such a line resolves to `star_promenade`, so
/// `_promenadeAnnotation` (which pins `promenade`) declines it. They are listed
/// star-first anyway, so the ordering reads the way the precedence works.
final FigureFrontEnd tcbFigureFrontEnd = FigureFrontEnd(
  preRecognizers: [
    _hey,
    _circulate,
    _squareThroughPassList,
    _balanceHandAnnotation,
    _gateAnnotation,
    _courtesyTurnAnnotation,
    _walkForwardAnnotation,
    _chainAnnotation,
    _starPromenadeAnnotation,
    _promenadeAnnotation,
    _rightLeftThroughAnnotation,
    // LAST, deliberately: the general `;`-run consume (#843) claims whatever
    // the bespoke decoders above left behind, so none of them loses a line.
    _sideRunAnnotation,
  ],
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
/// - **All-or-nothing, with a bounded NOTE FALLBACK.** Every clause must
///   independently structure to a taxonomy move. When one does not, the line is
///   normally kept as a single custom figure carrying the original text — never
///   partially structured, because structuring the surviving moves alone would
///   drop what the failing clause said. The ONE exception is a clause the
///   dialect can preserve losslessly as prose: a **note-eligible** clause
///   ([_noteEligibleClause]) is dropped from the figure list and preserved
///   VERBATIM as a note on the nearest PRECEDING structured figure, so
///   `Circle left 3/4; face up` yields `circle` plus the note `face up` instead
///   of one custom figure. Nothing is lost and no move is fabricated — the same
///   trade #729 made for annotations. Every clause outside the allowlist still
///   collapses the whole line (`…; fall back`, `…; bend the line`,
///   `…; cast down to place`, every `form <formation>` label). The note is the
///   SCRUBBED clause, so it is canonical (`; women turn around` is stored as
///   `role2s turn around`) and the renderer re-expresses it in the reader's
///   dialect (#715/#717) — never a raw gendered term.
/// - **A LEADING clause never note-ifies.** A note belongs *to* a figure, so
///   when the FIRST clause fails there is nothing to hang it on without
///   reordering the dance: `Walk forward; form long wave in center` stays
///   whole-custom, and so does any line whose failing clause precedes every
///   structured one.
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
/// - **A bare `walk forward` clause reads with the clause AFTER it (#733).**
///   TCB's `[<dancer>] walk forward; form <formation>` states the inbound
///   travel and its destination formation as two clauses of one figure, so the
///   pair is folded by [_walkForwardIntoFormation] rather than parsed
///   independently (which would leave the travel clause custom and, by the
///   all-or-nothing rule above, discard the formation clause with it). The fold
///   consumes both clauses and preserves the pair's beats budget; a bare
///   `walk forward` with no foldable follower still degrades to custom.
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
  final scrubFn = scrub ?? scrubFigureText;
  // Indices into `clauses` that failed to structure, in source order. Kept
  // rather than bailing on the first failure so the note fallback below can see
  // the WHOLE line: all-or-nothing still applies unless EVERY failure is
  // note-eligible, which is only knowable once every clause has been tried.
  //
  // That reasoning only holds while the note fallback is REACHABLE. Above
  // [_maxNoteFallbackClauses] `_withClauseNotes` declines outright, so a failing
  // clause can no longer produce anything but the whole-custom line and there is
  // nothing left to learn from the remaining clauses. Bailing immediately is
  // therefore behaviour-identical AND bounds attacker-controlled work: this
  // parser sits behind an online import path, and without the early return a
  // crafted line of N junk `;` clauses costs N parses before the result is
  // discarded (OWASP; the corpus maximum is 5 clauses, so no real dance ever
  // takes this path).
  final noteFallbackReachable = clauses.length <= _maxNoteFallbackClauses;
  final declined = <int>[];
  for (var i = 0; i < clauses.length; i++) {
    // Option A beats distribution: the source's combined total rides on the
    // first clause; every later clause is beats-absent so the cumulative total
    // equals the original compound (no double-count, no section drift). A
    // note-ified clause emits no figure at all, so it contributes 0 either way
    // and the line's total is unchanged by the fallback.
    final clauseBeats = i == 0 ? beats : 0;
    // #733: a bare `[<dancer>] walk forward` clause is TCB's inbound travel to
    // the formation the NEXT clause names, so the pair is read together rather
    // than clause-by-clause. Declines (→ the ordinary per-clause path, which
    // keeps a bare walk forward custom) for anything the fold cannot carry
    // faithfully; see [_walkForwardIntoFormation].
    final walk = _bareWalkForwardClause(scrubFn(clauses[i]));
    if (walk != null && i + 1 < clauses.length) {
      final folded = _walkForwardIntoFormation(
        walk,
        clauses[i + 1],
        beats: clauseBeats,
        // The wave clause is the LAST clause of the pair, so it carries the
        // whole-line progression marker when the pair ends the line.
        progression: progression && i + 2 == clauses.length,
        taxonomy: taxonomy,
        scrub: scrub,
        frontEnd: frontEnd,
      );
      if (folded != null) {
        parsed.addAll(folded);
        i++; // both clauses consumed
        continue;
      }
    }
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
    // A clause that fails to structure (null/empty or custom) is a candidate
    // for the note fallback; anything else is a figure.
    if (f == null || f.isCustom) {
      if (!noteFallbackReachable) return wholeAsList();
      declined.add(i);
    } else {
      parsed.add(f);
    }
  }
  if (declined.isEmpty) return parsed;
  return _withClauseNotes(clauses, parsed, declined, scrub) ?? wholeAsList();
}

/// Applies the note fallback to a partially-structured `;` compound, or returns
/// `null` to decline it (the caller then keeps the pre-existing whole-custom
/// line). [parsed] holds the structured figures in source order and [declined]
/// the indices of the clauses that failed.
///
/// Declines — i.e. keeps today's all-or-nothing behaviour — when:
/// - **nothing structured**, or the FIRST failing clause precedes every
///   structured one. A note has no figure to belong to, and inventing an order
///   (hanging it on a LATER figure) would state that the dance does the note's
///   action after the figure, which the source did not say;
/// - **any** failing clause is not [_noteEligibleClause]. The allowlist is the
///   whole fidelity argument: an ineligible clause is one we cannot assert is
///   pure commentary, so the line keeps its honest unstructured reading;
/// - the line carries more than [_maxNoteFallbackClauses] clauses — a
///   **security bound** (OWASP), mirroring [kMaxMeanwhileSides]: a hostile line
///   with a long `;` run degrades to the unchanged whole-custom line instead of
///   accumulating notes. The corpus maximum is 5.
///
/// On success each failing clause's SCRUBBED text (the same text the custom
/// fallback would have carried, so canonical `role1`/`role2` tokens reach the
/// renderer and #717 re-expresses them in the reader's dialect) is combined
/// onto the nearest preceding structured figure via [combineFigureNotes] — the
/// figure's own recognizer note leads, so `Ladies chain to partner; face down`
/// reads `to partner; face down` and neither half is lost.
List<Figure>? _withClauseNotes(
  List<String> clauses,
  List<Figure> parsed,
  List<int> declined,
  String Function(String)? scrub,
) {
  if (parsed.isEmpty) return null;
  if (clauses.length > _maxNoteFallbackClauses) return null;
  final scrubFn = scrub ?? scrubFigureText;
  // Notes to add, keyed by the index in `parsed` they belong to.
  final notes = <int, String>{};
  for (final index in declined) {
    final text = scrubFn(clauses[index]).trim();
    if (!_noteEligibleClause(text)) return null;
    // The host is the last structured figure emitted BEFORE this clause: the
    // number of clauses before `index` that structured. 0 means the clause
    // precedes every figure -> decline (the leading-clause rule).
    final host = index - declined.where((d) => d < index).length - 1;
    if (host < 0) return null;
    final combined = combineFigureNotes(notes[host], text);
    if (combined == null) return null; // Unreachable: `text` is non-empty.
    notes[host] = combined;
  }
  final out = List<Figure>.of(parsed);
  for (final entry in notes.entries) {
    final figure = out[entry.key];
    out[entry.key] = figure.copyWith(
      note: combineFigureNotes(figure.note, entry.value),
    );
  }
  return out;
}

/// Clause-count bound for the note fallback (OWASP; see [_withClauseNotes]).
/// The Caller's Box mirror's longest top-level `;` compound is 5 clauses, so
/// this never bites real data. A longer line is not rejected outright — it
/// simply keeps the pre-existing whole-custom reading.
const int _maxNoteFallbackClauses = 8;

/// Whether a `;` clause that failed to structure may be preserved as a figure
/// NOTE instead of collapsing the whole line to custom.
///
/// [scrubbed] is the post-[scrubFigureText] clause. This is an explicit
/// ALLOWLIST, not "anything that failed": note-ifying a clause asserts that it
/// is commentary ON the preceding figure rather than an action of its own. That
/// is only defensible for wordings the maintainer has ruled on, and each entry
/// below is measured over the whole Caller's Box mirror (non-mixer,
/// `Permission: full`, top-level `;` clauses only):
///
/// - **`face …` — 1,814 clause occurrences across 98 distinct wordings.** All 98
///   were enumerated; every one is a facing statement (`face up` 351, `face N2`
///   293, `face next` 229, `face down` 211, `face partner` 209, `face across`
///   96, …) and none names a move the taxonomy models, so no figure is being
///   passed over. The word boundary matters: it keeps `facing star …` — a real
///   move with a real recognizer — out of this branch entirely.
/// - **`finish proper` — 137**, and **`return to place` — 235.** Matched as
///   EXACT phrases, not prefixes. That is what keeps out the neighbouring
///   wordings the maintainer did NOT rule on (`finish improper`,
///   `finish progressed`, `finish next to partner`, `finish with …`,
///   `return to original place`, `return to place. role2 one follow`) and,
///   deliberately, the whole `cast up/down/back to place` family — those lines
///   must keep falling to custom so a future census of `cast` counts them.
/// - **`role2s turn around` — 132**, and **`role1s turn around` — 96.** Matched
///   by [_turnAroundClause], a PREFIX rule mirroring [_facingClause], so the 17
///   annotated variants (`… (cw)`, `… [with n2]`, `… (by left)`) come with them
///   — 221 sole-blocker lines in total. The subject-less `turn around
///   (by right)` and the differently-subjected `role2 one and role1 two turn
///   around` are still excluded.
///
///   Read those carefully: the comparison is against the **post-scrub**
///   role tokens, NOT the source words `women`/`men`. Eligibility is evaluated
///   after [scrubFigureText] *deliberately*: it lets the rule be stated once in
///   the canonical role vocabulary instead of enumerating every gendered
///   spelling a source might use — the same reason the recognizers themselves
///   match on `role1`/`role2` rather than on dialect words.
///
///   The consequence is what makes the note useful. The clause TCB writes as
///   `Women turn around` (in any casing) arrives here as `role2s turn around`
///   and is stored on the figure in exactly that form, so the renderer can
///   re-express it per dialect (#715/#717) — "robins turn around" under
///   larks/robins, "follows turn around" under leads/follows. Rewriting these
///   to `women`/`men` would therefore break twice: it would match nothing, AND
///   it would store a dialect-specific term the reader could never see
///   re-expressed.
///
/// Length-bounded first (OWASP: untrusted import text), so a pathological
/// clause cannot become an unbounded note. The longest eligible corpus clause is
/// 52 characters. Never throws.
bool _noteEligibleClause(String scrubbed) {
  if (scrubbed.isEmpty || scrubbed.length > kMaxClauseNote) return false;
  final normalized = scrubbed.toLowerCase();
  if (_facingClause.hasMatch(normalized)) return true;
  if (_turnAroundClause.hasMatch(normalized)) return true;
  return normalized == 'finish proper' || normalized == 'return to place';
}

/// Length bound on a single note-eligible `;` clause. Matches the per-run bound
/// `_annotationRe` puts on an annotation, the other free-text fragment this
/// dialect promotes into a note.
const int kMaxClauseNote = 120;

/// A bare facing statement. `\b` is load-bearing: without it this would also
/// claim `facing star …`, which is a structured move.
final RegExp _facingClause = RegExp(r'^face\b', caseSensitive: false);

/// A subject-bearing `turn around` statement, matched on the POST-SCRUB text
/// (hence `role1s`/`role2s`, never `men`/`women` — see [_noteEligibleClause]).
///
/// A prefix rule, deliberately mirroring [_facingClause]: both families are
/// verbatim prose in the note either way, so an annotated variant
/// (`role2s turn around (cw)`, `role1s turn around [with n2]`) preserves
/// exactly as much as the whole-custom line did. Accepting `face up [with n0]`
/// while rejecting `role2s turn around (cw)` would be arbitrary.
///
/// `^` and `\b` are load-bearing — they keep out the two wordings that name no
/// subject or a different one: `turn around (by right)` and
/// `role2 one and role1 two turn around`.
final RegExp _turnAroundClause = RegExp(
  r'^role[12]s turn around\b',
  caseSensitive: false,
);

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

// --- "Walk forward" clause folds (#733) -------------------------------------

/// A clause that is EXACTLY `[<dancer set>] walk forward` — TCB's inbound
/// travel clause — carrying the dancer set the clause names, or `null` when it
/// names none. Wrapping it distinguishes "no subject stated" from "not a bare
/// walk-forward clause at all" (which [_bareWalkForwardClause] reports as a
/// null result).
class _WalkForwardClause {
  const _WalkForwardClause(this.who);

  /// The canonical dancer-set token the clause names, or `null` for a bare
  /// `Walk forward` that names nobody.
  final String? who;
}

/// Recognises a clause that is EXACTLY `[<dancer set>] walk forward`, on
/// already-SCRUBBED text (so gendered terms have become `role1`/`role2`).
///
/// Anchored at BOTH ends, which is what keeps the genuinely bare and the
/// qualified lines custom (#733 group 3): `walk forward one step`, `walk
/// forward slowly (step; step)`, `walk forward on slight left diagonal`, `walk
/// forward (out)`, `walk forward until right shoulders are adjacent` and
/// `walk forward or loop left` all carry text after the anchor and are
/// declined. Annotations are deliberately NOT stripped first — a `(…)` after
/// the anchor is content the fold cannot carry, so it must decline rather than
/// silently drop it.
///
/// The leading dancer phrase is bounded at `{0,40}` (mirroring `_forwardRe`):
/// anything longer is prose, not a dancer set. Import text is untrusted
/// (OWASP), and the bound applies inside the regex, before any scan of the
/// captured text.
_WalkForwardClause? _bareWalkForwardClause(String scrubbedClause) {
  final m = _bareWalkForwardRe.firstMatch(scrubbedClause);
  if (m == null) return null;
  final lead = m.group(1)!.trim();
  if (lead.isEmpty) return const _WalkForwardClause(null);
  // `resolveDancerSetPhrase` is strict — it resolves ONLY a phrase that names
  // exactly one dancer set and nothing else — so a bracketed qualifier
  // (`[Sides] Women walk forward`) or any other lead declines the fold.
  final who = resolveDancerSetPhrase(lead);
  return who == null ? null : _WalkForwardClause(who);
}

final RegExp _bareWalkForwardRe = RegExp(
  r'^(.{0,40}?)\bwalk\s+forward\b[\s.,;:!]*$',
  caseSensitive: false,
);

/// The wave-formation move a bare `walk forward` clause is ABSORBED into
/// (#733 group 1a).
///
/// Only the SINGULAR `form_a_long_wave`. Its `who` means "which dancers dance
/// IN to the long wave in the centre", which is exactly what the walk-forward
/// clause states, so the subject transfers with its meaning intact. The PLURAL
/// `form_long_waves.who` means something else entirely (the pair that faces
/// IN, per its `MoveDef`), so a transfer there would fabricate a facing; no
/// corpus line pairs a bare walk forward with the plural anyway.
const String _walkForwardAbsorbingMove = 'form_a_long_wave';

/// The formation move a bare `walk forward` clause is a PASS THROUGH into
/// (#733 group 1b).
const String _walkForwardPassThroughMove = 'form_short_waves';

/// Folds TCB's `[<dancer>] walk forward; form <formation>` pair into the
/// figures the taxonomy already models, or returns `null` to leave both clauses
/// to the ordinary per-clause path (where a bare walk forward is custom and the
/// whole line therefore stays custom).
///
/// Two readings, decided by what the FORMATION clause resolves to. (Per-shape
/// line counts, and the population they are measured over, live in the
/// `walk forward` census in `docs/research/callersbox.md` rather than here —
/// an inline count drifts silently the next time the mirror is re-pulled and
/// cannot state its own population filter.)
///
/// - **`form long wave …` → absorb (group 1a).** Emit ONLY
///   the wave figure and DROP the travel clause. That is not data loss:
///   `form_a_long_wave.in` defaults to `true` and the renderer's entry for the
///   move reads "`<who>` dance in to a long wave in the center", so the
///   INBOUND TRAVEL is already in the target move's rendered text — a separate
///   travel figure would state it twice. The clause's `who` is TRANSFERRED onto
///   the wave (and `assumedSubject` cleared): every subject-bearing line in
///   this group states the role on the WALK clause and NONE on the wave
///   clause, while `form_a_long_wave.who` defaults to `role2s` — so absorbing
///   without the transfer would render every `Men walk forward …` line as a
///   women's figure.
/// - **`form wave of four with <dancer>` → pass through, then the wave (group
///   1b).** Walking forward into a wave of four with the dancer you
///   are NOT currently facing is a pass through; the wave clause already
///   structures on its own today, so the pair emits two figures. A bare
///   `pass_through()` is emitted and `dir`/`shoulder` are deliberately NOT
///   written — both are the move's own taxonomy defaults, and writing them
///   would assert a direction and a shoulder the source never stated.
///
/// Declines (→ `null`, never a partial structuring) when:
/// - the formation clause does not structure, or structures to any other move
///   (`turn alone`, `face across`, `form interlocking long waves`, `form wave
///   of two`, `form ring of four`, …);
/// - the walk clause names a subject AND the reading is the pass-through one:
///   `pass_through` has no `who` slot, so `Women walk forward; form wave of
///   four with N2` would silently drop the role.
///
/// **Beats.** The pair consumes two clauses but the source states ONE combined
/// total, which by the file's Option A convention rides on the FIRST clause —
/// so [beats] is exactly the pair's budget. The absorbing reading puts it on
/// the single emitted wave; the pass-through reading puts it on the
/// `pass_through` (the first figure) and leaves the wave beats-absent. Either
/// way [deriveSections]' cumulative total is byte-identical to the whole-custom
/// line this replaces.
///
/// A 4-beat `pass_through` is outside the move's `goodBeats` (`[2]`) and raises
/// an `atypical_beats` WARNING. That is correct and expected — a 4-beat pass
/// through is a leisurely pass through — and warnings never force the custom
/// fallback. No beats param is fabricated to suppress it.
List<Figure>? _walkForwardIntoFormation(
  _WalkForwardClause walk,
  String formationClause, {
  required int beats,
  required bool progression,
  required Taxonomy? taxonomy,
  required String Function(String)? scrub,
  required FigureFrontEnd frontEnd,
}) {
  try {
    final safeBeats = beats < 0 ? 0 : beats;
    Figure? parse(int clauseBeats) => parseFigureLine(
      formationClause,
      beats: clauseBeats,
      progression: progression,
      taxonomy: taxonomy,
      scrub: scrub,
      frontEnd: frontEnd,
    );

    // Classify on a beats-absent parse so the same call serves both readings;
    // the absorbing one re-parses with the budget so the figure it emits is
    // validated with its real beats.
    final probe = parse(0);
    if (probe == null || probe.isCustom) return null;

    if (probe.move == _walkForwardAbsorbingMove) {
      final wave = safeBeats > 0 ? parse(safeBeats) : probe;
      if (wave == null || wave.isCustom) return null;
      final who = walk.who;
      // Never clobber a `who` the wave clause itself stated (no corpus line
      // states one on both clauses; this is the same defensive rule the gate
      // annotation applies to `whom`).
      if (who == null || wave.params.containsKey('who')) return [wave];
      return [
        wave.copyWith(
          params: {...wave.params, 'who': who},
          assumedSubject: false,
        ),
      ];
    }

    if (probe.move == _walkForwardPassThroughMove && walk.who == null) {
      final tax = taxonomy ?? contraTaxonomy;
      final passThrough = Figure(
        move: 'pass_through',
        params: {if (safeBeats > 0) 'beats': safeBeats},
      );
      final hasError = tax
          .validateFigure(passThrough)
          .any((issue) => issue.severity == ValidationSeverity.error);
      if (hasError) return null;
      return [passThrough, probe];
    }

    return null;
  } catch (_) {
    // Parse-never-fails: any unexpected shape leaves both clauses to the
    // caller's ordinary per-clause reading.
    return null;
  }
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

// --- Balance hand annotation extraction (#870) --------------------------------

/// Pre-recognizer that extracts `(RH)` / `(LH)` hand annotations from TCB
/// balance lines before [_stripAnnotations] drops them.
///
/// TCB writes `Neighbor balance (RH)` or `Partner balance (LH)` on ~1,066
/// corpus lines. Without this, the `(RH)` parenthetical is stripped by
/// [_stripAnnotations] before the shared `_balance` recognizer runs, and the
/// hand is silently lost — the structured figure carries no hand while the
/// custom fallback (which reads the un-normalized text) would have kept it.
///
/// The annotation is **consumed** into the `hand` param, not preserved as a
/// note: the parenthetical states a hand the taxonomy now models (#870), and
/// duplicating parsed data into prose is the outcome #744's triage rules out.
///
/// Returns `null` (→ the normal path) unless the line contains a `balance`
/// anchor AND a `(RH)` or `(LH)` annotation AND the annotation-stripped text
/// resolves to the `balance` move through the shared recognizers.
FigureMatch? _balanceHandAnnotation(String scrubbed) {
  if (!_balanceAnchor.hasMatch(scrubbed)) return null;
  final handMatch = _balanceHandRe.firstMatch(scrubbed);
  if (handMatch == null) return null;
  final handCode = handMatch.group(1)!.toUpperCase();
  final hand = handCode == 'RH' ? 'right' : 'left';

  // Strip the hand annotation AND any other annotations, then run the shared
  // recognizer to confirm this is a `balance` line (not, say, "balance the
  // ring" or a custom balance-wave form).
  final stripped = scrubbed.replaceFirst(handMatch.group(0)!, ' ').trim();
  final match = recognizeSharedFigureLine(
    stripped,
    recognitionNormalize: _stripAnnotations,
  );
  if (match == null || match.moveId != 'balance') return null;

  return FigureMatch(
    'balance',
    params: {...match.params, 'hand': hand},
    note: match.note,
    assumedSubject: match.assumedSubject,
  );
}

final RegExp _balanceAnchor = RegExp(r'\bbalance\b', caseSensitive: false);

/// Matches `(RH)` or `(LH)` — the TCB hand annotation on balance lines.
/// Case-insensitive, bounded to exactly two characters inside the parens.
final RegExp _balanceHandRe = RegExp(r'\(\s*([RrLl][Hh])\s*\)');

// --- Gate annotation preservation (taxonomy v22) -----------------------------

/// TCB states which side of a gate MOVES in a trailing parenthetical —
/// `(ones forward)`, `(twos forward)`, `(men stay put)`, `(women are posts)`,
/// `(M1+W2 forward)` — on 82 of the 186 gate lines in the 24,107-dance corpus.
/// It is load-bearing choreography, and it is the same fact ContraDB stores in
/// its `who`/`whom` split (`figure.js:844`: "twos walk forward, ones back up").
/// But [_stripAnnotations] drops it for recognition, so before v22 a structured
/// gate SILENTLY LOST it — only an unrecognised line kept it, via the custom
/// fallback's un-normalized text.
///
/// This pre-recognizer closes that gap. It runs ahead of the shared
/// recognizers, delegates the actual grammar to [recognizeSharedFigureLine] (no
/// duplicated gate parsing, no recursion back into a front-end), and then:
///
///   * **structures a "`<dancers>` forward" annotation onto `whom`** — the
///     merged move's `whom` means precisely "the side that walks forward", so
///     this is source-verified, not inferred; and
///   * **preserves every OTHER annotation verbatim as the figure's note.**
///
/// The split is deliberate and conservative — prefer-custom applied at param
/// granularity:
///
///   * `(men stay put)`, `(women are posts)`, `(centers are posts)` state that
///     dancers are STATIONARY. That is neither `whom` ("walks forward") nor
///     `who` ("extends a hand and backs up" — a moving role: it backs up).
///     Mapping them to either slot would fabricate, so they stay note-only.
///   * `(M1+W2 forward)`, `(ends forward)`, `(twos and fours forward)`,
///     `(ones and threes forward)`, `(threes forward)` DO say "forward", but
///     name no dancer set our vocabulary models. [resolveDancerSetPhrase]
///     returns null for them and they stay note-only rather than being
///     approximated onto a token that means something else.
///   * A line with several annotations keeps the unconsumed ones:
///     `[Ones and twos] Neighbor mirror gate 3/4 (twos forward)` yields
///     `whom: twos` plus the note `Ones and twos`.
///
/// An annotation that IS consumed into `whom` does not also become a note:
/// notes render as their own row next to the figure line, so duplicating the
/// same words in both would read as a bug. Nothing is lost either way — the
/// structured slot carries the fact, and the display renderer states it.
///
/// Fires only for a line that (a) contains the `gate` anchor, (b) carries at
/// least one non-numeric annotation, and (c) the shared recognizers resolve to
/// the `gate` move. Anything else returns null and takes the normal path.
FigureMatch? _gateAnnotation(String scrubbed) {
  final base = _annotatedMatch(scrubbed, _gateAnchor, 'gate');
  if (base == null) return null;
  final match = base.match;

  String? whom;
  final kept = <String>[];
  for (final body in base.annotations) {
    // Only the FIRST resolvable "<dancers> forward" is consumed; a second one
    // would mean the line names two forward-walking sides, which no source
    // does — so it is kept verbatim rather than silently overwriting.
    final forward = whom == null ? _forwardDancers(body) : null;
    if (forward != null) {
      whom = forward;
    } else {
      kept.add(body);
    }
  }
  if (whom == null && kept.isEmpty) return null;

  return _withAnnotationNote(
    match,
    _joinAnnotations(kept),
    // Never clobber a `whom` the grammar itself resolved.
    extraParams: (whom != null && !match.params.containsKey('whom'))
        ? {'whom': whom}
        : const {},
  );
}

/// A [FigureMatch] the shared recognizers produced for an ANNOTATED line, plus
/// the annotation bodies that were stripped before they saw it.
class _AnnotatedMatch {
  const _AnnotatedMatch(this.match, this.annotations);
  final FigureMatch match;
  final List<String> annotations;
}

/// The one shared entry point for every annotation-preserving pre-recognizer
/// (`gate` since v22, `courtesy_turn` since v23).
///
/// [_stripAnnotations] drops `()`/`[]` for RECOGNITION, so without this a
/// structured match silently loses text the custom fallback keeps. Each caller
/// supplies its own [anchor] and expected [moveId]; this does the common work
/// once — cheap anchor test, BOUNDED annotation extraction, then delegation to
/// [recognizeSharedFigureLine] so no move's grammar is ever duplicated here and
/// no pre-recognizer can recurse back into a front-end.
///
/// Returns null (→ the normal path) unless the line has the anchor, carries at
/// least one non-numeric annotation, AND actually resolves to [moveId]. That
/// last condition is what stops, say, an annotated chain line that merely
/// mentions a courtesy turn from being claimed.
///
/// All bounding lives in [_annotations] / [_joinAnnotations] — `_maxAnnotations`,
/// `_maxAnnotationNote`, the per-run length cap inside `_annotationRe`, and
/// rune-safe truncation. Import text is untrusted (OWASP), and keeping the caps
/// in ONE place is why a new caller cannot accidentally introduce an unbounded
/// note.
_AnnotatedMatch? _annotatedMatch(
  String scrubbed,
  RegExp anchor,
  String moveId,
) {
  if (!anchor.hasMatch(scrubbed)) return null;
  final annotations = _annotations(scrubbed);
  if (annotations.isEmpty) return null;
  final match = recognizeSharedFigureLine(
    scrubbed,
    recognitionNormalize: _stripAnnotations,
  );
  if (match == null || match.moveId != moveId) return null;
  return _AnnotatedMatch(match, annotations);
}

/// Rebuilds [match] with [note] attached (and any [extraParams] merged in).
///
/// Notes COMBINE ([combineFigureNotes]) rather than one winning: resolving this
/// with `match.note ?? note` silently discarded the annotation whenever the
/// shared recognizer had already set its own note. That was a no-op for `gate`
/// and `courtesy_turn` (neither shared match carries a note of its own), but it
/// is live on 40 corpus lines through the `;`-clause note path — and, since
/// #733, on the `walk forward to <dancer>` lines too, where the recognizer's
/// own `to n2` destination note must not be displaced by a trailing
/// parenthetical. All three paths use the one combiner.
FigureMatch _withAnnotationNote(
  FigureMatch match,
  String? note, {
  Map<String, Object?> extraParams = const {},
}) => FigureMatch(
  match.moveId,
  params: <String, Object?>{...match.params, ...extraParams},
  note: combineFigureNotes(match.note, note),
  assumedSubject: match.assumedSubject,
);

/// The dancer set an annotation names as walking FORWARD, or `null` when the
/// annotation is not a "`<dancers>` forward" statement or names a set we do not
/// model. The trailing `forward` is REQUIRED — it is the word that makes the
/// annotation mean the same thing as the merged move's `whom`.
String? _forwardDancers(String body) {
  final trimmed = body.trim();
  final m = _forwardRe.firstMatch(trimmed);
  if (m == null) return null;
  return resolveDancerSetPhrase(m.group(1)!);
}

/// `{1,40}` bounds the dancer phrase; anything longer is prose, not a dancer
/// set, and falls through to note-only.
final RegExp _forwardRe = RegExp(
  r'^(.{1,40}?)\s+forward$',
  caseSensitive: false,
);

final RegExp _gateAnchor = RegExp(r'\bgates?\b', caseSensitive: false);

// --- Courtesy-turn annotation preservation (taxonomy v23) --------------------

/// The same gap [_gateAnnotation] closes, for `courtesy_turn`: TCB writes
/// annotations on 7 of the corpus's courtesy-turn lines — `Partner courtesy
/// turn (in center)` (x4), `[Ones and threes] Partner courtesy turn
/// (continued)` (x2), `[Sides] Partner courtesy turn (continued)` — and
/// [_stripAnnotations] drops them for recognition. Without this, adding the
/// move would make those lines structure while SILENTLY LOSING "in center",
/// "continued" and the bracketed subject, all of which the custom fallback
/// preserves today. Structuring a line must never cost information the
/// unstructured reading kept.
///
/// Simpler than the gate's counterpart, deliberately: `courtesy_turn` has no
/// slot any of these annotations could faithfully fill. "(in center)" is a
/// spatial staging note, not a dancer; "(continued)" is TCB's marker for a
/// figure that spans two phrases; "[Ones and threes]" names a set the taxonomy
/// does not model. So EVERY annotation is preserved verbatim as the note and
/// none is structured — prefer-custom applied at param granularity, the same
/// discipline that keeps `(men stay put)` note-only on a gate.
///
/// Shares [_annotatedMatch] with the gate path, so the OWASP caps
/// (`_maxAnnotations`, `_maxAnnotationNote`, the per-run length bound in
/// `_annotationRe`, rune-safe truncation) are the SAME ones — a hostile line
/// with thousands of parentheticals cannot inflate a note, and this adds no new
/// bound of its own.
///
/// Fires only for a line that (a) contains the `courtesy turn` anchor,
/// (b) carries at least one non-numeric annotation, and (c) resolves to the
/// `courtesy_turn` move through the shared recognizers. Anything else returns
/// null and takes the normal path — including, importantly, every
/// chain-embedded courtesy turn, which never resolves to this move.
FigureMatch? _courtesyTurnAnnotation(String scrubbed) {
  final base = _annotatedMatch(scrubbed, _courtesyTurnAnchor, 'courtesy_turn');
  if (base == null) return null;
  final note = _joinAnnotations(base.annotations);
  if (note == null) return null;
  return _withAnnotationNote(base.match, note);
}

final RegExp _courtesyTurnAnchor = RegExp(
  r'\bcourtesy\s+turns?\b',
  caseSensitive: false,
);

// --- Walk-forward annotation preservation (#733) -----------------------------

/// The same gap [_gateAnnotation] and [_courtesyTurnAnnotation] close, for the
/// `walk forward to <dancer>` lines #733 maps onto `pass_through`.
///
/// Exactly TWO lines of the `Permission: full` corpus spell the travel out in
/// a parenthetical — `Walk forward to N2 (women going on slight right
/// diagonal, men on slight left diagonal)` and its N3 mirror. That count is
/// stated inline because it is the whole justification for this
/// pre-recognizer's existence: at zero lines the code would be dead, and the
/// same population basis the `walk forward` census uses applies. Without it,
/// [_stripAnnotations] drops the parenthetical for recognition, so teaching
/// the recognizer those lines would make them structure while SILENTLY LOSING
/// the per-role diagonals the custom fallback preserves today. Structuring a
/// line must never cost information the unstructured reading kept.
///
/// `pass_through` has no slot any of this could faithfully fill, so EVERY
/// annotation is preserved verbatim as the note and none is structured — and
/// the recognizer's own `to <dancer>` destination note LEADS it (see
/// [_withAnnotationNote]), never being displaced by it.
///
/// Shares [_annotatedMatch] with the gate and courtesy-turn paths, so the OWASP
/// caps (`_maxAnnotations`, `_maxAnnotationNote`, the per-run length bound in
/// `_annotationRe`, rune-safe truncation) are the SAME ones; this adds no new
/// bound of its own.
///
/// Anchored on `walk forward` specifically, not on `pass_through` as a move, so
/// it claims ONLY the lines this change makes structurable: an ordinary
/// `Pass through across (PR)` line keeps its existing (annotation-stripped)
/// reading untouched.
FigureMatch? _walkForwardAnnotation(String scrubbed) {
  final base = _annotatedMatch(scrubbed, _walkForwardAnchor, 'pass_through');
  if (base == null) return null;
  final note = _joinAnnotations(base.annotations);
  if (note == null) return null;
  return _withAnnotationNote(base.match, note);
}

final RegExp _walkForwardAnchor = RegExp(
  r'\bwalk\s+forward\b',
  caseSensitive: false,
);

// --- Chain / promenade / right-and-left-through annotation preservation
// (#729) --------------------------------------------------------------------

/// The same gap [_gateAnnotation], [_courtesyTurnAnnotation] and
/// [_walkForwardAnnotation] close, for `chain`, `promenade` and
/// `right_left_through`.
///
/// TCB pairs these three high-frequency moves with a courtesy-turn
/// qualifier IN A PARENTHETICAL far more often than the moves this issue's
/// predecessors touched — `Ladies chain to partner (optional double
/// courtesy turn)`, `Partner promenade across (without courtesy turn)`,
/// `[Ones and twos] Same-role right and left through with neighbor`. Because
/// [_stripAnnotations] drops `()`/`[]` for recognition, all three used to
/// structure while SILENTLY LOSING the qualifier — and, for the negating
/// wordings ("without courtesy turn"), the structured figure was left
/// asserting the OPPOSITE of what the source said. That is the shape #295
/// declined to fix inline (chain/promenade are two of the highest-frequency
/// moves in the corpus, so blast radius had to be measured first, not
/// assumed) and #729 measures and closes it.
///
/// **Locked design ruling (owner, #729): preserve-as-note for EVERY
/// qualifier, additive or negating — never decline these lines to custom.**
/// A `courtesyTurn` taxonomy flag was raised and explicitly declined: adding
/// one would mean the taxonomy needs to know a courtesy turn *could* have
/// happened on a chain/promenade/right-and-left-through, which is a much
/// bigger and more speculative modeling question than "preserve the words
/// the source actually wrote". The consequence, adopted deliberately: the
/// structured figure still asserts the un-negated choreography (a `chain`
/// still IS a chain; nothing marks it "no courtesy turn"), while the
/// contradicting words live in the note, readable by a caller/dancer but not
/// machine-checkable against the figure's own params. A future modeler who
/// wants that checkable is welcome to add the flag additively (as
/// `promenade.singleFile` did, #634) — this pre-recognizer does not foreclose
/// it, it just does not attempt it.
///
/// `chain` and `right_left_through` already emit their OWN note
/// (`` `to <dancer>` `` / `` `same-role` ``), so without
/// [_withAnnotationNote]'s combine fix a naive `existing ?? added` would make
/// these two pre-recognizers silent no-ops whenever that note already fired —
/// invisible, because *a* note is still present, just not the annotation.
/// That combine fix already landed (motivated by this exact collision,
/// foreseen while #733 wired up its own annotation-preserving pre-recognizer)
/// — this PR only adds the three new pre-recognizers that actually exercise
/// it for these moves. `promenade` carries no note of its own, so it never
/// collides; it is still wired in here so all three moves share one mechanism
/// rather than two being "fixed" and one being left with the original silent
/// drop.
///
/// Measured over the `Permission: full` Caller's Box corpus (see
/// `docs/research/callersbox.md`'s figure-line census for #729): of
/// 117,981 lines across 12,001 dances, **0 move IDs, 0 beat totals and 0
/// custom/structured flips change** — this pre-recognizer only ever adds or
/// extends a `note`. **1,061** figures gain or change a note:
/// `right_left_through` 594 (mostly a bracketed subject group — `[Ones and
/// twos]`, `[Twos and threes]` — combining with the move's own
/// `` `same-role` `` note), `chain` 416 (mostly `(along the set)`/`(across
/// the set)`/`[those who can]`/`[Groups of four]` combining with the move's
/// own `` `to <dancer>` `` note), and `promenade` 51 (no collision — a
/// straightforward add, including this issue's own two example lines).
FigureMatch? _chainAnnotation(String scrubbed) {
  final base = _annotatedMatch(scrubbed, _chainAnchor, 'chain');
  if (base == null) return null;
  final note = _joinAnnotations(base.annotations);
  if (note == null) return null;
  return _withAnnotationNote(base.match, note);
}

/// See [_chainAnnotation]. `promenade` has no note of its own (no collision),
/// but shares the same mechanism for consistency.
FigureMatch? _promenadeAnnotation(String scrubbed) {
  final base = _annotatedMatch(scrubbed, _promenadeAnchor, 'promenade');
  if (base == null) return null;
  final note = _joinAnnotations(base.annotations);
  if (note == null) return null;
  return _withAnnotationNote(base.match, note);
}

/// See [_chainAnnotation]. The anchor accepts both `right and left through`
/// and `right left through`, matching the `and` being optional in the shared
/// recognizer's own grammar (`figure_parser.dart`), so the pre-recognizer's
/// cheap anchor test never rejects a line the delegated grammar would go on
/// to accept.
FigureMatch? _rightLeftThroughAnnotation(String scrubbed) {
  final base = _annotatedMatch(
    scrubbed,
    _rightLeftThroughAnchor,
    'right_left_through',
  );
  if (base == null) return null;
  final note = _joinAnnotations(base.annotations);
  if (note == null) return null;
  return _withAnnotationNote(base.match, note);
}

final RegExp _chainAnchor = RegExp(r'\bchains?\b', caseSensitive: false);
final RegExp _rightLeftThroughAnchor = RegExp(
  r'\bright\s+(and\s+)?left\s+through\b',
  caseSensitive: false,
);

// --- Star-promenade center annotation (taxonomy v26, #843) -------------------

/// TCB states the CENTER of a star promenade in a trailing parenthetical —
/// `Neighbor star promenade 1/2 (WR)`, `Partner star promenade 3/4 (ML)` — and
/// [_stripAnnotations] drops it for recognition.
///
/// **Why this is a note and not a param.** The parenthetical does NOT qualify
/// `who`. `(WR)` notates *"the women have right hands in the center"*, while
/// `who` names the dancer you PICK UP on the side. The two facts coexist, and
/// TCB's own flutterwheel decomposition shows both in one figure:
///
/// ```
/// (8) Neighbor flutterwheel  ->  (4) Women allemande right 1/2
///                            +  (4) Neighbor star promenade 1/2 (WR)
/// ```
///
/// `who` is `neighbors`; `(WR)` names the women. Different sets. Until taxonomy
/// v26 the center hand lived in a `star_promenade.hand` param that rendered
/// beside the subject — *"Neighbor star promenade right ½"* — implying a
/// right-hand connection with the NEIGHBOR when the right-hand connection is
/// between the two dancers in the center. The owner removed the param on
/// 2026-08-06; this pre-recognizer is what keeps the fact the param used to
/// (mis)carry.
///
/// **The note stores CANONICAL ROLE TOKENS, never `W`/`M`.** `role2s by the
/// right in the center` renders as *"Robins by the right in the center"* under
/// larks/robins and *"Ladies …"* under a gendered dialect, because notes go
/// through the renderer's `renderFreeText` role substitution. A literal `W`
/// would be frozen gendered text forever, in every dialect, permanently.
///
/// **`who` is never written or overwritten here.** It comes from the prose
/// subject via the shared recognizer, which is the whole point of the ruling:
/// the annotation names a different set, so letting it reach `who` would
/// reintroduce the exact confusion v26 removed.
///
/// Conservative, and shares [_annotatedMatch] with the gate / courtesy-turn /
/// walk-forward / chain paths — so the OWASP caps (`_maxAnnotations`,
/// `_maxAnnotationNote`, the per-run length bound in `_annotationRe`, rune-safe
/// truncation) are the SAME ones and this adds no new bound. An annotation that
/// is not exactly one `<people-code><R|L>` cell — a multi-cell run, an unmapped
/// people code (`O`, `Ph`, `SRN`, …), a missing or non-`R`/`L` tail — is
/// PRESERVED VERBATIM as the note rather than approximated onto a role token
/// that means something else. That mirrors `_gateAnnotation`'s treatment of
/// `(men stay put)`: prefer-custom applied at param granularity.
FigureMatch? _starPromenadeAnnotation(String scrubbed) {
  final base = _annotatedMatch(
    scrubbed,
    _starPromenadeAnchor,
    'star_promenade',
  );
  if (base == null) return null;

  final phrases = <String>[];
  for (final body in base.annotations) {
    phrases.add(_centerHandPhrase(body) ?? body);
  }
  final note = _joinAnnotations(phrases);
  if (note == null) return null;
  return _withAnnotationNote(base.match, note);
}

/// `<people-code><R|L>` → `<canonical role token> by the <hand> in the center`,
/// or `null` when the body is not exactly one such cell (the caller then keeps
/// it verbatim).
///
/// Deliberately STRICTER than the pass-list decoders: a star promenade has one
/// center, so a `;`-run states something this phrasing cannot express, and is
/// left verbatim rather than being collapsed onto its first cell.
String? _centerHandPhrase(String body) {
  final cell = body.trim().toLowerCase();
  if (cell.length < 2 || cell.contains(';')) return null;
  final handChar = cell[cell.length - 1];
  final hand = handChar == 'r'
      ? 'right'
      : handChar == 'l'
      ? 'left'
      : null;
  if (hand == null) return null;
  final who = tcbPassPeople[cell.substring(0, cell.length - 1)];
  if (who == null) return null;
  return '$who by the $hand in the center';
}

final RegExp _starPromenadeAnchor = RegExp(
  r'\bstar\s+promenades?\b',
  caseSensitive: false,
);

final RegExp _promenadeAnchor = RegExp(
  r'\bpromenades?\b',
  caseSensitive: false,
);

// --- `;`-run handedness / dancer consume (#843 Parts B and C) ----------------

/// Consumes TCB's `;`-run shorthand — `(ML)`, `(NR;PL)`, `(WR;PL;MR;N2L~)` —
/// into the resolved move's OWN slots, instead of letting [_stripAnnotations]
/// drop it and the taxonomy fill a default that may contradict the source.
///
/// **Why a general decoder rather than another per-move pre-recognizer.** Four
/// consume paths already exist ([_hey], [grandRightAndLeftFromPassList],
/// [_squareThroughPassList], and the adapter's balance-a-wave decoder), each
/// tied to one move because each LOWERS the run onto a bespoke structure — a
/// hey's ricochet slots, one `pull_by_dancers` per pass. This one does not
/// lower anything: it reads the same notation and fills whatever slots the
/// move it landed on happens to declare. Writing eleven more pre-recognizers
/// for the eleven remaining move keys would duplicate one cell walk eleven
/// times and still miss the twelfth move somebody adds later.
///
/// **The slot lookup asks the TAXONOMY, keyed on `ParamKind`.** #870 introduced
/// the pattern (query the resolved `MoveDef` rather than maintain a hardcoded
/// move list that drifts whenever a move gains or loses a slot) but keyed on the
/// literal param NAME `hand`. That is not portable here: of the twenty moves
/// with a side slot, seven name it `shoulder` and two name it `centerHand`, so
/// a name check would silently miss nine of them. [_sideSlot] therefore looks
/// for the single param whose kind is `handedness` or `shoulder`.
///
/// **Values are written even when they equal the taxonomy default** (owner
/// ruling). The decode either fires on a run or it does not; `if (decoded !=
/// default) apply` is a strange thing to write, and storing what the source
/// SAID rather than what we assumed means the value survives a future change of
/// default. This is byte-identical at both identity layers — `renderCanonical`
/// and `figureCanonicalKey` both build from `Taxonomy.effectiveParams`, which
/// fills defaults — so it raises no spurious #686 "Variation?" prompt. The
/// INVERSE value does change the key, but it should: the stored choreography
/// contradicted its source.
///
/// **Dancer identity (Part C).** The same cells name dancers, so `who`/`who2`
/// are filled too, on the moves that declare them. Two-pass moves alternate:
/// odd 1-based positions name `who`, even positions name `who2`. `pass_through`
/// declares NO `who`, so its dancer code has nowhere to go and is dropped —
/// which is the status quo for that half of the annotation, minus the wrong
/// shoulder. (Preserving it as a note instead would add one to ~2,048 figures
/// across 1,773 dances; that is a visible change at corpus scale and is the
/// owner's call, not this decoder's.)
///
/// **Declines (returns `null` → the ordinary annotation-stripped path) when:**
///   * the line has no `(...)` annotation, or more than one;
///   * the annotation is not entirely `<people-code><R|L>` cells, or any
///     people code is absent from [tcbPassPeople] (`O`, `Ph`, `SRN`, `C1`–`C3`,
///     out-of-range neighbors/shadows) — never approximated onto a token that
///     means something else;
///   * the sides do not alternate by position parity, which is the model both
///     two-pass renderers implement;
///   * a `square_through` 4-code list is not periodic (`code[2] == code[0]`,
///     `code[3] == code[1]`), or a `cross_trails` run is not the `?R;?L` shape
///     — each is a corpus-wide invariant (101/101 and 85/85 as reported on
///     #843), so a violation is an unmodeled variant rather than something to
///     structure;
///   * the resolved move declares no side slot at all;
///   * the shared recognizer ALREADY resolved the side from prose and the
///     annotation CONTRADICTS it — `Neighbor allemande left 1 (NR)`. The line
///     then keeps today's reading: the PROSE value stands and the annotation is
///     dropped, because prose is the authoritative statement and the fall-
///     through is exactly what happens now. Note this is a fall-through, NOT a
///     decline to custom: forcing custom here would regress a line that
///     structures today, which is a bigger loss than not consuming one
///     contradictory annotation.
///
/// Runs LAST among the pre-recognizers, so every bespoke decoder above keeps
/// the lines it already claims. Bounding is [_boundedPassListCells]'s, shared
/// with every other pass-list path (OWASP: imported text is untrusted, and the
/// cap runs before the split allocates).
FigureMatch? _sideRunAnnotation(String scrubbed) {
  final lower = scrubbed.toLowerCase();
  final open = lower.indexOf('(');
  if (open == -1) return null;
  final close = lower.indexOf(')', open + 1);
  if (close == -1) return null;
  // A second parenthetical means extra structure we do not model -> decline.
  if (lower.indexOf('(', close + 1) != -1) return null;

  final cells = _boundedPassListCells(lower.substring(open + 1, close));
  if (cells == null || cells.isEmpty || cells.length > kMaxPassListCells) {
    return null;
  }

  // Decode every cell before consulting the taxonomy: a run we cannot fully
  // account for declines outright, so no line is ever partially structured.
  final decoded = <_SideCell>[];
  String? sideBase;
  for (var i = 0; i < cells.length; i++) {
    // The `~` partial-last-pass marker is informational only (ratified) and is
    // dropped here exactly as the hey decoder drops it.
    final cell = cells[i].endsWith('~')
        ? cells[i].substring(0, cells[i].length - 1)
        : cells[i];
    if (cell.length < 2) return null;
    final sideChar = cell[cell.length - 1];
    final side = sideChar == 'r'
        ? 'right'
        : sideChar == 'l'
        ? 'left'
        : null;
    if (side == null) return null;
    final who = tcbPassPeople[cell.substring(0, cell.length - 1)];
    if (who == null) return null;

    // Sides alternate by parity; derive the base (position-1) side and require
    // every later cell to agree — a run that does not alternate is malformed.
    final position = i + 1;
    final impliedBase = position.isOdd ? side : _otherShoulder(side);
    if (sideBase == null) {
      sideBase = impliedBase;
    } else if (sideBase != impliedBase) {
      return null;
    }
    decoded.add(_SideCell(who, side));
  }
  if (sideBase == null) return null;

  final match = recognizeSharedFigureLine(
    scrubbed,
    recognitionNormalize: _stripAnnotations,
  );
  if (match == null) return null;
  final def = contraTaxonomy.resolve(match.moveId);
  if (def == null) return null;

  final slot = _sideSlot(def);
  if (slot == null) return null;

  // Structural invariants (Part C). A violation is an unmodeled variant:
  // decline rather than structure something the renderer cannot say.
  if (!_runShapeIsModelled(match.moveId, def, match.params, decoded)) {
    return null;
  }

  // Never silently overwrite a side the grammar itself resolved from prose. If
  // they agree, keep it; if they contradict, decline the RUN — the line then
  // falls through to the ordinary reading and keeps its prose-stated side. It
  // does NOT become custom.
  final stated = match.params[slot];
  if (stated is String && stated != sideBase) return null;

  final params = <String, Object?>{...match.params, slot: sideBase};

  // Dancer identity (Part C), only into slots the move actually declares.
  // Odd 1-based positions name `who`, even positions `who2` — the alternation
  // both two-pass renderers implement.
  final who1 = _consistentWho(decoded, odd: true);
  final who2 = _consistentWho(decoded, odd: false);
  if (who1 == null) return null; // positions disagree -> ambiguous -> decline.
  if (def.params.containsKey('who') && !match.params.containsKey('who')) {
    params['who'] = who1;
  }
  if (who2 != null &&
      def.params.containsKey('who2') &&
      !match.params.containsKey('who2')) {
    params['who2'] = who2;
  }

  return FigureMatch(
    match.moveId,
    params: params,
    note: match.note,
    assumedSubject: match.assumedSubject,
  );
}

/// One decoded `<people-code><R|L>` cell: the dancer it names and the side.
class _SideCell {
  const _SideCell(this.who, this.side);
  final String who;
  final String side;
}

/// The name of [def]'s single side param — the one whose kind is
/// `handedness` or `shoulder` — or `null` when it has none, or more than one.
///
/// Keyed on `ParamKind` rather than the literal name `hand`, because of the
/// twenty moves with a side slot seven call it `shoulder` and two call it
/// `centerHand`. More than one is treated as "no slot" rather than picking
/// arbitrarily: no move declares two today, and a future one should fail
/// loudly (the line stays custom) instead of having a slot chosen for it.
String? _sideSlot(MoveDef def) {
  String? found;
  for (final entry in def.params.entries) {
    final kind = entry.value.kind;
    if (kind != ParamKind.handedness && kind != ParamKind.shoulder) continue;
    if (found != null) return null;
    found = entry.key;
  }
  return found;
}

/// The dancer named at every odd (or even) 1-based position, or `null` when
/// those positions disagree — or, for the even case, when there are none.
String? _consistentWho(List<_SideCell> cells, {required bool odd}) {
  String? who;
  for (var i = 0; i < cells.length; i++) {
    if ((i + 1).isOdd != odd) continue;
    if (who == null) {
      who = cells[i].who;
    } else if (who != cells[i].who) {
      return null;
    }
  }
  return who;
}

/// Whether a decoded run matches the structural model the resolved move's
/// renderer implements. A cell is a PASS, so a run states as many passes as it
/// has cells, and a move that models fewer cannot carry it.
///
/// - **`square_through`**: the cell count must equal `places`. `Square through
///   3 (N2R;SL)` names two passes for a three-pass figure, so the third pass's
///   dancer would have to be inferred — which is precisely what #799 declined
///   to guess, and this decoder must not undo that ruling by the side door.
///   The 4-code lists are additionally required to be periodic (`code[2] ==
///   code[0]`, `code[3] == code[1]`), matching the renderer's "then repeat"
///   model; the parity check upstream forces the SIDES to alternate but would
///   let a list whose DANCERS break the period through.
/// - **A move declaring `who2`** models two passes, so AT MOST two cells —
///   `<= 2`, deliberately, not `== 2`.
///
///   The asymmetry with `square_through` above is real and worth stating,
///   because "at most" otherwise reads as an unconsidered `<=`. The difference
///   is whether the source CONTRADICTS itself. `Square through 3` states its
///   pass count in prose, so a two-cell list disagrees with the line's own
///   arity and the missing pass would have to be invented — decline. A
///   `cross_trails` line states no count anywhere, so a one-cell run is merely
///   INCOMPLETE, and consuming what the source did state is strictly better
///   than discarding it.
///
///   Measured, because the reverse is easy to assume. For
///   `Cross trail through (NR)`:
///     consumed (`<= 2`): "neighbors cross trails across neighbors"
///     declined (`== 2`): "partners cross trails across neighbors"
///   `who2` renders from its `neighbors` default EITHER WAY — declining does
///   not suppress it, because a bare `Cross trails` renders the same default
///   already. What declining changes is pass ONE, from the `neighbors` the
///   source stated to the `partners` default. So `== 2` would introduce a
///   falsehood about the pass the source DID state, in order to avoid
///   defaulting the pass it did not. That is a worse trade, not a safer one.
///
///   The residual hazard is honest and unfixed here: nothing downstream
///   distinguishes a source-stated `who2` from a defaulted one. That is a
///   property of the taxonomy's defaults, not of this decoder, and it predates
///   it. **Latent in the corpus**: of the cell-shaped annotations on
///   cross-trail lines, ZERO are single-cell (verified directly against the
///   mirror), so no imported dance takes this path today.
/// - **A move with no `who2`** (e.g. `pass_through`, `allemande`) models ONE
///   pass. A multi-cell run on such a line describes choreography the move
///   cannot express, so it declines rather than collapsing onto its first cell.
bool _runShapeIsModelled(
  String moveId,
  MoveDef def,
  Map<String, Object?> params,
  List<_SideCell> cells,
) {
  if (moveId == 'square_through') {
    final places = params['places'] ?? def.params['places']?.defaultValue;
    if (places is! int || cells.length != places) return false;
    for (var i = 2; i < cells.length; i++) {
      if (cells[i].who != cells[i - 2].who) return false;
    }
    return true;
  }
  return def.params.containsKey('who2') ? cells.length <= 2 : cells.length == 1;
}

/// Bounded extractor for `()`/`[]` annotation contents, in source order.
///
/// Import text is untrusted (OWASP): the match count is capped, each captured
/// run is length-capped by the regex itself, and [_joinAnnotations] truncates
/// the result — so a hostile line with thousands of parentheticals cannot
/// inflate a note. Purely-numeric annotations (a stray beat marker) are skipped:
/// they carry no choreography and would be noise on every figure.
List<String> _annotations(String scrubbed) {
  final out = <String>[];
  for (final m in _annotationRe.allMatches(scrubbed)) {
    if (out.length >= _maxAnnotations) break;
    final body = (m.group(1) ?? m.group(2) ?? '').trim();
    if (body.isEmpty || _numericOnly.hasMatch(body)) continue;
    out.add(body);
  }
  return out;
}

/// Joins the annotations kept for the note, or `null` when none remain.
String? _joinAnnotations(List<String> kept) {
  if (kept.isEmpty) return null;
  return truncateOnRuneBoundary(kept.join('; '), _maxAnnotationNote);
}

/// `{0,120}` bounds each captured run so a pathological line cannot produce an
/// unbounded capture; a longer parenthetical simply doesn't match and the line
/// takes the normal (annotation-stripped or custom) path.
final RegExp _annotationRe = RegExp(r'\(([^()]{0,120})\)|\[([^\[\]]{0,120})\]');
final RegExp _numericOnly = RegExp(r'^\d+$');
const int _maxAnnotations = 8;
const int _maxAnnotationNote = 200;

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
/// both — and by the CallersBox adapter's balance-a-wave decoder (#295), which
/// reads the SAME codes out of a `(NR,WL)` wave annotation — so there is
/// exactly one map. Public for that cross-file reuse; treat it as read-only.
///
/// A code with no entry here is NOT approximated — every decoder that reads
/// this map declines the run rather than guessing a token (prefer-custom /
/// never fabricate). **What "declines" then costs depends on the decoder**, and
/// the distinction is worth stating because it used to be described here as
/// always meaning "custom", which was never quite true and is now broadly
/// untrue:
///
/// - **The run IS the figure's structure** — [_hey], and
///   [grandRightAndLeftFromPassList]. Without the pass list there is nothing to
///   build, so the line goes to the custom fallback. `Hey 1/2 (P6R;P7L)` is
///   custom.
/// - **The run only ADDS params** — [_squareThroughPassList] (#799) and the
///   general [_sideRunAnnotation] (#843). The line still structures through the
///   shared recognizer; it simply keeps the taxonomy's defaults instead of the
///   values the run states. `Square through 2 (C1R;C2L)` stays a
///   `square_through`, and `Pass through along (OR)` stays a `pass_through`.
///
/// Either way no token is invented, which is the property that matters. The
/// second bullet already applied to `square_through` before #843; that issue's
/// general decoder widened the population it covers to every move with a side
/// slot.
///
/// Notable mappings and the deliberate omissions, per `Glossary.htm`:
/// - `C1`/`C2`/`C3` — the glossary's *"Corners (square)"* are a DIFFERENT
///   concept from its separate *"First/second corners"* entry ("First corners
///   are man one and woman two"), which is what [ParamVocab]'s
///   `firstCorners`/`secondCorners` model. C1 is "the non-partner next to you",
///   C2 "the person across from you", C3 "the remaining person" — a square/
///   four-face-four relationship the taxonomy has no token for.
/// - `P0`, `P2`–`P5` — a mixer's previous/future partners (taxonomy v24,
///   issue #732). These map to `prevPartners`, `nextPartners`, `thirdPartners`,
///   `fourthPartners`, `fifthPartners` respectively (see entries below).
///   `P6`+ and every `P-n` are absent from this map and decline to custom.
/// - `N5`+, `N-1`, `N-2`, `S3`+, `S-n` — beyond the modelled neighbor/shadow
///   depth.
/// - `Ph*` (phantoms), `TB*` (trail buddy), `SR*` (same-role), and bare `R`/`L`
///   (states a hand but no dancer at all).
/// - `O` — the glossary's *"opposite"* (`docs/research/callersbox.md`), the
///   most common unmapped prefix in the corpus (72 cells, ahead of `Ph` 21 and
///   `SRN` 17). It is listed here because its absence was previously
///   undocumented, which read as an oversight rather than a decision: the code
///   is real, and a reader checking the glossary against this map would find it
///   missing with no reason given. The taxonomy has no `opposites` token — in a
///   duple-minor improper set the dancer "across" is your neighbor or your
///   partner depending on where you are, so `O` is not a fixed relationship the
///   dancer-set vocabulary can name. Behaviour is already correct without any
///   change — an unmapped code declines the run, per the rule above — so this
///   is a DOCUMENTATION fix only; the owner ruled on 2026-08-06 that no new
///   token should be added.
const Map<String, String> tcbPassPeople = {
  'm': 'role1s',
  'w': 'role2s',
  'p': 'partners',
  // Glossary (Partners (mixers)): "Your current partner is P1." So `P1` is the
  // same person the bare `P` names.
  'p1': 'partners',
  // Glossary (Partners (mixers)): "Your previous partner is P0."
  'p0': 'prevPartners',
  // Glossary (Partners (mixers)): "The next partner in your direction of
  // progression is P2, then P3, and so forth." Taxonomy v24 (issue #732) adds
  // tokens for P0 and P2–P5. P6+ and every P-n have no token and are absent
  // from this map, so the decoder that reads them declines the run (see the
  // doc above for what declining costs per decoder — it is not always custom).
  'p2': 'nextPartners',
  'p3': 'thirdPartners',
  'p4': 'fourthPartners',
  'p5': 'fifthPartners',
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

/// Decodes TCB's `Square through <n> (<pass list>)` shorthand into a structured
/// `square_through`, reading the parenthetical pass codes that
/// [_stripAnnotations] would otherwise drop before recognition (#799).
///
/// **Why a dedicated pre-recognizer.** The pass list is the STRUCTURED payload
/// of the line, not a droppable prose qualifier — exactly like the `hey` pass
/// list ([_hey]) and `grand right and left` ([grandRightAndLeftFromPassList]),
/// and unlike the note-preserving `()`/`[]` qualifiers #729/#733/#744 handle.
/// Without it, `Square through 2 (N2R;SL)` reaches the shared recognizer as a
/// bare `square through 2`, which sets only `places` and lets `who`/`who2`/
/// `hand`/`balance` fall to their taxonomy defaults (`partners`/`neighbors`/
/// `right`/**`true`**). That does not merely lose the pass detail: the default
/// `who`/`who2` assert the WRONG dancers and the default `balance: true` renders
/// a balance the line never states (and, inside the `interrupted square
/// through` compound this issue reports, DOUBLES the balance the sibling
/// sub-figure already carries). This is a fidelity bug across the whole class of
/// `Square through <n> (<pass list>)` lines, not only the reported "2".
///
/// **Mapping (see the `square_through` renderer).** A square through's passes
/// alternate between two dancer sets and two hands: odd passes name `who` at the
/// base `hand`, even passes name `who2` at the opposite hand. So the pass list
/// is decoded as `<people-code><R|L>` cells whose:
///   * odd 1-based positions must all name the SAME dancer → `who`;
///   * even positions must all name the same dancer → `who2`;
///   * hands strictly alternate by position parity → the base `hand` (position
///     1's hand).
///
/// **`balance: false` explicitly (import fidelity).** TCB writes the balance as
/// a SEPARATE preceding line, never inline on a square-through line, so a
/// standalone `Square through <n> (…)` carries NO balance. `square_through`'s
/// MoveDef defaults `balance: true`, so — mirroring [_roryOMore] — we emit
/// `false` rather than inheriting a balance the source never stated. (This
/// pre-recognizer does not itself fold a preceding balance line in; a preceding
/// `<who> balance` remains its own figure, matching TCB's two-line source.)
///
/// **Conservative / prefer-custom (returns `null` → shared/custom path) when:**
///   * there is no single `(...)` pass list (a second parenthetical also
///     declines — extra structure we do not model);
///   * the text OUTSIDE the pass list is not exactly `square through <n>`
///     (modulo filler), `n` in 2..10 — so an `interrupted`/`modified` qualifier,
///     a trailing `-` clause, an inline `balance`, or any other prose stays out;
///   * the cell count does not equal `n` (a square through of `n` has `n`
///     passes; a mismatch is an unmodeled variant);
///   * any cell is not `<people-code><R|L>` with the people code present in
///     [tcbPassPeople] (square corners, mixer partner series, out-of-range
///     neighbors/shadows, phantoms and bare `R`/`L` therefore stay custom rather
///     than being approximated onto a token that means something else);
///   * the odd/even dancers are not internally consistent, or the hands do not
///     alternate (an ambiguous list is never partially structured).
///
/// [_boundedPassListCells] bounds the decode pre-split (OWASP: figure text is
/// untrusted, so the cell list must be capped before it is allocated, not
/// after); the `n <= 10` cap then keeps the accepted cell count small. Both
/// are shared with the hey and grand-right-and-left decoders.
FigureMatch? _squareThroughPassList(String scrubbed) {
  final lower = scrubbed.toLowerCase();
  final open = lower.indexOf('(');
  if (open == -1) return null;
  final close = lower.indexOf(')', open + 1);
  if (close == -1) return null;
  // A second parenthetical means extra structure we do not model -> decline.
  if (lower.indexOf('(', close + 1) != -1) return null;
  final passText = lower.substring(open + 1, close);
  final outside = '${lower.substring(0, open)} ${lower.substring(close + 1)}';

  // Outside the pass list must be EXACTLY "square through <n>" (+ filler).
  final outWords = outside
      .split(RegExp(r'\s+'))
      .map(_stripEdgePunct)
      .where((w) => w.isNotEmpty && !_filler.contains(w))
      .toList();
  if (outWords.length != 3) return null;
  if (outWords[0] != 'square' || outWords[1] != 'through') return null;
  final places = int.tryParse(outWords[2]);
  // A square through has at least 2 passes; the upper bound mirrors the shared
  // recognizer's 1..10 places domain.
  if (places == null || places < 2 || places > 10) return null;

  final cells = _boundedPassListCells(passText);
  // "Square through n" is exactly n passes; a mismatch is an unmodeled variant.
  // The OWASP cell bound is enforced pre-split by [_boundedPassListCells]; here
  // `== places` (places <= 10) already constrains the count.
  if (cells == null || cells.length != places) return null;

  String? who;
  String? who2;
  String? handBase;
  for (var i = 0; i < cells.length; i++) {
    final position = i + 1; // 1-based pass position.
    final cell = cells[i];
    if (cell.isEmpty) return null;
    final handChar = cell[cell.length - 1];
    final hand = handChar == 'r'
        ? 'right'
        : handChar == 'l'
        ? 'left'
        : null;
    if (hand == null) return null;
    final person = tcbPassPeople[cell.substring(0, cell.length - 1)];
    if (person == null) return null;

    // Hands alternate by parity; derive the base (position-1) hand and require
    // every cell to agree — a list that does not alternate is malformed -> null.
    final impliedBase = position.isOdd ? hand : _otherShoulder(hand);
    if (handBase == null) {
      handBase = impliedBase;
    } else if (handBase != impliedBase) {
      return null;
    }

    // Odd positions all name `who`, even positions all name `who2`.
    if (position.isOdd) {
      if (who == null) {
        who = person;
      } else if (who != person) {
        return null;
      }
    } else {
      if (who2 == null) {
        who2 = person;
      } else if (who2 != person) {
        return null;
      }
    }
  }
  if (who == null || handBase == null) return null;

  return FigureMatch(
    'square_through',
    params: {
      'places': places,
      'who': who,
      'who2': ?who2,
      'hand': handBase,
      // Import fidelity: TCB never inlines the balance on a square-through line.
      'balance': false,
    },
  );
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

  final cells = _boundedPassListCells(passText);
  if (cells == null || cells.isEmpty || cells.any((c) => c.isEmpty)) {
    return null;
  }

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
      final who = tcbPassPeople[people];
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
    final who = tcbPassPeople[cell.substring(0, cell.length - 1)];
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

/// The largest a pass list's inner text can legitimately be. A pass list has at
/// most [kMaxPassListCells] cells and each cell is a short code (a people code,
/// an optional `ricochet`/`~` marker and a trailing hand — the longest real one
/// is ~14 chars), so 24 chars per cell is generous; anything longer is not a
/// pass list we model.
const int _maxPassListChars = kMaxPassListCells * 24;

/// Splits a pass list's inner `;`-separated text into trimmed cells, or returns
/// `null` when the raw text is longer than a pass list we model can be —
/// **before** `String.split` allocates the list it would otherwise build.
///
/// Imported figure text is untrusted (OWASP). A hostile line carrying millions
/// of `;` (or one enormous "cell") must be rejected by a guard that runs before
/// the allocation, not after it: every pass-list decoder used to `split(';')`
/// first and check the cell count afterwards, so the oversized list was built
/// and only then discarded. The [_maxPassListChars] length cap fixes the class
/// in O(1) — with the raw text capped, both the resulting list and every
/// substring are provably small. Callers still apply their own exact cell-count
/// rules (`== places`, `>= 2`, `<= kMaxPassListCells`) to the returned cells.
List<String>? _boundedPassListCells(String passText) {
  if (passText.length > _maxPassListChars) return null;
  return passText.split(';').map((c) => c.trim()).toList();
}

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
///   [tcbPassPeople] — square corners (`C1`..`C3`), out-of-range mixer partner
///   codes (`P6`+/`P-n`), out-of-range neighbors/shadows, phantoms, trail
///   buddies and bare `R`/`L` (a hand with no dancer) therefore all stay custom
///   rather than being approximated onto a token that means something else;
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

  final cells = _boundedPassListCells(lower.substring(open + 1, close));
  if (cells == null || cells.length < 2 || cells.length > kMaxPassListCells) {
    return null;
  }

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
    final who = tcbPassPeople[cell.substring(0, cell.length - 1)];
    if (who == null) return null;
    passes.add(_GrandRightAndLeftPass(who, hand));
  }
  return passes;
}

const List<String> _grandRightAndLeftWords = ['grand', 'right', 'and', 'left'];
