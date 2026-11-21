import '../../l10n/app_localizations.dart';
import '../data/online_search.dart';

/// The line above online search results: how many there are, and any caveat
/// about how the search ran.
///
/// Two facts decide the wording: whether the source may hold more than [rows]
/// ([hasMore]), and whether scrolling can load it ([loadFailed] says a page
/// failed, so only the Try again button can).
///
/// | total known | more may remain | scrolling loads it | line |
/// | --- | --- | --- | --- |
/// | larger than shown | yes | yes | "Showing 20 of 143 ... Scroll down to load more." |
/// | larger than shown | no, or a page failed | no | "Showing 20 of 143 online results." |
/// | unknown | yes | yes | "Showing 20 ... There may be more: scroll down to load them." |
/// | unknown | yes | no (a page failed) | "Showing 20 ... There may be more." |
/// | otherwise | | | the plain count |
///
/// A note follows the count after a middle dot when Advanced conditions the
/// source has no counterpart for were left out of the search.
String onlineResultCountLabel(
  AppLocalizations l10n,
  List<OnlineSearchResultRow> rows, {
  required bool hasMore,
  bool loadFailed = false,
}) {
  final count = rows.length;
  final total = rows.isEmpty ? null : rows.first.totalMatching;
  // Nothing shown, so nothing more to load: a stale flag from an earlier
  // search must not read "Showing 0 ... there may be more".
  final more = hasMore && rows.isNotEmpty;
  final canScroll = more && !loadFailed;
  final String countLabel;
  if (total != null && total > count) {
    countLabel = canScroll
        ? l10n.onlineResultCountOfTotal(count, total)
        : l10n.onlineResultCountOfTotalStopped(count, total);
  } else if (total == null && more) {
    countLabel = canScroll
        ? l10n.onlineResultCountCapped(count)
        : l10n.onlineResultCountMaybeMore(count);
  } else {
    countLabel = l10n.onlineResultCount(count);
  }
  return rows.any((row) => row.advancedPartlyApplied)
      ? '$countLabel · ${l10n.onlineAdvancedPartlyApplied}'
      : countLabel;
}
