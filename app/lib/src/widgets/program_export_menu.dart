import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../export/program_pdf.dart';

/// Actions offered by the [ProgramExportMenu].
enum _ExportAction { shareText, copyText, pdf }

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
  });

  final Program program;
  final String? Function(String danceId) titleFor;

  String _formatDate(BuildContext context, DateTime date) =>
      MaterialLocalizations.of(context).formatMediumDate(date);

  String _plainText(BuildContext context) => programToPlainText(
    program,
    titleFor: titleFor,
    formatDate: (d) => _formatDate(context, d),
  );

  Future<void> _shareText(BuildContext context) async {
    await Share.share(_plainText(context), subject: program.title);
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
    await Printing.layoutPdf(
      name: program.title,
      onLayout: (format) => buildProgramPdf(
        program,
        titleFor: titleFor,
        formatDate: localizations.formatMediumDate,
      ),
    );
  }

  Future<void> _onSelected(BuildContext context, _ExportAction action) async {
    switch (action) {
      case _ExportAction.shareText:
        await _shareText(context);
      case _ExportAction.copyText:
        await _copyText(context);
      case _ExportAction.pdf:
        await _exportPdf(context);
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
