import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/canonical_discouraged_terms_scope.dart';
import '../export/json_export.dart';
import '../export/share_file.dart';
import 'dance_export_actions.dart';

export 'dance_export_actions.dart' show PdfLayouter, ShareInvoker;

/// Actions offered by the [DanceExportMenu].
enum _ExportAction { shareText, shareBundle, copyText, shareJson, pdf }

/// A labeled, keyboard-reachable print/share control for a single [Dance]
/// (`docs/design/ux.md` §2 dance-detail actions).
///
/// Mirrors the program-level [ProgramExportMenu]: a [PopupMenuButton] (icon +
/// tooltip "Export") with five actions, all implemented by
/// [DanceExportActions]:
/// - **Share dance (text)** — the shareable plain-text card, via the OS share
///   sheet (`share_plus`).
/// - **Share / save dance file** — the `.ccshare` bundle, via the share sheet
///   (or Save As where the platform's share sheet cannot carry files).
/// - **Copy dance** — copies the same text to the clipboard (an
///   always-available fallback); shows a confirming SnackBar.
/// - **Share dance JSON** — the plain JSON export, with a Save / Copy / Share
///   choice.
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
    this.difficultyLevelFor,
    this.shareInvoker,
    this.bundleFileWriter,
    this.pdfLayouter,
    this.jsonExportDelivery,
    this.fields = DanceShareField.allExceptTunes,
  });

  final Dance dance;
  final Dialect dialect;
  final List<String> authorNames;
  final String formationLabel;
  final String statusLabel;
  final String? levelLabel;
  final FigureRenderer? renderer;

  /// Which non-figures fields appear on the exported card (issue #1434).
  /// Defaults to every field this widget rendered unconditionally before the
  /// picker existed, minus tunes — see [DanceShareField.allExceptTunes].
  final Set<DanceShareField> fields;
  final Map<String, Choreographer> choreographersById;
  final Map<String, Tag> tagsById;
  final Map<String, PublishedSource> sourcesById;
  final Map<String, CustomFieldDef> customFieldsById;
  final DifficultyLevel? Function(String id)? difficultyLevelFor;

  /// Test seam for the share call; defaults to [SharePlus.instance.share].
  /// Not used on platforms where [isBundleShareUnsupported] (Linux) routes the
  /// file actions to Save As.
  final ShareInvoker? shareInvoker;

  /// Test seam for staging a share file.
  final BundleFileWriter? bundleFileWriter;

  /// Test seam for the print/save call; defaults to [Printing.layoutPdf].
  final PdfLayouter? pdfLayouter;

  /// Shared JSON delivery seam. When absent, the legacy share/file seams above
  /// are used for Share while Save, Copy, and the choice dialog use defaults.
  /// Its `saveInvoker` also receives the `.ccshare` bundle on platforms where
  /// [isBundleShareUnsupported] (Linux) turns the bundle action into Save As.
  final JsonExportDelivery? jsonExportDelivery;

  DanceExportActions _actions({required bool canonicalizeDiscouragedTerms}) =>
      DanceExportActions(
        dance: dance,
        dialect: dialect,
        authorNames: authorNames,
        formationLabel: formationLabel,
        statusLabel: statusLabel,
        levelLabel: levelLabel,
        renderer: renderer,
        fields: fields,
        canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
        choreographersById: choreographersById,
        tagsById: tagsById,
        sourcesById: sourcesById,
        customFieldsById: customFieldsById,
        difficultyLevelFor: difficultyLevelFor,
        shareInvoker: shareInvoker,
        bundleFileWriter: bundleFileWriter,
        pdfLayouter: pdfLayouter,
        jsonExportDelivery: jsonExportDelivery,
      );

  Future<void> _onSelected(BuildContext context, _ExportAction action) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final actions = _actions(
      canonicalizeDiscouragedTerms: CanonicalDiscouragedTermsScope.of(context),
    );
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
        await actions.shareText(messenger, l10n, origin: origin);
      case _ExportAction.shareBundle:
        await actions.shareBundle(messenger, l10n, origin: origin);
      case _ExportAction.copyText:
        await actions.copyText(messenger, l10n);
      case _ExportAction.shareJson:
        await actions.exportJson(context, messenger, l10n, origin: origin);
      case _ExportAction.pdf:
        await actions.exportPdf(messenger, l10n);
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
            leading: Icon(
              isBundleShareUnsupported()
                  ? Icons.save_alt_outlined
                  : Icons.share_outlined,
            ),
            title: Text(
              isBundleShareUnsupported()
                  ? l10n.exportSaveDanceBundle
                  : l10n.exportShareDanceBundle,
            ),
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
