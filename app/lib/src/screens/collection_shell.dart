import 'package:flutter/material.dart';

import '../data/import_io.dart';
import 'dance_detail_screen.dart';
import 'dance_list_screen.dart';
import 'import_review_screen.dart';

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

  /// Breakpoint (logical pixels) at which the split-pane layout activates.
  static const double splitBreakpoint = 900;

  /// Fixed width (logical pixels) of the list pane in split mode.
  static const double listPaneWidth = 400;

  @override
  State<CollectionShell> createState() => _CollectionShellState();
}

class _CollectionShellState extends State<CollectionShell> {
  String? _selectedDanceId;

  /// Whether the wide-layout detail pane currently shows the import view
  /// (instead of a [DanceDetailScreen] / the empty placeholder). Toggled by the
  /// app-bar Import action and cleared when the user selects a dance or closes
  /// the embedded import view.
  bool _showImport = false;

  /// Incrementing this value triggers [DanceListScreen] to reload via its
  /// [refreshTrigger] parameter.
  final _listRefresh = ValueNotifier<int>(0);

  List<ImportSource> get _importSources =>
      widget.importSources ?? defaultImportSources();

  @override
  void dispose() {
    _listRefresh.dispose();
    super.dispose();
  }

  void _onSelectDance(String danceId) {
    // Selecting a dance always exits import mode and shows that dance.
    setState(() {
      _selectedDanceId = danceId;
      _showImport = false;
    });
  }

  /// Wide layout: swap the detail pane over to the embedded import view.
  void _onImport() {
    setState(() => _showImport = true);
  }

  /// Wide layout: leave the embedded import view, returning to the previously
  /// selected dance (or the empty placeholder).
  void _onImportClose() {
    setState(() => _showImport = false);
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
    setState(() => _selectedDanceId = danceId);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= CollectionShell.splitBreakpoint) {
          return _buildSplitPane();
        }
        // Narrow: standard single-pane list with existing push navigation.
        // Import pushes its own full-screen route (there is no detail pane).
        return DanceListScreen(onImport: _pushImportRoute);
      },
    );
  }

  Widget _buildSplitPane() {
    final selectedId = _selectedDanceId;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Each pane gets its own ScaffoldMessenger so snackbars from the list
        // (e.g. swipe-to-delete) and the detail pane (delete/undo) appear in
        // the correct pane and are never duplicated across both.
        SizedBox(
          width: CollectionShell.listPaneWidth,
          child: ScaffoldMessenger(
            child: DanceListScreen(
              onSelectDance: _onSelectDance,
              selectedDanceId: _selectedDanceId,
              refreshTrigger: _listRefresh,
              onImport: _onImport,
            ),
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: ScaffoldMessenger(child: _buildDetailPane(selectedId))),
      ],
    );
  }

  /// The wide-layout detail pane: the embedded import view when import mode is
  /// active, otherwise the selected [DanceDetailScreen] or the empty
  /// placeholder.
  Widget _buildDetailPane(String? selectedId) {
    if (_showImport) {
      return ImportReviewScreen(
        // Keyed so switching in/out of import mode fully resets the flow.
        key: const ValueKey('collection-import'),
        sources: _importSources,
        picker: widget.importPicker,
        fetcher: widget.urlFetcher,
        onClose: _onImportClose,
      );
    }
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

/// Placeholder shown in the detail pane before the user selects a dance.
class _EmptyDetailPane extends StatelessWidget {
  const _EmptyDetailPane();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Select a dance',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose a dance from the list to view its details.',
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
