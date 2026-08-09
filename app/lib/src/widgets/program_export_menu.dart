import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../data/active_dialect_scope.dart';
import '../export/export_labels_l10n.dart';
import '../export/program_pdf.dart';
import '../export/program_share_bundle.dart';
import '../export/share_sanitization.dart';
import '../search/facet_labels.dart'
    show danceLevelLabel, danceStatusLabel, formationLabel;
import '../utils/safe_name.dart';
import 'venue_contact_share_dialog.dart';

/// Actions offered by the [ProgramExportMenu].
enum _ExportAction { shareText, shareBundle, copyText, shareJson, pdf }

enum _ProgramExportContent { setListOnly, setListWithFigures }

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
/// Renders a [PopupMenuButton] (icon + tooltip "Export") with these actions:
/// - **Share set list (text)** — the emailable plain-text set list, via the OS
///   share sheet (`share_plus`, text sharing is supported on all platforms).
/// - **Share (program + dances)** — the self-contained `.ccshare` bundle, which
///   the recipient's copy of the app opens directly.
/// - **Copy set list** — copies the set-list text to the clipboard; an
///   always-available fallback where a share target is unavailable.
/// - **Export as JSON** — the *same* bundle payload named `.json` (issue #853),
///   for a recipient without the app, an email attachment, or plain inspection.
/// - **Export / print PDF** — hands a generated PDF to the OS print/save dialog
///   (`printing`, all platforms including Linux).
///
/// The two file actions are gated on [danceFor]: without a dance resolver there
/// is nothing to embed.
///
/// Titles for dance slots are resolved through [titleFor]; the event date is
/// formatted with the ambient [MaterialLocalizations].
class ProgramExportMenu extends StatelessWidget {
  const ProgramExportMenu({
    super.key,
    required this.program,
    required this.titleFor,
    this.venuesById = const {},
    this.danceFor,
    this.choreographerFor,
    this.shareInvoker,
    this.bundleFileWriter,
    this.pdfLayouter,
  });

  final Program program;
  final String? Function(String danceId) titleFor;

  /// Loaded venue records keyed by id, so a program that links a reusable
  /// [Venue] ([Program.venueId]) exports that venue's display label (and, in
  /// the PDF, its richer detail block) instead of the free-text [Program.venue].
  /// Only the linked venue need be present; defaults to empty, which preserves
  /// the free-text-only export behavior.
  final Map<String, Venue> venuesById;

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

  /// Resolves a linked venue's display label for the **text** exports.
  ///
  /// [Venue.displayName] is `name, address1, city, stateProv, country`, so
  /// reading it straight off the stored record would put the venue's postal
  /// address — seven fields classified [EgressClass.deviceLocal] — into the
  /// shared/copied set list. The venue is therefore routed through
  /// [sanitizeVenueForShare] first, exactly as the bundle and PDF paths do, and
  /// the label collapses to the venue's public name (issue #853).
  ///
  /// No `include` set is threaded through: the six opt-in contact fields are
  /// not part of `displayName`, so there is nothing here for the consent dialog
  /// to grant, and the text export never prompts.
  String? _venueNameFor(String venueId) {
    final venue = venuesById[venueId];
    return venue == null ? null : sanitizeVenueForShare(venue).displayName;
  }

  String _plainText(BuildContext context) => programToPlainText(
    program,
    titleFor: titleFor,
    venueNameFor: _venueNameFor,
    formatDate: (d) => _formatDate(context, d),
    labels: programExportLabels(AppLocalizations.of(context)),
  );

  String _plainTextWithFigures(BuildContext context) {
    final cards = _danceCardsPlainText(context);
    if (cards.isEmpty) return _plainText(context);
    return '${_plainText(context)}\n\n${cards.join('\n\n')}';
  }

  Iterable<ProgramSlot> _outputSlots() sync* {
    for (final group in program.outputGrouped) {
      yield group.primary;
      yield* group.alternates;
    }
  }

  List<Dance> _orderedExportDances() {
    final resolveDance = danceFor;
    if (resolveDance == null) return const [];
    final seen = <String>{};
    final resolved = <Dance>[];
    for (final slot in _outputSlots()) {
      final id = slot.danceId;
      if (id == null || !seen.add(id)) continue;
      final dance = resolveDance(id);
      if (dance != null) resolved.add(dance);
    }
    return resolved;
  }

  String? _danceLevelLabel(AppLocalizations l10n, Dance dance) {
    final base = dance.level == null ? null : danceLevelLabel(l10n, dance.level!);
    if (base != null) {
      return dance.mixedLevel ? l10n.exportLevelWithMixed(base) : base;
    }
    return dance.mixedLevel ? l10n.exportLevelMixedOnly : null;
  }

  List<String> _danceCardsPlainText(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dialect =
        context.dependOnInheritedWidgetOfExactType<ActiveDialectScope>()
            ?.notifier
            ?.value ??
        Dialect.larksRobins;
    final labels = danceExportLabels(l10n);
    final resolveChoreographer = choreographerFor ?? (_) => null;
    return [
      for (final dance in _orderedExportDances())
        danceToPlainText(
          dance,
          dialect: dialect,
          authorNames: [
            for (final id in dance.authorIds)
              if (resolveChoreographer(id)?.name case final String name
                  when name.trim().isNotEmpty)
                name.trim(),
          ],
          formationLabel: formationLabel(l10n, dance.formation),
          levelLabel: _danceLevelLabel(l10n, dance),
          statusLabel: danceStatusLabel(l10n, dance.status),
          labels: labels,
        ),
    ];
  }

  Future<_ProgramExportContent?> _chooseProgramExportContent(
    BuildContext context,
  ) async {
    if (_orderedExportDances().isEmpty) return _ProgramExportContent.setListOnly;
    return showDialog<_ProgramExportContent>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('program-export-content-dialog'),
        title: const Text('What should this include?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(_ProgramExportContent.setListOnly),
            child: const Text('Set list only'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(_ProgramExportContent.setListWithFigures),
            child: const Text('Set list + figures'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareText(BuildContext context, Rect? origin) async {
    final content = await _chooseProgramExportContent(context);
    if (content == null) return;
    if (!context.mounted) return;
    final share = shareInvoker ?? SharePlus.instance.share;
    await share(
      ShareParams(
        text: content == _ProgramExportContent.setListWithFigures
            ? _plainTextWithFigures(context)
            : _plainText(context),
        subject: program.title,
        sharePositionOrigin: origin,
      ),
    );
  }

  /// Resolves the linked venue's contact-PII consent before an export flow.
  ///
  /// Returns the empty set (**proceed, no prompt**) when the program links no
  /// venue, or the venue has no populated contact fields — there is no contact
  /// PII to leak. Otherwise it shows the shared [VenueContactShareDialog] (rows
  /// unchecked by default) and returns the user's affirmative selection. A
  /// `null` result means the user cancelled/dismissed and the caller MUST
  /// **abort** the export (nothing shared or written). Shared by the
  /// share-bundle and PDF-export paths so both gate PII identically.
  Future<Set<VenueContactField>?> _venueContactConsent(
    BuildContext context,
  ) async {
    final venueId = program.venueId;
    final linkedVenue = venueId == null ? null : venuesById[venueId];
    if (linkedVenue == null ||
        populatedVenueContactFields(linkedVenue).isEmpty) {
      return const <VenueContactField>{};
    }
    return VenueContactShareDialog.show(context, venue: linkedVenue);
  }

  /// Writes a self-contained program-plus-referenced-dances bundle (the
  /// canonical [CompendiumArchive] JSON — see [buildProgramShareBundle]) to a
  /// temp file and hands it to the OS share sheet as a JSON [XFile].
  ///
  /// Serves **both** file-share actions. [extension] is the only difference
  /// between them: `.ccshare` (the default) binds the file to the app's
  /// exported UTI so a recipient's device opens it here, while `.json`
  /// (issue #853) leaves it a generic document for a recipient without the app,
  /// an email attachment, or plain inspection. The payload is byte-identical —
  /// there is deliberately no second encoder, so the two can never drift.
  ///
  /// The bundle *carries* the program plus the full definition of every dance
  /// its slots reference, and the receive side imports both.
  Future<void> _shareBundle(
    BuildContext context,
    Rect? origin, {
    String extension = programShareBundleExtension,
  }) async {
    final resolveDance = danceFor;
    if (resolveDance == null) return;

    // Gather the linked venue's contact-PII consent before building the bundle.
    // Contact fields are omit-by-default; a cancelled/dismissed dialog aborts
    // the share entirely (nothing leaves the device).
    final includeVenueContact = await _venueContactConsent(context);
    if (includeVenueContact == null) return;
    if (!context.mounted) return;

    final json = buildProgramShareBundle(
      program,
      danceFor: resolveDance,
      choreographerFor: choreographerFor ?? (_) => null,
      venueFor: (id) => venuesById[id],
      includeVenueContact: includeVenueContact,
    );
    final fileName = programShareBundleFileName(
      program.title,
      extension: extension,
    );

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
    final content = await _chooseProgramExportContent(context);
    if (content == null) return;
    if (!context.mounted) return;

    final localizations = MaterialLocalizations.of(context);
    final labels = programExportLabels(AppLocalizations.of(context));

    // Gate the venue's contact PII behind the same consent dialog the share
    // path uses. Contact fields are omit-by-default; a cancelled/dismissed
    // dialog aborts the export (no PDF is generated).
    final includeVenueContact = await _venueContactConsent(context);
    if (includeVenueContact == null) return;
    if (!context.mounted) return;

    // Feed the PDF builder a venue already run through the single
    // `sanitizeVenueForShare` primitive, so un-consented contact fields are
    // physically absent — the renderer never needs its own redaction.
    final venuesForPdf = venuesWithSanitizedContact(
      venuesById,
      program.venueId,
      include: includeVenueContact,
    );

    final layoutPdf = pdfLayouter ?? Printing.layoutPdf;
    final danceCards = content == _ProgramExportContent.setListWithFigures
        ? _danceCardsPlainText(context)
        : const <String>[];
    await layoutPdf(
      name: sanitizeExportName(program.title, fallback: 'program'),
      onLayout: (format) => buildProgramPdf(
        program,
        titleFor: titleFor,
        venuesById: venuesForPdf,
        formatDate: localizations.formatMediumDate,
        labels: labels,
        danceCards: danceCards,
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
          () => _shareBundle(context, origin),
        );
      case _ExportAction.copyText:
        await _copyText(context);
      case _ExportAction.shareJson:
        await _guard(
          messenger,
          l10n.exportShareProgramError,
          () => _shareBundle(
            context,
            origin,
            extension: programShareJsonExtension,
          ),
        );
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
        // Sits between "Copy set list" and "Export / print PDF" (issue #853).
        // Gated on `danceFor` for the same reason as the bundle action above:
        // without a dance resolver there is nothing to embed.
        if (danceFor != null)
          PopupMenuItem<_ExportAction>(
            value: _ExportAction.shareJson,
            child: ListTile(
              leading: const Icon(Icons.data_object_outlined),
              title: Text(l10n.exportShareProgramJson),
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
