import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'program_figure_widgets.dart';
import 'program_pdf.dart';

/// Builds a printable/saveable PDF of a single [Dance] card
/// (`docs/design/ux.md` §2 print/share).
///
/// The PDF mirrors the field ordering of [danceToPlainText] — title, authors,
/// formation, level/status, phrase notation, then the figure table grouped by
/// derived phrase section (A1, A2, …), then optional calling notes. Figures and
/// notes are rendered **dialect-aware** via the same [FigureRenderer] the
/// on-screen card uses, so the export matches what the caller sees.
///
/// It reuses the bundled Unicode font theme from the program export
/// ([loadProgramPdfTheme]) so accents, curly quotes and the `¶` progression
/// marker render correctly, and paginates automatically via [pw.MultiPage] for
/// a long card.
///
/// The caller resolves and passes in the display strings the app owns
/// ([authorNames], [formationLabel], [levelLabel], [statusLabel]); [levelLabel]
/// is `null` when unspecified and the Level line is omitted, and the Status
/// line is omitted for an active dance (mirroring the text renderer). [renderer]
/// supplies the dialect engine; when omitted a `FigureRenderer(contraTaxonomy)`
/// is used. [theme] supplies the Unicode font; when omitted it is loaded from
/// the bundled asset.
///
/// [fields] selects which non-figures fields appear (issue #1434). Gating and
/// the dialect rendering of the notes, walkthrough and tunes happen once, in
/// core's [DanceCardContent], which this builder only lays out — the same
/// object [danceToPlainText] serialises and [buildProgramPdf]'s figure-appendix
/// cards lay out. [pageFormat] defaults to A4. Defaults to
/// [DanceShareField.allExceptTunes], matching every block this builder
/// rendered before the picker existed. [pageFormat] defaults to A4.
Future<Uint8List> buildDancePdf(
  Dance dance, {
  required Dialect dialect,
  required List<String> authorNames,
  required String formationLabel,
  String? levelLabel,
  required String statusLabel,
  FigureRenderer? renderer,
  DanceExportLabels labels = const DanceExportLabels(),
  pw.ThemeData? theme,
  bool canonicalizeDiscouragedTerms = false,
  Set<DanceShareField> fields = DanceShareField.allExceptTunes,
  PdfPageFormat pageFormat = PdfPageFormat.a4,
}) async {
  final fig = renderer ?? FigureRenderer(contraTaxonomy);
  final resolvedTheme = theme ?? await loadProgramPdfTheme();
  final doc = pw.Document(title: dance.title, theme: resolvedTheme);

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

  doc.addPage(
    pw.MultiPage(
      pageFormat: pageFormat,
      build: (context) => danceCardWidgets(
        dance,
        content,
        fig,
        dialect,
        labels,
        canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
      ),
    ),
  );

  return doc.save();
}

/// Lays out a [DanceCardContent] as the single-dance PDF's widgets. Layout
/// only: every gating and dialect decision was made when [content] was built.
/// Exposed so tests can assert on what is laid out rather than on PDF bytes.
@visibleForTesting
List<pw.Widget> danceCardWidgets(
  Dance dance,
  DanceCardContent content,
  FigureRenderer renderer,
  Dialect dialect,
  DanceExportLabels labels, {
  bool canonicalizeDiscouragedTerms = false,
}) {
  pw.Widget heading(String text) => pw.Text(
    text,
    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
  );
  return [
    pw.Header(
      level: 0,
      child: pw.Text(
        content.title,
        style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
      ),
    ),
    if (content.authorNames.isNotEmpty)
      pw.Text(
        content.authorNames.join(', '),
        style: const pw.TextStyle(fontSize: 13),
      ),
    for (final line in content.metaLines)
      pw.Text(line, style: const pw.TextStyle(fontSize: 12)),
    if (content.figures.isNotEmpty) ...[
      pw.SizedBox(height: 12),
      heading(labels.figures),
      pw.SizedBox(height: 4),
      ...buildFigureWidgets(
        dance,
        renderer,
        dialect,
        labels,
        canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
      ),
    ],
    if (content.callingNotes case final notes?) ...[
      pw.SizedBox(height: 12),
      heading(labels.callingNotes),
      pw.SizedBox(height: 4),
      pw.Text(
        notes,
        style: const pw.TextStyle(fontSize: 12),
        overflow: pw.TextOverflow.span,
      ),
    ],
    if (content.walkthrough case final walkthrough?) ...[
      pw.SizedBox(height: 12),
      heading(labels.walkthrough),
      pw.SizedBox(height: 4),
      pw.Text(
        walkthrough,
        style: const pw.TextStyle(fontSize: 12),
        overflow: pw.TextOverflow.span,
      ),
    ],
    if (content.tuneNames.isNotEmpty) ...[
      pw.SizedBox(height: 12),
      heading(labels.tunes),
      pw.SizedBox(height: 4),
      pw.Text(
        content.tuneNames.join(', '),
        style: const pw.TextStyle(fontSize: 12),
      ),
    ],
  ];
}
