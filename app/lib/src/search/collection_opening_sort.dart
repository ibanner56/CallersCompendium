import 'package:compendium_core/compendium_core.dart';

import '../data/display_defaults.dart';
import 'collection_query.dart';

/// Reads the sort and direction a Collection-style list opens in, from
/// Settings ▸ Defaults ▸ **Collection sort order** (ROADMAP G.6a).
///
/// - A fixed default opens in its own direction (issue #1841), or the sort's
///   natural direction when none is stored or it is unrecognised.
/// - **Last used** (issue #895) opens in the Collection list's own last-used
///   sort and direction.
///
/// Returns `null` when a settings read fails, so the caller keeps its built-in
/// default (Title, ascending): a settings failure must never fail a list load.
/// A failed *direction* read under a fixed default is not a failure; the sort
/// still applies, in its natural direction.
///
/// Shared by the Collection screen and the program picker (FIND-7). The
/// picker only reads: it never writes the last-used keys, so a sort chosen
/// while picking lasts for that picker and never changes how the Collection
/// opens.
Future<({CollectionSort sort, SortDirection direction})?>
readCollectionOpeningSort(SettingsRepository settings) async {
  SortDefaultSetting<CollectionSort> mode;
  try {
    mode = sortDefaultSettingFromStored(
      await settings.get(kDefaultCollectionSortKey),
      collectionSortFromName,
      CollectionSort.title,
    );
  } catch (_) {
    // diagnostics: silent — a settings read/decode failure must not fail the
    // list load; the caller keeps the historical default (title, ascending).
    return null;
  }
  if (mode.isLastUsed) {
    try {
      final storedSort = await settings.get(kLastUsedCollectionSortKey);
      final storedDirection = await settings.get(
        kLastUsedCollectionSortDirectionKey,
      );
      final sort = collectionSortFromName(storedSort) ?? CollectionSort.title;
      return (
        sort: sort,
        direction:
            sortDirectionFromName(storedDirection) ??
            sort.searchSort.defaultDirection,
      );
    } catch (_) {
      // diagnostics: silent — same tolerance as the mode read above.
      return null;
    }
  }
  // A fixed default never reads the last-used keys.
  final sort = mode.sort;
  var direction = sort.searchSort.defaultDirection;
  try {
    direction =
        sortDirectionFromName(
          await settings.get(kDefaultCollectionSortDirectionKey),
        ) ??
        direction;
  } catch (_) {
    // diagnostics: silent — direction read failed; the fixed sort still
    // applies, in its natural direction.
  }
  return (sort: sort, direction: direction);
}
