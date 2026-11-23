import 'package:compendium_core/compendium_core.dart';

// The Collection search model and its translator live in compendium_core
// (#2325), so a saved search can resolve to a DanceFilter without Flutter.
// Re-exported so this file stays the one import the app's search code uses.
export 'package:compendium_core/compendium_core.dart'
    show
        BuilderFigure,
        BuilderFigureGroup,
        BuilderFigureNode,
        BuilderGroup,
        BuilderNode,
        BuilderTag,
        BuilderThen,
        ByPhraseSelections,
        CollectionSort,
        FacetSelections,
        GroupKind,
        NumberFacetState,
        RemovedTagRows,
        TextFacetState,
        availableCollectionSorts,
        buildCollectionFilter,
        calendarMonthsBefore,
        collectionSortFromName,
        isBareFullText,
        onlineFullTextScope,
        orGroup;

/// The English label of a [CollectionSort] (localized labels are in
/// `collection_query_labels.dart`).
extension CollectionSortX on CollectionSort {
  String get label => switch (this) {
    CollectionSort.relevance => 'Best match',
    CollectionSort.title => 'Title',
    CollectionSort.author => 'Author',
    CollectionSort.recentlyAdded => 'Recently added',
    CollectionSort.lastCalled => 'Last called',
  };
}
