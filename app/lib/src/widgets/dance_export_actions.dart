import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../export/dance_pdf.dart';
import '../export/dance_share_bundle.dart';
import '../export/export_labels_l10n.dart';
import '../export/json_export.dart';
import '../export/share_file.dart';
import '../utils/safe_name.dart';
import 'export_guard.dart';

/// Hands the shareable card to the OS share sheet. Defaults to
/// [SharePlus.instance.share]; overridable so tests can force a failure.
typedef ShareInvoker = Future<void> Function(ShareParams params);

/// Hands a generated PDF to the OS print/save dialog. Defaults to
/// [Printing.layoutPdf]; overridable so tests can force a failure.
typedef PdfLayouter =
    Future<void> Function({
      required String name,
      required LayoutCallback onLayout,
    });

/// The five dance export actions, implemented once for both the wide-layout
/// [DanceExportMenu] and the phone-width overflow menu in `DanceDetailScreen`.
///
/// The two surfaces used to carry their own copies of this wiring, which drifted
/// apart (#1395). Each method runs inside [guardExport] and takes the
/// [ScaffoldMessengerState] and [AppLocalizations] the caller resolved **before**
/// the menu route popped, so nothing here reads an inherited widget after an
/// `await`. [exportJson] is the one method that also takes a [BuildContext]: the
/// JSON choice dialog needs a live one, and it is only used for that dialog and
/// for `context.mounted` after it closes.
///
/// Diagnostic `source:` tags are `dance_export_actions.<method>`.
class DanceExportActions {
  const DanceExportActions({
    required this.dance,
    required this.dialect,
    required this.authorNames,
    required this.formationLabel,
    required this.statusLabel,
    required this.canonicalizeDiscouragedTerms,
    this.levelLabel,
    this.renderer,
    this.choreographersById = const {},
    this.tagsById = const {},
    this.sourcesById = const {},
    this.customFieldsById = const {},
    this.difficultyLevelFor,
    this.fields = DanceShareField.allExceptTunes,
    this.shareInvoker,
    this.bundleFileWriter,
    this.pdfLayouter,
    this.jsonExportDelivery,
  });

  final Dance dance;
  final Dialect dialect;
  final List<String> authorNames;
  final String formationLabel;
  final String statusLabel;
  final String? levelLabel;
  final FigureRenderer? renderer;
  final bool canonicalizeDiscouragedTerms;

  /// Which non-figures fields appear on the exported card (issue #1434).
  final Set<DanceShareField> fields;
  final Map<String, Choreographer> choreographersById;
  final Map<String, Tag> tagsById;
  final Map<String, PublishedSource> sourcesById;
  final Map<String, CustomFieldDef> customFieldsById;
  final DifficultyLevel? Function(String id)? difficultyLevelFor;

  /// Test seam for the share call; defaults to [SharePlus.instance.share]. Not
  /// used on platforms where [isBundleShareUnsupported] (Linux) routes the file
  /// actions to Save As.
  final ShareInvoker? shareInvoker;

  /// Test seam for staging a share file.
  final BundleFileWriter? bundleFileWriter;

  /// Test seam for the print/save call; defaults to [Printing.layoutPdf].
  final PdfLayouter? pdfLayouter;

  /// Shared JSON delivery seam. When absent, [shareInvoker] and
  /// [bundleFileWriter] are used for Share while Save, Copy, and the choice
  /// dialog use defaults. Its `saveInvoker` also receives the `.ccshare` bundle
  /// on platforms where [isBundleShareUnsupported] turns the bundle action into
  /// Save As.
  final JsonExportDelivery? jsonExportDelivery;

  String _plainText(AppLocalizations l10n) => danceToPlainText(
    dance,
    dialect: dialect,
    authorNames: authorNames,
    formationLabel: formationLabel,
    levelLabel: levelLabel,
    statusLabel: statusLabel,
    renderer: renderer,
    labels: danceExportLabels(l10n),
    canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
    fields: fields,
  );

  ({String json, String fileName}) _buildBundle({required String extension}) {
    final json = buildDanceShareBundle(
      dance,
      choreographerFor: (id) => choreographersById[id],
      tagFor: (id) => tagsById[id],
      publishedSourceFor: (id) => sourcesById[id],
      customFieldFor: (id) => customFieldsById[id],
      difficultyLevelFor: difficultyLevelFor,
    );
    final fileName = danceShareBundleFileName(
      dance.title,
      extension: extension,
    );
    return (json: json, fileName: fileName);
  }

  JsonExportDelivery get _jsonDelivery {
    final delivery = jsonExportDelivery;
    if (delivery == null) {
      return JsonExportDelivery(
        shareInvoker: shareInvoker,
        bundleFileWriter: bundleFileWriter,
      );
    }
    return JsonExportDelivery(
      choicePicker: delivery.choicePicker,
      saveInvoker: delivery.saveInvoker,
      clipboardWriter: delivery.clipboardWriter,
      shareInvoker: delivery.shareInvoker ?? shareInvoker,
      bundleFileWriter: delivery.bundleFileWriter ?? bundleFileWriter,
    );
  }

  /// Shares the plain-text card through the OS share sheet.
  Future<void> shareText(
    ScaffoldMessengerState messenger,
    AppLocalizations l10n, {
    Rect? origin,
  }) => guardExport(messenger, l10n.exportShareDanceError, () async {
    final share = shareInvoker ?? SharePlus.instance.share;
    await share(
      ShareParams(
        text: _plainText(l10n),
        subject: dance.title,
        sharePositionOrigin: origin,
      ),
    );
  }, source: 'dance_export_actions.shareText');

  /// Copies the plain-text card to the clipboard and confirms with a SnackBar.
  Future<void> copyText(
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
  ) => guardExport(messenger, l10n.exportDanceError, () async {
    await Clipboard.setData(ClipboardData(text: _plainText(l10n)));
    messenger.showSnackBar(SnackBar(content: Text(l10n.exportDanceCopied)));
  }, source: 'dance_export_actions.copyText');

  /// Shares the `.ccshare` dance file, or saves it where the platform's share
  /// sheet cannot carry files ([isBundleShareUnsupported]).
  Future<void> shareBundle(
    ScaffoldMessengerState messenger,
    AppLocalizations l10n, {
    Rect? origin,
  }) => guardExport(messenger, l10n.exportShareDanceError, () async {
    final bundle = _buildBundle(extension: danceShareBundleExtension);
    final result = await shareOrSaveBundleFile(
      json: bundle.json,
      fileName: bundle.fileName,
      subject: dance.title,
      origin: origin,
      shareInvoker: shareInvoker,
      bundleFileWriter: bundleFileWriter,
      saveInvoker: jsonExportDelivery?.saveInvoker,
    );
    announceBundleSaved(messenger, l10n, result);
  }, source: 'dance_export_actions.shareBundle');

  /// Builds the plain-JSON export, asks the user how to deliver it (Save, Copy
  /// or Share), then delivers it. [context] is used for the choice dialog and
  /// for `context.mounted` after it closes.
  Future<void> exportJson(
    BuildContext context,
    ScaffoldMessengerState messenger,
    AppLocalizations l10n, {
    Rect? origin,
  }) => guardExport(messenger, l10n.exportJsonShareError, () async {
    final bundle = _buildBundle(extension: danceShareJsonExtension);
    final delivery = _jsonDelivery;
    final choice = await delivery.choose(context);
    if (choice == null || !context.mounted) return;

    switch (choice) {
      case JsonExportChoice.save:
        await guardExport(messenger, l10n.exportJsonSaveError, () async {
          final result = await delivery.save(bundle.json, bundle.fileName);
          if (result == null || !context.mounted) return;
          final message = result.fileName == null
              ? l10n.exportJsonSavedGeneric
              : result.path.isEmpty
              ? l10n.exportJsonSaved(result.fileName!)
              : l10n.exportJsonSavedTo(result.fileName!, result.path);
          messenger.showSnackBar(SnackBar(content: Text(message)));
        }, source: 'dance_export_actions.exportJson');
      case JsonExportChoice.copy:
        await guardExport(messenger, l10n.exportJsonCopyError, () async {
          await delivery.copy(bundle.json);
          if (context.mounted) {
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.exportJsonCopied)),
            );
          }
        }, source: 'dance_export_actions.exportJson');
      case JsonExportChoice.share:
        await guardExport(messenger, l10n.exportJsonShareError, () async {
          final result = await delivery.share(
            json: bundle.json,
            fileName: bundle.fileName,
            subject: dance.title,
            sharePositionOrigin: origin,
          );
          announceBundleSaved(messenger, l10n, result);
        }, source: 'dance_export_actions.exportJson');
    }
  }, source: 'dance_export_actions.exportJson');

  /// Hands a generated PDF to the OS print/save dialog.
  Future<void> exportPdf(
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
  ) => guardExport(messenger, l10n.exportDanceError, () async {
    final layoutPdf = pdfLayouter ?? Printing.layoutPdf;
    // Resolved before the layout call: `onLayout` can run after further
    // internal awaits (font loading) or more than once.
    final labels = danceExportLabels(l10n);
    await layoutPdf(
      name: sanitizeExportName(dance.title, fallback: 'dance'),
      onLayout: (format) => buildDancePdf(
        dance,
        dialect: dialect,
        authorNames: authorNames,
        formationLabel: formationLabel,
        levelLabel: levelLabel,
        statusLabel: statusLabel,
        renderer: renderer,
        labels: labels,
        canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
        fields: fields,
      ),
    );
  }, source: 'dance_export_actions.exportPdf');
}
