import 'package:meta/meta.dart';

import '../model/dance.dart';
import '../model/figure.dart';
import 'raw_record.dart';

/// Severity of a non-fatal note surfaced while parsing a record.
enum ImportIssueSeverity { info, warning }

/// A non-fatal note attached to a [StructuredDraft] (e.g. "3 figures fell back
/// to custom", "unknown formation string"). Parsing never fails a dance
/// (`docs/design/imports.md`), so problems surface here rather than as thrown
/// errors.
@immutable
class ImportIssue {
  const ImportIssue({
    required this.severity,
    required this.code,
    required this.message,
    this.figureIndex,
  });

  final ImportIssueSeverity severity;

  /// Stable machine code (e.g. `custom_figure_fallback`).
  final String code;
  final String message;

  /// Index into [Dance.figures] this issue concerns, if figure-specific.
  final int? figureIndex;

  @override
  String toString() => '[${severity.name}] $code: $message';
}

/// The parse-quality score for a draft: what fraction of its figures were
/// mapped to structured taxonomy moves versus falling back to [customMove].
///
/// A dance with no figures (a metadata-only stub) scores [perfect] (1.0) — an
/// empty transcription is not a parse *failure*. A dance that is entirely
/// custom scores 0.0 and is still a valid, committable draft.
@immutable
class ParseQuality {
  const ParseQuality({required this.totalFigures, required this.customFigures})
    : assert(totalFigures >= 0),
      assert(customFigures >= 0),
      assert(customFigures <= totalFigures);

  /// A draft with no figures to evaluate: full score, no penalty.
  static const ParseQuality perfect = ParseQuality(
    totalFigures: 0,
    customFigures: 0,
  );

  final int totalFigures;
  final int customFigures;

  int get structuredFigures => totalFigures - customFigures;

  /// Fraction of figures that are structured, in `0.0..1.0`. Empty → 1.0.
  double get score =>
      totalFigures == 0 ? 1.0 : structuredFigures / totalFigures;

  /// True when every figure fell back to custom (and there is at least one).
  bool get isFullyCustom => totalFigures > 0 && customFigures == totalFigures;

  /// Computes the quality of an already-built figure list.
  factory ParseQuality.ofFigures(List<Figure> figures) => ParseQuality(
    totalFigures: figures.length,
    customFigures: figures.where((f) => f.isCustom).length,
  );

  @override
  bool operator ==(Object other) =>
      other is ParseQuality &&
      other.totalFigures == totalFigures &&
      other.customFigures == customFigures;

  @override
  int get hashCode => Object.hash(totalFigures, customFigures);

  @override
  String toString() =>
      'ParseQuality($structuredFigures/$totalFigures structured, '
      '${(score * 100).toStringAsFixed(0)}%)';
}

/// The output of an adapter's `parse` step: a parsed [Dance] draft together
/// with the [raw] record it came from, a [quality] score, and any non-fatal
/// [issues].
///
/// The draft's [dance] carries no provenance yet — the pipeline attaches
/// provenance (derived from [raw]) at commit time, so the same draft can be
/// re-targeted (new vs re-import vs link) without rebuilding it.
@immutable
class StructuredDraft {
  StructuredDraft({
    required this.dance,
    required this.raw,
    ParseQuality? quality,
    List<ImportIssue> issues = const [],
  }) : quality = quality ?? ParseQuality.ofFigures(dance.figures),
       issues = List.unmodifiable(issues);

  /// The parsed dance. Figures that could not be structured are present as
  /// [customMove] figures carrying their beats + text (the parse-never-fails
  /// invariant); the draft is valid even if 100% custom.
  final Dance dance;
  final RawRecord raw;
  final ParseQuality quality;
  final List<ImportIssue> issues;

  @override
  String toString() =>
      'StructuredDraft(${dance.title}, $quality, ${issues.length} issues)';
}

/// Builds a [customMove] [Figure] for an unparseable source line, preserving
/// its beats and text so nothing is ever dropped (the parse-never-fails
/// invariant, `docs/design/imports.md`). Adapters (6.2+) call this whenever a
/// figure line does not map to a structured taxonomy move.
///
/// [text] is stored in `params['text']` (the taxonomy's [customMove] `text`
/// parameter — this is what the renderer reads to feed canonical/search text);
/// [beats] (when > 0) is stored in `params['beats']` so the custom figure still
/// contributes to the dance's timing.
Figure customFigure(String text, {int beats = 0, bool progression = false}) {
  if (beats < 0) {
    throw ArgumentError.value(beats, 'beats', 'must be non-negative');
  }
  return Figure(
    move: customMove,
    params: {'text': text, if (beats > 0) 'beats': beats},
    progression: progression,
  );
}
