import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../export/dance_pdf.dart';
import '../export/export_labels_l10n.dart';
import '../utils/safe_name.dart';

/// Actions offered by the [DanceExportMenu].
enum _ExportAction { shareText, copyText, pdf }

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
/// tooltip "Export") with three actions:
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
    this.shareInvoker,
    this.pdfLayouter,
  });

  final Dance dance;
  final Dialect dialect;
  final List<String> authorNames;
  final String formationLabel;
  final String statusLabel;
  final String? levelLabel;
  final FigureRenderer? renderer;

  /// Test seam for the share call; defaults to [SharePlus.instance.share].
  final ShareInvoker? shareInvoker;

  /// Test seam for the print/save call; defaults to [Printing.layoutPdf].
  final PdfLayouter? pdfLayouter;

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
      case _ExportAction.copyText:
        await _copyText(context);
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
    } on Exception catch (e, st) {
      debugPrint('$failureMessage: $e\n$st');
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
          value: _ExportAction.copyText,
          child: ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: Text(l10n.exportCopyDance),
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
