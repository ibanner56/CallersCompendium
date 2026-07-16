import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../data/repositories_scope.dart';
import '../utils/confirm_delete.dart';
import '../widgets/program_list_tile.dart';
import '../widgets/skeleton.dart';
import 'app_shell_search_scope.dart';
import 'program_editor_screen.dart';
import 'program_summary_screen.dart';
import 'programs_recently_deleted_screen.dart';

/// How the Programs list is ordered (`docs/design/ux.md` §4).
enum ProgramSort {
  title('Title'),
  recentlyUpdated('Recently updated'),
  eventDate('Event date');

  const ProgramSort(this.label);
  final String label;
}

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
    switch (_sort) {
      case ProgramSort.title:
        programs.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case ProgramSort.recentlyUpdated:
        programs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case ProgramSort.eventDate:
        // Programs without a date sort last; otherwise soonest-first.
        programs.sort((a, b) {
          final ad = a.eventDate;
          final bd = b.eventDate;
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return ad.compareTo(bd);
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
      MaterialPageRoute<void>(
        builder: (_) => const ProgramsRecentlyDeletedScreen(),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _softDelete(Program program) async {
    await _repos.programs.softDelete(program.id, at: DateTime.now().toUtc());
    if (!mounted) return;
    setState(() => _programs?.removeWhere((p) => p.id == program.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey('program-deleted-snackbar'),
        content: Text('"${program.title}" deleted.'),
        action: SnackBarAction(
          label: 'Undo',
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
        content: Text('Duplicated as "${copy.title}".'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final openSearch = AppShellSearchScope.of(context)?.openSearch;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Programs'),
        actions: [
          // Phone-only: search lives in the app bar (the bottom-right FAB slot
          // is reserved for the "New program" FAB). On wide layouts the nav
          // rail owns search, so no scope is present and this action is omitted.
          if (openSearch != null)
            IconButton(
              key: const ValueKey('programs-search'),
              tooltip: 'Search (Ctrl/Cmd-K)',
              icon: const Icon(Icons.search),
              onPressed: openSearch,
            ),
          if (_programs != null) ...[
            IconButton(
              key: const ValueKey('programs-recently-deleted'),
              tooltip: 'Recently deleted',
              icon: const Icon(Icons.restore_from_trash_outlined),
              onPressed: _openRecentlyDeleted,
            ),
            PopupMenuButton<ProgramSort>(
              tooltip: 'Sort by',
              initialValue: _sort,
              onSelected: (value) => setState(() => _sort = value),
              itemBuilder: (context) => [
                for (final option in ProgramSort.values)
                  PopupMenuItem(value: option, child: Text(option.label)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sort),
                    const SizedBox(width: 4),
                    Text('Sort: ${_sort.label}'),
                  ],
                ),
              ),
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
              label: const Text('New program'),
            ),
    );
  }

  Widget _buildBody() {
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            const Text('Could not load your programs.'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                setState(() {
                  _programs = null;
                  _loadError = null;
                });
                _load();
              },
              child: const Text('Retry'),
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
                'No programs yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Build set lists for your events here. Create your first '
                'program to get started.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('empty-new-program'),
                onPressed: _openNewProgram,
                icon: const Icon(Icons.add),
                label: const Text('New program'),
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
                '${sorted.length} ${sorted.length == 1 ? 'program' : 'programs'}',
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
              return Dismissible(
                key: ValueKey('dismissible-${program.id}'),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) =>
                    confirmDeleteIfEnabled(context, itemLabel: program.title),
                onDismissed: (_) => _softDelete(program),
                background: Container(
                  alignment: Alignment.centerRight,
                  color: Theme.of(context).colorScheme.errorContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
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
