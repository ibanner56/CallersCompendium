import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import 'figure_param_editors.dart';
import 'move_autocomplete.dart';

// ---------------------------------------------------------------------------
// Lingo-line text editing controller
// ---------------------------------------------------------------------------

/// A [TextEditingController] that overlays "lingo line" decorations on typed
/// text: discouraged terms are struck through, role terms are underlined.
/// Styles are recomputed from core APIs on every change, so character offsets
/// stay correct across arbitrary edits.
class LingoTextEditingController extends TextEditingController {
  LingoTextEditingController({super.text, required this.dialect});

  Dialect dialect;

  /// Replaces the active dialect and redraws the styled spans.
  void updateDialect(Dialect newDialect) {
    if (dialect == newDialect) return;
    dialect = newDialect;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final raw = text;
    if (raw.isEmpty) return TextSpan(text: raw, style: style);

    final discSpans = canonicalize(raw, dialect).discouraged;
    final roleSpanList = roleSpans(raw, dialect);

    if (discSpans.isEmpty && roleSpanList.isEmpty) {
      return TextSpan(text: raw, style: style);
    }

    // Build a flat event list: discouraged first (higher priority), then role.
    // Events are sorted by start position; the first event to claim a range wins.
    final events = <({int start, int end, TextDecoration decoration})>[];
    for (final s in discSpans) {
      final end = (s.start + s.text.length).clamp(0, raw.length);
      if (s.start < end) {
        events.add((
          start: s.start,
          end: end,
          decoration: TextDecoration.lineThrough,
        ));
      }
    }
    for (final s in roleSpanList) {
      final end = (s.start + s.text.length).clamp(0, raw.length);
      if (s.start < end) {
        events.add((
          start: s.start,
          end: end,
          decoration: TextDecoration.underline,
        ));
      }
    }
    events.sort((a, b) => a.start.compareTo(b.start));

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final ev in events) {
      // Trim the event's start to wherever we are (overlapping spans are
      // skipped because the first-encountered span already covers that range).
      final start = ev.start < cursor ? cursor : ev.start;
      final end = ev.end > raw.length ? raw.length : ev.end;
      if (start >= end) continue;

      if (start > cursor) {
        spans.add(TextSpan(text: raw.substring(cursor, start), style: style));
      }
      spans.add(
        TextSpan(
          text: raw.substring(start, end),
          style: (style ?? const TextStyle()).copyWith(
            decoration: ev.decoration,
          ),
        ),
      );
      cursor = end;
    }
    if (cursor < raw.length) {
      spans.add(TextSpan(text: raw.substring(cursor), style: style));
    }

    return TextSpan(children: spans, style: style);
  }
}

// ---------------------------------------------------------------------------
// FigureDraft (unchanged public API)
// ---------------------------------------------------------------------------
/// editor. Committed to an immutable [Figure] on save via [toFigure].
class FigureDraft {
  FigureDraft({
    String? id,
    this.move,
    Map<String, Object?>? params,
    this.note = '',
    this.progression = false,
    this.schemaVersion = figureSchemaVersion,
  }) : id = id ?? uuidV4(),
       params = params ?? <String, Object?>{};

  /// Seeds a draft from an existing figure, keeping its params/note/flags.
  factory FigureDraft.fromFigure(Figure figure) => FigureDraft(
    move: figure.move,
    params: Map<String, Object?>.of(figure.params),
    note: figure.note ?? '',
    progression: figure.progression,
    schemaVersion: figure.schemaVersion,
  );

  /// Stable identity for widget keys across reorders/rebuilds.
  final String id;

  /// Canonical move (or alias) id, or `null` until the user picks one.
  String? move;
  final Map<String, Object?> params;
  String note;
  bool progression;
  final int schemaVersion;

  int get beats => (params['beats'] as int?) ?? 0;

  /// Builds the immutable figure, or `null` when no move is chosen yet.
  Figure? toFigure() {
    final id = move;
    if (id == null) return null;
    final trimmedNote = note.trim();
    return Figure(
      schemaVersion: schemaVersion,
      move: id,
      params: Map<String, Object?>.of(params),
      note: trimmedNote.isEmpty ? null : trimmedNote,
      progression: progression,
    );
  }
}

/// Editable, keyboard-first figure list for the dance editor (`docs/design/
/// ux.md` §3, roadmap 3.3b + 3.3c). Each row is a type-ahead move picker plus
/// per-parameter editors, a progression toggle, and a note with live lingo-line
/// styling (discouraged terms struck through, role terms underlined).
///
/// Reordering is supported via three affordances (WCAG 2.5.7):
///  - drag handle (pointer/touch),
///  - move-up / move-down buttons (keyboard/AT),
///  - cut and paste (keyboard/AT, multi-step).
class FigureListEditor extends StatefulWidget {
  const FigureListEditor({
    super.key,
    required this.drafts,
    required this.taxonomy,
    required this.phraseStructure,
    required this.onChanged,
    required this.onAdd,
    required this.onDelete,
    required this.onReorder,
    this.dialect,
  });

  final List<FigureDraft> drafts;
  final Taxonomy taxonomy;
  final PhraseStructure phraseStructure;

  /// Dialect used for lingo-line styling (discouraged + role terms).
  /// Defaults to [Dialect.larksRobins] when `null` (has the standard
  /// discouraged-term list).
  final Dialect? dialect;

  /// Called after any in-place edit to a draft (parent re-renders + revalidates).
  final VoidCallback onChanged;
  final VoidCallback onAdd;
  final ValueChanged<FigureDraft> onDelete;

  /// Called when the user reorders figures. Uses pre-adjusted indices matching
  /// Flutter's [ReorderableListView.onReorderItem] semantics:
  /// ```dart
  /// final item = list.removeAt(oldIndex);
  /// list.insert(newIndex, item); // newIndex already adjusted
  /// ```
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  State<FigureListEditor> createState() => _FigureListEditorState();
}

class _FigureListEditorState extends State<FigureListEditor> {
  /// The id of the draft currently "cut" (awaiting a paste destination), or
  /// `null` when no cut is in progress.
  String? _cutDraftId;

  Dialect get _dialect => widget.dialect ?? Dialect.larksRobins;

  void _startCut(String draftId) => setState(() => _cutDraftId = draftId);
  void _cancelCut() => setState(() => _cutDraftId = null);

  /// Moves the cut draft to just before [beforeIndex] (in the original list).
  /// Uses pre-adjusted semantics for the [widget.onReorder] call.
  void _paste(int beforeIndex) {
    final cutId = _cutDraftId;
    if (cutId == null) return;
    final cutIndex = widget.drafts.indexWhere((d) => d.id == cutId);
    if (cutIndex == -1) {
      setState(() => _cutDraftId = null);
      return;
    }
    setState(() => _cutDraftId = null);
    // After removing the cut item, the insertion point shifts down by one if
    // beforeIndex is after the cut item.
    final finalPos = beforeIndex > cutIndex ? beforeIndex - 1 : beforeIndex;
    widget.onReorder(cutIndex, finalPos);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final drafts = widget.drafts;
    final dialect = _dialect;

    // Validate cut draft still exists (may have been deleted externally).
    if (_cutDraftId != null && !drafts.any((d) => d.id == _cutDraftId)) {
      _cutDraftId = null;
    }

    // Derive a phrase label per drafted (move-bearing) figure by walking the
    // cumulative beats, mirroring deriveSections but keeping the draft↔row map.
    final labels = <String, String?>{};
    var beat = 0;
    var totalBeats = 0;
    var placedCount = 0;
    for (final draft in drafts) {
      if (draft.move == null) {
        labels[draft.id] = null;
        continue;
      }
      labels[draft.id] = widget.phraseStructure.labelAtBeat(beat);
      beat += draft.beats;
      totalBeats += draft.beats;
      placedCount++;
    }

    final cutName = _cutDraftId == null
        ? null
        : _figureDisplayName(
            drafts.firstWhere(
              (d) => d.id == _cutDraftId,
              orElse: () => FigureDraft(),
            ),
            widget.taxonomy,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cut-in-progress banner.
        if (_cutDraftId != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  Icons.content_cut,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '"${cutName ?? '—'}" is cut — tap Paste to place it.',
                    key: const ValueKey('cut-banner'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey('cut-cancel'),
                  onPressed: _cancelCut,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        if (drafts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No figures yet.', style: theme.textTheme.bodyMedium),
          ),
        // Paste-at-top affordance: shown when cut is active and there are figures.
        if (_cutDraftId != null && drafts.isNotEmpty)
          _PasteButton(
            key: const ValueKey('paste-top'),
            semanticsLabel: 'Paste before first figure',
            onPaste: () => _paste(0),
          ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: widget.onReorder,
          children: [
            for (var i = 0; i < drafts.length; i++) ...[
              _FigureDraftCard(
                key: ValueKey('figure-card-${drafts[i].id}'),
                index: i,
                totalCount: drafts.length,
                draft: drafts[i],
                label: labels[drafts[i].id],
                taxonomy: widget.taxonomy,
                dialect: dialect,
                isCut: drafts[i].id == _cutDraftId,
                onChanged: widget.onChanged,
                onDelete: () => widget.onDelete(drafts[i]),
                onMoveUp: i == 0 ? null : () => widget.onReorder(i, i - 1),
                onMoveDown: i == drafts.length - 1
                    ? null
                    : () => widget.onReorder(i, i + 1),
                onCut: drafts[i].id == _cutDraftId
                    ? null
                    : () => _startCut(drafts[i].id),
              ),
              // Paste-before-next-figure affordance (between cards).
              if (_cutDraftId != null && drafts[i].id != _cutDraftId)
                _PasteButton(
                  key: ValueKey('paste-after-${drafts[i].id}'),
                  semanticsLabel:
                      'Paste after '
                      '${_figureDisplayName(drafts[i], widget.taxonomy)}',
                  onPaste: () => _paste(i + 1),
                ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
              key: const ValueKey('figure-add'),
              onPressed: widget.onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add figure'),
            ),
            if (_cutDraftId != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _PasteButton(
                  key: const ValueKey('paste-end'),
                  semanticsLabel: 'Paste at end of figure list',
                  onPaste: () => _paste(drafts.length),
                ),
              ),
          ],
        ),
        if (placedCount > 0)
          _BeatSummary(
            totalBeats: totalBeats,
            expectedBeats: widget.phraseStructure.totalBeats,
          ),
      ],
    );
  }
}

/// Short display name for a draft (for accessibility labels and cut banner).
String _figureDisplayName(FigureDraft draft, Taxonomy taxonomy) {
  final move = draft.move;
  if (move == null) return 'Empty figure';
  if (move == customMove) {
    final text = draft.params['text'] as String?;
    return text != null && text.isNotEmpty ? '"$text"' : 'Custom figure';
  }
  final alias = taxonomy.aliases[move];
  final def = taxonomy.resolve(move);
  return alias?.displayName ?? def?.displayName ?? move;
}
// ---------------------------------------------------------------------------
// Small helper: paste affordance button
// ---------------------------------------------------------------------------

/// A compact button indicating where a cut figure will be inserted.
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
      child: TextButton.icon(
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        onPressed: onPaste,
        icon: const Icon(Icons.content_paste, size: 16),
        label: const Text('Paste here'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _FigureDraftCard
// ---------------------------------------------------------------------------

class _FigureDraftCard extends StatelessWidget {
  const _FigureDraftCard({
    super.key,
    required this.index,
    required this.totalCount,
    required this.draft,
    required this.label,
    required this.taxonomy,
    required this.dialect,
    required this.isCut,
    required this.onChanged,
    required this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
    this.onCut,
  });

  final int index;
  final int totalCount;
  final FigureDraft draft;
  final String? label;
  final Taxonomy taxonomy;
  final Dialect dialect;
  final bool isCut;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  /// Null when this figure is already at the top.
  final VoidCallback? onMoveUp;

  /// Null when this figure is already at the bottom.
  final VoidCallback? onMoveDown;

  /// Null when this figure is already the cut figure.
  final VoidCallback? onCut;

  void _selectMove(String moveId) {
    if (draft.move == moveId) return;
    draft.move = moveId;
    draft.params
      ..clear()
      ..addAll(taxonomy.effectiveParams(Figure(move: moveId)));
    onChanged();
  }

  void _createCustom(String text) {
    final trimmed = text.trim();
    // Ignore an all-whitespace submission rather than creating an empty
    // custom figure.
    if (trimmed.isEmpty) return;
    draft.move = customMove;
    draft.params
      ..clear()
      ..addAll(taxonomy.effectiveParams(Figure(move: customMove)))
      ..['text'] = trimmed;
    onChanged();
  }

  void _clearMove() {
    if (draft.move == null) return;
    draft.move = null;
    draft.params.clear();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final move = draft.move;
    final def = move == null ? null : taxonomy.resolve(move);
    final alias = move == null ? null : taxonomy.aliases[move];
    final moveText = move == null
        ? ''
        : (alias?.displayName ?? def?.displayName ?? move);
    final figureName = _figureDisplayName(draft, taxonomy);

    return Opacity(
      // Dim the card while it is in the "cut" state.
      opacity: isCut ? 0.45 : 1.0,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Drag handle (activates the ReorderableListView drag).
                  ReorderableDragStartListener(
                    index: index,
                    child: Semantics(
                      label: 'Drag to reorder $figureName',
                      child: const Icon(Icons.drag_handle),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 34,
                    child: Text(
                      label ?? '—',
                      key: ValueKey('figure-$index-label'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    // Rebuild the picker when the move changes so it shows the
                    // new display name.
                    child: MoveAutocomplete(
                      key: ValueKey('figure-$index-move-$move'),
                      fieldKey: 'figure-$index-move',
                      taxonomy: taxonomy,
                      initialText: moveText,
                      onSelected: (option) => _selectMove(option.id),
                      onCustomSubmitted: _createCustom,
                      onCleared: _clearMove,
                    ),
                  ),
                  // Move-up button (disabled at the top).
                  IconButton(
                    key: ValueKey('figure-$index-move-up'),
                    tooltip: 'Move $figureName up',
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: onMoveUp,
                  ),
                  // Move-down button (disabled at the bottom).
                  IconButton(
                    key: ValueKey('figure-$index-move-down'),
                    tooltip: 'Move $figureName down',
                    icon: const Icon(Icons.arrow_downward, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: onMoveDown,
                  ),
                  // Cut button (disabled while this figure is already cut).
                  IconButton(
                    key: ValueKey('figure-$index-cut'),
                    tooltip: 'Cut $figureName',
                    icon: const Icon(Icons.content_cut, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: onCut,
                  ),
                  IconButton(
                    key: ValueKey('figure-$index-delete'),
                    tooltip: 'Delete figure',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDelete,
                  ),
                ],
              ),
              if (def != null) ...[
                // Custom figures: lingo-styled text field instead of param editors.
                if (draft.move == customMove)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _LingoCustomTextField(
                      key: ValueKey('figure-$index-text-${draft.id}'),
                      fieldKey: 'figure-$index-text',
                      dialect: dialect,
                      value: (draft.params['text'] as String?) ?? '',
                      onChanged: (v) {
                        draft.params['text'] = v;
                        onChanged();
                      },
                    ),
                  )
                else if (def.params.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final entry in def.params.entries)
                          FigureParamEditor(
                            keyPrefix: 'figure-$index',
                            paramKey: entry.key,
                            spec: entry.value,
                            value:
                                draft.params[entry.key] ??
                                entry.value.defaultValue,
                            onChanged: (v) {
                              draft.params[entry.key] = v;
                              onChanged();
                            },
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Semantics(
                        label: 'Progression',
                        child: Switch(
                          key: ValueKey('figure-$index-progression'),
                          value: draft.progression,
                          onChanged: (v) {
                            draft.progression = v;
                            onChanged();
                          },
                        ),
                      ),
                      Text('Progression', style: theme.textTheme.bodyMedium),
                      if (def.progressionCapable && !draft.progression)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.info_outline,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _NoteField(
                    key: ValueKey('figure-$index-note-${draft.id}'),
                    fieldKey: 'figure-$index-note',
                    dialect: dialect,
                    value: draft.note,
                    onChanged: (text) {
                      draft.note = text;
                      onChanged();
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _LingoCustomTextField
// ---------------------------------------------------------------------------

/// Full-width text field for a custom figure's free-text description.
/// Uses [LingoTextEditingController] to show live lingo-line decoration.
class _LingoCustomTextField extends StatefulWidget {
  const _LingoCustomTextField({
    super.key,
    required this.fieldKey,
    required this.dialect,
    required this.value,
    required this.onChanged,
  });

  final String fieldKey;
  final Dialect dialect;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_LingoCustomTextField> createState() => _LingoCustomTextFieldState();
}

class _LingoCustomTextFieldState extends State<_LingoCustomTextField> {
  late final LingoTextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LingoTextEditingController(
      text: widget.value,
      dialect: widget.dialect,
    );
  }

  @override
  void didUpdateWidget(_LingoCustomTextField old) {
    super.didUpdateWidget(old);
    // Sync when the parent reseeds the value (e.g. a move change) without
    // clobbering in-progress typing.
    if (widget.value != old.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
    if (widget.dialect != old.dialect) {
      _controller.updateDialect(widget.dialect);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final discouraged = canonicalize(
      _controller.text,
      widget.dialect,
    ).discouraged;
    final hint = discouraged.isEmpty
        ? null
        : discouraged.map((s) => s.text).toSet().join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: ValueKey(widget.fieldKey),
          controller: _controller,
          decoration: InputDecoration(
            labelText: 'Custom figure text',
            isDense: true,
            border: const OutlineInputBorder(),
            helperText: hint == null
                ? 'Role terms underlined, discouraged terms struck through'
                : null,
          ),
          onChanged: widget.onChanged,
        ),
        // Accessible text hint when discouraged terms are present — satisfies
        // WCAG requirement not to rely on visual styling alone.
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                Icon(
                  Icons.warning_outlined,
                  size: 13,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Semantics(
                    label: 'Discouraged term: $hint',
                    child: Text(
                      'Discouraged: $hint',
                      key: ValueKey('${widget.fieldKey}-lingo-hint'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _NoteField  (lingo-aware)
// ---------------------------------------------------------------------------

class _NoteField extends StatefulWidget {
  const _NoteField({
    super.key,
    required this.fieldKey,
    required this.dialect,
    required this.value,
    required this.onChanged,
  });

  final String fieldKey;
  final Dialect dialect;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  late final LingoTextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LingoTextEditingController(
      text: widget.value,
      dialect: widget.dialect,
    );
  }

  @override
  void didUpdateWidget(_NoteField old) {
    super.didUpdateWidget(old);
    // Keep the note in sync when the parent supplies a new value (e.g. a
    // different draft loaded into this row) without disrupting live typing.
    if (widget.value != old.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
    if (widget.dialect != old.dialect) {
      _controller.updateDialect(widget.dialect);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: ValueKey(widget.fieldKey),
      controller: _controller,
      decoration: const InputDecoration(
        labelText: 'Note (optional)',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      onChanged: widget.onChanged,
    );
  }
}

class _BeatSummary extends StatelessWidget {
  const _BeatSummary({required this.totalBeats, required this.expectedBeats});

  final int totalBeats;
  final int expectedBeats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mismatch = totalBeats != expectedBeats;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total: $totalBeats / $expectedBeats beats',
            key: const ValueKey('figure-beats-total'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (mismatch)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                key: const ValueKey('figure-beats-warning'),
                children: [
                  Icon(
                    Icons.warning_amber,
                    size: 16,
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    totalBeats > expectedBeats
                        ? 'Over by ${totalBeats - expectedBeats} beats'
                        : 'Under by ${expectedBeats - totalBeats} beats',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
