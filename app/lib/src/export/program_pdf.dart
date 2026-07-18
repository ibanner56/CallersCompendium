import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Loads the bundled Unicode font (Roboto, SIL OFL-1.1) used for PDF export.
///
/// The built-in PDF standard fonts only cover Latin-1, so real dance titles
/// containing curly quotes, accents, or the `·`/`—` separators used in the set
/// list would render as blank glyphs. Bundling a Unicode TrueType font keeps
/// the app fully offline (no runtime font download) while rendering the same
/// characters as the emailable text. The theme is cached after first load.
pw.ThemeData? _cachedTheme;

Future<pw.ThemeData> loadProgramPdfTheme() async {
  final cached = _cachedTheme;
  if (cached != null) return cached;
  final data = await rootBundle.load('assets/fonts/Roboto-VariableFont.ttf');
  final font = pw.Font.ttf(data);
  return _cachedTheme = pw.ThemeData.withFont(base: font, bold: font);
}

/// Builds a printable/saveable PDF of a [Program] set list (ROADMAP §4.3).
///
/// The PDF mirrors the field ordering of [programToPlainText] — title,
/// event date/venue, band/caller/level, then the ordered slots with indented
/// ALTs, optional per-slot notes/guest caller/planned minutes and performed
/// markers, then optional program notes. It is laid out top-to-bottom in a
/// single logical reading order (accessible) and paginates automatically via
/// [pw.MultiPage] so a long set list flows onto extra pages for a handout.
///
/// - [titleFor] resolves a slot's dance id to a title (same contract as the
///   text renderer); [unknownDanceLabel] is used when it returns null.
/// - [formatDate] formats the event date; defaults to ISO `yyyy-MM-dd`.
/// - [theme] supplies the Unicode font; when omitted it is loaded from the
///   bundled asset via [loadProgramPdfTheme].
Future<Uint8List> buildProgramPdf(
  Program program, {
  required String? Function(String danceId) titleFor,
  String Function(DateTime date)? formatDate,
  String unknownDanceLabel = 'Untitled dance',
  pw.ThemeData? theme,
}) async {
  final fmtDate = formatDate ?? _isoDate;
  final resolvedTheme = theme ?? await loadProgramPdfTheme();
  final doc = pw.Document(title: program.title, theme: resolvedTheme);

  final metaLines = <String>[
    _dateVenue(program, fmtDate),
    if (_has(program.band)) 'Band: ${program.band!.trim()}',
    if (_has(program.caller)) 'Caller: ${program.caller!.trim()}',
    if (_has(program.dancerLevel)) 'Level: ${program.dancerLevel!.trim()}',
  ].where((l) => l.isNotEmpty).toList();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Header(
          level: 0,
          child: pw.Text(
            program.title.trim(),
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
        ),
        for (final line in metaLines)
          pw.Text(line, style: const pw.TextStyle(fontSize: 12)),
        if (program.outputGrouped.isNotEmpty) pw.SizedBox(height: 12),
        ..._slotWidgets(program, titleFor, unknownDanceLabel),
        if (_has(program.notes)) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            'Notes',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            program.notes.trim(),
            style: const pw.TextStyle(fontSize: 12),
          ),
        ],
      ],
    ),
  );

  return doc.save();
}

List<pw.Widget> _slotWidgets(
  Program program,
  String? Function(String danceId) titleFor,
  String unknownDanceLabel,
) {
  final widgets = <pw.Widget>[];
  var n = 1;
  for (final group in program.outputGrouped) {
    widgets.add(
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Text(
          '$n. ${_slotLine(group.primary, titleFor, unknownDanceLabel)}',
          style: const pw.TextStyle(fontSize: 13),
        ),
      ),
    );
    for (final alt in group.alternates) {
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 20, top: 1, bottom: 1),
          child: pw.Text(
            'ALT: ${_slotLine(alt, titleFor, unknownDanceLabel)}',
            style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
          ),
        ),
      );
    }
    n++;
  }
  return widgets;
}

String _dateVenue(Program program, String Function(DateTime) fmtDate) {
  final parts = <String>[
    if (program.eventDate != null) fmtDate(program.eventDate!),
    if (_has(program.venue)) program.venue!.trim(),
  ];
  return parts.join(' · ');
}

/// Mirrors the plain-text slot-line format so the PDF and the emailable text
/// stay in lockstep.
String _slotLine(
  ProgramSlot slot,
  String? Function(String danceId) titleFor,
  String unknownDanceLabel,
) {
  final buffer = StringBuffer();

  if (slot.danceId != null) {
    final title = titleFor(slot.danceId!);
    buffer.write(_has(title) ? title!.trim() : unknownDanceLabel);
    if (_has(slot.text)) buffer.write(' — ${slot.text!.trim()}');
  } else {
    buffer.write(slot.text!.trim());
  }

  final meta = <String>[
    if (_has(slot.guestCaller)) 'guest: ${slot.guestCaller!.trim()}',
    if (slot.plannedMinutes != null) '${slot.plannedMinutes} min',
  ];
  if (meta.isNotEmpty) buffer.write(' (${meta.join('; ')})');

  if (slot.performedAt != null) buffer.write(' [performed]');

  return buffer.toString();
}

bool _has(String? value) => value != null && value.trim().isNotEmpty;

String _isoDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
