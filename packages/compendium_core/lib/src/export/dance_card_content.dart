/// The gated, dialect-rendered content of a dance card, computed once and laid
/// out by every consumer (`danceToPlainText`, the single-dance PDF and the
/// program PDF's figure appendix).
library;

import '../dialect/author_role_terms.dart';
import '../dialect/dialect.dart';
import '../dialect/renderer.dart';
import '../model/dance.dart';
import '../model/figure.dart';
import '../model/figure_source.dart';
import '../taxonomy/taxonomy_registry.dart';
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
    required this.dialect,
    required this.authorNames,
    this.creditLines = const [],
    required this.metaLines,
    this.musicLines = const [],
    required this.figures,
    required this.callingNotes,
    required this.walkthrough,
    required this.tuneNames,
    this.hook,
    this.sourceLines = const [],
    this.formation,
    this.level,
  });

  /// Takes the same inputs as `danceToPlainText`.
  factory DanceCardContent.build(
    Dance dance, {
    required Dialect dialect,
    required List<String> authorNames,
    List<String> interpreterNames = const [],
    required String formationLabel,
    String? levelLabel,
    required String statusLabel,
    FigureRenderer? renderer,
    DanceExportLabels labels = const DanceExportLabels(),
    bool canonicalizeDiscouragedTerms = false,
    Set<DanceShareField> fields = DanceShareField.allExceptTunes,
    List<String> sourceLines = const [],
  }) {
    final fig = renderer ?? FigureRenderer(shippedTaxonomies.anyForm);
    // From the author names before [fields] gates them: a dance whose authors
    // are left off the card keeps its larks and robins all the same. The
    // interpreters never choose the dialect.
    final cardDialect = dialectForDance(
      dialect,
      title: dance.title,
      authorNames: authorNames,
    );
    String renderText(String text) => canonicalizeDiscouragedTerms
        ? fig.renderFreeTextWithCanonicalDiscouragedTerms(text, cardDialect)
        : fig.renderFreeText(text, cardDialect);
    String? gated(DanceShareField field, String text) {
      if (!fields.contains(field) || text.trim().isEmpty) return null;
      return renderText(text.trim());
    }

    return DanceCardContent(
      title: dance.title.trim(),
      dialect: cardDialect,
      authorNames: danceCardAuthorNames(authorNames, fields),
      creditLines: danceCardCreditLines(
        dance,
        authorNames: authorNames,
        interpreterNames: interpreterNames,
        labels: labels,
        fields: fields,
      ),
      metaLines: danceCardMetaLines(
        dance,
        formationLabel: formationLabel,
        levelLabel: levelLabel,
        statusLabel: statusLabel,
        labels: labels,
        fields: fields,
      ),
      musicLines: danceCardMusicLines(
        dance,
        labels: labels,
        fields: fields,
        render: renderText,
      ),
      figures: switch (dance.figuresSource) {
        DecodedFigures(:final figures) => figures,
        // Nothing to render: the card simply omits the figures section.
        UnreadableFigures() => const <Figure>[],
      },
      callingNotes: gated(DanceShareField.callingNotes, dance.callingNotes),
      walkthrough: gated(DanceShareField.walkthrough, dance.walkthrough),
      tuneNames: danceCardTuneNames(dance, fields),
      hook: gated(DanceShareField.hook, dance.hook),
      sourceLines: danceCardSourceLines(sourceLines, fields),
      formation: fields.contains(DanceShareField.formation)
          ? _nonBlank(formationLabel)
          : null,
      level: fields.contains(DanceShareField.level)
          ? _nonBlank(levelLabel)
          : null,
    );
  }

  /// Whether [dance] has anything to lay out beneath its title and meta lines
  /// under [fields]: structured figures, or calling notes, a walkthrough, a
  /// hook or source citations that are selected and non-empty. A set-list export appends a card for exactly
  /// these dances (a dance with only a title would add nothing).
  static bool hasBody(Dance dance, Set<DanceShareField> fields) =>
      switch (dance.figuresSource) {
        DecodedFigures(:final figures) => figures.isNotEmpty,
        UnreadableFigures() => false,
      } ||
      (fields.contains(DanceShareField.callingNotes) &&
          dance.callingNotes.trim().isNotEmpty) ||
      (fields.contains(DanceShareField.walkthrough) &&
          dance.walkthrough.trim().isNotEmpty) ||
      (fields.contains(DanceShareField.hook) && dance.hook.trim().isNotEmpty) ||
      (fields.contains(DanceShareField.sources) &&
          dance.sourceCitations.isNotEmpty);

  /// The trimmed dance title.
  final String title;

  /// The dialect this card is shown in: the one [DanceCardContent.build] was
  /// given, with lark and robin for the roles when the dance
  /// [requiresLarksRobins] (see [dialectForDance]). The free text here is
  /// already rendered in it; consumers render [figures] in it too.
  final Dialect dialect;

  /// Resolved, non-blank author names; empty when the field is deselected.
  final List<String> authorNames;

  /// The credit lines a card prints under its title, in place of the bare
  /// [authorNames]: the authors with the composed year, then the
  /// interpreters with the interpreted year (see [danceCardCreditLines]);
  /// empty when [DanceShareField.authors] is deselected or there is nothing
  /// to credit.
  final List<String> creditLines;

  /// Formation/level/mixer/status/phrase lines, already gated and labelled.
  final List<String> metaLines;

  /// The meter and key line and the Barnes line, labelled, with their values
  /// dialect-rendered (see [danceCardMusicLines]); empty when
  /// [DanceShareField.music] is deselected or the dance has none of them.
  final List<String> musicLines;

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

  /// Dialect-rendered, trimmed hook; `null` when the field is deselected or the
  /// hook is blank.
  final String? hook;

  /// Resolved source-citation lines (one per citation); empty when the field is
  /// deselected or the caller supplied none.
  final List<String> sourceLines;

  /// The trimmed formation label on its own, without the "Formation:" label
  /// [metaLines] gives it, for a layout that places it by itself; `null` when
  /// the field is deselected or the label is blank.
  final String? formation;

  /// The trimmed level label on its own, as [formation]; `null` when the
  /// field is deselected, or the dance has no level.
  final String? level;
}

String? _nonBlank(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
