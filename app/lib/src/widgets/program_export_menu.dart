import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../export/program_pdf.dart';
import '../export/program_share_bundle.dart';

/// Actions offered by the [ProgramExportMenu].
enum _ExportAction { shareText, shareBundle, copyText, pdf }

/// Hands the shareable set list to the OS share sheet. Defaults to
/// [SharePlus.instance.share]; overridable so tests can force a failure.
typedef ShareInvoker = Future<void> Function(ShareParams params);

/// Materializes a share-bundle [json] payload as an [XFile] named [fileName]
/// for the OS share sheet. The default writes it to a temp file (via
/// `path_provider`); overridable so tests can supply the file without invoking
/// the `path_provider` platform channel, which has no plugin implementation
/// under `flutter test` (its calls would throw `MissingPluginException`).
typedef BundleFileWriter = Future<XFile> Function(String json, String fileName);

/// Resolves the base directory a share bundle is staged into before it is
/// handed to the OS share sheet. Defaults to the OS temporary directory (via
/// `path_provider`); injectable so [writeBundleFile] can be exercised in tests
/// against a directory that doesn't touch the `path_provider` platform channel.
typedef ShareTempDirProvider = Future<Directory> Function();

/// Writes [json] to a file named [fileName] inside the directory from
/// [getDir], **creating that directory first**, and returns it as a JSON
/// [XFile].
///
/// The directory is created (recursively) before the write because on sandboxed
/// macOS `getTemporaryDirectory()` returns a per-bundle subdirectory under
/// `Caches/` that does not necessarily exist yet. Writing a file straight into
/// a missing directory throws `PathNotFoundException` (errno 2), which the
/// share action's guard surfaces as "Couldn't share this program". Creating the
/// directory first makes the temp-file write reliable across platforms.
Future<XFile> writeBundleFile(
  String json,
  String fileName, {
  ShareTempDirProvider getDir = getTemporaryDirectory,
}) async {
  final dir = await getDir();
  await dir.create(recursive: true);
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(json);
  return XFile(file.path, mimeType: 'application/json');
}

/// Default [BundleFileWriter]: writes [json] to a temp file (via
/// `path_provider`) and returns it as a JSON [XFile].
Future<XFile> writeBundleTempFile(String json, String fileName) =>
    writeBundleFile(json, fileName);

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
    this.danceFor,
    this.choreographerFor,
    this.shareInvoker,
    this.bundleFileWriter,
    this.pdfLayouter,
  });

  final Program program;
  final String? Function(String danceId) titleFor;

  /// Resolves a slot's `danceId` to its full [Dance], so the "Share (program +
  /// dances)" action can embed every referenced dance in a self-contained
  /// bundle. When `null`, that action is omitted (there is nothing to embed).
  final Dance? Function(String danceId)? danceFor;

  /// Resolves a dance's author id to its full [Choreographer], so the "Share
  /// (program + dances)" action can embed the choreographers its bundled dances
  /// reference and author attribution survives the round-trip. Optional and
  /// best-effort: an unresolved id is simply omitted from the bundle.
  final Choreographer? Function(String id)? choreographerFor;

  /// Test seam for the share call; defaults to [SharePlus.instance.share].
  final ShareInvoker? shareInvoker;

  /// Test seam for the bundle temp-file write; defaults to
  /// [writeBundleTempFile].
  final BundleFileWriter? bundleFileWriter;

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

  /// Writes a self-contained program-plus-referenced-dances bundle (the
  /// canonical [CompendiumArchive] JSON — see [buildProgramShareBundle]) to a
  /// temp file and hands it to the OS share sheet as a JSON [XFile].
  ///
  /// The bundle *carries* the program plus the full definition of every dance
  /// its slots reference. On the receiving device the **existing** manual
  /// Import flow (`GenericJsonAdapter`) imports the embedded **dances** today;
  /// it does not yet import the program. The program travels in the bundle for
  /// the forthcoming receive-side auto-open (issue #298, PR 2), which will
  /// import the program itself. This send-side action ships first, so a
  /// recipient on a build without the receive side gets the dances now and the
  /// program once PR 2 lands.
  Future<void> _shareBundle(Rect? origin) async {
    final resolveDance = danceFor;
    if (resolveDance == null) return;

    final json = buildProgramShareBundle(
      program,
      danceFor: resolveDance,
      choreographerFor: choreographerFor ?? (_) => null,
    );
    final fileName = programShareBundleFileName(program.title);

    final writeFile = bundleFileWriter ?? writeBundleTempFile;
    final xfile = await writeFile(json, fileName);

    final share = shareInvoker ?? SharePlus.instance.share;
    await share(
      ShareParams(
        files: [xfile],
        fileNameOverrides: [fileName],
        subject: program.title,
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<void> _copyText(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: _plainText(context)));
    messenger.showSnackBar(SnackBar(content: Text(l10n.exportSetListCopied)));
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
          l10n.exportShareSetListError,
          () => _shareText(context, origin),
        );
      case _ExportAction.shareBundle:
        await _guard(
          messenger,
          l10n.exportShareProgramError,
          () => _shareBundle(origin),
        );
      case _ExportAction.copyText:
        await _copyText(context);
      case _ExportAction.pdf:
        await _guard(
          messenger,
          l10n.exportSetListError,
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
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<_ExportAction>(
      key: const ValueKey('program-export-menu'),
      tooltip: l10n.exportTooltip,
      icon: const Icon(Icons.ios_share),
      onSelected: (action) => _onSelected(context, action),
      itemBuilder: (context) => [
        PopupMenuItem<_ExportAction>(
          value: _ExportAction.shareText,
          child: ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(l10n.exportShareSetListText),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (danceFor != null)
          PopupMenuItem<_ExportAction>(
            value: _ExportAction.shareBundle,
            child: ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(l10n.exportShareProgramBundle),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem<_ExportAction>(
          value: _ExportAction.copyText,
          child: ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: Text(l10n.exportCopySetList),
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
