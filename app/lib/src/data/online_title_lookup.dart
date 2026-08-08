import 'online_search.dart';

/// Why [lookupUniqueExactTitle] could not settle on a single online dance for a
/// title. Each value is a *distinct* user-facing situation — a caller who pasted
/// twelve titles needs to tell "the Box has never heard of this" apart from "the
/// Box was unreachable just now", because only one of those is worth retrying.
///
/// Deliberately typed rather than prose: the data layer never bakes English in
/// (the presentation layer localizes these at the render site), and the program
/// path collapses every value to the same `null` without inspecting it.
///
/// Note that a source may exclude rows the user could not act on before this
/// ever sees them — a Caller's Box search omits dances whose figures TCB will
/// not serve (issue #845) — so [noResults] and [noExactMatch] mean "nothing
/// usable was offered", not "the archive holds no such dance". A caller that
/// needs the wider set passes `requireFigures: false` to
/// [lookupUniqueExactTitle].
enum OnlineTitleLookupFailure {
  /// The search returned nothing at all.
  noResults,

  /// The search returned results, but none whose name equals the pasted title
  /// (trimmed, case-insensitive) — only fuzzy/substring neighbours.
  noExactMatch,

  /// More than one result has exactly this title, so which dance was meant is
  /// genuinely ambiguous and must not be guessed at.
  ///
  /// Source-side exclusions are applied first, so two same-titled Caller's Box
  /// dances of which only one will serve its figures resolve to a hit rather
  /// than landing here — except where the caller opted out with
  /// `requireFigures: false`, which is precisely why the unattended program
  /// path does so.
  multipleExactMatches,

  /// The search could not be performed (fetch/parse failure). Swallowed
  /// per-title so one bad title can never abort a batch.
  fetchError,
}

/// Outcome of [lookupUniqueExactTitle]: either the single unambiguous
/// [OnlineTitleHit], or an [OnlineTitleMiss] carrying the reason.
sealed class OnlineTitleLookupResult {
  const OnlineTitleLookupResult();
}

/// The unique exact-title match for the searched title.
final class OnlineTitleHit extends OnlineTitleLookupResult {
  const OnlineTitleHit(this.row);

  final OnlineSearchResultRow row;
}

/// No unique exact-title match, with the [failure] explaining which way it
/// missed.
final class OnlineTitleMiss extends OnlineTitleLookupResult {
  const OnlineTitleMiss(this.failure);

  final OnlineTitleLookupFailure failure;
}

/// Searches [service] for [title] and returns the **unique exact-title hit** —
/// exactly one result whose [OnlineSearchResultRow.name] equals [title] once
/// both are trimmed and lower-cased — or an [OnlineTitleMiss] saying why there
/// isn't one.
///
/// This is the shared, **non-committing** title→result step. It performs a
/// single search fetch and writes nothing; deciding what to *do* with a hit
/// belongs to the caller, and the two callers decide differently:
///
/// - the **program** path ([resolveConfidentOnlineDanceId] in
///   `program_import_online_resolver.dart`) is non-interactive — no user is
///   present to adjudicate a program line — so it previews and commits the hit
///   itself under the #685/#686 rules;
/// - the **Collection** path (`title_list_import.dart`, issue #823) previews the
///   hit into an `ImportRecordPlan` and hands it to `ImportReviewScreen`, which
///   commits nothing until the user confirms.
///
/// Keeping only this step shared is what lets those two stay different: folding
/// the commit in here would drag the program path's unattended import into a
/// flow that has a user watching, which is exactly what #823's batch-review
/// ruling exists to prevent.
///
/// Any fetch/parse [Exception] becomes [OnlineTitleLookupFailure.fetchError]
/// rather than propagating, so one bad title can't abort a batch; `Error`s
/// (assertion/programmer bugs) still surface.
///
/// [requireFigures] is forwarded to the search (see
/// [OnlineSearchQuery.requireFigures]). It defaults to `true` — a title that
/// only resolves to a dance the source won't hand over with its figures is not
/// a useful match — but the unattended program path passes `false`, because
/// there a narrower result set can turn a deliberate no-op into an automatic
/// commit.
Future<OnlineTitleLookupResult> lookupUniqueExactTitle(
  String title, {
  required OnlineSearchService service,
  bool requireFigures = true,
}) async {
  final wanted = title.trim().toLowerCase();
  final List<OnlineSearchResultRow> rows;
  try {
    rows = await service.search(
      OnlineSearchQuery(title: title, requireFigures: requireFigures),
    );
  } on Exception catch (_) {
    return const OnlineTitleMiss(OnlineTitleLookupFailure.fetchError);
  }
  if (rows.isEmpty) {
    return const OnlineTitleMiss(OnlineTitleLookupFailure.noResults);
  }
  final exact = rows
      .where((r) => r.name.trim().toLowerCase() == wanted)
      .toList();
  if (exact.isEmpty) {
    return const OnlineTitleMiss(OnlineTitleLookupFailure.noExactMatch);
  }
  if (exact.length > 1) {
    return const OnlineTitleMiss(OnlineTitleLookupFailure.multipleExactMatches);
  }
  return OnlineTitleHit(exact.single);
}
