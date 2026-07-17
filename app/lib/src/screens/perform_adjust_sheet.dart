import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../search/collection_data.dart';
import '../widgets/collection_picker.dart';

/// The non-destructive in-event "adjust" sheet for Performance mode
/// (`docs/design/ux.md` §5: "reorder remaining slots, insert from quick-search,
/// add ad-hoc note — all in an 'adjust' sheet, never disturbing the reading
/// view"). Also lets the caller mark the current slot performed
/// (`ProgramSlot.performedAt`).
///
/// Edits a private working copy of the [Program] and returns it via
/// [Navigator.pop] when the caller taps **Done** (or `null` when nothing
/// changed / the sheet is dismissed). [PerformProgramScreen] then applies the
/// result live with a single SnackBar undo and persists it — so the reading
/// view underneath is never disturbed while adjusting.
class PerformAdjustSheet extends StatefulWidget {
  const PerformAdjustSheet({
    super.key,
    required this.program,
    required this.currentGroupIndex,
    required this.currentSlotId,
    required this.data,
    required this.dialect,
    required this.enrichment,
  });

  final Program program;

  /// The group the reading view is on. The current group and everything after
  /// it are reorderable; already-passed groups stay fixed.
  final int currentGroupIndex;

  /// Id of the slot currently on screen — the mark-performed target and the
  /// anchor that new inserts land right after.
  final String currentSlotId;

  final CollectionData data;

  /// Active dialect for the quick-search picker's canonicalization.
  final Dialect dialect;

  /// Always-on search enrichment (union of every saved dialect) for the
  /// quick-search picker, so its search resolves saved-dialect vocabulary
  /// regardless of the active dialect — parity with the main Collection search.
  /// Built by the parent so it crosses the modal bottom sheet's navigator
  /// boundary reliably (mirrors [dialect]).
  final SearchEnrichment enrichment;

  @override
  State<PerformAdjustSheet> createState() => _PerformAdjustSheetState();
}

class _PerformAdjustSheetState extends State<PerformAdjustSheet> {
  late Program _working = widget.program;
  bool _changed = false;

  /// The reorderable region's fixed start: the group the reading view was on
  /// when the sheet opened. The current group and everything after it are
  /// reorderable; earlier (already-passed) groups stay fixed. Captured once so
  /// moving the current slot within the region doesn't shrink the region.
  late final int _movableStart = widget.currentGroupIndex.clamp(
    0,
    widget.program.grouped.isEmpty ? 0 : widget.program.grouped.length - 1,
  );

  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  // --- Model helpers --------------------------------------------------------

  List<ProgramSlot> _flatten(List<ProgramSlotGroup> groups) => [
    // keep alternates trailing their primary so grouping stays consistent.
    for (final group in groups) ...[group.primary, ...group.alternates],
  ];

  /// Rebuilds [_working] from an ordered slot list, renumbering positions and
  /// bumping `updatedAt`.
  Program _withSlots(List<ProgramSlot> ordered) {
    final renumbered = [
      for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(position: i),
    ];
    return _working.copyWith(
      slots: renumbered,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  /// Group index of the slot currently on screen within the *current* working
  /// grouping (it moves as the list is reordered).
  int _currentGroupIndex() {
    final groups = _working.grouped;
    final index = groups.indexWhere(
      (g) =>
          [g.primary, ...g.alternates].any((s) => s.id == widget.currentSlotId),
    );
    return index < 0 ? 0 : index;
  }

  /// Flattened-slot index just past the current group's last member — where a
  /// freshly inserted dance/note lands ("play this next").
  int _afterCurrentFlatIndex() {
    final groups = _working.grouped;
    final currentGroup = _currentGroupIndex();
    var count = 0;
    for (var i = 0; i <= currentGroup && i < groups.length; i++) {
      count += 1 + groups[i].alternates.length;
    }
    return count;
  }

  String _label(ProgramSlot slot) {
    if (slot.danceId != null) {
      final dance = widget.data.dancesById[slot.danceId];
      if (dance != null) return dance.title;
    }
    final text = slot.text?.trim();
    if (text != null && text.isNotEmpty) return text;
    return 'Untitled slot';
  }

  void _announce(String message) {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      TextDirection.ltr,
    );
  }

  // --- Edits ----------------------------------------------------------------

  void _toggleCurrentPerformed() {
    final now = DateTime.now().toUtc();
    ProgramSlot? edited;
    final slots = [
      for (final s in _working.slots)
        if (s.id == widget.currentSlotId)
          edited = s.performedAt == null
              ? s.copyWith(performedAt: now)
              : s.copyWith(clearPerformedAt: true)
        else
          s,
    ];
    setState(() {
      _working = _working.copyWith(slots: slots, updatedAt: now);
      _changed = true;
    });
    final nowPerformed = edited?.performedAt != null;
    _announce(
      nowPerformed
          ? 'Marked ${_label(edited!)} performed'
          : 'Cleared performed mark',
    );
  }

  void _moveGroup(int fromMovableIndex, int toMovableIndex) {
    final groups = [..._working.grouped];
    final start = _movableStart;
    final movable = groups.sublist(start);
    if (toMovableIndex < 0 || toMovableIndex >= movable.length) return;
    final item = movable.removeAt(fromMovableIndex);
    movable.insert(toMovableIndex, item);
    setState(() {
      _working = _withSlots(
        _flatten([...groups.sublist(0, start), ...movable]),
      );
      _changed = true;
    });
    _announce(
      'Moved ${_label(item.primary)} to position ${start + toMovableIndex + 1}',
    );
  }

  void _onReorder(int oldIndex, int newIndex) => _moveGroup(oldIndex, newIndex);

  void _insertDance(String danceId) {
    final flat = [..._flatten(_working.grouped)];
    final at = _afterCurrentFlatIndex();
    flat.insert(at, ProgramSlot(id: uuidV4(), position: at, danceId: danceId));
    setState(() {
      _working = _withSlots(flat);
      _changed = true;
    });
    final title = widget.data.dancesById[danceId]?.title ?? 'dance';
    _announce('Inserted $title');
  }

  void _addNote() {
    final text = _noteController.text.trim();
    if (text.isEmpty) return;
    final flat = [..._flatten(_working.grouped)];
    final at = _afterCurrentFlatIndex();
    flat.insert(at, ProgramSlot(id: uuidV4(), position: at, text: text));
    setState(() {
      _working = _withSlots(flat);
      _changed = true;
      _noteController.clear();
    });
    _announce('Added note');
  }

  Future<void> _openInsertPicker() async {
    // A modal picker: use the standard drag-handle bottom sheet for
    // consistency with the app's other pickers (e.g. Perform's jump-to-slot),
    // rather than a hand-built header with a close button.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.of(sheetContext).size.height * 0.85;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Insert a dance',
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                  ),
                ),
                Expanded(
                  child: CollectionPicker(
                    key: const ValueKey('adjust-picker'),
                    data: widget.data,
                    dialect: widget.dialect,
                    enrichment: widget.enrichment,
                    onAddDance: (id) {
                      _insertDance(id);
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets;
    final maxHeight = MediaQuery.of(context).size.height * 0.9;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(theme),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCurrentSlotSection(theme),
                      const SizedBox(height: 20),
                      _buildReorderSection(theme),
                      const SizedBox(height: 20),
                      _buildInsertSection(theme),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Row(
        children: [
          Semantics(
            header: true,
            child: Text('Adjust program', style: theme.textTheme.titleLarge),
          ),
          const Spacer(),
          FilledButton(
            key: const ValueKey('adjust-done'),
            onPressed: () =>
                Navigator.of(context).pop(_changed ? _working : null),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String text) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    ),
  );

  Widget _buildCurrentSlotSection(ThemeData theme) {
    final current = _working.slots.firstWhere(
      (s) => s.id == widget.currentSlotId,
      orElse: () => _working.slots.first,
    );
    final performed = current.performedAt != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(theme, 'Current slot'),
        Text(_label(current), style: theme.textTheme.bodyLarge),
        const SizedBox(height: 8),
        // A single semantics node carrying button role + name + the current
        // performed STATE, so AT knows whether the slot is already marked
        // (never color/icon-only).
        MergeSemantics(
          child: Semantics(
            toggled: performed,
            child: OutlinedButton.icon(
              key: const ValueKey('adjust-mark-performed'),
              onPressed: _toggleCurrentPerformed,
              icon: Icon(
                performed ? Icons.check_circle : Icons.check_circle_outline,
              ),
              label: Text(
                performed ? 'Performed — tap to clear' : 'Mark performed',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReorderSection(ThemeData theme) {
    final groups = _working.grouped;
    final start = _movableStart;
    final movable = groups.sublist(start);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(theme, 'Reorder remaining slots'),
        if (movable.length < 2)
          Text(
            'No later slots to reorder.',
            key: const ValueKey('adjust-reorder-empty'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (movable.length * 64.0).clamp(64.0, 320.0),
            ),
            child: ReorderableListView.builder(
              key: const ValueKey('adjust-reorder-list'),
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              itemCount: movable.length,
              onReorderItem: _onReorder,
              itemBuilder: (context, index) {
                final group = movable[index];
                final absolute = start + index;
                return _ReorderRow(
                  key: ValueKey('adjust-reorder-${group.primary.id}'),
                  index: index,
                  absolutePosition: absolute,
                  total: movable.length,
                  label: _label(group.primary),
                  alternates: group.alternates.length,
                  onMoveUp: index > 0
                      ? () => _moveGroup(index, index - 1)
                      : null,
                  onMoveDown: index < movable.length - 1
                      ? () => _moveGroup(index, index + 1)
                      : null,
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildInsertSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(theme, 'Add to program'),
        OutlinedButton.icon(
          key: const ValueKey('adjust-insert-dance'),
          onPressed: _openInsertPicker,
          icon: const Icon(Icons.library_music_outlined),
          label: const Text('Insert dance from search'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('adjust-note-field'),
          controller: _noteController,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _addNote(),
          decoration: const InputDecoration(
            labelText: 'Ad-hoc note / break',
            hintText: 'e.g. Waltz, announcements',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('adjust-add-note'),
            onPressed: _addNote,
            icon: const Icon(Icons.notes_outlined),
            label: const Text('Add note'),
          ),
        ),
      ],
    );
  }
}

/// A single reorderable row in the adjust sheet: label + a non-drag move
/// up/down alternative (WCAG 2.5.7, `docs/design/ux.md` §4) plus a drag handle
/// (excluded from semantics so AT uses the buttons).
class _ReorderRow extends StatelessWidget {
  const _ReorderRow({
    super.key,
    required this.index,
    required this.absolutePosition,
    required this.total,
    required this.label,
    required this.alternates,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final int index;
  final int absolutePosition;
  final int total;
  final String label;
  final int alternates;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = alternates > 0
        ? '$alternates alternate${alternates == 1 ? '' : 's'}'
        : null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(child: Text('${absolutePosition + 1}')),
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('adjust-move-up-$index'),
            tooltip: 'Move "$label" up',
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: onMoveUp,
          ),
          IconButton(
            key: ValueKey('adjust-move-down-$index'),
            tooltip: 'Move "$label" down',
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: onMoveDown,
          ),
          ReorderableDragStartListener(
            index: index,
            child: ExcludeSemantics(
              child: Icon(
                Icons.drag_handle,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
