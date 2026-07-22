import '../../l10n/app_localizations.dart';
import 'collection_query.dart';

/// Localized labels for the Collection query enums ([CollectionSort],
/// [GroupKind]) shown in the sort menu and the advanced-query builder.
///
/// The enum `label` extensions in `collection_query.dart` stay English for
/// non-UI callers (export/plain-text, and the not-yet-localized Settings
/// default-sort picker); UI on the Collection screens routes through these
/// helpers instead so the visible text is localizable.
String collectionSortLabel(AppLocalizations l10n, CollectionSort sort) =>
    switch (sort) {
      CollectionSort.relevance => l10n.collectionSortRelevance,
      CollectionSort.title => l10n.collectionSortTitle,
      CollectionSort.author => l10n.collectionSortAuthor,
      CollectionSort.recentlyAdded => l10n.collectionSortRecentlyAdded,
      CollectionSort.lastCalled => l10n.collectionSortLastCalled,
    };

String groupKindLabel(AppLocalizations l10n, GroupKind kind) => switch (kind) {
  GroupKind.all => l10n.collectionQueryGroupAll,
  GroupKind.any => l10n.collectionQueryGroupAny,
  GroupKind.none => l10n.collectionQueryGroupNone,
};
