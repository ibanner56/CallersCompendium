import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';
import '../utils/confirm_delete.dart';
import '../widgets/program_list_tile.dart';
import '../widgets/skeleton.dart';
import 'app_shell_search_scope.dart';
import 'contradb_program_import_screen.dart';
import 'plaintext_program_import_screen.dart';
import 'program_editor_screen.dart';
import 'program_summary_screen.dart';
import 'recently_deleted_screen.dart';

/// The program-import sources offered by the Programs list "Import" menu.
enum _ProgramImportSource { plaintext, contraDb }

/// How the Programs list is ordered (`docs/design/ux.md` §4).
enum ProgramSort {
  title('Title'),
  recentlyUpdated('Recently updated'),
  eventDate('Event date');

  const ProgramSort(this.label);
  final String label;

  /// The historical (pre-toggle) direction for this sort key, used to seed the
  /// direction toggle so behavior is unchanged until the user flips it.
  SortDirection get defaultDirection => switch (this) {
    ProgramSort.title || ProgramSort.eventDate => SortDirection.ascending,
    ProgramSort.recentlyUpdated => SortDirection.descending,
  };
}

/// Localized label for a [ProgramSort] option shown in the Programs list sort
/// menu. Mirrors the L2 `collection_query_labels.dart` pattern so the display
/// text is translatable without baking a locale into the enum — whose English
/// [ProgramSort.label] field is still used by the (L5) Settings default-sort
/// picker.
String programSortLabel(AppLocalizations l10n, ProgramSort sort) =>
    switch (sort) {
      ProgramSort.title => l10n.programsSortTitle,
      ProgramSort.recentlyUpdated => l10n.programsSortRecentlyUpdated,
      ProgramSort.eventDate => l10n.programsSortEventDate,
    };

/// Programs list (`docs/design/ux.md` §4): non-deleted programs with title,
/// event date, venue, slot count and a status chip (icon+text). Sort by title /
/// recently-updated / event date; swipe-to-delete with undo; empty state that
/// teaches. Mirrors [DanceListScreen].
///
/// [onSelectProgram] wires split-pane callers ([ProgramsShell]); when null the
/// list uses push-navigation to the editor. [selectedProgramId] highlights the
/// selected row and [refreshTrigger] lets a parent request a reload.
class ProgramsListScreen extends StatefulWidget {
  const ProgramsListScreen({
    super.key,
    this.onSelectProgram,
    this.onCreateProgram,
    this.selectedProgramId,
    this.refreshTrigger,
  });

  final void Function(String programId)? onSelectProgram;

  /// Called (split-pane mode) when the user taps "New program" so the parent
  /// can host the create flow in a pane. When null, a route is pushed.
  final VoidCallback? onCreateProgram;

  final String? selectedProgramId;
  final ValueListenable<int>? refreshTrigger;

  @override
  State<ProgramsListScreen> createState() => _ProgramsListScreenState();
}

class _ProgramsListScreenState extends State<ProgramsListScreen> {
  late CompendiumRepositories _repos;
  bool _started = false;

  List<Program>? _programs;
  Object? _loadError;
  ProgramSort _sort = ProgramSort.title;
  SortDirection _sortDir = ProgramSort.title.defaultDirection;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
      widget.refreshTrigger?.addListener(_onRefreshTriggered);
      _load();
    }
  }

  @override
  void didUpdateWidget(ProgramsListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger) {
      oldWidget.refreshTrigger?.removeListener(_onRefreshTriggered);
      widget.refreshTrigger?.addListener(_onRefreshTriggered);
    }
  }

  void _onRefreshTriggered() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    widget.refreshTrigger?.removeListener(_onRefreshTriggered);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final programs = await _repos.programs.listAll();
      if (!mounted) return;
      setState(() {
        _programs = programs;
        _loadError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  List<Program> get _sorted {
    final programs = [...?_programs];
    final descending = _sortDir == SortDirection.descending;
    int flip(int cmp) => descending ? -cmp : cmp;
    switch (_sort) {
      case ProgramSort.title:
        programs.sort(
          (a, b) =>
              flip(a.title.toLowerCase().compareTo(b.title.toLowerCase())),
        );
      case ProgramSort.recentlyUpdated:
        // Ascending base (oldest-first); the default direction (descending)
        // flips it to newest-first.
        programs.sort((a, b) => flip(a.updatedAt.compareTo(b.updatedAt)));
      case ProgramSort.eventDate:
        // Programs without a date sort last regardless of direction; dated
        // programs are soonest-first ascending, latest-first descending.
        programs.sort((a, b) {
          final ad = a.eventDate;
          final bd = b.eventDate;
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return flip(ad.compareTo(bd));
        });
    }
    return programs;
  }

  Future<void> _openNewProgram() async {
    if (widget.onCreateProgram != null) {
      widget.onCreateProgram!();
      return;
    }
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ProgramEditorScreen()),
    );
    if (mounted && result != null) await _load();
  }

  Future<void> _openProgram(String id) async {
    if (widget.onSelectProgram != null) {
      widget.onSelectProgram!(id);
      return;
    }
    // Narrow (single-pane) mode: open the read-focused, Perform-first summary
    // rather than dropping the caller straight into the edit builder. Mirrors
    // the dance side's narrow list → [DanceDetailScreen] flow; Edit lives
    // behind the summary. Always reload on return since the summary can mutate
    // the program (edit / duplicate / delete / mark performed).
    await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => ProgramSummaryScreen(programId: id),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openRecentlyDeleted() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RecentlyDeletedScreen.programs()),
    );
    if (mounted) await _load();
  }

  Future<void> _openPlaintextImport() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const PlaintextProgramImportScreen(),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      await _load();
      if (mounted) widget.onSelectProgram?.call(result);
    }
  }

  Future<void> _openContraDbImport() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const ContraDbProgramImportScreen(),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      await _load();
      if (mounted) widget.onSelectProgram?.call(result);
    }
  }

  Future<void> _softDelete(Program program) async {
    await _repos.programs.softDelete(program.id, at: DateTime.now().toUtc());
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _programs?.removeWhere((p) => p.id == program.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey('program-deleted-snackbar'),
        content: Text(l10n.programsDeletedSnack(program.title)),
        action: SnackBarAction(
          label: l10n.commonUndo,
          onPressed: () async {
            await _repos.programs.restore(
              program.id,
              at: DateTime.now().toUtc(),
            );
            if (mounted) await _load();
          },
        ),
      ),
    );
  }

  Future<void> _duplicateFromList(Program program) async {
    final now = DateTime.now().toUtc();
    final copy = await _repos.programs.duplicate(
      id: program.id,
      newId: uuidV4(),
      newSlotId: uuidV4,
      now: now,
      newTitle: '${program.title} (copy)',
    );
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey('program-duplicated-snackbar'),
        content: Text(
          AppLocalizations.of(context).programsDuplicatedSnack(copy.title),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final openSearch = AppShellSearchScope.of(context)?.openSearch;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.programsTitle),
        actions: [
          // Phone-only: search lives in the app bar (the bottom-right FAB slot
          // is reserved for the "New program" FAB). On wide layouts the nav
          // rail owns search, so no scope is present and this action is omitted.
          if (openSearch != null)
            IconButton(
              key: const ValueKey('programs-search'),
              tooltip: l10n.collectionSearchTooltip,
              icon: const Icon(Icons.search),
              onPressed: openSearch,
            ),
          if (_programs != null) ...[
            PopupMenuButton<_ProgramImportSource>(
              key: const ValueKey('programs-import'),
              tooltip: 'Import program',
              icon: const Icon(Icons.file_download_outlined),
              onSelected: (source) => switch (source) {
                _ProgramImportSource.plaintext => _openPlaintextImport(),
                _ProgramImportSource.contraDb => _openContraDbImport(),
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  key: ValueKey('programs-import-plaintext'),
                  value: _ProgramImportSource.plaintext,
                  child: ListTile(
                    leading: Icon(Icons.playlist_add),
                    title: Text('From title list'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  key: ValueKey('programs-import-contradb'),
                  value: _ProgramImportSource.contraDb,
                  child: ListTile(
                    leading: Icon(Icons.cloud_download_outlined),
                    title: Text('From ContraDB'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            IconButton(
              key: const ValueKey('programs-recently-deleted'),
              tooltip: l10n.collectionRecentlyDeletedTooltip,
              icon: const Icon(Icons.restore_from_trash_outlined),
              onPressed: _openRecentlyDeleted,
            ),
            PopupMenuButton<ProgramSort>(
              key: const ValueKey('programs-sort'),
              tooltip: l10n.programsSortByTooltip(
                programSortLabel(l10n, _sort),
              ),
              initialValue: _sort,
              icon: const Icon(Icons.sort),
              onSelected: (value) => setState(() {
                _sort = value;
                _sortDir = value.defaultDirection;
              }),
              itemBuilder: (context) => [
                for (final option in ProgramSort.values)
                  PopupMenuItem(
                    value: option,
                    child: Text(programSortLabel(l10n, option)),
                  ),
              ],
            ),
            IconButton(
              key: const ValueKey('programs-sort-direction'),
              tooltip: _sortDir == SortDirection.ascending
                  ? l10n.collectionSortAscendingTooltip
                  : l10n.collectionSortDescendingTooltip,
              icon: Icon(
                _sortDir == SortDirection.ascending
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
              ),
              onPressed: () => setState(() {
                _sortDir = _sortDir == SortDirection.ascending
                    ? SortDirection.descending
                    : SortDirection.ascending;
              }),
            ),
          ],
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _programs == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('new-program'),
              heroTag: 'new-program',
              onPressed: _openNewProgram,
              icon: const Icon(Icons.add),
              label: Text(l10n.programsNewProgram),
            ),
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context);
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            Text(l10n.programsListLoadError),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                setState(() {
                  _programs = null;
                  _loadError = null;
                });
                _load();
              },
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      );
    }

    final programs = _programs;
    if (programs == null) {
      return const SkeletonListView();
    }

    if (programs.isEmpty) {
      return Center(
        key: const ValueKey('empty-state'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.event_note_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.programsEmptyTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(l10n.programsListEmptyBody, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('empty-new-program'),
                onPressed: _openNewProgram,
                icon: const Icon(Icons.add),
                label: Text(l10n.programsNewProgram),
              ),
            ],
          ),
        ),
      );
    }

    final sorted = _sorted;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              liveRegion: true,
              child: Text(
                l10n.programsCount(sorted.length),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: sorted.length,
            itemBuilder: (context, index) {
              final program = sorted[index];
              // Swipe left to reveal a Delete button (issue #352). Tapping the
              // revealed Delete button is the confirmation — a swipe alone
              // never deletes. It routes into the same soft-delete + Undo flow
              // as the ⋮ menu, with no extra dialog on this path. The "Confirm
              // before delete" setting continues to gate only the ⋮ menu below.
              return Slidable(
                key: ValueKey('slidable-${program.id}'),
                groupTag: 'programs-list',
                endActionPane: ActionPane(
                  motion: const DrawerMotion(),
                  extentRatio: 0.25,
                  children: [
                    SlidableAction(
                      key: ValueKey('slide-delete-${program.id}'),
                      onPressed: (_) => _softDelete(program),
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.errorContainer,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onErrorContainer,
                      icon: Icons.delete_outline,
                      label: l10n.commonDelete,
                    ),
                  ],
                ),
                child: ProgramListTile(
                  program: program,
                  selected:
                      widget.onSelectProgram != null &&
                      widget.selectedProgramId == program.id,
                  onTap: () => _openProgram(program.id),
                  // Row action menu (⋮): non-swipe access for mouse/keyboard/AT
                  // users. Delete routes through the identical confirm +
                  // soft-delete + undo flow as the Dismissible swipe above.
                  onDelete: () async {
                    if (await confirmDeleteIfEnabled(
                      context,
                      itemLabel: program.title,
                    )) {
                      await _softDelete(program);
                    }
                  },
                  onDuplicate: () => _duplicateFromList(program),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
