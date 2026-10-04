/// The gated, dialect-rendered content of a dance card, computed once and laid
/// out by every consumer (`danceToPlainText`, the single-dance PDF and the
/// program PDF's figure appendix).
library;

import '../dialect/dialect.dart';
import '../dialect/renderer.dart';
import '../model/dance.dart';
import '../model/figure.dart';
import '../model/figure_source.dart';
import '../taxonomy/contra_taxonomy.dart';
import 'dance_card_fields.dart';
import 'dance_share_fields.dart';
import 'export_labels.dart';

/// What a dance card carries, with every decision already made: which blocks
/// the [DanceShareField] selection turns on, the dialect conversion of the
/// free text, and trimming. Pure Dart; consumers only choose layout (plain
/// text lines, PDF widgets, font sizes), so the text card and the PDFs cannot
/// drift on which blocks appear or how their text reads.
///
/// Figures are resolved here ([figures]) but their per-figure rendering stays
/// with the consumer: the text card and the PDF share `deriveSections` and
/// `FigureRenderer.renderSummary`, not a pre-rendered string.
class DanceCardContent {
  const DanceCardContent({
    required this.title,
    required this.authorNames,
    required this.metaLines,
    required this.figures,
    required this.callingNotes,
    required this.walkthrough,
    required this.tuneNames,
  });

  /// Takes the same inputs as `danceToPlainText`.
  factory DanceCardContent.build(
    Dance dance, {
    required Dialect dialect,
    required List<String> authorNames,
    required String formationLabel,
    String? levelLabel,
    required String statusLabel,
    FigureRenderer? renderer,
    DanceExportLabels labels = const DanceExportLabels(),
    bool canonicalizeDiscouragedTerms = false,
    Set<DanceShareField> fields = DanceShareField.allExceptTunes,
  }) {
    final fig = renderer ?? FigureRenderer(contraTaxonomy);
    String renderText(String text) => canonicalizeDiscouragedTerms
        ? fig.renderFreeTextWithCanonicalDiscouragedTerms(text, dialect)
        : fig.renderFreeText(text, dialect);
    String? gated(DanceShareField field, String text) {
      if (!fields.contains(field) || text.trim().isEmpty) return null;
      return renderText(text.trim());
    }

    return DanceCardContent(
      title: dance.title.trim(),
      authorNames: danceCardAuthorNames(authorNames, fields),
      metaLines: danceCardMetaLines(
        dance,
        formationLabel: formationLabel,
        levelLabel: levelLabel,
        statusLabel: statusLabel,
        labels: labels,
        fields: fields,
      ),
      figures: switch (dance.figuresSource) {
        DecodedFigures(:final figures) => figures,
        // Nothing to render: the card simply omits the figures section.
        UnreadableFigures() => const <Figure>[],
      },
      callingNotes: gated(DanceShareField.callingNotes, dance.callingNotes),
      walkthrough: gated(DanceShareField.walkthrough, dance.walkthrough),
      tuneNames: danceCardTuneNames(dance, fields),
    );
  }

  /// The trimmed dance title.
  final String title;

  /// Resolved, non-blank author names; empty when the field is deselected.
  final List<String> authorNames;

  /// Formation/level/mixer/status/phrase lines, already gated and labelled.
  final List<String> metaLines;

  /// The decoded figures; empty when there are none or they are unreadable.
  /// Not gated by `fields` (figures are controlled separately).
  final List<Figure> figures;

  /// Dialect-rendered, trimmed calling notes; `null` when the field is
  /// deselected or the notes are blank.
  final String? callingNotes;

  /// Dialect-rendered, trimmed walkthrough; `null` when the field is
  /// deselected or the walkthrough is blank.
  final String? walkthrough;

  /// Resolved, non-blank tune names; empty when the field is deselected.
  final List<String> tuneNames;
}
