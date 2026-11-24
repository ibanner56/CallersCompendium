// Fill on an unfilled placeholder slot (#2338): what the picker opens with.
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';
import '../search/collection_data.dart';
import '../search/saved_search_context.dart';
import '../theme/app_spacing.dart';
import 'collection_picker.dart';
import 'saved_search_actions.dart';

/// What **Fill** opens the picker with: the placeholder's saved search loaded
/// in the panels ([request]), or, when that search cannot be used whole, no
/// search at all and a [notice] that says why.
@immutable
class PlaceholderFillStart {
  const PlaceholderFillStart.search(CollectionPanelRequest this.request)
    : notice = null;

  const PlaceholderFillStart.unfiltered(Widget this.notice) : request = null;

  /// The picker's one-shot panel state ([CollectionPicker.panelState]), or
  /// null for an unfiltered picker.
  final CollectionPanelRequest? request;

  /// Shown above the picker's search tools ([CollectionPicker.header]) when
  /// the search could not be loaded.
  final Widget? notice;
}

/// Reads what **Fill** on [slot] opens the picker with (#2338). Null when
/// [slot] is not a placeholder, or when reading failed (a message already
/// says so).
///
/// The saved search is loaded through the same path the picker's own saved
/// search dropdown uses ([SavedSearchActions.load], #2325), and its panel
/// state reaches the picker through the one entry point every caller uses
/// ([CollectionPicker.panelState]).
///
/// A search that names something that is gone (a deleted tag, level or
/// venue) is **never** loaded in part: dropping a criterion broadens an AND,
/// narrows an OR and inverts a **None of**. The picker opens unfiltered
/// instead, with a notice naming each missing criterion, and the caller
/// chooses. A saved search that is gone altogether opens it unfiltered too,
/// saying so.
Future<PlaceholderFillStart?> preparePlaceholderFill(
  BuildContext context, {
  required ProgramSlot slot,
  required CollectionData data,
  required Dialect dialect,
  required SearchEnrichment enrichment,
  String? programId,
  SearchClock clock = const SearchClock(),
}) async {
  final searchId = slot.placeholderSearchId;
  if (searchId == null) return null;
  final repos = RepositoriesScope.of(context);
  final label = slot.text ?? '';
  final SavedSearch? search;
  try {
    search = await repos.savedSearches.get(searchId);
  } on Object {
    // diagnostics: silent — an unreadable value reads as no saved search,
    // which the notice below reports; nothing is applied.
    return PlaceholderFillStart.unfiltered(PlaceholderFillNotice(label: label));
  }
  if (!context.mounted) return null;
  if (search == null) {
    return PlaceholderFillStart.unfiltered(PlaceholderFillNotice(label: label));
  }
  CollectionPanelState? loaded;
  final load = await SavedSearchActions(
    context,
    clock: clock,
    dialect: dialect,
    enrichment: enrichment,
    current: () => loaded!,
    apply: (state) => loaded = state,
    // Only the panel state and what is missing are used here; the picker
    // builds the filter itself, with its own live Calling history settings.
    readContext: (text) => readSavedSearchContext(
      repos,
      today: clock.today(),
      taxonomy: data.taxonomy,
      text: text,
      currentProgramId: programId,
    ),
  ).load(search);
  final state = loaded;
  if (load == null || state == null) return null;
  if (load.missing.isNotEmpty) {
    return PlaceholderFillStart.unfiltered(
      PlaceholderFillNotice(
        label: label,
        searchName: search.name,
        missing: load.missing,
      ),
    );
  }
  return PlaceholderFillStart.search(CollectionPanelRequest(state));
}

/// Says why **Fill** shows every dance: the placeholder's saved search is gone
/// ([searchName] null), or it names things that are gone ([missing], each by
/// name). Read out when it appears.
class PlaceholderFillNotice extends StatelessWidget {
  const PlaceholderFillNotice({
    super.key,
    required this.label,
    this.searchName,
    this.missing = const [],
  });

  /// The placeholder's label.
  final String label;

  /// The saved search's name, or null when the search itself is gone.
  final String? searchName;
  final List<SavedSearchMissing> missing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final name = searchName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Material(
          key: const ValueKey('placeholder-fill-notice'),
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(AppSpacing.xs),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber, color: scheme.onErrorContainer),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: scheme.onErrorContainer),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name == null
                              ? l10n.programsFillSearchGone(label)
                              : l10n.programsFillSearchUnresolvable(
                                  label,
                                  name,
                                ),
                        ),
                        for (final m in missing)
                          Text(savedSearchMissingText(l10n, m)),
                      ],
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
}
