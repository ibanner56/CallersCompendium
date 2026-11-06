import '../../l10n/app_localizations.dart';
import '../data/online_search.dart';

/// The line above online search results: how many there are, and any caveat
/// about how the search ran.
///
/// - The source gave a total larger than what is shown: "Showing 20 of 143".
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
  final String countLabel;
  if (total != null && total > count) {
    countLabel = l10n.onlineResultCountOfTotal(count, total);
  } else if (total == null && hasMore) {
    countLabel = l10n.onlineResultCountCapped(count);
  } else {
    countLabel = l10n.onlineResultCount(count);
  }
  return rows.any((row) => row.advancedPartlyApplied)
      ? '$countLabel · ${l10n.onlineAdvancedPartlyApplied}'
      : countLabel;
}
