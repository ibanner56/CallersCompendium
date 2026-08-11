import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../l10n/app_localizations.dart';
import '../data/programs_refresh_scope.dart';
import '../data/repositories_scope.dart';
import '../utils/confirm_delete.dart';
import '../utils/undo_snack_bar.dart';
import '../widgets/program_list_tile.dart';
import '../widgets/skeleton.dart';
import '../widgets/weekday_header_strip.dart';
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
  Map<String, Venue> _venuesById = const {};
  Object? _loadError;
  ProgramSort _sort = ProgramSort.title;
  SortDirection _sortDir = ProgramSort.title.defaultDirection;

  /// The app-level programs-refresh notifier (issue #768), if provided. Program
  /// data is written from outside the Programs tab — the "add to program" sheet
  /// on a Collection row, an archive or program import, a share-target bundle —
  /// and this list is kept alive in an `IndexedStack`, so without this those
  /// writes were invisible until the app restarted. Tracked so the listener is
  /// swapped correctly.
  ValueListenable<int>? _programsRefresh;

  /// The revision this list published itself. A broadcast notifies every
  /// subscriber including this one; where the list has already applied the
  /// change locally (the optimistic row removal on delete, which deliberately
  /// avoids a full reload) the echo is skipped so the mutation still costs one
  /// render, not two (issue #340).
  int? _selfBroadcastRevision;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
      widget.refreshTrigger?.addListener(_onRefreshTriggered);
      _load();
    }
    final programsRefresh = ProgramsRefreshScope.maybeOf(context);
    if (!identical(programsRefresh, _programsRefresh)) {
      _programsRefresh?.removeListener(_onRefreshTriggered);
      _programsRefresh = programsRefresh;
      _programsRefresh?.addListener(_onRefreshTriggered);
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
    final revision = _programsRefresh?.value;
    if (revision != null && revision == _selfBroadcastRevision) return;
    if (mounted) _load();
  }

  /// Broadcasts "program data changed" so the views rendering program-derived
  /// data elsewhere — the Collection's "called N times" badge, a dance detail
  /// screen's calling history, a summary pane beside this list — reload.
  ///
  /// Reloading this list is the broadcast's job, not the caller's; a site that
  /// does both loads twice for one mutation (issue #340). Pass
  /// [alreadyApplied] when the list has updated itself optimistically, to skip
  /// its own echo. Returns `false` when no scope is mounted (focused widget
  /// tests), so the caller can fall back to reloading directly.
  bool _broadcastProgramChange({bool alreadyApplied = false}) {
    final revision = _programsRefresh;
    if (revision is! ValueNotifier<int>) return false;
    // Set before incrementing: listeners fire synchronously inside the setter.
    if (alreadyApplied) _selfBroadcastRevision = revision.value + 1;
    revision.value++;
    return true;
  }

  @override
  void dispose() {
    widget.refreshTrigger?.removeListener(_onRefreshTriggered);
    _programsRefresh?.removeListener(_onRefreshTriggered);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final programs = await _repos.programs.listAll();
      // Only load the venue catalogue when a program actually links one;
      // ProgramListTile falls back to Program.venue with an empty map.
      final hasLinkedVenue = programs.any((p) => p.venueId != null);
      final venuesById = hasLinkedVenue
          ? {for (final v in await _repos.venues.listAll()) v.id: v}
          : const <String, Venue>{};
      if (!mounted) return;
      setState(() {
        _programs = programs;
        _venuesById = venuesById;
        _loadError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  /// Day-precision event dates (time-of-day dropped) for the "this week"
  /// header strip's markers (ROADMAP G.8's first-day-of-week consumer).
  static Set<DateTime> _programEventDates(List<Program> programs) => {
    for (final program in programs)
      if (program.eventDate case final date?)
        DateTime(date.year, date.month, date.day),
  };

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
    // The builder broadcasts its own save, which already reloaded this list
    // (issue #768); reloading again here would load twice (issue #340).
    if (mounted && result != null && _programsRefresh == null) await _load();
  }

  Future<void> _openProgram(String id) async {
    if (widget.onSelectProgram != null) {
      widget.onSelectProgram!(id);
      return;
    }
    // Narrow (single-pane) mode: open the read-focused, Perform-first summary
    // rather than dropping the caller straight into the edit builder. Mirrors
    // the dance side's narrow list → [DanceDetailScreen] flow; Edit lives
    // behind the summary. Every way the summary can mutate the program (edit /
    // duplicate / delete / mark performed) now broadcasts, so this list has
    // already reloaded by the time the route pops; the direct reload is the
    // fallback for focused tests that mount no scope (issue #768).
    await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => ProgramSummaryScreen(programId: id),
      ),
    );
    if (mounted && _programsRefresh == null) await _load();
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
      // The import broadcasts its own commit, which already reloaded this list
      // (issue #768); the direct reload is the unscoped fallback.
      if (_programsRefresh == null) await _load();
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
      // The import broadcasts its own commit, which already reloaded this list
      // (issue #768); the direct reload is the unscoped fallback.
      if (_programsRefresh == null) await _load();
      if (mounted) widget.onSelectProgram?.call(result);
    }
  }

  Future<void> _softDelete(Program program) async {
    await _repos.programs.softDelete(program.id, at: DateTime.now().toUtc());
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _programs?.removeWhere((p) => p.id == program.id));
    // The row is already gone from this list; the broadcast is for everything
    // else that renders this program's slots (issue #768, gap 4).
    _broadcastProgramChange(alreadyApplied: true);
    showUndoSnackBar(
      ScaffoldMessenger.of(context),
      key: const ValueKey('program-deleted-snackbar'),
      message: l10n.programsDeletedSnack(program.title),
      undoLabel: l10n.commonUndo,
      accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
      onUndo: () async {
        await _repos.programs.restore(program.id, at: DateTime.now().toUtc());
        // The broadcast must not depend on this screen's lifetime — an undo
        // snackbar outlives its host by design. Only the unscoped fallback
        // does, because it reloads *this* screen.
        if (!_broadcastProgramChange() && mounted) await _load();
      },
    );
  }

  Future<void> _duplicateFromList(Program program) async {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now().toUtc();
    final copy = await _repos.programs.duplicate(
      id: program.id,
      newId: uuidV4(),
      newSlotId: uuidV4,
      now: now,
      newTitle: l10n.commonDuplicateTitleSuffix(program.title),
    );
    if (!mounted) return;
    if (!_broadcastProgramChange()) await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey('program-duplicated-snackbar'),
        content: Text(l10n.programsDuplicatedSnack(copy.title)),
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
              tooltip: l10n.importProgramTooltip,
              icon: const Icon(Icons.file_download_outlined),
              onSelected: (source) => switch (source) {
                _ProgramImportSource.plaintext => _openPlaintextImport(),
                _ProgramImportSource.contraDb => _openContraDbImport(),
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  key: const ValueKey('programs-import-plaintext'),
                  value: _ProgramImportSource.plaintext,
                  child: ListTile(
                    leading: const Icon(Icons.playlist_add),
                    title: Text(l10n.importFromTitleList),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  key: const ValueKey('programs-import-contradb'),
                  value: _ProgramImportSource.contraDb,
                  child: ListTile(
                    leading: const Icon(Icons.cloud_download_outlined),
                    title: Text(l10n.importFromContraDb),
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: WeekdayHeaderStrip(markedDates: _programEventDates(programs)),
        ),
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
                  venuesById: _venuesById,
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
