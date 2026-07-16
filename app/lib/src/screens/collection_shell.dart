import 'package:flutter/material.dart';

import 'dance_detail_screen.dart';
import 'dance_list_screen.dart';

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
  const CollectionShell({super.key});

  /// Breakpoint (logical pixels) at which the split-pane layout activates.
  static const double splitBreakpoint = 900;

  /// Fixed width (logical pixels) of the list pane in split mode.
  static const double listPaneWidth = 400;

  @override
  State<CollectionShell> createState() => _CollectionShellState();
}

class _CollectionShellState extends State<CollectionShell> {
  String? _selectedDanceId;

  /// Incrementing this value triggers [DanceListScreen] to reload via its
  /// [refreshTrigger] parameter.
  final _listRefresh = ValueNotifier<int>(0);

  @override
  void dispose() {
    _listRefresh.dispose();
    super.dispose();
  }

  void _onSelectDance(String danceId) {
    setState(() => _selectedDanceId = danceId);
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
        return const DanceListScreen();
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
            ),
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: ScaffoldMessenger(
            child: selectedId != null
                ? DanceDetailScreen(
                    // Keyed on the dance id so the screen fully resets when the
                    // selection changes (fresh FutureBuilder, clean _canonicalView).
                    key: ValueKey('detail-$selectedId'),
                    danceId: selectedId,
                    onDeleted: _onDetailDeleted,
                    onRestored: _onDetailRestored,
                    onNavigateTo: _onNavigateTo,
                  )
                : const _EmptyDetailPane(),
          ),
        ),
      ],
    );
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
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
