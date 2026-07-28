import 'package:meta/meta.dart';

import '../model/figure.dart';
import '../taxonomy/taxonomy.dart';
import 'callersbox_figure_dialect.dart';
import 'figure_parser.dart';

/// Upper bound on the length of stored custom text we will feed back through
/// the parser. Import-gap text is a single figure line (typically a few dozen
/// characters); anything beyond this is treated as malformed/hostile stored
/// data and left untouched rather than doing unbounded recognition work. The
/// stored text may have originated from an online import, so per OWASP we treat
/// it as untrusted even though it now lives locally.
const int maxReparseTextLength = 2000;

/// The result of re-parsing a figure list: the (possibly rewritten) [figures]
/// and how many import-gap customs were [upgradedCount] to structured moves.
@immutable
class FigureReparseOutcome {
  const FigureReparseOutcome({
    required this.figures,
    required this.upgradedCount,
  });

  /// The figure list after re-parsing. When [upgradedCount] is 0 this is the
  /// input list, unchanged (identity preserved so callers can skip writes).
  final List<Figure> figures;

  /// Number of figures that were import-gap customs at input and now parse to
  /// a structured taxonomy move.
  final int upgradedCount;

  bool get changed => upgradedCount > 0;
}

/// Re-runs the current [parseFigureLine] over the stored text of every
/// [CustomOrigin.importGap] custom figure in [figures], upgrading in place any
/// that now map to a structured taxonomy move.
///
/// This is the local-first heart of issue #417: an import-gap custom only ever
/// existed because the parser could not map its source line at import time
/// (#398). Improved taxonomy/recognizers since then can now structure some of
/// those lines — without the user deleting and re-importing (which would lose
/// their tags, ratings, notes, etc.).
///
/// Contract:
/// - Only figures with `isCustom && customOrigin == CustomOrigin.importGap` are
///   ever considered. [CustomOrigin.userEntered] customs and structured figures
///   pass through byte-identical — this is the whole point of the #398 flag.
/// - A figure is replaced ONLY when its re-parse yields a non-null, non-custom
///   figure. If the re-parse still degrades to custom (no confident match), the
///   original figure is kept unchanged (still import-gap). This makes the
///   operation idempotent: a second run finds nothing further to upgrade.
/// - Untrusted stored text is guarded before parsing (must be a non-empty
///   String no longer than [maxReparseTextLength]; beats coerced to a safe
///   non-negative int). [parseFigureLine] itself never throws (parse-never-
///   fails), so a malformed line degrades to custom rather than crashing.
/// - When nothing changes the input list is returned unchanged (identity
///   preserved) so repository callers can cheaply skip the write.
FigureReparseOutcome reparseImportGapFigures(
  List<Figure> figures, {
  Taxonomy? taxonomy,
}) {
  List<Figure>? rewritten;
  var upgraded = 0;

  for (var i = 0; i < figures.length; i++) {
    final figure = figures[i];
    final replacement = _tryUpgrade(figure, taxonomy);
    if (replacement == null) continue;
    rewritten ??= List<Figure>.of(figures);
    rewritten[i] = replacement;
    upgraded++;
  }

  return FigureReparseOutcome(
    figures: rewritten ?? figures,
    upgradedCount: upgraded,
  );
}

/// Returns a structured replacement for [figure] if it is an import-gap custom
/// whose stored text now parses to a structured move, else `null` (leave as-is).
Figure? _tryUpgrade(Figure figure, Taxonomy? taxonomy) {
  if (!figure.isCustom || figure.customOrigin != CustomOrigin.importGap) {
    return null;
  }

  final rawText = figure.params['text'];
  if (rawText is! String) return null;
  // Reject an oversized raw string BEFORE trimming/copying it: `trim()` on a
  // multi-megabyte malformed value would already do the unbounded work we want
  // to avoid. Guard on the raw length first, then normalise.
  if (rawText.length > maxReparseTextLength) return null;
  final text = rawText.trim();
  if (text.isEmpty) return null;

  final rawBeats = figure.params['beats'];
  final beats = rawBeats is int && rawBeats > 0 ? rawBeats : 0;

  final parsed = parseFigureLine(
    text,
    beats: beats,
    progression: figure.progression,
    taxonomy: taxonomy,
    frontEnd: tcbFigureFrontEnd,
  );

  // Keep the original when the re-parse is empty or still custom: an import-gap
  // figure that re-parses to custom stays exactly as it was (idempotent).
  if (parsed == null || parsed.isCustom) return null;

  return parsed.copyWith(note: _mergeNotes(figure.note, parsed.note));
}

/// Combines the [original] custom figure's note with the newly structured
/// figure's recognizer [parsed] note so neither is silently dropped when a
/// figure is upgraded. Keeps the single note when only one is present (or they
/// are equal), and joins two distinct notes with `'; '` in a stable order
/// (original first) when both exist.
String? _mergeNotes(String? original, String? parsed) {
  if (original == null || original == parsed) return parsed;
  if (parsed == null) return original;
  return '$original; $parsed';
}
