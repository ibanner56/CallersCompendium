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
/// figure table is rendered in full (unless [compactFigures] asks for the
/// set-list layout) and **dialect-aware** using the same core
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
/// [compactFigures] selects the set-list figure layout: no beat or bar
/// counts, and each phrase label on a line of its own above the figures that
/// start in that phrase. Nothing relies on aligned spacing, so the layout survives a
/// proportional font. The single-dance card
/// and the dances CSV keep the default layout, which labels and times every
/// figure. See [danceCardFigureLines].
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
/// With [compactFigures]:
/// Figures:
/// A1
/// <rendered figure> ¶
/// <figure starting in the same phrase>
///     <optional per-figure note>
/// A2
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
  bool compactFigures = false,
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
    lines.addAll(
      danceCardFigureLines(
        dance,
        content,
        renderer: fig,
        labels: labels,
        canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
        compact: compactFigures,
      ),
    );
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

/// The figure lines of [dance]'s card: by default one per figure with its
/// phrase label (none for a free-form dance), beat or bar count and
/// progression mark, each followed by its indented note when it
/// has one. They are worded in [content]'s dialect, exactly as
/// [danceToPlainText] words them: that renderer writes these lines under its
/// Figures heading, and the dances CSV export (#2332) writes them in its Figures
/// cell, so the two cannot drift.
///
/// With [compact] (the set-list layout, [danceToPlainText]'s
/// `compactFigures`) the beat and bar counts are left off, and each phrase label gets
/// a line of its own, written once above the figures that start in that
/// phrase.
///
/// [content] must be built from [dance] with the same [renderer] and
/// [canonicalizeDiscouragedTerms]. Empty when the dance has no readable
/// figures.
List<String> danceCardFigureLines(
  Dance dance,
  DanceCardContent content, {
  required FigureRenderer renderer,
  DanceExportLabels labels = const DanceExportLabels(),
  bool canonicalizeDiscouragedTerms = false,
  bool compact = false,
}) {
  if (content.figures.isEmpty) return const [];
  final cardDialect = content.dialect;
  final lines = <String>[];
  final sectioned = deriveSections(
    content.figures,
    dance.phraseStructure,
    freeForm: dance.isFreeForm,
  );
  final timing = barTimingFor(
    dance.form,
    dance.phraseStructure,
    meter: dance.meter,
  );
  String? previousLabel;
  for (final sf in sectioned) {
    final text = canonicalizeDiscouragedTerms
        ? renderer.renderSummaryWithCanonicalDiscouragedTerms(
            sf.figure,
            cardDialect,
          )
        : renderer.renderSummary(sf.figure, cardDialect);
    final marker = sf.figure.progression ? ' ¶' : '';
    // A free-form dance's figures have no phrase label to lead with.
    if (compact) {
      // The compact layout heads each phrase with its label on a line of its
      // own; no column alignment, which a proportional font would not keep.
      if (sf.label.isNotEmpty && sf.label != previousLabel) {
        lines.add(sf.label);
      }
      previousLabel = sf.label;
      lines.add('$text$marker');
    } else {
      final lead = sf.label.isEmpty ? '' : '${sf.label}  ';
      final beatsLabel = labels.count(sf.figure.beats, timing, sf.startBeat);
      lines.add('$lead$text ($beatsLabel)$marker');
    }
    final note = sf.figure.note?.trim();
    if (note != null && note.isNotEmpty) {
      final renderedNote = canonicalizeDiscouragedTerms
          ? renderer.renderFreeTextWithCanonicalDiscouragedTerms(
              note,
              cardDialect,
            )
          : renderer.renderFreeText(note, cardDialect);
      lines.add('    $renderedNote');
    }
  }
  return lines;
}
