import 'package:meta/meta.dart';

import '../model/figure.dart';
import '../taxonomy/taxonomy.dart';

/// The result of re-parsing a figure list: the (possibly rewritten) [figures]
/// and how many import-gap customs were [upgradedCount] to structured moves.
///
/// Lives in `storage/` rather than beside `reparseImportGapFigures` in
/// `imports/` so [DanceRepository]'s reparse methods can name their parameter
/// type ([FigureReparser]) without the storage layer importing the imports
/// layer; the imports layer depends on storage, not the reverse.
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

/// A re-parse of a figure list, supplied by the caller of the repository's
/// reparse methods (`reparseImportGapFigures` from the imports layer in the
/// app). Injected so `storage/` does not import `imports/`.
typedef FigureReparser =
    FigureReparseOutcome Function(List<Figure> figures, {Taxonomy? taxonomy});
