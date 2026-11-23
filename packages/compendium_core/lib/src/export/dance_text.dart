import '../dialect/dialect.dart';
import '../dialect/renderer.dart';
import '../model/bar_count.dart';
import '../model/dance.dart';
import '../model/phrase_structure.dart';
import '../taxonomy/taxonomy_registry.dart';
import 'dance_card_content.dart';
import 'dance_share_fields.dart';
import 'export_labels.dart';

/// Renders a single [Dance] as a clean, human-readable plain-text card — the
/// single-dance analogue of [programToPlainText] and the shareable/copyable
/// companion to the dance-detail screen (`docs/design/ux.md` §2).
///
/// Like the program renderer this lives in `compendium_core` and is
/// intentionally **pure Dart** (no Flutter/intl): it can be unit-tested and is
/// reused by the app's share/copy path. It serialises a [DanceCardContent];
/// the PDF builders lay out the same [DanceCardContent], so the field gating
/// and the dialect rendering of the notes, walkthrough and tunes are computed
/// in one place.
///
/// Unlike a program set list, a dance card *is* dance-card territory, so the
/// figure table is rendered in full and **dialect-aware** using the same core
/// APIs the detail and Perform screens use ([deriveSections] +
/// [FigureRenderer.renderSummary] for figures, [FigureRenderer.renderFreeText]
/// for calling notes). Using [FigureRenderer.renderSummary] (not the terse
/// [FigureRenderer.render]) is what keeps the export at parity with the screen:
/// it surfaces the ContraDB secondary modifiers the terse form omits — balance
/// prefixes, down/up-the-hall and zig-zag enders, and long-lines direction — so
/// role/move terms *and* modifiers match the on-screen output for the chosen
/// [dialect].
///
/// The caller resolves and passes in the display strings that the app owns:
/// - [authorNames] are the already-resolved choreographer *names* (privacy
///   precedent, ROADMAP 4b.4: a shared export must never carry a Choreographer
///   record, so private contact fields like email/location have no path in —
///   this renderer only ever sees names).
/// - [interpreterNames] are the already-resolved names of the people who
///   interpreted the dance, under the same contract; they print with the
///   authors, under [DanceShareField.authors], and never choose the dialect.
/// - [formationLabel], [levelLabel] and [statusLabel] are the app's
///   human-readable facet labels; [levelLabel] is `null` when unspecified and
///   the Level line is omitted. The Status line is omitted for an active dance.
///
/// [renderer] supplies the dialect rendering engine; when omitted a default
/// `FigureRenderer` over `TaxonomyRegistry.anyForm` is used, as the app
/// wires it.
///
/// [sourceLines] are the already-resolved published-source citation lines (one
/// per citation, built by the app from its localized strings); they appear
/// only when [DanceShareField.sources] is in [fields].
///
/// [fields] selects which non-figures fields appear (issue #1434); figures
/// are controlled separately (unaffected by this parameter). Defaults to
/// [DanceShareField.allExceptTunes]: every block this renderer emitted
/// before the picker existed, plus the meter, key and Barnes lines; tunes,
/// the hook and sources stay off until explicitly selected.
///
/// Layout:
/// ```
/// <TITLE>
/// <author, author> (<composed year>)
/// Interpreted by <interpreter, interpreter> (<interpreted year>)
/// Formation: <formationLabel>
/// Level: <levelLabel>
/// Mixer
/// Status: <statusLabel>
/// Phrase: <phrase structure, see phraseStructureText>
/// Meter: <meter> · Key: <key>
/// Barnes: <Barnes reference>
/// Hook: <hook>
///
/// Figures:
/// A1  <rendered figure> (16 beats) ¶
///     <optional per-figure note>
/// ...
///
/// Calling notes:
/// <rendered notes>
///
/// Walkthrough:
/// <rendered walkthrough>
///
/// Tunes:
/// <tune, tune, ...>
///
/// Sources:
/// <one resolved citation per line>
/// ```
/// Absent parts are omitted. A dance with no figures renders the header (and
/// notes, if any) only.
String danceToPlainText(
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
  final content = DanceCardContent.build(
    dance,
    dialect: dialect,
    authorNames: authorNames,
    interpreterNames: interpreterNames,
    formationLabel: formationLabel,
    levelLabel: levelLabel,
    statusLabel: statusLabel,
    renderer: fig,
    labels: labels,
    canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
    fields: fields,
    sourceLines: sourceLines,
  );
  final cardDialect = content.dialect;
  String renderText(String text) => canonicalizeDiscouragedTerms
      ? fig.renderFreeTextWithCanonicalDiscouragedTerms(text, cardDialect)
      : fig.renderFreeText(text, cardDialect);
  final lines = <String>[];

  lines.add(content.title);

  lines.addAll(content.creditLines);
  lines.addAll(content.metaLines);
  lines.addAll(content.musicLines);

  if (content.hook case final hook?) {
    lines.add('${labels.labelled(labels.hook)}$hook');
  }

  if (content.figures.isNotEmpty) {
    lines.add('');
    lines.add(labels.heading(labels.figures));
    final sectioned = deriveSections(content.figures, dance.phraseStructure);
    final timing = barTimingFor(
      dance.form,
      dance.phraseStructure,
      meter: dance.meter,
    );
    for (final sf in sectioned) {
      final text = canonicalizeDiscouragedTerms
          ? fig.renderSummaryWithCanonicalDiscouragedTerms(
              sf.figure,
              cardDialect,
            )
          : fig.renderSummary(sf.figure, cardDialect);
      final beatsLabel = labels.count(sf.figure.beats, timing, sf.startBeat);
      final marker = sf.figure.progression ? ' ¶' : '';
      lines.add('${sf.label}  $text ($beatsLabel)$marker');
      final note = sf.figure.note?.trim();
      if (note != null && note.isNotEmpty) {
        final renderedNote = renderText(note);
        lines.add('    $renderedNote');
      }
    }
  }

  if (content.callingNotes case final notes?) {
    lines.add('');
    lines.add(labels.heading(labels.callingNotes));
    lines.add(notes);
  }

  if (content.walkthrough case final walkthrough?) {
    lines.add('');
    lines.add(labels.heading(labels.walkthrough));
    lines.add(walkthrough);
  }

  if (content.tuneNames.isNotEmpty) {
    lines.add('');
    lines.add(labels.heading(labels.tunes));
    lines.add(content.tuneNames.join(', '));
  }

  if (content.sourceLines.isNotEmpty) {
    lines.add('');
    lines.add(labels.heading(labels.sources));
    lines.addAll(content.sourceLines);
  }

  return lines.join('\n');
}
