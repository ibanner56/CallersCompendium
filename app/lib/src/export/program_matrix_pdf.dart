import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'program_pdf.dart' show loadProgramMatrixMarkerFont, loadProgramPdfTheme;

/// Marker glyphs for the printed matrix. Deliberately distinct SHAPES + a
/// legend (never colour alone) so the report matches the on-screen table's
/// accessibility contract (`ProgramMatrixTable`, WCAG 1.4.1): a
/// same-figure-same-phrase collision with a strictly-adjacent dance is an
/// alert (`‼`, top precedence), a move's program debut (first dance to use it)
/// is a star, a dance's own first figure is a triangle, any other present move
/// is a check, and an absent move is blank.
///
/// The collision mark (`‼`, U+203C) is present in the bundled Roboto font's
/// glyph set, so it renders without help. The star/triangle/check marks are
/// not — the `pdf` package silently drops glyphs the active font lacks (#633)
/// — so [buildProgramMatrixPdf] registers [loadProgramMatrixMarkerFont] as a
/// `fontFallback` on the cell/legend text styles, letting `pdf` fall back to
/// it per-glyph instead of swapping these documented marks
/// (`docs/user/programs.md`) for different characters.
const String _collisionMark = '‼';
const String _debutMark = '★';
const String _firstMark = '▸';
const String _presentMark = '✓';

/// Builds a printable/saveable PDF of the Programming Matrix (ROADMAP §4.4).
///
/// A separate landscape layout from the set-list PDF ([buildProgramPdf]): a
/// matrix is wide (moves × dances), so it uses `PdfPageFormat.a4.landscape` and
/// a [pw.Table]. The header row is the dialect-aware column labels (via
/// [matrixColumnLabel]); the first column is the dance title; body cells carry
/// [_debutMark]/[_firstMark]/[_presentMark]/blank markers with the same
/// semantics as the on-screen [ProgramMatrix]
/// (`isProgramDebut`/`isFirst`/`isPresent`). A short legend explains the marks.
/// The header block (program title + event date/venue) mirrors the
/// field ordering/format of [buildProgramPdf].
///
/// - [formatDate] formats [eventDate]; defaults to ISO `yyyy-MM-dd`.
/// - [omittedFreeTextCount] renders the same "free-text slots omitted" caption
///   as the on-screen matrix, so the dances-only scope stays explicit.
/// - The empty matrix (no move columns) renders the header, the omitted caption
///   (when any), and an empty-state line instead of a table.
/// - [theme] supplies the bundled Unicode font; when omitted it is loaded via
///   [loadProgramPdfTheme].
/// - [markerFont] supplies the fallback font for the ★/▸/✓ marker glyphs the
///   bundled Roboto lacks (#633); when omitted it is loaded via
///   [loadProgramMatrixMarkerFont].
Future<Uint8List> buildProgramMatrixPdf(
  ProgramMatrix matrix, {
  required Taxonomy taxonomy,
  required Dialect dialect,
  required String programTitle,
  String Function(DateTime date)? formatDate,
  DateTime? eventDate,
  String? venue,
  int omittedFreeTextCount = 0,
  ProgramMatrixExportLabels labels = const ProgramMatrixExportLabels(),
  pw.ThemeData? theme,
  pw.Font? markerFont,
}) async {
  final fmtDate = formatDate ?? _isoDate;
  final resolvedTheme = theme ?? await loadProgramPdfTheme();
  final title = programTitle.trim().isEmpty
      ? labels.defaultTitle
      : programTitle.trim();
  final doc = pw.Document(title: title, theme: resolvedTheme);

  final dateVenue = _dateVenue(eventDate, venue, fmtDate);

  // The marker font is only used when the matrix actually has rows/columns
  // to draw (the legend + marker cells), so it's loaded lazily rather than
  // unconditionally — an empty matrix shouldn't pay for the extra asset I/O.
  final resolvedMarkerFont = matrix.isEmpty
      ? null
      : (markerFont ?? await loadProgramMatrixMarkerFont());

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      build: (context) => [
        pw.Header(
          level: 0,
          child: pw.Text(
            title,
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
        ),
        if (dateVenue.isNotEmpty)
          pw.Text(dateVenue, style: const pw.TextStyle(fontSize: 12)),
        pw.SizedBox(height: 12),
        if (matrix.isEmpty)
          pw.Text(labels.emptyState, style: const pw.TextStyle(fontSize: 12))
        else ...[
          _legend(labels, resolvedMarkerFont!),
          pw.SizedBox(height: 8),
          _matrixTable(matrix, taxonomy, dialect, labels, resolvedMarkerFont),
        ],
        if (omittedFreeTextCount > 0) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            labels.omittedCaption(omittedFreeTextCount),
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ],
      ],
    ),
  );

  return doc.save();
}

pw.Widget _matrixTable(
  ProgramMatrix matrix,
  Taxonomy taxonomy,
  Dialect dialect,
  ProgramMatrixExportLabels labels,
  pw.Font markerFont,
) {
  final columnLabels = [
    for (final c in matrix.columns) matrixColumnLabel(c, taxonomy, dialect),
  ];

  final headerStyle = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
  // The dance-title column never contains marker glyphs, so it keeps the
  // plain Roboto-only style; only the marker cells (below) get the fallback
  // font, keeping its scope exactly to the ★/▸/✓/‼ marks (#633).
  const titleStyle = pw.TextStyle(fontSize: 12);
  final markerStyle = pw.TextStyle(fontSize: 12, fontFallback: [markerFont]);

  pw.Widget headerCell(String text, {pw.Alignment? align}) => pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Align(
      alignment: align ?? pw.Alignment.center,
      child: pw.Text(text, style: headerStyle),
    ),
  );

  pw.Widget markCell(String mark) => pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Center(child: pw.Text(mark, style: markerStyle)),
  );

  final headerRow = pw.TableRow(
    decoration: const pw.BoxDecoration(color: PdfColors.grey300),
    children: [
      headerCell(labels.danceColumn, align: pw.Alignment.centerLeft),
      for (final label in columnLabels) headerCell(label),
    ],
  );

  final bodyRows = <pw.TableRow>[];
  for (var r = 0; r < matrix.rows.length; r++) {
    bodyRows.add(
      pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(matrix.rows[r].title, style: titleStyle),
          ),
          for (var c = 0; c < matrix.columns.length; c++)
            markCell(
              matrix.isPhraseCollision(r, c)
                  ? _collisionMark
                  : matrix.isProgramDebut(r, c)
                  ? _debutMark
                  : matrix.isFirst(r, c)
                  ? _firstMark
                  : matrix.isPresent(r, c)
                  ? _presentMark
                  : '',
            ),
        ],
      ),
    );
  }

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    children: [headerRow, ...bodyRows],
  );
}

pw.Widget _legend(ProgramMatrixExportLabels labels, pw.Font markerFont) =>
    pw.Text(
      '$_collisionMark  ${labels.legendCollision}      '
      '$_debutMark  ${labels.legendDebut}      '
      '$_firstMark  ${labels.legendFirst}      '
      '$_presentMark  ${labels.legendPresent}',
      style: pw.TextStyle(
        fontSize: 10,
        color: PdfColors.grey700,
        fontFallback: [markerFont],
      ),
    );

String _dateVenue(
  DateTime? eventDate,
  String? venue,
  String Function(DateTime) fmtDate,
) {
  final parts = <String>[
    if (eventDate != null) fmtDate(eventDate),
    if (venue != null && venue.trim().isNotEmpty) venue.trim(),
  ];
  return parts.join(' · ');
}

String _isoDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
