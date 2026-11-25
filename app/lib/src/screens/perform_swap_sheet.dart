import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/calling_history_tracking_scope.dart';
import '../data/event_rules_scope.dart';
import '../data/repositories_scope.dart';
import '../data/require_event_date_for_history_scope.dart';
import '../data/require_performed_for_history_scope.dart';
import '../data/suggestions_scope.dart';
import '../data/user_figures_scope.dart';
import '../search/collection_data.dart';
import '../search/event_rule_check.dart';
import '../search/facet_labels.dart';
import '../search/saved_search_context.dart';
import '../theme/app_spacing.dart';
import '../widgets/collection_picker.dart';
import '../widgets/move_autocomplete.dart' show moveLabelWithForm;
import '../widgets/picker_suggestions.dart';

/// The smallest a control on this sheet may be, on each side: Perform's
/// target size (docs/design/ux.md, "Cross-cutting UX rules": "44pt in
/// Perform").
const double kPerformSwapMinTarget = 44;

/// Perform's swap sheet (#2346): **Keep** (what the replacement must share
/// with the dance being swapped), then the matching dances, already searched,
/// with the slot's alternates first under **Your alternates**.
///
/// Built on [CollectionPicker], as the program builder's pickers are: the
/// Keep items are the picker's own Filters and Advanced state
/// ([swapKeepPanelState]), each Keep change sent as a new
/// [CollectionPicker.panelState] request, so every change searches again
/// with no Search button, and **More filters** shows the same criteria in
/// the panels, editable. From then on the panels hold the query: no request
/// is sent again, the Keep chips that live in the panels are put away, and
/// **Not already in tonight's program**, which leaves dances out by id
/// rather than by a panel criterion, stays and changes only those ids. A
/// request replaces the sort too, so each one carries the sort the user last
/// picked ([CollectionPicker.onSortChanged]).
///
/// With Settings ▸ Experimental ▸ Suggestions and its **Use in Perform's Swap
/// this dance** both on ([SuggestionsInPerformSwapScope.activeOf], #2348),
/// the results under **Your alternates** open in the picker's **Suggested**
/// order for [programContext]'s position, the place of the slot being
/// swapped, each with its reason line ([CollectionPicker.openSuggested]).
/// Ranking only reorders: the same dances show either way, in the plain
/// order until it finishes, and a tap swaps either way. With either off the
/// sheet is as #2346 ships it, with no Suggested in the Sort menu.
///
/// With Settings ▸ Experimental ▸ Event rules and its **Check Perform's Swap
/// this dance** both on ([EventRulesCheckPerformSwapScope.activeOf], #2347)
/// and rules applied to the program ([eventRuleIds]), each dance that would
/// break one of them in the swapped slot is marked with the rule's sentence
/// and listed after every unmarked dance, in any order
/// ([CollectionPicker.eventRules], [PickerEventRules.inEveryOrder]); so is
/// each of **Your alternates**, listed last among them. The check is at
/// [rulePosition], the program as the swap stores it, the swapped-out dance
/// kept as an alternate ([swapCandidatePosition]). The results show at once,
/// unmarked, and the marks follow when the check is done. Nothing is hidden,
/// and a tap swaps either way. With either off, or no rules applied, the
/// sheet is as #2346 ships it.
///
/// Tapping a result calls [onPick] with its id. Online search is not offered:
/// an import at the mic adds a network wait and a possible duplicate prompt.
class PerformSwapSheet extends StatefulWidget {
  const PerformSwapSheet({
    super.key,
    required this.title,
    required this.data,
    required this.dialect,
    required this.enrichment,
    required this.seed,
    required this.initialChoices,
    required this.onPick,
    this.swappedDanceId,
    this.swappedForm,
    this.levelLabel,
    this.alternateIds = const [],
    this.programDanceIds = const {},
    this.programContext,
    this.danceOverrides = const {},
    this.authorNameOverrides = const {},
    this.rankSuggestions,
    this.eventRuleIds = const [],
    this.rulePosition,
  });

  /// The name of the dance being swapped, as the adjust sheet shows it.
  final String title;

  final CollectionData data;
  final Dialect dialect;
  final SearchEnrichment enrichment;

  /// What the dance being swapped offers to keep.
  final SwapKeepSeed seed;

  /// The Keep items on when the sheet opens (from Settings ▸ Program ▸
  /// Perform mode ▸ **Swap a dance**).
  final SwapKeepChoices initialChoices;

  final ValueChanged<String> onPick;

  /// The dance being swapped, never listed as its own replacement.
  final String? swappedDanceId;

  /// The form of the dance being swapped, or null when it could not be read.
  final DanceForm? swappedForm;

  /// The name of the dance's level, for **This level or easier**.
  final String? levelLabel;

  /// The slot's other choices, listed first under **Your alternates**.
  final List<String> alternateIds;

  /// Every dance in the program, left out under **Not already in tonight's
  /// program**.
  final Set<String> programDanceIds;

  final PickerProgramContext? programContext;
  final Map<String, Dance> danceOverrides;
  final Map<String, String> authorNameOverrides;

  /// Ranks for Suggested: [CollectionPicker.rankSuggestions], a test seam.
  final SuggestionRanker? rankSuggestions;

  /// The rules applied to the program ([Program.eventRuleIds], #2347), in
  /// the order applied. Empty checks nothing.
  final List<String> eventRuleIds;

  /// Where a replacement goes, for checking it against [eventRuleIds]: the
  /// program as the swap stores it ([swapCandidatePosition]). Null checks
  /// nothing.
  final SuggestionPosition? rulePosition;

  @override
  State<PerformSwapSheet> createState() => _PerformSwapSheetState();
}

class _PerformSwapSheetState extends State<PerformSwapSheet> {
  late SwapKeepChoices _choices = widget.initialChoices;

  /// The sort the user last picked in the picker, carried into each request.
  ({CollectionSort sort, SortDirection direction})? _sort;

  /// The search the picker shows. Held here, as [CollectionPicker.panelState]
  /// asks, and replaced by a new request only when a Keep item changes.
  late CollectionPanelRequest _request = CollectionPanelRequest(
    _stateFor(_choices),
  );

  CollectionPanelState _stateFor(SwapKeepChoices choices) {
    final state = swapKeepPanelState(widget.seed, choices);
    if (_sort case final sort?) {
      state
        ..sort = sort.sort
        ..sortDirection = sort.direction;
    }
    return state;
  }

  /// Whether **More filters** was tapped: the panels now hold the query.
  bool _moreFilters = false;

  void _update(SwapKeepChoices next) {
    setState(() {
      _choices = next;
      // After More filters the panels hold the query, with the user's edits:
      // a Keep change then touches only the dances left out by id.
      if (!_moreFilters) _request = CollectionPanelRequest(_stateFor(next));
    });
  }

  Set<String> get _excluded => {
    ?widget.swappedDanceId,
    if (_choices.notInProgram) ...widget.programDanceIds,
  };

  String _moveName(String move) {
    final taxonomy = widget.data.taxonomy;
    if (taxonomy.resolve(move) == null) return move;
    return moveLabelWithForm(
      context,
      taxonomy,
      move,
      FigureRenderer(taxonomy).displayMoveName(move, widget.dialect),
    );
  }

  /// The search context the rules' saved searches resolve against, read
  /// once for the sheet: what a rule matches does not change while the
  /// caller picks a replacement.
  Future<SavedSearchContext>? _ruleContext;

  /// The program's event rules for the picker to check the results against
  /// (#2347), or null when nothing is checked: **Check Perform's Swap this
  /// dance** off, no rules applied, or no place to check. The picker itself
  /// checks only while Event rules is on.
  ///
  /// The picker hands the check its own position, the one Suggested ranks
  /// for ([SuggestionPosition.replacing]); the check is made at
  /// [PerformSwapSheet.rulePosition] instead, the same slot with the
  /// swapped-out dance kept as an alternate. Both are fixed while the sheet
  /// is open.
  PickerEventRules? _eventRules(BuildContext context) {
    final ruleIds = widget.eventRuleIds;
    final position = widget.rulePosition;
    if (ruleIds.isEmpty ||
        position == null ||
        !EventRulesCheckPerformSwapScope.of(context)) {
      return null;
    }
    final repos = RepositoriesScope.of(context);
    final catalog =
        context
            .getInheritedWidgetOfExactType<UserFiguresScope>()
            ?.notifier
            ?.catalog ??
        UserFigureCatalog.empty;
    final dialect = widget.dialect;
    final enrichment = widget.enrichment;
    final performedOnly = RequirePerformedForHistoryScope.of(context);
    final requireEventDate = RequireEventDateForHistoryScope.of(context);
    final tracking = callingHistoryTrackingOf(context);
    Future<SavedSearchContext> readContext() =>
        _ruleContext ??= readSavedSearchContext(
          repos,
          today: const SearchClock().today(),
          taxonomy: widget.data.taxonomy,
          text: savedSearchTextCodec(
            saveDialect: dialect,
            showDialect: dialect,
            enrichment: enrichment,
            renderer: FigureRenderer(
              shippedTaxonomies.anyForm,
              userFigures: catalog,
            ),
          ),
          callerFilter: widget.data.callerFilter,
          performedOnly: performedOnly,
          requireEventDate: requireEventDate,
          tracking: tracking,
          currentProgramId: widget.programContext?.programId,
        );
    return PickerEventRules(
      check: (_, candidateIds) => checkCandidateEventRules(
        repos: repos,
        ruleIds: ruleIds,
        position: position,
        candidateIds: candidateIds,
        readContext: readContext,
        dialect: dialect,
        enrichment: enrichment,
      ),
      revision: Object.hashAll(ruleIds),
      inEveryOrder: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ordered = SuggestionsInPerformSwapScope.activeOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Semantics(
            header: true,
            child: Text(
              l10n.performSwapDanceNamed(widget.title),
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
        Expanded(
          child: CollectionPicker(
            key: const ValueKey('swap-picker'),
            data: widget.data,
            dialect: widget.dialect,
            enrichment: widget.enrichment,
            danceOverrides: widget.danceOverrides,
            choreographerNamesOverride: widget.authorNameOverrides,
            rowAction: PickerRowAction.replace,
            programContext: widget.programContext,
            // Ordering by suggestions (#2348), behind its own setting.
            offerSuggested: ordered,
            openSuggested: ordered,
            rankSuggestions: widget.rankSuggestions,
            // Marks by the program's event rules (#2347), behind its own
            // setting.
            eventRules: _eventRules(context),
            panelState: _request,
            onSortChanged: (sort, direction) =>
                _sort = (sort: sort, direction: direction),
            showSearchControls: _moreFilters,
            initialPanel: PickerSearchPanel.filters,
            excludedDanceIds: _excluded,
            pinned: PickerPinnedDances(
              heading: l10n.performSwapAlternatesHeading,
              resultsHeading: l10n.performSwapResultsHeading,
              danceIds: widget.alternateIds,
            ),
            header: _buildKeep(context),
            onAddDance: widget.onPick,
          ),
        ),
      ],
    );
  }

  Widget _chip({
    required Key key,
    required String label,
    String? semanticsLabel,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    final chip = ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: kPerformSwapMinTarget,
        minWidth: kPerformSwapMinTarget,
      ),
      child: FilterChip(
        key: key,
        label: Text(label),
        selected: selected,
        onSelected: onSelected,
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
    if (semanticsLabel == null) return chip;
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      selected: selected,
      button: true,
      onTap: () => onSelected(!selected),
      child: chip,
    );
  }

  Widget _buildKeep(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final seed = widget.seed;
    final keptFigures = [
      for (final figure in seed.figures)
        if (_choices.figures[figure.index] case final keep?) (figure, keep),
    ];
    final notInProgram = _chip(
      key: const ValueKey('swap-keep-not-in-program'),
      label: l10n.performSwapKeepNotInProgram,
      selected: _choices.notInProgram,
      onSelected: (on) => _update(_choices.copyWith(notInProgram: on)),
    );
    Widget section(String text) => Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: AppSpacing.xxs,
        ),
        child: Text(text, style: theme.textTheme.titleSmall),
      ),
    );
    const spacing = AppSpacing.xs;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          section(l10n.performSwapKeepHeader),
          if (_moreFilters) ...[
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [notInProgram],
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                l10n.performSwapKeepInPanels,
                key: const ValueKey('swap-keep-in-panels'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ] else ...[
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                if (seed.formation case final shape?)
                  _chip(
                    key: const ValueKey('swap-keep-formation'),
                    label: l10n.performSwapKeepFormation(
                      formationShapeLabel(l10n, shape),
                    ),
                    selected: _choices.formation,
                    onSelected: (on) =>
                        _update(_choices.copyWith(formation: on)),
                  ),
                if (seed.levelIds.isNotEmpty)
                  _chip(
                    key: const ValueKey('swap-keep-level'),
                    label: l10n.performSwapKeepLevel(widget.levelLabel ?? ''),
                    selected: _choices.levelOrEasier,
                    onSelected: (on) =>
                        _update(_choices.copyWith(levelOrEasier: on)),
                  ),
                if (seed.form case final form?)
                  _chip(
                    key: const ValueKey('swap-keep-type'),
                    label: l10n.performSwapKeepType(danceFormLabel(l10n, form)),
                    selected: _choices.sameType,
                    onSelected: (on) =>
                        _update(_choices.copyWith(sameType: on)),
                  ),
                notInProgram,
              ],
            ),
            if (seed.figures.isNotEmpty) ...[
              section(l10n.performSwapFiguresHeader),
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final figure in seed.figures) _figureChip(l10n, figure),
                ],
              ),
            ],
            for (final (figure, keep) in keptFigures)
              if (figure.section != null || figure.beforeMove != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _figureLabel(l10n, figure),
                        style: theme.textTheme.labelLarge,
                      ),
                      if (figure.section case final phrase?)
                        _chip(
                          key: ValueKey(
                            'swap-keep-same-phrase-${figure.index}',
                          ),
                          label: l10n.performSwapSamePhrase(phrase),
                          semanticsLabel: l10n.performSwapSamePhraseSemantic(
                            _moveName(figure.move),
                            phrase,
                          ),
                          selected: keep.samePhrase,
                          onSelected: (on) => _update(
                            _choices.withFigure(
                              figure.index,
                              keep.copyWith(samePhrase: on),
                            ),
                          ),
                        ),
                      if (figure.beforeMove case final before?)
                        _chip(
                          key: ValueKey(
                            'swap-keep-with-before-${figure.index}',
                          ),
                          label: l10n.performSwapWithBefore(_moveName(before)),
                          semanticsLabel: l10n.performSwapWithBeforeSemantic(
                            _moveName(figure.move),
                            _moveName(before),
                          ),
                          selected: keep.withBefore,
                          onSelected: (on) => _update(
                            _choices.withFigure(
                              figure.index,
                              keep.copyWith(withBefore: on),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            if (widget.swappedForm == DanceForm.ecd)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  l10n.performSwapEnglishNote,
                  key: const ValueKey('swap-keep-english-note'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  key: const ValueKey('swap-more-filters'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(
                      kPerformSwapMinTarget,
                      kPerformSwapMinTarget,
                    ),
                  ),
                  onPressed: () => setState(() => _moreFilters = true),
                  icon: const Icon(Icons.tune),
                  label: Text(l10n.performSwapMoreFilters),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }

  String _figureLabel(AppLocalizations l10n, SwapKeepFigure figure) {
    final name = _moveName(figure.move);
    final phrase = figure.section;
    return phrase == null ? name : l10n.performSwapFigureInPhrase(name, phrase);
  }

  Widget _figureChip(AppLocalizations l10n, SwapKeepFigure figure) {
    final keep = _choices.figures[figure.index];
    final label = _figureLabel(l10n, figure);
    return _chip(
      key: ValueKey('swap-keep-figure-${figure.index}'),
      label: label,
      semanticsLabel: l10n.performSwapKeepFigureSemantic(label),
      selected: keep != null,
      onSelected: (on) => _update(
        _choices.withFigure(figure.index, on ? const SwapFigureKeep() : null),
      ),
    );
  }
}
