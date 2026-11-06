import '../../l10n/app_localizations.dart';
import '../data/online_search.dart';

/// The line above online search results: how many there are, and any caveat
/// about how the search ran.
///
/// - The source gave a total larger than what is shown: "Showing 20 of 143",
///   with a hint to scroll while [hasMore], and without it when no more will
///   load by scrolling.
/// - The source gave a total and everything is shown: the plain count.
/// - No total, but [hasMore] (a response filled its page and more may remain):
///   the "there may be more" form.
/// - Otherwise: the plain count.
///
/// A note follows the count after a middle dot when Advanced conditions the
/// source has no counterpart for were left out of the search.
String onlineResultCountLabel(
  AppLocalizations l10n,
  List<OnlineSearchResultRow> rows, {
  required bool hasMore,
}) {
  final count = rows.length;
  final total = rows.isEmpty ? null : rows.first.totalMatching;
  // Nothing shown, so nothing more to load: a stale flag from an earlier
  // search must not read "Showing 0 ... there may be more".
  final more = hasMore && rows.isNotEmpty;
  final String countLabel;
  if (total != null && total > count) {
    // The hint to scroll is only true while scrolling can load more: not once
    // paging has ended short of the total, nor while a failed page waits for
    // its Try again button.
    countLabel = more
        ? l10n.onlineResultCountOfTotal(count, total)
        : l10n.onlineResultCountOfTotalStopped(count, total);
  } else if (total == null && more) {
    countLabel = l10n.onlineResultCountCapped(count);
  } else {
    countLabel = l10n.onlineResultCount(count);
  }
  return rows.any((row) => row.advancedPartlyApplied)
      ? '$countLabel · ${l10n.onlineAdvancedPartlyApplied}'
      : countLabel;
}
