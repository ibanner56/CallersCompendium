import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:printing/printing.dart';

import '../../l10n/app_localizations.dart';
import '../data/active_dialect_scope.dart';
import '../data/date_format_scope.dart';
import '../data/dialect_library_scope.dart';
import '../data/display_defaults.dart';
import '../data/regional_formats.dart';
import '../data/repositories_scope.dart';
import '../export/program_matrix_pdf.dart';
import '../search/collection_data.dart';
import '../theme/keyboard_dismiss.dart';
import '../utils/confirm_delete.dart';
import '../utils/safe_name.dart';
import '../utils/undo_snack_bar.dart';
import '../widgets/collection_picker.dart';
import 'perform_program_screen.dart';
import '../widgets/program_export_menu.dart';
import '../widgets/program_matrix_table.dart';
import '../widgets/program_slot_list_editor.dart';
import '../widgets/program_status_chip.dart';

/// Full-screen Program Builder (`docs/design/ux.md` §4).
///
/// Builds on the Phase 4.1 metadata editor with the slot list, a dance picker,
/// CC-parity event metadata (band / caller / dancer level), per-slot structured
/// fields (guest caller, planned minutes), ALT grouping, and mark-performed.
///
/// It is pushed as a **focused full-screen route** so its two-pane layout
/// (slots | picker) gets the full content width. It also still supports the
/// Phase 4.1 embedded callbacks so existing callers keep working, but its own
/// [LayoutBuilder] drives the internal responsive behaviour: wide (≥ ~820 px)
/// shows an inline persistent picker pane; narrow opens the picker in a modal
/// bottom sheet.
///
/// Language-neutral sentinel stored in [_ProgramEditorScreenState._loadError]
/// when the requested program no longer exists. Kept locale-independent (rather
/// than a resolved string) so the message re-localizes if the app language is
/// switched live while this retained editor is off-screen.
enum _ProgramLoadError { missing }

/// [programId] null ⇒ create a new program; otherwise edit that program.
class ProgramEditorScreen extends StatefulWidget {
  const ProgramEditorScreen({
    super.key,
    this.programId,
    this.onSaved,
    this.onDeleted,
    this.onNavigateTo,
  });

  final String? programId;

  /// Called after a successful save with the program's id (embedded mode).
  final void Function(String programId)? onSaved;

  /// Called after a successful soft-delete (embedded mode).
  final VoidCallback? onDeleted;

  /// Called after duplication with the new copy's id (embedded mode).
  final void Function(String programId)? onNavigateTo;

  /// Width (of the builder's own constraints) at/above which the picker shows
  /// as a persistent right pane instead of a modal sheet.
  static const double twoPaneBreakpoint = 820;

  bool get isNew => programId == null;
  bool get isEmbedded =>
      onSaved != null || onDeleted != null || onNavigateTo != null;

  @override
  State<ProgramEditorScreen> createState() => _ProgramEditorScreenState();
}

class _ProgramEditorScreenState extends State<ProgramEditorScreen>
    with SingleTickerProviderStateMixin {
  late CompendiumRepositories _repos;
  late final TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _venueController = TextEditingController();
  final _bandController = TextEditingController();
  final _callerController = TextEditingController();
  final _levelController = TextEditingController();
  final _notesController = TextEditingController();

  bool _loaded = false;
  Object? _loadError;

  Program? _existing;
  DateTime? _eventDate;
  ProgramStatus _status = ProgramStatus.draft;
  bool _hideAlternates = false;
  List<ProgramSlot> _slots = const [];
  CollectionData? _data;
  bool _saving = false;
  bool _dirty = false;

  /// In-memory Perform resume state (issue #434). Perform is pushed *on top* of
  /// this editor, so this field survives that navigation: on exit the Perform
  /// view hands back its live position + clock here, and the next launch threads
  /// it back in so re-entry resumes at the current slot with the clock intact
  /// instead of resetting to slot 1. Purely a UI concern, so it lives here
  /// rather than in the persisted program (ADR-001 keeps the domain Flutter-free).
  PerformResumeState? _performResume;

  Dialect _dialect = Dialect.larksRobins;

  /// Always-on search enrichment for the embedded [CollectionPicker], built
  /// from the union of every saved dialect (presets + custom) so the picker's
  /// search resolves saved-dialect vocabulary regardless of the active dialect
  /// — parity with the main Collection search. Rebuilt in
  /// [didChangeDependencies] when the library changes.
  SearchEnrichment _enrichment = SearchEnrichment.empty;

  /// The dialect list [_enrichment] was built from, used to avoid rebuilding
  /// the union when nothing changed.
  List<Dialect> _enrichmentDialects = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Rebuild so the save FAB can hide on the read-only Matrix tab.
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read the active dialect if a scope is present; tolerate its absence
    // (e.g. narrow embedded tests) with a sensible default.
    final scope = context
        .dependOnInheritedWidgetOfExactType<ActiveDialectScope>();
    if (scope?.notifier != null) _dialect = scope!.notifier!.value;

    // Build the always-on enrichment from the union of every saved dialect
    // (presets + custom). Registers a rebuild dependency on the library so a
    // dialect add/edit/delete updates the picker's search live.
    final library = DialectLibraryScope.maybeOf(context);
    final newDialects = library?.all ?? const <Dialect>[];
    if (!listEquals(newDialects, _enrichmentDialects)) {
      _enrichmentDialects = newDialects;
      _enrichment = SearchEnrichment.fromDialects(newDialects);
    }

    if (!_loaded && _loadError == null && _data == null) {
      _repos = RepositoriesScope.of(context);
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final data = await CollectionData.load(_repos);
      Program? program;
      if (!widget.isNew) {
        program = await _repos.programs.getById(widget.programId!);
        if (program == null) {
          if (!mounted) return;
          setState(() {
            _data = data;
            _loadError = _ProgramLoadError.missing;
            _loaded = true;
          });
          return;
        }
      }
      if (!mounted) return;
      if (program != null) {
        _titleController.text = program.title;
        _venueController.text = program.venue ?? '';
        _bandController.text = program.band ?? '';
        _callerController.text = program.caller ?? '';
        _levelController.text = program.dancerLevel ?? '';
        _notesController.text = program.notes;
      } else if (widget.isNew) {
        // ROADMAP G.3: prefill a new program's caller/band from saved defaults.
        // Only seeds a still-blank field, never overrides; a settings read
        // failure falls back silently to a blank field.
        await _prefillNewProgramDefaults();
      }
      setState(() {
        _data = data;
        _existing = program;
        _eventDate = program?.eventDate;
        _status = program?.status ?? ProgramStatus.draft;
        _hideAlternates = program?.hideAlternates ?? false;
        _slots = program?.slots.toList() ?? const [];
        _loaded = true;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error;
          _loaded = true;
        });
      }
    }
  }

  /// Seeds the caller/band controllers for a NEW program from the saved G.3
  /// defaults, only when the controller is still blank. Each key is read
  /// independently so a failure (or corrupt value) reading one never blocks the
  /// other, and a settings read failure is swallowed so the editor still opens
  /// (with that field blank).
  Future<void> _prefillNewProgramDefaults() async {
    await _prefillControllerFromDefault(
      _callerController,
      kDefaultProgramCallerKey,
    );
    await _prefillControllerFromDefault(
      _bandController,
      kDefaultProgramBandKey,
    );
  }

  Future<void> _prefillControllerFromDefault(
    TextEditingController controller,
    String key,
  ) async {
    if (controller.text.isNotEmpty) return;
    try {
      final stored = await _repos.settings.get(key);
      final value = stored is String ? stored.trim() : '';
      if (value.isNotEmpty) controller.text = value;
    } catch (_) {
      // Leave the field blank if this default can't be read.
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _venueController.dispose();
    _bandController.dispose();
    _callerController.dispose();
    _levelController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// Renumbers positions contiguously (0..n-1) in list order.
  List<ProgramSlot> _renumber(List<ProgramSlot> slots) => [
    for (var i = 0; i < slots.length; i++)
      slots[i].position == i ? slots[i] : slots[i].copyWith(position: i),
  ];

  String? _titleForDance(String danceId) => _data?.dancesById[danceId]?.title;

  /// Resolves a dance's formation for the slot editor's redundant accent +
  /// formation text (issue #270). Null when the dance is unavailable.
  Formation? _formationForDance(String danceId) =>
      _data?.dancesById[danceId]?.formation;

  /// Shared renderer for the large-print Perform view (mirrors the dance
  /// detail / single-dance Perform screens).
  static final FigureRenderer _performRenderer = FigureRenderer(contraTaxonomy);

  /// The program to hand to the large-print Perform view, assembled from the
  /// current (possibly unsaved) edits. Falls back to a placeholder title for a
  /// brand-new, still-untitled program so performing always works when slots
  /// exist. Returns null when there is nothing to perform.
  Program? _programToPerform(AppLocalizations l10n) {
    if (_slots.isEmpty) return null;
    final draft = _draftProgram;
    if (draft != null) return draft;
    final now = _existing?.createdAt ?? DateTime.now().toUtc();
    try {
      return Program(
        id: _existing?.id ?? 'draft',
        title: l10n.programsFallbackTitle,
        slots: _renumber(_slots),
        createdAt: now,
        updatedAt: now,
      );
    } catch (_) {
      return null;
    }
  }

  void _performProgram() {
    final data = _data;
    final program = _programToPerform(AppLocalizations.of(context));
    if (data == null || program == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PerformProgramScreen(
          program: program,
          data: data,
          renderer: _performRenderer,
          // Resume where the caller left off (issue #434): thread the last
          // position + clock back in, and capture the new one on exit. The
          // screen clamps a now-out-of-range group after edits.
          initialGroup: _performResume?.groupIndex ?? 0,
          initialElapsedSeconds: _performResume?.elapsedSeconds ?? 0,
          initialSlotStartSeconds: _performResume?.slotStartSeconds ?? 0,
          initialPaused: _performResume?.paused ?? false,
          onExit: (state) => _performResume = state,
          // In-event adjustments (`docs/design/ux.md` §5) fold back into the
          // builder's working slots. For an already-saved program this is the
          // real live-gig path (a tablet routed through the builder is the
          // primary Perform form factor), so — mirroring the wide summary
          // pane's persist callback in `programs_shell.dart` — we write the
          // change (e.g. a mark-performed stamp) straight to the repository
          // immediately. The editor has no autosave, so without this a
          // background/kill before an explicit Save would silently lose it.
          // A brand-new, still-unsaved program has nothing to update in the DB
          // yet, so its adjustments stay in the working slots to be saved
          // explicitly; a failed write falls back the same way rather than
          // dropping the change.
          onProgramChanged: (updated) async {
            if (!mounted) return;
            final slots = _renumber(updated.slots.toList());
            final existing = _existing;
            if (existing != null) {
              final persisted = existing.copyWith(
                slots: slots,
                updatedAt: DateTime.now().toUtc(),
              );
              try {
                await _repos.programs.update(persisted);
                if (!mounted) return;
                setState(() {
                  _existing = persisted;
                  _slots = slots;
                });
                return;
              } on Exception catch (_) {
                // Fall through to keep the change in the working slots.
              }
            }
            if (!mounted) return;
            setState(() {
              _slots = slots;
              _dirty = true;
            });
          },
        ),
      ),
    );
  }

  // --- Slot mutations -------------------------------------------------------

  void _addDanceSlot(String danceId) {
    setState(() {
      _slots = _renumber([
        ..._slots,
        ProgramSlot(id: uuidV4(), position: _slots.length, danceId: danceId),
      ]);
      _dirty = true;
    });
    final l10n = AppLocalizations.of(context);
    final title = _titleForDance(danceId) ?? l10n.programsUntitledDanceFallback;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.programsAddedDanceSnack(title))),
    );
    SemanticsService.sendAnnouncement(
      View.of(context),
      l10n.programsAddedDanceAnnounce(title),
      TextDirection.ltr,
    );
  }

  Future<void> _addFreeTextSlot() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _FreeTextSlotDialog(),
    );
    if (text == null || text.isEmpty || !mounted) return;
    setState(() {
      _slots = _renumber([
        ..._slots,
        ProgramSlot(id: uuidV4(), position: _slots.length, text: text),
      ]);
      _dirty = true;
    });
    SemanticsService.sendAnnouncement(
      View.of(context),
      AppLocalizations.of(context).programsAddedNoteAnnounce,
      TextDirection.ltr,
    );
  }

  void _insertBreakSlot() {
    setState(() {
      _slots = _renumber([
        ..._slots,
        ProgramSlot(
          id: uuidV4(),
          position: _slots.length,
          text: Program.breakSlotText,
        ),
      ]);
      _dirty = true;
    });
    SemanticsService.sendAnnouncement(
      View.of(context),
      AppLocalizations.of(context).programsAddedBreakAnnounce,
      TextDirection.ltr,
    );
  }

  void _reorderSlot(int oldIndex, int newIndex) {
    setState(() {
      final list = [..._slots];
      final item = list.removeAt(oldIndex);
      list.insert(newIndex.clamp(0, list.length), item);
      _slots = _renumber(list);
      _dirty = true;
    });
  }

  void _updateSlot(int index, ProgramSlot updated) {
    setState(() {
      final list = [..._slots];
      list[index] = updated;
      _slots = _renumber(list);
      _dirty = true;
    });
  }

  void _removeSlot(int index) {
    setState(() {
      final list = [..._slots]..removeAt(index);
      _slots = _renumber(list);
      _dirty = true;
    });
  }

  Future<void> _markAllPerformed() async {
    final now = DateTime.now().toUtc();
    final l10n = AppLocalizations.of(context);
    setState(() {
      _slots = [
        for (final s in _slots)
          s.danceId != null && s.performedAt == null
              ? s.copyWith(performedAt: now)
              : s,
      ];
      _dirty = true;
    });
    SemanticsService.sendAnnouncement(
      View.of(context),
      l10n.programsMarkedAllPerformed,
      TextDirection.ltr,
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.programsMarkedAllPerformed)));
  }

  // --- Persistence ----------------------------------------------------------

  /// The live program assembled from the current form + slots, used to drive
  /// warning-level validation (`orphaned_alt`) and export (share/copy/PDF).
  Program? get _draftProgram {
    final title = _titleController.text.trim();
    if (title.isEmpty) return null;
    final now = _existing?.createdAt ?? DateTime.now().toUtc();
    String? nn(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    try {
      final base =
          _existing ??
          Program(id: 'draft', title: title, createdAt: now, updatedAt: now);
      return base.copyWith(
        title: title,
        eventDate: _eventDate,
        clearEventDate: _eventDate == null,
        venue: nn(_venueController),
        clearVenue: nn(_venueController) == null,
        band: nn(_bandController),
        clearBand: nn(_bandController) == null,
        caller: nn(_callerController),
        clearCaller: nn(_callerController) == null,
        dancerLevel: nn(_levelController),
        clearDancerLevel: nn(_levelController) == null,
        notes: _notesController.text,
        status: _status,
        hideAlternates: _hideAlternates,
        slots: _renumber(_slots),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    final now = DateTime.now().toUtc();
    final title = _titleController.text.trim();
    final venue = _venueController.text.trim();
    final band = _bandController.text.trim();
    final caller = _callerController.text.trim();
    final level = _levelController.text.trim();
    final notes = _notesController.text.trim();
    final slots = _renumber(_slots);

    try {
      final String id;
      if (widget.isNew) {
        id = uuidV4();
        await _repos.programs.create(
          Program(
            id: id,
            title: title,
            eventDate: _eventDate,
            venue: venue.isEmpty ? null : venue,
            band: band.isEmpty ? null : band,
            caller: caller.isEmpty ? null : caller,
            dancerLevel: level.isEmpty ? null : level,
            notes: notes,
            status: _status,
            hideAlternates: _hideAlternates,
            slots: slots,
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else {
        id = _existing!.id;
        final updated = _existing!.copyWith(
          title: title,
          eventDate: _eventDate,
          clearEventDate: _eventDate == null,
          venue: venue.isEmpty ? null : venue,
          clearVenue: venue.isEmpty,
          band: band.isEmpty ? null : band,
          clearBand: band.isEmpty,
          caller: caller.isEmpty ? null : caller,
          clearCaller: caller.isEmpty,
          dancerLevel: level.isEmpty ? null : level,
          clearDancerLevel: level.isEmpty,
          notes: notes,
          status: _status,
          hideAlternates: _hideAlternates,
          slots: slots,
          updatedAt: now,
        );
        await _repos.programs.update(updated);
        _existing = updated;
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
        _slots = slots;
      });
      final messenger = ScaffoldMessenger.of(context);
      if (widget.isEmbedded) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.programsSavedSnack(title))),
        );
        widget.onSaved?.call(id);
      } else {
        Navigator.of(context).pop(id);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.programsSaveError)));
    }
  }

  Future<void> _duplicate() async {
    final source = _existing;
    if (source == null) return;
    final now = DateTime.now().toUtc();
    final copy = await _repos.programs.duplicate(
      id: source.id,
      newId: uuidV4(),
      newSlotId: uuidV4,
      now: now,
      newTitle: '${source.title} (copy)',
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context).programsDuplicatedSnack(copy.title),
        ),
      ),
    );
    if (widget.isEmbedded) {
      widget.onNavigateTo?.call(copy.id);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<String>(
          builder: (_) => ProgramEditorScreen(programId: copy.id),
        ),
      );
    }
  }

  Future<void> _delete() async {
    final source = _existing;
    if (source == null) return;
    final title = source.title;
    // ROADMAP G.7: optional confirm dialog before the (still-undoable) delete.
    if (!await confirmDeleteIfEnabled(context, itemLabel: title)) return;
    if (!mounted) return;
    await _repos.programs.softDelete(source.id, at: DateTime.now().toUtc());
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    showUndoSnackBar(
      messenger,
      message: l10n.programsDeletedSnack(title),
      undoLabel: l10n.commonUndo,
      accessibleNavigation: accessibleNavigation,
      onUndo: () =>
          _repos.programs.restore(source.id, at: DateTime.now().toUtc()),
    );
    if (widget.isEmbedded) {
      widget.onDeleted?.call();
    } else {
      Navigator.of(context).pop('deleted');
    }
  }

  // --- Unsaved-changes guard ------------------------------------------------

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final l10n = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.programsDiscardTitle),
        content: Text(l10n.programsDiscardBody),
        actions: [
          TextButton(
            key: const ValueKey('discard-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.programsKeepEditing),
          ),
          FilledButton(
            key: const ValueKey('discard-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.programsDiscard),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope<Object?>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final ok = await _confirmDiscard();
        if (!context.mounted) return;
        if (ok) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.isNew ? l10n.programsNewProgram : l10n.programsBuildProgram,
          ),
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                key: const ValueKey('program-build-tab'),
                icon: const Icon(Icons.list_alt_outlined),
                text: l10n.programsBuildTab,
              ),
              Tab(
                key: const ValueKey('program-matrix-tab'),
                icon: const Icon(Icons.grid_on_outlined),
                text: l10n.programsMatrixTab,
              ),
            ],
          ),
          actions: [
            if (_loaded &&
                _loadError == null &&
                _data != null &&
                _slots.isNotEmpty)
              IconButton(
                key: const ValueKey('perform-program'),
                tooltip: l10n.programsPerformTooltip,
                icon: const Icon(Icons.slideshow),
                onPressed: _performProgram,
              ),
            if (_loaded && _loadError == null && _draftProgram != null)
              ProgramExportMenu(
                program: _draftProgram!,
                titleFor: _titleForDance,
                danceFor: (id) => _data?.dancesById[id],
                choreographerFor: (id) => _data?.choreographersById[id],
              ),
            if (!widget.isNew && _existing != null) ...[
              if (_slots.any((s) => s.danceId != null))
                IconButton(
                  key: const ValueKey('mark-all-performed'),
                  tooltip: l10n.programsMarkAllPerformedTooltip,
                  icon: const Icon(Icons.done_all),
                  onPressed: _markAllPerformed,
                ),
              IconButton(
                key: const ValueKey('duplicate-program'),
                tooltip: l10n.commonDuplicate,
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: _duplicate,
              ),
              IconButton(
                key: const ValueKey('delete-program'),
                tooltip: l10n.commonDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
            ],
          ],
        ),
        body: TabBarView(
          controller: _tabController,
          children: [_buildBody(), _buildMatrixTab()],
        ),
        floatingActionButton:
            (_loaded && _loadError == null && _tabController.index == 0)
            ? FloatingActionButton.extended(
                key: const ValueKey('save-program'),
                heroTag: 'save-program',
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_dirty ? l10n.programsSaveDirty : l10n.commonSave),
              )
            : null,
      ),
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context);
    if (!_loaded) {
      return Center(
        child: CircularProgressIndicator(semanticsLabel: l10n.programsLoading),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _loadError == _ProgramLoadError.missing
                ? l10n.programsNoLongerExists
                : l10n.programsLoadError,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoPane =
            constraints.maxWidth >= ProgramEditorScreen.twoPaneBreakpoint;
        final left = _buildEditorColumn(twoPane: twoPane);
        if (!twoPane) return left;
        final data = _data;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            const VerticalDivider(width: 1, thickness: 1),
            if (data != null)
              Expanded(
                child: CollectionPicker(
                  key: const ValueKey('inline-picker'),
                  data: data,
                  dialect: _dialect,
                  enrichment: _enrichment,
                  onAddDance: _addDanceSlot,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMatrixTab() {
    final l10n = AppLocalizations.of(context);
    if (!_loaded) {
      return Center(
        child: CircularProgressIndicator(semanticsLabel: l10n.programsLoading),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _loadError == _ProgramLoadError.missing
                ? l10n.programsNoLongerExists
                : l10n.programsLoadError,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final data = _data;
    if (data == null) return const SizedBox.shrink();

    // Rows = dance slots in program order (flat). Free-text-only slots are
    // omitted; a slot referencing a soft-deleted dance renders a tombstone
    // row so the gap is still visible in the matrix. Per-row halves are
    // derived from the full ordered slot list (including the break and any
    // free-text slots) so the "1st"/"2nd" badge reflects the break position.
    final now = DateTime.now();
    final halvesForSlots = Program.halvesForSlots(_slots);
    final rows = <Dance>[];
    final rowHalves = <ProgramHalf?>[];
    final altDanceIds = <String>{};
    var omittedFreeText = 0;
    for (var i = 0; i < _slots.length; i++) {
      final slot = _slots[i];
      final danceId = slot.danceId;
      if (danceId == null) {
        omittedFreeText++;
        continue;
      }
      final dance =
          data.dancesById[danceId] ??
          Dance(
            id: danceId,
            title: l10n.programsDeletedDanceFallback,
            createdAt: now,
            updatedAt: now,
          );
      rows.add(dance);
      rowHalves.add(halvesForSlots[i]);
      if (slot.isAlt) altDanceIds.add(danceId);
    }

    final matrix = buildProgramMatrix(
      rows,
      taxonomy: data.taxonomy,
      halves: rowHalves,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                key: const ValueKey('program-matrix-export-pdf'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: l10n.exportMatrixPdfTooltip,
                onPressed: matrix.isEmpty
                    ? null
                    : () => _exportMatrixPdf(
                        matrix,
                        data.taxonomy,
                        omittedFreeText,
                      ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ProgramMatrixTable(
            key: const ValueKey('program-matrix-table'),
            matrix: matrix,
            taxonomy: data.taxonomy,
            dialect: _dialect,
            omittedFreeTextCount: omittedFreeText,
            altDanceIds: altDanceIds,
          ),
        ),
      ],
    );
  }

  Future<void> _exportMatrixPdf(
    ProgramMatrix matrix,
    Taxonomy taxonomy,
    int omittedFreeTextCount,
  ) async {
    final localizations = MaterialLocalizations.of(context);
    final l10n = AppLocalizations.of(context);
    final title = _titleController.text.trim();
    final venue = _venueController.text.trim();
    await Printing.layoutPdf(
      name: sanitizeExportName(title, fallback: l10n.exportMatrixPdfFilename),
      onLayout: (format) => buildProgramMatrixPdf(
        matrix,
        taxonomy: taxonomy,
        dialect: _dialect,
        programTitle: title,
        eventDate: _eventDate,
        venue: venue.isEmpty ? null : venue,
        omittedFreeTextCount: omittedFreeTextCount,
        formatDate: localizations.formatMediumDate,
      ),
    );
  }

  Widget _buildEditorColumn({required bool twoPane}) {
    final l10n = AppLocalizations.of(context);
    final draft = _draftProgram;
    final warnings = draft?.validate() ?? const <ValidationIssue>[];

    return Form(
      key: _formKey,
      child: ListView(
        keyboardDismissBehavior: kTextEntryKeyboardDismiss,
        padding: const EdgeInsets.all(16),
        children: [
          _buildMetadataSection(),
          const SizedBox(height: 24),
          if (warnings.isNotEmpty) ...[
            _ProgramWarningsCard(warnings: warnings),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Text(
                l10n.programsSlotsLabel,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              Text(
                '${_slots.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!twoPane)
                OutlinedButton.icon(
                  key: const ValueKey('add-dance-slot'),
                  onPressed: _openPickerSheet,
                  icon: const Icon(Icons.library_music_outlined),
                  label: Text(l10n.programsAddDanceButton),
                ),
              OutlinedButton.icon(
                key: const ValueKey('add-free-text-slot'),
                onPressed: _addFreeTextSlot,
                icon: const Icon(Icons.notes_outlined),
                label: Text(l10n.programsAddNoteBreakButton),
              ),
              OutlinedButton.icon(
                key: const ValueKey('insert-break-slot'),
                onPressed: _insertBreakSlot,
                icon: const Icon(Icons.free_breakfast_outlined),
                label: Text(l10n.programsInsertBreakButton),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ProgramSlotListEditor(
            slots: _slots,
            danceTitles: _titleForDance,
            formationFor: _formationForDance,
            onReorder: _reorderSlot,
            onSlotChanged: _updateSlot,
            onRemove: _removeSlot,
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> _openPickerSheet() async {
    final data = _data;
    if (data == null) return;
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 16),
                    Text(
                      l10n.programsAddADanceSheetTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      key: const ValueKey('picker-sheet-close'),
                      tooltip: l10n.commonClose,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
                Expanded(
                  child: CollectionPicker(
                    key: const ValueKey('sheet-picker'),
                    data: data,
                    dialect: _dialect,
                    enrichment: _enrichment,
                    scrollController: scrollController,
                    // Keep the sheet open so callers can add several dances.
                    onAddDance: _addDanceSlot,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMetadataSection() {
    final l10n = AppLocalizations.of(context);
    final dateLabel = _eventDate == null
        ? l10n.programsNoDateSet
        : formatEventDate(
            _eventDate!,
            DateFormatScope.of(context),
            MaterialLocalizations.of(context),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey('program-title'),
          controller: _titleController,
          autofocus: widget.isNew,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _markDirty(),
          decoration: InputDecoration(
            labelText: l10n.programsTitleLabel,
            hintText: l10n.programsTitleHint,
            border: const OutlineInputBorder(),
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? l10n.programsTitleRequired
              : null,
        ),
        const SizedBox(height: 16),
        InputDecorator(
          decoration: InputDecoration(
            labelText: l10n.programsEventDateLabel,
            border: const OutlineInputBorder(),
          ),
          child: Row(
            children: [
              Expanded(child: Text(dateLabel)),
              TextButton.icon(
                key: const ValueKey('pick-event-date'),
                onPressed: _pickEventDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(
                  _eventDate == null
                      ? l10n.programsSetDate
                      : l10n.programsChangeDate,
                ),
              ),
              if (_eventDate != null)
                IconButton(
                  key: const ValueKey('clear-event-date'),
                  tooltip: l10n.programsClearEventDate,
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() {
                    _eventDate = null;
                    _dirty = true;
                  }),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('program-venue'),
          controller: _venueController,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _markDirty(),
          decoration: InputDecoration(
            labelText: l10n.programsVenueLabel,
            hintText: l10n.programsVenueHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('program-band'),
          controller: _bandController,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _markDirty(),
          decoration: InputDecoration(
            labelText: l10n.programsBandLabel,
            hintText: l10n.programsBandHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('program-caller'),
          controller: _callerController,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _markDirty(),
          decoration: InputDecoration(
            labelText: l10n.programsCallerLabel,
            hintText: l10n.programsCallerHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('program-dancer-level'),
          controller: _levelController,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _markDirty(),
          decoration: InputDecoration(
            labelText: l10n.programsDancerLevelLabel,
            hintText: l10n.programsDancerLevelHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('program-notes'),
          controller: _notesController,
          minLines: 3,
          maxLines: 6,
          onChanged: (_) => _markDirty(),
          decoration: InputDecoration(
            labelText: l10n.programsNotesLabel,
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<ProgramStatus>(
          key: const ValueKey('program-status'),
          initialValue: _status,
          decoration: InputDecoration(
            labelText: l10n.programsStatusFieldLabel,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final status in ProgramStatus.values)
              DropdownMenuItem(
                value: status,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      programStatusPresentation(status, l10n).icon,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(programStatusPresentation(status, l10n).label),
                  ],
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _status = value;
                _dirty = true;
              });
            }
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const ValueKey('program-hide-alternates'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.programsHideAlternatesTitle),
          subtitle: Text(l10n.programsHideAlternatesSubtitle),
          value: _hideAlternates,
          onChanged: (value) {
            setState(() {
              _hideAlternates = value;
              _dirty = true;
            });
          },
        ),
      ],
    );
  }

  Future<void> _pickEventDate() async {
    final now = DateTime.now();
    final stored = _eventDate;
    final initial = stored == null
        ? now
        : DateTime(stored.year, stored.month, stored.day);
    // The date picker follows the platform locale's first day of week; a
    // configurable first-day-of-week preference is a future item (ROADMAP G.8).
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      setState(() {
        _eventDate = DateTime.utc(picked.year, picked.month, picked.day);
        _dirty = true;
      });
    }
  }
}

/// Non-blocking warnings card mirroring the dance editor's `_WarningsCard`,
/// surfacing `Program.validate()` issues (e.g. `orphaned_alt`) with icon+text.
class _ProgramWarningsCard extends StatelessWidget {
  const _ProgramWarningsCard({required this.warnings});

  final List<ValidationIssue> warnings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('program-warnings-card'),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  size: 18,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.programsWarningCount(warnings.length),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final w in warnings)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    w.message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Dialog for adding a free-text slot (break / waltz / announcement). Owns its
/// [TextEditingController] so it is disposed only after the dialog is gone,
/// avoiding "controller used after dispose" during the exit animation.
class _FreeTextSlotDialog extends StatefulWidget {
  const _FreeTextSlotDialog();

  @override
  State<_FreeTextSlotDialog> createState() => _FreeTextSlotDialogState();
}

class _FreeTextSlotDialogState extends State<_FreeTextSlotDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.programsAddNoteBreakDialogTitle),
      content: TextField(
        key: const ValueKey('free-text-slot-input'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: l10n.programsFreeTextLabel,
          hintText: l10n.programsFreeTextHint,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('free-text-slot-add'),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10n.commonAdd),
        ),
      ],
    );
  }
}
