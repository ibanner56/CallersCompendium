import 'package:meta/meta.dart';

import '../model/figure.dart';
import '../model/formation.dart';
import '../model/phrase_structure.dart';
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
/// app). Injected so `storage/` does not import `imports/`. [meter] and
/// [phraseStructure] are the dance's own, which an English line's bar range
/// is counted by.
typedef FigureReparser =
    FigureReparseOutcome Function(
      List<Figure> figures, {
      Taxonomy? taxonomy,
      String? meter,
      PhraseStructure? phraseStructure,
    });

/// What one English Country Dance's opt-in ECD migration (ADR-006 §12.1 F5)
/// would write: its new [figures] and [formation], and the counts a preview
/// shows. Built by the caller-supplied [EcdDanceMigrator].
@immutable
class EcdDanceMigrationResult {
  const EcdDanceMigrationResult({
    required this.figures,
    required this.formation,
    required this.movesConverted,
    required this.linesReread,
    required this.shapeChanged,
  });

  final List<Figure> figures;
  final Formation formation;
  final int movesConverted;
  final int linesReread;
  final bool shapeChanged;

  bool get changed => movesConverted > 0 || linesReread > 0 || shapeChanged;
}

/// The ECD migration of one dance's [figures] and [formation]
/// (`migrateEcdDance` from the imports layer in the app). Injected, as
/// [FigureReparser] is, so `storage/` does not import `imports/`. The
/// dance's [meter] and [phraseStructure] count a re-read line's bar range, as
/// for [FigureReparser].
typedef EcdDanceMigrator =
    EcdDanceMigrationResult Function(
      List<Figure> figures,
      Formation formation, {
      String? meter,
      PhraseStructure? phraseStructure,
    });
