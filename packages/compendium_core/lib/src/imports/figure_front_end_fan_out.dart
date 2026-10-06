import '../model/figure.dart';
import '../taxonomy/contra_taxonomy.dart';
import '../taxonomy/taxonomy.dart';
import 'callers_companion_mapping.dart';
import 'callersbox_figure_dialect.dart';
import 'contradb_figure_dialect.dart';
import 'figure_parser.dart';
import 'figure_text_scrub.dart';
import 'structured_draft.dart';

/// The source front-ends the local free-text consumers fan OUT across, in
/// descending PRECEDENCE order (issue: free-text fan-out). On a shorthand miss,
/// [parseFigureLineFanOut]/[parseFigureLinesFanOut] try each front-end in this
/// order and take the HIGHEST-PRECEDENCE result that yields a non-custom parse:
///
///   [contraDbHtmlFigureFrontEnd] > [tcbFigureFrontEnd] > [callersCompanionFigureFrontEnd]
///
/// Rationale (maintainer, 2026-07-28): ContraDB has the most defined/rigid
/// input→output rules (the shared recognizer's canonical dialect is
/// ContraDB-aligned), CallersBox/TCB is next, and CallersCompanion is the least
/// understood/supported. The three constants are referenced BY NAME so this
/// orchestration automatically benefits once the ContraDB front-end is enriched
/// from its current canonical alias into a real reverse-render front-end — no
/// change is needed here.
///
/// This list is `final` (not `const`) because [tcbFigureFrontEnd] is itself a
/// runtime `final` (it closes over pre-recognizer functions).
final List<FigureFrontEnd> figureFanOutFrontEnds = List.unmodifiable([
  contraDbHtmlFigureFrontEnd,
  tcbFigureFrontEnd,
  callersCompanionFigureFrontEnd,
]);

/// How a fan-out attempt ranks. The fan-out prefers a [clean] structured parse
/// over a [noteBearing] one REGARDLESS of front-end precedence, because the
/// enriched source front-ends (notably ContraDB) match a move as an anchored
/// PREFIX and capture whatever trails as a verbatim note. That note-tail is the
/// right structuring for genuine source-rendered input, but when a
/// TCB-dialect free-text line is fed through the fan-out it lets a front-end
/// greedily "structure" a line by swallowing the semantically-important
/// remainder into a note (e.g. `balance and swing (NR)` → a bare `balance` with
/// `and swing (NR)` dropped into a note, or `circle left 3/4` → `circle` with
/// `3/4` as a note instead of `places: 3`). Preferring a CLEAN (noteless) parse
/// from ANY front-end over a note-bearing one keeps the highest-fidelity reading
/// while still honouring precedence WITHIN each tier.
enum _AttemptTier {
  /// Non-empty, every figure structured (non-custom), and none carries a note.
  /// A container with a custom child is NOT clean (see [_hasCustomDescendant]):
  /// it is a partial parse, accepted only when no front-end reads the line whole.
  clean,

  /// Structured, but at least one figure carries a note — an acceptable
  /// last-resort structuring. Notes built by [combineFigureNotes] /
  /// `_joinAnnotations` (e.g. a `chain`'s recognizer note joined to a
  /// qualifier annotation) legitimately contain `'; '` as a combiner; the
  /// [none] demotion for a `;`/`||`-containing note only fires for
  /// **all non-TCB** front-ends — for those, a `;`/`||` in a produced note
  /// may indicate absorbed `;`-compound or simultaneity source syntax.
  noteBearing,

  /// Not a usable structured win: either custom/empty, OR (only when the caller
  /// opts in with `demoteNoteTails`: free-text entry and the re-parse upgrade)
  /// a note-bearing parse whose every note is only another move name, `and back` or a bare number — see [_noteIsLeftover];
  /// such a note would otherwise structure the line with the wrong beats and
  /// hide the rest of it, so the line stays custom instead — OR a structured
  /// parse from a **non-TCB** front-end (ContraDB, CallersCompanion) whose
  /// captured note swallowed a top-level `;`/`||`. The latter means the
  /// front-end absorbed compound (`;`) or simultaneity (`||`) syntax it must
  /// not represent as one figure, so it is rejected here and the line is left
  /// to the TCB splitter / custom fallback.
  ///
  /// [tcbFigureFrontEnd] is exempt from the swallow check because it already
  /// handles top-level `;`/`||` splitting before producing any note. A `||`
  /// inside brackets can still appear in a TCB note as literal annotation text
  /// (it is caller text, not simultaneity syntax) — see [_classify] for the
  /// full account.
  none,
}

/// Whether [note] carries a top-level (bracket-depth-0) `;` or `||` — the
/// TCB-dialect compound/simultaneity separators. Applied to results from
/// **all non-TCB** front-ends (ContraDB, CallersCompanion): a captured note
/// from those containing one may indicate the front-end absorbed `;`-compound
/// or simultaneity source syntax that must not appear in a single figure's note.
///
/// [tcbFigureFrontEnd] results are exempt — see [_classify].
bool _noteSwallowedCompound(String? note) =>
    note != null &&
    (hasTopLevelSeparator(note, '||') || hasTopLevelSeparator(note, ';'));

/// Classifies a fan-out attempt [result] into an [_AttemptTier].
///
/// [frontEnd] identifies which front-end produced [result]. When it is
/// [tcbFigureFrontEnd], the [_noteSwallowedCompound] check is skipped: the TCB
/// front-end already splits on `;` (via `parseFigureLines`) and on `||` (via
/// `meanwhileFromDoublePipe`) before producing any figure, so a `'; '` in its
/// output is a deliberately-constructed joiner from `combineFigureNotes` /
/// `_joinAnnotations` — not a sign that compound source syntax was absorbed.
/// A top-level `||` from the raw line never demotes a structured TCB result:
/// when [meanwhileFromDoublePipe] accepts (≤ `kMaxMeanwhileSides` well-formed
/// sides), every top-level `||` becomes a [Figure.meanwhile] container. When
/// it declines, [_attemptLine] falls back to [parseFigureLine] on the raw
/// text; the `||`-bearing line is unrecognised, the result is a custom figure,
/// and `_classify`'s `result.any((f) => f.isCustom)` check fires before the
/// note check applies. A `||` inside `(...)`/`[...]` is different: it is
/// invisible to `_splitTopLevel` and CAN appear in a TCB note as literal
/// annotation text — deliberately exempted here, since a `||` inside brackets
/// is caller text, not simultaneity syntax. For all other front-ends the
/// check is applied as before — ContraDB and CallersCompanion do not split on
/// `;`, so a top-level `;`/`||` in their note still means the front-end absorbed
/// compound/simultaneity source syntax it must not represent as one figure.
///
/// With [demoteNoteTails] (free-text entry and the re-parse upgrade), a
/// note-bearing result whose every note passes [_noteIsLeftover] is also
/// [_AttemptTier.none].
_AttemptTier _classify(
  List<Figure> result, {
  required FigureFrontEnd frontEnd,
  bool demoteNoteTails = false,
  Set<String> moveNames = const {},
}) {
  if (result.isEmpty || result.any((f) => f.isCustom)) return _AttemptTier.none;
  if (!identical(frontEnd, tcbFigureFrontEnd) &&
      result.any((f) => _noteSwallowedCompound(f.note))) {
    return _AttemptTier.none;
  }
  if (demoteNoteTails) {
    // Descendants count too: a ContraDB `while` builds a noteless container
    // whose first child carries the tail (`neighbors swing 16 while partners
    // swing`), which would otherwise rank clean.
    final notes = _allNotes(result).toList();
    if (notes.isNotEmpty && notes.every((n) => _noteIsLeftover(n, moveNames))) {
      return _AttemptTier.none;
    }
  }
  return result.any((f) => f.note != null || _hasCustomDescendant(f))
      ? _AttemptTier.noteBearing
      : _AttemptTier.clean;
}

/// Every non-null note on [figures] and, recursively, their sub-figures.
Iterable<String> _allNotes(Iterable<Figure> figures) sync* {
  for (final f in figures) {
    if (f.note != null) yield f.note!;
    if (f.isContainer) yield* _allNotes(f.subFigures);
  }
}

/// The whole-line import-gap custom a demoted line falls to when no front-end
/// produced a custom of its own.
Figure _demotedCustom(String rawText, int beats, bool progression) =>
    customFigure(
      scrubFigureText(rawText),
      beats: beats < 0 ? 0 : beats,
      progression: progression,
      origin: CustomOrigin.importGap,
    );

/// Whether [note] is only a leftover that must not count as a parse: another
/// move name (`petronella`), `and back`, or a bare number (`16`) — each the
/// unconsumed tail of a line a recognizer matched only as a PREFIX, so the
/// structured figure would carry the wrong beats/moves with the rest hidden.
///
/// [moveNames] is derived from the active taxonomy ([_moveNamesOf]); nothing
/// here is a hard-coded move list.
bool _noteIsLeftover(String note, Set<String> moveNames) {
  var n = note.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  n = n.replaceAll(RegExp(r'^[\s,.;:!-]+|[\s,.;:!-]+$'), '');
  // Checked before the leading "and"/"then" is stripped: "[then] [over] and
  // back" is the leftover the rule targets, but a bare "back" ("ladies chain
  // back") is the ordinary phrasing for the return chain and must keep the
  // structured parse.
  if (_andBackNote.hasMatch(n)) return true;
  n = n.replaceFirst(RegExp(r'^(and|then) '), '');
  if (n.isEmpty) return false;
  return RegExp(r'^\d+$').hasMatch(n) || moveNames.contains(n);
}

final RegExp _andBackNote = RegExp(r'^((and|then) )?(over )?and back$');

/// The lowercase move names of [taxonomy]: display names, ids spelled with
/// spaces, and search keywords.
Set<String> _moveNamesOf(Taxonomy taxonomy) => {
  for (final m in taxonomy.moves.values) ...[
    m.displayName.toLowerCase(),
    m.id.replaceAll('_', ' '),
    ...m.searchKeywords.map((k) => k.toLowerCase()),
  ],
};

/// Whether a container [f] holds a custom child. A container is never itself
/// [Figure.isCustom], so without this a `meanwhile[long_lines, custom]` built by
/// one front-end's `while` fan-out would rank [_AttemptTier.clean] and shadow a
/// later front-end's genuinely structured reading of the same line (#1415).
bool _hasCustomDescendant(Figure f) =>
    f.isContainer &&
    f.subFigures.any((c) => c.isCustom || _hasCustomDescendant(c));

/// Runs one [frontEnd] over [rawText] for the PLURAL (free-text entry) path,
/// returning one [Figure] per emitted clause.
///
/// The top-level `;`-compound splitter is a TCB-dialect construct that lives in
/// `callersbox_figure_dialect.dart` ([parseFigureLines]); ContraDB and
/// CallersCompanion do NOT `;`-split, so only the [tcbFigureFrontEnd] attempt is
/// routed through [parseFigureLines] — every other front-end (including any
/// caller-injected one) attempts the WHOLE line as a single figure via
/// [parseFigureLine]. [contraDbHtmlFigureFrontEnd] is routed through
/// [parseContraDbFigureLine] instead of a plain [parseFigureLine] call so a
/// ContraDB `A while B`/`A whiles B` simultaneity line fans into a
/// [Figure.meanwhile] container (#591/#572) with the same precedence
/// guarantees as the dedicated ContraDB import adapter — [parseFigureLines]
/// already gives [tcbFigureFrontEnd] the equivalent `||` fan-out for free. An
/// empty result means the line was empty after scrubbing (front-end-
/// independent), which the plural fan-out treats as "nothing to insert".
List<Figure> _attemptLines(
  String rawText,
  FigureFrontEnd frontEnd, {
  required int beats,
  required bool progression,
  required Taxonomy? taxonomy,
}) {
  if (identical(frontEnd, tcbFigureFrontEnd)) {
    return parseFigureLines(
      rawText,
      beats: beats,
      progression: progression,
      taxonomy: taxonomy,
      frontEnd: frontEnd,
    );
  }
  if (identical(frontEnd, contraDbHtmlFigureFrontEnd)) {
    final figure = parseContraDbFigureLine(
      rawText,
      beats: beats,
      progression: progression,
      taxonomy: taxonomy,
    );
    return figure == null ? const [] : [figure];
  }
  final figure = parseFigureLine(
    rawText,
    beats: beats,
    progression: progression,
    taxonomy: taxonomy,
    frontEnd: frontEnd,
  );
  return figure == null ? const [] : [figure];
}

/// Runs one [frontEnd] over [rawText] for the SINGULAR (reparse/free-text
/// single-line) path, returning the best single [Figure].
///
/// Mirrors [_attemptLines] but never `;`-splits (the singular path's
/// historical single-line contract — see [parseFigureLineFanOut]). `||`/
/// `while` simultaneity fan-out IS extended to this path (#591/#572,
/// maintainer decision 2026-07-31): the reparse-upgrade mechanism exists
/// precisely to upgrade an old whole-custom figure when recognition
/// improves, so an old `||`/`while` whole-custom (including a TCB
/// `<core> while <modifier>` line, [modifierFromWhile]) gets the SAME upgrade a
/// freshly-imported line does. [tcbFigureFrontEnd] tries
/// [meanwhileFromDoublePipe] first (falling back to a plain [parseFigureLine]
/// attempt when it declines — no top-level `||`, or a malformed/oversized
/// split); [contraDbHtmlFigureFrontEnd] is routed through
/// [parseContraDbFigureLine], which already runs the full recognizer
/// pipeline before attempting its own `while`/`whiles` fallback.
Figure? _attemptLine(
  String rawText,
  FigureFrontEnd frontEnd, {
  required int beats,
  required bool progression,
  required Taxonomy? taxonomy,
}) {
  if (identical(frontEnd, tcbFigureFrontEnd)) {
    final fallBackLongWave = fallBackLongWaveFromDoublePipe(
      rawText,
      beats: beats,
      progression: progression,
      taxonomy: taxonomy,
      scrub: null,
      frontEnd: frontEnd,
    );
    if (fallBackLongWave != null) return fallBackLongWave;
    final meanwhile = meanwhileFromDoublePipe(
      rawText,
      beats: beats,
      progression: progression,
      taxonomy: taxonomy,
      scrub: null,
      frontEnd: frontEnd,
    );
    if (meanwhile != null) return meanwhile;
    final whileModifier = modifierFromWhile(
      rawText,
      beats: beats,
      progression: progression,
      taxonomy: taxonomy,
      scrub: null,
      frontEnd: frontEnd,
    );
    if (whileModifier != null) return whileModifier;
    return parseFigureLine(
      rawText,
      beats: beats,
      progression: progression,
      taxonomy: taxonomy,
      frontEnd: frontEnd,
    );
  }
  if (identical(frontEnd, contraDbHtmlFigureFrontEnd)) {
    return parseContraDbFigureLine(
      rawText,
      beats: beats,
      progression: progression,
      taxonomy: taxonomy,
    );
  }
  return parseFigureLine(
    rawText,
    beats: beats,
    progression: progression,
    taxonomy: taxonomy,
    frontEnd: frontEnd,
  );
}

/// Parses a SINGLE free-text figure line by fanning OUT across [frontEnds] (the
/// [figureFanOutFrontEnds] precedence list by default) and returning the
/// best structured (non-custom) [Figure].
///
/// This is the single-line orchestrator used by the reparse-customs upgrade
/// path: it never `;`-splits (matching that path's historical single-line
/// behaviour), though it DOES fan a top-level `||`/`while` simultaneity line
/// into a [Figure.meanwhile] container — see [_attemptLine]. Each front-end
/// is tried in precedence order via [_attemptLine] and its result is ranked
/// with the [_AttemptTier] two-tier rule:
/// - the FIRST front-end that yields a CLEAN (noteless) structured figure wins
///   outright — a clean parse always beats a note-bearing one, so a
///   lower-precedence front-end that reads the whole line cleanly is preferred
///   over a higher-precedence front-end that only prefix-matched and dumped the
///   remainder into a note (e.g. TCB's `swing{prefix: balance}` is taken over
///   ContraDB's bare `balance` + `"and swing"` note);
/// - failing any clean parse, the highest-precedence NOTE-BEARING structured
///   figure is returned (e.g. a legitimate ContraDB note-tail such as an
///   allemande's `- don't let go`), UNLESS it came from a non-TCB
///   front-end (ContraDB, CallersCompanion) whose note swallowed a top-level
///   `;`/`||` — compound/simultaneity syntax a single figure must not absorb,
///   so it is rejected in favour of custom. [tcbFigureFrontEnd] is exempt: its
///   note-bearing results are always accepted because its own splitters run
///   before any note is built;
/// - failing any structured parse, the custom fallback is returned.
///   [parseFigureLine]'s custom fallback uses the UN-normalized scrubbed text,
///   so it is byte-identical across all front-ends; the first front-end's custom
///   is a faithful, source-neutral fallback carrying today's
///   [CustomOrigin.importGap] flag, beats, and progression;
/// - `null` is returned only when the line is empty after scrubbing (nothing to
///   store) — this is front-end-independent, so the first `null` short-circuits.
///
/// [frontEnds] defaults to (and an EMPTY list is coalesced to)
/// [figureFanOutFrontEnds]; the parameter exists to substitute a DIFFERENT,
/// non-empty set of front-ends in tests, and an empty set is meaningless (you
/// cannot fan out across nothing), so it is treated as "use the defaults" rather
/// than silently dropping a non-empty line.
///
/// [demoteNoteTails] has the same opt-in meaning as on [parseFigureLinesFanOut]
/// (free-text entry and the reparse upgrade only; imports keep `false`).
Figure? parseFigureLineFanOut(
  String rawText, {
  int beats = 0,
  bool progression = false,
  Taxonomy? taxonomy,
  List<FigureFrontEnd>? frontEnds,
  bool demoteNoteTails = false,
}) {
  final fes = (frontEnds == null || frontEnds.isEmpty)
      ? figureFanOutFrontEnds
      : frontEnds;
  final moveNames = demoteNoteTails
      ? _moveNamesOf(taxonomy ?? contraTaxonomy)
      : const <String>{};
  Figure? noteWin;
  Figure? customFallback;
  var demoted = false;
  for (final fe in fes) {
    final parsed = _attemptLine(
      rawText,
      fe,
      beats: beats,
      progression: progression,
      taxonomy: taxonomy,
    );
    // Empty after scrubbing is front-end-independent: nothing to store.
    if (parsed == null) return null;
    switch (_classify(
      [parsed],
      frontEnd: fe,
      demoteNoteTails: demoteNoteTails,
      moveNames: moveNames,
    )) {
      case _AttemptTier.clean:
        // Highest-precedence clean parse: nothing lower can beat it.
        return parsed;
      case _AttemptTier.noteBearing:
        noteWin ??= parsed;
      case _AttemptTier.none:
        if (parsed.isCustom) {
          customFallback ??= parsed;
        } else {
          demoted = true;
        }
    }
  }
  if (noteWin == null && customFallback == null && demoted) {
    return _demotedCustom(rawText, beats, progression);
  }
  return noteWin ?? customFallback;
}

/// Parses a free-text figure line — possibly a `;`-compound — by fanning OUT
/// across [frontEnds] (the [figureFanOutFrontEnds] precedence list by default)
/// and returning the best attempt that structures the WHOLE line to non-custom
/// figure(s).
///
/// This is the plural orchestrator used by the local "free-text entry" path.
/// Each front-end is tried in precedence order over the whole line
/// (via [_attemptLines], so only the TCB attempt `;`-splits) and ranked with the
/// [_AttemptTier] two-tier rule:
/// - the FIRST attempt that is CLEAN (all figures structured, none carrying a
///   note) wins outright, so a `;`-compound structures via the TCB attempt's
///   all-or-nothing split (its clauses are clean) rather than being swallowed
///   whole by a higher-precedence front-end that would capture the `;`-tail as a
///   single figure's note;
/// - failing any clean attempt, the highest-precedence NOTE-BEARING attempt
///   wins, UNLESS it came from a non-TCB front-end (ContraDB,
///   CallersCompanion) whose note swallowed a top-level `;`/`||`
///   (compound/simultaneity syntax that the front-end absorbed instead of
///   splitting) — such an attempt is rejected so the line stays custom.
///   [tcbFigureFrontEnd] is exempt: its note-bearing results are always
///   accepted because its own splitters run before any note is built;
/// - failing any structured attempt, the custom fallback is returned. Every
///   front-end's failing attempt collapses to the SAME single whole-line custom
///   (identical un-normalized scrubbed text, beats, progression, and
///   [CustomOrigin.importGap] origin), so the first front-end's custom preserves
///   the pre-fan-out free-text fallback byte-for-byte;
/// - an empty list is returned when the line is empty after scrubbing (nothing
///   to insert) — front-end-independent, so the first empty short-circuits.
///
/// [frontEnds] defaults to (and an EMPTY list is coalesced to)
/// [figureFanOutFrontEnds] — see [parseFigureLineFanOut] for the rationale — so
/// an empty set never silently turns a real line into "nothing to insert".
///
/// [demoteNoteTails] is OPT-IN. Free-text entry and the "Re-parse custom
/// figures" upgrade (`reparse_custom_figures.dart`) pass it; imports keep
/// `false`. The re-parse upgrade passes it deliberately: a custom that
/// free-text entry demoted carries the same `CustomOrigin.importGap` as an
/// import-gap custom, so the upgrade cannot tell them apart and must apply the
/// same rule, or it would undo the demotion. When
/// true, a note-bearing attempt whose every note is just another move name,
/// `and back` or a bare number is treated as a miss (see [_classify]) and the
/// line falls to the custom fallback, instead of becoming a structured figure
/// with the wrong beats and the rest of the line hidden in a note
/// (`ladies chain over and back`, `neighbors swing 16`). It defaults to false
/// because source-rendered imports (ContraDB HTML, `.USR`, CallersBox)
/// legitimately rely on the note tail, and changing it there would churn the
/// import fixtures.
List<Figure> parseFigureLinesFanOut(
  String rawText, {
  int beats = 0,
  bool progression = false,
  Taxonomy? taxonomy,
  List<FigureFrontEnd>? frontEnds,
  bool demoteNoteTails = false,
}) {
  final fes = (frontEnds == null || frontEnds.isEmpty)
      ? figureFanOutFrontEnds
      : frontEnds;
  final moveNames = demoteNoteTails
      ? _moveNamesOf(taxonomy ?? contraTaxonomy)
      : const <String>{};
  List<Figure>? noteWin;
  List<Figure>? customFallback;
  var demoted = false;
  for (final fe in fes) {
    final result = _attemptLines(
      rawText,
      fe,
      beats: beats,
      progression: progression,
      taxonomy: taxonomy,
    );
    // Empty after scrubbing is front-end-independent: nothing to insert.
    if (result.isEmpty) return const [];
    switch (_classify(
      result,
      frontEnd: fe,
      demoteNoteTails: demoteNoteTails,
      moveNames: moveNames,
    )) {
      case _AttemptTier.clean:
        return result;
      case _AttemptTier.noteBearing:
        noteWin ??= result;
      case _AttemptTier.none:
        if (result.every((f) => f.isCustom)) {
          customFallback ??= result;
        } else {
          demoted = true;
        }
    }
  }
  if (noteWin == null && customFallback == null && demoted) {
    // Every attempt was a demoted note tail, so no front-end produced the
    // custom itself: build the same whole-line import-gap custom they would.
    return [_demotedCustom(rawText, beats, progression)];
  }
  return noteWin ?? customFallback ?? const [];
}
