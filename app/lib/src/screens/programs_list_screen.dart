import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../l10n/app_localizations.dart';
import '../data/display_defaults.dart';
import '../data/repositories_scope.dart';
import '../diagnostics/error_log.dart';
import '../search/program_sort.dart';
import '../search/program_sort_labels.dart';
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

/// Programs list (`docs/design/ux.md` §4): non-deleted programs with title,
/// event date, venue, slot count and a status chip (icon+text). Sort by title /
/// recently-updated / event date; swipe-to-delete with undo; empty state that
/// teaches. Mirrors [DanceListScreen].
///
/// [onSelectProgram] wires split-pane callers ([ProgramsShell]); when null the
/// list uses push-navigation to the editor. [selectedProgramId] highlights the
/// selected row.
///
/// The list is **driven by a stream** ([ProgramRepository.watchAll]) rather than
/// by reload requests (issue #768). It takes no `refreshTrigger`: the parameter
/// was removed rather than left accepted-and-ignored, so a caller still passing
/// one is a compile error instead of a silently dead argument.
class ProgramsListScreen extends StatefulWidget {
  const ProgramsListScreen({
    super.key,
    this.onSelectProgram,
    this.onCreateProgram,
    this.selectedProgramId,
  });

  final void Function(String programId)? onSelectProgram;

  /// Called (split-pane mode) when the user taps "New program" so the parent
  /// can host the create flow in a pane. When null, a route is pushed.
  final VoidCallback? onCreateProgram;

  final String? selectedProgramId;

  @override
  State<ProgramsListScreen> createState() => _ProgramsListScreenState();
}

class _ProgramsListScreenState extends State<ProgramsListScreen> {
  late CompendiumRepositories _repos;

  /// Whether one-time setup has run. **This is a contract between two changes
  /// that arrived from opposite directions, and neither states it alone.**
  ///
  /// The subscription is opened exactly once per [State] — issue #768, so that
  /// a rebuild neither drops nor duplicates it. Issue #895 then gave
  /// [ProgramsShell] a [GlobalKey] so this State *survives* being reparented
  /// across the 900 px breakpoint (`programs_shell.dart:44`), which is what
  /// preserves the sort and scroll position through a rotation.
  ///
  /// Together those mean: **a rotation must not re-open the subscription.** It
  /// does not today, because a reparented Element is moved rather than
  /// destroyed — `deactivate` then `activate`, never `dispose` — so this flag
  /// stays true and the only cancel paths ([dispose] and `_resubscribe`, which
  /// immediately re-opens) are unreachable from a breakpoint crossing.
  ///
  /// What would falsify it: moving the subscription to `initState` and dropping
  /// the flag (correct before #895, a leak after it), or overriding
  /// `deactivate` to cancel — which would leave `_started` true with no stream,
  /// i.e. a list that silently stops updating after the first rotation.
  bool _started = false;

  List<Program>? _programs;
  Map<String, Venue> _venuesById = const {};
  Object? _loadError;
  ProgramSort _sort = ProgramSort.title;
  SortDirection _sortDir = ProgramSort.title.defaultDirection;

  /// The live Programs list (issue #768).
  ///
  /// Program data is written from outside the Programs tab — the "add to
  /// program" sheet on a Collection row, an archive or program import, a
  /// share-target bundle — and this list is kept alive in an `IndexedStack`, so
  /// before the conversion those writes were invisible until the app restarted.
  /// A broadcast fixed the sites anyone remembered; the stream fixes the ones
  /// nobody did.
  StreamSubscription<({List<Program> programs, Map<String, Venue> venuesById})>?
  _programsSub;

  /// Whether the user has explicitly chosen a sort this session (issue #895).
  /// Once set, the saved default no longer seeds `_sort` — protecting an
  /// in-session choice from a late async read. Mirrors
  /// `dance_list_screen.dart`'s `_sortUserSet` guard for the Collection list,
  /// which this screen had no equivalent of before this issue: it never read
  /// settings at all.
  bool _sortUserSet = false;

  /// Whether the saved-default sort seed has run (it runs at most once, from
  /// [didChangeDependencies]).
  bool _defaultSortSeeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
      _subscribe();
      // Fire-and-forget: unlike the Collection list, sorting here is a pure
      // client-side re-order of already-loaded data (`_sorted`), not a
      // database query, so the seed has nothing to sequence after — it only
      // needs `setState` to run before the next build that reads `_sort`.
      unawaited(_seedDefaultSort());
    }
  }

  /// Opens the subscription. Deliberately not awaiting a first value the way
  /// the Collection panes do: this list has nothing to sequence after it, so
  /// there is no pending future for an abandonment path to orphan — the hazard
  /// that `_replaceSubscription`, in the program summary **pane**
  /// (`program_summary_screen.dart`), exists to close cannot arise here, and
  /// adding a completer to mirror it would create the hazard rather than guard
  /// against it.
  ///
  /// Named in prose rather than as a `[...]` reference because it is a private
  /// member of a private `State` class in another library, so a dartdoc link
  /// cannot resolve to it — and a link that silently resolves to nothing is the
  /// same defect as the wrong class name this replaces.
  void _subscribe() {
    _programsSub = _repos.programs
        // This list renders a venue label per row, resolved from a table
        // `listAll` does not read, so the stream must be told (issue #944).
        // The Collection list makes the opposite choice at its own seam: it
        // renders no venue and deliberately does not opt in.
        .watchAll(includeVenues: true)
        // `asyncMap`, not a handler that awaits inside `listen`.
        //
        // Resolving venue labels is asynchronous, and `listen` does not
        // await its callback: two emits arriving close together would run
        // concurrently and could finish in the wrong order, letting an
        // older list win by finishing last. `asyncMap` holds the
        // subscription until each mapper completes, so that interleaving
        // cannot occur — a property of the stream rather than a counter
        // this screen has to maintain and a future edit could drop.
        //
        // The alternative, a sequence number compared after the await, was
        // written first and removed: it worked, but nothing could test it.
        // Inverting the order deterministically needs the venue read held
        // open, and holding a read open on a single-connection database
        // blocks the very write that would produce the second emit.
        .asyncMap(_withVenues)
        .listen(
          _onPrograms,
          onError: (Object error, StackTrace stackTrace) {
            logCaughtError(
              error,
              stackTrace,
              source: 'programs_list_screen._subscribe',
            );
            if (mounted) setState(() => _loadError = error);
          },
        );
  }

  /// Pairs a program list with the venues its rows need.
  ///
  /// The catalogue is read only when a program actually links one;
  /// [ProgramListTile] falls back to `Program.venue` with an empty map.
  ///
  /// This read IS covered by the watched set (issue #944): the subscription
  /// opts into `venues`, so a rename re-emits and this re-reads. It stays a
  /// separate query rather than part of `listAll`, because a program's venue is
  /// a label resolved beside the row, not a column of it.
  Future<({List<Program> programs, Map<String, Venue> venuesById})> _withVenues(
    List<Program> programs,
  ) async {
    final hasLinkedVenue = programs.any((p) => p.venueId != null);
    return (
      programs: programs,
      venuesById: hasLinkedVenue
          ? {for (final v in await _repos.venues.listAll()) v.id: v}
          : const <String, Venue>{},
    );
  }

  /// Retry after a load error: the stream may have terminated with it, so the
  /// old subscription is cancelled and a fresh one opened rather than waiting
  /// for an emit that a closed source will never produce.
  void _resubscribe() {
    unawaited(_programsSub?.cancel());
    _programsSub = null;
    _subscribe();
  }

  /// Seeds `_sort` (and, under "Last used", `_sortDir`) from the saved default
  /// Programs sort order (issue #895), at most once and only if the user
  /// hasn't already chosen a sort this session. A `null`/invalid stored value
  /// leaves the historical default (`title`, ascending) in place. Mirrors
  /// `dance_list_screen.dart`'s `_seedDefaultSort` exactly, including the
  /// (sort, direction) *pair* comparison at the end — a key-only comparison
  /// would skip the `setState` whenever the resolved sort equals the initial
  /// `_sort` (title) even when the direction differs, silently dropping a
  /// stored non-default direction under "Last used".
  Future<void> _seedDefaultSort() async {
    if (_defaultSortSeeded || _sortUserSet) return;
    _defaultSortSeeded = true;
    // A settings read/decode failure must not fail the whole Programs load:
    // fall back silently to the historical default (title, ascending).
    SortDefaultSetting<ProgramSort> mode;
    try {
      final stored = await _repos.settings.get(kDefaultProgramSortKey);
      mode = sortDefaultSettingFromStored(
        stored,
        programSortFromName,
        ProgramSort.title,
      );
    } catch (_) {
      // diagnostics: silent — sort default setting read failed; returns early to built-in default (title, ascending).
      return;
    }
    if (!mounted || _sortUserSet) return;
    ProgramSort sort;
    SortDirection direction;
    if (mode.isLastUsed) {
      // "Last used": seed from the list's own last-used sort + direction
      // (issue #895), not the fixed default. A second settings read, tolerant
      // of failure the same way as the mode read above.
      try {
        final storedSort = await _repos.settings.get(kLastUsedProgramSortKey);
        final storedDirection = await _repos.settings.get(
          kLastUsedProgramSortDirectionKey,
        );
        sort = programSortFromName(storedSort) ?? ProgramSort.title;
        direction =
            sortDirectionFromName(storedDirection) ?? sort.defaultDirection;
      } catch (_) {
        // diagnostics: silent — last-used sort/direction read failed; returns early to built-in default.
        return;
      }
      if (!mounted || _sortUserSet) return;
    } else {
      // A fixed default always uses that sort's natural direction, regardless
      // of what was last used in the list (Isaac's ruling, issue #895) — never
      // the stored last-used direction, which is why this branch never reads
      // the last-used keys at all.
      sort = mode.sort;
      direction = sort.defaultDirection;
    }

    if (sort != _sort || direction != _sortDir) {
      setState(() {
        _sort = sort;
        _sortDir = direction;
      });
    }
  }

  /// Persists the Programs list's own last-used sort + direction (issue
  /// #895), read back by [_seedDefaultSort] when the configured default is
  /// "Last used". Fire-and-forget, mirroring the Collection list's
  /// `_persistLastUsedSort`. Unlike Collection's `CollectionSort`, `ProgramSort`
  /// has no query-scoped member like `relevance`, so every value here is a
  /// durable choice and none needs skipping.
  void _persistLastUsedSort() {
    unawaited(_repos.settings.set(kLastUsedProgramSortKey, _sort.name));
    unawaited(
      _repos.settings.set(kLastUsedProgramSortDirectionKey, _sortDir.name),
    );
  }

  @override
  void dispose() {
    unawaited(_programsSub?.cancel());
    super.dispose();
  }

  void _onPrograms(
    ({List<Program> programs, Map<String, Venue> venuesById}) snapshot,
  ) {
    if (!mounted) return;
    setState(() {
      _programs = snapshot.programs;
      _venuesById = snapshot.venuesById;
      _loadError = null;
    });
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
    await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ProgramEditorScreen()),
    );
    // No reload: the save is a write to `programs`/`program_slots`, so the
    // stream has already delivered it (issue #768).
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
    // duplicate / delete / mark performed) is a write to `programs` /
    // `program_slots`, which this list watches — so it has already updated by
    // the time the route pops, with no broadcast involved and no reload of its
    // own to perform (issue #768).
    await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => ProgramSummaryScreen(programId: id),
      ),
    );
  }

  Future<void> _openRecentlyDeleted() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RecentlyDeletedScreen.programs()),
    );
    // A restore from that screen clears `deleted_at`, which the stream sees.
  }

  Future<void> _openPlaintextImport() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const PlaintextProgramImportScreen(),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      // The commit is a write, so the stream has already delivered it.
      widget.onSelectProgram?.call(result);
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
      // The commit is a write, so the stream has already delivered it.
      widget.onSelectProgram?.call(result);
    }
  }

  Future<void> _softDelete(Program program) async {
    await _repos.programs.softDelete(program.id, at: DateTime.now().toUtc());
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    // No optimistic removal: the soft delete is a write to `programs`, so the
    // stream re-emits without the row. Removing it here as well would render
    // the same change twice and, worse, leave this list's state diverging from
    // the stream's if the write were ever to fail after the fact.
    //
    // Everything else that renders this program's slots (issue #768, gap 4)
    // learns about the delete, and about an Undo, from its own stream — so this
    // no longer captures a refresh notifier before the snackbar.
    //
    // Two hazards died with that capture, and they are recorded because the
    // shape recurs wherever a callback outlives the widget that offered it. The
    // notifier had to be resolved while the context was live, since the undo
    // callback runs when it may not be; and an earlier version guarded the bump
    // with `if (mounted)`, which was not a fix but a silencer — it made the
    // unsafe read unreachable by making the broadcast not happen, so a user who
    // navigated away before pressing Undo restored the program and notified
    // nobody. That is the staleness this whole issue is about, reintroduced in
    // the one callback documented as needing care.
    showUndoSnackBar(
      ScaffoldMessenger.of(context),
      key: const ValueKey('program-deleted-snackbar'),
      message: l10n.programsDeletedSnack(program.title),
      undoLabel: l10n.commonUndo,
      accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
      onUndo: () async {
        await _repos.programs.restore(program.id, at: DateTime.now().toUtc());
        // No `mounted` check and no context read, and nothing captured above
        // to bump: the restore is a write and the stream carries it, to this
        // list and to every other view of the program.
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
              onSelected: (value) {
                setState(() {
                  _sortUserSet = true;
                  _sort = value;
                  _sortDir = value.defaultDirection;
                });
                _persistLastUsedSort();
              },
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
              onPressed: () {
                setState(() {
                  _sortUserSet = true;
                  _sortDir = _sortDir == SortDirection.ascending
                      ? SortDirection.descending
                      : SortDirection.ascending;
                });
                _persistLastUsedSort();
              },
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
                _resubscribe();
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
