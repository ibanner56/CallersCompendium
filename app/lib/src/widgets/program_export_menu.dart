import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

export '../export/share_file.dart';

import '../../l10n/app_localizations.dart';
import '../data/active_dialect_scope.dart';
import '../diagnostics/error_log.dart';
import '../export/export_labels_l10n.dart';
import '../export/program_pdf.dart';
import '../export/program_share_bundle.dart';
import '../export/json_export.dart';
import '../export/share_sanitization.dart';
import '../export/share_file.dart';
import '../search/facet_labels.dart';
import '../utils/safe_name.dart';
import 'program_figures_prompt_dialog.dart';
import 'venue_contact_share_dialog.dart';

/// Actions offered by the [ProgramExportMenu].
enum _ExportAction { shareText, shareBundle, copyText, shareJson, pdf }

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
    this.jsonExportDelivery,
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

  /// Shared JSON delivery seam. When absent, the legacy share/file seams above
  /// are used for Share while Save, Copy, and the choice dialog use defaults.
  final JsonExportDelivery? jsonExportDelivery;

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

  /// Walks [program.outputGrouped] and yields every primary and alternate dance
  /// that can be resolved via [danceFor], in slot order, deduped by dance id.
  /// Alternates are tagged `isAlternate: true` so callers can label them.
  ///
  /// Mirrors the approach validated in PR #896 (`_orderedExportDances`), which
  /// reuses the grouped output rather than walking raw slots.
  List<({Dance dance, bool isAlternate})> _orderedExportDances() {
    final resolveDance = danceFor;
    if (resolveDance == null) return const [];
    final seen = <String>{};
    final result = <({Dance dance, bool isAlternate})>[];
    for (final group in program.outputGrouped) {
      final primaryId = group.primary.danceId;
      if (primaryId != null && seen.add(primaryId)) {
        final dance = resolveDance(primaryId);
        if (dance != null) result.add((dance: dance, isAlternate: false));
      }
      for (final alt in group.alternates) {
        final altId = alt.danceId;
        if (altId != null && seen.add(altId)) {
          final dance = resolveDance(altId);
          if (dance != null) result.add((dance: dance, isAlternate: true));
        }
      }
    }
    return result;
  }

  /// Returns `true` if any dance reachable via [danceFor] in this program has
  /// at least one figure. When `false` the "Include figures?" prompt is skipped
  /// and all text/PDF paths proceed as set-list-only.
  bool _hasFigures() =>
      _orderedExportDances().any((e) => e.dance.figures.isNotEmpty);

  /// Asks whether to include figures in the current export.
  ///
  /// Returns `null` when the user cancels/dismisses (the caller MUST abort),
  /// `false` for "Set list only", `true` for "Set list and figures". When no
  /// figures are available the prompt is skipped and `false` is returned
  /// immediately.
  Future<bool?> _figuresConsent(BuildContext context) async {
    if (!_hasFigures()) return false;
    return ProgramFiguresPromptDialog.show(context);
  }

  /// The set-list text with full dance cards appended — one [danceToPlainText]
  /// card per dance (primary then alternates, deduped), each preceded by a
  /// separator line and (for alternates) the "Alternate" label.
  ///
  /// Uses [ActiveDialectScope] for dialect-aware rendering, falling back to
  /// [Dialect.larksRobins] when no scope is mounted (the fallback is reachable
  /// only in tests; in the running app the scope is always provided — ruling 9).
  String _plainTextWithFigures(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final setList = _plainText(context);
    final danceLabels = danceExportLabels(l10n);
    final dialect = ActiveDialectScope.maybeOf(context) ?? Dialect.larksRobins;
    final renderer = FigureRenderer(contraTaxonomy);
    final buf = StringBuffer(setList);
    final alternate = l10n.exportIncludeFiguresAlternate;
    for (final entry in _orderedExportDances()) {
      final dance = entry.dance;
      if (dance.figures.isEmpty) continue;
      buf.writeln();
      // Mark alternates on the separator line so the title from
      // danceToPlainText appears exactly once (ruling 8: mark, not duplicate).
      buf.writeln(entry.isAlternate ? '--- $alternate' : '---');
      // Resolve metadata for the full dance card (ruling 6).
      // authorNames: names only via choreographerFor — no deviceLocal fields
      // (email/location/deceased) enter because the API accepts List<String>.
      final authorNames = [
        for (final id in dance.authorIds)
          if (choreographerFor?.call(id)?.name case final String name
              when name.isNotEmpty)
            name,
      ];
      // Level label mirrors the dance_detail_screen pattern.
      final String? levelLabel;
      if (dance.level != null) {
        final base = danceLevelLabel(l10n, dance.level!);
        levelLabel = dance.mixedLevel ? l10n.exportLevelWithMixed(base) : base;
      } else {
        levelLabel = dance.mixedLevel ? l10n.exportLevelMixedOnly : null;
      }
      buf.writeln(
        danceToPlainText(
          dance,
          authorNames: authorNames,
          formationLabel: formationLabel(l10n, dance.formation),
          levelLabel: levelLabel,
          statusLabel: danceStatusLabel(l10n, dance.status),
          dialect: dialect,
          renderer: renderer,
          labels: danceLabels,
        ),
      );
    }
    return buf.toString();
  }

  Future<void> _shareText(BuildContext context, Rect? origin) async {
    final includeFigures = await _figuresConsent(context);
    if (includeFigures == null) return;
    if (!context.mounted) return;
    final share = shareInvoker ?? SharePlus.instance.share;
    await share(
      ShareParams(
        text: includeFigures
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
    final bundle = await _buildBundle(context, extension: extension);
    if (bundle == null) return;

    final writeFile = bundleFileWriter ?? writeBundleTempFile;
    final xfile = await writeFile(bundle.json, bundle.fileName);

    final share = shareInvoker ?? SharePlus.instance.share;
    await share(
      ShareParams(
        files: [xfile],
        fileNameOverrides: [bundle.fileName],
        subject: program.title,
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<({String json, String fileName})?> _buildBundle(
    BuildContext context, {
    required String extension,
  }) async {
    final resolveDance = danceFor;
    if (resolveDance == null) return null;

    // Gather the linked venue's contact-PII consent before building the bundle.
    // Contact fields are omit-by-default; a cancelled/dismissed dialog aborts
    // the share entirely (nothing leaves the device).
    final includeVenueContact = await _venueContactConsent(context);
    if (includeVenueContact == null) return null;
    if (!context.mounted) return null;

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
    final bundle = await _buildBundle(
      context,
      extension: programShareJsonExtension,
    );
    if (bundle == null || !context.mounted) return;

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
          final message = result.path.isEmpty
              ? l10n.exportJsonSaved(result.fileName)
              : l10n.exportJsonSavedTo(result.fileName, result.path);
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
            subject: program.title,
            sharePositionOrigin: origin,
          );
        });
    }
  }

  Future<void> _copyText(BuildContext context) async {
    final includeFigures = await _figuresConsent(context);
    if (includeFigures == null) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(
      ClipboardData(
        text: includeFigures
            ? _plainTextWithFigures(context)
            : _plainText(context),
      ),
    );
    messenger.showSnackBar(SnackBar(content: Text(l10n.exportSetListCopied)));
  }

  Future<void> _exportPdf(BuildContext context) async {
    final localizations = MaterialLocalizations.of(context);
    final l10n = AppLocalizations.of(context);
    final labels = programExportLabels(l10n);

    // Gate the venue's contact PII behind the same consent dialog the share
    // path uses. Contact fields are omit-by-default; a cancelled/dismissed
    // dialog aborts the export (no PDF is generated).
    final includeVenueContact = await _venueContactConsent(context);
    if (includeVenueContact == null) return;
    if (!context.mounted) return;

    // Ask whether to include figures. Skipped silently when no dance has any.
    final includeFigures = await _figuresConsent(context);
    if (includeFigures == null) return;
    if (!context.mounted) return;

    // Feed the PDF builder a venue already run through the single
    // `sanitizeVenueForShare` primitive, so un-consented contact fields are
    // physically absent — the renderer never needs its own redaction.
    final venuesForPdf = venuesWithSanitizedContact(
      venuesById,
      program.venueId,
      include: includeVenueContact,
    );

    final List<({Dance dance, bool isAlternate})>? appendDances;
    final Dialect? dialect;
    if (includeFigures) {
      appendDances = _orderedExportDances();
      dialect = ActiveDialectScope.maybeOf(context) ?? Dialect.larksRobins;
    } else {
      appendDances = null;
      dialect = null;
    }

    final layoutPdf = pdfLayouter ?? Printing.layoutPdf;
    await layoutPdf(
      name: sanitizeExportName(program.title, fallback: 'program'),
      onLayout: (format) => buildProgramPdf(
        program,
        titleFor: titleFor,
        venuesById: venuesForPdf,
        formatDate: localizations.formatMediumDate,
        labels: labels,
        appendDances: appendDances,
        danceLabels: includeFigures ? danceExportLabels(l10n) : null,
        dialect: dialect,
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
          l10n.exportJsonShareError,
          () => _exportJson(context, origin),
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
      logCaughtError(e, st, source: 'program_export_menu._guard');
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
