import 'filter.dart' show FullTextScope;
import 'search_sort.dart';

/// Sort options surfaced in the Collection UI (`docs/design/ux.md` §1). Maps
/// onto the core [SearchSort] allow-list. [relevance] is only offered when the
/// query is a bare full-text search (`docs/design/search.md` decision 6);
/// `recentlyEdited` stays out of the UI to avoid a confusing
/// "added" vs "edited" pair, though it remains available in core.
enum CollectionSort {
  relevance,
  title,
  author,
  recentlyAdded,
  lastCalled;

  /// The core [SearchSort] this option sorts by.
  SearchSort get searchSort => switch (this) {
    CollectionSort.relevance => SearchSort.relevance,
    CollectionSort.title => SearchSort.title,
    CollectionSort.author => SearchSort.author,
    CollectionSort.recentlyAdded => SearchSort.recentlyAdded,
    CollectionSort.lastCalled => SearchSort.lastCalled,
  };
}

/// Resolves a persisted settings value (the [CollectionSort] `.name`) into a
/// [CollectionSort] usable as the Collection list's default sort (ROADMAP G.6a).
///
/// Returns `null` — so callers fall back to their historical default (`title`)
/// — for `null`, a non-string, an unrecognized name, or [CollectionSort.relevance]
/// (relevance is only meaningful for a bare full-text query, never as a saved
/// default; see `docs/design/search.md` decision 6).
CollectionSort? collectionSortFromName(Object? stored) {
  if (stored is! String) return null;
  for (final sort in CollectionSort.values) {
    if (sort.name == stored && sort != CollectionSort.relevance) return sort;
  }
  return null;
}

/// The sorts a Collection-style list offers for the current query, in menu
/// order. [CollectionSort.relevance] is offered only while [bareFullText] —
/// see [isBareFullText] — so the Collection and the program picker offer the
/// same set (FIND-7).
List<CollectionSort> availableCollectionSorts({required bool bareFullText}) => [
  if (bareFullText) CollectionSort.relevance,
  CollectionSort.title,
  CollectionSort.author,
  CollectionSort.recentlyAdded,
  CollectionSort.lastCalled,
];

/// The **Search in** choice an online search uses. The online sources search
/// by title, author or figure, so **All fields** falls back to
/// [FullTextScope.title]; the other three pass through.
FullTextScope onlineFullTextScope(FullTextScope scope) => switch (scope) {
  FullTextScope.omni => FullTextScope.title,
  FullTextScope.title || FullTextScope.author || FullTextScope.figure => scope,
};
