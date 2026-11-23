import 'builder_nodes.dart';
import 'collection_search_state.dart';
import 'collection_sort.dart';
import 'filter.dart';
import 'search_sort.dart';

/// Everything a Collection-style search panel holds: the search text, **Search
/// in**, every Filters selection, the By phrase rows, the Advanced tree and the
/// sort with its direction.
///
/// This is the in-memory, live form a host edits (and the type a host takes to
/// open with a given search). The persisted form is `SavedSearchSpec`, which
/// maps to and from this one. It holds live, mutable objects on purpose: they
/// are the objects the panels already edit.
class CollectionPanelState {
  CollectionPanelState({
    this.text = '',
    this.scope = FullTextScope.omni,
    FacetSelections? facets,
    ByPhraseSelections? byPhrase,
    BuilderGroup? advanced,
    this.sort = CollectionSort.title,
    SortDirection? sortDirection,
    this.fromSavedSearch = false,
  }) : facets = facets ?? FacetSelections(),
       byPhrase = byPhrase ?? ByPhraseSelections(),
       advanced = advanced ?? BuilderGroup(),
       sortDirection = sortDirection ?? sort.searchSort.defaultDirection;

  /// The search text as the user sees it (in the active dialect).
  String text;

  /// The **Search in** choice.
  FullTextScope scope;

  final FacetSelections facets;
  final ByPhraseSelections byPhrase;

  /// The Advanced tree's root. Its children are the rows.
  final BuilderGroup advanced;

  CollectionSort sort;
  SortDirection sortDirection;

  /// Whether this state was read from a saved search
  /// (`SavedSearchSpec.toPanelState` sets it), rather than built by a caller.
  /// A host says so where it matters: a **Within** window none of the
  /// Calling history presets offers reads "12 months, saved" instead of
  /// "12 months".
  final bool fromSavedSearch;

  /// Whether any search text, filter, phrase row or Advanced row is set — the
  /// condition under which a search is worth saving. **Search in** and the sort
  /// alone do not count.
  bool get hasQuery =>
      text.trim().isNotEmpty ||
      !facets.isEmpty ||
      !byPhrase.isEmpty ||
      advanced.toFilter() != null;

  /// Whether this is a bare full-text search, the only case where
  /// [CollectionSort.relevance] is offered.
  bool get isBareFullTextSearch => isBareFullText(
    ftsText: text,
    facets: facets,
    scope: scope,
    byPhrase: byPhrase,
    advancedRoot: advanced,
  );

  /// The sort and direction to apply: [sort] and [sortDirection], except that
  /// a [CollectionSort.relevance] that is no longer offered falls back to
  /// **Title** with its own default direction, as the Collection does when a
  /// bare full-text search stops being one.
  ({CollectionSort sort, SortDirection direction}) get effectiveSort {
    if (sort == CollectionSort.relevance && !isBareFullTextSearch) {
      return (
        sort: CollectionSort.title,
        direction: CollectionSort.title.searchSort.defaultDirection,
      );
    }
    return (sort: sort, direction: sortDirection);
  }
}
