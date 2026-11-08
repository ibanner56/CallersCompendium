import 'online_search.dart';

/// Whether an online source (ContraDB) has more results than [shown], given the
/// [lastPage] of rows just added to it.
///
/// - The source said how many matched ([OnlineSearchResultRow.totalMatching]):
///   more remain while fewer rows than that are shown.
/// - It did not (two merged spellings, or a response without a total): more may
///   remain while the page just fetched was full
///   ([OnlineSearchResultRow.mayHaveMore]).
///
/// Either way, a page that added nothing new ends it, so a source that repeats
/// itself cannot keep the list asking for ever.
bool onlineHasMore(
  List<OnlineSearchResultRow> shown,
  List<OnlineSearchResultRow> lastPage,
) {
  if (shown.isEmpty || lastPage.isEmpty) return false;
  final total = shown.first.totalMatching;
  if (total != null) return shown.length < total;
  return lastPage.any((row) => row.mayHaveMore);
}

/// [shown] followed by the rows of [page] it does not already hold (by id).
List<OnlineSearchResultRow> appendOnlinePage(
  List<OnlineSearchResultRow> shown,
  List<OnlineSearchResultRow> page,
) {
  final ids = {for (final row in shown) row.id};
  return [
    ...shown,
    for (final row in page)
      if (ids.add(row.id)) row,
  ];
}
