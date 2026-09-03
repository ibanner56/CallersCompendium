import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../diagnostics/error_log.dart';
import '../export/dance_pdf.dart';
import '../export/export_labels_l10n.dart';
import '../utils/safe_name.dart';
import '../export/dance_share_bundle.dart';
import '../export/json_export.dart';
import '../export/share_file.dart';

/// Actions offered by the [DanceExportMenu].
enum _ExportAction { shareText, shareBundle, copyText, shareJson, pdf }

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

/// A labeled, keyboard-reachable print/share control for a single [Dance]
/// (`docs/design/ux.md` §2 dance-detail actions).
///
/// Mirrors the program-level [ProgramExportMenu]: a [PopupMenuButton] (icon +
/// tooltip "Export") with five actions:
/// - **Share dance (text)** — the shareable plain-text card, via the OS share
///   sheet (`share_plus`).
/// - **Copy dance** — copies the same text to the clipboard (an
///   always-available fallback); shows a confirming SnackBar.
/// - **Export / print PDF** — hands a generated PDF to the OS print/save dialog
///   (`printing`).
///
/// The card is rendered **dialect-aware** and privacy-safe: the caller resolves
/// author [authorNames] and the facet label strings, so no choreographer
/// contact record is ever handed to the renderer.
class DanceExportMenu extends StatelessWidget {
  const DanceExportMenu({
    super.key,
    required this.dance,
    required this.dialect,
    required this.authorNames,
    required this.formationLabel,
    required this.statusLabel,
    this.levelLabel,
    this.renderer,
    this.choreographersById = const {},
    this.tagsById = const {},
    this.sourcesById = const {},
    this.customFieldsById = const {},
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
  final Map<String, Choreographer> choreographersById;
  final Map<String, Tag> tagsById;
  final Map<String, PublishedSource> sourcesById;
  final Map<String, CustomFieldDef> customFieldsById;

  /// Test seam for the share call; defaults to [SharePlus.instance.share].
  final ShareInvoker? shareInvoker;

  /// Test seam for staging a share file.
  final BundleFileWriter? bundleFileWriter;

  /// Test seam for the print/save call; defaults to [Printing.layoutPdf].
  final PdfLayouter? pdfLayouter;

  /// Shared JSON delivery seam. When absent, the legacy share/file seams above
  /// are used for Share while Save, Copy, and the choice dialog use defaults.
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
  );

  Future<void> _shareText(AppLocalizations l10n, Rect? origin) async {
    final share = shareInvoker ?? SharePlus.instance.share;
    await share(
      ShareParams(
        text: _plainText(l10n),
        subject: dance.title,
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<void> _copyText(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: _plainText(l10n)));
    messenger.showSnackBar(SnackBar(content: Text(l10n.exportDanceCopied)));
  }

  Future<void> _shareBundle(
    Rect? origin, {
    String extension = danceShareBundleExtension,
  }) async {
    final bundle = _buildBundle(extension: extension);
    final writeFile = bundleFileWriter ?? writeBundleTempFile;
    final xfile = await writeFile(bundle.json, bundle.fileName);
    final share = shareInvoker ?? SharePlus.instance.share;
    await share(
      ShareParams(
        files: [xfile],
        fileNameOverrides: [bundle.fileName],
        subject: dance.title,
        sharePositionOrigin: origin,
      ),
    );
  }

  ({String json, String fileName}) _buildBundle({required String extension}) {
    final json = buildDanceShareBundle(
      dance,
      choreographerFor: (id) => choreographersById[id],
      tagFor: (id) => tagsById[id],
      publishedSourceFor: (id) => sourcesById[id],
      customFieldFor: (id) => customFieldsById[id],
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

  Future<void> _exportJson(BuildContext context, Rect? origin) async {
    final bundle = _buildBundle(extension: danceShareJsonExtension);
    final delivery = _jsonDelivery;
    final choice = await delivery.choose(context);
    if (choice == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);

    switch (choice) {
      case JsonExportChoice.save:
        await _guard(messenger, l10n.exportJsonSaveError, () async {
          final result = await delivery.save(bundle.json, bundle.fileName);
          if (result == null || !context.mounted) return;
          final message = result.fileName == null
              ? l10n.exportJsonSavedGeneric
              : result.path.isEmpty
              ? l10n.exportJsonSaved(result.fileName!)
              : l10n.exportJsonSavedTo(result.fileName!, result.path);
          messenger.showSnackBar(SnackBar(content: Text(message)));
        });
      case JsonExportChoice.copy:
        await _guard(messenger, l10n.exportJsonCopyError, () async {
          await delivery.copy(bundle.json);
          if (context.mounted) {
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.exportJsonCopied)),
            );
          }
        });
      case JsonExportChoice.share:
        await _guard(messenger, l10n.exportJsonShareError, () {
          return delivery.share(
            json: bundle.json,
            fileName: bundle.fileName,
            subject: dance.title,
            sharePositionOrigin: origin,
          );
        });
    }
  }

  Future<void> _exportPdf(AppLocalizations l10n) async {
    final layoutPdf = pdfLayouter ?? Printing.layoutPdf;
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
        labels: danceExportLabels(l10n),
      ),
    );
  }

  Future<void> _onSelected(BuildContext context, _ExportAction action) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    // Capture the button's screen position before any await: on desktop
    // `share_plus` needs a `sharePositionOrigin` to anchor the native share
    // popover, and the render tree may have moved on by the time the async
    // gap resumes. A null box (e.g. not yet laid out) degrades gracefully —
    // the share is still attempted, just without an anchor.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? (box.localToGlobal(Offset.zero) & box.size)
        : null;
    switch (action) {
      case _ExportAction.shareText:
        await _guard(
          messenger,
          l10n.exportShareDanceError,
          () => _shareText(l10n, origin),
        );
      case _ExportAction.shareBundle:
        await _guard(
          messenger,
          l10n.exportShareDanceError,
          () => _shareBundle(origin),
        );
      case _ExportAction.copyText:
        await _copyText(context);
      case _ExportAction.shareJson:
        await _guard(
          messenger,
          l10n.exportJsonShareError,
          () => _exportJson(context, origin),
        );
      case _ExportAction.pdf:
        await _guard(messenger, l10n.exportDanceError, () => _exportPdf(l10n));
    }
  }

  /// Runs [action], surfacing [failureMessage] as a [SnackBar] if it throws.
  ///
  /// A user who simply cancels a share/print sheet surfaces as a normal
  /// (non-throwing) result, so only genuine failures are reported.
  Future<void> _guard(
    ScaffoldMessengerState messenger,
    String failureMessage,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on Object catch (e, st) {
      logCaughtError(e, st, source: 'dance_export_menu._guard');
      if (kDebugMode) {
        debugPrint('$failureMessage: $e\n$st');
      }
      messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<_ExportAction>(
      key: const ValueKey('dance-export-menu'),
      tooltip: l10n.exportTooltip,
      icon: const Icon(Icons.ios_share),
      onSelected: (action) => _onSelected(context, action),
      itemBuilder: (context) => [
        PopupMenuItem<_ExportAction>(
          value: _ExportAction.shareText,
          child: ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(l10n.exportShareDanceText),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<_ExportAction>(
          value: _ExportAction.shareBundle,
          child: ListTile(
            leading: const Icon(Icons.share_outlined),
            title: Text(l10n.exportShareDanceBundle),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<_ExportAction>(
          value: _ExportAction.copyText,
          child: ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: Text(l10n.exportCopyDance),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<_ExportAction>(
          value: _ExportAction.shareJson,
          child: ListTile(
            leading: const Icon(Icons.data_object_outlined),
            title: Text(l10n.exportShareDanceJson),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<_ExportAction>(
          value: _ExportAction.pdf,
          child: ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(l10n.exportPrintPdf),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
