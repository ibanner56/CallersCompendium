import '../model/figure.dart';
import '../taxonomy/taxonomy.dart';
import 'callers_companion_mapping.dart';
import 'callersbox_figure_dialect.dart';
import 'contradb_html_adapter.dart';
import 'figure_parser.dart';

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

/// Whether a fan-out attempt [result] counts as a structured (non-custom)
/// success: it must be non-empty AND every figure must be non-custom. For a
/// single-figure line this is just "the one figure structured"; for a
/// multi-figure `;`-compound (only [tcbFigureFrontEnd] splits — see
/// [parseFigureLinesFanOut]) it is the existing all-or-nothing contract: every
/// clause structured.
bool _isStructured(List<Figure> result) =>
    result.isNotEmpty && result.every((f) => !f.isCustom);

/// Runs one [frontEnd] over [rawText] for the PLURAL (free-text entry) path,
/// returning one [Figure] per emitted clause.
///
/// The top-level `;`-compound splitter is a TCB-dialect construct that lives in
/// `callersbox_figure_dialect.dart` ([parseFigureLines]); ContraDB and
/// CallersCompanion do NOT `;`-split, so only the [tcbFigureFrontEnd] attempt is
/// routed through [parseFigureLines] — every other front-end (including any
/// caller-injected one) attempts the WHOLE line as a single figure via
/// [parseFigureLine]. An empty result means the line was empty after scrubbing
/// (front-end-independent), which the plural fan-out treats as "nothing to
/// insert".
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
  final figure = parseFigureLine(
    rawText,
    beats: beats,
    progression: progression,
    taxonomy: taxonomy,
    frontEnd: frontEnd,
  );
  return figure == null ? const [] : [figure];
}

/// Parses a SINGLE free-text figure line by fanning OUT across [frontEnds] (the
/// [figureFanOutFrontEnds] precedence list by default) and returning the
/// highest-precedence structured (non-custom) [Figure].
///
/// This is the single-line orchestrator used by the reparse-customs upgrade
/// path: it never `;`-splits (matching that path's historical single-line
/// behaviour). Each front-end is tried in order via [parseFigureLine]:
/// - the FIRST front-end that returns a non-custom figure wins;
/// - if every front-end degrades to custom, the custom fallback is returned.
///   [parseFigureLine]'s custom fallback uses the UN-normalized scrubbed text,
///   so it is byte-identical across all front-ends (only recognition differs);
///   the first front-end's custom is therefore a faithful, source-neutral
///   fallback carrying today's [CustomOrigin.importGap] flag, beats, and
///   progression;
/// - `null` is returned only when the line is empty after scrubbing (nothing to
///   store) — this is front-end-independent, so the first `null` short-circuits.
///
/// [frontEnds] defaults to (and an EMPTY list is coalesced to)
/// [figureFanOutFrontEnds]; the parameter exists to substitute a DIFFERENT,
/// non-empty set of front-ends in tests, and an empty set is meaningless (you
/// cannot fan out across nothing), so it is treated as "use the defaults" rather
/// than silently dropping a non-empty line.
Figure? parseFigureLineFanOut(
  String rawText, {
  int beats = 0,
  bool progression = false,
  Taxonomy? taxonomy,
  List<FigureFrontEnd>? frontEnds,
}) {
  final fes = (frontEnds == null || frontEnds.isEmpty)
      ? figureFanOutFrontEnds
      : frontEnds;
  Figure? customFallback;
  for (final fe in fes) {
    final parsed = parseFigureLine(
      rawText,
      beats: beats,
      progression: progression,
      taxonomy: taxonomy,
      frontEnd: fe,
    );
    // Empty after scrubbing is front-end-independent: nothing to store.
    if (parsed == null) return null;
    if (!parsed.isCustom) return parsed;
    customFallback ??= parsed;
  }
  return customFallback;
}

/// Parses a free-text figure line — possibly a `;`-compound — by fanning OUT
/// across [frontEnds] (the [figureFanOutFrontEnds] precedence list by default)
/// and returning the highest-precedence attempt that structures the WHOLE line
/// to non-custom figure(s).
///
/// This is the plural orchestrator used by the local "free-text entry" path.
/// Each front-end is tried in precedence order over the whole line
/// (via [_attemptLines], so only the TCB attempt `;`-splits):
/// - the FIRST attempt whose figures are ALL non-custom wins (a `;`-compound
///   therefore structures via the TCB attempt once the ContraDB single-line
///   attempt misses, keeping segmentation coherent with "ContraDB/CC don't
///   `;`-split"; a top-level `||` stays whole-custom because that guard lives in
///   [parseFigureLines], reached via the TCB attempt);
/// - if no attempt fully structures, the custom fallback is returned. Every
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
List<Figure> parseFigureLinesFanOut(
  String rawText, {
  int beats = 0,
  bool progression = false,
  Taxonomy? taxonomy,
  List<FigureFrontEnd>? frontEnds,
}) {
  final fes = (frontEnds == null || frontEnds.isEmpty)
      ? figureFanOutFrontEnds
      : frontEnds;
  List<Figure>? customFallback;
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
    if (_isStructured(result)) return result;
    customFallback ??= result;
  }
  return customFallback ?? const [];
}
