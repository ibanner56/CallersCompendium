import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../export/program_pdf.dart';

/// Actions offered by the [ProgramExportMenu].
enum _ExportAction { shareText, copyText, pdf }

/// Hands the shareable set list to the OS share sheet. Defaults to
/// [SharePlus.instance.share]; overridable so tests can force a failure.
typedef ShareInvoker = Future<void> Function(ShareParams params);

/// Hands a generated PDF to the OS print/save dialog. Defaults to
/// [Printing.layoutPdf]; overridable so tests can force a failure.
typedef PdfLayouter =
    Future<void> Function({
      required String name,
      required LayoutCallback onLayout,
    });

/// A labeled, keyboard-reachable export control for a [Program] (ROADMAP §4.3).
///
/// Renders a [PopupMenuButton] (icon + tooltip "Export") with three actions:
/// - **Share set list (text)** — the emailable plain-text set list, via the OS
///   share sheet (`share_plus`, text sharing is supported on all platforms).
/// - **Copy set list** — copies the same text to the clipboard; an
///   always-available fallback where a share target is unavailable.
/// - **Export / print PDF** — hands a generated PDF to the OS print/save dialog
///   (`printing`, all platforms including Linux).
///
/// Titles for dance slots are resolved through [titleFor]; the event date is
/// formatted with the ambient [MaterialLocalizations].
class ProgramExportMenu extends StatelessWidget {
  const ProgramExportMenu({
    super.key,
    required this.program,
    required this.titleFor,
    this.shareInvoker,
    this.pdfLayouter,
  });

  final Program program;
  final String? Function(String danceId) titleFor;

  /// Test seam for the share call; defaults to [SharePlus.instance.share].
  final ShareInvoker? shareInvoker;

  /// Test seam for the print/save call; defaults to [Printing.layoutPdf].
  final PdfLayouter? pdfLayouter;

  String _formatDate(BuildContext context, DateTime date) =>
      MaterialLocalizations.of(context).formatMediumDate(date);

  String _plainText(BuildContext context) => programToPlainText(
    program,
    titleFor: titleFor,
    formatDate: (d) => _formatDate(context, d),
  );

  Future<void> _shareText(BuildContext context, Rect? origin) async {
    final share = shareInvoker ?? SharePlus.instance.share;
    await share(
      ShareParams(
        text: _plainText(context),
        subject: program.title,
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<void> _copyText(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _plainText(context)));
    messenger.showSnackBar(
      const SnackBar(content: Text('Set list copied to clipboard.')),
    );
  }

  Future<void> _exportPdf(BuildContext context) async {
    final localizations = MaterialLocalizations.of(context);
    final layoutPdf = pdfLayouter ?? Printing.layoutPdf;
    await layoutPdf(
      name: program.title,
      onLayout: (format) => buildProgramPdf(
        program,
        titleFor: titleFor,
        formatDate: localizations.formatMediumDate,
      ),
    );
  }

  Future<void> _onSelected(BuildContext context, _ExportAction action) async {
    final messenger = ScaffoldMessenger.of(context);
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
          "Couldn't share this set list",
          () => _shareText(context, origin),
        );
      case _ExportAction.copyText:
        await _copyText(context);
      case _ExportAction.pdf:
        await _guard(
          messenger,
          "Couldn't export this set list",
          () => _exportPdf(context),
        );
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
    return PopupMenuButton<_ExportAction>(
      key: const ValueKey('program-export-menu'),
      tooltip: 'Export',
      icon: const Icon(Icons.ios_share),
      onSelected: (action) => _onSelected(context, action),
      itemBuilder: (context) => const [
        PopupMenuItem<_ExportAction>(
          value: _ExportAction.shareText,
          child: ListTile(
            leading: Icon(Icons.mail_outline),
            title: Text('Share set list (text)'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<_ExportAction>(
          value: _ExportAction.copyText,
          child: ListTile(
            leading: Icon(Icons.copy_outlined),
            title: Text('Copy set list'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<_ExportAction>(
          value: _ExportAction.pdf,
          child: ListTile(
            leading: Icon(Icons.picture_as_pdf_outlined),
            title: Text('Export / print PDF'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
