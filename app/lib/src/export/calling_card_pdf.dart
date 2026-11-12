import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart' show Matrix4;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'calling_card_highlight.dart';
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

  void _clear() {
    scales.clear();
    overflowed.clear();
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
  final format = PdfPageFormat(width, height, marginAll: margin);

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
    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (_) => _ShrinkToFit(
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
    );
  }
  return doc.save();
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

  /// The dialect's dancer words, for `figures highlight`; worked out once
  /// per card.
  late final Set<String> _dancers = renderer.dancerTerms(dialect);

  /// How `figures highlight` sets each kind of span apart: the move in bold
  /// dark red, the dancers in bold, the amounts in slate. Bold carries the
  /// difference on a black-and-white printer.
  static pw.TextStyle? _highlightStyle(CallingCardSpanKind kind) =>
      switch (kind) {
        CallingCardSpanKind.plain => null,
        CallingCardSpanKind.move => const pw.TextStyle(
          color: _move,
          fontWeight: pw.FontWeight.bold,
        ),
        CallingCardSpanKind.dancer => pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
        ),
        CallingCardSpanKind.amount => const pw.TextStyle(color: _muted),
      };

  static const _move = PdfColor.fromInt(0xff7a2e2e);
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
                if (b.highlight)
                  pw.RichText(
                    text: pw.TextSpan(
                      style: _style(b),
                      children: [
                        for (final span in highlightFigureLine(
                          _render(figure),
                          moves: callingCardMoveNames(
                            figure,
                            renderer,
                            dialect,
                            canonicalizeDiscouragedTerms:
                                canonicalizeDiscouragedTerms,
                          ),
                          dancers: _dancers,
                        ))
                          pw.TextSpan(
                            text: span.text,
                            style: _highlightStyle(span.kind),
                          ),
                        pw.TextSpan(text: marker),
                      ],
                    ),
                  )
                else
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
