import 'dart:async';

import 'package:clock/clock.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../l10n/app_localizations.dart';
import '../data/program_forms.dart';
import '../data/display_defaults.dart';
import '../data/program_templates.dart' show ProgramTemplateChoice;
import '../data/repositories_scope.dart';
import '../data/weekends_and_series_scope.dart';
import '../search/collection_selection.dart';
import '../data/sort_ignore_articles_scope.dart';
import '../diagnostics/error_log.dart';
import '../export/program_calendar_export.dart';
import '../search/program_sort.dart';
import '../search/program_sort_labels.dart';
import '../theme/app_spacing.dart';
import '../utils/confirm_delete.dart';
import '../utils/row_focus.dart';
import '../utils/undo_snack_bar.dart';
import '../widgets/brand_mark.dart';
import '../widgets/calendar_export_dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/export_guard.dart';
import '../widgets/load_error_view.dart';
import '../widgets/program_list_tile.dart';
import '../widgets/program_template_chooser.dart';
import '../widgets/skeleton.dart';
import '../widgets/sync_now_action.dart';
import '../widgets/weekday_header_strip.dart';
import 'app_shell_search_scope.dart';
import 'calendar_import_screen.dart';
import 'combined_programs_screen.dart';
import 'contradb_program_import_screen.dart';
import 'plaintext_program_import_screen.dart';
import 'program_editor_screen.dart';
import 'perform_program_screen.dart' show PerformResumeStore;
import 'program_summary_screen.dart';
import 'recently_deleted_screen.dart';
import '../export/csv_export.dart';
import '../widgets/adaptive_fab.dart';
import '../widgets/programs_csv_export_action.dart';

/// The program-import sources offered by the Programs list "Import" menu.
enum _ProgramImportSource { plaintext, contraDb, calendar }

enum _ProgramsCompactAction {
  importPlaintext,
  importContraDb,
  importCalendar,
  exportCalendar,
  toggleArchived,
  exportCsv,
  recentlyDeleted,
  selectPrograms,
}

/// Programs list (`docs/design/ux.md` §4): non-deleted programs with title,
/// event date, venue, slot count and a status chip (icon+text). Sort by title /
/// recently-updated / event date; swipe-to-delete with undo; empty state that
/// teaches. Mirrors [DanceListScreen].
///
/// Archived programs are left out unless the ⋮ menu's "Show archived" is on,
/// and then they are listed alongside the rest with an "Archived" chip. The
/// choice lives in this [State], so it outlasts opening a program, the
/// builder, a rotation across the split breakpoint (the shell's [GlobalKey]),
/// and a trip to Recently deleted; it is cleared when [isActive] goes false,
/// which the app shell does when another top-level destination is chosen, and
/// it is never saved, so it starts off on every launch.
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
    this.performResumeStore,
    this.isActive = true,
    this.onSelectedProgramHidden,
    this.calendarExportDelivery,
    this.csvExportDelivery = const CsvExportDelivery(),
  });

  /// Delivers the **Export programs as CSV** file (#2333); a test seam.
  final CsvExportDelivery csvExportDelivery;

  final void Function(String programId)? onSelectProgram;

  /// Called (split-pane mode) when the selected program ([selectedProgramId])
  /// stops being listed while it still exists, for whatever reason: archived
  /// from its row (or by a sync or import) while archived programs are hidden,
  /// hidden by "Hide archived", or hidden when leaving the Programs tab turns
  /// "Show archived" off. It is also checked when a rotation into the split
  /// layout hands over a selection. The host closes it, as it does when the
  /// program leaves through its own Archive or Delete (the maintainer's
  /// decision on #2218; the tab-leave case is this list's own consequence of
  /// it).
  final VoidCallback? onSelectedProgramHidden;

  /// Whether the Programs destination is the one showing. Leaving it (true to
  /// false) hides archived programs again; see the class comment.
  final bool isActive;

  /// Called (split-pane mode) when the user taps "New program", with the
  /// program template they chose (#2337), so the parent can host the create
  /// flow in a pane. When null, a route is pushed.
  final void Function(ProgramTemplateChoice templateChoice)? onCreateProgram;

  final String? selectedProgramId;

  /// Handed to the summary this list opens in narrow mode: see
  /// [ProgramSummaryPane.performResumeStore].
  final PerformResumeStore? performResumeStore;

  /// Test seam for "Export calendar (.ics)"; defaults to the production
  /// dialogs and file delivery.
  final CalendarExportDelivery? calendarExportDelivery;

  @override
  State<ProgramsListScreen> createState() => _ProgramsListScreenState();
}

class _ProgramsListScreenState extends State<ProgramsListScreen> {
  late CompendiumRepositories _repos;

  /// Programs whose ⋮ → Delete is between the tap and the end of the delete.
  /// The confirm reads the calling-history count before its dialog opens
  /// (LIFE-6), so reopening the menu and choosing Delete again in that gap
  /// would stack a second confirmation for the same program.
  final Set<String> _deletingIds = {};

  /// Whether one-time setup has run. **This is a contract between two changes
  /// that arrived from opposite directions, and neither states it alone.**
  ///
  /// The subscription is opened exactly once per [State] — issue #768, so that
  /// a rebuild neither drops nor duplicates it. Issue #895 then gave
  /// this list a [GlobalKey] inside [ProgramsShell] so this State *survives* being reparented
  /// across the 900 px split breakpoint (`programs_shell.dart`), and the app
  /// shell's body key moves the whole page across the 720 px rail breakpoint
  /// (`app_shell.dart`); together they preserve the sort and scroll position
  /// through a rotation.
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

  /// The forms of each program's dances, live
  /// ([ProgramRepository.watchFormsByProgram]).
  Map<String, Set<DanceForm>> _formsById = const {};
  StreamSubscription<Map<String, Set<DanceForm>>>? _formsSub;

  /// The type filter: only programs whose dances are of these forms, compared
  /// as [_formMatch] says ([formsMatch]), and the open program whatever its
  /// forms. Null shows every program. Dropped once it is no longer one of the
  /// chips. Not saved.
  Set<DanceForm>? _formFilter;

  /// Whether the type filter keeps programs of only the chosen forms or every
  /// program that includes them. Not saved, like the filter.
  FormMatch _formMatch = FormMatch.only;
  Object? _loadError;
  ProgramSort _sort = ProgramSort.title;
  SortDirection _sortDir = ProgramSort.title.defaultDirection;

  /// Whether archived programs are listed too ("Show archived"). Session-only;
  /// see the class comment for when it resets.
  bool _showArchived = false;

  /// Whether the list is selecting programs for the combined view (#2349),
  /// with Settings ▸ Experimental ▸ Weekends and series on. Session-only, like
  /// [_showArchived]: it ends when the Programs destination is left or the
  /// setting is turned off.
  bool _selectionMode = false;

  /// The programs checked while [_selectionMode] is on. Like the Collection's
  /// (docs/design/bulk-selection.md, N4-1), a program the type filter or
  /// "Hide archived" stops listing stays checked, and the count line says how
  /// many are not shown; a program deleted or gone is dropped.
  final CollectionSelection _selection = CollectionSelection();

  void _enterSelectionMode() => setState(() => _selectionMode = true);

  void _exitSelectionMode() => setState(() {
    _selectionMode = false;
    _selection.clear();
  });

  Set<String> get _shownIds => {for (final p in _visiblePrograms) p.id};

  /// Opens the combined view of the checked programs, in the order the view
  /// sorts them (by event date), not the order they were checked in.
  Future<void> _openCombinedView() async {
    final ids = _selection.snapshot();
    if (ids.length < 2) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CombinedProgramsScreen(programIds: ids),
      ),
    );
  }

  @override
  void didUpdateWidget(ProgramsListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive && _selectionMode) {
      _exitSelectionMode();
    }
    if (oldWidget.isActive && !widget.isActive && _showArchived) {
      setState(() => _showArchived = false);
      _closeHiddenSelection();
    } else if (oldWidget.selectedProgramId != widget.selectedProgramId ||
        (oldWidget.onSelectedProgramHidden == null) !=
            (widget.onSelectedProgramHidden == null)) {
      // A rotation into the split layout hands this list a selection (and the
      // callback) the narrow layout kept while the list could not report it:
      // a program hidden while narrow must close now, not at the next write.
      _closeHiddenSelection();
    }
  }

  void _toggleShowArchived() {
    setState(() {
      _showArchived = !_showArchived;
      _dropStaleFormFilter();
    });
    _closeHiddenSelection();
  }

  /// Clears [_formFilter] once it is no longer one of the chips, so it can't
  /// come back on its own when a later program does. Call within setState.
  void _dropStaleFormFilter() {
    if (_activeFormFilter == null) _formFilter = null;
  }

  /// Tells the host when the selected program is in the data but no longer
  /// listed, after the frame (the host's `setState` must not run mid-build).
  void _closeHiddenSelection() {
    final selected = widget.selectedProgramId;
    final onHidden = widget.onSelectedProgramHidden;
    if (selected == null || onHidden == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.selectedProgramId != selected) return;
      final all = _programs ?? const <Program>[];
      final exists = all.any((p) => p.id == selected);
      final listed = _visiblePrograms.any((p) => p.id == selected);
      if (exists && !listed) onHidden();
    });
  }

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
    // Turning Weekends and series off ends a selection in progress; the build
    // that follows shows the plain list. Read whether or not a selection is
    // in progress, so the dependency is always registered.
    final seriesOn = WeekendsAndSeriesScope.of(context);
    if (_selectionMode && !seriesOn) {
      _selectionMode = false;
      _selection.clear();
    }
    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
      _subscribe();
      // Fire-and-forget: unlike the Collection list, sorting here is a pure
      // client-side re-order of already-loaded data (`_sortedPrograms`), not a
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
    // A stream of its own: a program's forms change when one of its dances
    // is deleted, restored or changes form, none of which [watchAll] sees.
    _formsSub = _repos.programs.watchFormsByProgram().listen(
      (forms) {
        if (!mounted) return;
        setState(() {
          _formsById = forms;
          _dropStaleFormFilter();
        });
        _closeHiddenSelection();
      },
      onError: (Object error, StackTrace stackTrace) => logCaughtError(
        error,
        stackTrace,
        source: 'programs_list_screen._subscribe forms',
      ),
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

  /// Seeds `_sort` and `_sortDir` from the saved default Programs sort order
  /// (issue #895), at most once and only if the user hasn't already chosen a
  /// sort this session. The direction comes from the last-used keys under
  /// "Last used", otherwise from the default's own direction key (issue #1841),
  /// falling back to the sort's natural direction. A `null`/invalid stored sort
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
      // A fixed default opens in the direction chosen in Settings ▸ Defaults
      // (issue #1841), or the sort's natural direction when none is stored or
      // it is unrecognised. Never the last-used direction, so this branch never
      // reads the last-used keys.
      sort = mode.sort;
      direction = sort.defaultDirection;
      try {
        direction =
            sortDirectionFromName(
              await _repos.settings.get(kDefaultProgramSortDirectionKey),
            ) ??
            direction;
      } catch (_) {
        // diagnostics: silent — direction read failed; the fixed sort still
        // applies, in its natural direction.
      }
      if (!mounted || _sortUserSet) return;
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
    unawaited(_formsSub?.cancel());
    super.dispose();
  }

  void _onPrograms(
    ({List<Program> programs, Map<String, Venue> venuesById}) snapshot,
  ) {
    if (!mounted) return;
    setState(() {
      _programs = snapshot.programs;
      _venuesById = snapshot.venuesById;
      _dropStaleFormFilter();
      _loadError = null;
      // A checked program that was deleted, here or on another device, is
      // gone rather than hidden (N4-1).
      _selection.reconcile({for (final p in snapshot.programs) p.id});
    });
    _closeHiddenSelection();
    final focusIds = _pendingFocusIds;
    if (focusIds.isEmpty) return;
    _pendingFocusIds = const [];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      restoreFocusToRowMenu(
        context,
        candidateKeys: [
          for (final id in focusIds) ValueKey('program-actions-$id'),
        ],
      );
    });
  }

  /// Programs, nearest first, whose ⋮ button should take focus when the next
  /// list snapshot lands: the neighbours of a deleted row (next, else
  /// previous), or the restored row after an Undo. A deleted row leaves the
  /// tree only when the stream re-emits, so focus cannot be moved before then.
  /// See [restoreFocusToRowMenu] for when it is actually moved.
  List<String> _pendingFocusIds = const [];

  /// The ids to refocus once `sorted[index]` is deleted: the next row, else the
  /// previous one.
  List<String> _neighbourIds(List<Program> sorted, int index) => [
    if (index + 1 < sorted.length) sorted[index + 1].id,
    if (index > 0) sorted[index - 1].id,
  ];

  /// Day-precision event dates (time-of-day dropped) for the "this week"
  /// header strip's markers (ROADMAP G.8's first-day-of-week consumer).
  static Set<DateTime> _programEventDates(List<Program> programs) => {
    for (final program in programs)
      if (program.eventDate case final date?)
        DateTime(date.year, date.month, date.day),
  };

  /// The programs this list shows: all of them with "Show archived" on, else
  /// the ones not archived; with a type filter, those of its forms. The open
  /// program stays listed whatever its forms, so neither a chip nor a dance
  /// of another form added to it closes it.
  List<Program> get _visiblePrograms {
    final filter = _activeFormFilter;
    final open = widget.selectedProgramId;
    return [
      for (final program in _unfilteredPrograms)
        if (filter == null ||
            program.id == open ||
            formsMatch(_formsById[program.id], filter, _formMatch))
          program,
    ];
  }

  /// The programs shown before the type filter: all, or the unarchived.
  Iterable<Program> get _unfilteredPrograms => (_programs ?? const <Program>[])
      .where((p) => _showArchived || !p.isArchived);

  /// [_formFilter] while it is still one of the chips; null once it is not
  /// (its last program changed, or was archived or deleted, no second mix is
  /// left to offer chips at all, or the switch between Only and Includes
  /// changed the chips), so a filter is never on without a chip to show it
  /// and clear it.
  Set<DanceForm>? get _activeFormFilter {
    final filter = _formFilter;
    if (filter == null) return null;
    return _formChoiceSets().any((m) => sameForms(m, filter)) ? filter : null;
  }

  /// The sets of forms the type filter offers as chips, in no particular
  /// order; empty unless there are at least two mixes among the programs
  /// shown with no type filter. With [FormMatch.only], each mix is a chip.
  /// With [FormMatch.includes], each form in any of them is one, so Contra
  /// can list every program with a contra dance even when none is contra
  /// only. A form every program with dances has gets a chip too, though it
  /// hides only programs with no dances, so that no type present goes
  /// missing from the row (Hudson, 21 November 2026).
  List<Set<DanceForm>> _formChoiceSets() {
    final mixes = _distinctMixes();
    if (mixes.length < 2) return const [];
    return switch (_formMatch) {
      FormMatch.only => mixes,
      FormMatch.includes => [
        for (final form in DanceForm.values)
          if (mixes.any((m) => m.contains(form))) {form},
      ],
    };
  }

  /// Each distinct set of forms among the programs shown with no type
  /// filter, in no particular order.
  List<Set<DanceForm>> _distinctMixes() {
    final mixes = <String, Set<DanceForm>>{};
    for (final program in _unfilteredPrograms) {
      final forms = _formsById[program.id];
      if (forms == null || forms.isEmpty) continue;
      mixes[([for (final f in forms) f.name]..sort()).join('+')] = forms;
    }
    return mixes.values.toList();
  }

  /// The type filter's chips ([_formChoiceSets]) in the order of their
  /// labels.
  List<Set<DanceForm>> _formChoices(AppLocalizations l10n) {
    final choices = <String, Set<DanceForm>>{
      for (final forms in _formChoiceSets())
        programFormsLabel(l10n, forms)!: forms,
    };
    final labels = choices.keys.toList()..sort();
    return [for (final label in labels) choices[label]!];
  }

  Widget _formFilterRow(AppLocalizations l10n, List<Set<DanceForm>> choices) =>
      Padding(
        key: const ValueKey('programs-form-filter'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          0,
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                container: true,
                label: l10n.programsFormMatchLabel,
                child: SegmentedButton<FormMatch>(
                  key: const ValueKey('programs-form-match'),
                  segments: [
                    ButtonSegment(
                      value: FormMatch.only,
                      label: Text(l10n.programsFormMatchOnly),
                      tooltip: l10n.programsFormMatchOnlyTooltip,
                    ),
                    ButtonSegment(
                      value: FormMatch.includes,
                      label: Text(l10n.programsFormMatchIncludes),
                      tooltip: l10n.programsFormMatchIncludesTooltip,
                    ),
                  ],
                  selected: {_formMatch},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) => setState(() {
                    _formMatch = selection.single;
                    // A chip that the other mode doesn't offer is dropped,
                    // such as Contra + English (ECD) under Includes.
                    _dropStaleFormFilter();
                  }),
                ),
              ),
              for (final forms in choices)
                FilterChip(
                  key: ValueKey(
                    'programs-form-${[for (final f in DanceForm.values)
                      if (forms.contains(f)) f.name].join('+')}',
                  ),
                  label: Text(programFormsLabel(l10n, forms)!),
                  selected:
                      _activeFormFilter != null &&
                      sameForms(forms, _activeFormFilter!),
                  onSelected: (selected) =>
                      setState(() => _formFilter = selected ? forms : null),
                ),
            ],
          ),
        ),
      );

  List<Program> _sortedPrograms({required bool ignoreLeadingArticles}) {
    final programs = _visiblePrograms;
    final descending = _sortDir == SortDirection.descending;
    int flip(int cmp) => descending ? -cmp : cmp;
    switch (_sort) {
      case ProgramSort.title:
        // The same key the Collection and the program dance picker sort by, so
        // "Ignore leading articles when sorting" governs this list too.
        String key(Program p) => ignoreLeadingArticles
            ? titleSortKey(p.title)
            : foldForTitleMatch(p.title);
        programs.sort((a, b) => flip(key(a).compareTo(key(b))));
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

  /// New program: asks which template to start from when there are two or
  /// more (#2337), then opens the builder. Dismissing the chooser cancels.
  Future<void> _openNewProgram() async {
    final choice = await chooseProgramTemplate(context);
    if (choice == null || !mounted) return;
    if (widget.onCreateProgram != null) {
      widget.onCreateProgram!(choice);
      return;
    }
    await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ProgramEditorScreen(templateChoice: choice),
      ),
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
        builder: (_) => ProgramSummaryScreen(
          programId: id,
          performResumeStore: widget.performResumeStore,
        ),
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

  /// Opens the calendar import (#2352). It creates drafts and offers Undo
  /// itself; the list shows them through its stream.
  Future<void> _openCalendarImport() async {
    await Navigator.of(context).push<List<String>>(
      MaterialPageRoute<List<String>>(
        builder: (_) => const CalendarImportScreen(),
      ),
    );
  }

  Future<void> _softDelete(Program program, List<String> focusAfter) async {
    _pendingFocusIds = focusAfter;
    var deleted = false;
    try {
      await _repos.programs.softDelete(program.id, at: DateTime.now().toUtc());
      deleted = true;
    } finally {
      // Nothing was deleted, so no later snapshot should move focus.
      if (!deleted) _pendingFocusIds = const [];
    }
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
      undoFailedMessage: l10n.commonUndoFailed,
      accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
      onUndo: () async {
        // A plain field write, safe on a disposed State, and not a `mounted`
        // guard on the restore itself (see above).
        _pendingFocusIds = [program.id];
        await _repos.programs.restore(program.id, at: DateTime.now().toUtc());
        // No `mounted` check and no context read, and nothing captured above
        // to bump: the restore is a write and the stream carries it, to this
        // list and to every other view of the program.
      },
    );
  }

  /// Archives [program] from its row's ⋮ menu, with an Undo. Focus moves as for
  /// a delete when the row leaves the list (archived programs hidden), and
  /// stays on the row when it does not.
  Future<void> _archive(Program program, List<String> focusAfter) async {
    _pendingFocusIds = _showArchived ? [program.id] : focusAfter;
    final archived = await _repos.programs.archive(
      program.id,
      at: DateTime.now().toUtc(),
    );
    // Only a write that happened is announced: `false` means the program was
    // archived or deleted elsewhere meanwhile, and the stream shows that.
    if (!archived) _pendingFocusIds = const [];
    if (!archived || !mounted) return;
    final l10n = AppLocalizations.of(context);
    showUndoSnackBar(
      ScaffoldMessenger.of(context),
      key: const ValueKey('program-archived-snackbar'),
      message: l10n.programsArchivedSnack(program.title),
      undoLabel: l10n.commonUndo,
      undoFailedMessage: l10n.commonUndoFailed,
      accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
      onUndo: () async {
        // A write the stream carries, as for the delete's Undo above.
        _pendingFocusIds = [program.id];
        await _repos.programs.unarchive(program.id, at: DateTime.now().toUtc());
      },
    );
  }

  /// Unarchives [program] from its row's ⋮ menu (only offered while archived
  /// programs are shown). The row stays where it is.
  Future<void> _unarchive(Program program) async {
    final unarchived = await _repos.programs.unarchive(
      program.id,
      at: DateTime.now().toUtc(),
    );
    if (!unarchived || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey('program-unarchived-snackbar'),
        content: Text(
          AppLocalizations.of(context).programsUnarchivedSnack(program.title),
        ),
      ),
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
    final searchPrograms = AppShellSearchScope.of(context)?.searchPrograms;
    return Scaffold(
      appBar: _selectionMode
          ? _buildSelectionAppBar(l10n)
          : AppBar(
              title: Text(l10n.programsTitle),
              actions: [
                // Phone-only: a search of programs alone (the bottom-right FAB slot
                // is reserved for the "New program" FAB). On wide layouts the nav
                // rail owns search, so no scope is present and this action is omitted.
                if (searchPrograms != null)
                  IconButton(
                    key: const ValueKey('programs-search'),
                    tooltip: l10n.programsSearchTooltip,
                    icon: const Icon(Icons.search),
                    onPressed: searchPrograms,
                  ),
                // Second entry to Settings ▸ Sync now; renders nothing unless Device
                // Sync is on and paired.
                const SyncNowAction(),
                if (_programs != null) ...[
                  // Overflow ⋮ goes last, as on every other app bar.
                  if (searchPrograms == null)
                    PopupMenuButton<_ProgramImportSource>(
                      key: const ValueKey('programs-import'),
                      tooltip: l10n.importProgramTooltip,
                      icon: const Icon(Icons.file_download_outlined),
                      onSelected: (source) => switch (source) {
                        _ProgramImportSource.plaintext =>
                          _openPlaintextImport(),
                        _ProgramImportSource.contraDb => _openContraDbImport(),
                        _ProgramImportSource.calendar => _openCalendarImport(),
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
                        PopupMenuItem(
                          key: const ValueKey('programs-import-calendar'),
                          value: _ProgramImportSource.calendar,
                          child: ListTile(
                            leading: const Icon(Icons.event_outlined),
                            title: Text(l10n.importFromCalendar),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  // Nothing to sort until there is a program.
                  if (_programs!.isNotEmpty) ...[
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
                  if (searchPrograms != null)
                    _buildCompactMoreActions(l10n)
                  else
                    PopupMenuButton<_ProgramsCompactAction>(
                      key: const ValueKey('programs-more-actions'),
                      tooltip: l10n.danceMoreActions,
                      icon: const Icon(Icons.more_vert),
                      onSelected: (action) => switch (action) {
                        _ProgramsCompactAction.toggleArchived =>
                          _toggleShowArchived(),
                        _ProgramsCompactAction.exportCalendar =>
                          _exportCalendar(),
                        _ProgramsCompactAction.exportCsv => _exportCsv(),
                        _ProgramsCompactAction.selectPrograms =>
                          _enterSelectionMode(),
                        _ => _openRecentlyDeleted(),
                      },
                      itemBuilder: (context) => [
                        ?_selectProgramsMenuItem(l10n),
                        _exportCalendarMenuItem(l10n),
                        _exportCsvMenuItem(l10n),
                        _showArchivedMenuItem(l10n),
                        PopupMenuItem(
                          key: const ValueKey('programs-recently-deleted'),
                          value: _ProgramsCompactAction.recentlyDeleted,
                          child: Text(l10n.collectionRecentlyDeletedTooltip),
                        ),
                      ],
                    ),
                ],
              ],
            ),
      body: _buildBody(),
      // The floating New is for a list: the empty state carries its own New
      // program button, so it waits until there is a program. Selecting
      // programs hides it, as selecting dances hides New dance.
      floatingActionButton: _programs?.isNotEmpty != true || _selectionMode
          ? null
          : adaptiveExtendedFab(
              context,
              key: const ValueKey('new-program'),
              heroTag: 'new-program',
              onPressed: _openNewProgram,
              icon: const Icon(Icons.add),
              label: l10n.programsNewProgram,
            ),
    );
  }

  /// **Select programs** in the ⋮ menu (#2349): only while Settings ▸
  /// Experimental ▸ Weekends and series is on and there is a program.
  PopupMenuItem<_ProgramsCompactAction>? _selectProgramsMenuItem(
    AppLocalizations l10n,
  ) {
    if (!WeekendsAndSeriesScope.of(context)) return null;
    if (_programs?.isNotEmpty != true) return null;
    return PopupMenuItem(
      key: const ValueKey('programs-select-programs'),
      value: _ProgramsCompactAction.selectPrograms,
      child: Text(l10n.programsSelectPrograms),
    );
  }

  /// The selection bar while selecting programs (#2349), laid out as the
  /// Collection's: a close button, the live-region count, and the one action,
  /// **Combined view**, which needs two programs.
  PreferredSizeWidget _buildSelectionAppBar(AppLocalizations l10n) {
    final count = _selection.length;
    final canCombine = count >= 2;
    return AppBar(
      leading: IconButton(
        key: const ValueKey('programs-selection-exit'),
        tooltip: l10n.collectionExitSelectionTooltip,
        icon: const Icon(Icons.close),
        onPressed: _exitSelectionMode,
      ),
      title: Semantics(
        liveRegion: true,
        child: Text(l10n.collectionSelectedCount(count)),
      ),
      actions: [
        // An icon with a tooltip, like the Collection's batch actions, so the
        // bar fits a narrow list pane in every language.
        IconButton(
          key: const ValueKey('programs-combined-view'),
          tooltip: canCombine
              ? l10n.programsCombinedViewTooltip
              : l10n.programsCombinedViewNeedsTwo,
          onPressed: canCombine ? _openCombinedView : null,
          icon: const Icon(Icons.table_chart_outlined),
        ),
        // Show archived stays reachable while selecting, so an archived
        // program can be added to the set (#2349), as the type chips stay.
        PopupMenuButton<_ProgramsCompactAction>(
          key: const ValueKey('programs-selection-more'),
          tooltip: l10n.danceMoreActions,
          icon: const Icon(Icons.more_vert),
          onSelected: (_) => _toggleShowArchived(),
          itemBuilder: (context) => [_showArchivedMenuItem(l10n)],
        ),
      ],
    );
  }

  /// "Export calendar (.ics)" in the ⋮ menu on every layout (#2351).
  PopupMenuItem<_ProgramsCompactAction> _exportCalendarMenuItem(
    AppLocalizations l10n,
  ) => PopupMenuItem(
    key: const ValueKey('programs-export-calendar'),
    value: _ProgramsCompactAction.exportCalendar,
    child: Text(l10n.programsExportCalendar),
  );

  /// Picks programs for a calendar file and exports them (#2351): upcoming
  /// ones ticked, past ones behind a switch, as [calendarExportCandidates]
  /// splits them at today's date ([clock], so tests can move it).
  Future<void> _exportCalendar() async {
    final programs = _programs;
    if (programs == null) return;
    final venuesById = _venuesById;
    // The share sheet's anchor, captured before any await: on iPad,
    // share_plus needs a non-zero origin for its popover. The list's own
    // rect stands in for the ⋮ button, which the menu has closed by now.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    final now = clock.now();
    final candidates = calendarExportCandidates(
      programs,
      DateTime(now.year, now.month, now.day),
    );
    final chosen = await CalendarProgramPickerDialog.show(
      context,
      upcoming: candidates.upcoming,
      past: candidates.past,
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;
    final l10n = AppLocalizations.of(context);
    await guardExport(
      ScaffoldMessenger.of(context),
      l10n.exportCalendarShareError,
      () => (widget.calendarExportDelivery ?? const CalendarExportDelivery())
          .export(
            context,
            programs: chosen,
            venuesById: venuesById,
            fileName: chosen.length == 1
                ? programCalendarFileName(chosen.single)
                : calendarMultiFileName,
            subject: l10n.exportCalendarPickTitle,
            sharePositionOrigin: origin,
          ),
      source: 'programs_list_screen._exportCalendar',
    );
  }

  /// "Show archived" / "Hide archived", just above "Recently deleted" in the
  /// ⋮ menu on every layout.
  PopupMenuItem<_ProgramsCompactAction> _showArchivedMenuItem(
    AppLocalizations l10n,
  ) => PopupMenuItem(
    key: const ValueKey('programs-toggle-archived'),
    value: _ProgramsCompactAction.toggleArchived,
    child: Text(
      _showArchived ? l10n.programsHideArchived : l10n.programsShowArchived,
    ),
  );

  /// "Export programs as CSV" (#2333), just above "Show archived", whose
  /// choice decides whether archived programs are in the file ("Show
  /// archived" keeps its place just above "Recently deleted"). Off while the
  /// view lists no program.
  PopupMenuItem<_ProgramsCompactAction> _exportCsvMenuItem(
    AppLocalizations l10n,
  ) => PopupMenuItem(
    key: const ValueKey('programs-export-csv'),
    value: _ProgramsCompactAction.exportCsv,
    enabled: _visiblePrograms.isNotEmpty,
    child: Text(l10n.programsExportCsv),
  );

  /// Exports the programs this list shows, in its order: the current view,
  /// with archived programs only while "Show archived" is on.
  Future<void> _exportCsv() {
    // The share sheet's anchor, as in [_exportCalendar]: the list's own rect
    // stands in for the ⋮ button, which the menu has closed by now.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    return exportProgramsCsv(
      context,
      programIds: [
        for (final p in _sortedPrograms(
          ignoreLeadingArticles: SortIgnoreArticlesScope.of(context),
        ))
          p.id,
      ],
      delivery: widget.csvExportDelivery,
      origin: origin,
      source: 'programs_list_screen._exportCsv',
    );
  }

  Widget _buildCompactMoreActions(AppLocalizations l10n) {
    return PopupMenuButton<_ProgramsCompactAction>(
      key: const ValueKey('programs-more-actions'),
      tooltip: l10n.danceMoreActions,
      icon: const Icon(Icons.more_vert),
      onSelected: (action) {
        switch (action) {
          case _ProgramsCompactAction.importPlaintext:
            _openPlaintextImport();
          case _ProgramsCompactAction.importContraDb:
            _openContraDbImport();
          case _ProgramsCompactAction.importCalendar:
            _openCalendarImport();
          case _ProgramsCompactAction.exportCalendar:
            _exportCalendar();
          case _ProgramsCompactAction.toggleArchived:
            _toggleShowArchived();
          case _ProgramsCompactAction.exportCsv:
            _exportCsv();
          case _ProgramsCompactAction.recentlyDeleted:
            _openRecentlyDeleted();
          case _ProgramsCompactAction.selectPrograms:
            _enterSelectionMode();
        }
      },
      itemBuilder: (context) => [
        ?_selectProgramsMenuItem(l10n),
        PopupMenuItem(
          value: _ProgramsCompactAction.importPlaintext,
          child: Text(l10n.importProgramFromTitleList),
        ),
        PopupMenuItem(
          value: _ProgramsCompactAction.importContraDb,
          child: Text(l10n.importProgramFromContraDb),
        ),
        PopupMenuItem(
          key: const ValueKey('programs-import-calendar'),
          value: _ProgramsCompactAction.importCalendar,
          child: Text(l10n.importProgramFromCalendar),
        ),
        _exportCalendarMenuItem(l10n),
        _exportCsvMenuItem(l10n),
        _showArchivedMenuItem(l10n),
        PopupMenuItem(
          key: const ValueKey('programs-recently-deleted'),
          value: _ProgramsCompactAction.recentlyDeleted,
          child: Text(l10n.collectionRecentlyDeletedTooltip),
        ),
      ],
    );
  }

  /// The program count, and while selecting, how many checked programs the
  /// list does not show, with **Deselect those not shown** (N4-1).
  Widget _countLine(AppLocalizations l10n, int shownCount) {
    final style = Theme.of(context).textTheme.bodySmall;
    final hidden = _selectionMode ? _selection.notShown(_shownIds) : 0;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(l10n.programsCount(shownCount), style: style),
        ),
        // Outside the live region: the bar title already announces each
        // change to the selection count.
        if (hidden > 0) ...[
          Text(
            ' · ${l10n.collectionSelectionNotShown(_selection.length, hidden)}',
            key: const ValueKey('programs-selection-not-shown'),
            style: style,
          ),
          const SizedBox(width: AppSpacing.xs),
          TextButton(
            key: const ValueKey('programs-deselect-not-shown'),
            onPressed: () {
              final shown = _shownIds;
              setState(() => _selection.deselectNotShown(shown));
            },
            child: Text(l10n.collectionDeselectNotShown),
          ),
        ],
      ],
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context);
    if (_loadError != null) {
      return LoadErrorView(
        icon: LoadErrorView.errorGlyph(context),
        message: l10n.programsListLoadError,
        onRetry: () {
          setState(() {
            _programs = null;
            _loadError = null;
          });
          _resubscribe();
        },
      );
    }

    final programs = _programs;
    if (programs == null) {
      return const SkeletonListView();
    }

    if (programs.isEmpty) {
      return EmptyState(
        key: const ValueKey('empty-state'),
        icon: BrandMark(
          size: 64,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        title: l10n.programsEmptyTitle,
        body: l10n.programsListEmptyBody,
        actions: [
          FilledButton.icon(
            key: const ValueKey('empty-new-program'),
            onPressed: _openNewProgram,
            icon: const Icon(Icons.add),
            label: Text(l10n.programsNewProgram),
          ),
        ],
      );
    }

    final sorted = _sortedPrograms(
      ignoreLeadingArticles: SortIgnoreArticlesScope.of(context),
    );
    if (sorted.isEmpty) {
      // Every program is archived, and archived programs are hidden. While
      // selecting, the count line stays, so checked archived programs are
      // still said to be selected but not shown (N4-1), and New program
      // waits, as the floating one does.
      final empty = EmptyState(
        key: const ValueKey('all-archived-state'),
        icon: EmptyState.glyph(context, Icons.archive_outlined),
        title: l10n.programsAllArchivedTitle,
        body: l10n.programsAllArchivedBody,
        actions: [
          OutlinedButton.icon(
            key: const ValueKey('empty-show-archived'),
            onPressed: _toggleShowArchived,
            icon: const Icon(Icons.visibility_outlined),
            label: Text(l10n.programsShowArchived),
          ),
          if (!_selectionMode)
            FilledButton.icon(
              key: const ValueKey('empty-new-program'),
              onPressed: _openNewProgram,
              icon: const Icon(Icons.add),
              label: Text(l10n.programsNewProgram),
            ),
        ],
      );
      if (!_selectionMode) return empty;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _countLine(l10n, 0),
            ),
          ),
          Expanded(child: empty),
        ],
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            0,
          ),
          child: WeekdayHeaderStrip(markedDates: _programEventDates(sorted)),
        ),
        if (_formChoices(l10n) case final choices when choices.isNotEmpty)
          _formFilterRow(l10n, choices),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _countLine(l10n, sorted.length),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            // Lets the last row scroll clear of the floating New program.
            padding: const EdgeInsets.only(bottom: AppSpacing.fabClearance),
            itemCount: sorted.length,
            itemBuilder: (context, index) {
              final program = sorted[index];
              // Swipe left to reveal a Delete button (issue #352). Tapping the
              // revealed Delete button is the confirmation — a swipe alone
              // never deletes. It routes into the same soft-delete + Undo flow
              // as the ⋮ menu, with no extra dialog on this path. The "Confirm
              // before delete" setting continues to gate only the ⋮ menu below.
              if (_selectionMode) {
                return ProgramListTile(
                  key: ValueKey('program-row-${program.id}'),
                  program: program,
                  venuesById: _venuesById,
                  forms: _formsById[program.id],
                  selectionMode: true,
                  checked: _selection.contains(program.id),
                  selected: _selection.contains(program.id),
                  onTap: () => setState(() => _selection.toggle(program.id)),
                );
              }
              return Slidable(
                key: ValueKey('slidable-${program.id}'),
                groupTag: 'programs-list',
                endActionPane: ActionPane(
                  motion: const DrawerMotion(),
                  extentRatio: 0.25,
                  children: [
                    SlidableAction(
                      key: ValueKey('slide-delete-${program.id}'),
                      onPressed: (_) =>
                          _softDelete(program, _neighbourIds(sorted, index)),
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
                  forms: _formsById[program.id],
                  selected:
                      widget.onSelectProgram != null &&
                      widget.selectedProgramId == program.id,
                  onTap: () => _openProgram(program.id),
                  // Row action menu (⋮): non-swipe access for mouse/keyboard/AT
                  // users. Unlike the Slidable swipe above, which deletes
                  // without a prompt, this path honours "Confirm before
                  // delete" (confirmDeleteProgramIfEnabled) before the shared
                  // soft-delete + undo flow.
                  onDelete: () async {
                    if (!_deletingIds.add(program.id)) return;
                    try {
                      if (await confirmDeleteProgramIfEnabled(
                        context,
                        itemLabel: program.title,
                        programId: program.id,
                        repositories: _repos,
                      )) {
                        await _softDelete(
                          program,
                          _neighbourIds(sorted, index),
                        );
                      }
                    } finally {
                      _deletingIds.remove(program.id);
                    }
                  },
                  onDuplicate: () => _duplicateFromList(program),
                  onArchive: () =>
                      _archive(program, _neighbourIds(sorted, index)),
                  onUnarchive: () => _unarchive(program),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
