import '../dialect/dialect.dart';
import '../dialect/renderer.dart';
import '../model/dance.dart';
import '../model/enums.dart';
import '../model/phrase_structure.dart';
import '../taxonomy/contra_taxonomy.dart';
import 'export_labels.dart';

/// Renders a single [Dance] as a clean, human-readable plain-text card — the
/// single-dance analogue of [programToPlainText] and the shareable/copyable
/// companion to the dance-detail screen (`docs/design/ux.md` §2).
///
/// Like the program renderer this lives in `compendium_core` and is
/// intentionally **pure Dart** (no Flutter/intl): it can be unit-tested and is
/// reused by the app's share/copy path and by the PDF layout (which mirrors the
/// same field ordering).
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
/// Layout:
/// ```
/// <TITLE>
/// <author, author>
/// Formation: <formationLabel>
/// Level: <levelLabel>
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
}) {
  final fig = renderer ?? FigureRenderer(contraTaxonomy);
  final lines = <String>[];

  lines.add(dance.title.trim());

  final names = authorNames.map((n) => n.trim()).where((n) => n.isNotEmpty);
  if (names.isNotEmpty) lines.add(names.join(', '));

  if (_has(formationLabel)) {
    lines.add('${labels.formation}: ${formationLabel.trim()}');
  }
  if (_has(levelLabel)) lines.add('${labels.level}: ${levelLabel!.trim()}');
  // Mirror the on-screen card, which only surfaces a status banner for a
  // non-active dance; an active dance omits the Status line entirely.
  if (dance.status != DanceStatus.active && _has(statusLabel)) {
    lines.add('${labels.status}: ${statusLabel.trim()}');
  }
  if (_has(dance.phraseStructure.raw)) {
    lines.add('${labels.phrase}: ${dance.phraseStructure.raw.trim()}');
  }

  if (dance.figures.isNotEmpty) {
    lines.add('');
    lines.add('${labels.figures}:');
    final sectioned = deriveSections(dance.figures, dance.phraseStructure);
    for (final sf in sectioned) {
      final text = fig.renderSummary(sf.figure, dialect);
      final beatsLabel = labels.beats(sf.figure.beats);
      final marker = sf.figure.progression ? ' ¶' : '';
      lines.add('${sf.label}  $text ($beatsLabel)$marker');
      final note = sf.figure.note?.trim();
      if (note != null && note.isNotEmpty) lines.add('    $note');
    }
  }

  if (_has(dance.callingNotes)) {
    lines.add('');
    lines.add('${labels.callingNotes}:');
    lines.add(fig.renderFreeText(dance.callingNotes.trim(), dialect));
  }

  if (_has(dance.walkthrough)) {
    lines.add('');
    lines.add('${labels.walkthrough}:');
    lines.add(fig.renderFreeText(dance.walkthrough.trim(), dialect));
  }

  return lines.join('\n');
}

bool _has(String? value) => value != null && value.trim().isNotEmpty;
