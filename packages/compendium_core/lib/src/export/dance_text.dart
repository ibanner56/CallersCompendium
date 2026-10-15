import '../dialect/dialect.dart';
import '../dialect/renderer.dart';
import '../model/dance.dart';
import '../model/phrase_structure.dart';
import '../taxonomy/contra_taxonomy.dart';
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
/// - [formationLabel], [levelLabel] and [statusLabel] are the app's
///   human-readable facet labels; [levelLabel] is `null` when unspecified and
///   the Level line is omitted. The Status line is omitted for an active dance.
///
/// [renderer] supplies the dialect rendering engine; when omitted a default
/// `FigureRenderer(contraTaxonomy)` is used (the same taxonomy the app wires).
///
/// [fields] selects which non-figures fields appear (issue #1434); figures
/// are controlled separately (unaffected by this parameter). Defaults to
/// [DanceShareField.allExceptTunes], matching every block this renderer
/// emitted before the picker existed — so a caller that doesn't pass [fields]
/// (every call site before this parameter was added) sees no change, and
/// tunes stays off until explicitly selected.
///
/// Layout:
/// ```
/// <TITLE>
/// <author, author>
/// Formation: <formationLabel>
/// Level: <levelLabel>
/// Mixer
/// Status: <statusLabel>
/// Phrase: <phraseStructure notation>
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
/// ```
/// Absent parts are omitted. A dance with no figures renders the header (and
/// notes, if any) only.
String danceToPlainText(
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
  final content = DanceCardContent.build(
    dance,
    dialect: dialect,
    authorNames: authorNames,
    formationLabel: formationLabel,
    levelLabel: levelLabel,
    statusLabel: statusLabel,
    renderer: fig,
    labels: labels,
    canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
    fields: fields,
  );
  String renderText(String text) => canonicalizeDiscouragedTerms
      ? fig.renderFreeTextWithCanonicalDiscouragedTerms(text, dialect)
      : fig.renderFreeText(text, dialect);
  final lines = <String>[];

  lines.add(content.title);

  if (content.authorNames.isNotEmpty) {
    lines.add(content.authorNames.join(', '));
  }

  lines.addAll(content.metaLines);

  if (content.figures.isNotEmpty) {
    lines.add('');
    lines.add('${labels.figures}:');
    final sectioned = deriveSections(content.figures, dance.phraseStructure);
    for (final sf in sectioned) {
      final text = canonicalizeDiscouragedTerms
          ? fig.renderSummaryWithCanonicalDiscouragedTerms(sf.figure, dialect)
          : fig.renderSummary(sf.figure, dialect);
      final beatsLabel = labels.beats(sf.figure.beats);
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
    lines.add('${labels.callingNotes}:');
    lines.add(notes);
  }

  if (content.walkthrough case final walkthrough?) {
    lines.add('');
    lines.add('${labels.walkthrough}:');
    lines.add(walkthrough);
  }

  if (content.tuneNames.isNotEmpty) {
    lines.add('');
    lines.add('${labels.tunes}:');
    lines.add(content.tuneNames.join(', '));
  }

  return lines.join('\n');
}
