import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../data/reduce_motion_scope.dart';
import '../data/decimal_turns_scope.dart';
import '../editor/figure_draft.dart';
import '../search/facet_labels.dart';
import 'figure_param_editors.dart';
import 'import_gap_badge.dart';
import 'lingo_text_editing_controller.dart';
import 'move_autocomplete.dart';

/// Move id of the placeholder "stand still" figure that seeds new dances (see
/// `defaultNewDanceFigureTemplate`). Activating such a figure opens its editor
/// with the Move field cleared so the caller can type over the placeholder
/// immediately, without first deleting the "stand still" text. Only the
/// editing field is blanked — the stored draft keeps its move/params until a
/// real move is chosen, so nothing is lost if the editor is collapsed as-is.
const String _standStillMove = 'stand_still';

/// Editable, keyboard-first figure list for the dance editor (`docs/design/
/// ux.md` §3, roadmap 3.3b + 3.3c). Adopts a collapse-to-sentence accordion:
/// each figure rests as a single glanceable summary row (rendered sentence +
/// beats + section label + progression marker); tapping (or Enter/Space on a
/// focused row) reveals the heavy editor inline beneath it — a type-ahead move
/// picker plus per-parameter editors, a compact progression toggle, and an
/// on-demand note with live lingo-line styling. At most one figure is expanded
/// at a time (opening another commits + collapses the previous one).
///
/// Reordering is supported via four affordances (WCAG 2.5.7):
///  - drag handle (pointer/touch),
///  - move-up / move-down in the per-row overflow (`⋮`) menu (keyboard/AT),
///  - Alt+ArrowUp / Alt+ArrowDown on a focused collapsed row (keyboard/AT),
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
    this.onDuplicate,
    this.dialect,
    this.moveParamDefaults,
    this.freeTextEntry = false,
    this.onAddFreeText,
  });

  final List<FigureDraft> drafts;
  final Taxonomy taxonomy;
  final PhraseStructure phraseStructure;

  /// Dialect used for lingo-line styling (discouraged + role terms).
  /// Defaults to [Dialect.larksRobins] when `null` (has the standard
  /// discouraged-term list).
  final Dialect? dialect;

  /// Per-move parameter overrides applied when INSERTING a move (ROADMAP DD.3),
  /// keyed by move id then param key. When a move is selected (or a custom
  /// figure created), any override values for params present in that move's
  /// schema are overlaid on top of the taxonomy's `MoveDef` defaults — the user
  /// can still edit the row afterward. `null` (the default) or an absent
  /// move/param falls through to the pure taxonomy defaults (today's behavior).
  final Map<String, Map<String, Object?>>? moveParamDefaults;

  /// Called after any in-place edit to a draft (parent re-renders + revalidates).
  final VoidCallback onChanged;
  final VoidCallback onAdd;
  final ValueChanged<FigureDraft> onDelete;

  /// Optional: duplicate [draft], inserting a clone (fresh id, copied
  /// move/params/note/progression) right after it. When `null` the Duplicate
  /// overflow-menu item is hidden, so existing callers stay source-compatible.
  final ValueChanged<FigureDraft>? onDuplicate;

  /// Called when the user reorders figures. Uses pre-adjusted indices matching
  /// Flutter's [ReorderableListView.onReorderItem] semantics:
  /// ```dart
  /// final item = list.removeAt(oldIndex);
  /// list.insert(newIndex, item); // newIndex already adjusted
  /// ```
  final void Function(int oldIndex, int newIndex) onReorder;

  /// When true (issue #419, opt-in "Free-text entry"), the Add flow opens a
  /// single free-text field instead of appending a blank structured draft: the
  /// typed line is routed through the shared core parser
  /// ([parseFreeTextFigureEntry]) and its result is inserted as editable row(s)
  /// via [onAddFreeText]. Editing an EXISTING figure always uses the structured
  /// editor regardless of this flag. Takes effect only when [onAddFreeText] is
  /// also provided; otherwise the Add flow falls back to the structured [onAdd].
  final bool freeTextEntry;

  /// Inserts the figure(s) parsed from one free-text line at the end of the
  /// list. Only used when [freeTextEntry] is true. A single typed line may yield
  /// more than one figure when it is a `;`-compound.
  final void Function(List<Figure> figures)? onAddFreeText;

  @override
  State<FigureListEditor> createState() => _FigureListEditorState();
}

class _FigureListEditorState extends State<FigureListEditor> {
  /// The id of the draft currently "cut" (awaiting a paste destination), or
  /// `null` when no cut is in progress.
  String? _cutDraftId;

  /// Id of the currently expanded (editing) draft, or `null` when every figure
  /// is collapsed. Tracked by id — never index — so reorders and deletions
  /// can't misroute the open editor to the wrong figure.
  String? _openDraftId;

  /// Set when the Add flow needs the freshly-appended figure to auto-expand +
  /// focus its Move field after the parent rebuilds with the new draft.
  bool _openLastAfterAdd = false;

  /// Per-row focus nodes (keyed by draft id) so the collapsed summary is
  /// keyboard-focusable, can receive Enter/Space/Alt+Arrow, and can be
  /// re-focused after collapse/delete/reorder.
  final Map<String, FocusNode> _rowFocusNodes = {};

  /// Focus target of last resort after deleting the final figure.
  final FocusNode _addButtonFocusNode = FocusNode(debugLabel: 'figure-add');

  /// Whether the opt-in free-text entry composer is currently open (issue
  /// #419). Only ever set when [_freeTextEnabled]; the Add flow opens it and a
  /// blank submit / Escape / Done closes it.
  bool _freeTextComposing = false;
  final TextEditingController _freeTextController = TextEditingController();
  final FocusNode _freeTextFocusNode = FocusNode(
    debugLabel: 'figure-free-text',
  );

  /// Free-text entry is active only when the caller opted in AND wired an
  /// insertion callback; otherwise the Add flow keeps its structured behaviour.
  bool get _freeTextEnabled =>
      widget.freeTextEntry && widget.onAddFreeText != null;

  Dialect get _dialect => widget.dialect ?? Dialect.larksRobins;

  FocusNode _rowFocusNode(String id) => _rowFocusNodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: 'figure-row-$id'),
  );

  @override
  void didUpdateWidget(FigureListEditor old) {
    super.didUpdateWidget(old);
    final ids = widget.drafts.map((d) => d.id).toSet();

    // Auto-open + focus the figure the Add flow just appended.
    if (_openLastAfterAdd) {
      _openLastAfterAdd = false;
      if (widget.drafts.isNotEmpty) {
        final newId = widget.drafts.last.id;
        _openDraftId = newId;
        _ensureVisibleSoon(newId);
        _announce('Added figure ${widget.drafts.length}. Choose a move.');
      }
    }

    // Collapse the editor if its draft was removed externally.
    if (_openDraftId != null && !ids.contains(_openDraftId)) {
      _openDraftId = null;
    }

    // Drop focus nodes for drafts that no longer exist.
    final stale = _rowFocusNodes.keys.where((k) => !ids.contains(k)).toList();
    for (final k in stale) {
      _rowFocusNodes.remove(k)?.dispose();
    }

    // Close the free-text composer if free-text entry was turned off (or its
    // insertion callback removed) while it was open. Route through
    // [_dismissFreeText] so focus is restored to the Add button rather than
    // stranded on the TextField that is about to be removed from the tree.
    if (_freeTextComposing && !_freeTextEnabled) {
      _dismissFreeText();
    }
  }

  @override
  void dispose() {
    for (final node in _rowFocusNodes.values) {
      node.dispose();
    }
    _addButtonFocusNode.dispose();
    _freeTextController.dispose();
    _freeTextFocusNode.dispose();
    super.dispose();
  }

  void _announce(String message) {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.maybeOf(context) ?? TextDirection.ltr,
    );
  }

  void _ensureVisibleSoon(String id) {
    // Respect "Reduce motion" (ROADMAP G.7): jump instantly when it's on.
    final reduceMotion = ReduceMotionScope.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _rowFocusNodes[id]?.context;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 200),
          alignment: 0.1,
        );
      }
    });
  }

  // --- Cut / paste ----------------------------------------------------------
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
    _announce('Figure pasted at position ${finalPos + 1}.');
  }

  // --- Reorder --------------------------------------------------------------
  /// Reorders using pre-adjusted (`onReorderItem`) semantics and announces the
  /// new position. When [refocus] is set the moved row regains focus so
  /// keyboard users can chain Alt+Arrow / menu moves.
  void _reorder(int oldIndex, int newIndex, {bool refocus = false}) {
    if (oldIndex < 0 || oldIndex >= widget.drafts.length) return;
    final movedId = widget.drafts[oldIndex].id;
    widget.onReorder(oldIndex, newIndex);
    _announce('Moved to position ${newIndex + 1} of ${widget.drafts.length}.');
    if (refocus) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _rowFocusNode(movedId).requestFocus(),
      );
    }
  }

  // --- Accordion ------------------------------------------------------------
  void _openDraft(String id) {
    setState(() => _openDraftId = id);
    // Focus lands on the Move field via MoveAutocomplete.autofocus when the
    // editor mounts, but only for a blank or `stand_still` draft (genuine new
    // entry); opening an already-set figure leaves focus alone so the caller can
    // adjust its params. We intentionally do NOT scroll the list into view on
    // expand: the tapped/activated row is already visible, and an animated
    // viewport jump on every open is disorienting. (The Add flow still scrolls
    // its freshly-appended figure into view via _ensureVisibleSoon.)
    final i = widget.drafts.indexWhere((d) => d.id == id);
    if (i != -1) {
      final name = _figureDisplayName(widget.drafts[i], widget.taxonomy);
      _announce('Editing figure ${i + 1}, $name.');
    }
  }

  void _closeDraft(String id) {
    final i = widget.drafts.indexWhere((d) => d.id == id);
    if (_openDraftId == id) setState(() => _openDraftId = null);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _rowFocusNode(id).requestFocus(),
    );
    if (i != -1) _announce('Collapsed figure ${i + 1}.');
  }

  void _toggleDraft(String id) =>
      _openDraftId == id ? _closeDraft(id) : _openDraft(id);

  /// Ctrl/Cmd+Enter: commit the current editor (edits are already live) and
  /// open the next figure's editor — or add a new figure when at the end.
  void _commitAndOpenNext(String id) {
    final i = widget.drafts.indexWhere((d) => d.id == id);
    if (i == -1) return;
    if (i < widget.drafts.length - 1) {
      _openDraft(widget.drafts[i + 1].id);
    } else {
      _addFigure();
    }
  }

  void _addFigure() {
    if (_freeTextEnabled) {
      // Free-text entry (opt-in): open a single free-text field instead of
      // appending a blank structured draft. The typed line is parsed and
      // inserted on submit (see [_submitFreeText]).
      setState(() => _freeTextComposing = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _freeTextFocusNode.requestFocus();
      });
      _announce('Type a figure and press Enter to add it.');
      return;
    }
    _openLastAfterAdd = true;
    widget.onAdd();
  }

  /// Parses the free-text field's current line through the shared core parser
  /// and inserts the resulting row(s). Keeps the composer open (cleared and
  /// refocused) for rapid entry of the next figure; a blank submit closes it.
  void _submitFreeText() {
    final onAddFreeText = widget.onAddFreeText;
    if (onAddFreeText == null) return;
    final figures = parseFreeTextFigureEntry(
      _freeTextController.text,
      taxonomy: widget.taxonomy,
    );
    if (figures.isEmpty) {
      // Nothing to insert (blank, or scrubbed to empty) — close the composer.
      _dismissFreeText();
      return;
    }
    onAddFreeText(figures);
    _freeTextController.clear();
    final n = figures.length;
    _announce(
      n == 1
          ? 'Added 1 figure. Type another, or press Escape to finish.'
          : 'Added $n figures. Type another, or press Escape to finish.',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _freeTextFocusNode.requestFocus();
    });
  }

  /// Closes the free-text composer and returns focus to the Add button.
  void _dismissFreeText() {
    _freeTextController.clear();
    setState(() => _freeTextComposing = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _addButtonFocusNode.requestFocus();
    });
  }

  void _deleteDraft(int index) {
    final drafts = widget.drafts;
    if (index < 0 || index >= drafts.length) return;
    final deleted = drafts[index];
    // Resolve the post-delete focus target BEFORE the list mutates: the next
    // row, else the previous, else the Add button when the list empties.
    String? focusTargetId;
    if (drafts.length > 1) {
      focusTargetId = index < drafts.length - 1
          ? drafts[index + 1].id
          : drafts[index - 1].id;
    }
    if (_openDraftId == deleted.id) _openDraftId = null;
    widget.onDelete(deleted);
    _announce('Deleted figure ${index + 1}. Undo available.');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (focusTargetId != null) {
        _rowFocusNode(focusTargetId).requestFocus();
      } else {
        _addButtonFocusNode.requestFocus();
      }
    });
  }

  void _duplicate(int index) {
    final onDuplicate = widget.onDuplicate;
    if (onDuplicate == null) return;
    if (index < 0 || index >= widget.drafts.length) return;
    onDuplicate(widget.drafts[index]);
    _announce('Duplicated figure ${index + 1}.');
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

    if (drafts.isEmpty) {
      // Teaching empty state: placeholder text paired with a primary action
      // that behaves exactly like Add (and keeps the `figure-add` key). In
      // free-text mode the composer replaces the button once it is open.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No figures yet.', style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(height: 4),
          if (_freeTextComposing)
            _buildFreeTextComposer(context)
          else
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const ValueKey('figure-add'),
                focusNode: _addButtonFocusNode,
                onPressed: _addFigure,
                icon: const Icon(Icons.add),
                label: const Text('Add first figure'),
              ),
            ),
        ],
      );
    }

    // Derive a phrase label per drafted (move-bearing) figure by walking the
    // cumulative beats, mirroring deriveSections but keeping the draft↔row map.
    // `sectionStart` marks the first figure of each section so the label gutter
    // only prints at section boundaries (like figure_table.dart's headers),
    // while the keyed label widget stays present on every row.
    final labels = <String, String?>{};
    final sectionStart = <String, bool>{};
    var beat = 0;
    var totalBeats = 0;
    var placedCount = 0;
    String? lastLabel;
    for (final draft in drafts) {
      if (draft.move == null) {
        labels[draft.id] = null;
        sectionStart[draft.id] = false;
        continue;
      }
      final label = widget.phraseStructure.labelAtBeat(beat);
      labels[draft.id] = label;
      sectionStart[draft.id] = label != lastLabel;
      lastLabel = label;
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

    _FigureDraftCard buildCard(int i, {required bool draggable}) {
      final draft = drafts[i];
      final isCutCard = draft.id == _cutDraftId;
      return _FigureDraftCard(
        key: ValueKey('figure-card-${draft.id}'),
        index: i,
        totalCount: drafts.length,
        draft: draft,
        label: labels[draft.id],
        showLabel: sectionStart[draft.id] ?? false,
        taxonomy: widget.taxonomy,
        dialect: dialect,
        moveParamDefaults: widget.moveParamDefaults,
        isCut: isCutCard,
        draggable: draggable,
        isOpen: _openDraftId == draft.id,
        rowFocusNode: _rowFocusNode(draft.id),
        onChanged: widget.onChanged,
        onActivate: () => _toggleDraft(draft.id),
        onClose: () => _closeDraft(draft.id),
        onCommitNext: () => _commitAndOpenNext(draft.id),
        onDelete: () => _deleteDraft(i),
        onDuplicate: widget.onDuplicate == null ? null : () => _duplicate(i),
        onMoveUp: i == 0 ? null : () => _reorder(i, i - 1, refocus: true),
        onMoveDown: i == drafts.length - 1
            ? null
            : () => _reorder(i, i + 1, refocus: true),
        onCut: isCutCard ? null : () => _startCut(draft.id),
      );
    }

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
        // -------------------------------------------------------------------
        // Figure list.  Two modes:
        //
        //  • Normal (no cut active): ReorderableListView so drag-to-reorder
        //    works.  Exactly one child per draft, so ReorderableDragStartListener
        //    indices stay 1:1 with drafts[].
        //
        //  • Cut active: plain Column with paste buttons interleaved between
        //    cards.  Drag is disabled during cut/paste to avoid index skew
        //    (a paste button inserted into a ReorderableListView would shift
        //    every drag-handle index beyond it — reviewer comment #4).
        // -------------------------------------------------------------------
        if (_cutDraftId == null)
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (oldIndex, newIndex) => _reorder(oldIndex, newIndex),
            children: [
              for (var i = 0; i < drafts.length; i++)
                buildCard(i, draggable: true),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Paste-at-top affordance.
              if (drafts.isNotEmpty)
                _PasteButton(
                  key: const ValueKey('paste-top'),
                  semanticsLabel: 'Paste before first figure',
                  onPaste: () => _paste(0),
                ),
              for (var i = 0; i < drafts.length; i++) ...[
                buildCard(i, draggable: false),
                // Paste-after-this-card affordance (skip for the cut figure
                // itself — pasting adjacent to the source is a no-op).
                if (drafts[i].id != _cutDraftId)
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
        if (_freeTextComposing)
          _buildFreeTextComposer(context)
        else
          Row(
            children: [
              TextButton.icon(
                key: const ValueKey('figure-add'),
                focusNode: _addButtonFocusNode,
                onPressed: _addFigure,
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

  // --- Free-text composer (issue #419) --------------------------------------
  /// The single-line free-text entry field shown in place of the Add button
  /// while composing. Enter submits (parse + insert), Escape cancels; a Done
  /// button offers the same dismissal for pointer/AT users. Kept deliberately
  /// simple: one line at a time, matching the ruling (no multi-line paste).
  Widget _buildFreeTextComposer(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _dismissFreeText();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('figure-free-text-field'),
                controller: _freeTextController,
                focusNode: _freeTextFocusNode,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitFreeText(),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  labelText: 'Type a figure',
                  helperText:
                      'e.g. "neighbor balance & swing" or "16 circle left 3/4". '
                      'Enter adds it; unrecognized text is kept as a custom '
                      'figure.',
                  helperMaxLines: 3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: FilledButton(
                key: const ValueKey('figure-free-text-submit'),
                onPressed: _submitFreeText,
                child: const Text('Add'),
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: TextButton(
                key: const ValueKey('figure-free-text-done'),
                onPressed: _dismissFreeText,
                child: Text(
                  'Done',
                  style: TextStyle(color: theme.colorScheme.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Short display name for a draft (for accessibility labels and cut banner).
/// Returns raw text — callers are responsible for any quoting they need.
String _figureDisplayName(FigureDraft draft, Taxonomy taxonomy) {
  final move = draft.move;
  if (move == null) return 'Empty figure';
  if (move == customMove) {
    final text = draft.params['text'] as String?;
    return text != null && text.isNotEmpty ? text : 'Custom figure';
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

/// One figure in the list. At rest it is a single glanceable summary row
/// (rendered sentence + beats + section label + progression marker + a ⋮
/// overflow menu). Tapping/activating the row expands a full inline editor
/// beneath the summary (the accordion is coordinated by the parent so only one
/// card is open at a time). Live edits are applied immediately via [onChanged],
/// so collapsing is a commit — never a discard.
class _FigureDraftCard extends StatefulWidget {
  const _FigureDraftCard({
    super.key,
    required this.index,
    required this.totalCount,
    required this.draft,
    required this.label,
    required this.showLabel,
    required this.taxonomy,
    required this.dialect,
    this.moveParamDefaults,
    required this.isCut,
    required this.draggable,
    required this.isOpen,
    required this.rowFocusNode,
    required this.onChanged,
    required this.onActivate,
    required this.onClose,
    required this.onCommitNext,
    required this.onDelete,
    this.onDuplicate,
    this.onMoveUp,
    this.onMoveDown,
    this.onCut,
  });

  final int index;
  final int totalCount;
  final FigureDraft draft;

  /// Phrase label (A1/A2/…) for this figure, or null for an empty draft.
  final String? label;

  /// Whether this row starts a new section — the label gutter only prints text
  /// on section boundaries, but the keyed `figure-$index-label` widget is
  /// present on every row.
  final bool showLabel;

  final Taxonomy taxonomy;
  final Dialect dialect;

  /// Per-move insert-time param overrides (ROADMAP DD.3); see
  /// [FigureListEditor.moveParamDefaults]. Null = pure taxonomy defaults.
  final Map<String, Map<String, Object?>>? moveParamDefaults;

  final bool isCut;

  /// Whether to show the drag-handle widget. False during cut/paste mode
  /// because drag indices would be misaligned with the plain-Column layout.
  final bool draggable;

  /// Whether the inline editor is expanded for this figure.
  final bool isOpen;

  /// Focus node for the collapsed summary row (keyboard focus + focus ring).
  final FocusNode rowFocusNode;

  final VoidCallback onChanged;

  /// Toggles the accordion open/closed for this figure.
  final VoidCallback onActivate;

  /// Commits + collapses this figure (Escape / Done).
  final VoidCallback onClose;

  /// Ctrl/Cmd+Enter: commit + open the next figure (or add one at the end).
  final VoidCallback onCommitNext;

  final VoidCallback onDelete;

  /// Null hides the Duplicate menu item (parent didn't wire onDuplicate).
  final VoidCallback? onDuplicate;

  /// Null when this figure is already at the top.
  final VoidCallback? onMoveUp;

  /// Null when this figure is already at the bottom.
  final VoidCallback? onMoveDown;

  /// Null when this figure is already the cut figure.
  final VoidCallback? onCut;

  @override
  State<_FigureDraftCard> createState() => _FigureDraftCardState();
}

class _FigureDraftCardState extends State<_FigureDraftCard> {
  /// Whether the on-demand note field is revealed. Existing notes are always
  /// shown (never hide existing content); an empty note starts hidden behind
  /// the "+ Add note" button.
  bool _showNote = false;

  /// Whether the ">3 params" overflow disclosure is expanded.
  bool _showMoreOptions = false;

  /// One-shot flag so the note field autofocuses the first frame after the
  /// user taps "+ Add note".
  bool _justRevealedNote = false;

  @override
  void initState() {
    super.initState();
    _showNote = widget.draft.note.trim().isNotEmpty;
  }

  // --- Move mutations (live) ------------------------------------------------
  void _selectMove(String moveId) {
    if (widget.draft.move == moveId) return;
    widget.draft.move = moveId;
    widget.draft.params
      ..clear()
      ..addAll(widget.taxonomy.effectiveParams(Figure(move: moveId)));
    // Picking a move is an explicit authorship action: any inherited
    // parser-assumed-subject marker (#460) no longer applies.
    widget.draft.assumedSubject = false;
    // …and the figure is now a stated, user-authored choice, so it is no longer
    // a parser-gap custom (#419): drop any inherited importGap origin.
    widget.draft.customOrigin = CustomOrigin.userEntered;
    // A fresh move brings a fresh canonical beat default; that default is
    // authoritative until the user overrides it again. A saved per-move beats
    // default (DD.3) is a user-configured value, so _applyMoveParamDefaults
    // re-marks beats as touched when it applies one.
    widget.draft.beatsTouched = false;
    _applyMoveParamDefaults(moveId);
    _showMoreOptions = false;
    widget.onChanged();
  }

  void _createCustom(String text) {
    final trimmed = text.trim();
    // Ignore an all-whitespace submission rather than creating an empty
    // custom figure.
    if (trimmed.isEmpty) return;
    widget.draft.move = customMove;
    widget.draft.params
      ..clear()
      ..addAll(widget.taxonomy.effectiveParams(Figure(move: customMove)));
    widget.draft.beatsTouched = false;
    // A user-authored custom figure carries no assumed subject (#460).
    widget.draft.assumedSubject = false;
    // Authoring a custom by hand is a stated choice, not a parser gap (#419).
    widget.draft.customOrigin = CustomOrigin.userEntered;
    _applyMoveParamDefaults(customMove);
    widget.draft.params['text'] = trimmed;
    _showMoreOptions = false;
    widget.onChanged();
  }

  /// Overlays the user's saved per-move param defaults (ROADMAP DD.3) on top of
  /// the taxonomy defaults just seeded into [widget.draft.params]. Only keys
  /// present in the move's schema are applied, so stale/unknown override keys
  /// are ignored. A null map or an absent move/param leaves the taxonomy
  /// defaults untouched (today's behavior).
  void _applyMoveParamDefaults(String moveId) {
    final overrides = widget.moveParamDefaults?[moveId];
    if (overrides == null || overrides.isEmpty) return;
    final schema = widget.taxonomy.resolve(moveId)?.params;
    if (schema == null) return;
    for (final entry in overrides.entries) {
      if (schema.containsKey(entry.key)) {
        widget.draft.params[entry.key] = entry.value;
        // A saved per-move beats default is a user-configured value; treat it
        // as owned so a later non-beats edit's resync won't revert it to the
        // taxonomy canonical.
        if (entry.key == 'beats') {
          widget.draft.beatsTouched = true;
        }
      }
    }
  }

  void _clearMove() {
    if (widget.draft.move == null) return;
    widget.draft.move = null;
    widget.draft.params.clear();
    widget.draft.beatsTouched = false;
    _showMoreOptions = false;
    widget.onChanged();
  }

  /// Applies a non-`beats` param change and reconciles `beats` with the move's
  /// canonical default (issue #262). Capturing the default before *and* after
  /// the mutation means:
  ///
  /// - a driver change that shifts the default (e.g. adding a `balance` prefix
  ///   to a swing, 8→16) snaps beats to the new default; but
  /// - a change that leaves the default put (e.g. a circle's `turn`/`places`,
  ///   which carry no `paramBeats`) never disturbs an existing count — so a
  ///   user-entered value isn't snapped back when nothing about the duration
  ///   changed.
  ///
  /// A `beats` that is missing or non-int (older/partial data loaded without an
  /// explicit count) is still seeded to the canonical default, so an unowned
  /// figure never gets stuck at 0. A manual override
  /// ([FigureDraft.beatsTouched]) is never overwritten.
  void _applyNonBeatsParamChange(String key, Object? value) {
    final draft = widget.draft;
    // Explicitly editing the subject makes it a stated choice, so it is no
    // longer a parser-assumed default (#460): drop the non-authoritative marker.
    if (key == 'who') draft.assumedSubject = false;
    final oldDefault = _canonicalBeats(draft.params);
    draft.params[key] = value;
    final newDefault = _canonicalBeats(draft.params);
    if (draft.beatsTouched || newDefault == null) return;
    final currentBeats = draft.params['beats'];
    if (currentBeats is! int || newDefault != oldDefault) {
      draft.params['beats'] = newDefault;
    }
  }

  /// The move's canonical `beats` default for [params], ignoring any explicit
  /// `beats` so the taxonomy re-derives the value from the driver params.
  /// Returns null when there is no move, no beats spec (e.g. a custom figure),
  /// or a non-int result. Delegates to the Flutter-free core resolver.
  int? _canonicalBeats(Map<String, Object?> params) {
    final move = widget.draft.move;
    if (move == null) return null;
    final def = widget.taxonomy.resolve(move);
    if (def == null || !def.params.containsKey('beats')) return null;
    final probeParams = Map<String, Object?>.of(params)..remove('beats');
    final beats = widget.taxonomy.effectiveParams(
      Figure(move: move, params: probeParams),
    )['beats'];
    return beats is int ? beats : null;
  }

  void _toggleProgression() {
    widget.draft.progression = !widget.draft.progression;
    widget.onChanged();
  }

  // --- Keyboard -------------------------------------------------------------
  KeyEventResult _handleRowKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    if (isAlt && key == LogicalKeyboardKey.arrowUp) {
      final cb = widget.onMoveUp;
      if (cb == null) return KeyEventResult.ignored;
      cb();
      return KeyEventResult.handled;
    }
    if (isAlt && key == LogicalKeyboardKey.arrowDown) {
      final cb = widget.onMoveDown;
      if (cb == null) return KeyEventResult.ignored;
      cb();
      return KeyEventResult.handled;
    }
    if (!isAlt &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.space)) {
      widget.onActivate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleEditorKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    final ctrlOrMeta =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (ctrlOrMeta &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      widget.onCommitNext();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      // Dim the card while it is in the "cut" state.
      opacity: widget.isCut ? 0.45 : 1.0,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSummary(context),
              if (widget.isOpen) _buildEditor(context),
            ],
          ),
        ),
      ),
    );
  }

  // --- Collapsed summary row ------------------------------------------------
  Widget _buildSummary(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;
    final figure = draft.toFigure();
    final hasMove = figure != null;
    final renderer = FigureRenderer(widget.taxonomy);
    final sentence = hasMove
        ? renderer.renderSummary(
            figure,
            widget.dialect,
            decimals: DecimalTurnsScope.of(context),
          )
        : '(empty — choose a move)';
    final spoken = hasMove
        ? renderer.renderSummary(figure, widget.dialect, verbose: true)
        : 'empty figure, choose a move';
    final note = draft.note.trim();
    final hasNote = note.isNotEmpty;
    final noteDiscouraged =
        hasNote && canonicalize(note, widget.dialect).discouraged.isNotEmpty;
    final beatsLabel = '${draft.beats} ${draft.beats == 1 ? 'beat' : 'beats'}';
    // Parser-gap custom (#398/#419): a custom figure the parser could not map,
    // whether from import or a locally-typed free-text line. Surfaces the same
    // inline marker as the read-only figure table and stays reparse-eligible.
    final isImportGap = draft.customOrigin == CustomOrigin.importGap;
    final labelText = (widget.showLabel && widget.label != null)
        ? widget.label!
        : '';

    // Screen-reader composite: "A1, neighbors balance and swing, progression,
    // 16 beats, note: smooth swing. Figure 3 of 12."
    final parts = <String>[
      if (labelText.isNotEmpty) labelText,
      spoken,
      if (isImportGap) importGapMessage,
      if (draft.progression) 'progression',
      if (hasMove) beatsLabel,
      if (hasNote) 'note: $note',
    ];
    final composite =
        '${parts.join(', ')}. Figure ${widget.index + 1} of ${widget.totalCount}.';

    final summaryContent = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: composite,
            hint: 'Activate to edit',
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey('figure-${widget.index}-summary'),
              canRequestFocus: false,
              onTap: widget.onActivate,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDragHandle(context),
                    const SizedBox(width: 4),
                    // Section-label gutter — text only on section boundaries,
                    // but keyed on every row so `figure-$index-label` resolves.
                    SizedBox(
                      width: 30,
                      child: Text(
                        labelText,
                        key: ValueKey('figure-${widget.index}-label'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    // Progression marker (glyph + tooltip; never colour alone).
                    SizedBox(
                      width: 16,
                      child: draft.progression
                          ? Tooltip(
                              message: 'Progression',
                              child: Icon(
                                progressionIcon,
                                size: MediaQuery.textScalerOf(context)
                                    .scale(
                                      theme.textTheme.bodyLarge?.fontSize ?? 16,
                                    )
                                    .clamp(14.0, 16.0),
                                color: theme.colorScheme.primary,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sentence,
                            style: hasMove
                                ? theme.textTheme.bodyLarge
                                : theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontStyle: FontStyle.italic,
                                  ),
                          ),
                          if (hasNote)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (noteDiscouraged) ...[
                                    Icon(
                                      Icons.warning_amber,
                                      size: 13,
                                      color: theme.colorScheme.error,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Expanded(
                                    child: Text(
                                      note,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontStyle: FontStyle.italic,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (isImportGap) ...[
                      const SizedBox(width: 8),
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: ImportGapBadge(),
                      ),
                    ],
                    if (hasMove) ...[
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          beatsLabel,
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        // Overflow (⋮) menu — kept OUTSIDE the excludeSemantics summary so it
        // stays independently accessible to screen readers.
        _buildMenu(context),
      ],
    );

    // Focusable wrapper: 2px primary focus ring + Enter/Space/Alt+Arrow keys.
    return Focus(
      focusNode: widget.rowFocusNode,
      onKeyEvent: _handleRowKey,
      child: AnimatedBuilder(
        animation: widget.rowFocusNode,
        child: summaryContent,
        builder: (context, child) {
          final focused = widget.rowFocusNode.hasFocus;
          return DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: focused ? theme.colorScheme.primary : Colors.transparent,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: child,
          );
        },
      ),
    );
  }

  Widget _buildDragHandle(BuildContext context) {
    if (!widget.draggable) {
      // Keep the horizontal footprint stable so rows don't jump between
      // reorderable and cut/paste modes.
      return const Icon(Icons.drag_handle, size: 20, color: Colors.transparent);
    }
    final figureName = _figureDisplayName(widget.draft, widget.taxonomy);
    return ReorderableDragStartListener(
      index: widget.index,
      child: Semantics(
        label: 'Drag to reorder $figureName',
        child: const Icon(Icons.drag_handle, size: 20),
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;
    final figureName = _figureDisplayName(draft, widget.taxonomy);
    return MenuAnchor(
      builder: (context, controller, child) => IconButton(
        key: ValueKey('figure-${widget.index}-menu'),
        icon: const Icon(Icons.more_vert),
        tooltip: 'Actions for $figureName',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        MenuItemButton(
          key: ValueKey('figure-${widget.index}-move-up'),
          onPressed: widget.onMoveUp,
          leadingIcon: const Icon(Icons.arrow_upward, size: 18),
          child: const Text('Move up'),
        ),
        MenuItemButton(
          key: ValueKey('figure-${widget.index}-move-down'),
          onPressed: widget.onMoveDown,
          leadingIcon: const Icon(Icons.arrow_downward, size: 18),
          child: const Text('Move down'),
        ),
        MenuItemButton(
          key: ValueKey('figure-${widget.index}-cut'),
          onPressed: widget.onCut,
          leadingIcon: const Icon(Icons.content_cut, size: 18),
          child: const Text('Cut'),
        ),
        if (widget.onDuplicate != null)
          MenuItemButton(
            key: ValueKey('figure-${widget.index}-duplicate'),
            onPressed: widget.onDuplicate,
            leadingIcon: const Icon(Icons.copy, size: 18),
            child: const Text('Duplicate'),
          ),
        MenuItemButton(
          key: ValueKey('figure-${widget.index}-toggle-progression'),
          onPressed: _toggleProgression,
          leadingIcon: Icon(
            draft.progression ? Icons.flag : Icons.outlined_flag,
            size: 18,
          ),
          child: Text(
            draft.progression ? 'Clear progression' : 'Mark progression',
          ),
        ),
        MenuItemButton(
          key: ValueKey('figure-${widget.index}-delete'),
          onPressed: widget.onDelete,
          leadingIcon: Icon(
            Icons.delete_outline,
            size: 18,
            color: theme.colorScheme.error,
          ),
          style: MenuItemButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
          ),
          child: const Text('Delete'),
        ),
      ],
    );
  }

  // --- Expanded editor ------------------------------------------------------
  Widget _buildEditor(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;
    final move = draft.move;
    final def = move == null ? null : widget.taxonomy.resolve(move);
    // A figure whose move is not in the active taxonomy (authored in a newer
    // app version, or a since-removed move) degrades to a read-only panel: we
    // don't know its param schema, so exposing the editable move field / param
    // editors risks silently coercing or discarding the preserved data. The
    // original move + params stay intact and untouched, so the figure renders
    // and edits normally again once the move is known (issue #358). Reorder,
    // delete, duplicate, progression, and note remain available.
    final isUnknownMove =
        move != null &&
        move != customMove &&
        move != _standStillMove &&
        def == null;
    if (isUnknownMove) {
      return _buildUnknownMoveEditor(context, move);
    }
    // Open the Move field EMPTY for an unset draft or the placeholder
    // `stand_still` figure so the caller can type over it immediately. Because
    // the editor (and its MoveAutocomplete) remounts on every open, this blanks
    // the field on each activation without ever mutating the stored draft — a
    // real move still shows its display text as before.
    final moveText = (move == null || move == _standStillMove)
        ? ''
        : FigureRenderer(
            widget.taxonomy,
          ).displayMoveName(move, widget.dialect, params: draft.params);

    return Focus(
      canRequestFocus: false,
      onKeyEvent: _handleEditorKey,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
            color: theme.colorScheme.surfaceContainerLow,
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Move picker FIRST, full width. Keyed by index only (not move
              // text) so selecting a move doesn't remount the field and re-pop
              // the options overlay over the editor. Autofocus is gated to genuine
              // new entry — a blank draft or the `stand_still` placeholder — so
              // opening an already-set figure to tweak its params doesn't steal
              // focus to the Move text field.
              MoveAutocomplete(
                key: ValueKey('figure-${widget.index}-move'),
                fieldKey: 'figure-${widget.index}-move',
                taxonomy: widget.taxonomy,
                dialect: widget.dialect,
                initialText: moveText,
                autofocus: move == null || move == _standStillMove,
                onSelected: (option) => _selectMove(option.id),
                onCustomSubmitted: _createCustom,
                onCleared: _clearMove,
              ),
              if (def != null) ...[
                const SizedBox(height: 12),
                // Custom figures: lingo text field in place of param editors.
                if (draft.move == customMove)
                  _LingoCustomTextField(
                    key: ValueKey('figure-${widget.index}-text-${draft.id}'),
                    fieldKey: 'figure-${widget.index}-text',
                    dialect: widget.dialect,
                    taxonomy: widget.taxonomy,
                    value: (draft.params['text'] as String?) ?? '',
                    onChanged: (v) {
                      // 'text' only exists on the custom move, which carries a
                      // flat beats default (no paramBeats): editing text never
                      // moves that default, so an existing count is left alone
                      // while a missing one is seeded. A manual override is
                      // still respected.
                      _applyNonBeatsParamChange('text', v);
                      widget.onChanged();
                    },
                  )
                else if (def.params.isNotEmpty)
                  _buildParams(context, def),
                const SizedBox(height: 12),
                _buildProgressionToggle(context, def),
                const SizedBox(height: 8),
                _buildNote(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Read-only editor panel for a figure whose move is unknown to the active
  /// taxonomy (issue #358). Shows best-effort text (the renderer's raw-id
  /// fallback) and a clear "unrecognized move" indicator explaining why it
  /// can't be edited here. The stored move + params are never mutated by this
  /// path; note and progression stay editable (they are not move params, so
  /// editing them can't corrupt the unknown schema).
  Widget _buildUnknownMoveEditor(BuildContext context, String move) {
    final theme = Theme.of(context);
    final figure = widget.draft.toFigure();
    final bestEffortText = figure == null
        ? move
        : FigureRenderer(widget.taxonomy).render(figure, widget.dialect);

    return Focus(
      canRequestFocus: false,
      onKeyEvent: _handleEditorKey,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
            color: theme.colorScheme.surfaceContainerLow,
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                key: ValueKey('figure-${widget.index}-unknown-move'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.help_outline,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(bestEffortText, style: theme.textTheme.bodyLarge),
                        const SizedBox(height: 4),
                        Text(
                          'Unrecognized move "$move" — not in this version\'s '
                          'taxonomy. Shown read-only so its data is preserved; '
                          'it will edit normally again if the move becomes '
                          'known. You can still reorder or delete it.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildProgressionToggle(context, null),
              const SizedBox(height: 8),
              _buildNote(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParams(BuildContext context, MoveDef def) {
    final draft = widget.draft;
    final entries = def.params.entries.toList();
    // Progressive disclosure: >3 params → first 3 inline, rest behind a
    // collapsed "More options" disclosure. ≤3 params → all inline, no toggle.
    final hasMore = entries.length > 3;
    final inline = hasMore ? entries.take(3).toList() : entries;
    final extra = hasMore
        ? entries.sublist(3)
        : const <MapEntry<String, ParamSpec>>[];

    Widget paramWrap(List<MapEntry<String, ParamSpec>> items) => Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final entry in items)
          FigureParamEditor(
            keyPrefix: 'figure-${widget.index}',
            paramKey: entry.key,
            spec: entry.value,
            dialect: widget.dialect,
            value: draft.params[entry.key] ?? entry.value.defaultValue,
            onChanged: (v) {
              if (entry.key == 'beats') {
                draft.params['beats'] = v;
                // The user edited beats directly: lock the value so nothing
                // auto-fills over it.
                draft.beatsTouched = true;
              } else {
                // A non-beats edit may move the canonical duration; snap beats
                // to the new default only if it actually changed and the user
                // doesn't own beats (issue #262).
                _applyNonBeatsParamChange(entry.key, v);
              }
              widget.onChanged();
            },
          ),
      ],
    );

    if (!hasMore) return paramWrap(inline);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        paramWrap(inline),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: ValueKey('figure-${widget.index}-more-options'),
            onPressed: () =>
                setState(() => _showMoreOptions = !_showMoreOptions),
            icon: Icon(
              _showMoreOptions ? Icons.expand_less : Icons.expand_more,
              size: 18,
            ),
            label: Text(
              _showMoreOptions
                  ? 'Fewer options'
                  : 'More options (${extra.length})',
            ),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ),
        if (_showMoreOptions)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: paramWrap(extra),
          ),
      ],
    );
  }

  Widget _buildProgressionToggle(BuildContext context, MoveDef? def) {
    final theme = Theme.of(context);
    final draft = widget.draft;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'Progression',
          child: Switch(
            key: ValueKey('figure-${widget.index}-progression'),
            value: draft.progression,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) {
              draft.progression = v;
              widget.onChanged();
            },
          ),
        ),
        const SizedBox(width: 8),
        Text('Progression', style: theme.textTheme.bodyMedium),
        if (def != null && def.progressionCapable && !draft.progression)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Tooltip(
              message: 'This move can carry the progression.',
              child: Icon(
                Icons.info_outline,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNote(BuildContext context) {
    final draft = widget.draft;
    final showField = _showNote || draft.note.trim().isNotEmpty;
    if (!showField) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: ValueKey('figure-${widget.index}-add-note'),
          onPressed: () => setState(() {
            _showNote = true;
            _justRevealedNote = true;
          }),
          icon: const Icon(Icons.note_add_outlined, size: 18),
          label: const Text('Add note'),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
      );
    }
    final autofocus = _justRevealedNote;
    if (_justRevealedNote) {
      // Reset after this build so re-renders don't keep stealing focus.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _justRevealedNote = false;
      });
    }
    return _NoteField(
      key: ValueKey('figure-${widget.index}-note-${draft.id}'),
      fieldKey: 'figure-${widget.index}-note',
      dialect: widget.dialect,
      taxonomy: widget.taxonomy,
      value: draft.note,
      autofocus: autofocus,
      onChanged: (text) {
        draft.note = text;
        widget.onChanged();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Inline emphasis affordance (issue #369)
// ---------------------------------------------------------------------------

/// Wraps the current selection of [controller] in [delimiter] (e.g. `*` for
/// bold, `_` for underline) so callers can mark up their own note / custom
/// text. With no selection it inserts an empty `delimiter+delimiter` pair and
/// places the caret between them. The markup lives verbatim in the string; the
/// Perform view renders it via `parseInlineEmphasis`.
@visibleForTesting
void wrapSelectionWith(TextEditingController controller, String delimiter) {
  final value = controller.value;
  final text = value.text;
  var selection = value.selection;
  // Normalise an invalid/absent selection to the end of the text.
  if (!selection.isValid) {
    selection = TextSelection.collapsed(offset: text.length);
  }
  // `isValid` only guarantees non-negative offsets; clamp to the current text
  // length (and order them) so a stale/out-of-range selection can never throw a
  // RangeError on substring / replaceRange.
  final a = selection.start.clamp(0, text.length);
  final b = selection.end.clamp(0, text.length);
  final start = a <= b ? a : b;
  final end = a <= b ? b : a;
  final selected = text.substring(start, end);
  final replacement = '$delimiter$selected$delimiter';
  final newText = text.replaceRange(start, end, replacement);
  final caret = selected.isEmpty
      ? start +
            delimiter
                .length // between the empty pair
      : end + delimiter.length * 2; // after the closing delimiter
  controller.value = TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: caret),
  );
}

/// A compact bold/underline button pair for marking up user-authored text.
class _EmphasisToolbar extends StatelessWidget {
  const _EmphasisToolbar({
    required this.fieldKey,
    required this.controller,
    required this.onChanged,
  });

  final String fieldKey;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  void _apply(String delimiter) {
    wrapSelectionWith(controller, delimiter);
    onChanged(controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: ValueKey('$fieldKey-bold'),
          onPressed: () => _apply('*'),
          icon: const Icon(Icons.format_bold, size: 18),
          tooltip: 'Bold (*text*)',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
        ),
        IconButton(
          key: ValueKey('$fieldKey-underline'),
          onPressed: () => _apply('_'),
          icon: const Icon(Icons.format_underlined, size: 18),
          tooltip: 'Underline (_text_)',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
        ),
      ],
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
    required this.taxonomy,
    required this.value,
    required this.onChanged,
  });

  final String fieldKey;
  final Dialect dialect;
  final Taxonomy taxonomy;
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
      taxonomy: widget.taxonomy,
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
    if (widget.taxonomy != old.taxonomy) {
      _controller.updateTaxonomy(widget.taxonomy);
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
        _EmphasisToolbar(
          fieldKey: widget.fieldKey,
          controller: _controller,
          onChanged: widget.onChanged,
        ),
        TextField(
          key: ValueKey(widget.fieldKey),
          controller: _controller,
          decoration: InputDecoration(
            labelText: 'Custom figure text',
            isDense: true,
            border: const OutlineInputBorder(),
            helperText: hint == null
                ? 'Move names dotted·underline, role terms underlined, '
                      'discouraged terms struck through'
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
    required this.taxonomy,
    required this.value,
    required this.onChanged,
    this.autofocus = false,
  });

  final String fieldKey;
  final Dialect dialect;
  final Taxonomy taxonomy;
  final String value;
  final ValueChanged<String> onChanged;
  final bool autofocus;

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
      taxonomy: widget.taxonomy,
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
    if (widget.taxonomy != old.taxonomy) {
      _controller.updateTaxonomy(widget.taxonomy);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _EmphasisToolbar(
          fieldKey: widget.fieldKey,
          controller: _controller,
          onChanged: widget.onChanged,
        ),
        TextField(
          key: ValueKey(widget.fieldKey),
          controller: _controller,
          autofocus: widget.autofocus,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: widget.onChanged,
        ),
      ],
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
