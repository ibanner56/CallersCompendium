import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
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
/// [fields] selects which non-figures fields appear (issue #1434), gated via
/// the shared core `dance_card_fields.dart` helpers so this stays in lockstep with
/// [buildProgramPdf]'s figure-appendix cards. Defaults to
/// [DanceShareField.allExceptTunes], matching every block this builder
/// rendered before the picker existed.
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
}) async {
  final fig = renderer ?? FigureRenderer(contraTaxonomy);
  final resolvedTheme = theme ?? await loadProgramPdfTheme();
  final doc = pw.Document(title: dance.title, theme: resolvedTheme);

  final names = danceCardAuthorNames(authorNames, fields);

  final metaLines = danceCardMetaLines(
    dance,
    formationLabel: formationLabel,
    levelLabel: levelLabel,
    statusLabel: statusLabel,
    labels: labels,
    fields: fields,
  );

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
        if (switch (dance.figuresSource) {
          DecodedFigures(:final figures) => figures,
          UnreadableFigures() => const <Figure>[],
        }.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            labels.figures,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          ...buildFigureWidgets(
            dance,
            fig,
            dialect,
            labels,
            canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
          ),
        ],
        if (fields.contains(DanceShareField.callingNotes) &&
            _has(dance.callingNotes)) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            labels.callingNotes,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            canonicalizeDiscouragedTerms
                ? fig.renderFreeTextWithCanonicalDiscouragedTerms(
                    dance.callingNotes.trim(),
                    dialect,
                  )
                : fig.renderFreeText(dance.callingNotes.trim(), dialect),
            style: const pw.TextStyle(fontSize: 12),
            overflow: pw.TextOverflow.span,
          ),
        ],
        if (fields.contains(DanceShareField.walkthrough) &&
            _has(dance.walkthrough)) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            labels.walkthrough,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            canonicalizeDiscouragedTerms
                ? fig.renderFreeTextWithCanonicalDiscouragedTerms(
                    dance.walkthrough.trim(),
                    dialect,
                  )
                : fig.renderFreeText(dance.walkthrough.trim(), dialect),
            style: const pw.TextStyle(fontSize: 12),
            overflow: pw.TextOverflow.span,
          ),
        ],
        if (danceCardTuneNames(dance, fields) case final tunes
            when tunes.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            labels.tunes,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(tunes.join(', '), style: const pw.TextStyle(fontSize: 12)),
        ],
      ],
    ),
  );

  return doc.save();
}

bool _has(String? value) => value != null && value.trim().isNotEmpty;
