import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Editable, reorderable list of a program's slots for the builder
/// (`docs/design/ux.md` §4).
///
/// Reordering offers a drag handle **plus** a non-drag alternative (move
/// up/down and cut/paste), mirroring `figure_list_editor.dart` for WCAG 2.5.7.
/// `isAlt` slots render **indented** under their primary with an alt icon +
/// "Alt" text (never colour alone), matching [Program.grouped] semantics.
///
/// All mutations flow through callbacks so the parent builder owns the slot
/// list and its dirty/undo state. Positions are the parent's responsibility to
/// renumber contiguously after each [onReorder].
class ProgramSlotListEditor extends StatefulWidget {
  const ProgramSlotListEditor({
    super.key,
    required this.slots,
    required this.danceTitles,
    required this.onReorder,
    required this.onSlotChanged,
    required this.onRemove,
  });

  /// Slots in position order.
  final List<ProgramSlot> slots;

  /// Resolves a slot's `danceId` to a display title. A missing id (soft-deleted
  /// dance) yields null → a tombstone is shown.
  final String? Function(String danceId) danceTitles;

  /// Reorder from [oldIndex] to [newIndex] using [ReorderableListView]'s
  /// `onReorderItem` semantics (newIndex is the post-removal insertion index).
  final void Function(int oldIndex, int newIndex) onReorder;

  /// Replace the slot at [index] with [updated] (same id).
  final void Function(int index, ProgramSlot updated) onSlotChanged;

  /// Remove the slot at [index].
  final void Function(int index) onRemove;

  @override
  State<ProgramSlotListEditor> createState() => _ProgramSlotListEditorState();
}

class _ProgramSlotListEditorState extends State<ProgramSlotListEditor> {
  /// Id of the slot currently "cut" (awaiting a paste destination), or null.
  String? _cutSlotId;

  void _startCut(String id) => setState(() => _cutSlotId = id);
  void _cancelCut() => setState(() => _cutSlotId = null);

  /// Moves the cut slot to just before [beforeIndex] (original-list index).
  void _paste(int beforeIndex) {
    final cutId = _cutSlotId;
    if (cutId == null) return;
    final cutIndex = widget.slots.indexWhere((s) => s.id == cutId);
    if (cutIndex == -1) {
      setState(() => _cutSlotId = null);
      return;
    }
    setState(() => _cutSlotId = null);
    // After removing the cut item, an insertion point after it shifts down one.
    final finalPos = beforeIndex > cutIndex ? beforeIndex - 1 : beforeIndex;
    widget.onReorder(cutIndex, finalPos);
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Slot moved.',
      TextDirection.ltr,
    );
  }

  bool _isAltAtIndex(int index) {
    final slot = widget.slots[index];
    // A leading alt (no preceding primary) is degenerate — treat it as a
    // primary for indentation so it still renders at the base level, matching
    // Program.grouped's total behaviour.
    if (!slot.isAlt) return false;
    for (var i = index - 1; i >= 0; i--) {
      if (!widget.slots[i].isAlt) return true; // has a preceding primary
    }
    return false;
  }

  String _slotTitle(ProgramSlot slot) {
    final danceId = slot.danceId;
    if (danceId != null) {
      final title = widget.danceTitles(danceId);
      return title ?? '(deleted dance)';
    }
    final text = slot.text;
    return (text == null || text.trim().isEmpty) ? 'Note' : text;
  }

  @override
  Widget build(BuildContext context) {
    final slots = widget.slots;
    // Guard: a cut slot removed externally.
    if (_cutSlotId != null && !slots.any((s) => s.id == _cutSlotId)) {
      _cutSlotId = null;
    }

    if (slots.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          key: ValueKey('slots-empty'),
          child: Text('No slots yet. Add a dance or a note to get started.'),
        ),
      );
    }

    final cutName = _cutSlotId == null
        ? null
        : _slotTitle(slots.firstWhere((s) => s.id == _cutSlotId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_cutSlotId != null)
          Card(
            key: const ValueKey('slot-cut-banner'),
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.content_cut, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '"${cutName ?? '—'}" is cut — tap Paste to place it.',
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('slot-cut-cancel'),
                    onPressed: _cancelCut,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        if (_cutSlotId == null)
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: widget.onReorder,
            children: [
              for (var i = 0; i < slots.length; i++)
                _SlotTile(
                  key: ValueKey('slot-${slots[i].id}'),
                  index: i,
                  slot: slots[i],
                  title: _slotTitle(slots[i]),
                  isDanceSlot: slots[i].danceId != null,
                  isTombstone:
                      slots[i].danceId != null &&
                      widget.danceTitles(slots[i].danceId!) == null,
                  indented: _isAltAtIndex(i),
                  draggable: true,
                  isCut: false,
                  onMoveUp: i == 0 ? null : () => _moveUp(i),
                  onMoveDown: i == slots.length - 1 ? null : () => _moveDown(i),
                  onCut: () => _startCut(slots[i].id),
                  onEdit: () => _editSlot(i),
                  onToggleAlt: () => _toggleAlt(i),
                  onTogglePerformed: () => _togglePerformed(i),
                  onRemove: () => _remove(i),
                ),
            ],
          )
        else
          Column(
            children: [
              _PasteButton(
                key: const ValueKey('slot-paste-top'),
                semanticsLabel: 'Paste before first slot',
                onPaste: () => _paste(0),
              ),
              for (var i = 0; i < slots.length; i++) ...[
                _SlotTile(
                  key: ValueKey('slot-${slots[i].id}'),
                  index: i,
                  slot: slots[i],
                  title: _slotTitle(slots[i]),
                  isDanceSlot: slots[i].danceId != null,
                  isTombstone:
                      slots[i].danceId != null &&
                      widget.danceTitles(slots[i].danceId!) == null,
                  indented: _isAltAtIndex(i),
                  draggable: false,
                  isCut: slots[i].id == _cutSlotId,
                  onMoveUp: i == 0 ? null : () => _moveUp(i),
                  onMoveDown: i == slots.length - 1 ? null : () => _moveDown(i),
                  onCut: slots[i].id == _cutSlotId
                      ? null
                      : () => _startCut(slots[i].id),
                  onEdit: () => _editSlot(i),
                  onToggleAlt: () => _toggleAlt(i),
                  onTogglePerformed: () => _togglePerformed(i),
                  onRemove: () => _remove(i),
                ),
                if (slots[i].id != _cutSlotId)
                  _PasteButton(
                    key: ValueKey('slot-paste-after-${slots[i].id}'),
                    semanticsLabel: 'Paste after ${_slotTitle(slots[i])}',
                    onPaste: () => _paste(i + 1),
                  ),
              ],
            ],
          ),
      ],
    );
  }

  void _moveUp(int i) {
    widget.onReorder(i, i - 1);
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Slot moved up.',
      TextDirection.ltr,
    );
  }

  void _moveDown(int i) {
    // onReorderItem semantics: newIndex is the post-removal insertion index,
    // so moving down one slot targets i + 1.
    widget.onReorder(i, i + 1);
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Slot moved down.',
      TextDirection.ltr,
    );
  }

  void _toggleAlt(int i) {
    final slot = widget.slots[i];
    widget.onSlotChanged(i, slot.copyWith(isAlt: !slot.isAlt));
    SemanticsService.sendAnnouncement(
      View.of(context),
      slot.isAlt ? 'Marked as primary.' : 'Marked as alternate.',
      TextDirection.ltr,
    );
  }

  void _togglePerformed(int i) {
    final slot = widget.slots[i];
    if (slot.performedAt == null) {
      widget.onSlotChanged(
        i,
        slot.copyWith(performedAt: DateTime.now().toUtc()),
      );
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Marked performed.',
        TextDirection.ltr,
      );
    } else {
      // Rebuild without performedAt (copyWith can't clear it).
      widget.onSlotChanged(
        i,
        ProgramSlot(
          id: slot.id,
          position: slot.position,
          danceId: slot.danceId,
          text: slot.text,
          isAlt: slot.isAlt,
          guestCaller: slot.guestCaller,
          plannedMinutes: slot.plannedMinutes,
        ),
      );
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Performed mark cleared.',
        TextDirection.ltr,
      );
    }
  }

  void _remove(int i) {
    final name = _slotTitle(widget.slots[i]);
    widget.onRemove(i);
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Removed $name.',
      TextDirection.ltr,
    );
  }

  Future<void> _editSlot(int index) async {
    final slot = widget.slots[index];
    final result = await showDialog<ProgramSlot>(
      context: context,
      builder: (_) => _SlotEditDialog(slot: slot),
    );
    if (result != null && mounted) widget.onSlotChanged(index, result);
  }
}

/// A single slot row: drag handle + alt-indent + summary + inline controls.
class _SlotTile extends StatelessWidget {
  const _SlotTile({
    super.key,
    required this.index,
    required this.slot,
    required this.title,
    required this.isDanceSlot,
    required this.isTombstone,
    required this.indented,
    required this.draggable,
    required this.isCut,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onCut,
    required this.onEdit,
    required this.onToggleAlt,
    required this.onTogglePerformed,
    required this.onRemove,
  });

  final int index;
  final ProgramSlot slot;
  final String title;
  final bool isDanceSlot;
  final bool isTombstone;
  final bool indented;
  final bool draggable;
  final bool isCut;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onCut;
  final VoidCallback onEdit;
  final VoidCallback onToggleAlt;
  final VoidCallback onTogglePerformed;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final performed = slot.performedAt != null;

    final subtitleParts = <String>[
      if (isDanceSlot && (slot.text?.trim().isNotEmpty ?? false))
        'Note: ${slot.text!.trim()}',
      if (!isDanceSlot && (slot.text?.trim().isNotEmpty ?? false)) '',
      if (slot.guestCaller != null) 'Guest: ${slot.guestCaller}',
      if (slot.plannedMinutes != null) '${slot.plannedMinutes} min',
    ]..removeWhere((s) => s.isEmpty);

    return Opacity(
      opacity: isCut ? 0.45 : 1.0,
      child: Padding(
        // Indent alternates under their primary.
        padding: EdgeInsets.only(left: indented ? 32 : 0, top: 4, bottom: 4),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (draggable)
                  ReorderableDragStartListener(
                    index: index,
                    child: Semantics(
                      label: 'Drag to reorder $title',
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.drag_handle, color: Colors.transparent),
                  ),
                // Type icon (icon + text, never colour alone).
                Icon(
                  isDanceSlot
                      ? (isTombstone
                            ? Icons.report_gmailerrorred_outlined
                            : Icons.music_note_outlined)
                      : Icons.notes_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (slot.isAlt) ...[
                            Icon(
                              Icons.subdirectory_arrow_right,
                              size: 16,
                              color: theme.colorScheme.tertiary,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'Alt',
                              key: ValueKey('slot-${slot.id}-alt-badge'),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.tertiary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              title,
                              key: ValueKey('slot-${slot.id}-title'),
                              style: theme.textTheme.titleSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (performed) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.check_circle_outline,
                              size: 16,
                              color: theme.colorScheme.primary,
                              semanticLabel: 'Performed',
                            ),
                          ],
                        ],
                      ),
                      if (subtitleParts.isNotEmpty)
                        Text(
                          subtitleParts.join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('slot-$index-move-up'),
                  tooltip: 'Move $title up',
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: onMoveUp,
                ),
                IconButton(
                  key: ValueKey('slot-$index-move-down'),
                  tooltip: 'Move $title down',
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: onMoveDown,
                ),
                IconButton(
                  key: ValueKey('slot-$index-cut'),
                  tooltip: 'Cut $title',
                  icon: const Icon(Icons.content_cut, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: onCut,
                ),
                PopupMenuButton<String>(
                  key: ValueKey('slot-$index-menu'),
                  tooltip: 'More actions for $title',
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        onEdit();
                      case 'alt':
                        onToggleAlt();
                      case 'performed':
                        onTogglePerformed();
                      case 'remove':
                        onRemove();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit slot'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'alt',
                      child: ListTile(
                        leading: const Icon(Icons.alt_route),
                        title: Text(
                          slot.isAlt ? 'Make primary' : 'Mark as alternate',
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'performed',
                      child: ListTile(
                        leading: const Icon(Icons.check_circle_outline),
                        title: Text(
                          performed ? 'Clear performed' : 'Mark performed',
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'remove',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Remove slot'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact "paste here" affordance shown between cards during a cut.
class _PasteButton extends StatelessWidget {
  const _PasteButton({
    super.key,
    required this.semanticsLabel,
    required this.onPaste,
  });

  final String semanticsLabel;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      button: true,
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onPaste,
          icon: const Icon(Icons.content_paste, size: 16),
          label: const Text('Paste here'),
        ),
      ),
    );
  }
}

/// Dialog to edit a slot's per-slot note, guest caller, planned minutes, and
/// alt flag. Returns the updated [ProgramSlot] (or null if cancelled).
class _SlotEditDialog extends StatefulWidget {
  const _SlotEditDialog({required this.slot});

  final ProgramSlot slot;

  @override
  State<_SlotEditDialog> createState() => _SlotEditDialogState();
}

class _SlotEditDialogState extends State<_SlotEditDialog> {
  late final TextEditingController _note = TextEditingController(
    text: widget.slot.text ?? '',
  );
  late final TextEditingController _guest = TextEditingController(
    text: widget.slot.guestCaller ?? '',
  );
  late final TextEditingController _minutes = TextEditingController(
    text: widget.slot.plannedMinutes?.toString() ?? '',
  );
  late bool _isAlt = widget.slot.isAlt;
  String? _minutesError;
  String? _noteError;

  bool get _isDanceSlot => widget.slot.danceId != null;

  @override
  void dispose() {
    _note.dispose();
    _guest.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _save() {
    final noteText = _note.text.trim();
    final guestText = _guest.text.trim();
    final minutesText = _minutes.text.trim();

    // A free-text slot must keep some text (its danceId is null); a dance slot
    // may clear its optional caller note entirely.
    if (!_isDanceSlot && noteText.isEmpty) {
      setState(() => _noteError = 'Enter some text for this slot.');
      return;
    }

    int? minutes;
    if (minutesText.isNotEmpty) {
      final parsed = int.tryParse(minutesText);
      if (parsed == null || parsed < 0) {
        setState(() => _minutesError = 'Enter a whole number ≥ 0.');
        return;
      }
      minutes = parsed;
    }

    final updated = ProgramSlot(
      id: widget.slot.id,
      position: widget.slot.position,
      danceId: widget.slot.danceId,
      text: noteText.isEmpty ? null : noteText,
      isAlt: _isAlt,
      guestCaller: guestText.isEmpty ? null : guestText,
      plannedMinutes: minutes,
      performedAt: widget.slot.performedAt,
    );
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isDanceSlot ? 'Edit dance slot' : 'Edit note'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('slot-edit-note'),
              controller: _note,
              minLines: 1,
              maxLines: 4,
              onChanged: (_) {
                if (_noteError != null) setState(() => _noteError = null);
              },
              decoration: InputDecoration(
                labelText: _isDanceSlot ? 'Caller note (optional)' : 'Text',
                hintText: _isDanceSlot
                    ? 'e.g. teach the hey first'
                    : 'e.g. Break, waltz, announcement',
                errorText: _noteError,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('slot-edit-guest'),
              controller: _guest,
              decoration: const InputDecoration(
                labelText: 'Guest caller (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('slot-edit-minutes'),
              controller: _minutes,
              keyboardType: TextInputType.number,
              onChanged: (_) {
                if (_minutesError != null) setState(() => _minutesError = null);
              },
              decoration: InputDecoration(
                labelText: 'Planned minutes (optional)',
                errorText: _minutesError,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              key: const ValueKey('slot-edit-alt'),
              contentPadding: EdgeInsets.zero,
              value: _isAlt,
              onChanged: (v) => setState(() => _isAlt = v ?? false),
              title: const Text('Alternate dance'),
              subtitle: const Text('Renders indented under the slot above it.'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('slot-edit-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('slot-edit-save'),
          onPressed: _save,
          child: const Text('Done'),
        ),
      ],
    );
  }
}
