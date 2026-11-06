import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../l10n/app_localizations.dart';
import '../export/calling_card_layout.dart';
import '../export/calling_card_pdf.dart';
import '../export/export_labels_l10n.dart';
import 'dance_export_actions.dart' show PdfLayouter;
import 'export_guard.dart';

/// Prints [entries] as calling cards through the OS print dialog, laid out by
/// [settings], and says afterwards if any card was cut off.
///
/// [pdfLayouter] is the Export menus' test seam. Without it the dialog opens
/// on the card's own paper size and does not re-lay the cards out when the
/// user picks other paper: a card is printed at its size, on card stock.
///
/// Every context-dependent value is a parameter, resolved by the caller
/// before any await, as for the other exports.
Future<void> printCallingCards({
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
  required String jobName,
  required List<CallingCardEntry> entries,
  required CallingCardSettings settings,
  required Dialect dialect,
  required FigureRenderer? renderer,
  required Set<DanceShareField> fields,
  required bool canonicalizeDiscouragedTerms,
  required String failureMessage,
  required String source,
  String programTitle = '',
  PdfLayouter? pdfLayouter,
}) => guardExport(messenger, failureMessage, () async {
  final report = CallingCardFitReport();
  final labels = danceExportLabels(l10n);
  final layout = CallingCardLayout.parse(settings.layoutSource);
  final size = settings.size;
  // The dialog's paper is not used: each page is the card.
  Future<Uint8List> build(PdfPageFormat _) => buildCallingCardsPdf(
    entries,
    layout: layout,
    size: size,
    dialect: dialect,
    fields: fields,
    renderer: renderer,
    labels: labels,
    programTitle: programTitle,
    documentTitle: jobName,
    canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
    report: report,
  );
  if (pdfLayouter != null) {
    await pdfLayouter(name: jobName, onLayout: build);
  } else {
    await Printing.layoutPdf(
      name: jobName,
      format: PdfPageFormat(size.widthPoints, size.heightPoints),
      dynamicLayout: false,
      onLayout: build,
    );
  }
  final cutOff = report.overflowed.length;
  if (cutOff > 0) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.exportCallingCardsCutOff(cutOff))),
    );
  }
}, source: source);

/// What each card's `number` block prints when a program is printed: the
/// dance's place among the program's primary dances (1, 2, 3, ...), or
/// [alternateLabel] for an alternate, which takes no place of its own.
List<String> callingCardPlaces(
  Iterable<bool> isAlternate,
  String alternateLabel,
) {
  var place = 0;
  return [
    for (final alternate in isAlternate)
      alternate ? alternateLabel : '${++place}',
  ];
}
