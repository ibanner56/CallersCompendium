import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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
Future<Uint8List> buildDancePdf(
  Dance dance, {
  required Dialect dialect,
  required List<String> authorNames,
  required String formationLabel,
  String? levelLabel,
  required String statusLabel,
  FigureRenderer? renderer,
  pw.ThemeData? theme,
}) async {
  final fig = renderer ?? FigureRenderer(contraTaxonomy);
  final resolvedTheme = theme ?? await loadProgramPdfTheme();
  final doc = pw.Document(title: dance.title, theme: resolvedTheme);

  final names = authorNames.map((n) => n.trim()).where((n) => n.isNotEmpty);

  final metaLines = <String>[
    if (_has(formationLabel)) 'Formation: ${formationLabel.trim()}',
    if (_has(levelLabel)) 'Level: ${levelLabel!.trim()}',
    // Mirror the on-screen card / text export: only a non-active dance shows
    // a Status line; an active dance omits it.
    if (dance.status != DanceStatus.active && _has(statusLabel))
      'Status: ${statusLabel.trim()}',
    if (_has(dance.phraseStructure.raw))
      'Phrase: ${dance.phraseStructure.raw.trim()}',
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Header(
          level: 0,
          child: pw.Text(
            dance.title.trim(),
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
        ),
        if (names.isNotEmpty)
          pw.Text(names.join(', '), style: const pw.TextStyle(fontSize: 13)),
        for (final line in metaLines)
          pw.Text(line, style: const pw.TextStyle(fontSize: 12)),
        if (dance.figures.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            'Figures',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          ..._figureWidgets(dance, fig, dialect),
        ],
        if (_has(dance.callingNotes)) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            'Calling notes',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            fig.renderFreeText(dance.callingNotes.trim(), dialect),
            style: const pw.TextStyle(fontSize: 12),
          ),
        ],
        if (_has(dance.walkthrough)) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            'Walkthrough',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            fig.renderFreeText(dance.walkthrough.trim(), dialect),
            style: const pw.TextStyle(fontSize: 12),
          ),
        ],
      ],
    ),
  );

  return doc.save();
}

List<pw.Widget> _figureWidgets(
  Dance dance,
  FigureRenderer renderer,
  Dialect dialect,
) {
  final widgets = <pw.Widget>[];
  final sectioned = deriveSections(dance.figures, dance.phraseStructure);
  String? lastLabel;
  for (final sf in sectioned) {
    if (sf.label != lastLabel) {
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6, bottom: 2),
          child: pw.Text(
            sf.label,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey700,
            ),
          ),
        ),
      );
      lastLabel = sf.label;
    }
    final beats = sf.figure.beats;
    final beatsLabel = '$beats ${beats == 1 ? 'beat' : 'beats'}';
    final marker = sf.figure.progression ? ' ¶' : '';
    widgets.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(left: 12, top: 1, bottom: 1),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text(
                '${renderer.renderSummary(sf.figure, dialect)}$marker',
                style: const pw.TextStyle(fontSize: 12),
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Text(
              beatsLabel,
              style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
    );
    final note = sf.figure.note?.trim();
    if (note != null && note.isNotEmpty) {
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 24, bottom: 1),
          child: pw.Text(
            note,
            style: pw.TextStyle(
              fontSize: 10,
              fontStyle: pw.FontStyle.italic,
              color: PdfColors.grey700,
            ),
          ),
        ),
      );
    }
  }
  return widgets;
}

bool _has(String? value) => value != null && value.trim().isNotEmpty;
