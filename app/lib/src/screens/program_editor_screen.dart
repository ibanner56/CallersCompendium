import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:printing/printing.dart';

import '../data/active_dialect_scope.dart';
import '../data/display_defaults.dart';
import '../data/repositories_scope.dart';
import '../export/program_matrix_pdf.dart';
import '../search/collection_data.dart';
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
  List<ProgramSlot> _slots = const [];
  CollectionData? _data;
  bool _saving = false;
  bool _dirty = false;

  Dialect _dialect = Dialect.larksRobins;

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
            _loadError = 'This program no longer exists.';
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

  /// Shared renderer for the large-print Perform view (mirrors the dance
  /// detail / single-dance Perform screens).
  static final FigureRenderer _performRenderer = FigureRenderer(contraTaxonomy);

  /// The program to hand to the large-print Perform view, assembled from the
  /// current (possibly unsaved) edits. Falls back to a placeholder title for a
  /// brand-new, still-untitled program so performing always works when slots
  /// exist. Returns null when there is nothing to perform.
  Program? get _programToPerform {
    if (_slots.isEmpty) return null;
    final draft = _draftProgram;
    if (draft != null) return draft;
    final now = _existing?.createdAt ?? DateTime.now().toUtc();
    try {
      return Program(
        id: _existing?.id ?? 'draft',
        title: 'Program',
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
    final program = _programToPerform;
    if (data == null || program == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PerformProgramScreen(
          program: program,
          data: data,
          renderer: _performRenderer,
          // In-event adjustments (`docs/design/ux.md` §5) fold back into the
          // builder's working slots so they survive returning here and persist
          // through the editor's normal save — the draft may be unsaved, so we
          // never write it out from Perform directly.
          onProgramChanged: (updated) async {
            if (!mounted) return;
            setState(() {
              _slots = _renumber(updated.slots.toList());
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
    final title = _titleForDance(danceId) ?? 'dance';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Added "$title".')));
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Added $title to program.',
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
      'Added note to program.',
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
      'Marked all dances performed.',
      TextDirection.ltr,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Marked all dances performed.')),
    );
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
        slots: _renumber(_slots),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
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
        messenger.showSnackBar(SnackBar(content: Text('"$title" saved.')));
        widget.onSaved?.call(id);
      } else {
        Navigator.of(context).pop(id);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the program.')),
      );
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
      SnackBar(content: Text('Duplicated as "${copy.title}".')),
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
    await _repos.programs.softDelete(source.id, at: DateTime.now().toUtc());
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('"$title" deleted.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () =>
              _repos.programs.restore(source.id, at: DateTime.now().toUtc()),
        ),
      ),
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
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes to this program.'),
        actions: [
          TextButton(
            key: const ValueKey('discard-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            key: const ValueKey('discard-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
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
          title: Text(widget.isNew ? 'New program' : 'Build program'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(
                key: ValueKey('program-build-tab'),
                icon: Icon(Icons.list_alt_outlined),
                text: 'Build',
              ),
              Tab(
                key: ValueKey('program-matrix-tab'),
                icon: Icon(Icons.grid_on_outlined),
                text: 'Matrix',
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
                tooltip: 'Perform this program',
                icon: const Icon(Icons.slideshow),
                onPressed: _performProgram,
              ),
            if (_loaded && _loadError == null && _draftProgram != null)
              ProgramExportMenu(
                program: _draftProgram!,
                titleFor: _titleForDance,
              ),
            if (!widget.isNew && _existing != null) ...[
              if (_slots.any((s) => s.danceId != null))
                IconButton(
                  key: const ValueKey('mark-all-performed'),
                  tooltip: 'Mark all performed',
                  icon: const Icon(Icons.done_all),
                  onPressed: _markAllPerformed,
                ),
              IconButton(
                key: const ValueKey('duplicate-program'),
                tooltip: 'Duplicate',
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: _duplicate,
              ),
              IconButton(
                key: const ValueKey('delete-program'),
                tooltip: 'Delete',
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
                label: Text(_dirty ? 'Save *' : 'Save'),
              )
            : null,
      ),
    );
  }

  Widget _buildBody() {
    if (!_loaded) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Loading program'),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _loadError is String
                ? _loadError! as String
                : 'Could not load the program.',
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
                  onAddDance: _addDanceSlot,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMatrixTab() {
    if (!_loaded) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Loading program'),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _loadError is String
                ? _loadError! as String
                : 'Could not load the program.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final data = _data;
    if (data == null) return const SizedBox.shrink();

    // Rows = dance slots in program order (flat). Free-text-only slots are
    // omitted; a slot referencing a soft-deleted dance renders a tombstone
    // row so the gap is still visible in the matrix.
    final now = DateTime.now();
    final rows = <Dance>[];
    final altDanceIds = <String>{};
    var omittedFreeText = 0;
    for (final slot in _slots) {
      final danceId = slot.danceId;
      if (danceId == null) {
        omittedFreeText++;
        continue;
      }
      final dance =
          data.dancesById[danceId] ??
          Dance(
            id: danceId,
            title: '(deleted dance)',
            createdAt: now,
            updatedAt: now,
          );
      rows.add(dance);
      if (slot.isAlt) altDanceIds.add(danceId);
    }

    final matrix = buildProgramMatrix(rows, taxonomy: data.taxonomy);

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
                tooltip: 'Export or print matrix as PDF',
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
    final title = _titleController.text.trim();
    final venue = _venueController.text.trim();
    await Printing.layoutPdf(
      name: title.isEmpty ? 'Programming matrix' : title,
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
    final draft = _draftProgram;
    final warnings = draft?.validate() ?? const <ValidationIssue>[];

    return Form(
      key: _formKey,
      child: ListView(
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
              Text('Slots', style: Theme.of(context).textTheme.titleMedium),
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
                  label: const Text('Add dance'),
                ),
              OutlinedButton.icon(
                key: const ValueKey('add-free-text-slot'),
                onPressed: _addFreeTextSlot,
                icon: const Icon(Icons.notes_outlined),
                label: const Text('Add note / break'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ProgramSlotListEditor(
            slots: _slots,
            danceTitles: _titleForDance,
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
                      'Add a dance',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      key: const ValueKey('picker-sheet-close'),
                      tooltip: 'Close',
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
    final dateLabel = _eventDate == null
        ? 'No date set'
        : MaterialLocalizations.of(context).formatMediumDate(_eventDate!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey('program-title'),
          controller: _titleController,
          autofocus: widget.isNew,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _markDirty(),
          decoration: const InputDecoration(
            labelText: 'Title',
            hintText: 'e.g. Friday Night Contra',
            border: OutlineInputBorder(),
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? 'A title is required.'
              : null,
        ),
        const SizedBox(height: 16),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Event date',
            border: OutlineInputBorder(),
          ),
          child: Row(
            children: [
              Expanded(child: Text(dateLabel)),
              TextButton.icon(
                key: const ValueKey('pick-event-date'),
                onPressed: _pickEventDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(_eventDate == null ? 'Set date' : 'Change'),
              ),
              if (_eventDate != null)
                IconButton(
                  key: const ValueKey('clear-event-date'),
                  tooltip: 'Clear event date',
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
          decoration: const InputDecoration(
            labelText: 'Venue',
            hintText: 'e.g. Grange Hall',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('program-band'),
          controller: _bandController,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _markDirty(),
          decoration: const InputDecoration(
            labelText: 'Band',
            hintText: 'e.g. The Fiddleheads',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('program-caller'),
          controller: _callerController,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _markDirty(),
          decoration: const InputDecoration(
            labelText: 'Caller',
            hintText: 'Host caller for the event',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('program-dancer-level'),
          controller: _levelController,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _markDirty(),
          decoration: const InputDecoration(
            labelText: 'Dancer level',
            hintText: 'e.g. All welcome, Experienced',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('program-notes'),
          controller: _notesController,
          minLines: 3,
          maxLines: 6,
          onChanged: (_) => _markDirty(),
          decoration: const InputDecoration(
            labelText: 'Notes',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<ProgramStatus>(
          key: const ValueKey('program-status'),
          initialValue: _status,
          decoration: const InputDecoration(
            labelText: 'Status',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final status in ProgramStatus.values)
              DropdownMenuItem(
                value: status,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(programStatusPresentation(status).icon, size: 18),
                    const SizedBox(width: 8),
                    Text(programStatusPresentation(status).label),
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
      ],
    );
  }

  Future<void> _pickEventDate() async {
    final now = DateTime.now();
    final stored = _eventDate;
    final initial = stored == null
        ? now
        : DateTime(stored.year, stored.month, stored.day);
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
                  warnings.length == 1
                      ? '1 warning'
                      : '${warnings.length} warnings',
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
    return AlertDialog(
      title: const Text('Add note or break'),
      content: TextField(
        key: const ValueKey('free-text-slot-input'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Text',
          hintText: 'e.g. Break, waltz, announcement',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('free-text-slot-add'),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
