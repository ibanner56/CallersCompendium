import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../search/collection_data.dart';
import '../search/facet_labels.dart' show danceLevelLabel;
import '../theme/app_motion.dart';
import '../../l10n/app_localizations.dart';
import '../data/canonical_discouraged_terms_scope.dart';
import '../data/collection_facets_scope.dart';
import '../data/repositories_scope.dart';
import '../data/settings_keys.dart' show kPerformSwapDefaultsKey;
import '../theme/app_spacing.dart';
import '../utils/slot_dance_title.dart';
import '../widgets/collection_picker.dart';
import '../widgets/picker_suggestions.dart';
import 'perform_swap_sheet.dart';

/// The non-destructive in-event "adjust" sheet for Performance mode
/// (`docs/design/ux.md` §5: "reorder remaining slots, insert from quick-search,
/// add ad-hoc note, swap the current or an upcoming dance — all in an
/// 'adjust' sheet, never disturbing the reading view"). Also lets the caller mark the current slot performed
/// (`ProgramSlot.performedAt`), and swap the dance being called or an upcoming
/// one for another (**Swap**, #2346): never a dance already called, that is a
/// slot before the current one or one marked performed.
///
/// Edits a private working copy of the [Program] and returns it via
/// [Navigator.pop] when the caller taps **Done** (or `null` when nothing
/// changed). Every edit is also reported through [onEdited] as it happens, so
/// a sheet closed any other way — swipe down, barrier tap, system back — still
/// hands its edits to the caller instead of silently discarding them.
/// [PerformProgramScreen] then applies the result live with a
/// single SnackBar undo and persists it — so the reading view underneath is
/// never disturbed while adjusting.
class PerformAdjustSheet extends StatefulWidget {
  const PerformAdjustSheet({
    super.key,
    required this.program,
    required this.currentGroupIndex,
    required this.currentSlotId,
    required this.data,
    required this.dialect,
    required this.enrichment,
    this.dialectForForm,
    this.danceOverrides = const {},
    this.authorNameOverrides = const {},
    this.onEdited,
    this.rankSuggestions,
    this.noteDraft = '',
    this.onNoteDraftChanged,
  });

  final Program program;

  /// Called after every edit with the working copy, or with `null` once the
  /// edits have cancelled out (a mark cleared again, a slot moved back). The
  /// opener keeps the latest value and applies it when the sheet closes
  /// without a result (swipe-down, barrier tap, back), so **Done** is not the
  /// only way to keep the edits.
  final ValueChanged<Program?>? onEdited;

  /// The group the reading view is on. The current group and everything after
  /// it are reorderable; already-passed groups stay fixed.
  final int currentGroupIndex;

  /// Id of the slot currently on screen — the mark-performed target and the
  /// anchor that new inserts land right after.
  final String currentSlotId;

  final CollectionData data;

  /// Fresh dance records the source [PerformProgramScreen] has loaded while the
  /// debounced collection snapshot is catching up.
  final Map<String, Dance> danceOverrides;

  /// Fresh author names paired with [danceOverrides].
  final Map<String, String> authorNameOverrides;

  /// Active dialect for the quick-search picker's canonicalization.
  final Dialect dialect;

  /// The dialect a dance of a given form is shown in, for the swap sheet of a
  /// dance whose form differs from the one on screen. Null uses [dialect].
  final Dialect Function(DanceForm form)? dialectForForm;

  /// Always-on search enrichment (union of every saved dialect) for the
  /// quick-search picker, so its search resolves saved-dialect vocabulary
  /// regardless of the active dialect — parity with the main Collection search.
  /// Built by the parent so it crosses the modal bottom sheet's navigator
  /// boundary reliably (mirrors [dialect]).
  final SearchEnrichment enrichment;

  /// An ad-hoc note typed in an earlier opening of this sheet and not added:
  /// the note field starts with it.
  final String noteDraft;

  /// Called with the note field's text whenever it changes, and with `''`
  /// once the note is added. The opener keeps the latest value and passes it
  /// back as [noteDraft] the next time it opens the sheet, so a note typed and
  /// not yet added survives the sheet closing however it closes, without a
  /// prompt (the maintainer's answer to question 43 of the pre-release audit's
  /// decision sheet, 2026-11-27: nothing asks during a performance).
  final ValueChanged<String>? onNoteDraftChanged;

  /// Ranks the swap sheet's results when they are ordered by suggestions
  /// (#2348): [CollectionPicker.rankSuggestions], a test seam. Null, as in
  /// the app, ranks on the picker's own worker.
  final SuggestionRanker? rankSuggestions;

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

  late final _noteController = TextEditingController(text: widget.noteDraft)
    ..addListener(_reportNoteDraft);

  /// The note field's text as last reported, so a selection-only change to the
  /// controller reports nothing.
  late String _reportedNoteDraft = widget.noteDraft;

  void _reportNoteDraft() {
    final text = _noteController.text;
    if (text == _reportedNoteDraft) return;
    _reportedNoteDraft = text;
    widget.onNoteDraftChanged?.call(text);
  }

  /// Records whether [_working] now differs from the program the sheet opened
  /// with, and reports it to [PerformAdjustSheet.onEdited]. Called inside each
  /// edit's `setState`, after [_working] is assigned. Edits that cancel out
  /// leave nothing to apply, so closing the sheet after them changes nothing.
  void _markChanged() {
    _changed = !listEquals(_working.slots, widget.program.slots);
    widget.onEdited?.call(_changed ? _working : null);
  }

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

  String _label(AppLocalizations l10n, ProgramSlot slot) {
    if (slot.danceId != null) {
      final dance =
          widget.danceOverrides[slot.danceId] ??
          widget.data.dancesById[slot.danceId];
      if (dance != null) return slotDanceTitle(l10n, dance);
    }
    if (slot.isBreak) return l10n.programsBreakSlotLabel;
    final rawText = slot.text?.trim();
    final text =
        rawText == null ||
            (slot.danceId == null && slot.isPurgedDance != false) ||
            !CanonicalDiscouragedTermsScope.of(context)
        ? rawText
        : FigureRenderer(
            shippedTaxonomies.anyForm,
          ).renderFreeTextWithCanonicalDiscouragedTerms(
            rawText,
            widget.dialect,
          );
    if (text != null && text.isNotEmpty) return text;
    return l10n.performUntitledSlot;
  }

  void _announce(String message) {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.maybeOf(context) ?? TextDirection.ltr,
    );
  }

  // --- Edits ----------------------------------------------------------------

  void _toggleCurrentPerformed() {
    final now = nextStoredTimestamp(
      now: DateTime.now().toUtc(),
      current: _working.slots.map((s) => s.performedAt),
    );
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
      _markChanged();
    });
    final nowPerformed = edited?.performedAt != null;
    final l10n = AppLocalizations.of(context);
    _announce(
      nowPerformed
          ? l10n.performMarkedPerformedAnnounce(_label(l10n, edited!))
          : l10n.performClearedPerformedAnnounce,
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
      _markChanged();
    });
    final l10n = AppLocalizations.of(context);
    _announce(
      l10n.performMovedToPosition(
        _label(l10n, item.primary),
        start + toMovableIndex + 1,
      ),
    );
  }

  void _onReorder(int oldIndex, int newIndex) => _moveGroup(oldIndex, newIndex);

  void _insertDance(String danceId) {
    final l10n = AppLocalizations.of(context);
    final flat = [..._flatten(_working.grouped)];
    final at = _afterCurrentFlatIndex();
    flat.insert(at, ProgramSlot(id: uuidV4(), position: at, danceId: danceId));
    setState(() {
      _working = _withSlots(flat);
      _markChanged();
    });
    final title =
        (widget.danceOverrides[danceId] ?? widget.data.dancesById[danceId])
            ?.title ??
        l10n.performDanceFallback;
    _announce(l10n.performInsertedAnnounce(title));
  }

  Dance? _danceFor(String? id) => id == null
      ? null
      : widget.danceOverrides[id] ?? widget.data.dancesById[id];

  /// Whether [slot] may be swapped (#2346): a dance not marked performed
  /// and, for an alternate, one whose group's primary is not marked
  /// performed either: that dance has been called, so a swap that demotes it
  /// would rewrite what happened. Callers also keep Swap off slots before
  /// the current one.
  bool _swappable(ProgramSlot slot) {
    if (slot.danceId == null || slot.performedAt != null) return false;
    if (!slot.isAlt) return true;
    final slots = [..._flatten(_working.grouped)];
    final index = slots.indexWhere((s) => s.id == slot.id);
    if (index < 0) return false;
    final front = slots[Program.alternateGroupRange(slots, index).start];
    return front.id == slot.id || front.performedAt == null;
  }

  /// Swaps the dance of slot [slotId] for [danceId], keeping the old dance as
  /// an alternate ([Program.swapSlotDanceKeepingAlternate]).
  void _swapDance(String slotId, String danceId) {
    final flat = [..._flatten(_working.grouped)];
    final index = flat.indexWhere((s) => s.id == slotId);
    if (index < 0) return;
    setState(() {
      _working = _withSlots(
        Program.swapSlotDanceKeepingAlternate(
          flat,
          index,
          danceId: danceId,
          alternateId: uuidV4(),
        ),
      );
      _markChanged();
    });
    final l10n = AppLocalizations.of(context);
    _announce(
      l10n.performSwappedAnnounce(
        _danceFor(danceId)?.title ?? l10n.performDanceFallback,
      ),
    );
  }

  /// Opens the swap sheet for slot [slotId] (#2346), seeded from its dance,
  /// with the Keep items Settings ▸ Program ▸ Perform mode ▸ Swap a dance
  /// starts on.
  Future<void> _openSwap(String slotId) async {
    // The settings read leaves the Swap buttons live for a moment: a second
    // tap then must not open a second sheet.
    if (_swapOpen) return;
    _swapOpen = true;
    try {
      await _showSwap(slotId);
    } finally {
      _swapOpen = false;
    }
  }

  /// Whether a swap sheet is opening or open.
  bool _swapOpen = false;

  Future<void> _showSwap(String slotId) async {
    final repos = RepositoriesScope.of(context);
    var defaults = PerformSwapDefaults.defaults;
    try {
      defaults = readPerformSwapDefaults(
        await repos.settings.get(kPerformSwapDefaultsKey),
      ).defaults;
    } catch (_) {
      // diagnostics: silent — a failed read opens with every Keep item on,
      // the shipped defaults; the swap itself does not depend on it.
    }
    if (!mounted) return;
    final group = _working.grouped.firstWhere(
      (g) => [g.primary, ...g.alternates].any((s) => s.id == slotId),
    );
    final members = [group.primary, ...group.alternates];
    final slot = members.firstWhere((s) => s.id == slotId);
    final dance = _danceFor(slot.danceId);
    final programDanceIds = {for (final s in _working.slots) ?s.danceId};
    final forms = {for (final id in programDanceIds) ?_danceFor(id)?.form};
    final levelId = dance?.difficultyLevelId;
    final level = levelId == null
        ? null
        : widget.data.levels.where((l) => l.id == levelId).firstOrNull;
    final l10n = AppLocalizations.of(context);
    final program = _working;
    final flatIndex = program.slots.indexWhere((s) => s.id == slotId);
    final title = _label(l10n, slot);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.of(sheetContext).size.height * 0.9;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: PerformSwapSheet(
              key: const ValueKey('adjust-swap-sheet'),
              title: title,
              data: widget.data,
              // The swapped dance's own form's dialect: its Keep chips name
              // its moves, and the query asks for them.
              dialect: dance == null
                  ? widget.dialect
                  : widget.dialectForForm?.call(dance.form) ?? widget.dialect,
              enrichment: widget.enrichment,
              danceOverrides: widget.danceOverrides,
              authorNameOverrides: widget.authorNameOverrides,
              seed: dance == null
                  ? SwapKeepSeed.empty
                  : SwapKeepSeed.of(
                      dance,
                      levels: widget.data.levels,
                      programMixesTypes: forms.length > 1,
                      // A section hidden in Settings ▸ Collection is not
                      // offered as a Keep item (its criterion would be
                      // invisible in the panels).
                      hiddenFacets: CollectionFacetsScope.of(sheetContext),
                    ),
              initialChoices: SwapKeepChoices.fromDefaults(defaults),
              swappedDanceId: slot.danceId,
              swappedForm: dance?.form,
              levelLabel: level == null
                  ? null
                  : danceLevelLabel(AppLocalizations.of(sheetContext), level),
              // The slot's other choices, not yet called.
              alternateIds: [
                for (final member in members)
                  if (member.id != slotId &&
                      member.danceId != null &&
                      member.danceId != slot.danceId &&
                      member.performedAt == null)
                    member.danceId!,
              ],
              programDanceIds: programDanceIds,
              rankSuggestions: widget.rankSuggestions,
              // Suggestions, when they order the results (#2348), rank for
              // the place of the slot being swapped: the dances on both sides
              // of it, and not the dance being swapped out.
              programContext: PickerProgramContext(
                programId: program.id,
                venueId: program.venueId,
                venue: program.venue,
                venueLabel: program.venue,
                position: flatIndex < 0
                    ? null
                    : SuggestionPosition.replacing(program.slots, flatIndex),
              ),
              // Event rules, when the swap sheet checks them (#2347): at the
              // place of the slot being swapped, the swapped-out dance kept as
              // an alternate, as the swap stores it.
              eventRuleIds: program.eventRuleIds,
              rulePosition: flatIndex < 0
                  ? null
                  : swapCandidatePosition(program.slots, flatIndex),
              onPick: (danceId) {
                _swapDance(slotId, danceId);
                Navigator.of(sheetContext).pop();
              },
            ),
          ),
        );
      },
      sheetAnimationStyle: AppMotion.styleFor(context),
    );
  }

  void _addNote() {
    final l10n = AppLocalizations.of(context);
    final text = _noteController.text.trim();
    if (text.isEmpty) return;
    final flat = [..._flatten(_working.grouped)];
    final at = _afterCurrentFlatIndex();
    flat.insert(at, ProgramSlot(id: uuidV4(), position: at, text: text));
    setState(() {
      _working = _withSlots(flat);
      _markChanged();
      _noteController.clear();
    });
    _announce(l10n.performAddedNoteAnnounce);
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
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.xs,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      AppLocalizations.of(sheetContext).performInsertADance,
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
                    danceOverrides: widget.danceOverrides,
                    choreographerNamesOverride: widget.authorNameOverrides,
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
      sheetAnimationStyle: AppMotion.styleFor(context),
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
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
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
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xxs,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          // Expanded (not Flexible, which would leave Done next to the title):
          // the title takes the free width, so Done stays at the trailing edge,
          // and at large text it wraps instead of pushing Done off-screen.
          // Done is not the only way to keep the edits — any dismissal keeps
          // them (see [PerformAdjustSheet.onEdited]) — but it is the explicit
          // one, so it must stay reachable.
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                l10n.performAdjustProgram,
                style: theme.textTheme.titleLarge,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const ValueKey('adjust-done'),
            onPressed: () =>
                Navigator.of(context).pop(_changed ? _working : null),
            child: Text(l10n.commonDone),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String text) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    ),
  );

  Widget _buildCurrentSlotSection(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final current = _working.slots.firstWhere(
      (s) => s.id == widget.currentSlotId,
      orElse: () => _working.slots.first,
    );
    final performed = current.performedAt != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(theme, l10n.performCurrentSlotSection),
        Text(_label(l10n, current), style: theme.textTheme.bodyLarge),
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
                performed
                    ? l10n.performPerformedTapToClear
                    : l10n.programsMarkPerformedMenu,
              ),
            ),
          ),
        ),
        if (_swappable(current)) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('adjust-swap-current'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(
                kPerformSwapMinTarget,
                kPerformSwapMinTarget,
              ),
            ),
            onPressed: () => _openSwap(current.id),
            icon: const Icon(Icons.swap_horiz),
            label: Text(l10n.performSwapThisDance),
          ),
        ],
      ],
    );
  }

  Widget _buildReorderSection(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final groups = _working.grouped;
    final start = _movableStart;
    final movable = groups.sublist(start);
    final currentGroup = _currentGroupIndex();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(theme, l10n.performReorderSection),
        if (movable.length < 2)
          Text(
            l10n.performNoLaterSlots,
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
                final label = _label(l10n, group.primary);
                // Upcoming only: never the current group (it has Swap this
                // dance above) or one before it, which was already called.
                final swappable =
                    absolute > currentGroup && _swappable(group.primary);
                return _ReorderRow(
                  key: ValueKey('adjust-reorder-${group.primary.id}'),
                  index: index,
                  absolutePosition: absolute,
                  total: movable.length,
                  label: label,
                  alternates: group.alternates.length,
                  onSwap: swappable ? () => _openSwap(group.primary.id) : null,
                  swapKey: ValueKey('adjust-swap-${group.primary.id}'),
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
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(theme, l10n.commonAddToProgram),
        OutlinedButton.icon(
          key: const ValueKey('adjust-insert-dance'),
          onPressed: _openInsertPicker,
          icon: const Icon(Icons.library_music_outlined),
          label: Text(l10n.performInsertDanceFromSearch),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('adjust-note-field'),
          controller: _noteController,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _addNote(),
          decoration: InputDecoration(
            labelText: l10n.performAdHocNoteLabel,
            hintText: l10n.performAdHocNoteHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('adjust-add-note'),
            onPressed: _addNote,
            icon: const Icon(Icons.notes_outlined),
            label: Text(l10n.performAddNote),
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
    this.onSwap,
    this.swapKey,
  });

  final int index;
  final int absolutePosition;
  final int total;
  final String label;
  final int alternates;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  /// Opens the swap sheet for this row's dance, or null when it is not
  /// offered (#2346).
  final VoidCallback? onSwap;
  final Key? swapKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final subtitle = alternates > 0
        ? l10n.performAlternatesCount(alternates)
        : null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      leading: CircleAvatar(child: Text('${absolutePosition + 1}')),
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onSwap != null)
            IconButton(
              key: swapKey,
              tooltip: l10n.performSwapDanceNamed(label),
              icon: const Icon(Icons.swap_horiz),
              onPressed: onSwap,
            ),
          IconButton(
            key: ValueKey('adjust-move-up-$index'),
            tooltip: l10n.performMoveLabelUp(label),
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: onMoveUp,
          ),
          IconButton(
            key: ValueKey('adjust-move-down-$index'),
            tooltip: l10n.performMoveLabelDown(label),
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
