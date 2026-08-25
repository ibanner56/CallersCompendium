import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/callersbox_online.dart';
import '../data/contradb_online.dart';
import '../data/dance_reimport.dart';
import '../data/import_error_labels.dart';
import '../data/import_io.dart';
import '../data/online_search.dart';
import '../data/online_search_labels.dart';
import '../data/repositories_scope.dart';
import '../diagnostics/error_log.dart';
import '../search/dance_detail_data.dart';
import '../theme/app_spacing.dart';
import '../widgets/brand_mark.dart';
import '../published_collections/published_collection_service.dart';
import 'dance_detail_screen.dart';
import 'dance_list_screen.dart';
import 'dance_reimport_flow.dart';
import 'custom_fields_screen.dart';
import 'import_review_screen.dart';
import 'online_import_variation_dialog.dart';
import 'recently_deleted_screen.dart';

/// Responsive collection shell (`docs/design/ux.md` — list/detail split pane
/// for desktop/tablet; `docs/ROADMAP.md` deferred follow-up
/// `defer-editor-splitpane`).
///
/// **Breakpoint: 900 logical pixels wide.**
/// - **Narrow (< 900 px):** renders [DanceListScreen] directly, preserving the
///   existing push-navigation to [DanceDetailScreen]. No behaviour change on
///   phones or narrow tablet portrait.
/// - **Wide (≥ 900 px):** renders a master-detail [Row]:
///   - *List pane* (fixed 400 px): [DanceListScreen] with [onSelectDance] wired
///     to update the detail pane, and the currently selected row highlighted.
///   - *Detail pane* (flexible remaining space): the selected
///     [DanceDetailScreen]; or an empty-state placeholder when nothing is
///     selected yet.
///
/// Deletion from the detail pane (via [DanceDetailScreen.onDeleted]) refreshes
/// the list and clears the selection back to the empty-state placeholder.
/// Undo-restore (via [DanceDetailScreen.onRestored]) refreshes the list without
/// clearing the selection so the restored dance is visible again.
/// Duplication (via [DanceDetailScreen.onNavigateTo]) refreshes the list and
/// switches the selection to the new copy's id.
class CollectionShell extends StatefulWidget {
  const CollectionShell({
    super.key,
    this.importPicker,
    this.urlFetcher,
    this.importSources,
    this.publishedCollectionService,
    this.callersBoxOnline,
    this.contraDbOnline,
  });

  /// Test seam for choosing an import file; forwarded to [ImportReviewScreen].
  /// Defaults to [pickImportFile] (native open-file dialog) when null.
  final ImportPicker? importPicker;

  /// Test seam for fetching an import URL; forwarded to [ImportReviewScreen].
  /// Defaults to [fetchImportUrl] (real HTTP GET) when null.
  final UrlFetcher? urlFetcher;

  /// Override for the selectable import sources; defaults to
  /// [defaultImportSources]. Exists so widget tests can inject a trimmed or
  /// fake source list without real file-picking / network.
  final List<ImportSource>? importSources;

  /// Test seam for the signed catalog shown inside Collection import.
  final PublishedCollectionService? publishedCollectionService;

  /// The Caller's Box online service, shared by the list pane and the
  /// detail-pane preview. Injected in tests with a seam-backed instance;
  /// defaults to a network-backed [CallersBoxOnline].
  final CallersBoxOnline? callersBoxOnline;

  /// The ContraDB online service, shared by the list pane and the detail-pane
  /// preview. Injected in tests with a seam-backed instance; defaults to a
  /// network-backed [ContraDbOnline].
  final ContraDbOnline? contraDbOnline;

  /// Breakpoint (logical pixels) at which the split-pane layout activates.
  static const double splitBreakpoint = 900;

  /// Fixed width (logical pixels) of the list pane in split mode.
  static const double listPaneWidth = 400;

  @override
  State<CollectionShell> createState() => _CollectionShellState();
}

class _CollectionShellState extends State<CollectionShell> {
  String? _selectedDanceId;

  /// Which non-dance view (if any) the wide-layout detail pane currently shows,
  /// instead of a [DanceDetailScreen] / the empty placeholder. The states are
  /// mutually exclusive: opening one clears the others. When [_DetailMode.none],
  /// the pane shows the selected dance (or the empty placeholder). Generalizes
  /// the earlier `_showImport` bool so the online preview is a first-class third
  /// state.
  _DetailMode _detailMode = _DetailMode.none;

  /// The import sources, resolved once and cached for the lifetime of this
  /// state. [defaultImportSources] builds fresh [ImportSource] instances on
  /// every call and [ImportSource] uses identity equality, so rebuilding the
  /// list on each access would make the embedded [ImportReviewScreen]'s
  /// [DropdownButton] assert (its selected value would no longer match any item
  /// instance in a freshly-built list).
  late final List<ImportSource> _importSources =
      widget.importSources ?? defaultImportSources();

  late final CallersBoxOnline _callersBox =
      widget.callersBoxOnline ?? CallersBoxOnline();
  late final ContraDbOnline _contraDb =
      widget.contraDbOnline ?? ContraDbOnline();
  late final PublishedCollectionService _publishedCollectionService =
      widget.publishedCollectionService ?? PublishedCollectionService();

  /// Resolves the online service for a given [source], so a tapped result / its
  /// preview is loaded and imported through the source it came from.
  OnlineSearchService _serviceFor(OnlineSource source) =>
      source == OnlineSource.contraDb ? _contraDb : _callersBox;

  /// Messenger for the detail pane. Snackbars from the online Import button must
  /// be shown here (not via the shell's own context, which sits above the two
  /// per-pane [ScaffoldMessenger]s and would find no Scaffold to attach to).
  final _detailMessengerKey = GlobalKey<ScaffoldMessengerState>();

  /// Identifies the single logical [DanceListScreen] across both
  /// [LayoutBuilder] branches (the narrow branch vs `_buildSplitPane`).
  ///
  /// Those branches place the list at structurally different tree positions
  /// (bare vs nested in `Row > SizedBox > ScaffoldMessenger`), so without a
  /// stable key Flutter treats a breakpoint crossing (e.g. a tablet rotation)
  /// as removing one Element and inserting a different one — discarding the
  /// list's State (its sort choice, search text, facets, and scroll position)
  /// even though it is logically the same screen (issue #895). A [GlobalKey]
  /// on the same widget in both branches makes Flutter *move* the existing
  /// Element (and its State) to the new position instead, mirroring
  /// [_detailMessengerKey] above.
  final _listKey = GlobalKey();
  final _importReviewKey = GlobalKey();

  /// The currently previewed online dance in the detail pane, plus its
  /// loading/error state. Meaningful only while [_detailMode] is
  /// [_DetailMode.onlinePreview].
  OnlinePreview? _onlinePreview;
  bool _onlinePreviewLoading = false;
  String? _onlinePreviewError;
  int _onlineSeq = 0;

  /// Guards the direct-import commit so a rapid double-tap (or re-tap) of the
  /// preview Import button cannot commit the same plan twice.
  bool _importing = false;
  bool _importCommitInFlight = false;
  String? _reimportTargetId;
  DateTime? _reimportTargetUpdatedAt;
  DanceDetailData? _reimportPreview;

  void _onSelectDance(String danceId) {
    if (_importCommitInFlight) return;
    setState(() {
      _selectedDanceId = danceId;
      // A fresh local selection exits import mode and clears any online preview.
      _detailMode = _DetailMode.none;
      _clearOnlinePreview();
    });
  }

  /// Called after a successful new-dance save. Selects the new dance so the
  /// detail pane shows it immediately. Delegates to [_onSelectDance]: creating
  /// a dance is a local selection and carries the same contract — exits import
  /// mode, clears any online preview. It broadcasts nothing and reloads
  /// nothing: both panes read the database directly, so the save reaches them
  /// on its own.
  void _onNewDance(String danceId) => _onSelectDance(danceId);

  /// Wide layout: swap the detail pane over to the embedded import view.
  void _onImport() {
    setState(() {
      _detailMode = _DetailMode.importReview;
      _clearOnlinePreview();
    });
  }

  /// Wide layout: leave the embedded import view, returning to the previously
  /// selected dance (or the empty placeholder).
  void _onImportClose() {
    setState(() => _detailMode = _DetailMode.none);
  }

  /// Narrow layout: push the import view as a full-screen route (it has its own
  /// Scaffold/AppBar). Mirrors how detail uses push-nav on narrow.
  void _pushImportRoute() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImportReviewScreen(
          sources: _importSources,
          picker: widget.importPicker,
          fetcher: widget.urlFetcher,
          publishedCollectionService: _publishedCollectionService,
        ),
      ),
    );
  }

  void _onCustomFields() {
    if (_importCommitInFlight) return;
    setState(() {
      _detailMode = _DetailMode.customFields;
      _clearOnlinePreview();
    });
  }

  void _onRecentlyDeleted() {
    if (_importCommitInFlight) return;
    setState(() {
      _detailMode = _DetailMode.recentlyDeleted;
      _clearOnlinePreview();
    });
  }

  void _onDetailModeClose() {
    setState(() => _detailMode = _DetailMode.none);
  }

  /// Resets the online-preview sub-state. Call when leaving the online preview.
  void _clearOnlinePreview() {
    _onlinePreview = null;
    _onlinePreviewLoading = false;
    _onlinePreviewError = null;
    _reimportTargetId = null;
    _reimportTargetUpdatedAt = null;
    _reimportPreview = null;
  }

  Future<void> _beginReimport(DanceDetailData detail) async {
    final messenger = _detailMessengerKey.currentState;
    try {
      final preview = await selectReimportDance(
        context,
        target: detail.dance,
        callersBox: _callersBox,
        contraDb: _contraDb,
        picker: widget.importPicker ?? pickImportFile,
      );
      if (!mounted || preview == null) return;
      setState(() {
        _reimportTargetId = detail.dance.id;
        _reimportTargetUpdatedAt = detail.dance.updatedAt;
        _reimportPreview = preview;
        _onlinePreview = null;
        _onlinePreviewLoading = false;
        _onlinePreviewError = null;
        _detailMode = _DetailMode.onlinePreview;
      });
    } on DanceReimportJsonException catch (error) {
      logCaughtErrorTypeOnly(
        error,
        StackTrace.current,
        source: 'collection_shell._beginReimport',
      );
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            error.programBearing
                ? AppLocalizations.of(context).danceReimportProgramArchive
                : AppLocalizations.of(context).danceReimportInvalidJson,
          ),
        ),
      );
    } catch (error, stackTrace) {
      logCaughtErrorTypeOnly(
        error,
        stackTrace,
        source: 'collection_shell._beginReimport',
      );
      messenger?.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).danceReimportSourceFailed),
        ),
      );
    }
  }

  Future<void> _commitReimport(DanceDetailData preview) async {
    final target = _reimportTargetId;
    final expectedUpdatedAt = _reimportTargetUpdatedAt;
    if (_importing || target == null || expectedUpdatedAt == null) return;
    _importing = true;
    try {
      final result = await replaceDanceChoreography(
        RepositoriesScope.of(context),
        targetDanceId: target,
        incoming: preview.dance,
        expectedUpdatedAt: expectedUpdatedAt,
      );
      if (!mounted) return;
      if (result == DanceReimportResult.replaced) {
        setState(() {
          _selectedDanceId = target;
          _detailMode = _DetailMode.none;
          _onlinePreview = null;
          _onlinePreviewLoading = false;
          _onlinePreviewError = null;
          _reimportTargetId = null;
          _reimportTargetUpdatedAt = null;
          _reimportPreview = null;
        });
        _detailMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).danceReimported)),
        );
      } else {
        _detailMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              result == DanceReimportResult.targetMissing
                  ? AppLocalizations.of(context).danceReimportTargetMissing
                  : AppLocalizations.of(context).danceReimportTargetChanged,
            ),
          ),
        );
      }
    } catch (error, stackTrace) {
      logCaughtErrorTypeOnly(
        error,
        stackTrace,
        source: 'collection_shell._commitReimport',
      );
      if (mounted) {
        _detailMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).danceReimportSourceFailed,
            ),
          ),
        );
      }
    } finally {
      _importing = false;
    }
  }

  /// Fetches the tapped online result's full record and shows it in the detail
  /// pane. Guarded by a sequence number so a slow fetch can't overwrite a newer
  /// selection.
  Future<void> _onSelectOnlineDance(OnlineSearchResultRow result) async {
    if (_importCommitInFlight) return;
    final repos = RepositoriesScope.of(context);
    final l10n = AppLocalizations.of(context);
    final seq = ++_onlineSeq;
    setState(() {
      _selectedDanceId = null;
      _detailMode = _DetailMode.onlinePreview;
      _onlinePreview = null;
      _onlinePreviewError = null;
      _onlinePreviewLoading = true;
    });
    try {
      final preview = await _serviceFor(
        result.source,
      ).loadPreview(repos, result);
      if (!mounted || seq != _onlineSeq) return;
      setState(() {
        _onlinePreview = preview;
        _onlinePreviewLoading = false;
      });
    } on UrlFetchException catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'collection_shell._onSelectOnlineDance',
      );
      if (!mounted || seq != _onlineSeq) return;
      setState(() {
        _onlinePreviewError = importErrorMessage(l10n, error);
        _onlinePreviewLoading = false;
      });
    } catch (error, stackTrace) {
      logCaughtErrorTypeOnly(
        error,
        stackTrace,
        source: 'collection_shell._onSelectOnlineDance',
      );
      if (!mounted || seq != _onlineSeq) return;
      setState(() {
        _onlinePreviewError = l10n.onlineLoadError(result.source.label);
        _onlinePreviewLoading = false;
      });
    }
  }

  /// Directly imports the previewed online dance into the local collection
  /// (dedup-aware) and, on success, lands the user on the now-persisted dance in
  /// the detail pane (a full [DanceDetailScreen], not the preview) so they need
  /// not hunt for it in the list. An exact re-import opens the existing matching
  /// dance when its id is known. Reports the outcome via a detail-pane snackbar.
  ///
  /// Navigating away from the preview also removes its Import button, so the
  /// commit can't be repeated; an [_importing] guard additionally blocks a rapid
  /// double-tap before the first commit resolves.
  Future<void> _importOnline(OnlinePreview preview) async {
    if (_importing) return;
    _importing = true;
    final messenger = _detailMessengerKey.currentState;
    final repos = RepositoriesScope.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      final service = _serviceFor(preview.result.source);
      var result = await service.import(repos, preview.plan);
      if (result.kind == OnlineImportKind.needsConfirmation) {
        if (!mounted) return;
        final existingId = result.danceId;
        // needsConfirmation requires a candidate id — a null here is a service
        // bug. Assert in debug; silently cancel in release (better than crashing).
        assert(
          existingId != null,
          'needsConfirmation must carry an existing dance id',
        );
        if (existingId == null) return;
        final existingTitle =
            (await repos.dances.getById(existingId))?.title ?? result.title;
        if (!mounted) return;
        final resolution = await showOnlineImportVariationDialog(
          context,
          l10n,
          existingTitle: existingTitle,
          existingId: existingId,
        );
        if (resolution == null || !mounted) return; // user cancelled
        result = await service.import(
          repos,
          preview.plan,
          ambiguousResolution: resolution,
        );
      } else if (result.kind == OnlineImportKind.needsConfirmationIdentical) {
        if (!mounted) return;
        final existingId = result.danceId;
        // needsConfirmationIdentical requires a candidate id — a null here is a
        // service bug. Assert in debug; silently cancel in release.
        assert(
          existingId != null,
          'needsConfirmationIdentical must carry an existing dance id',
        );
        if (existingId == null) return;
        final existingTitle =
            (await repos.dances.getById(existingId))?.title ?? result.title;
        if (!mounted) return;
        final resolution = await showOnlineImportCrossSourceDuplicateDialog(
          context,
          l10n,
          existingTitle: existingTitle,
          existingId: existingId,
        );
        if (resolution == null || !mounted) return; // user cancelled
        result = await service.import(
          repos,
          preview.plan,
          ambiguousResolution: resolution,
        );
      }
      if (!mounted) return;
      final danceId = result.danceId;
      // Land on the imported dance ONLY for a single-dance import. This online
      // path is single-dance by construction; the explicit count guard ensures
      // the auto-open can never fire for a multi-dance result (those go through
      // ImportReviewScreen, which keeps its result summary + Done affordance).
      if (result.danceCount == 1 && danceId != null) {
        setState(() {
          _selectedDanceId = danceId;
          _detailMode = _DetailMode.none;
          _clearOnlinePreview();
        });
      }
      messenger?.showSnackBar(
        SnackBar(
          key: const ValueKey('online-import-snackbar'),
          content: Text(onlineImportMessage(l10n, result)),
        ),
      );
    } on UrlFetchException catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'collection_shell._importOnline',
      );
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text(importErrorMessage(l10n, error))),
      );
    } catch (error, stackTrace) {
      logCaughtErrorTypeOnly(
        error,
        stackTrace,
        source: 'collection_shell._importOnline',
      );
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text(l10n.onlineImportError)));
    } finally {
      _importing = false;
    }
  }

  /// Called by the embedded [DanceDetailScreen] after a successful soft-delete.
  /// Clears the selection; the list removes the dance from its own stream.
  void _onDetailDeleted() {
    setState(() => _selectedDanceId = null);
  }

  /// Called by the embedded [DanceDetailScreen] when the Undo snackbar restores
  /// a dance.
  ///
  /// Now a no-op, and deliberately kept rather than removed from
  /// [DanceDetailScreen]'s contract: the restore is a database write, so the
  /// list's stream reinstates the row without being told. The callback stays
  /// because the detail screen has no other way to say "I restored something"
  /// and a future consumer may need to know.
  void _onDetailRestored() {}

  /// Called by the embedded [DanceDetailScreen] after duplication.
  /// Selects the new id; the copy reaches the list through its own stream.
  void _onNavigateTo(String danceId) {
    setState(() {
      _selectedDanceId = danceId;
      _detailMode = _DetailMode.none;
      _clearOnlinePreview();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= CollectionShell.splitBreakpoint) {
          return _buildSplitPane();
        }
        // Narrow: standard single-pane list with existing push navigation.
        // Import pushes its own full-screen route (there is no detail pane); the
        // list likewise pushes its own preview route for online results (its
        // onSelectOnlineDance is left null), sharing the online service so the
        // same seam is used in tests.
        if (_detailMode != _DetailMode.none &&
            _detailMode != _DetailMode.onlinePreview) {
          // Keep an active detail mode mounted across a breakpoint change.
          // Embedded screens own their transient state, so replacing one with
          // the narrow list would discard its current context.
          return _buildDetailPane();
        }
        return DanceListScreen(
          key: _listKey,
          onImport: _pushImportRoute,
          callersBoxOnline: _callersBox,
          contraDbOnline: _contraDb,
        );
      },
    );
  }

  Widget _buildSplitPane() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Each pane gets its own ScaffoldMessenger so snackbars from the list
        // (e.g. swipe-to-delete) and the detail pane (delete/undo/import) appear
        // in the correct pane and are never duplicated across both.
        SizedBox(
          width: CollectionShell.listPaneWidth,
          child: ScaffoldMessenger(
            child: DanceListScreen(
              key: _listKey,
              onSelectDance: _onSelectDance,
              onNewDance: _onNewDance,
              selectedDanceId: _selectedDanceId,
              onImport: _onImport,
              onCustomFields: _onCustomFields,
              onRecentlyDeleted: _onRecentlyDeleted,
              compactActions: true,
              onSelectOnlineDance: _onSelectOnlineDance,
              selectedOnlineId: _onlinePreview?.result.id,
              callersBoxOnline: _callersBox,
              contraDbOnline: _contraDb,
            ),
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: ScaffoldMessenger(
            key: _detailMessengerKey,
            child: _buildDetailPane(),
          ),
        ),
      ],
    );
  }

  /// The wide-layout detail pane. Shows, in precedence order: the online preview
  /// (with its loading/error sub-states) when [_detailMode] is
  /// [_DetailMode.onlinePreview]; the embedded import review when
  /// [_DetailMode.importReview]; otherwise the selected [DanceDetailScreen], or
  /// the empty-state placeholder when nothing is selected.
  Widget _buildDetailPane() {
    switch (_detailMode) {
      case _DetailMode.onlinePreview:
        {
          if (_onlinePreviewLoading) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(
                  key: ValueKey('online-preview-loading'),
                ),
              ),
            );
          }
          if (_onlinePreviewError != null) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    _onlinePreviewError!,
                    key: const ValueKey('online-preview-error'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          }
          final preview = _onlinePreview;
          final reimportPreview = _reimportPreview;
          if (reimportPreview != null) {
            return DanceDetailScreen.preview(
              key: ValueKey('reimport-preview-${_reimportTargetId!}'),
              data: reimportPreview,
              onImport: () => _commitReimport(reimportPreview),
            );
          }
          if (preview != null) {
            return DanceDetailScreen.preview(
              key: ValueKey('online-preview-${preview.result.id}'),
              data: preview.detail,
              onImport: () => _importOnline(preview),
            );
          }
        }
        // No explicit fall-through in Dart 3; an empty preview state falls out
        // of the switch to the selected-dance / empty-pane logic below.
        break;
      case _DetailMode.importReview:
        return ImportReviewScreen(
          // GlobalKey preserves the review when a responsive layout moves it
          // between the split detail pane and the narrow surface.
          key: _importReviewKey,
          sources: _importSources,
          picker: widget.importPicker,
          fetcher: widget.urlFetcher,
          publishedCollectionService: _publishedCollectionService,
          onClose: _onImportClose,
          onCommitStateChanged: (active) {
            _importCommitInFlight = active;
          },
        );
      case _DetailMode.customFields:
        return CustomFieldsScreen(onClose: _onDetailModeClose);
      case _DetailMode.recentlyDeleted:
        return RecentlyDeletedScreen.dances(onClose: _onDetailModeClose);
      case _DetailMode.none:
        break;
    }
    final selectedId = _selectedDanceId;
    if (selectedId != null) {
      return DanceDetailScreen(
        // Keyed on the dance id so the pane fully resets when the selection
        // changes — a fresh subscription, and a clean canonical/dialect
        // toggle. Note the key changes only with the *selection*: an edit to
        // the dance already shown does not re-create this pane, so nothing
        // here carries that edit into it. What does is the pane's own watch on
        // the database (#768); this key is why it needs one.
        key: ValueKey('detail-$selectedId'),
        danceId: selectedId,
        onDeleted: _onDetailDeleted,
        onRestored: _onDetailRestored,
        onNavigateTo: _onNavigateTo,
        onReimport: _beginReimport,
      );
    }
    return const _EmptyDetailPane();
  }
}

/// The mutually-exclusive non-dance views the wide-layout detail pane can show.
/// [none] means the pane shows the selected dance (or the empty placeholder).
enum _DetailMode {
  none,
  importReview,
  onlinePreview,
  customFields,
  recentlyDeleted,
}

/// Placeholder shown in the detail pane before the user selects a dance.
class _EmptyDetailPane extends StatelessWidget {
  const _EmptyDetailPane();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.collectionSplitEmptyTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.collectionSplitEmptySubtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                // Body text must clear the 4.5:1 WCAG AA threshold, so it uses
                // onSurfaceVariant (a text role) rather than outlineVariant (a
                // hairline/border role that falls below AA against the pane).
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
