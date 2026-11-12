import 'dart:math' as math;
import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart' show Matrix4;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'calling_card_layout.dart';
import 'program_pdf.dart';

/// One card to print: a dance, the display strings the app resolved for it,
/// and its place in a printed program.
class CallingCardEntry {
  const CallingCardEntry({
    required this.dance,
    required this.labels,
    this.number = '',
  });

  final Dance dance;

  /// The same author names and facet labels the other dance exports use
  /// (resolved names only, never a [Choreographer] record).
  final DanceCardLabels labels;

  /// What the `number` block prints: the dance's place in the program ("3",
  /// or the localized "Alternate"), or empty for a single dance.
  final String number;
}

/// What happened when a document was laid out. Filled while the PDF is
/// saved, so read it after [buildCallingCardsPdf] returns.
class CallingCardFitReport {
  /// The scale each card was printed at, in order: 1 when it fit as written.
  final List<double> scales = [];

  /// The titles of the cards that did not fit even at
  /// [kCallingCardMinScale], and so were cut off at the bottom.
  final List<String> overflowed = [];

  /// Printing on sheets: whether the cards were larger than the paper, and so
  /// were printed one to a page, scaled down to fit.
  bool cardsShrunkToSheet = false;

  void _clear() {
    scales.clear();
    overflowed.clear();
    cardsShrunkToSheet = false;
  }
}

/// How far a card's text may shrink to fit, as a fraction of the sizes the
/// layout asks for. Below half size a 10-point figure line is 5 points, which
/// no one can call from.
const double kCallingCardMinScale = 0.5;

/// Builds a PDF of calling cards, one card per page, each page the card's own
/// [size] (not the print dialog's paper: a card printer is loaded with cards).
///
/// Each card is laid out by [layout]. What a block may show is also gated by
/// [fields], the Settings › Defaults dance-field picker that every other dance
/// export honours, so a field turned off there stays off a card even when the
/// layout names it. Notes, walkthrough and hook are rendered in [dialect]
/// through the shared [DanceCardContent], and figures through [renderer], as
/// in the dance PDF.
///
/// When a card's content is taller than the card, the whole card shrinks
/// evenly until it fits, down to [kCallingCardMinScale]; past that it is cut
/// off at the bottom and marked with a small corner triangle. [report], when
/// given, records each card's scale and the cards that were cut off.
///
/// With [sheet], the cards are printed several to a page of that paper
/// instead, edge to edge in a centred grid with marks to cut along; see
/// [callingCardSheetGrid].
///
/// [programTitle] is what the `program` block prints. [theme] supplies the
/// Unicode font; when omitted it is loaded from the bundled asset.
Future<Uint8List> buildCallingCardsPdf(
  List<CallingCardEntry> entries, {
  required CallingCardLayout layout,
  required CallingCardSize size,
  required Dialect dialect,
  required Set<DanceShareField> fields,
  FigureRenderer? renderer,
  DanceExportLabels labels = const DanceExportLabels(),
  String programTitle = '',
  String? documentTitle,
  bool canonicalizeDiscouragedTerms = false,
  pw.ThemeData? theme,
  CallingCardFitReport? report,
  PdfPageFormat? sheet,
}) async {
  final fig = renderer ?? FigureRenderer(contraTaxonomy);
  final resolvedTheme = theme ?? _withBoldItalic(await loadProgramPdfTheme());
  report?._clear();
  final doc = pw.Document(
    title:
        documentTitle ??
        (entries.length == 1 ? entries.single.dance.title : programTitle),
    theme: resolvedTheme,
  );
  final width = size.widthPoints;
  final height = size.heightPoints;
  // A margin can never eat more than a quarter of the short side.
  final margin = layout.margin.clamp(
    0.0,
    (width < height ? width : height) / 4,
  );

  final cards = <pw.Widget>[];
  for (final entry in entries) {
    final content = DanceCardContent.build(
      entry.dance,
      dialect: dialect,
      authorNames: entry.labels.authorNames,
      formationLabel: entry.labels.formationLabel,
      levelLabel: entry.labels.levelLabel,
      statusLabel: entry.labels.statusLabel,
      renderer: fig,
      labels: labels,
      canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
      fields: fields,
      sourceLines: entry.labels.sourceLines,
    );
    final card = _CardBuilder(
      entry: entry,
      content: content,
      renderer: fig,
      dialect: dialect,
      labels: labels,
      programTitle: programTitle,
      canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
    );
    cards.add(
      pw.SizedBox(
        width: width,
        height: height,
        child: pw.Padding(
          padding: pw.EdgeInsets.all(margin),
          child: _ShrinkToFit(
            minScale: kCallingCardMinScale,
            onLaidOut: (scale, overflowed) {
              report?.scales.add(scale);
              if (overflowed) report?.overflowed.add(content.title);
            },
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [for (final row in layout.rows) ?card.row(row)],
            ),
          ),
        ),
      ),
    );
  }

  if (sheet == null) {
    for (final card in cards) {
      doc.addPage(
        pw.Page(pageFormat: PdfPageFormat(width, height), build: (_) => card),
      );
    }
  } else {
    _addSheets(doc, cards, size, sheet, report);
  }
  return doc.save();
}

/// The space a sheet keeps around its grid of cards when it can: a quarter
/// inch, inside what most printers reach, with room for the cut marks.
const double kCallingCardSheetMargin = 18;

/// How much a paper size reported by a print dialog may fall short of a
/// grid's size and still take it. Dialogs round: Windows reports A4 as
/// 595.2 pt and macOS as 595 pt, against its true 595.28, and a grid of A6
/// or A7 cards needs every bit of it.
const double kCallingCardSheetTolerance = 1;

/// How cards tile onto a page of paper: [columns] × [rows] of them, each
/// [rotated] a quarter turn or not, inside [margin] points of the paper's
/// edge.
typedef CallingCardSheetGrid = ({
  int columns,
  int rows,
  bool rotated,
  double margin,
});

/// The arrangement that fits the most cards of [card]'s size onto [paper].
///
/// It tries four: inside [kCallingCardSheetMargin], upright then turned a
/// quarter turn, and then filling the paper to its edge, upright then
/// turned. It keeps the first that fits the most, so on a tie the margin wins
/// over filling the page, and upright over turned. Filling the page is what
/// lets sizes made to divide a sheet, such as A6 on A4, print four to a page;
/// each card's own margin keeps its text clear of the edge a printer cannot
/// reach. Zero cards when a card is larger than the paper either way. Paper
/// may fall [kCallingCardSheetTolerance] short of a grid and still take it.
CallingCardSheetGrid callingCardSheetGrid(
  PdfPageFormat paper,
  CallingCardSize card,
) {
  int fit(double room, double side) =>
      ((room + kCallingCardSheetTolerance) / side).floor();
  CallingCardSheetGrid? best;
  for (final margin in const [kCallingCardSheetMargin, 0.0]) {
    final across = paper.width - 2 * margin;
    final down = paper.height - 2 * margin;
    for (final rotated in const [false, true]) {
      final w = rotated ? card.heightPoints : card.widthPoints;
      final h = rotated ? card.widthPoints : card.heightPoints;
      final grid = (
        columns: fit(across, w),
        rows: fit(down, h),
        rotated: rotated,
        margin: margin,
      );
      if (best == null || grid.columns * grid.rows > best.columns * best.rows) {
        best = grid;
      }
    }
  }
  return best!;
}

/// One straight cut mark, from ([x1], [y1]) to ([x2], [y2]) in points from
/// the page's top-left corner.
typedef CallingCardCutMark = ({double x1, double y1, double x2, double y2});

/// Where a sheet's cut marks go: a short mark in line with every edge of the
/// grid's cards ([columns] × [rows] cells of [cellWidth] × [cellHeight],
/// whose top-left corner is at ([left], [top]) on a page of [pageWidth] ×
/// [pageHeight]).
///
/// Every mark lies on a cut line, so it never crosses a card's content,
/// which keeps its card's margin away from every edge. No mark comes within
/// [printableInset] of the paper's edge, the strip the printer is taken not
/// to reach. Where the paper leaves room for a full-length mark between that
/// strip and the grid, the marks sit there, stopping [_markGap] short of the
/// cards so a slightly crooked cut leaves no line on a card. Otherwise they
/// run inward from the edge of the printable area, along the cut lines
/// between the cards. A cut line that itself lies within [printableInset] of
/// the paper's edge gets no mark: the paper's edge is that cut.
List<CallingCardCutMark> callingCardCutMarks({
  required double pageWidth,
  required double pageHeight,
  required double left,
  required double top,
  required double cellWidth,
  required double cellHeight,
  required int columns,
  required int rows,
  required double printableInset,
}) {
  final marks = <CallingCardCutMark>[];
  // The span, measured in from one paper edge, that a mark may cover on the
  // [offset] side of the grid.
  (double, double) span(double offset) {
    final outsideTo = offset - _markGap;
    if (outsideTo - printableInset >= _markLength) {
      return (outsideTo - _markLength, outsideTo);
    }
    final insideFrom = math.max(printableInset, offset);
    return (insideFrom, insideFrom + _markLength);
  }

  final gridRight = left + columns * cellWidth;
  final gridBottom = top + rows * cellHeight;
  final above = span(top);
  final below = span(pageHeight - gridBottom);
  // A cut line within the unprintable strip is the paper's own edge.
  bool printable(double at, double extent) =>
      at >= printableInset && at <= extent - printableInset;
  for (var c = 0; c <= columns; c++) {
    final x = left + c * cellWidth;
    if (!printable(x, pageWidth)) continue;
    final (a1, b1) = above;
    final (a2, b2) = below;
    marks
      ..add((x1: x, y1: a1, x2: x, y2: b1))
      ..add((x1: x, y1: pageHeight - a2, x2: x, y2: pageHeight - b2));
  }
  final before = span(left);
  final after = span(pageWidth - gridRight);
  for (var r = 0; r <= rows; r++) {
    final y = top + r * cellHeight;
    if (!printable(y, pageHeight)) continue;
    final (a1, b1) = before;
    final (a2, b2) = after;
    marks
      ..add((x1: a1, y1: y, x2: b1, y2: y))
      ..add((x1: pageWidth - a2, y1: y, x2: pageWidth - b2, y2: y));
  }
  return marks;
}

const double _markGap = 3;
const double _markLength = 11;

/// Lays [cards] out on pages of [paper]: a grid per page with cut marks, or,
/// for cards larger than the paper, one per page scaled to fit, turned if
/// that prints them larger.
void _addSheets(
  pw.Document doc,
  List<pw.Widget> cards,
  CallingCardSize size,
  PdfPageFormat paper,
  CallingCardFitReport? report,
) {
  // The grid is placed on the whole sheet; only the marks keep clear of the
  // edge. How far is a guess: the dialog's paper reports margins, which on
  // most platforms are the printer's unprintable strip but on macOS are the
  // page setup's, and pdf's stock A4 and Letter carry 2 cm. The largest of
  // them, capped at a quarter inch, keeps marks off the strip most printers
  // cannot reach without pushing them off the sheet.
  final page = PdfPageFormat(paper.width, paper.height);
  final printableInset = math.min(
    [
      paper.marginLeft,
      paper.marginRight,
      paper.marginTop,
      paper.marginBottom,
    ].reduce(math.max),
    kCallingCardSheetMargin,
  );
  final grid = callingCardSheetGrid(page, size);
  final perPage = grid.columns * grid.rows;
  if (perPage == 0) {
    report?.cardsShrunkToSheet = true;
    final across = page.width - 2 * kCallingCardSheetMargin;
    final down = page.height - 2 * kCallingCardSheetMargin;
    final upright = math.min(
      across / size.widthPoints,
      down / size.heightPoints,
    );
    final turned = math.min(
      across / size.heightPoints,
      down / size.widthPoints,
    );
    for (final card in cards) {
      doc.addPage(
        pw.Page(
          pageFormat: page.copyWith(
            marginLeft: kCallingCardSheetMargin,
            marginRight: kCallingCardSheetMargin,
            marginTop: kCallingCardSheetMargin,
            marginBottom: kCallingCardSheetMargin,
          ),
          build: (_) => pw.Center(
            child: pw.FittedBox(
              child: turned > upright
                  ? pw.Transform.rotateBox(angle: math.pi / 2, child: card)
                  : card,
            ),
          ),
        ),
      );
    }
    return;
  }
  final cellWidth = grid.rotated ? size.heightPoints : size.widthPoints;
  final cellHeight = grid.rotated ? size.widthPoints : size.heightPoints;
  final left = (page.width - grid.columns * cellWidth) / 2;
  final top = (page.height - grid.rows * cellHeight) / 2;
  for (var first = 0; first < cards.length; first += perPage) {
    final onPage = cards.skip(first).take(perPage).toList();
    // Only the rows this page fills get marks.
    final marks = callingCardCutMarks(
      pageWidth: page.width,
      pageHeight: page.height,
      left: left,
      top: top,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
      columns: grid.columns,
      rows: (onPage.length / grid.columns).ceil(),
      printableInset: printableInset,
    );
    doc.addPage(
      pw.Page(
        pageFormat: page,
        build: (_) => pw.Stack(
          children: [
            for (final (i, card) in onPage.indexed)
              pw.Positioned(
                left: left + (i % grid.columns) * cellWidth,
                top: top + (i ~/ grid.columns) * cellHeight,
                child: grid.rotated
                    ? pw.Transform.rotateBox(angle: math.pi / 2, child: card)
                    : card,
              ),
            // Over the cards: a mark may fall inside a card's blank margin.
            pw.Positioned.fill(
              child: pw.CustomPaint(
                painter: (canvas, area) {
                  canvas
                    ..setStrokeColor(PdfColors.grey700)
                    ..setLineWidth(0.5);
                  // The canvas's y runs up from the bottom of the page.
                  for (final m in marks) {
                    canvas
                      ..moveTo(m.x1, area.y - m.y1)
                      ..lineTo(m.x2, area.y - m.y2);
                  }
                  canvas.strokePath();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [theme] with its bold face standing in for bold italic.
///
/// The bundled theme has no bold-italic face, and the `pdf` package then
/// falls back to the standard Helvetica-BoldOblique, which has no glyphs
/// beyond Latin-1. A layout may ask for both (`notes italic` keeps its bold
/// label), so here that prints in the bundled bold — upright, but with every
/// glyph the bold face has, Japanese fallback included.
pw.ThemeData _withBoldItalic(pw.ThemeData theme) => theme.copyWith(
  defaultTextStyle: theme.defaultTextStyle.copyWith(
    fontBoldItalic: theme.defaultTextStyle.fontBold,
  ),
);

/// Lays out one dance's blocks.
class _CardBuilder {
  _CardBuilder({
    required this.entry,
    required this.content,
    required this.renderer,
    required this.dialect,
    required this.labels,
    required this.programTitle,
    required this.canonicalizeDiscouragedTerms,
  });

  final CallingCardEntry entry;
  final DanceCardContent content;
  final FigureRenderer renderer;
  final Dialect dialect;
  final DanceExportLabels labels;
  final String programTitle;
  final bool canonicalizeDiscouragedTerms;

  static const _ink = PdfColor.fromInt(0xff1d2528);
  static const _muted = PdfColor.fromInt(0xff4d6470);
  static const _divider = PdfColor.fromInt(0xff7aa0b8);
  static const _ruleDefault = PdfColor.fromInt(0xff1d2528);

  /// A row's widget, or `null` when none of its blocks has anything to show
  /// (a level-only row for a dance with no level), so it takes no space.
  pw.Widget? row(List<CallingCardBlock> blocks) {
    final built = [for (final b in blocks) (b, block(b))];
    if (built.every((e) => e.$2 == null)) return null;
    if (built.length == 1) return built.single.$2;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final (b, w) in built)
          pw.Expanded(flex: b.width, child: w ?? pw.SizedBox()),
      ],
    );
  }

  /// One block's widget, or `null` when it has nothing to show.
  pw.Widget? block(CallingCardBlock b) => switch (b.kind) {
    CallingCardBlockKind.rule => pw.Container(
      height: b.thickness,
      margin: const pw.EdgeInsets.symmetric(vertical: 2),
      color: b.color == null ? _ruleDefault : _color(b.color!),
    ),
    CallingCardBlockKind.space => pw.SizedBox(height: b.space),
    // `card` never reaches a row: the parser takes it as the card's margin.
    CallingCardBlockKind.card => null,
    CallingCardBlockKind.figures => _figures(b),
    _ => _text(b, _textFor(b.kind, b), _defaultLabel(b.kind)),
  };

  String _textFor(CallingCardBlockKind kind, CallingCardBlock b) =>
      switch (kind) {
        CallingCardBlockKind.title => content.title,
        CallingCardBlockKind.authors => content.authorNames.join(', '),
        CallingCardBlockKind.formation => content.formation ?? '',
        CallingCardBlockKind.level => content.level ?? '',
        CallingCardBlockKind.meta => content.metaLines.join('  ·  '),
        CallingCardBlockKind.notes => content.callingNotes ?? '',
        CallingCardBlockKind.walkthrough => content.walkthrough ?? '',
        CallingCardBlockKind.hook => content.hook ?? '',
        CallingCardBlockKind.tunes => content.tuneNames.join(', '),
        CallingCardBlockKind.sources => content.sourceLines.join('\n'),
        CallingCardBlockKind.program => programTitle.trim(),
        CallingCardBlockKind.number => entry.number,
        CallingCardBlockKind.text => b.text,
        CallingCardBlockKind.figures ||
        CallingCardBlockKind.rule ||
        CallingCardBlockKind.space ||
        CallingCardBlockKind.card => '',
      };

  /// The label a block prints before its text unless the layout says
  /// otherwise: the field's own label for the long-text fields.
  String _defaultLabel(CallingCardBlockKind kind) => switch (kind) {
    CallingCardBlockKind.notes => '${labels.callingNotes}: ',
    CallingCardBlockKind.walkthrough => '${labels.walkthrough}: ',
    CallingCardBlockKind.hook => '${labels.hook}: ',
    CallingCardBlockKind.tunes => '${labels.tunes}: ',
    CallingCardBlockKind.sources => '${labels.sources}: ',
    _ => '',
  };

  static PdfColor _color(int rgb) => PdfColor.fromInt(0xff000000 | rgb);

  static pw.TextAlign _align(CallingCardAlign a) => switch (a) {
    CallingCardAlign.left => pw.TextAlign.left,
    CallingCardAlign.center => pw.TextAlign.center,
    CallingCardAlign.right => pw.TextAlign.right,
  };

  pw.TextStyle _style(CallingCardBlock b, {double? size, bool? bold}) =>
      pw.TextStyle(
        fontSize: size ?? b.size,
        fontWeight: (bold ?? b.bold) ? pw.FontWeight.bold : null,
        fontStyle: b.italic ? pw.FontStyle.italic : null,
        color: b.color == null ? _ink : _color(b.color!),
      );

  pw.Widget? _text(CallingCardBlock b, String text, String defaultLabel) {
    if (text.trim().isEmpty) return null;
    final label = b.label ?? defaultLabel;
    return pw.RichText(
      textAlign: _align(b.align),
      maxLines: b.maxLines,
      overflow: pw.TextOverflow.clip,
      text: pw.TextSpan(
        style: _style(b),
        children: [
          if (label.isNotEmpty)
            pw.TextSpan(
              text: label,
              style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          pw.TextSpan(text: text),
        ],
      ),
    );
  }

  String _render(Figure figure) => canonicalizeDiscouragedTerms
      ? renderer.renderSummaryWithCanonicalDiscouragedTerms(figure, dialect)
      : renderer.renderSummary(figure, dialect);

  String _renderFree(String text) => canonicalizeDiscouragedTerms
      ? renderer.renderFreeTextWithCanonicalDiscouragedTerms(text, dialect)
      : renderer.renderFreeText(text, dialect);

  /// The phrase / beats / figure table: one group per phrase, its label
  /// centred beside its figures, thin lines between phrases.
  pw.Widget? _figures(CallingCardBlock b) {
    if (content.figures.isEmpty) return null;
    final sections = <List<SectionedFigure>>[];
    for (final sf in deriveSections(
      content.figures,
      entry.dance.phraseStructure,
    )) {
      if (sections.isEmpty || sections.last.first.label != sf.label) {
        sections.add([sf]);
      } else {
        sections.last.add(sf);
      }
    }
    final s = b.size;
    final rows = <pw.Widget>[];
    for (var i = 0; i < sections.length; i++) {
      if (i > 0 && b.dividers) {
        rows.add(
          pw.Container(
            height: 0.6,
            margin: pw.EdgeInsets.symmetric(vertical: s * 0.25),
            color: _divider,
          ),
        );
      } else if (i > 0) {
        rows.add(pw.SizedBox(height: s * 0.3));
      }
      final section = sections[i];
      rows.add(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (b.phrases)
              pw.SizedBox(
                width: s * 2.4,
                child: pw.Text(
                  section.first.label,
                  style: pw.TextStyle(
                    fontSize: s * 1.05,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
              ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [for (final sf in section) _figureLine(b, sf.figure)],
              ),
            ),
          ],
        ),
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  pw.Widget _figureLine(CallingCardBlock b, Figure figure) {
    final s = b.size;
    final marker = figure.progression ? ' ¶' : '';
    final note = figure.note?.trim() ?? '';
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: s * 0.08),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (b.beats) ...[
            pw.SizedBox(
              width: s * 1.6,
              child: pw.Text(
                figure.beats > 0 ? '${figure.beats}' : '',
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                  fontSize: s * 0.8,
                  fontWeight: pw.FontWeight.bold,
                  color: _muted,
                ),
              ),
            ),
            pw.SizedBox(width: s * 0.7),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('${_render(figure)}$marker', style: _style(b)),
                if (b.figureNotes && note.isNotEmpty)
                  pw.Text(
                    _renderFree(note),
                    style: pw.TextStyle(
                      fontSize: s * 0.8,
                      fontStyle: pw.FontStyle.italic,
                      color: _muted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lays its child out at full width and, when it is taller than the space it
/// is given, at the largest scale (down to [minScale]) at which it fits — laid
/// out wider by the inverse of that scale, so that once painted at the scale
/// it spans the full width again and its lines re-wrap rather than squash —
/// then paints it scaled into the space. Past [minScale] the child
/// is clipped at the bottom and a corner triangle marks the card.
class _ShrinkToFit extends pw.SingleChildWidget {
  _ShrinkToFit({
    required pw.Widget child,
    required this.minScale,
    required this.onLaidOut,
  }) : super(child: child);

  final double minScale;
  final void Function(double scale, bool overflowed) onLaidOut;

  double _scale = 1;
  bool _overflowed = false;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    bool fitsAt(double scale) {
      child!.layout(
        context,
        pw.BoxConstraints(maxWidth: width / scale),
        parentUsesSize: true,
      );
      return child!.box!.height * scale <= height + 0.01;
    }

    var scale = 1.0;
    var overflowed = false;
    if (!fitsAt(1)) {
      if (!fitsAt(minScale)) {
        scale = minScale;
        overflowed = true;
      } else {
        // Largest fitting scale, to within 1%.
        var fits = minScale;
        var tooBig = 1.0;
        while (tooBig - fits > 0.01) {
          final mid = (fits + tooBig) / 2;
          if (fitsAt(mid)) {
            fits = mid;
          } else {
            tooBig = mid;
          }
        }
        scale = fits;
        // The search's last layout may have been at a scale that did not
        // fit; the child must be laid out at the one it is painted at.
        fitsAt(scale);
      }
    }
    _scale = scale;
    _overflowed = overflowed;
    onLaidOut(scale, overflowed);
    box = PdfRect(0, 0, width, height);
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    final b = box!;
    final childHeight = child!.box!.height * _scale;
    final mat = Matrix4.translationValues(b.left, b.top - childHeight, 0)
      ..scaleByDouble(_scale, _scale, 1, 1);
    context.canvas
      ..saveContext()
      ..drawBox(b)
      ..clipPath()
      ..setTransform(mat);
    child!.paint(context);
    context.canvas.restoreContext();
    if (_overflowed) {
      // A dog-ear in the bottom-right corner: this card is cut off.
      const ear = 9.0;
      context.canvas
        ..saveContext()
        ..setFillColor(PdfColors.grey600)
        ..moveTo(b.right, b.bottom)
        ..lineTo(b.right - ear, b.bottom)
        ..lineTo(b.right, b.bottom + ear)
        ..closePath()
        ..fillPath()
        ..restoreContext();
    }
  }
}
