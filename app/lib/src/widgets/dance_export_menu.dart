import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../export/dance_pdf.dart';

/// Actions offered by the [DanceExportMenu].
enum _ExportAction { shareText, copyText, pdf }

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
  });

  final Dance dance;
  final Dialect dialect;
  final List<String> authorNames;
  final String formationLabel;
  final String statusLabel;
  final String? levelLabel;
  final FigureRenderer? renderer;

  String _plainText() => danceToPlainText(
    dance,
    dialect: dialect,
    authorNames: authorNames,
    formationLabel: formationLabel,
    levelLabel: levelLabel,
    statusLabel: statusLabel,
    renderer: renderer,
  );

  Future<void> _shareText() async {
    await SharePlus.instance.share(
      ShareParams(text: _plainText(), subject: dance.title),
    );
  }

  Future<void> _copyText(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _plainText()));
    messenger.showSnackBar(
      const SnackBar(content: Text('Dance copied to clipboard.')),
    );
  }

  Future<void> _exportPdf() async {
    await Printing.layoutPdf(
      name: dance.title,
      onLayout: (format) => buildDancePdf(
        dance,
        dialect: dialect,
        authorNames: authorNames,
        formationLabel: formationLabel,
        levelLabel: levelLabel,
        statusLabel: statusLabel,
        renderer: renderer,
      ),
    );
  }

  Future<void> _onSelected(BuildContext context, _ExportAction action) async {
    switch (action) {
      case _ExportAction.shareText:
        await _shareText();
      case _ExportAction.copyText:
        await _copyText(context);
      case _ExportAction.pdf:
        await _exportPdf();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ExportAction>(
      key: const ValueKey('dance-export-menu'),
      tooltip: 'Export',
      icon: const Icon(Icons.ios_share),
      onSelected: (action) => _onSelected(context, action),
      itemBuilder: (context) => const [
        PopupMenuItem<_ExportAction>(
          value: _ExportAction.shareText,
          child: ListTile(
            leading: Icon(Icons.mail_outline),
            title: Text('Share dance (text)'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<_ExportAction>(
          value: _ExportAction.copyText,
          child: ListTile(
            leading: Icon(Icons.copy_outlined),
            title: Text('Copy dance'),
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
