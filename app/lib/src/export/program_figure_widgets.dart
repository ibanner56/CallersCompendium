import 'package:compendium_core/compendium_core.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Renders the figure table for [dance] as a list of [pw.Widget]s.
///
/// Used by both [buildDancePdf] (as the main content of a single-dance card)
/// and by the program-PDF figure appendix ([buildProgramPdf] when the caller
/// opts into "set list and figures"). Extracted here to avoid the mutual import
/// that would arise if either PDF builder imported the other directly
/// (`dance_pdf.dart` already imports `program_pdf.dart` for [loadProgramPdfTheme]).
///
/// Layout: bold section-heading rows (A1 / A2 / B1 / B2 …) in blueGrey,
/// indented figure rows with beat-count in a right-aligned grey column, and
/// optional italic per-figure notes further indented beneath.
List<pw.Widget> buildFigureWidgets(
  Dance dance,
  FigureRenderer renderer,
  Dialect dialect,
  DanceExportLabels labels,
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
    final beatsLabel = labels.beats(sf.figure.beats);
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
            renderer.renderFreeText(note, dialect),
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
