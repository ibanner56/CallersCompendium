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
/// [settings], and says afterwards if any card was cut off — unless the
/// dialog was cancelled.
///
/// [pdfLayouter] is the Export menus' test seam. Without it the dialog opens
/// on the card's own paper size and does not re-lay the cards out when the
/// user picks other paper: a card is printed at its size, on card stock.
/// With [CallingCardSettings.onSheets] it is the other way round: the cards
/// are laid out several to a page of whatever paper the dialog chooses, and
/// again whenever the user changes it.
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
  final onSheets = settings.onSheets;
  // On card stock the dialog's paper is not used: each page is the card.
  Future<Uint8List> build(PdfPageFormat paper) => buildCallingCardsPdf(
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
    sheet: onSheets ? paper : null,
  );
  // The seam does not say whether the user printed; the real dialog does.
  var printed = true;
  if (pdfLayouter != null) {
    await pdfLayouter(name: jobName, onLayout: build);
  } else if (onSheets) {
    printed = await Printing.layoutPdf(name: jobName, onLayout: build);
  } else {
    printed = await Printing.layoutPdf(
      name: jobName,
      format: PdfPageFormat(size.widthPoints, size.heightPoints),
      dynamicLayout: false,
      onLayout: build,
    );
  }
  if (!printed) return;
  final cutOff = report.overflowed.length;
  if (cutOff > 0) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.exportCallingCardsCutOff(cutOff))),
    );
  }
  if (report.cardsShrunkToSheet) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.exportCallingCardsBiggerThanPaper)),
    );
  }
}, source: source);

/// What each card's `number` block prints when [program] is printed, by
/// dance id: the number the set list gives the dance's first slot (planned
/// dances, note slots included, numbered 1, 2, 3, ... in output order by
/// [Program.danceNumbersForSlots]), or [alternateLabel] when that slot is an
/// alternate, which the set list marks instead of numbering. A dance that
/// appears twice keeps its first slot's label, as it prints one card.
Map<String, String> callingCardPlaces(Program program, String alternateLabel) {
  final slots = [
    for (final group in program.outputGrouped) ...[
      group.primary,
      ...group.alternates,
    ],
  ];
  final numbers = Program.danceNumbersForSlots(slots);
  final places = <String, String>{};
  for (final (i, slot) in slots.indexed) {
    final id = slot.danceId;
    if (id == null || places.containsKey(id)) continue;
    final number = numbers[i];
    if (number != null) {
      places[id] = '$number';
    } else if (slot.isAlt) {
      places[id] = alternateLabel;
    }
  }
  return places;
}
