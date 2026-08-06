import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/callersbox_online.dart';
import '../data/collection_refresh_scope.dart';
import '../data/contradb_online.dart';
import '../data/import_error_labels.dart';
import '../data/import_io.dart';
import '../data/online_search.dart';
import '../data/online_search_labels.dart';
import '../data/repositories_scope.dart';
import '../theme/app_spacing.dart';
import '../widgets/brand_mark.dart';
import 'dance_detail_screen.dart';
import 'dance_list_screen.dart';
import 'import_review_screen.dart';
import 'online_import_variation_dialog.dart';

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

  /// Incrementing this value triggers [DanceListScreen] to reload via its
  /// [refreshTrigger] parameter.
  final _listRefresh = ValueNotifier<int>(0);

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

  /// Resolves the online service for a given [source], so a tapped result / its
  /// preview is loaded and imported through the source it came from.
  OnlineSearchService _serviceFor(OnlineSource source) =>
      source == OnlineSource.contraDb ? _contraDb : _callersBox;

  /// Messenger for the detail pane. Snackbars from the online Import button must
  /// be shown here (not via the shell's own context, which sits above the two
  /// per-pane [ScaffoldMessenger]s and would find no Scaffold to attach to).
  final _detailMessengerKey = GlobalKey<ScaffoldMessengerState>();

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

  @override
  void dispose() {
    _listRefresh.dispose();
    super.dispose();
  }

  void _onSelectDance(String danceId) {
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
  /// mode, clears any online preview. Does not bump [_listRefresh] directly;
  /// [CollectionRefreshScope.bump] already fires inside the editor on save and
  /// bumping here too would double-load (issue #340). [_onSelectDance] likewise
  /// does not bump [_listRefresh], so delegation is safe.
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
        ),
      ),
    );
  }

  /// Resets the online-preview sub-state. Call when leaving the online preview.
  void _clearOnlinePreview() {
    _onlinePreview = null;
    _onlinePreviewLoading = false;
    _onlinePreviewError = null;
  }

  /// Fetches the tapped online result's full record and shows it in the detail
  /// pane. Guarded by a sequence number so a slow fetch can't overwrite a newer
  /// selection.
  Future<void> _onSelectOnlineDance(OnlineSearchResultRow result) async {
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
    } on UrlFetchException catch (error) {
      if (!mounted || seq != _onlineSeq) return;
      setState(() {
        _onlinePreviewError = importErrorMessage(l10n, error);
        _onlinePreviewLoading = false;
      });
    } catch (_) {
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
      if (result.kind == OnlineImportKind.created) {
        CollectionRefreshScope.bump(context);
        _listRefresh.value++;
      }
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
    } on UrlFetchException catch (error) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text(importErrorMessage(l10n, error))),
      );
    } catch (_) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text(l10n.onlineImportError)));
    } finally {
      _importing = false;
    }
  }

  /// Called by the embedded [DanceDetailScreen] after a successful soft-delete.
  /// Clears the selection and refreshes the list so the deleted dance disappears.
  void _onDetailDeleted() {
    _listRefresh.value++;
    setState(() => _selectedDanceId = null);
  }

  /// Called by the embedded [DanceDetailScreen] when the Undo snackbar restores
  /// a dance.  Refreshes the list so the dance reappears; keeps the selection.
  void _onDetailRestored() {
    _listRefresh.value++;
  }

  /// Called by the embedded [DanceDetailScreen] after duplication.
  /// Refreshes the list (so the copy appears) and selects the new id.
  void _onNavigateTo(String danceId) {
    _listRefresh.value++;
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
        return DanceListScreen(
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
              onSelectDance: _onSelectDance,
              onNewDance: _onNewDance,
              selectedDanceId: _selectedDanceId,
              refreshTrigger: _listRefresh,
              onImport: _onImport,
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
          // Keyed so switching in/out of import mode fully resets the flow.
          key: const ValueKey('collection-import'),
          sources: _importSources,
          picker: widget.importPicker,
          fetcher: widget.urlFetcher,
          onClose: _onImportClose,
        );
      case _DetailMode.none:
        break;
    }
    final selectedId = _selectedDanceId;
    if (selectedId != null) {
      return DanceDetailScreen(
        // Keyed on the dance id so the screen fully resets when the
        // selection changes (fresh FutureBuilder, clean _canonicalView).
        key: ValueKey('detail-$selectedId'),
        danceId: selectedId,
        onDeleted: _onDetailDeleted,
        onRestored: _onDetailRestored,
        onNavigateTo: _onNavigateTo,
      );
    }
    return const _EmptyDetailPane();
  }
}

/// The mutually-exclusive non-dance views the wide-layout detail pane can show.
/// [none] means the pane shows the selected dance (or the empty placeholder).
enum _DetailMode { none, importReview, onlinePreview }

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
