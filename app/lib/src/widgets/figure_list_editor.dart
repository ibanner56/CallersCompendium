import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../data/user_figures_scope.dart';
import '../data/aggressive_beats_update_scope.dart';
import '../data/reduce_motion_scope.dart';
import '../data/capitalize_figures_scope.dart';
import '../data/decimal_turns_scope.dart';
import '../editor/figure_draft.dart';
import '../editor/free_text_composer_controller.dart';
import '../editor/pending_move_text_controller.dart';
import '../editor/user_figure_draft.dart';
import '../glossary/custom_figures.dart';
import '../search/facet_labels.dart';
import 'compound_argument_editor.dart';
import 'figure_param_editors.dart';
import 'import_gap_badge.dart';
import 'lingo_text_editing_controller.dart';
import 'move_autocomplete.dart';
import 'user_figure_use_editor.dart';

/// Move id of the placeholder "stand still" figure that seeds new dances while
/// Free-text entry is off (see `defaultNewDanceFigureTemplate`). Activating
/// such a figure opens its editor with the Move field cleared so the caller
/// can type over the placeholder immediately, without first deleting the
/// "stand still" text. Only the editing field is blanked — the stored draft
/// keeps its move/params until a real move is chosen, so nothing is lost if
/// the editor is collapsed as-is.
const String _standStillMove = 'stand_still';

/// Replaces each run of line breaks, with the spaces around it, by one space.
final TextInputFormatter _lineBreaksToSpaces = FilteringTextInputFormatter(
  RegExp(r'[ \t]*[\r\n]+[ \t]*'),
  allow: false,
  replacementString: ' ',
);

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
    this.onReorder,
    this.onDuplicate,
    this.dialect,
    this.mixer = false,
    this.moveParamDefaults,
    this.freeTextEntry = false,
    this.onAddFreeText,
    this.freeTextComposerController,
    this.pendingMoveTextController,
    this.onReplaceWithFreeText,
    this.onSubmitCompoundShorthand,
    this.onReplaceWithShorthand,
    this.isOwnShorthandToken,
    this.shorthandMappings,
    this.snippetLibraryDefaultFor,
    this.onSnippetCommitted,
    this.showWordingOverride = false,
    this.canonicalizeDiscouragedTerms = false,
    this.onGroupWithNext,
    this.onGroupWithNextAsModifier,
    this.onGroupWithNextAsSequence,
    this.onCollapseMeanwhileGroup,
    this.onConvertToMeanwhile,
    this.onConvertToModifier,
    this.onConvertToSequence,
    this.onUngroupContainer,
    this.onAddMeanwhile,
    this.onAddModifier,
    this.onAddSequence,
    this.allowAdding = true,
    this.allowDuplicating = true,
    this.showPhraseStructure = true,
    this.allowModifierSelection = true,
    this.allowNestedContainerSelection = true,
    this.allowCustom = true,
    this.compoundOptions,
    this.resolveCompound,
    this.userFigureOptions,
    this.keyPrefix = 'figure',
  });

  final List<FigureDraft> drafts;
  final Taxonomy taxonomy;
  final PhraseStructure phraseStructure;

  /// Dialect used for lingo-line styling (discouraged + role terms).
  /// Defaults to [Dialect.larksRobins] when `null` (has the standard
  /// discouraged-term list).
  final Dialect? dialect;

  /// Whether the enclosing dance is a mixer (issue #732).
  ///
  /// Forwarded to each [FigureParamEditor] so that dancer-set/pair dropdowns
  /// suppress the partner-series tokens except when the stored value is already
  /// one of them (see [offerableDancerSets]). Defaults to `false`.
  ///
  /// This is a deliberate implementation choice for callers that have no dance
  /// in context (e.g. the collection-wide defaults editor in
  /// `defaults_section.dart`): the default `false` means partner-series tokens
  /// are not offered, which is correct because a collection-wide default is
  /// applied to every new figure regardless of dance type, and seeding it with
  /// a mixer-specific token would be wrong for the large majority of dances.
  final bool mixer;

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
  /// `null` disables the inner reorderable list, which is used for nested
  /// container editors whose parent owns the ordering controls.
  final void Function(int oldIndex, int newIndex)? onReorder;

  /// When true (issue #419, opt-in "Free-text entry"), the Add flow opens a
  /// single free-text field instead of appending a blank structured draft: the
  /// typed line is routed through the shared core parser
  /// ([parseFreeTextFigureEntry]) and its result is inserted as editable row(s)
  /// via [onAddFreeText]. The callback returns the number of figures accepted
  /// so filtered or capped input is not reported as inserted. An EXISTING
  /// figure still opens in the structured editor, but when
  /// [onReplaceWithFreeText] is also provided, Enter on text in its Move box
  /// that matches no move runs the same parser and replaces the row (#1177,
  /// decision D2) instead of making a stated custom figure.
  /// Takes effect only when [onAddFreeText] is also provided; otherwise the Add
  /// flow falls back to the structured [onAdd].
  final bool freeTextEntry;

  /// Inserts the figure(s) parsed from one free-text line at the end of the
  /// list. Only used when [freeTextEntry] is true. A single typed line may yield
  /// more than one figure when it is a `;`-compound.
  final int Function(List<Figure> figures)? onAddFreeText;

  /// Told whether the free-text composer holds a line not yet added, and able
  /// to add it, so the screen can count that line as unsaved and add it on
  /// Save. Null (the default) leaves the composer to itself.
  final FreeTextComposerController? freeTextComposerController;

  /// Told whether a row's Move box holds text that leaving it would apply,
  /// and able to settle it (AUTH-1), so the screen can count that text as
  /// unsaved and apply it on Save. Null (the default) gives the list one of
  /// its own, which still settles the box when another row opens or this one
  /// closes.
  final PendingMoveTextController? pendingMoveTextController;

  /// Replaces the row [draft] with the figure(s) parsed from a line typed into
  /// its Move box (#1177), in its place. Only used when free-text entry is
  /// active (see [freeTextEntry]). Returns the number of figures accepted; 0
  /// leaves the row as it was, and the line becomes a stated custom figure as
  /// it does with free-text entry off. Null keeps that behaviour always.
  final int Function(FigureDraft draft, List<Figure> figures)?
  onReplaceWithFreeText;

  /// Offered each free-text line before it is parsed (#709): inserts a row for
  /// one of the user's own figures, a compound or (#1023) a new figure, when
  /// the line is a shorthand for one that can be used (with or without a
  /// leading or trailing beat count, #1861), or a `;` list with one as a
  /// clause (#1866), and returns how many rows it inserted. A line it declines
  /// (0) is parsed as usual. Null (the default) offers none.
  final int Function(String line)? onSubmitCompoundShorthand;

  /// [onSubmitCompoundShorthand] for a line typed into the Move box of the
  /// existing row [draft] (#1847): on a match it puts that shorthand's row in
  /// the row's place, so the old row is replaced as a parsed line replaces it,
  /// and returns how many rows replaced it. A line it declines (0) is parsed and replaces the
  /// row as before (#1177). Only used when free-text entry is
  /// active; null offers none.
  final int Function(FigureDraft draft, String line)? onReplaceWithShorthand;

  /// Whether [token] is a shorthand for one of the user's own figures, a
  /// compound or a new figure, that the Move box should take as a shorthand
  /// on Enter even though it is part of a move's name (see
  /// [MoveAutocomplete.submitsAsText]); [shorthandMappings] answers for the
  /// plain ones. Null: none.
  final bool Function(String token)? isOwnShorthandToken;

  /// User-defined shorthand → figure(s) mappings (issue #420) consulted
  /// during free-text entry before the parser (after
  /// [onSubmitCompoundShorthand], whose caller lets a figure shorthand with
  /// the same token win): a typed line matching a shorthand token (whole
  /// line, or one `;` clause, case-insensitive, with an optional leading or
  /// trailing beat count split off; see [parseFreeTextFigureEntry]) expands to
  /// the mapped figures instead of being parsed. `null` (the default) disables shorthand expansion, preserving the
  /// pure #419 parse behavior. Only relevant when [freeTextEntry] is enabled.
  final ShorthandMappings? shorthandMappings;

  /// Resolves the GLOBAL walkthrough-snippet library default for a figure draft
  /// (#411) — the text stored for the draft's figure signature, ignoring any
  /// per-dance override. `null` (the default) hides the per-figure walkthrough
  /// snippet affordance entirely (e.g. no snippet-library scope in the tree).
  final String? Function(FigureDraft draft)? snippetLibraryDefaultFor;

  /// Invoked when the user commits a per-figure walkthrough snippet edit (the
  /// field loses focus). The parent runs the learn-on-first-entry /
  /// divergence-prompt flow (#411) and may update [draft.walkthroughOverride]
  /// and/or the global library. Only wired when [snippetLibraryDefaultFor] is.
  final void Function(FigureDraft draft)? onSnippetCommitted;

  /// Whether this dance-scoped editor should expose the per-figure display
  /// wording override. Disabled for reusable defaults and shorthand mappings,
  /// where a per-dance value would be misleading.
  final bool showWordingOverride;

  /// Enables canonical discouraged-term wording only for read-only,
  /// dance-scoped summaries. Settings editors leave this disabled so their
  /// collapsed previews match the literal editable values.
  final bool canonicalizeDiscouragedTerms;

  /// Groups [draft] with the figure immediately after it into a **meanwhile**
  /// group (#590/#593): the caller replaces both top-level entries with one
  /// group draft whose sides are the two originals. `null` (the default)
  /// hides the "Group with next" row-menu affordance entirely, mirroring
  /// [onDuplicate] — existing callers stay source-compatible.
  final ValueChanged<FigureDraft>? onGroupWithNext;

  /// Groups [draft] with the following row as a modifier container.
  final ValueChanged<FigureDraft>? onGroupWithNextAsModifier;

  /// Groups [draft] with the following row as a sequence container. Offered
  /// only while the two rows' counts together fit in one phrase of
  /// [phraseStructure].
  final ValueChanged<FigureDraft>? onGroupWithNextAsSequence;

  /// Collapses a meanwhile group back to a plain figure (#593): called when a
  /// 2-side group has one of its sides removed, leaving [remainingSide]. The
  /// caller replaces [groupDraft]'s top-level list slot with [remainingSide].
  /// `null` hides the remove-side affordance's collapse behavior (only
  /// relevant when [onGroupWithNext] is also wired, since that's the only way
  /// a group is created).
  final void Function(FigureDraft groupDraft, FigureDraft remainingSide)?
  onCollapseMeanwhileGroup;
  final ValueChanged<FigureDraft>? onConvertToMeanwhile;
  final ValueChanged<FigureDraft>? onConvertToModifier;
  final ValueChanged<FigureDraft>? onConvertToSequence;
  final ValueChanged<FigureDraft>? onUngroupContainer;

  /// Adds a new meanwhile container draft through the list-level Add menu and
  /// returns the inserted draft's id. When `null`, the existing single Add
  /// button is retained.
  final Future<String?> Function()? onAddMeanwhile;

  /// Adds a new modifier container through the list-level Add menu.
  final Future<String?> Function()? onAddModifier;

  /// Adds a new sequence container through the list-level Add menu.
  final Future<String?> Function()? onAddSequence;

  /// Whether list-level insertion affordances are available.
  final bool allowAdding;

  /// Whether row-level duplicate affordances are available.
  final bool allowDuplicating;

  /// Whether phrase labels and the beat summary are shown.
  final bool showPhraseStructure;

  /// Whether ordinary figure editors offer the structural `modifier` and
  /// `sequence` options. Settings lists whose persistence accepts ordinary
  /// figures only disable this affordance.
  final bool allowModifierSelection;

  /// Whether text that names no move becomes a custom figure. The compound
  /// editor (#709) turns it off: a compound's parts must be taxonomy figures,
  /// whose slots it can fill.
  final bool allowCustom;

  /// The user's own compound figures a top-level row's move picker offers
  /// (#709); picking one turns the row into a [FigureDraft.compound]
  /// placeholder. Null or empty offers none. Only the dance editor sets it, and
  /// only while Custom Figures is on: the nested container editors never
  /// receive it, so no placeholder can become a meanwhile side or a modifier
  /// child.
  final List<UserGlossaryEntry>? compoundOptions;

  /// Looks a placeholder row's compound up as it is now, to edit its
  /// arguments and show what it expands to. Null in every editor that cannot
  /// hold a placeholder.
  final CompoundResolver? resolveCompound;

  /// The user's own new figures (#1023) a row's move picker offers, in a
  /// meanwhile side or modifier child too (maintainer decision 11): picking
  /// one makes the row a use of it. Null or empty offers none; only the dance
  /// editor sets it, and only while Custom Figures is on.
  final List<UserGlossaryEntry>? userFigureOptions;

  /// Whether ordinary children may be converted into a container of another
  /// kind than their parent. Nested editors at the maximum depth disable this
  /// so the selector cannot create a third structural level.
  final bool allowNestedContainerSelection;

  /// Prefix for widget keys when multiple editors share one screen.
  final String keyPrefix;

  @override
  State<FigureListEditor> createState() => _FigureListEditorState();
}

class _FigureListEditorState extends State<FigureListEditor>
    with AutomaticKeepAliveClientMixin<FigureListEditor> {
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
  final Set<String> _pendingMeanwhileDraftIds = {};

  /// Serves the Move boxes when the screen passes no
  /// [FigureListEditor.pendingMoveTextController].
  PendingMoveTextController? _ownPendingMoveText;

  PendingMoveTextController get _pendingMoveText =>
      widget.pendingMoveTextController ??
      (_ownPendingMoveText ??= PendingMoveTextController());

  /// Per-row focus nodes (keyed by draft id) so the collapsed summary is
  /// keyboard-focusable, can receive Enter/Space/Alt+Arrow, and can be
  /// re-focused after collapse/delete/reorder.
  final Map<String, FocusNode> _rowFocusNodes = {};

  /// Focus target of last resort after deleting the final figure.
  final FocusNode _addButtonFocusNode = FocusNode(debugLabel: 'figure-add');

  /// First item of the Add menu. Opening the menu does not move focus
  /// into the menu, so without this a keyboard user's Down/Tab/Enter land on
  /// the page behind it (#1821).
  final FocusNode _addMenuFirstItemFocusNode = FocusNode(
    debugLabel: 'figure-add-menu-first',
  );

  /// Whether the opt-in free-text entry composer is currently open (issue
  /// #419). Only ever set when [_freeTextEnabled]; the Add flow opens it, and
  /// a blank submit, Escape or Finish adding closes it.
  bool _freeTextComposing = false;
  final TextEditingController _freeTextController = TextEditingController();

  /// The visible "Added N figures" line under the composer (#1825); null until
  /// a line is accepted, and cleared again by the next keystroke or when the
  /// composer closes. Screen readers hear the announcement from [_announce]
  /// instead (it names the Escape key, which touch users lack), so the visible
  /// copy is excluded from semantics.
  String? _freeTextConfirmation;
  final FocusNode _freeTextFocusNode = FocusNode(
    debugLabel: 'figure-free-text',
  );

  /// Free-text entry is active only when the caller opted in AND wired an
  /// insertion callback; otherwise the Add flow keeps its structured behaviour.
  bool get _freeTextEnabled =>
      widget.freeTextEntry && widget.onAddFreeText != null;

  Dialect get _dialect => widget.dialect ?? Dialect.larksRobins;
  AppLocalizations get _l10n => AppLocalizations.of(context);

  ValueKey<String> _key(String suffix) =>
      ValueKey('${widget.keyPrefix}-$suffix');

  FocusNode _rowFocusNode(String id) => _rowFocusNodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: 'figure-row-$id'),
  );

  @override
  void initState() {
    super.initState();
    _freeTextController.addListener(_reportPendingLine);
    widget.freeTextComposerController?.attach(_submitPendingLine);
    // A fresh editor has no line; this clears a flag left by one it replaced.
    _reportPendingLine();
  }

  @override
  void didUpdateWidget(FigureListEditor old) {
    super.didUpdateWidget(old);
    if (old.freeTextComposerController != widget.freeTextComposerController) {
      old.freeTextComposerController?.detach(_submitPendingLine);
      widget.freeTextComposerController?.attach(_submitPendingLine);
      _reportPendingLine();
    }
    final ids = widget.drafts.map((d) => d.id).toSet();

    // Auto-open + focus the figure the Add flow just appended.
    if (_openLastAfterAdd) {
      _openLastAfterAdd = false;
      if (widget.drafts.isNotEmpty) {
        final newId = widget.drafts.last.id;
        _openDraftId = newId;
        _ensureVisibleSoon(newId);
        _announce(_l10n.danceEditorAddedFigureChooseMove(widget.drafts.length));
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
    if (_freeTextComposing && (!_freeTextEnabled || !widget.allowAdding)) {
      _dismissFreeText(focusAddButton: widget.allowAdding);
    }

    _openPendingContainerDraft(rebuild: false);
  }

  @override
  void dispose() {
    for (final node in _rowFocusNodes.values) {
      node.dispose();
    }
    _addButtonFocusNode.dispose();
    _addMenuFirstItemFocusNode.dispose();
    widget.freeTextComposerController?.detach(_submitPendingLine);
    _ownPendingMoveText?.dispose();
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
    final onReorder = widget.onReorder;
    if (onReorder == null) return;
    final cutIndex = widget.drafts.indexWhere((d) => d.id == cutId);
    if (cutIndex == -1) {
      setState(() => _cutDraftId = null);
      return;
    }
    setState(() => _cutDraftId = null);
    // After removing the cut item, the insertion point shifts down by one if
    // beforeIndex is after the cut item.
    final finalPos = beforeIndex > cutIndex ? beforeIndex - 1 : beforeIndex;
    onReorder(cutIndex, finalPos);
    _announce(_l10n.danceEditorFigurePastedAnnouncement(finalPos + 1));
  }

  // --- Reorder --------------------------------------------------------------
  /// Reorders using pre-adjusted (`onReorderItem`) semantics and announces the
  /// new position. When [refocus] is set the moved row regains focus so
  /// keyboard users can chain Alt+Arrow / menu moves.
  void _reorder(int oldIndex, int newIndex, {bool refocus = false}) {
    if (oldIndex < 0 || oldIndex >= widget.drafts.length) return;
    final onReorder = widget.onReorder;
    if (onReorder == null) return;
    final movedId = widget.drafts[oldIndex].id;
    onReorder(oldIndex, newIndex);
    _announce(
      _l10n.danceEditorFigureMovedAnnouncement(
        newIndex + 1,
        widget.drafts.length,
      ),
    );
    if (refocus) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _rowFocusNode(movedId).requestFocus(),
      );
    }
  }

  // --- Accordion ------------------------------------------------------------
  void _openDraft(String id) {
    // Opening a row closes the open one, and its Move box with it: settle the
    // box first, as leaving it does, since a tap does not always take focus.
    _pendingMoveText.settle();
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
      final name = _figureDisplayName(
        widget.drafts[i],
        widget.taxonomy,
        _l10n,
        _dialect,
        UserFiguresScope.catalogOf(context),
      );
      _announce(_l10n.danceEditorEditingFigureAnnouncement(i + 1, name));
    }
  }

  void _closeDraft(String id) {
    _pendingMoveText.settle();
    final i = widget.drafts.indexWhere((d) => d.id == id);
    if (_openDraftId == id) setState(() => _openDraftId = null);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _rowFocusNode(id).requestFocus(),
    );
    if (i != -1) {
      _announce(_l10n.danceEditorCollapsedFigureAnnouncement(i + 1));
    }
  }

  void _toggleDraft(String id) =>
      _openDraftId == id ? _closeDraft(id) : _openDraft(id);

  /// Ctrl/Cmd+Enter: commit the current editor (edits are already live) and
  /// open the next figure's editor — or add a new figure when at the end.
  void _commitAndOpenNext(String id) {
    final i = widget.drafts.indexWhere((d) => d.id == id);
    if (i == -1) return;
    _pendingMoveText.settle();
    if (i < widget.drafts.length - 1) {
      _openDraft(widget.drafts[i + 1].id);
    } else {
      _addFigure();
    }
  }

  void _addFigure() {
    if (!widget.allowAdding) return;
    // The new row opens in place of the open one.
    _pendingMoveText.settle();
    if (_freeTextEnabled) {
      // Free-text entry (opt-in): open a single free-text field instead of
      // appending a blank structured draft. The typed line is parsed and
      // inserted on submit (see [_submitFreeText]).
      setState(() => _freeTextComposing = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _freeTextFocusNode.requestFocus();
      });
      _announce(_l10n.danceEditorTypeFigureAnnouncement);
      return;
    }
    _openLastAfterAdd = true;
    widget.onAdd();
  }

  Future<void> _addContainer(Future<String?> Function()? onAdd) async {
    if (!widget.allowAdding || onAdd == null) return;
    final draftId = await onAdd();
    if (!mounted || draftId == null) return;
    _pendingMeanwhileDraftIds.add(draftId);
    _openPendingContainerDraft(rebuild: true);
  }

  /// Opens the container draft an Add-menu entry just inserted, once it is in
  /// [FigureListEditor.drafts], and announces it by its kind.
  void _openPendingContainerDraft({required bool rebuild}) {
    final ready = _pendingMeanwhileDraftIds
        .where((id) => widget.drafts.any((draft) => draft.id == id))
        .toList();
    if (ready.isEmpty) return;
    final draftId = ready.last;
    _pendingMeanwhileDraftIds.removeAll(ready);

    void openDraft() => _openDraftId = draftId;
    if (rebuild) {
      setState(openDraft);
    } else {
      openDraft();
    }
    _ensureVisibleSoon(draftId);
    final kind = widget.drafts
        .firstWhere((draft) => draft.id == draftId)
        .containerKind;
    _announce(switch (kind) {
      modifierMove => _l10n.danceEditorAddedModifierAnnouncement,
      sequenceMove => _l10n.danceEditorAddedSequenceAnnouncement,
      _ => _l10n.danceEditorAddedMeanwhileAnnouncement,
    });
  }

  Widget _buildAddAffordance(BuildContext context, {required bool empty}) {
    if (!widget.allowAdding) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final onAddMeanwhile = widget.onAddMeanwhile;
    final onAddModifier = widget.onAddModifier;
    final onAddSequence = widget.onAddSequence;
    final addButton = empty
        ? FilledButton.icon(
            focusNode: _addButtonFocusNode,
            onPressed: _addFigure,
            icon: const Icon(Icons.add),
            label: Text(l10n.danceEditorAddFirstFigure),
          )
        : TextButton.icon(
            focusNode: _addButtonFocusNode,
            onPressed: _addFigure,
            icon: const Icon(Icons.add),
            label: Text(l10n.danceEditorAddFigure),
          );
    if (onAddMeanwhile == null &&
        onAddModifier == null &&
        onAddSequence == null) {
      return KeyedSubtree(key: _key('add'), child: addButton);
    }

    return MenuAnchor(
      key: _key('add'),
      onOpen: () => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addMenuFirstItemFocusNode.requestFocus();
      }),
      builder: (context, controller, child) => empty
          ? FilledButton.icon(
              focusNode: _addButtonFocusNode,
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              icon: const Icon(Icons.add),
              label: Text(l10n.danceEditorAddFirstFigure),
            )
          : TextButton.icon(
              focusNode: _addButtonFocusNode,
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              icon: const Icon(Icons.add),
              label: Text(l10n.danceEditorAddFigure),
            ),
      menuChildren: [
        MenuItemButton(
          key: _key('add-figure'),
          focusNode: _addMenuFirstItemFocusNode,
          onPressed: _addFigure,
          child: Text(l10n.danceEditorAddFigure),
        ),
        if (onAddMeanwhile != null)
          MenuItemButton(
            key: _key('add-meanwhile'),
            onPressed: () => _addContainer(onAddMeanwhile),
            child: Text(l10n.danceEditorAddMeanwhile),
          ),
        if (onAddModifier != null)
          MenuItemButton(
            key: _key('add-modifier'),
            onPressed: () => _addContainer(onAddModifier),
            child: Text(l10n.danceEditorAddModifier),
          ),
        if (onAddSequence != null)
          MenuItemButton(
            key: _key('add-sequence'),
            onPressed: () => _addContainer(onAddSequence),
            child: Text(l10n.danceEditorAddSequence),
          ),
      ],
    );
  }

  /// Parses the free-text field's current line through the shared core parser
  /// and inserts the resulting row(s). Keeps the composer open (cleared and
  /// refocused) for rapid entry of the next figure; a blank submit closes it.
  /// This is the keyboard's Enter, the Add button, and a Save with a line
  /// still in the box ([_submitPendingLine]).
  void _submitFreeText() {
    final acceptedCount = _insertFreeTextLine();
    if (acceptedCount == null) return;
    if (acceptedCount == 0) {
      // Nothing to insert (blank, or scrubbed to empty) — close the composer.
      _dismissFreeText();
      return;
    }
    _freeTextAccepted(acceptedCount);
  }

  /// Finish adding: adds a line still in the box, as Enter would, then closes
  /// the composer. It never discards typed text; a line that could not be
  /// added stays in the box.
  void _finishFreeText() {
    final acceptedCount = _insertFreeTextLine();
    if (acceptedCount == null) return;
    _dismissFreeText();
    if (acceptedCount > 0) {
      _announce(_l10n.danceEditorFreeTextFinishedAnnouncement(acceptedCount));
    }
  }

  /// Inserts the row(s) for the composer's line and returns how many were
  /// inserted: 0 when the line yields nothing to insert (blank, or scrubbed to
  /// empty), null when the host declined the rows, leaving the line as it is.
  int? _insertFreeTextLine() {
    final onAddFreeText = widget.onAddFreeText;
    if (onAddFreeText == null) return null;
    // A compound shorthand inserts a placeholder row, which is not a [Figure]
    // the parser could return, so it is offered the line first.
    final shorthandRows =
        widget.onSubmitCompoundShorthand?.call(_freeTextController.text) ?? 0;
    if (shorthandRows > 0) return shorthandRows;
    final figures = parseFreeTextFigureEntry(
      _freeTextController.text,
      taxonomy: widget.taxonomy,
      shorthands: widget.shorthandMappings,
      dialect: _dialect,
    );
    if (figures.isEmpty) return 0;
    final acceptedCount = onAddFreeText(figures);
    return acceptedCount > 0 ? acceptedCount : null;
  }

  /// [FreeTextComposerController.submitPendingLine]: Enter on the composer's
  /// line, for a Save made with the line still in the box. Returns whether no
  /// line is left pending.
  bool _submitPendingLine() {
    if (!_freeTextComposing) return true;
    _submitFreeText();
    return _freeTextController.text.trim().isEmpty;
  }

  bool get _hasPendingLine =>
      _freeTextComposing && _freeTextController.text.trim().isNotEmpty;

  /// A lazy list around the editor (the dance editor's form) would otherwise
  /// dispose it, and the line with it, once it scrolls out of view while the
  /// box is not focused.
  @override
  bool get wantKeepAlive => _hasPendingLine;

  /// Tells [FigureListEditor.freeTextComposerController] whether a line is
  /// waiting in the composer, and keeps the editor alive while one is.
  void _reportPendingLine() {
    widget.freeTextComposerController?.updatePendingLine(_hasPendingLine);
    updateKeepAlive();
  }

  /// Clears the composer after [acceptedCount] rows were inserted, announces
  /// and shows the count ([_freeTextConfirmation]), and keeps the composer
  /// focused for the next line.
  void _freeTextAccepted(int acceptedCount) {
    _freeTextController.clear();
    final message = _l10n.danceEditorFreeTextFiguresAddedAnnouncement(
      acceptedCount,
    );
    setState(
      () => _freeTextConfirmation = _l10n
          .danceEditorFreeTextFiguresAddedConfirmation(acceptedCount),
    );
    _announce(message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _freeTextFocusNode.requestFocus();
    });
  }

  /// Replaces [draft] with the figure(s) parsed from [line], typed into its
  /// Move box and matching no move (#1177). Returns false when nothing was
  /// replaced, so the caller makes the line a stated custom figure instead.
  bool _replaceWithFreeText(FigureDraft draft, String line) {
    final onReplace = widget.onReplaceWithFreeText;
    if (!_freeTextEnabled || onReplace == null) return false;
    final index = widget.drafts.indexOf(draft);
    if (index == -1) return false;
    // A shorthand for a compound or one of the user's figures is offered the
    // line first, as in the composer, since it is not a [Figure] the parser
    // returns.
    final shorthandRows = widget.onReplaceWithShorthand?.call(draft, line) ?? 0;
    if (shorthandRows > 0) {
      _afterRowReplaced(draft, index, shorthandRows);
      return true;
    }
    final figures = parseFreeTextFigureEntry(
      line,
      taxonomy: widget.taxonomy,
      shorthands: widget.shorthandMappings,
      dialect: _dialect,
    );
    if (figures.isEmpty) return false;
    final acceptedCount = onReplace(draft, figures);
    if (acceptedCount <= 0) return false;
    _afterRowReplaced(draft, index, acceptedCount);
    return true;
  }

  /// Whether a Move box's [text] is one of the user's shorthands, of any
  /// kind, which Enter takes as typed rather than as the first move whose
  /// name contains it (AUTH-8).
  bool _isShorthandToken(String text) =>
      widget.shorthandMappings?.resolve(text) != null ||
      (widget.isOwnShorthandToken?.call(text) ?? false);

  /// Settles the editor after [draft], at [index], was replaced by
  /// [acceptedCount] rows.
  void _afterRowReplaced(FigureDraft draft, int index, int acceptedCount) {
    // The replaced row is gone; its replacements arrive collapsed, as rows
    // from the composer do, with focus on the first of them.
    if (_openDraftId == draft.id) setState(() => _openDraftId = null);
    _announce(_l10n.danceEditorFreeTextRowReplacedAnnouncement(acceptedCount));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || index >= widget.drafts.length) return;
      // A row replaced because its Move box lost focus (AUTH-1) leaves focus
      // where the caller moved it. Focus that fell back to a scope went with
      // the replaced row, and comes to its replacement.
      final focused = FocusManager.instance.primaryFocus;
      if (focused != null && focused is! FocusScopeNode) return;
      _rowFocusNode(widget.drafts[index].id).requestFocus();
    });
  }

  /// Closes the free-text composer and returns focus to Add or the last row.
  void _dismissFreeText({bool focusAddButton = true}) {
    setState(() {
      _freeTextComposing = false;
      _freeTextConfirmation = null;
    });
    // After the flag is down, so the listener reports no pending line.
    _freeTextController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (focusAddButton) {
        _addButtonFocusNode.requestFocus();
      } else if (widget.drafts.isNotEmpty) {
        _rowFocusNode(widget.drafts.last.id).requestFocus();
      }
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
    _announce(_l10n.danceEditorDeletedFigureAnnouncement(index + 1));
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
    if (!widget.allowDuplicating || onDuplicate == null) return;
    if (index < 0 || index >= widget.drafts.length) return;
    onDuplicate(widget.drafts[index]);
    _announce(_l10n.danceEditorDuplicatedFigureAnnouncement(index + 1));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin
    return PendingMoveTextScope(
      controller: _pendingMoveText,
      child: Builder(builder: _buildList),
    );
  }

  Widget _buildList(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
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
            child: Text(
              l10n.danceFiguresEmpty,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 4),
          if (_freeTextComposing && widget.allowAdding)
            _buildFreeTextComposer(context)
          else
            Align(
              alignment: Alignment.centerLeft,
              child: _buildAddAffordance(context, empty: true),
            ),
        ],
      );
    }

    // Derive a phrase label per move-bearing draft or structural container by
    // walking cumulative beats, mirroring deriveSections while keeping the
    // draft↔row map.
    // `sectionStart` marks the first figure of each section so the label gutter
    // only prints at section boundaries (like figure_table.dart's headers),
    // while the keyed label widget stays present on every row.
    final labels = <String, String?>{};
    final sectionStart = <String, bool>{};
    var beat = 0;
    var totalBeats = 0;
    var placedCount = 0;
    String? lastLabel;
    if (widget.showPhraseStructure) {
      for (final draft in drafts) {
        // Only rows Save writes count: a row with no move and no note, a group
        // short of two sides, or a modifier group with a blank core builds no
        // figure, and counting its beats would put a figure the saved dance
        // lacks into the Total.
        if (draft.toFigure() == null && !draft.keepsNoteWithoutMove) {
          labels[draft.id] = null;
          sectionStart[draft.id] = false;
          continue;
        }
        final label = labelForFigure(beat, draft.beats, widget.phraseStructure);
        labels[draft.id] = label;
        sectionStart[draft.id] = label != lastLabel;
        lastLabel = label;
        beat += draft.beats;
        totalBeats += draft.beats;
        placedCount++;
      }
    }

    final cutName = _cutDraftId == null
        ? null
        : _figureDisplayName(
            drafts.firstWhere(
              (d) => d.id == _cutDraftId,
              orElse: () => FigureDraft(),
            ),
            widget.taxonomy,
            l10n,
            dialect,
            UserFiguresScope.catalogOf(context),
          );

    final sequenceBeatLimit = widget.phraseStructure.longestPhraseBeats;
    // Resolves a "group with next as [kind]" action for row [i]: null (menu
    // item hidden) when there is no next row or the two cannot form [kind].
    VoidCallback? groupWithNext(
      ValueChanged<FigureDraft>? action,
      String kind,
      int i,
    ) =>
        action == null ||
            i == drafts.length - 1 ||
            !FigureDraft.canGroup(
              kind,
              drafts[i],
              drafts[i + 1],
              sequenceBeatLimit: sequenceBeatLimit,
            )
        ? null
        : () => action(drafts[i]);
    VoidCallback? convertTo(
      ValueChanged<FigureDraft>? action,
      String kind,
      FigureDraft draft,
    ) =>
        action == null ||
            !draft.canConvertContainerTo(
              kind,
              sequenceBeatLimit: sequenceBeatLimit,
            )
        ? null
        : () => action(draft);

    _FigureDraftCard buildCard(int i, {required bool draggable}) {
      final draft = drafts[i];
      final isCutCard = draft.id == _cutDraftId;
      return _FigureDraftCard(
        key: _key('card-${draft.id}'),
        index: i,
        totalCount: drafts.length,
        draft: draft,
        label: labels[draft.id],
        showLabel: sectionStart[draft.id] ?? false,
        taxonomy: widget.taxonomy,
        dialect: dialect,
        canonicalizeDiscouragedTerms: widget.canonicalizeDiscouragedTerms,
        mixer: widget.mixer,
        moveParamDefaults: widget.moveParamDefaults,
        isCut: isCutCard,
        draggable: draggable,
        isOpen: _openDraftId == draft.id,
        phraseStructure: widget.phraseStructure,
        rowFocusNode: _rowFocusNode(draft.id),
        allowModifierSelection: widget.allowModifierSelection,
        allowNestedContainerSelection: widget.allowNestedContainerSelection,
        allowCustom: widget.allowCustom,
        compoundOptions: widget.compoundOptions,
        resolveCompound: widget.resolveCompound,
        userFigureOptions: widget.userFigureOptions,
        onSubmitUnmatchedText:
            _freeTextEnabled && widget.onReplaceWithFreeText != null
            ? (line) => _replaceWithFreeText(draft, line)
            : null,
        isShorthandToken:
            _freeTextEnabled && widget.onReplaceWithFreeText != null
            ? _isShorthandToken
            : null,
        onChanged: widget.onChanged,
        onActivate: () => _toggleDraft(draft.id),
        onClose: () => _closeDraft(draft.id),
        onCommitNext: () => _commitAndOpenNext(draft.id),
        onDelete: () => _deleteDraft(i),
        onDuplicate: widget.onDuplicate == null || !widget.allowDuplicating
            ? null
            : () => _duplicate(i),
        onMoveUp: widget.onReorder == null || i == 0
            ? null
            : () => _reorder(i, i - 1, refocus: true),
        onMoveDown: widget.onReorder == null || i == drafts.length - 1
            ? null
            : () => _reorder(i, i + 1, refocus: true),
        onCut: widget.onReorder == null || isCutCard
            ? null
            : () => _startCut(draft.id),
        snippetLibraryDefaultFor: widget.snippetLibraryDefaultFor,
        onSnippetCommitted: widget.onSnippetCommitted,
        showWordingOverride: widget.showWordingOverride,
        onGroupWithNext: groupWithNext(
          widget.onGroupWithNext,
          meanwhileMove,
          i,
        ),
        onGroupWithNextAsModifier: groupWithNext(
          widget.onGroupWithNextAsModifier,
          modifierMove,
          i,
        ),
        onGroupWithNextAsSequence: groupWithNext(
          widget.onGroupWithNextAsSequence,
          sequenceMove,
          i,
        ),
        onCollapseMeanwhileGroup: widget.onCollapseMeanwhileGroup,
        onConvertToMeanwhile: convertTo(
          widget.onConvertToMeanwhile,
          meanwhileMove,
          draft,
        ),
        onConvertToModifier: convertTo(
          widget.onConvertToModifier,
          modifierMove,
          draft,
        ),
        onConvertToSequence: convertTo(
          widget.onConvertToSequence,
          sequenceMove,
          draft,
        ),
        onUngroupContainer:
            widget.onUngroupContainer == null || !draft.isContainerDraft
            ? null
            : () => widget.onUngroupContainer!(draft),
        keyPrefix: widget.keyPrefix,
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
                    l10n.danceEditorCutBanner(cutName ?? '—'),
                    key: const ValueKey('cut-banner'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey('cut-cancel'),
                  onPressed: _cancelCut,
                  child: Text(l10n.commonCancel),
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
        if (_cutDraftId == null && widget.onReorder != null)
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
        else if (_cutDraftId != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Paste-at-top affordance.
              if (drafts.isNotEmpty)
                _PasteButton(
                  key: const ValueKey('paste-top'),
                  semanticsLabel: l10n.danceEditorPasteBeforeFirstFigure,
                  onPaste: () => _paste(0),
                ),
              for (var i = 0; i < drafts.length; i++) ...[
                buildCard(i, draggable: false),
                // Paste-after-this-card affordance (skip for the cut figure
                // itself — pasting adjacent to the source is a no-op).
                if (drafts[i].id != _cutDraftId)
                  _PasteButton(
                    key: ValueKey('paste-after-${drafts[i].id}'),
                    semanticsLabel: l10n.danceEditorPasteAfterFigure(
                      _figureDisplayName(
                        drafts[i],
                        widget.taxonomy,
                        l10n,
                        dialect,
                        UserFiguresScope.catalogOf(context),
                      ),
                    ),
                    onPaste: () => _paste(i + 1),
                  ),
              ],
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < drafts.length; i++)
                buildCard(i, draggable: false),
            ],
          ),
        const SizedBox(height: 8),
        if (_freeTextComposing && widget.allowAdding)
          _buildFreeTextComposer(context)
        else
          Row(
            children: [
              _buildAddAffordance(context, empty: false),
              if (_cutDraftId != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _PasteButton(
                    key: const ValueKey('paste-end'),
                    semanticsLabel: l10n.danceEditorPasteAtEndOfFigureList,
                    onPaste: () => _paste(drafts.length),
                  ),
                ),
            ],
          ),
        if (widget.showPhraseStructure && placedCount > 0)
          _BeatSummary(
            totalBeats: totalBeats,
            expectedBeats: widget.phraseStructure.totalBeats,
            keyPrefix: widget.keyPrefix,
          ),
      ],
    );
  }

  // --- Free-text composer (issue #419) --------------------------------------
  /// The single-line free-text entry field shown in place of the Add button
  /// while composing. Enter submits (parse + insert), Escape cancels; Finish
  /// adding adds any line still in the box and then closes it, so the button
  /// never discards typed text. Kept deliberately simple: one line at a time,
  /// matching the ruling (no multi-line paste).
  Widget _buildFreeTextComposer(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final confirmation = _freeTextConfirmation;
    // The box is its own semantics boundary: without it the surrounding section
    // help, empty-state text and beat total/warnings merge into the field's
    // label (#1825).
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Focus(
          // A key-handler wrapper only (Escape to cancel); it must not become a
          // tab stop of its own around the field.
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              _dismissFreeText();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: _key('free-text-field'),
                controller: _freeTextController,
                focusNode: _freeTextFocusNode,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  if (_freeTextConfirmation != null) {
                    setState(() => _freeTextConfirmation = null);
                  }
                },
                onSubmitted: (_) => _submitFreeText(),
                // One figure line, but not a `maxLines: 1` field: Flutter puts
                // its single-line formatter ahead of ours and that deletes a
                // pasted line break, gluing `swing⏎partner` into `swingpartner`.
                // A few lines with a text keyboard still submits on the action
                // key; [_lineBreaksToSpaces] turns any line break into a space,
                // keeping a paste one line (#419 rules out splitting it).
                keyboardType: TextInputType.text,
                minLines: 1,
                maxLines: 4,
                inputFormatters: [_lineBreaksToSpaces],
                maxLength: maxFreeTextEntryLength,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                // A figure line is short; the cap is a defensive bound, not a
                // budget to show off — suppress the character counter.
                buildCounter:
                    (
                      _, {
                      required int currentLength,
                      required bool isFocused,
                      int? maxLength,
                    }) => null,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  labelText: l10n.danceEditorTypeFigureLabel,
                  // A widget, not `helperText`: that one is a single ellipsised
                  // line unless capped, and any cap cuts a long translation.
                  helper: Text(
                    l10n.danceEditorTypeFigureHelper,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              // Add and Finish adding sit beneath the field, not beside it:
              // beside it they left the field too narrow for its help at phone
              // width, where the help was cut off mid-word (#1830).
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton(
                      key: _key('free-text-submit'),
                      onPressed: _submitFreeText,
                      child: Text(l10n.commonAdd),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      key: _key('free-text-done'),
                      onPressed: _finishFreeText,
                      child: Text(
                        l10n.danceEditorFreeTextFinish,
                        style: TextStyle(color: theme.colorScheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
              if (confirmation != null)
                Padding(
                  key: _key('free-text-confirmation'),
                  padding: const EdgeInsets.only(top: 4),
                  // Spoken by [_announce]; a second, live-region copy would be
                  // read twice.
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            confirmation,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
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
}

/// Short display name for a draft (for accessibility labels and cut banner).
/// Returns raw text — callers are responsible for any quoting they need.
String _figureDisplayName(
  FigureDraft draft,
  Taxonomy taxonomy,
  AppLocalizations l10n,
  Dialect dialect,
  UserFigureCatalog userFigures,
) {
  if (draft.compound case final compound?) {
    return FigureRenderer(taxonomy).renderFreeText(compound.name, dialect);
  }
  final sides = draft.meanwhileSides;
  if (sides != null) return l10n.danceEditorMeanwhileGroupLabel(sides.length);
  final modifiers = draft.modifierFigures;
  if (modifiers != null) {
    return l10n.danceEditorModifierGroupLabel(modifiers.length);
  }
  final steps = draft.sequenceFigures;
  if (steps != null) return l10n.danceEditorSequenceGroupLabel(steps.length);
  final move = draft.move;
  if (move == null) return l10n.danceEditorEmptyFigureName;
  if (move == customMove) {
    final text = draft.params['text'] as String?;
    if (text == null || text.isEmpty) return l10n.danceEditorCustomFigureName;
    // A use of one of the user's own figures (#1023) reads as the row's
    // summary does, from the figure as it is now; its stored line is the
    // fallback when the figure can't render it.
    final figure = isUserFigureDraft(draft) ? draft.toFigure() : null;
    return figure == null
        ? text
        : FigureRenderer(
            taxonomy,
            userFigures: userFigures,
          ).render(figure, dialect);
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
        label: Text(AppLocalizations.of(context).danceEditorPasteHere),
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
    this.mixer = false,
    this.moveParamDefaults,
    required this.isCut,
    required this.draggable,
    required this.isOpen,
    required this.rowFocusNode,
    this.onSubmitUnmatchedText,
    this.isShorthandToken,
    required this.onChanged,
    required this.onActivate,
    required this.onClose,
    required this.onCommitNext,
    required this.onDelete,
    this.onDuplicate,
    this.onMoveUp,
    this.onMoveDown,
    this.onCut,
    this.snippetLibraryDefaultFor,
    this.onSnippetCommitted,
    this.showWordingOverride = false,
    this.canonicalizeDiscouragedTerms = false,
    this.allowModifierSelection = true,
    this.allowNestedContainerSelection = true,
    this.allowCustom = true,
    this.compoundOptions,
    this.resolveCompound,
    this.userFigureOptions,
    this.onGroupWithNext,
    this.onGroupWithNextAsModifier,
    this.onGroupWithNextAsSequence,
    this.onCollapseMeanwhileGroup,
    this.onConvertToMeanwhile,
    this.onConvertToModifier,
    this.onConvertToSequence,
    this.onUngroupContainer,
    this.phraseStructure = PhraseStructure.standard,
    this.keyPrefix = 'figure',
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

  /// See [FigureListEditor.mixer].
  final bool mixer;
  final bool canonicalizeDiscouragedTerms;

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

  /// Offered text entered in the Move box that matches no move, before it
  /// becomes a stated custom figure; true means it replaced this row (#1177).
  /// See [FigureListEditor.onReplaceWithFreeText].
  final bool Function(String line)? onSubmitUnmatchedText;

  /// Whether Move-box text is a shorthand, sent to [onSubmitUnmatchedText]
  /// on Enter unless a move is named by it exactly. Null while free-text
  /// entry is off: shorthands only work with it on.
  final bool Function(String text)? isShorthandToken;

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

  /// Resolves the global snippet-library default for this figure (#411); `null`
  /// hides the walkthrough-snippet affordance. See [FigureListEditor].
  final String? Function(FigureDraft draft)? snippetLibraryDefaultFor;

  /// Commit hook for a per-figure snippet edit (field blur). See
  /// [FigureListEditor.onSnippetCommitted].
  final void Function(FigureDraft draft)? onSnippetCommitted;

  final bool showWordingOverride;
  final bool allowModifierSelection;
  final bool allowNestedContainerSelection;

  /// See [FigureListEditor.allowCustom].
  final bool allowCustom;

  /// See [FigureListEditor.compoundOptions].
  final List<UserGlossaryEntry>? compoundOptions;

  /// See [FigureListEditor.userFigureOptions].
  final List<UserGlossaryEntry>? userFigureOptions;

  /// See [FigureListEditor.resolveCompound].
  final CompoundResolver? resolveCompound;

  /// Resolved "group with next" action for THIS row (#590/#593), already
  /// accounting for adjacency/flat-only conditions (see
  /// [FigureListEditor.onGroupWithNext]). `null` hides the menu item.
  final VoidCallback? onGroupWithNext;

  final VoidCallback? onGroupWithNextAsModifier;
  final VoidCallback? onGroupWithNextAsSequence;

  /// Collapses [draft] (when it `isMeanwhileGroup`) back to a plain figure.
  /// See [FigureListEditor.onCollapseMeanwhileGroup].
  final void Function(FigureDraft groupDraft, FigureDraft remainingSide)?
  onCollapseMeanwhileGroup;
  final VoidCallback? onConvertToMeanwhile;
  final VoidCallback? onConvertToModifier;
  final VoidCallback? onConvertToSequence;
  final VoidCallback? onUngroupContainer;

  /// The enclosing dance's phrase structure: a sequence's steps must fit in
  /// one of its phrases ([PhraseStructure.longestPhraseBeats]).
  final PhraseStructure phraseStructure;
  final String keyPrefix;

  @override
  State<_FigureDraftCard> createState() => _FigureDraftCardState();
}

/// Replaces an ordinary draft with a minimally valid container draft of
/// [kind] (a modifier or sequence) while preserving the selected figure as its
/// first child: a modifier's core, a sequence's first step. The editor keeps
/// the same parent object so callers only need the usual [onChanged] rebuild.
void _initializeContainer(FigureDraft draft, String kind) {
  if (draft.isContainerDraft) return;
  // A compound placeholder cannot be a container's child (#709): the
  // container starts with an empty one instead.
  final core = draft.clone()..compound = null;
  final beats = draft.beats;
  final beatsTouched = draft.beatsTouched;
  draft.move = null;
  draft.params
    ..clear()
    ..['beats'] = beats;
  draft
    ..note = ''
    ..progression = false
    ..beatsTouched = beatsTouched
    ..assumedSubject = false
    ..customOrigin = CustomOrigin.userEntered
    ..walkthroughOverride = null
    ..wordingOverride = null
    ..compound = null
    ..setContainer(kind, [core, FigureDraft()]);
}

class _FigureDraftCardState extends State<_FigureDraftCard> {
  ValueKey<String> _key(String suffix) =>
      ValueKey('${widget.keyPrefix}-${widget.index}-$suffix');

  /// First enabled item of the ⋮ menu. Opening the menu does not move focus
  /// into it, so without this a keyboard user's Down/Enter land on the page
  /// behind it (#1831). The first items are disabled at the ends of the list.
  final FocusNode _menuFirstItemFocusNode = FocusNode(
    debugLabel: 'figure-row-menu-first',
  );

  /// Whether the on-demand note field is revealed. Existing notes are always
  /// shown (never hide existing content); an empty note starts hidden behind
  /// the "+ Add note" button.
  bool _showNote = false;

  /// Whether the ">3 params" overflow disclosure is expanded.
  bool _showMoreOptions = false;

  /// One-shot flag so the note field autofocuses the first frame after the
  /// user taps "+ Add note".
  bool _justRevealedNote = false;

  /// Whether the on-demand walkthrough snippet field is revealed (#411). An
  /// existing resolved snippet (override or library default) is always shown; an
  /// empty one starts hidden behind the "+ Add walkthrough step" button.
  bool _showSnippet = false;

  /// One-shot autofocus flag for the snippet field, mirroring [_justRevealedNote].
  bool _justRevealedSnippet = false;

  /// Whether the per-dance wording field is revealed.
  bool _showWordingOverride = false;

  @override
  void dispose() {
    _menuFirstItemFocusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _showNote = widget.draft.note.trim().isNotEmpty;
    _showWordingOverride =
        widget.draft.wordingOverride?.trim().isNotEmpty ?? false;
    _showSnippet = _resolvedSnippet().trim().isNotEmpty;
    // Seed beats for custom figures loaded from data that predates #795.
    // Old custom figures carry no 'beats' key; the editor would display
    // the taxonomy default but toFigure() would persist nothing — leaving
    // figure.beats to read 0 downstream. Seed the draft now so the
    // displayed value and the saved value agree from the first render.
    // beatsTouched stays false: this is a default fill, not a user override.
    if (widget.draft.move == customMove &&
        !widget.draft.params.containsKey('beats')) {
      final def = widget.taxonomy.resolve(customMove);
      if (def?.params['beats'] case final beatsSpec?) {
        widget.draft.params['beats'] = beatsSpec.defaultValue;
      }
    }
  }

  /// The snippet text currently shown for this figure: the per-dance override
  /// if set, else the global library default (via [widget.snippetLibraryDefaultFor]),
  /// else empty.
  String _resolvedSnippet() {
    final override = widget.draft.walkthroughOverride?.trim();
    if (override != null && override.isNotEmpty) return override;
    return widget.snippetLibraryDefaultFor?.call(widget.draft) ?? '';
  }

  // --- Move mutations (live) ------------------------------------------------
  void _selectMove(String moveId) {
    if (widget.draft.move == moveId) return;
    widget.draft.move = moveId;
    widget.draft.compound = null;
    widget.draft.params
      ..clear()
      ..addAll(widget.taxonomy.entryParams(moveId));
    // Picking a move is an explicit authorship action: any inherited
    // parser-assumed-subject marker (#460) no longer applies.
    widget.draft.assumedSubject = false;
    // …and the figure is now a stated, user-authored choice, so it is no longer
    // a parser-gap custom (#419): drop any inherited importGap origin.
    widget.draft.customOrigin = CustomOrigin.userEntered;
    widget.draft.wordingOverride = null;
    // A fresh move brings a fresh canonical beat default; that default is
    // authoritative until the user overrides it again. A saved per-move beats
    // default (DD.3) is a user-configured value, so _applyMoveParamDefaults
    // re-marks beats as touched when it applies one.
    widget.draft.beatsTouched = false;
    // #976: apply a saved per-move default FIRST — it may itself override
    // `who` (defaults are sparse per-param diffs, `display_defaults.dart`),
    // and seeding hand from the PRE-override `who` would then store a hand
    // for a role the default just replaced. Seed the role-implied hand
    // afterward, from the now-final `who` — unless the saved default itself
    // named an explicit `hand`, which must win.
    _applyMoveParamDefaults(moveId);
    final chainOverrides = widget.moveParamDefaults?[moveId];
    if (chainOverrides == null || !chainOverrides.containsKey('hand')) {
      seedChainHand(moveId, widget.draft.params);
    }
    _showMoreOptions = false;
    widget.onChanged();
  }

  void _selectContainer(String kind) {
    _initializeContainer(widget.draft, kind);
    widget.onChanged();
  }

  /// Turns this row into a placeholder for the user's compound [entryId]
  /// (#709), its arguments seeded with the values its author wrote. Whatever
  /// the row held before is replaced, as picking a move replaces it.
  void _selectCompound(String entryId) {
    final entry = widget.compoundOptions
        ?.where((e) => e.id == entryId)
        .firstOrNull;
    final definition = widget.resolveCompound?.call(entryId);
    if (entry == null || definition == null) return;
    final draft = widget.draft;
    draft
      ..move = null
      ..beatsTouched = false
      ..assumedSubject = false
      ..customOrigin = CustomOrigin.userEntered
      ..walkthroughOverride = null
      ..wordingOverride = null
      ..compound = CompoundPlaceholder(
        id: entryId,
        name: entry.name,
        args: previewArguments(definition, widget.taxonomy) ?? {},
      );
    draft.params.clear();
    _refreshCompoundBeats();
    _showMoreOptions = false;
    widget.onChanged();
  }

  /// Updates the placeholder's beat count from its expansion, when it has one.
  void _refreshCompoundBeats() {
    final compound = widget.draft.compound;
    final resolve = widget.resolveCompound;
    if (compound == null || resolve == null) return;
    if (expandPlaceholder(compound, resolve) case final expanded?) {
      compound.beats = CompoundDefinition.beatsOf(expanded, widget.taxonomy);
    }
  }

  /// The user's compounds and new figures as move-picker options, named in
  /// the dialect.
  List<MoveOption> _compoundPickerOptions() => [
    ..._userEntryPickerOptions(
      widget.compoundOptions,
      MoveOptionKind.compound,
      widget.dialect,
    ),
    ..._userEntryPickerOptions(
      widget.userFigureOptions,
      MoveOptionKind.userFigure,
      widget.dialect,
    ),
  ];

  void _onMoveOptionSelected(MoveOption option) => switch (option.kind) {
    MoveOptionKind.modifier => _selectContainer(modifierMove),
    MoveOptionKind.sequence => _selectContainer(sequenceMove),
    MoveOptionKind.compound => _selectCompound(option.id),
    MoveOptionKind.userFigure => _selectUserFigure(option.id),
    MoveOptionKind.move => _selectMove(option.id),
  };

  /// Makes this row a use of the user's figure [entryId] (#1023), with its
  /// defaults and its default beats. Whatever the row held before is
  /// replaced, as picking a move replaces it.
  void _selectUserFigure(String entryId) {
    if (selectUserFigure(widget.draft, entryId, widget.userFigureOptions)) {
      _showMoreOptions = false;
      widget.onChanged();
    }
  }

  /// Enter on Move-box text that matches no move: with free-text entry on, the
  /// line is parsed and replaces this row (#1177); otherwise, or when the
  /// replacement is declined, it becomes a stated custom figure.
  void _submitUnmatched(String text) {
    if (widget.onSubmitUnmatchedText?.call(text) ?? false) return;
    _createCustom(text);
  }

  void _createCustom(String text) {
    final trimmed = text.trim();
    // Ignore an all-whitespace submission rather than creating an empty
    // custom figure.
    if (trimmed.isEmpty) return;
    widget.draft.move = customMove;
    widget.draft.compound = null;
    widget.draft.params
      ..clear()
      ..addAll(widget.taxonomy.effectiveParams(Figure(move: customMove)));
    widget.draft.beatsTouched = false;
    // A user-authored custom figure carries no assumed subject (#460).
    widget.draft.assumedSubject = false;
    // Authoring a custom by hand is a stated choice, not a parser gap (#419).
    // With free-text entry on, the line reaches here only when the list
    // declined to replace the row with the parsed figures (#1177).
    widget.draft.customOrigin = CustomOrigin.userEntered;
    widget.draft.wordingOverride = null;
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
    if (widget.draft.move == null && !widget.draft.isCompoundPlaceholder) {
      return;
    }
    widget.draft.move = null;
    widget.draft.compound = null;
    widget.draft.params.clear();
    widget.draft.beatsTouched = false;
    widget.draft.wordingOverride = null;
    _showMoreOptions = false;
    widget.onChanged();
  }

  /// Applies a non-`beats` param change with every rule it carries — the
  /// hey and promenade resets, the `balance` flag's ±4 beats, chain's
  /// role-implied hand, inverse-pair rerouting, and reconciling `beats` with
  /// the move's canonical default (#262), which keeps a manual override
  /// ([FigureDraft.beatsTouched]) unless the opt-in "Aggressively recompute
  /// figure beats" setting (#689) is on. The rules are core's
  /// [applyParamChange], which documents each one.
  void _applyNonBeatsParamChange(String key, Object? value) {
    final draft = widget.draft;
    // Explicitly editing the subject makes it a stated choice, so it is no
    // longer a parser-assumed default (#460): drop the non-authoritative marker.
    if (key == 'who') draft.assumedSubject = false;
    final move = draft.move;
    if (move == null) {
      draft.params[key] = value;
      return;
    }
    // The rules themselves are in core, shared with compound expansion (#709).
    // The aggressive-beats setting only matters for a manual override, so it is
    // read only then.
    draft.move = applyParamChange(
      widget.taxonomy,
      move: move,
      params: draft.params,
      key: key,
      value: value,
      beatsTouched: draft.beatsTouched,
      aggressiveBeats:
          draft.beatsTouched && AggressiveBeatsUpdateScope.of(context),
    );
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
    // Enter/Space activate the row only when the row itself is focused. Key
    // events also bubble up from the ⋮ button and its open menu, which sit under
    // this Focus; claiming them here would stop the menu from opening and its
    // items from activating by keyboard (#1831).
    if (!isAlt &&
        node.hasPrimaryFocus &&
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
    final l10n = AppLocalizations.of(context);
    final draft = widget.draft;
    final figure = draft.toFigure();
    final hasMove = figure != null;
    final renderer = FigureRenderer(
      widget.taxonomy,
      userFigures: UserFiguresScope.catalogOf(context),
    );
    String displaySummary({required bool verbose}) {
      return widget.canonicalizeDiscouragedTerms
          ? renderer.renderSummaryWithCanonicalDiscouragedTerms(
              figure!,
              widget.dialect,
              verbose: verbose,
              decimals: !verbose && DecimalTurnsScope.of(context),
            )
          : renderer.renderSummary(
              figure!,
              widget.dialect,
              verbose: verbose,
              decimals: !verbose && DecimalTurnsScope.of(context),
            );
    }

    // A group not complete enough to save, said on its row as the Warnings
    // card says it (AUTH-2), so the row is not mistaken for part of the dance.
    final incomplete = draft.isIncomplete;
    final compound = draft.compound;
    final resolve = widget.resolveCompound;
    // A placeholder that cannot expand is saved as its name alone (#709).
    final compoundUnavailable =
        compound != null &&
        (resolve == null || expandPlaceholder(compound, resolve) == null);
    final sentence = compound != null
        ? capitalizeFirstLetter(
            _compoundSummary(l10n, compound),
            capitalize: CapitalizeFiguresScope.of(context),
          )
        : hasMove
        ? capitalizeFirstLetter(
            displaySummary(verbose: false),
            capitalize: CapitalizeFiguresScope.of(context),
          )
        : l10n.danceEditorEmptyFigureSummary;
    final spoken = compound != null
        ? l10n.danceEditorCompoundSemantic(
            _compoundSummary(l10n, compound),
            compoundUnavailable ? 'yes' : 'no',
          )
        : hasMove
        ? displaySummary(verbose: true)
        : l10n.danceEditorEmptyFigureSemantic;
    final note = draft.note.trim();
    final hasNote = note.isNotEmpty;
    final displayNote = hasNote
        ? widget.canonicalizeDiscouragedTerms
              ? renderer.renderFreeTextWithCanonicalDiscouragedTerms(
                  note,
                  widget.dialect,
                )
              : renderer.renderFreeText(note, widget.dialect)
        : '';
    final noteDiscouraged =
        hasNote && canonicalize(note, widget.dialect).discouraged.isNotEmpty;
    final beatsLabel = l10n.danceFigureBeats(draft.beats);
    // Parser-gap custom (#398/#419): a *custom* figure the parser could not
    // map, whether from import or a locally-typed free-text line. Guarded on
    // the custom move (like figure_table.dart / perform_card.dart) so a
    // tampered draft that pairs a real move with an importGap origin can't
    // surface the marker. Surfaces the same inline marker as the read-only
    // figure table and stays reparse-eligible.
    final isImportGap =
        draft.move == customMove &&
        draft.customOrigin == CustomOrigin.importGap;
    final labelText = (widget.showLabel && widget.label != null)
        ? widget.label!
        : '';

    // Screen-reader composite: "A1, neighbors balance and swing, progression,
    // 16 beats, note: smooth swing. Figure 3 of 12."
    final main = labelText.isEmpty ? spoken : '$labelText, $spoken';
    final summarySemantic = l10n.danceEditorFigureSummarySemantic(
      main,
      isImportGap ? 'yes' : 'no',
      l10n.importGapMessage,
      draft.progression ? 'yes' : 'no',
      hasMove ? 'yes' : 'no',
      draft.beats,
      hasNote ? 'yes' : 'no',
      displayNote,
      widget.index + 1,
      widget.totalCount,
    );
    final composite = incomplete
        ? '$summarySemantic ${l10n.danceEditorIncompleteFigure}'
        : summarySemantic;

    final summaryContent = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: composite,
            hint: l10n.danceEditorActivateToEditHint,
            excludeSemantics: true,
            child: InkWell(
              key: _key('summary'),
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
                        key: _key('label'),
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
                              message: l10n.commonProgression,
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
                          if (compound != null)
                            Row(
                              children: [
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    end: 4,
                                  ),
                                  child: Icon(
                                    Icons.person_outline,
                                    size: 16,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                Flexible(
                                  child: Text(
                                    sentence,
                                    style: theme.textTheme.bodyLarge,
                                  ),
                                ),
                              ],
                            )
                          else
                            Text(
                              sentence,
                              style: hasMove
                                  ? theme.textTheme.bodyLarge
                                  : theme.textTheme.bodyLarge?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontStyle: FontStyle.italic,
                                    ),
                            ),
                          if (compoundUnavailable)
                            Text(
                              l10n.danceEditorCompoundUnavailable,
                              key: _key('compound-unavailable'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          if (incomplete)
                            Text(
                              l10n.danceEditorIncompleteFigure,
                              key: _key('incomplete'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
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
                                      Icons.warning_amber_outlined,
                                      size: 13,
                                      color: theme.colorScheme.error,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Expanded(
                                    child: Text(
                                      displayNote,
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

  /// A placeholder's one-line summary: the compound's name in the dialect and
  /// the value it gives each parameter, in the order they are declared.
  String _compoundSummary(AppLocalizations l10n, CompoundPlaceholder compound) {
    final name = FigureRenderer(
      widget.taxonomy,
    ).renderFreeText(compound.name, widget.dialect);
    final definition = widget.resolveCompound?.call(compound.id);
    if (definition == null || definition.params.isEmpty) return name;
    final values = compoundArgumentsText(
      l10n,
      definition,
      compound.args,
      widget.dialect,
    );
    return l10n.danceEditorCompoundSummary(name, values);
  }

  Widget _buildDragHandle(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!widget.draggable) {
      // Keep the horizontal footprint stable so rows don't jump between
      // reorderable and cut/paste modes.
      return const Icon(Icons.drag_handle, size: 20, color: Colors.transparent);
    }
    final figureName = _figureDisplayName(
      widget.draft,
      widget.taxonomy,
      l10n,
      widget.dialect,
      UserFiguresScope.catalogOf(context),
    );
    return ReorderableDragStartListener(
      index: widget.index,
      child: Semantics(
        label: l10n.danceEditorDragToReorderFigure(figureName),
        child: const Icon(Icons.drag_handle, size: 20),
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final draft = widget.draft;
    final figureName = _figureDisplayName(
      draft,
      widget.taxonomy,
      l10n,
      widget.dialect,
      UserFiguresScope.catalogOf(context),
    );
    // The first enabled item takes focus when the menu opens; later items get
    // none.
    var firstItemClaimed = false;
    FocusNode? firstEnabled(VoidCallback? onPressed) {
      if (onPressed == null || firstItemClaimed) return null;
      firstItemClaimed = true;
      return _menuFirstItemFocusNode;
    }

    return MenuAnchor(
      onOpen: () => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _menuFirstItemFocusNode.requestFocus();
      }),
      builder: (context, controller, child) => IconButton(
        key: _key('menu'),
        icon: const Icon(Icons.more_vert),
        tooltip: l10n.danceEditorFigureActionsTooltip(figureName),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        MenuItemButton(
          key: _key('move-up'),
          focusNode: firstEnabled(widget.onMoveUp),
          onPressed: widget.onMoveUp,
          leadingIcon: const Icon(Icons.arrow_upward, size: 18),
          child: Text(l10n.danceEditorMoveUp),
        ),
        MenuItemButton(
          key: _key('move-down'),
          focusNode: firstEnabled(widget.onMoveDown),
          onPressed: widget.onMoveDown,
          leadingIcon: const Icon(Icons.arrow_downward, size: 18),
          child: Text(l10n.danceEditorMoveDown),
        ),
        MenuItemButton(
          key: _key('cut'),
          focusNode: firstEnabled(widget.onCut),
          onPressed: widget.onCut,
          leadingIcon: const Icon(Icons.content_cut, size: 18),
          child: Text(l10n.danceEditorCut),
        ),
        if (widget.onDuplicate != null)
          MenuItemButton(
            key: _key('duplicate'),
            focusNode: firstEnabled(widget.onDuplicate),
            onPressed: widget.onDuplicate,
            leadingIcon: const Icon(Icons.copy_outlined, size: 18),
            child: Text(l10n.commonDuplicate),
          ),
        if (widget.onGroupWithNext != null)
          MenuItemButton(
            key: _key('group-with-next'),
            focusNode: firstEnabled(widget.onGroupWithNext),
            onPressed: widget.onGroupWithNext,
            leadingIcon: const Icon(Icons.call_split, size: 18),
            child: Text(l10n.danceEditorGroupWithNext),
          ),
        if (widget.onGroupWithNextAsModifier != null)
          MenuItemButton(
            key: _key('group-with-next-modifier'),
            focusNode: firstEnabled(widget.onGroupWithNextAsModifier),
            onPressed: widget.onGroupWithNextAsModifier,
            leadingIcon: const Icon(Icons.tune, size: 18),
            child: Text(l10n.danceEditorGroupWithNextAsModifier),
          ),
        if (widget.onGroupWithNextAsSequence != null)
          MenuItemButton(
            key: _key('group-with-next-sequence'),
            focusNode: firstEnabled(widget.onGroupWithNextAsSequence),
            onPressed: widget.onGroupWithNextAsSequence,
            leadingIcon: const Icon(Icons.format_list_numbered, size: 18),
            child: Text(l10n.danceEditorGroupWithNextAsSequence),
          ),
        if (widget.onConvertToMeanwhile != null)
          MenuItemButton(
            key: _key('convert-to-meanwhile'),
            focusNode: firstEnabled(widget.onConvertToMeanwhile),
            onPressed: widget.onConvertToMeanwhile,
            leadingIcon: const Icon(Icons.sync_alt, size: 18),
            child: Text(l10n.danceEditorConvertToMeanwhile),
          ),
        if (widget.onConvertToModifier != null)
          MenuItemButton(
            key: _key('convert-to-modifier'),
            focusNode: firstEnabled(widget.onConvertToModifier),
            onPressed: widget.onConvertToModifier,
            leadingIcon: const Icon(Icons.tune, size: 18),
            child: Text(l10n.danceEditorConvertToModifier),
          ),
        if (widget.onConvertToSequence != null)
          MenuItemButton(
            key: _key('convert-to-sequence'),
            focusNode: firstEnabled(widget.onConvertToSequence),
            onPressed: widget.onConvertToSequence,
            leadingIcon: const Icon(Icons.format_list_numbered, size: 18),
            child: Text(l10n.danceEditorConvertToSequence),
          ),
        if (widget.onUngroupContainer != null)
          MenuItemButton(
            key: _key('ungroup-container'),
            focusNode: firstEnabled(widget.onUngroupContainer),
            onPressed: widget.onUngroupContainer,
            leadingIcon: const Icon(Icons.call_merge, size: 18),
            child: Text(switch (draft.containerKind) {
              modifierMove => l10n.danceEditorUngroupModifier,
              sequenceMove => l10n.danceEditorUngroupSequence,
              _ => l10n.danceEditorUngroupMeanwhile,
            }),
          ),
        MenuItemButton(
          key: _key('toggle-progression'),
          focusNode: firstEnabled(_toggleProgression),
          onPressed: _toggleProgression,
          leadingIcon: Icon(
            draft.progression ? Icons.flag : Icons.outlined_flag,
            size: 18,
          ),
          child: Text(
            draft.progression
                ? l10n.danceEditorClearProgression
                : l10n.danceEditorMarkProgression,
          ),
        ),
        MenuItemButton(
          key: _key('delete'),
          focusNode: firstEnabled(widget.onDelete),
          onPressed: widget.onDelete,
          leadingIcon: Icon(
            Icons.delete_outline,
            size: 18,
            color: theme.colorScheme.error,
          ),
          style: MenuItemButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
          ),
          child: Text(l10n.commonDelete),
        ),
      ],
    );
  }

  // --- Expanded editor ------------------------------------------------------
  Widget _buildEditor(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;
    if (draft.isContainerDraft) {
      return _buildContainerEditor(context);
    }
    if (draft.isCompoundPlaceholder) {
      return _buildCompoundEditor(context);
    }
    if (isUserFigureDraft(draft)) {
      return _buildUserFigureEditor(context);
    }
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
                key: _key('move'),
                fieldKey: 'figure-${widget.index}-move',
                taxonomy: widget.taxonomy,
                dialect: widget.dialect,
                initialText: moveText,
                autofocus: move == null || move == _standStillMove,
                includeModifier: widget.allowModifierSelection,
                includeSequence: widget.allowModifierSelection,
                sequenceOptionLabel: AppLocalizations.of(
                  context,
                ).danceEditorSequenceOptionLabel,
                includeCustomMove: widget.allowCustom,
                compoundOptions: _compoundPickerOptions(),
                compoundMarkerLabel: AppLocalizations.of(
                  context,
                ).glossaryCustomMarker,
                onSelected: _onMoveOptionSelected,
                onCustomSubmitted: widget.allowCustom ? _submitUnmatched : null,
                submitsAsText: widget.allowCustom
                    ? widget.isShorthandToken
                    : null,
                onCleared: _clearMove,
                commitOnBlur: true,
              ),
              if (def != null) ...[
                const SizedBox(height: 12),
                // Custom figures: lingo text field + beats editor (#795).
                if (draft.move == customMove) ...[
                  _LingoCustomTextField(
                    key: _key('text-${draft.id}'),
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
                      // Rewriting the text is authoring it: the line is no
                      // longer one the parser could not read, so it loses the
                      // "couldn't parse" badge and Re-check leaves it alone.
                      draft.customOrigin = CustomOrigin.userEntered;
                      widget.onChanged();
                    },
                  ),
                  // Source spec and default directly from the taxonomy so the
                  // editor and the taxonomy agree without a hardcoded copy (#795).
                  if (def.params['beats'] case final beatsSpec?) ...[
                    const SizedBox(height: 8),
                    FigureParamEditor(
                      keyPrefix: 'figure-${widget.index}',
                      paramKey: 'beats',
                      spec: beatsSpec,
                      dialect: widget.dialect,
                      mixer: widget.mixer,
                      value: draft.params['beats'] ?? beatsSpec.defaultValue,
                      onChanged: (v) {
                        draft.params['beats'] = v;
                        draft.beatsTouched = true;
                        widget.onChanged();
                      },
                    ),
                  ],
                ] else if (def.params.isNotEmpty)
                  _buildParams(context, def),
                const SizedBox(height: 12),
                _buildProgressionToggle(context),
                const SizedBox(height: 8),
                _buildNote(context),
                _buildWalkthroughSnippet(context),
                if (widget.showWordingOverride) _buildWordingOverride(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // --- Compound placeholder editor (#709) -----------------------------------

  /// Expanded editor for a compound placeholder: the move picker (to replace
  /// it), one editor per parameter the compound declares, offering only the
  /// values [allowedValues] admits, what it expands to, and the progression
  /// mark and note. A placeholder has no walkthrough or wording override.
  Widget _buildCompoundEditor(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final draft = widget.draft;
    final compound = draft.compound!;
    final resolve = widget.resolveCompound;
    final definition = resolve?.call(compound.id);
    final expanded = resolve == null
        ? null
        : expandPlaceholder(compound, resolve);
    final name = FigureRenderer(
      widget.taxonomy,
    ).renderFreeText(compound.name, widget.dialect);
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
              MoveAutocomplete(
                key: _key('move'),
                fieldKey: 'figure-${widget.index}-move',
                taxonomy: widget.taxonomy,
                dialect: widget.dialect,
                initialText: name,
                // A placeholder is never a container's child, so the
                // options would only discard it.
                includeModifier: false,
                includeCustomMove: widget.allowCustom,
                compoundOptions: _compoundPickerOptions(),
                compoundMarkerLabel: l10n.glossaryCustomMarker,
                onSelected: _onMoveOptionSelected,
                onCustomSubmitted: widget.allowCustom ? _submitUnmatched : null,
                submitsAsText: widget.allowCustom
                    ? widget.isShorthandToken
                    : null,
                onCleared: _clearMove,
                commitOnBlur: true,
              ),
              if (definition != null)
                for (final param in definition.params) ...[
                  const SizedBox(height: 8),
                  _buildCompoundArgument(definition, param),
                ],
              const SizedBox(height: 8),
              Text(
                expanded == null
                    ? l10n.danceEditorCompoundUnavailable
                    : l10n.danceEditorCompoundExpandsTo(
                        expanded.length,
                        CompoundDefinition.beatsOf(expanded, widget.taxonomy),
                      ),
                key: _key('compound-status'),
                style: expanded == null
                    ? theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      )
                    : theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              _buildProgressionToggle(context),
              const SizedBox(height: 8),
              _buildNote(context),
            ],
          ),
        ),
      ),
    );
  }

  /// The editor for one of a placeholder's arguments.
  Widget _buildCompoundArgument(
    CompoundDefinition definition,
    CompoundParam param,
  ) {
    final compound = widget.draft.compound!;
    return CompoundArgumentEditor(
      keyPrefix: 'figure-${widget.index}-compound',
      definition: definition,
      param: param,
      value: compound.args[param.key],
      dialect: widget.dialect,
      mixer: widget.mixer,
      taxonomy: widget.taxonomy,
      onChanged: (value) {
        compound.args[param.key] = value;
        _refreshCompoundBeats();
        widget.onChanged();
      },
    );
  }

  // --- Use of one of the user's own figures (#1023) -------------------------

  /// Expanded editor for a use of one of the user's own figures: the move
  /// picker (to replace it), one editor per parameter the figure declares,
  /// its beats, and the progression mark and note. Its line is the figure's
  /// wording, so it has no line of its own to edit, and no walkthrough or
  /// wording override.
  Widget _buildUserFigureEditor(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final draft = widget.draft;
    final view = UserFiguresScope.catalogOf(context)[userFigureIdOf(draft)!];
    final name = _userEntryRenderer.renderFreeText(
      view?.name ?? (draft.params['text'] as String?) ?? '',
      widget.dialect,
    );
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
              MoveAutocomplete(
                key: _key('move'),
                fieldKey: 'figure-${widget.index}-move',
                taxonomy: widget.taxonomy,
                dialect: widget.dialect,
                initialText: name,
                includeModifier: widget.allowModifierSelection,
                includeSequence: widget.allowModifierSelection,
                sequenceOptionLabel: AppLocalizations.of(
                  context,
                ).danceEditorSequenceOptionLabel,
                includeCustomMove: widget.allowCustom,
                compoundOptions: _compoundPickerOptions(),
                compoundMarkerLabel: l10n.glossaryCustomMarker,
                onSelected: _onMoveOptionSelected,
                onCustomSubmitted: widget.allowCustom ? _submitUnmatched : null,
                submitsAsText: widget.allowCustom
                    ? widget.isShorthandToken
                    : null,
                onCleared: _clearMove,
                commitOnBlur: true,
              ),
              const SizedBox(height: 12),
              UserFigureUseEditor(
                key: _key('user-figure-${draft.id}'),
                keyPrefix: 'figure-${widget.index}-userFigure',
                params: draft.params,
                dialect: widget.dialect,
                mixer: widget.mixer,
                onChanged: (next) {
                  if (next['beats'] != draft.params['beats']) {
                    draft.beatsTouched = true;
                  }
                  draft.params
                    ..clear()
                    ..addAll(next);
                  widget.onChanged();
                },
              ),
              const SizedBox(height: 12),
              _buildProgressionToggle(context),
              const SizedBox(height: 8),
              _buildNote(context),
            ],
          ),
        ),
      ),
    );
  }

  // --- Structural container editor (#590/#593/#1198) ------------------------

  /// Expanded editor for a structural container draft. A meanwhile or
  /// modifier shows one shared Beats field (the container's single count —
  /// never per-child); a sequence instead shows its total, the sum of its
  /// steps' own Beats fields, and a warning once that total is longer than a
  /// phrase of [_FigureDraftCard.phraseStructure]. Then come each ordered child
  /// editor, an add-child control (capped at the kind's
  /// [maxContainerChildren], and for a sequence hidden once a phrase is full),
  /// and per-child move/remove controls. Ordinary children use
  /// [_MeanwhileSideEditor]; a legal other-kind nested container is delegated
  /// to a nested [FigureListEditor].
  Widget _buildContainerEditor(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final draft = widget.draft;
    final kind = draft.containerKind!;
    final sides = draft.containerChildren!;
    final isModifier = kind == modifierMove;
    final isSequence = kind == sequenceMove;
    final keyPrefix = '${widget.keyPrefix}-${widget.index}';
    final cap = maxContainerChildren(kind);
    final beatLimit = widget.phraseStructure.longestPhraseBeats;
    final phraseFull = isSequence && draft.beats >= beatLimit;
    String childLabel(int i) => isModifier
        ? i == 0
              ? l10n.danceEditorModifierCoreLabel
              : l10n.danceEditorModifierChildLabel
        : isSequence
        ? l10n.danceEditorSequenceStepLabel(i + 1)
        : l10n.danceEditorMeanwhileSideLabel(i + 1);
    String childSemantic(int i) => isModifier
        ? i == 0
              ? l10n.danceEditorModifierCoreSemantic
              : l10n.danceEditorModifierChildSemantic(i + 1, sides.length)
        : isSequence
        ? l10n.danceEditorSequenceStepSemantic(i + 1, sides.length)
        : l10n.danceEditorMeanwhileSideSemantic(i + 1, sides.length);
    String removeTooltip(int i) => isModifier
        ? i == 0
              ? l10n.danceEditorRemoveModifierCore
              : l10n.danceEditorRemoveModifierChild
        : isSequence
        ? l10n.danceEditorRemoveSequenceStep
        : l10n.danceEditorRemoveMeanwhileSide;
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
          child: Semantics(
            container: true,
            label: switch (kind) {
              modifierMove => l10n.danceEditorModifierGroupSemantic(
                draft.beats,
                sides.length,
              ),
              sequenceMove => l10n.danceEditorSequenceGroupSemantic(
                sides.length,
                draft.beats,
              ),
              _ => l10n.danceEditorMeanwhileGroupSemantic(
                sides.length,
                draft.beats,
              ),
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isSequence
                          ? Icons.format_list_numbered
                          : Icons.call_split,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(switch (kind) {
                        modifierMove => l10n.danceEditorModifierGroupLabel(
                          sides.length,
                        ),
                        sequenceMove => l10n.danceEditorSequenceGroupLabel(
                          sides.length,
                        ),
                        _ => l10n.danceEditorMeanwhileGroupLabel(sides.length),
                      }, style: theme.textTheme.titleSmall),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (isSequence) ...[
                  // A sequence's count is its steps' counts added up: each
                  // step edits its own, so there is no field here to edit.
                  Text(
                    l10n.danceEditorSequenceTotalBeats(draft.beats),
                    key: ValueKey('$keyPrefix-sequence-beats'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (draft.beats > beatLimit)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        l10n.danceEditorSequenceOverPhrase(
                          draft.beats,
                          beatLimit,
                        ),
                        key: ValueKey('$keyPrefix-sequence-over-phrase'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                ] else
                  // The SINGLE shared beats field — this is the container's
                  // own `params['beats']`, not any side's. Sides never show
                  // their own beats field (see [_MeanwhileSideEditor]), so
                  // there is only ever one beats control visible for the whole
                  // group.
                  FigureParamEditor(
                    keyPrefix: '$keyPrefix-$kind',
                    paramKey: 'beats',
                    spec: const ParamSpec(ParamKind.beats, defaultValue: 0),
                    dialect: widget.dialect,
                    mixer: widget.mixer,
                    value: draft.beats,
                    onChanged: (v) {
                      draft.params['beats'] = v;
                      draft.beatsTouched = true;
                      widget.onChanged();
                    },
                  ),
                const SizedBox(height: 12),
                if (widget.showWordingOverride) _buildWordingOverride(context),
                for (var i = 0; i < sides.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: sides[i].isContainerDraft
                        ? Semantics(
                            container: true,
                            label: childSemantic(i),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        childLabel(i),
                                        style: theme.textTheme.labelLarge,
                                      ),
                                    ),
                                    IconButton(
                                      key: ValueKey(
                                        '$keyPrefix-nested-$i-move-up',
                                      ),
                                      tooltip: l10n.danceEditorMoveUp,
                                      icon: const Icon(
                                        Icons.arrow_upward,
                                        size: 18,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: i == 0
                                          ? null
                                          : () => _reorderSide(i, i - 1),
                                    ),
                                    IconButton(
                                      key: ValueKey(
                                        '$keyPrefix-nested-$i-move-down',
                                      ),
                                      tooltip: l10n.danceEditorMoveDown,
                                      icon: const Icon(
                                        Icons.arrow_downward,
                                        size: 18,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: i == sides.length - 1
                                          ? null
                                          : () => _reorderSide(i, i + 1),
                                    ),
                                    IconButton(
                                      key: ValueKey(
                                        '$keyPrefix-nested-$i-remove',
                                      ),
                                      tooltip: removeTooltip(i),
                                      icon: Icon(
                                        Icons.remove_circle_outline,
                                        size: 18,
                                        color: theme.colorScheme.error,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _removeSide(i),
                                    ),
                                  ],
                                ),
                                FigureListEditor(
                                  key: ValueKey(
                                    'nested-container-${sides[i].id}',
                                  ),
                                  drafts: [sides[i]],
                                  taxonomy: widget.taxonomy,
                                  // Labels and totals are hidden below, but a
                                  // nested sequence still fits one phrase of
                                  // this dance.
                                  phraseStructure: widget.phraseStructure,
                                  dialect: widget.dialect,
                                  mixer: widget.mixer,
                                  moveParamDefaults: widget.moveParamDefaults,
                                  showWordingOverride:
                                      widget.showWordingOverride,
                                  onChanged: _onSideChanged,
                                  onAdd: () {},
                                  onDelete: (_) => _removeSide(i),
                                  onCollapseMeanwhileGroup:
                                      (groupDraft, remainingSide) =>
                                          _collapseNestedContainer(
                                            sides,
                                            i,
                                            groupDraft,
                                            remainingSide,
                                          ),
                                  // A nested container must remain another
                                  // kind than its parent; converting it could
                                  // create invalid same-kind nesting. Ungroup
                                  // is the legal structural escape hatch for
                                  // this menu.
                                  onUngroupContainer:
                                      _canUngroupNestedContainer(sides, i)
                                      ? (nested) => _ungroupNestedContainer(
                                          sides,
                                          i,
                                          nested,
                                        )
                                      : null,
                                  allowNestedContainerSelection: false,
                                  allowAdding: false,
                                  allowDuplicating: false,
                                  showPhraseStructure: false,
                                  userFigureOptions: widget.userFigureOptions,
                                  keyPrefix: '$keyPrefix-nested-$i',
                                ),
                              ],
                            ),
                          )
                        : _MeanwhileSideEditor(
                            key: ValueKey('meanwhile-side-${sides[i].id}'),
                            keyPrefix: '$keyPrefix-side-$i',
                            sideNumber: i + 1,
                            totalSides: sides.length,
                            role: isModifier
                                ? i == 0
                                      ? _ChildRole.core
                                      : _ChildRole.modifier
                                : isSequence
                                ? _ChildRole.step
                                : null,
                            draft: sides[i],
                            taxonomy: widget.taxonomy,
                            dialect: widget.dialect,
                            mixer: widget.mixer,
                            moveParamDefaults: widget.moveParamDefaults,
                            showWordingOverride: widget.showWordingOverride,
                            userFigureOptions: widget.userFigureOptions,
                            onChanged: _onSideChanged,
                            includeModifier:
                                widget.allowModifierSelection &&
                                kind != modifierMove &&
                                widget.allowNestedContainerSelection,
                            includeSequence:
                                widget.allowModifierSelection &&
                                kind != sequenceMove &&
                                widget.allowNestedContainerSelection,
                            onMoveUp: i == 0
                                ? null
                                : () => _reorderSide(i, i - 1),
                            onMoveDown: i == sides.length - 1
                                ? null
                                : () => _reorderSide(i, i + 1),
                            onRemove: () => _removeSide(i),
                          ),
                  ),
                if (sides.length < cap && !phraseFull)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: ValueKey('$keyPrefix-add-side'),
                      onPressed: _addSide,
                      icon: const Icon(Icons.add),
                      label: Text(switch (kind) {
                        modifierMove => l10n.danceEditorAddModifierChild,
                        sequenceMove => l10n.danceEditorAddSequenceStep,
                        _ => l10n.danceEditorAddMeanwhileSide,
                      }),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      sides.length < cap
                          ? l10n.danceEditorSequencePhraseFull(beatLimit)
                          : switch (kind) {
                              modifierMove =>
                                l10n.danceEditorModifierChildrenCapReached(cap),
                              sequenceMove =>
                                l10n.danceEditorSequenceStepsCapReached(cap),
                              _ => l10n.danceEditorMeanwhileSidesCapReached(
                                cap,
                              ),
                            },
                      key: ValueKey('$keyPrefix-$kind-cap'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A side of this group changed: the group's shared count follows its
  /// sides until the caller types one (AUTH-11, [FigureDraft.syncContainerBeats]).
  void _onSideChanged() {
    widget.draft.syncContainerBeats();
    widget.onChanged();
  }

  /// Appends a fresh blank child, capped at the kind's [maxContainerChildren]
  /// and, for a sequence, refused once its steps fill a phrase — the add
  /// button is already hidden then, so this is a defensive no-op guard.
  void _addSide() {
    final draft = widget.draft;
    final sides = draft.containerChildren!;
    if (sides.length >= maxContainerChildren(draft.containerKind!)) return;
    if (draft.isSequenceGroup &&
        draft.beats >= widget.phraseStructure.longestPhraseBeats) {
      return;
    }
    sides.add(FigureDraft());
    widget.onChanged();
  }

  /// Removes side [index]. When exactly 2 sides remain, removing one would
  /// leave a single-side "group" — instead, the group **collapses** to a
  /// plain figure (acceptance criterion: removing down to one side degrades
  /// gracefully). Prefers [FigureListEditor.onCollapseMeanwhileGroup] when the
  /// host wired it (the dance editor does, so its undo/autosave pipeline runs
  /// via the controller's own `collapseMeanwhileGroup`); when it's `null` —
  /// [FigureListEditor] is reused by other screens (e.g. defaults/shorthand
  /// editors) that don't opt into that callback — falls back to converting
  /// `widget.draft` in place into the remaining side and calling
  /// `widget.onChanged()` directly, the same way every other in-row edit here
  /// (e.g. [_addSide], [_reorderSide]) updates state without a dedicated
  /// controller callback. Without this fallback the remove control would
  /// silently no-op on those hosts (#679 review).
  void _removeSide(int index) {
    final draft = widget.draft;
    final sides = draft.containerChildren!;
    if (index < 0 || index >= sides.length) return;
    if (sides.length <= 2) {
      final remaining = sides[index == 0 ? 1 : 0];
      final onCollapse = widget.onCollapseMeanwhileGroup;
      if (onCollapse != null) {
        onCollapse(draft, remaining);
        return;
      }
      draft
        ..move = remaining.move
        ..note = remaining.note
        ..progression = remaining.progression
        ..beatsTouched = remaining.beatsTouched
        ..assumedSubject = remaining.assumedSubject
        ..customOrigin = remaining.customOrigin
        ..walkthroughOverride = remaining.walkthroughOverride
        ..wordingOverride = remaining.wordingOverride
        ..setContainer(null, null);
      draft.params
        ..clear()
        ..addAll(remaining.params);
      widget.onChanged();
      return;
    }
    sides.removeAt(index);
    _onSideChanged();
  }

  /// Reorders a side within the group (up/down buttons only — sides don't get
  /// their own drag handle to avoid nesting a second reorderable region inside
  /// the outer [ReorderableListView]).
  void _reorderSide(int oldIndex, int newIndex) {
    final sides = widget.draft.containerChildren!;
    final side = sides.removeAt(oldIndex);
    sides.insert(newIndex, side);
    _onSideChanged();
  }

  /// Whether the nested container at [index] can be replaced by its own
  /// children: they must fit this container's child cap and, when this is a
  /// sequence, a phrase — a nested meanwhile's children count their own
  /// beats once they become steps.
  bool _canUngroupNestedContainer(List<FigureDraft> sides, int index) {
    if (index < 0 || index >= sides.length) return false;
    final nested = sides[index];
    if (!nested.isContainerDraft) return false;
    final children = nested.containerChildren;
    if (children == null ||
        children.length < 2 ||
        sides.length - 1 + children.length >
            maxContainerChildren(widget.draft.containerKind!)) {
      return false;
    }
    if (!widget.draft.isSequenceGroup) return true;
    final beats =
        widget.draft.beats -
        nested.beats +
        children.fold(0, (sum, child) => sum + child.beats);
    return beats <= widget.phraseStructure.longestPhraseBeats;
  }

  void _ungroupNestedContainer(
    List<FigureDraft> sides,
    int index,
    FigureDraft nested,
  ) {
    if (index < 0 ||
        index >= sides.length ||
        !identical(sides[index], nested) ||
        !_canUngroupNestedContainer(sides, index)) {
      return;
    }
    final children = List<FigureDraft>.of(nested.containerChildren!);
    sides
      ..removeAt(index)
      ..insertAll(index, children);
    _onSideChanged();
  }

  void _collapseNestedContainer(
    List<FigureDraft> sides,
    int index,
    FigureDraft groupDraft,
    FigureDraft remainingSide,
  ) {
    if (index < 0 ||
        index >= sides.length ||
        !identical(sides[index], groupDraft)) {
      return;
    }
    if (!remainingSide.canNestInContainer(widget.draft.containerKind!)) {
      return;
    }
    sides[index] = remainingSide;
    _onSideChanged();
  }

  /// Read-only editor panel for a figure whose move is unknown to the active
  /// taxonomy (issue #358). Shows best-effort text (the renderer's raw-id
  /// fallback) and a clear "unrecognized move" indicator explaining why it
  /// can't be edited here. The stored move + params are never mutated by this
  /// path; note and progression stay editable (they are not move params, so
  /// editing them can't corrupt the unknown schema).
  Widget _buildUnknownMoveEditor(BuildContext context, String move) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
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
                key: _key('unknown-move'),
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
                          l10n.danceEditorUnrecognizedMoveReadOnly(move),
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
              _buildProgressionToggle(context),
              const SizedBox(height: 8),
              _buildNote(context),
              _buildWalkthroughSnippet(context),
              if (widget.showWordingOverride) _buildWordingOverride(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParams(BuildContext context, MoveDef def) {
    final l10n = AppLocalizations.of(context);
    final draft = widget.draft;
    var entries = def.params.entries.toList();
    // issue #576: hey's `meetTarget` is meaningful only for the two partial
    // lengths — surface it in the editor ONLY when `length ∈ {lessThanHalf,
    // betweenHalfAndFull}`, so the field never appears for half/full heys (and
    // never for other moves, which lack the param). Filtering it out of the
    // entries here keeps the "first 3 inline" disclosure byte-identical to today
    // for non-partial heys.
    if (def.id == 'hey') {
      final length =
          draft.params['length'] ?? def.params['length']?.defaultValue;
      final showsMeetTarget =
          length == 'lessThanHalf' || length == 'betweenHalfAndFull';
      if (!showsMeetTarget) {
        entries = entries
            .where((e) => e.key != 'meetTarget')
            .toList(growable: false);
      }
    }
    // v30 (#989): a promenade's `where` gates two other params' relevance:
    // - `direction` (rotation sense) is meaningless once `where` leaves the
    //   across/along plane (`in`/`out`/`up`/`down`) — hidden here, and reset
    //   to the sentinel by core's `applyParamChange` the moment `where`
    //   changes to one of those, so the field can never go stale-but-hidden.
    // - `destination` renders nowhere once `where == 'across'` (the renderer's
    //   `where != 'across'` gate, matching Ask 2) — hidden here too, so the
    //   editor never offers a field the renderer will silently ignore (the
    // defect issue #989/F5 named). Unlike `direction`, its value is left alone
    //   rather than cleared: `across` is the taxonomy default, so a figure
    //   loaded with a stored destination and no stated `dir` must not lose
    //   that data on the mere act of opening the editor — only stop
    //   rendering it, exactly as Q3 specified.
    if (def.id == 'promenade') {
      final dir = draft.params['where'] ?? def.params['where']?.defaultValue;
      const rotationless = {'in', 'out', 'up', 'down'};
      final hideTurn = rotationless.contains(dir);
      final hideDestination = dir == 'across';
      if (hideTurn || hideDestination) {
        entries = entries
            .where(
              (e) =>
                  !((hideTurn && e.key == 'direction') ||
                      (hideDestination && e.key == 'destination')),
            )
            .toList(growable: false);
      }
    }
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
            mixer: widget.mixer,
            moveId: draft.move,
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
            key: _key('more-options'),
            onPressed: () =>
                setState(() => _showMoreOptions = !_showMoreOptions),
            icon: Icon(
              _showMoreOptions ? Icons.expand_less : Icons.expand_more,
              size: 18,
            ),
            label: Text(
              _showMoreOptions
                  ? l10n.danceEditorFewerOptions
                  : l10n.danceEditorMoreOptions(extra.length),
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

  Widget _buildProgressionToggle(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final draft = widget.draft;
    return Row(
      key: _key('progression-row'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: l10n.commonProgression,
          child: Switch(
            key: _key('progression'),
            value: draft.progression,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) {
              draft.progression = v;
              widget.onChanged();
            },
          ),
        ),
        const SizedBox(width: 8),
        Text(l10n.commonProgression, style: theme.textTheme.bodyMedium),
      ],
    );
  }

  Widget _buildNote(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = widget.draft;
    final showField = _showNote || draft.note.trim().isNotEmpty;
    if (!showField) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: _key('add-note'),
          onPressed: () => setState(() {
            _showNote = true;
            _justRevealedNote = true;
          }),
          icon: const Icon(Icons.note_add_outlined, size: 18),
          label: Text(l10n.danceEditorAddNote),
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
      key: _key('note-${draft.id}'),
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

  /// The on-demand per-figure **walkthrough snippet** field (#411). Shown only
  /// when the parent wired [widget.snippetLibraryDefaultFor] (a snippet-library
  /// scope is present) and a move is chosen. Seeded with the resolved snippet
  /// (override → library default); edits update the per-dance override live and
  /// the learn/divergence flow runs on blur via [widget.onSnippetCommitted].
  Widget _buildWalkthroughSnippet(BuildContext context) {
    if (widget.snippetLibraryDefaultFor == null || widget.draft.move == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final draft = widget.draft;
    final resolved = _resolvedSnippet();
    final showField = _showSnippet || resolved.trim().isNotEmpty;
    if (!showField) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: _key('add-walkthrough'),
          onPressed: () => setState(() {
            _showSnippet = true;
            _justRevealedSnippet = true;
          }),
          icon: const Icon(Icons.menu_book_outlined, size: 18),
          label: Text(l10n.danceEditorAddWalkthroughStep),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
      );
    }
    final autofocus = _justRevealedSnippet;
    if (_justRevealedSnippet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _justRevealedSnippet = false;
      });
    }
    return _SnippetField(
      key: _key('walkthrough-${draft.id}'),
      fieldKey: 'figure-${widget.index}-walkthrough',
      dialect: widget.dialect,
      taxonomy: widget.taxonomy,
      value: resolved,
      autofocus: autofocus,
      onChanged: (text) {
        draft.walkthroughOverride = text;
        widget.onChanged();
      },
      onCommit: () => widget.onSnippetCommitted?.call(draft),
    );
  }

  /// Per-dance display wording. Unlike the walkthrough snippet, this value
  /// never participates in the global snippet library and replaces the entire
  /// rendered line, so the preview uses the same renderer as the card summary.
  Widget _buildWordingOverride(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = widget.draft;
    if ((draft.move == null && !draft.isContainerDraft) ||
        draft.move == customMove) {
      return const SizedBox.shrink();
    }
    final value = draft.wordingOverride ?? '';
    final showField = _showWordingOverride || value.trim().isNotEmpty;
    if (!showField) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: _key('add-wording-override'),
          onPressed: () => setState(() => _showWordingOverride = true),
          icon: const Icon(Icons.edit_note, size: 18),
          label: Text(l10n.danceEditorAddWordingOverride),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
      );
    }
    final figure = draft.toFigure();
    final preview = figure == null
        ? ''
        : FigureRenderer(widget.taxonomy).render(figure, widget.dialect);
    return _WordingOverrideField(
      key: _key('wording-override-${draft.id}'),
      fieldKey: 'figure-${widget.index}-wording-override',
      value: value,
      preview: preview,
      onChanged: (text) {
        draft.wordingOverride = text;
        widget.onChanged();
      },
      onCommit: () {
        final trimmed = draft.wordingOverride?.trim();
        final normalized = trimmed == null || trimmed.isEmpty ? null : trimmed;
        if (draft.wordingOverride == normalized) return;
        draft.wordingOverride = normalized;
        widget.onChanged();
      },
      onClear: () {
        draft.wordingOverride = null;
        setState(() => _showWordingOverride = false);
        widget.onChanged();
      },
    );
  }
}

void _rerouteInversePair(FigureDraft draft, Taxonomy taxonomy) {
  final move = draft.move;
  if (move == null) return;
  final resolved = taxonomy.resolvedMoveId(
    Figure(move: move, params: draft.params),
  );
  if (resolved != move) draft.move = resolved;
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

// ---------------------------------------------------------------------------
// _MeanwhileSideEditor (#590/#593)
// ---------------------------------------------------------------------------

/// A child's place in its container, for its label and semantics: a
/// modifier's core or one of its modifiers, or a sequence's step. Null for a
/// meanwhile side.
enum _ChildRole { core, modifier, step }

/// Editor for ONE ordinary child of a structural container: a move-picker +
/// param editors + note, reusing the same widgets [_FigureDraftCard] uses for
/// a top-level figure, but with its own key namespace (so a container's
/// children never collide with the outer row's keys). It has NO "group"
/// affordances of its own — nested containers are rendered by a nested
/// [FigureListEditor]. A meanwhile side's or modifier child's `beats` is
/// display-only, because the parent container's shared beats field is
/// authoritative, so it is not shown; a sequence step's is its share of the
/// sequence's total, so it is ([_ChildRole.step]).
class _MeanwhileSideEditor extends StatefulWidget {
  const _MeanwhileSideEditor({
    super.key,
    required this.keyPrefix,
    required this.sideNumber,
    required this.totalSides,
    this.role,
    required this.draft,
    required this.taxonomy,
    required this.dialect,
    this.mixer = false,
    this.moveParamDefaults,
    this.showWordingOverride = false,
    this.includeModifier = false,
    this.includeSequence = false,
    this.userFigureOptions,
    required this.onChanged,
    this.onMoveUp,
    this.onMoveDown,
    required this.onRemove,
  });

  /// Stem for this side's widget keys (e.g. `figure-2-side-0`).
  final String keyPrefix;

  /// 1-based position among the group's sides (for labels/semantics).
  final int sideNumber;
  final int totalSides;
  final _ChildRole? role;
  final FigureDraft draft;
  final Taxonomy taxonomy;
  final Dialect dialect;

  /// See [FigureListEditor.mixer].
  final bool mixer;

  final Map<String, Map<String, Object?>>? moveParamDefaults;
  final bool showWordingOverride;
  final bool includeModifier;
  final bool includeSequence;

  /// See [FigureListEditor.userFigureOptions].
  final List<UserGlossaryEntry>? userFigureOptions;

  final VoidCallback onChanged;

  /// Null when this side is already first/last within the group.
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onRemove;

  @override
  State<_MeanwhileSideEditor> createState() => _MeanwhileSideEditorState();
}

class _MeanwhileSideEditorState extends State<_MeanwhileSideEditor> {
  bool _showNote = false;
  bool _showWordingOverride = false;

  @override
  void initState() {
    super.initState();
    _showNote = widget.draft.note.trim().isNotEmpty;
    _showWordingOverride =
        widget.draft.wordingOverride?.trim().isNotEmpty ?? false;
  }

  void _selectMove(String moveId) {
    final draft = widget.draft;
    if (draft.move == moveId) return;
    draft.move = moveId;
    draft.params
      ..clear()
      ..addAll(widget.taxonomy.entryParams(moveId));
    draft.assumedSubject = false;
    draft.customOrigin = CustomOrigin.userEntered;
    draft.wordingOverride = null;
    draft.beatsTouched = false;
    // #976: apply a saved per-move default FIRST — it may itself override
    // `who` (defaults are sparse per-param diffs, `display_defaults.dart`),
    // and seeding hand from the PRE-override `who` would then store a hand
    // for a role the default just replaced. Seed the role-implied hand
    // afterward, from the now-final `who` — unless the saved default itself
    // named an explicit `hand`, which must win.
    _applyMoveParamDefaults(moveId);
    final chainOverrides = widget.moveParamDefaults?[moveId];
    if (chainOverrides == null || !chainOverrides.containsKey('hand')) {
      seedChainHand(moveId, draft.params);
    }
    widget.onChanged();
  }

  void _selectContainer(String kind) {
    _initializeContainer(widget.draft, kind);
    widget.onChanged();
  }

  void _selectUserFigure(String entryId) {
    if (selectUserFigure(widget.draft, entryId, widget.userFigureOptions)) {
      widget.onChanged();
    }
  }

  void _createCustom(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final draft = widget.draft;
    draft.move = customMove;
    draft.params
      ..clear()
      ..addAll(widget.taxonomy.effectiveParams(Figure(move: customMove)));
    draft.beatsTouched = false;
    draft.assumedSubject = false;
    draft.customOrigin = CustomOrigin.userEntered;
    draft.wordingOverride = null;
    _applyMoveParamDefaults(customMove);
    draft.params['text'] = trimmed;
    widget.onChanged();
  }

  void _applyMoveParamDefaults(String moveId) {
    final overrides = widget.moveParamDefaults?[moveId];
    if (overrides == null || overrides.isEmpty) return;
    final schema = widget.taxonomy.resolve(moveId)?.params;
    if (schema == null) return;
    final draft = widget.draft;
    for (final entry in overrides.entries) {
      if (schema.containsKey(entry.key)) {
        draft.params[entry.key] = entry.value;
        if (entry.key == 'beats') draft.beatsTouched = true;
      }
    }
  }

  void _clearMove() {
    final draft = widget.draft;
    if (draft.move == null) return;
    draft.move = null;
    draft.params.clear();
    draft.beatsTouched = false;
    draft.wordingOverride = null;
    widget.onChanged();
  }

  Widget _buildSideWordingOverride(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = widget.draft;
    if (draft.move == null || draft.move == customMove) {
      return const SizedBox.shrink();
    }
    final value = draft.wordingOverride ?? '';
    if (!_showWordingOverride && value.trim().isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: ValueKey('${widget.keyPrefix}-add-wording-override'),
          onPressed: () => setState(() => _showWordingOverride = true),
          icon: const Icon(Icons.edit_note, size: 18),
          label: Text(l10n.danceEditorAddWordingOverride),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
      );
    }
    final figure = draft.toFigure();
    final preview = figure == null
        ? ''
        : FigureRenderer(widget.taxonomy).render(figure, widget.dialect);
    return _WordingOverrideField(
      key: ValueKey('${widget.keyPrefix}-wording-override-${draft.id}'),
      fieldKey: '${widget.keyPrefix}-wording-override',
      value: value,
      preview: preview,
      onChanged: (text) {
        draft.wordingOverride = text;
        widget.onChanged();
      },
      onCommit: () {
        final trimmed = draft.wordingOverride?.trim();
        final normalized = trimmed == null || trimmed.isEmpty ? null : trimmed;
        if (draft.wordingOverride == normalized) return;
        draft.wordingOverride = normalized;
        widget.onChanged();
      },
      onClear: () {
        draft.wordingOverride = null;
        setState(() => _showWordingOverride = false);
        widget.onChanged();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final draft = widget.draft;
    final move = draft.move;
    final def = move == null ? null : widget.taxonomy.resolve(move);
    final userFigureId = userFigureIdOf(draft);
    final userFigure = userFigureId == null
        ? null
        : UserFiguresScope.catalogOf(context)[userFigureId];
    final moveText = move == null
        ? ''
        : userFigureId != null
        ? _userEntryRenderer.renderFreeText(
            userFigure?.name ?? (draft.params['text'] as String?) ?? '',
            widget.dialect,
          )
        : FigureRenderer(
            widget.taxonomy,
          ).displayMoveName(move, widget.dialect, params: draft.params);

    return Semantics(
      container: true,
      label: switch (widget.role) {
        _ChildRole.core => l10n.danceEditorModifierCoreSemantic,
        _ChildRole.modifier => l10n.danceEditorModifierChildSemantic(
          widget.sideNumber,
          widget.totalSides,
        ),
        _ChildRole.step => l10n.danceEditorSequenceStepSemantic(
          widget.sideNumber,
          widget.totalSides,
        ),
        null => l10n.danceEditorMeanwhileSideSemantic(
          widget.sideNumber,
          widget.totalSides,
        ),
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(switch (widget.role) {
                    _ChildRole.core => l10n.danceEditorModifierCoreLabel,
                    _ChildRole.modifier => l10n.danceEditorModifierChildLabel,
                    _ChildRole.step => l10n.danceEditorSequenceStepLabel(
                      widget.sideNumber,
                    ),
                    null => l10n.danceEditorMeanwhileSideLabel(
                      widget.sideNumber,
                    ),
                  }, style: theme.textTheme.labelLarge),
                ),
                IconButton(
                  key: ValueKey('${widget.keyPrefix}-move-up'),
                  tooltip: l10n.danceEditorMoveUp,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onMoveUp,
                ),
                IconButton(
                  key: ValueKey('${widget.keyPrefix}-move-down'),
                  tooltip: l10n.danceEditorMoveDown,
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onMoveDown,
                ),
                IconButton(
                  key: ValueKey('${widget.keyPrefix}-remove'),
                  tooltip: switch (widget.role) {
                    _ChildRole.core => l10n.danceEditorRemoveModifierCore,
                    _ChildRole.modifier => l10n.danceEditorRemoveModifierChild,
                    _ChildRole.step => l10n.danceEditorRemoveSequenceStep,
                    null => l10n.danceEditorRemoveMeanwhileSide,
                  },
                  icon: Icon(
                    Icons.remove_circle_outline,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            MoveAutocomplete(
              key: ValueKey('${widget.keyPrefix}-move'),
              fieldKey: '${widget.keyPrefix}-move',
              taxonomy: widget.taxonomy,
              dialect: widget.dialect,
              initialText: moveText,
              autofocus: false,
              includeModifier: widget.includeModifier,
              includeSequence: widget.includeSequence,
              sequenceOptionLabel: l10n.danceEditorSequenceOptionLabel,
              compoundOptions: _userEntryPickerOptions(
                widget.userFigureOptions,
                MoveOptionKind.userFigure,
                widget.dialect,
              ),
              compoundMarkerLabel: l10n.glossaryCustomMarker,
              onSelected: (option) => switch (option.kind) {
                MoveOptionKind.modifier => _selectContainer(modifierMove),
                MoveOptionKind.sequence => _selectContainer(sequenceMove),
                MoveOptionKind.userFigure => _selectUserFigure(option.id),
                _ => _selectMove(option.id),
              },
              onCustomSubmitted: _createCustom,
              onCleared: _clearMove,
              commitOnBlur: true,
            ),
            if (def != null) ...[
              const SizedBox(height: 8),
              if (userFigureId != null)
                // A meanwhile or modifier owns the beats, as for any side; a
                // sequence's step keeps its own.
                UserFigureUseEditor(
                  key: ValueKey('${widget.keyPrefix}-user-figure-${draft.id}'),
                  keyPrefix: '${widget.keyPrefix}-userFigure',
                  params: draft.params,
                  dialect: widget.dialect,
                  mixer: widget.mixer,
                  showBeats: widget.role == _ChildRole.step,
                  onChanged: (next) {
                    draft.params
                      ..clear()
                      ..addAll(next);
                    widget.onChanged();
                  },
                )
              else if (draft.move == customMove)
                _LingoCustomTextField(
                  key: ValueKey('${widget.keyPrefix}-text-${draft.id}'),
                  fieldKey: '${widget.keyPrefix}-text',
                  dialect: widget.dialect,
                  taxonomy: widget.taxonomy,
                  value: (draft.params['text'] as String?) ?? '',
                  onChanged: (v) {
                    draft.params['text'] = v;
                    // Authored, as for a row's own text: see above.
                    draft.customOrigin = CustomOrigin.userEntered;
                    widget.onChanged();
                  },
                )
              else if (def.params.isNotEmpty)
                _buildSideParams(context, def),
              const SizedBox(height: 8),
              _buildSideNote(context),
              if (widget.showWordingOverride)
                _buildSideWordingOverride(context),
            ],
          ],
        ),
      ),
    );
  }

  /// Same param editors as a top-level figure, EXCEPT `beats` for a meanwhile
  /// side or modifier child — its own beats is display-only (the group's
  /// shared count is authoritative), so showing an editable-but-ignored field
  /// here would be a confusing dead control. Hidden rather than disabled. A
  /// sequence step shows `beats`, which counts toward the sequence's total,
  /// and its other edits reconcile beats as a top-level figure's do.
  Widget _buildSideParams(BuildContext context, MoveDef def) {
    final draft = widget.draft;
    final isStep = widget.role == _ChildRole.step;
    final entries = def.params.entries
        .where((e) => isStep || e.key != 'beats')
        .toList(growable: false);
    if (entries.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final entry in entries)
          FigureParamEditor(
            keyPrefix: widget.keyPrefix,
            paramKey: entry.key,
            spec: entry.value,
            dialect: widget.dialect,
            mixer: widget.mixer,
            moveId: draft.move,
            value: draft.params[entry.key] ?? entry.value.defaultValue,
            onChanged: (v) {
              if (entry.key == 'who') draft.assumedSubject = false;
              if (isStep) {
                if (entry.key == 'beats') {
                  draft.params['beats'] = v;
                  draft.beatsTouched = true;
                } else {
                  draft.move = applyParamChange(
                    widget.taxonomy,
                    move: draft.move!,
                    params: draft.params,
                    key: entry.key,
                    value: v,
                    beatsTouched: draft.beatsTouched,
                    aggressiveBeats:
                        draft.beatsTouched &&
                        AggressiveBeatsUpdateScope.of(context),
                  );
                }
                widget.onChanged();
                return;
              }
              draft.params[entry.key] = v;
              // #976: a `who` edit on a chain rewrites its role-implied
              // hand, mirroring ContraDB's `chainChange` (figure.js:256-263)
              // — an explicit hand set for the OLD role must not silently
              // survive onto the new one.
              if (draft.move == 'chain' && entry.key == 'who') {
                seedChainHand('chain', draft.params);
              }
              _rerouteInversePair(draft, widget.taxonomy);
              widget.onChanged();
            },
          ),
      ],
    );
  }

  Widget _buildSideNote(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = widget.draft;
    final showField = _showNote || draft.note.trim().isNotEmpty;
    if (!showField) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: ValueKey('${widget.keyPrefix}-add-note'),
          onPressed: () => setState(() => _showNote = true),
          icon: const Icon(Icons.note_add_outlined, size: 18),
          label: Text(l10n.danceEditorAddNote),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
      );
    }
    return _NoteField(
      key: ValueKey('${widget.keyPrefix}-note-${draft.id}'),
      fieldKey: '${widget.keyPrefix}-note',
      dialect: widget.dialect,
      taxonomy: widget.taxonomy,
      value: draft.note,
      onChanged: (text) {
        draft.note = text;
        widget.onChanged();
      },
    );
  }
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
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: ValueKey('$fieldKey-bold'),
          onPressed: () => _apply('*'),
          icon: const Icon(Icons.format_bold, size: 18),
          tooltip: l10n.danceEditorBoldTooltip,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
        ),
        IconButton(
          key: ValueKey('$fieldKey-underline'),
          onPressed: () => _apply('_'),
          icon: const Icon(Icons.format_underlined, size: 18),
          tooltip: l10n.danceEditorUnderlineTooltip,
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
    final l10n = AppLocalizations.of(context);
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
            labelText: l10n.danceEditorCustomFigureTextLabel,
            isDense: true,
            border: const OutlineInputBorder(),
            helperText: hint == null
                ? l10n.danceEditorLingoStylingHelper
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
                  Icons.warning_amber_outlined,
                  size: 13,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Semantics(
                    label: l10n.danceEditorDiscouragedTermSemantic(hint),
                    child: Text(
                      l10n.danceEditorDiscouragedTermText(hint),
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
    final l10n = AppLocalizations.of(context);
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
          decoration: InputDecoration(
            labelText: l10n.danceEditorNoteOptionalLabel,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: widget.onChanged,
        ),
      ],
    );
  }
}

/// A per-figure **walkthrough snippet** field (#411). Mirrors [_NoteField]'s
/// lingo-aware editing, but commits on blur (loses focus) so the parent can run
/// the learn-on-first-entry / divergence-prompt flow once, when the user is done
/// editing — not on every keystroke. Live keystrokes still flow through
/// [onChanged] so the per-dance override and autosave/undo stay in sync.
class _SnippetField extends StatefulWidget {
  const _SnippetField({
    super.key,
    required this.fieldKey,
    required this.dialect,
    required this.taxonomy,
    required this.value,
    required this.onChanged,
    required this.onCommit,
    this.autofocus = false,
  });

  final String fieldKey;
  final Dialect dialect;
  final Taxonomy taxonomy;
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onCommit;
  final bool autofocus;

  @override
  State<_SnippetField> createState() => _SnippetFieldState();
}

class _SnippetFieldState extends State<_SnippetField> {
  late final LingoTextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = LingoTextEditingController(
      text: widget.value,
      dialect: widget.dialect,
      taxonomy: widget.taxonomy,
    );
    _focusNode = FocusNode(debugLabel: widget.fieldKey);
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    // Commit once, when focus LEAVES the field — the point at which a snippet
    // edit is "done" and the learn/divergence flow should run.
    if (!_focusNode.hasFocus) widget.onCommit();
  }

  @override
  void didUpdateWidget(_SnippetField old) {
    super.didUpdateWidget(old);
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
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          minLines: 1,
          maxLines: 4,
          maxLength: kMaxWalkthroughSnippetLength,
          decoration: InputDecoration(
            labelText: l10n.danceEditorWalkthroughStepLabel,
            helperText: l10n.danceEditorWalkthroughStepHelper,
            helperMaxLines: 2,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: widget.onChanged,
        ),
      ],
    );
  }
}

/// A display-only wording override for one figure occurrence. Text is stored
/// live for autosave/undo, while [onCommit] normalizes it when focus leaves.
class _WordingOverrideField extends StatefulWidget {
  const _WordingOverrideField({
    super.key,
    required this.fieldKey,
    required this.value,
    required this.preview,
    required this.onChanged,
    required this.onCommit,
    required this.onClear,
  });

  final String fieldKey;
  final String value;
  final String preview;
  final ValueChanged<String> onChanged;
  final VoidCallback onCommit;
  final VoidCallback onClear;

  @override
  State<_WordingOverrideField> createState() => _WordingOverrideFieldState();
}

class _WordingOverrideFieldState extends State<_WordingOverrideField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode(debugLabel: widget.fieldKey)
      ..addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) widget.onCommit();
  }

  @override
  void didUpdateWidget(_WordingOverrideField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: ValueKey(widget.fieldKey),
          controller: _controller,
          focusNode: _focusNode,
          minLines: 1,
          maxLines: 4,
          maxLength: kMaxWalkthroughSnippetLength,
          decoration: InputDecoration(
            labelText: l10n.danceEditorWordingOverrideLabel,
            helperText: l10n.danceEditorWordingOverrideHelper,
            helperMaxLines: 3,
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              key: ValueKey('${widget.fieldKey}-clear'),
              tooltip: l10n.danceEditorResetWordingOverride,
              icon: const Icon(Icons.restart_alt),
              onPressed: widget.onClear,
            ),
          ),
          onChanged: widget.onChanged,
        ),
        if (widget.preview.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.danceEditorWordingOverridePreview(widget.preview),
              key: ValueKey('${widget.fieldKey}-preview'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _BeatSummary extends StatelessWidget {
  const _BeatSummary({
    required this.totalBeats,
    required this.expectedBeats,
    this.keyPrefix = 'figure',
  });

  final int totalBeats;
  final int expectedBeats;
  final String keyPrefix;

  ValueKey<String> _key(String suffix) => ValueKey('$keyPrefix-$suffix');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final mismatch = totalBeats != expectedBeats;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.danceEditorBeatTotal(totalBeats, expectedBeats),
            key: _key('beats-total'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (mismatch)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                key: _key('beats-warning'),
                children: [
                  Icon(
                    Icons.warning_amber_outlined,
                    size: 16,
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    totalBeats > expectedBeats
                        ? l10n.danceEditorOverByBeats(
                            totalBeats - expectedBeats,
                          )
                        : l10n.danceEditorUnderByBeats(
                            expectedBeats - totalBeats,
                          ),
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

final FigureRenderer _userEntryRenderer = FigureRenderer(contraTaxonomy);

/// The user's [entries] (compounds or new figures, by [kind]) as move-picker
/// options, named and found by their keywords in [dialect].
List<MoveOption> _userEntryPickerOptions(
  List<UserGlossaryEntry>? entries,
  MoveOptionKind kind,
  Dialect dialect,
) => [
  for (final entry in entries ?? const <UserGlossaryEntry>[])
    MoveOption(
      id: entry.id,
      displayName: _userEntryRenderer.renderFreeText(entry.name, dialect),
      kind: kind,
      searchTerms: [
        for (final k in entry.keywords)
          _userEntryRenderer.renderFreeText(k, dialect),
      ],
    ),
];
