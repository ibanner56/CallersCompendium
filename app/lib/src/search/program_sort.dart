import 'package:compendium_core/compendium_core.dart';

/// How the Programs list is ordered (`docs/design/ux.md` §4).
///
/// Extracted from `screens/programs_list_screen.dart` (issue #895) so it can
/// be imported by the Settings ▸ Defaults picker without pulling in the
/// 600+-line Programs list screen (and, transitively, the import screens,
/// the editor, and `flutter_slidable`) — mirrors the existing
/// `search/collection_query.dart` split for `CollectionSort` (a dartdoc
/// `[...]` link to it would not resolve from this file, which does not
/// import that library).
enum ProgramSort {
  title,
  recentlyUpdated,
  eventDate;

  /// The historical (pre-toggle) direction for this sort key, used to seed the
  /// direction toggle so behavior is unchanged until the user flips it.
  SortDirection get defaultDirection => switch (this) {
    ProgramSort.title || ProgramSort.eventDate => SortDirection.ascending,
    ProgramSort.recentlyUpdated => SortDirection.descending,
  };
}

/// Resolves a persisted settings value (a [ProgramSort] `.name`) into a
/// [ProgramSort] usable as the Programs list's default sort (ROADMAP G.6c,
/// issue #895).
///
/// Returns `null` — so callers fall back to their historical default
/// (`title`) — for `null`, a non-string, or an unrecognized name. Mirrors
/// `collectionSortFromName` in `collection_query.dart`.
ProgramSort? programSortFromName(Object? stored) {
  if (stored is! String) return null;
  for (final sort in ProgramSort.values) {
    if (sort.name == stored) return sort;
  }
  return null;
}
