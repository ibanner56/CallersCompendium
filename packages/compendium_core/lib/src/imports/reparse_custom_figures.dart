import 'package:meta/meta.dart';

import '../model/figure.dart';
import '../taxonomy/taxonomy.dart';
import 'figure_front_end_fan_out.dart';

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

/// Re-runs the fan-out parser ([parseFigureLineFanOut]) over the stored text of
/// every [CustomOrigin.importGap] custom figure in [figures], upgrading in place
/// any that now map to a structured taxonomy move.
///
/// This is the local-first heart of issue #417: an import-gap custom only ever
/// existed because the parser could not map its source line at import time
/// (#398). Improved taxonomy/recognizers since then — and now the fan-out across
/// all three source front-ends (ContraDB > CallersBox > CallersCompanion) — can
/// structure some of those lines without the user deleting and re-importing
/// (which would lose their tags, ratings, notes, etc.).
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
///   non-negative int). [parseFigureLineFanOut] itself never throws (parse-
///   never-fails), so a malformed line degrades to custom rather than crashing.
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
    final result = figure.isContainer
        ? _tryUpgradeContainer(figure, taxonomy, containerDepth: 1)
        : _tryUpgradeLeaf(figure, taxonomy);
    final replacement = result?.figure;
    if (replacement == null) continue;
    rewritten ??= List<Figure>.of(figures);
    rewritten[i] = replacement;
    upgraded += result!.count;
  }

  return FigureReparseOutcome(
    figures: rewritten ?? figures,
    upgradedCount: upgraded,
  );
}

/// Recurses into either structural container, calling [_tryUpgrade] on each
/// leaf and itself on each legal opposite-kind child. If any descendant
/// upgrades, rebuilds the container preserving the container's [Figure.beats] —
/// the group total is the authoritative section-math count and must not be
/// replaced by child beats.
///
/// A replacement that would create same-kind or deeper nesting is **declined**
/// (left unchanged) rather than nested or flattened. Flattening would splice
/// children that share a different beat total into this container, silently
/// corrupting section maths.
///
/// [upgradedCount] in the returned record counts upgraded custom descendants,
/// consistent with the top-level counter semantics.
///
/// Returns `null` when [figure] is not a container, or when no child upgrades.
({Figure figure, int count})? _tryUpgradeContainer(
  Figure figure,
  Taxonomy? taxonomy, {
  required int containerDepth,
}) {
  if (!figure.isContainer) return null;
  final children = figure.subFigures;
  List<Figure>? newChildren;
  var upgraded = 0;
  for (var i = 0; i < children.length; i++) {
    final child = children[i];
    final result = child.isContainer
        ? _tryUpgradeContainer(
            child,
            taxonomy,
            containerDepth: containerDepth + 1,
          )
        : _tryUpgradeLeaf(
            child,
            taxonomy,
            allowContainerReplacement: containerDepth < kMaxContainerDepth,
          );
    final replacement = result?.figure;
    if (replacement == null ||
        (replacement.isContainer &&
            (containerDepth >= kMaxContainerDepth ||
                !_isLegalContainerChild(figure, replacement)))) {
      continue;
    }
    newChildren ??= List<Figure>.of(children);
    newChildren[i] = replacement;
    upgraded += result!.count;
  }
  if (newChildren == null) return null;
  return (
    // Use copyWith so every field the container may carry — walkthroughOverride,
    // customOrigin, assumedSubject, schemaVersion, and any future params — is
    // preserved by construction rather than by remembering to name it.
    // Only params['figures'] is replaced; beats lives at params['beats'] and
    // comes through the spread automatically.
    figure: figure.copyWith(
      params: {
        ...figure.params,
        'figures': List<Figure>.unmodifiable(newChildren),
      },
    ),
    count: upgraded,
  );
}

bool _isLegalContainerChild(Figure parent, Figure child) {
  if (!child.isContainer || child.move == parent.move) return false;
  return child.subFigures.every((grandchild) => !grandchild.isContainer);
}

({Figure figure, int count})? _tryUpgradeLeaf(
  Figure figure,
  Taxonomy? taxonomy, {
  bool allowContainerReplacement = true,
}) {
  final replacement = _tryUpgrade(figure, taxonomy);
  if (replacement == null ||
      (!allowContainerReplacement && replacement.isContainer)) {
    return null;
  }
  return (figure: replacement, count: 1);
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

  final parsed = parseFigureLineFanOut(
    text,
    beats: beats,
    progression: figure.progression,
    taxonomy: taxonomy,
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
