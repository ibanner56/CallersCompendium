import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import 'figure_param_editors.dart';
import 'move_autocomplete.dart';

/// Mutable working state for one figure while it is being transcribed in the
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
/// ux.md` §3, roadmap 3.3b). Each row is a type-ahead move picker plus concrete
/// per-parameter editors, a progression toggle and a note; a running per-section
/// beat count with an overflow/underflow warning tracks the whole list.
///
/// Reordering affordances (drag/up-down/cut-paste) are deliberately deferred to
/// 3.3c; this slice supports add / edit / delete and append.
class FigureListEditor extends StatelessWidget {
  const FigureListEditor({
    super.key,
    required this.drafts,
    required this.taxonomy,
    required this.phraseStructure,
    required this.onChanged,
    required this.onAdd,
    required this.onDelete,
  });

  final List<FigureDraft> drafts;
  final Taxonomy taxonomy;
  final PhraseStructure phraseStructure;

  /// Called after any in-place edit to a draft (parent re-renders + revalidates).
  final VoidCallback onChanged;
  final VoidCallback onAdd;
  final ValueChanged<FigureDraft> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
      labels[draft.id] = phraseStructure.labelAtBeat(beat);
      beat += draft.beats;
      totalBeats += draft.beats;
      placedCount++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (drafts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No figures yet.', style: theme.textTheme.bodyMedium),
          ),
        for (var i = 0; i < drafts.length; i++)
          _FigureDraftCard(
            key: ValueKey('figure-card-${drafts[i].id}'),
            index: i,
            draft: drafts[i],
            label: labels[drafts[i].id],
            taxonomy: taxonomy,
            onChanged: onChanged,
            onDelete: () => onDelete(drafts[i]),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('figure-add'),
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add figure'),
          ),
        ),
        if (placedCount > 0)
          _BeatSummary(
            totalBeats: totalBeats,
            expectedBeats: phraseStructure.totalBeats,
          ),
      ],
    );
  }
}

class _FigureDraftCard extends StatelessWidget {
  const _FigureDraftCard({
    super.key,
    required this.index,
    required this.draft,
    required this.label,
    required this.taxonomy,
    required this.onChanged,
    required this.onDelete,
  });

  final int index;
  final FigureDraft draft;
  final String? label;
  final Taxonomy taxonomy;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  void _selectMove(String moveId) {
    if (draft.move == moveId) return;
    draft.move = moveId;
    draft.params
      ..clear()
      ..addAll(taxonomy.effectiveParams(Figure(move: moveId)));
    onChanged();
  }

  void _createCustom(String text) {
    draft.move = customMove;
    draft.params
      ..clear()
      ..addAll(taxonomy.effectiveParams(Figure(move: customMove)))
      ..['text'] = text;
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

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
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
                IconButton(
                  key: ValueKey('figure-$index-delete'),
                  tooltip: 'Delete figure',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                ),
              ],
            ),
            if (def != null) ...[
              if (def.params.isNotEmpty)
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
    );
  }
}

class _NoteField extends StatefulWidget {
  const _NoteField({
    super.key,
    required this.fieldKey,
    required this.value,
    required this.onChanged,
  });

  final String fieldKey;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
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
