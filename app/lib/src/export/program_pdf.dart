import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'share_sanitization.dart';
import 'program_figure_widgets.dart';

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
///
/// Roboto has no CJK glyphs, and the `pdf` package draws a placeholder box
/// for any rune no font covers (printing a notice only inside an `assert`, so
/// release builds are silent). The theme therefore carries a
/// [pw.TextStyle.fontFallback] of `NotoSansJP-Regular-Subset.ttf` — a static
/// (`fvar`-free) `fonttools subset` of Noto Sans JP (SIL OFL 1.1) holding
/// Hiragana, Katakana, CJK/fullwidth punctuation and forms, and the JIS X 0208
/// level 1 kanji (plus the kanji the app's own Japanese strings use). It is
/// needed in *every* UI language, since a Japanese program or dance title
/// prints in an English export too. Kanji outside the subset (JIS level 2,
/// Simplified Chinese, Hangul) still draw as boxes. The fallback has no bold
/// face, so CJK text inside a bold heading is drawn at regular weight.
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
  final cjkFuture = rootBundle.load(
    'assets/fonts/NotoSansJP-Regular-Subset.ttf',
  );
  return _cachedTheme = pw.ThemeData.withFont(
    base: pw.Font.ttf(await regularFuture),
    bold: pw.Font.ttf(await boldFuture),
    italic: pw.Font.ttf(await italicFuture),
    fontFallback: [pw.Font.ttf(await cjkFuture)],
  );
}

/// The program-matrix PDF's marker glyphs (★ ▸ ✓), cached after first load.
pw.Font? _cachedMatrixMarkerFont;

/// Per-dance display labels for a figure-appendix card (issue #1434) — the
/// same four strings `program_export_menu.dart` already resolves for the
/// text-path card (`_plainTextWithFigures`): resolved author *names* (never
/// a [Choreographer] record), and the app's human-readable facet labels.
typedef DanceCardLabels = ({
  List<String> authorNames,
  String formationLabel,
  String? levelLabel,
  String statusLabel,
});

/// One figure-appendix entry: the dance, whether it is an alternate, and its
/// laid-out-ready [DanceCardContent] (`null` when the caller supplied no
/// `cardLabelsFor`, i.e. title + figures only).
typedef ProgramAppendixCard = ({
  Dance dance,
  bool isAlternate,
  DanceCardContent? content,
});

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
///   block (sponsor/website, schedule/price, and the contact lines the user
///   consented to) is rendered below the metadata; otherwise the free-text
///   [Program.venue] is used and no block is drawn. The builder runs the venue
///   through [sanitizeVenueForShare] itself: the postal address is never
///   printed, in the block or the header label. Defaults to empty, preserving
///   the pre-venue-entity output.
/// - [includeVenueContact] names the venue contact fields the user opted in to
///   print (empty by default: none). Same contract as
///   [buildProgramShareBundle].
/// - [theme] supplies the Unicode font; when omitted it is loaded from the
///   bundled asset via [loadProgramPdfTheme].
/// - [appendDances] — when non-null and non-empty, appends a figure appendix
///   after the set list: one compact dance card per entry using
///   [buildFigureWidgets] (the same layout as the single-dance PDF but at a
///   smaller scale and without forced page breaks — [pw.MultiPage] paginates
///   naturally). Alternates in the list are labelled with [labels.alternate].
///   Requires [dialect] and [renderer] when provided; both default sensibly
///   ([dialect] falls back to [Dialect.larksRobins], [renderer] to a
///   fresh [FigureRenderer] using [contraTaxonomy]).
/// - [authorNamesFor] resolves a slot's `danceId` to its already-resolved
///   author *names* for the numbered set-list line (issue #1434) — same
///   contract as `programToPlainText`'s parameter of the same name. `null`
///   (the default) omits the suffix, preserving the pre-#1434 slot-line
///   format.
/// - [cardLabelsFor] resolves an appendix dance to the labels its card needs
///   (issue #1434). `null` (the default) preserves the pre-#1434 appendix
///   content exactly (title + figures only); when supplied, each appendix
///   card is enriched to the same field set as [buildDancePdf] — a core
///   [DanceCardContent] built with [fields] (defaults to
///   [DanceShareField.allExceptTunes]) and laid out here, so the two builders
///   can't drift.
/// - [pageFormat] is the page size; defaults to A4.
Future<Uint8List> buildProgramPdf(
  Program program, {
  required String? Function(String danceId) titleFor,
  Map<String, Venue> venuesById = const {},
  String Function(DateTime date)? formatDate,
  ProgramExportLabels labels = const ProgramExportLabels(),
  pw.ThemeData? theme,
  List<({Dance dance, bool isAlternate})>? appendDances,
  DanceExportLabels? danceLabels,
  Dialect? dialect,
  FigureRenderer? renderer,
  bool canonicalizeDiscouragedTerms = false,
  List<String> Function(String danceId)? authorNamesFor,
  DanceCardLabels Function(Dance dance)? cardLabelsFor,
  Set<DanceShareField> fields = DanceShareField.allExceptTunes,
  PdfPageFormat pageFormat = PdfPageFormat.a4,
  Set<VenueContactField> includeVenueContact = const {},
}) async {
  final resolvedTheme = theme ?? await loadProgramPdfTheme();
  final doc = pw.Document(title: program.title, theme: resolvedTheme);
  final fig = renderer ?? FigureRenderer(contraTaxonomy);
  final resolvedDialect = dialect ?? Dialect.larksRobins;

  final venueText = programPdfVenueText(
    program,
    venuesById,
    labels,
    includeVenueContact: includeVenueContact,
  );

  final metaLines = programHeaderLines(
    program,
    venueNameFor: (_) => venueText.headerLabel,
    formatDate: formatDate,
    labels: labels,
    renderer: fig,
    dialect: resolvedDialect,
    canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
  );

  final resolvedDanceLabels = danceLabels ?? const DanceExportLabels();

  // `cardLabelsFor == null` keeps the pre-#1434 appendix (title + figures
  // only): no content is built, so no gated block can be laid out.
  final appendCards = <ProgramAppendixCard>[
    for (final entry
        in appendDances ?? const <({Dance dance, bool isAlternate})>[])
      (
        dance: entry.dance,
        isAlternate: entry.isAlternate,
        content: switch (cardLabelsFor?.call(entry.dance)) {
          final card? => DanceCardContent.build(
            entry.dance,
            dialect: resolvedDialect,
            authorNames: card.authorNames,
            formationLabel: card.formationLabel,
            levelLabel: card.levelLabel,
            statusLabel: card.statusLabel,
            renderer: fig,
            labels: resolvedDanceLabels,
            canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
            fields: fields,
          ),
          null => null,
        },
      ),
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: pageFormat,
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
        ..._venueBlock(venueText.blockLines, labels),
        if (program.outputGrouped.isNotEmpty) pw.SizedBox(height: 12),
        ..._slotWidgets(
          program,
          titleFor,
          labels,
          renderer: fig,
          dialect: resolvedDialect,
          canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
          authorNamesFor: authorNamesFor,
        ),
        if (_has(program.notes)) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            labels.notes,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            canonicalizeDiscouragedTerms
                ? fig.renderFreeTextWithCanonicalDiscouragedTerms(
                    program.notes.trim(),
                    resolvedDialect,
                  )
                : program.notes.trim(),
            style: const pw.TextStyle(fontSize: 12),
            overflow: pw.TextOverflow.span,
          ),
        ],
        if (appendCards.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Text(
            labels.figures,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          ...programAppendixWidgets(
            appendCards,
            fig,
            resolvedDialect,
            resolvedDanceLabels,
            labels,
            canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
          ),
        ],
      ],
    ),
  );

  return doc.save();
}

/// Renders one compact dance-card block per entry in the list for the figure
/// appendix. Dance title is a bold sub-header; alternates are prefixed with
/// [labels.alternate]. No forced page breaks — [pw.MultiPage] handles
/// pagination naturally.
///
/// Each entry's `content` is the field-gated card added by issue #1434 (author
/// line, formation/level/mixer/status/phrase, calling notes, walkthrough,
/// tunes), the same core [DanceCardContent] [buildDancePdf] lays out. A `null`
/// `content` (no `cardLabelsFor`) preserves the pre-#1434 appendix exactly:
/// title + figures only, regardless of the selected fields.
@visibleForTesting
List<pw.Widget> programAppendixWidgets(
  List<ProgramAppendixCard> cards,
  FigureRenderer renderer,
  Dialect dialect,
  DanceExportLabels danceLabels,
  ProgramExportLabels labels, {
  bool canonicalizeDiscouragedTerms = false,
}) {
  final widgets = <pw.Widget>[];
  for (final entry in cards) {
    final dance = entry.dance;
    final content = entry.content;
    final danceFigures = switch (dance.figuresSource) {
      DecodedFigures(:final figures) => figures,
      UnreadableFigures() => const <Figure>[],
    };
    if (danceFigures.isEmpty) continue;
    final titlePrefix = entry.isAlternate ? '${labels.alternate}: ' : '';
    widgets.add(pw.SizedBox(height: 10));
    widgets.add(
      pw.Text(
        '$titlePrefix${dance.title.trim()}',
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
      ),
    );
    if (content != null) {
      if (content.authorNames.isNotEmpty) {
        widgets.add(
          pw.Text(
            content.authorNames.join(', '),
            style: const pw.TextStyle(fontSize: 12),
          ),
        );
      }
      for (final line in content.metaLines) {
        widgets.add(pw.Text(line, style: const pw.TextStyle(fontSize: 11)));
      }
    }
    widgets.addAll(
      buildFigureWidgets(
        dance,
        renderer,
        dialect,
        danceLabels,
        canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
      ),
    );
    if (content != null) {
      if (content.callingNotes case final notes?) {
        widgets.add(pw.SizedBox(height: 4));
        widgets.add(_appendixHeading(danceLabels.callingNotes));
        widgets.add(
          pw.Text(
            notes,
            style: const pw.TextStyle(fontSize: 11),
            overflow: pw.TextOverflow.span,
          ),
        );
      }
      if (content.walkthrough case final walkthrough?) {
        widgets.add(pw.SizedBox(height: 4));
        widgets.add(_appendixHeading(danceLabels.walkthrough));
        widgets.add(
          pw.Text(
            walkthrough,
            style: const pw.TextStyle(fontSize: 11),
            overflow: pw.TextOverflow.span,
          ),
        );
      }
      if (content.tuneNames.isNotEmpty) {
        widgets.add(pw.SizedBox(height: 4));
        widgets.add(_appendixHeading(danceLabels.tunes));
        widgets.add(
          pw.Text(
            content.tuneNames.join(', '),
            style: const pw.TextStyle(fontSize: 11),
          ),
        );
      }
    }
  }
  return widgets;
}

pw.Widget _appendixHeading(String text) => pw.Text(
  text,
  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
);

List<pw.Widget> _slotWidgets(
  Program program,
  String? Function(String danceId) titleFor,
  ProgramExportLabels labels, {
  required FigureRenderer renderer,
  required Dialect dialect,
  bool canonicalizeDiscouragedTerms = false,
  List<String> Function(String danceId)? authorNamesFor,
}) {
  final widgets = <pw.Widget>[];
  var n = 1;
  for (final group in program.outputGrouped) {
    final primary = programSlotLine(
      group.primary,
      titleFor,
      labels,
      renderer: renderer,
      dialect: dialect,
      canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
      authorNamesFor: authorNamesFor,
    );
    // Slot lines are direct `pw.Text(overflow: span)` children, spaced with
    // `SizedBox`es: `pw.Padding` is not a `SpanningWidget`, so a note longer
    // than a page inside one would make `MultiPage` throw.
    widgets.add(pw.SizedBox(height: 2));
    widgets.add(
      pw.Text(
        '$n. $primary',
        style: const pw.TextStyle(fontSize: 13),
        overflow: pw.TextOverflow.span,
      ),
    );
    widgets.add(pw.SizedBox(height: 2));
    for (final alt in group.alternates) {
      final alternate = programSlotLine(
        alt,
        titleFor,
        labels,
        renderer: renderer,
        dialect: dialect,
        canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
        authorNamesFor: authorNamesFor,
      );
      widgets.add(pw.SizedBox(height: 1));
      widgets.add(
        pw.Text(
          '${labels.alt}: $alternate',
          style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
          overflow: pw.TextOverflow.span,
        ),
      );
      widgets.add(pw.SizedBox(height: 1));
    }
    n++;
  }
  return widgets;
}

/// The venue text [buildProgramPdf] prints for [program]: the header
/// date/venue label and the venue detail block's lines (empty when the program
/// links no resolvable venue).
///
/// The venue goes through [sanitizeVenueForShare] here, so the postal address
/// is never printed (in the block or in the header label) and a contact field
/// is printed only when it is in [includeVenueContact]. Callers pass the raw
/// venue; they need no redaction of their own.
///
/// Extracted so the redaction is testable without decoding PDF bytes; it is the
/// single path [buildProgramPdf] draws from.
@visibleForTesting
({String? headerLabel, List<String> blockLines}) programPdfVenueText(
  Program program,
  Map<String, Venue> venuesById,
  ProgramExportLabels labels, {
  Set<VenueContactField> includeVenueContact = const {},
}) {
  final linkedVenue = program.venueId != null
      ? venuesById[program.venueId!]
      : null;
  return (
    headerLabel: resolveSanitizedVenueLabelParts(
      program.venueId,
      program.venue,
      venuesById,
    ),
    blockLines: linkedVenue == null
        ? const []
        : _venueLines(
            sanitizeVenueForShare(linkedVenue, include: includeVenueContact),
            labels,
          ),
  );
}

/// The venue detail block's text lines for an already-sanitised [venue]: the
/// descriptive fields, then the contact lines that survived the consent
/// choice. Each line/field is emitted only when present (relying on the model's
/// trim/empty→null normalization) so an unset field never shows a placeholder.
List<String> _venueLines(Venue venue, ProgramExportLabels labels) {
  final detail = <String>[
    if (_has(venue.eventName)) venue.eventName!,
    if (_has(venue.time)) '${labels.time}: ${venue.time}',
    if (_has(venue.genericSchedule))
      '${labels.schedule}: ${venue.genericSchedule}',
    if (_has(venue.price)) '${labels.price}: ${venue.price}',
    if (_has(venue.sponsor)) '${labels.sponsor}: ${venue.sponsor}',
    if (_has(venue.website)) venue.website!,
  ];

  final contacts = <String>[
    _contactLine(venue.contact1Name, venue.contact1Phone, venue.contact1Email),
    _contactLine(venue.contact2Name, venue.contact2Phone, venue.contact2Email),
  ].where((l) => l.isNotEmpty).toList();

  return [...detail, ...contacts];
}

/// Renders the venue detail block for [lines] (see [programPdfVenueText]).
/// Values are drawn as plain PDF text — no markup interpolation — so stored
/// venue text can't inject layout.
List<pw.Widget> _venueBlock(List<String> lines, ProgramExportLabels labels) {
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

bool _has(String? value) => value != null && value.trim().isNotEmpty;
