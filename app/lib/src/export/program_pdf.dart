import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/venue_label.dart';

/// Loads the bundled Unicode font (Roboto, SIL OFL-1.1) used for PDF export.
///
/// The built-in PDF standard fonts only cover Latin-1, so real dance titles
/// containing curly quotes, accents, or the `·`/`—` separators used in the set
/// list would render as blank glyphs. Bundling a Unicode TrueType font keeps
/// the app fully offline (no runtime font download) while rendering the same
/// characters as the emailable text. The theme is cached after first load.
///
/// The `pdf` package (unlike the Flutter engine used for on-screen text)
/// cannot resolve OpenType variable-font axes — it always renders whichever
/// master is baked in as a font's default, regardless of the requested
/// [pw.FontWeight]/[pw.FontStyle]. So PDF export loads **static**,
/// single-instance Regular/Bold/Italic TTFs instead of the variable font used
/// on-screen. These are pinned-axis instances of the exact same upstream
/// Roboto (same family/copyright/license, see `Roboto-OFL.txt`), generated
/// with `fonttools varLib.instancer`.
pw.ThemeData? _cachedTheme;

Future<pw.ThemeData> loadProgramPdfTheme() async {
  final cached = _cachedTheme;
  if (cached != null) return cached;
  // The three faces are independent assets, so kick off all three loads
  // before awaiting any of them, instead of paying three sequential I/O
  // round-trips on the first export. (Deliberately *not* `Future.wait` here:
  // under `flutter test`'s asset-loading shim, wrapping concurrent
  // `rootBundle.load` calls in `Future.wait` reproducibly returns an empty
  // result list even though each future resolves correctly on its own —
  // starting the loads eagerly and awaiting them individually sidesteps
  // that while still overlapping the I/O.)
  final regularFuture = rootBundle.load('assets/fonts/Roboto-Regular.ttf');
  final boldFuture = rootBundle.load('assets/fonts/Roboto-Bold.ttf');
  final italicFuture = rootBundle.load('assets/fonts/Roboto-Italic.ttf');
  return _cachedTheme = pw.ThemeData.withFont(
    base: pw.Font.ttf(await regularFuture),
    bold: pw.Font.ttf(await boldFuture),
    italic: pw.Font.ttf(await italicFuture),
  );
}

/// The program-matrix PDF's marker glyphs (★ ▸ ✓), cached after first load.
pw.Font? _cachedMatrixMarkerFont;

/// Loads the bundled marker-glyph fallback font used by the program-matrix
/// PDF (see `program_matrix_pdf.dart`, #633).
///
/// The bundled Roboto TTFs above don't include ★ (U+2605), ▸ (U+25B8), or ✓
/// (U+2713) — the `pdf` package silently drops glyphs missing from the active
/// font, so those matrix markers rendered blank in exported PDFs. Rather than
/// swap the documented marker glyphs (`docs/user/programs.md`,
/// `docs/ROADMAP.md` both describe the matrix legend by these exact
/// characters) for ones Roboto happens to have, this loads a single static
/// TTF — `ProgramMatrixMarkers-Regular.ttf`, a hand-subsetted (`fonttools
/// subset`) instance of Google's Noto Sans Symbols 2 (OFL 1.1) trimmed to
/// just those three glyphs — and registers it as a `pw.TextStyle
/// .fontFallback` only on the matrix's marker/legend text, so the `pdf`
/// package falls back to it per-glyph instead of dropping the character (see
/// `pdf`'s `Text._buildSpans` rune-fallback loop). Like the static Roboto
/// faces above, this is a fixed-instance TTF, never a variable font.
Future<pw.Font> loadProgramMatrixMarkerFont() async {
  final cached = _cachedMatrixMarkerFont;
  if (cached != null) return cached;
  final bytes = await rootBundle.load(
    'assets/fonts/ProgramMatrixMarkers-Regular.ttf',
  );
  return _cachedMatrixMarkerFont = pw.Font.ttf(bytes);
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
/// - [venuesById] maps venue ids to the loaded [Venue] records. When the
///   program links a resolvable venue ([Program.venueId]), its
///   [Venue.displayName] wins in the header date·venue line and a richer venue
///   block (address, contacts, sponsor/website, schedule/price) is rendered
///   below the metadata; otherwise the free-text [Program.venue] is used and no
///   block is drawn. Defaults to empty, preserving the pre-venue-entity output.
/// - [theme] supplies the Unicode font; when omitted it is loaded from the
///   bundled asset via [loadProgramPdfTheme].
Future<Uint8List> buildProgramPdf(
  Program program, {
  required String? Function(String danceId) titleFor,
  Map<String, Venue> venuesById = const {},
  String Function(DateTime date)? formatDate,
  ProgramExportLabels labels = const ProgramExportLabels(),
  pw.ThemeData? theme,
}) async {
  final fmtDate = formatDate ?? _isoDate;
  final resolvedTheme = theme ?? await loadProgramPdfTheme();
  final doc = pw.Document(title: program.title, theme: resolvedTheme);

  final linkedVenue = program.venueId != null
      ? venuesById[program.venueId!]
      : null;

  final metaLines = <String>[
    _dateVenue(program, fmtDate, venuesById),
    if (_has(program.band)) '${labels.band}: ${program.band!.trim()}',
    if (_has(program.caller)) '${labels.caller}: ${program.caller!.trim()}',
    if (_has(program.dancerLevel))
      '${labels.level}: ${program.dancerLevel!.trim()}',
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
        if (linkedVenue != null) ..._venueBlock(linkedVenue, labels),
        if (program.outputGrouped.isNotEmpty) pw.SizedBox(height: 12),
        ..._slotWidgets(program, titleFor, labels),
        if (_has(program.notes)) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            labels.notes,
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
  ProgramExportLabels labels,
) {
  final widgets = <pw.Widget>[];
  var n = 1;
  for (final group in program.outputGrouped) {
    widgets.add(
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Text(
          '$n. ${_slotLine(group.primary, titleFor, labels)}',
          style: const pw.TextStyle(fontSize: 13),
        ),
      ),
    );
    for (final alt in group.alternates) {
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 20, top: 1, bottom: 1),
          child: pw.Text(
            '${labels.alt}: ${_slotLine(alt, titleFor, labels)}',
            style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
          ),
        ),
      );
    }
    n++;
  }
  return widgets;
}

String _dateVenue(
  Program program,
  String Function(DateTime) fmtDate,
  Map<String, Venue> venuesById,
) {
  final parts = <String>[
    if (program.eventDate != null) fmtDate(program.eventDate!),
    ?resolveVenueLabel(program, venuesById),
  ];
  return parts.join(' · ');
}

/// Renders the richer venue detail block shown when a program links a
/// resolvable [Venue]. Each line/field is emitted only when present (relying on
/// the model's trim/empty→null normalization) so an unset field never shows a
/// placeholder. Values are drawn as plain PDF text — no markup interpolation —
/// so stored venue text can't inject layout.
List<pw.Widget> _venueBlock(Venue venue, ProgramExportLabels labels) {
  final cityLine = venueLocalityLine(venue);

  final detail = <String>[
    if (_has(venue.eventName)) venue.eventName!,
    if (_has(venue.time)) '${labels.time}: ${venue.time}',
    if (_has(venue.genericSchedule))
      '${labels.schedule}: ${venue.genericSchedule}',
    if (_has(venue.price)) '${labels.price}: ${venue.price}',
    if (_has(venue.sponsor)) '${labels.sponsor}: ${venue.sponsor}',
    if (_has(venue.website)) venue.website!,
  ];

  final address = <String>[
    if (_has(venue.address1)) venue.address1!,
    if (_has(venue.address2)) venue.address2!,
    if (cityLine.isNotEmpty) cityLine,
    if (_has(venue.country)) venue.country!,
  ];

  final contacts = <String>[
    _contactLine(venue.contact1Name, venue.contact1Phone, venue.contact1Email),
    _contactLine(venue.contact2Name, venue.contact2Phone, venue.contact2Email),
  ].where((l) => l.isNotEmpty).toList();

  final lines = [...address, ...detail, ...contacts];
  if (lines.isEmpty) return const [];

  return [
    pw.SizedBox(height: 8),
    pw.Text(
      labels.venue,
      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 2),
    for (final line in lines)
      pw.Text(line, style: const pw.TextStyle(fontSize: 11)),
  ];
}

/// Joins a US-style ZIP and its +4 add-on ("12345-6789"); returns the bare ZIP
/// when there is no add-on, or `null` when neither is set.
String? _postal(String? postalCode, String? plus4) {
  final zip = postalCode?.trim();
  final add = plus4?.trim();
  if (zip == null || zip.isEmpty) return null;
  return (add == null || add.isEmpty) ? zip : '$zip-$add';
}

/// Formats a venue's locality line as "City, ST 05602-1234": the city and
/// state/province are comma-joined, and the postal code follows separated by a
/// SPACE (US convention), never a comma. Any absent part is dropped, so a
/// city-only venue is just "City" and a postal-only one is just the ZIP.
/// Returns an empty string when none of the parts are present.
@visibleForTesting
String venueLocalityLine(Venue venue) {
  final cityState = [
    venue.city,
    venue.stateProv,
  ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
  return [
    if (cityState.isNotEmpty) cityState,
    ?_postal(venue.postalCode, venue.plus4),
  ].join(' ');
}

/// Renders one contact as "name · phone · email", skipping empty parts; empty
/// when the contact has no fields at all.
String _contactLine(String? name, String? phone, String? email) => [
  if (_has(name)) name!.trim(),
  if (_has(phone)) phone!.trim(),
  if (_has(email)) email!.trim(),
].join(' · ');

/// Mirrors the plain-text slot-line format so the PDF and the emailable text
/// stay in lockstep.
String _slotLine(
  ProgramSlot slot,
  String? Function(String danceId) titleFor,
  ProgramExportLabels labels,
) {
  final buffer = StringBuffer();

  if (slot.danceId != null) {
    final title = titleFor(slot.danceId!);
    buffer.write(_has(title) ? title!.trim() : labels.unknownDance);
    if (_has(slot.text)) buffer.write(' — ${slot.text!.trim()}');
  } else {
    buffer.write(slot.text!.trim());
  }

  final meta = <String>[
    if (_has(slot.guestCaller)) '${labels.guest}: ${slot.guestCaller!.trim()}',
    if (slot.plannedMinutes != null) labels.minutes(slot.plannedMinutes!),
  ];
  if (meta.isNotEmpty) buffer.write(' (${meta.join('; ')})');

  if (slot.performedAt != null) buffer.write(' [${labels.performed}]');

  return buffer.toString();
}

bool _has(String? value) => value != null && value.trim().isNotEmpty;

String _isoDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
