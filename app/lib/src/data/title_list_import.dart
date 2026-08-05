import 'package:compendium_core/compendium_core.dart';

import 'online_search.dart';
import 'online_title_lookup.dart';
import 'plaintext_program_import.dart';

/// Hard cap on the raw length of a pasted title list, in UTF-16 code units.
///
/// The paste is **untrusted input** (OWASP A04 Insecure Design — uncontrolled
/// resource consumption): the user may paste anything, and unlike a picked file
/// there is no filesystem to bound it. 64 KiB leaves generous room for the
/// [kMaxTitleListTitles] × [kMaxTitleLength] worst case (~20 KB) while keeping a
/// pathological paste from being split, normalized, and diffed on every
/// keystroke. Enforced fail-closed: over the cap, nothing is parsed and no
/// request is made.
const int kMaxTitleListChars = 64 * 1024;

/// Hard cap on how many **distinct** titles one paste may resolve.
///
/// This is the fan-out bound: each title costs at most one search fetch plus one
/// per-dance fetch, so an accepted paste is capped at `2 × kMaxTitleListTitles`
/// requests, issued one at a time and cancellable. A paste above the cap makes
/// **zero** requests — it is refused before the network is touched, rather than
/// silently truncated, so a caller never believes a list imported in full when
/// it did not.
///
/// 100 is deliberately far above real use (an evening's program is ~12-15
/// dances, a season well under 100) and far below anything that would hammer The
/// Caller's Box. Counted **after** blank-dropping and case-insensitive
/// de-duplication, so repeating one title 500 times is one title, not a refusal.
const int kMaxTitleListTitles = 100;

/// Hard cap on the length of a single pasted line, in UTF-16 code units.
///
/// A line this long is not a dance title — it is pasted prose, a stray
/// paragraph, or a wrapped block. Such a line is reported as unfindable and
/// **never searched**, rather than aborting the whole paste: the rest of the
/// list is still worth resolving, and turning a paragraph into a search query
/// would be both useless and needlessly noisy for the source.
const int kMaxTitleLength = 200;

/// Which cap a paste tripped, for [TitleListTooLargeException].
enum TitleListRejection {
  /// The raw pasted text exceeded [kMaxTitleListChars].
  textTooLong,

  /// The paste held more than [kMaxTitleListTitles] distinct titles.
  tooManyTitles,
}

/// Raised when a paste trips a hard cap, **before** any parsing or network
/// access. Carries only the typed [rejection] and the offending [count] — no
/// user prose; the presentation layer localizes it (mirroring
/// [ImportFileTooLargeException] in `import_io.dart`, which is the in-repo
/// precedent for bounding untrusted import input).
class TitleListTooLargeException implements Exception {
  const TitleListTooLargeException(this.rejection, this.count);

  final TitleListRejection rejection;

  /// Characters for [TitleListRejection.textTooLong], distinct titles for
  /// [TitleListRejection.tooManyTitles].
  final int count;

  @override
  String toString() => 'TitleListTooLargeException($rejection, $count)';
}

/// Raised by [resolveTitleList] when the caller's `isCancelled` callback goes
/// true mid-batch. Nothing has been written at any point during resolution, so
/// a cancel simply discards the partial work; there is no half-committed state
/// to unwind.
class TitleListCancelled implements Exception {
  const TitleListCancelled();

  @override
  String toString() => 'TitleListCancelled';
}

/// Which of the three review groups a pasted title belongs to (issue #823).
///
/// Every pasted title lands in exactly one of these and **all three are shown**.
/// The two non-importable groups exist because a caller who pastes twelve titles
/// and gets six imports otherwise cannot tell which of the remaining six she
/// already owned and which the app could not find — and those need completely
/// different follow-up.
enum TitleListGroup {
  /// Resolved to a single online dance; has a review row with the usual
  /// per-record actions and dedupe verdict.
  toImport,

  /// Already in the local collection, so there is nothing to import. The useful
  /// information is that she already has it.
  alreadyInCollection,

  /// Nothing importable could be identified. [TitleListRow.reason] says which
  /// way it missed.
  notFound,
}

/// Why a [TitleListGroup.notFound] title produced nothing.
///
/// Kept distinct rather than collapsed into one "not found" because they call
/// for different follow-up: a fetch error is worth retrying, a title the source
/// has never heard of is not, and several exact matches means the source *has*
/// it but cannot say which one was meant.
enum TitleListNotFoundReason {
  /// The search returned nothing.
  noResults,

  /// Results came back, but none matched the title exactly — only fuzzy
  /// neighbours, which are never auto-imported.
  noExactMatch,

  /// Several results share this exact title, so which was meant is ambiguous.
  multipleExactMatches,

  /// The search or the per-dance fetch failed. Isolated per title so one bad
  /// title cannot abort the batch.
  fetchError,

  /// The line was longer than [kMaxTitleLength], so it was never searched.
  lineTooLong,
}

/// One pasted title's place in the review, in paste order.
class TitleListRow {
  const TitleListRow._({
    required this.title,
    required this.group,
    this.planIndex,
    this.reason,
    this.localMatchCount = 0,
    this.localAuthors = const [],
  });

  /// A title that resolved to an online dance, planned at [planIndex] in
  /// [TitleListResolution.batch].
  const TitleListRow.toImport({required String title, required int planIndex})
    : this._(
        title: title,
        group: TitleListGroup.toImport,
        planIndex: planIndex,
      );

  /// A title the local collection already has, [count] time(s). [authors] names
  /// the matched dance's choreographer(s) when there is exactly one match — the
  /// local match is title-only, so the author is what lets the user tell a real
  /// "you already have this" from a different dance that happens to share a
  /// title. With several matches the count is the message and the authors are
  /// omitted as noise.
  const TitleListRow.alreadyInCollection({
    required String title,
    required int count,
    List<String> authors = const [],
  }) : this._(
         title: title,
         group: TitleListGroup.alreadyInCollection,
         localMatchCount: count,
         localAuthors: authors,
       );

  /// A title nothing importable could be found for.
  const TitleListRow.notFound({
    required String title,
    required TitleListNotFoundReason reason,
  }) : this._(title: title, group: TitleListGroup.notFound, reason: reason);

  /// The pasted title, trimmed.
  final String title;

  final TitleListGroup group;

  /// Index into [TitleListResolution.batch]'s records; non-null only for
  /// [TitleListGroup.toImport].
  final int? planIndex;

  /// Non-null only for [TitleListGroup.notFound].
  final TitleListNotFoundReason? reason;

  /// How many local dances share this title; `>0` only for
  /// [TitleListGroup.alreadyInCollection].
  final int localMatchCount;

  /// Choreographer names of the single local match, when there is exactly one.
  final List<String> localAuthors;
}

/// The result of resolving a pasted title list: the planned-but-**uncommitted**
/// [batch] the review screen acts on, plus a [rows] entry for every pasted
/// title including the ones with nothing to import.
class TitleListResolution {
  const TitleListResolution({
    required this.batch,
    required this.rows,
    required this.duplicateLines,
  });

  /// Only the importable records, in paste order, ready for
  /// `ImportReviewScreen` to review and commit. Nothing here is written yet.
  final ImportBatchResult batch;

  /// One row per pasted title, in paste order, across all three groups.
  final List<TitleListRow> rows;

  /// How many repeated lines were folded away by de-duplication.
  final int duplicateLines;

  Iterable<TitleListRow> rowsIn(TitleListGroup group) =>
      rows.where((r) => r.group == group);

  int countIn(TitleListGroup group) => rowsIn(group).length;
}

/// One pasted line after bounding, before any local or online resolution.
class TitleListLine {
  const TitleListLine(this.title, {this.rejected});

  final String title;

  /// Non-null when the line was rejected by a per-line bound and must never be
  /// searched.
  final TitleListNotFoundReason? rejected;
}

/// The pure, synchronous, network-free bounding pass over a pasted blob.
///
/// Split out from [resolveTitleList] so the input UI can call it on every
/// keystroke — to show the distinct-title count and refuse Continue *before* the
/// user waits on anything — while [resolveTitleList] calls it again and enforces
/// the same caps itself. The UI check is an affordance; this is the control. A
/// bound that only exists in a widget is not a bound.
///
/// In order, it: rejects the whole paste over [kMaxTitleListChars]; splits on
/// newlines; trims; drops blank lines; flags lines over [kMaxTitleLength] as
/// [TitleListNotFoundReason.lineTooLong] (kept in place so they still appear in
/// the review, but never searched); folds case-insensitive duplicates onto their
/// first occurrence; and rejects the paste over [kMaxTitleListTitles] distinct
/// titles.
TitleListPreflight preflightTitleList(String text) {
  if (text.length > kMaxTitleListChars) {
    return TitleListPreflight._(
      const [],
      0,
      TitleListRejection.textTooLong,
      text.length,
    );
  }
  final lines = <TitleListLine>[];
  final seen = <String>{};
  var duplicates = 0;
  var distinct = 0;
  for (final raw in text.split('\n')) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.length > kMaxTitleLength) {
      lines.add(
        TitleListLine(trimmed, rejected: TitleListNotFoundReason.lineTooLong),
      );
      continue;
    }
    // Case-insensitive, first-occurrence-wins. A program may legitimately call
    // the same dance twice, which is why `parsePlaintextProgram` keeps
    // duplicates and this de-duplication lives out here instead: importing the
    // same dance twice is never useful, and searching for it twice is pure
    // waste against someone else's server.
    if (!seen.add(trimmed.toLowerCase())) {
      duplicates++;
      continue;
    }
    distinct++;
    lines.add(TitleListLine(trimmed));
  }
  if (distinct > kMaxTitleListTitles) {
    return TitleListPreflight._(
      const [],
      duplicates,
      TitleListRejection.tooManyTitles,
      distinct,
    );
  }
  return TitleListPreflight._(lines, duplicates, null, 0);
}

/// Outcome of [preflightTitleList].
class TitleListPreflight {
  const TitleListPreflight._(
    this.lines,
    this.duplicateLines,
    this.rejection,
    this.rejectionCount,
  );

  /// The bounded lines in paste order, or empty when [rejection] is non-null.
  final List<TitleListLine> lines;

  /// How many repeated lines were folded away.
  final int duplicateLines;

  /// Non-null when the whole paste is refused; [resolveTitleList] turns this
  /// into a [TitleListTooLargeException] before touching the network.
  final TitleListRejection? rejection;

  /// Characters or distinct titles, matching [rejection].
  final int rejectionCount;

  /// The titles that will actually be resolved (excludes over-long lines).
  List<String> get searchableTitles => [
    for (final l in lines)
      if (l.rejected == null) l.title,
  ];

  /// How many titles a resolution run would look up, at most. The real number is
  /// lower whenever a title is already in the local collection.
  int get resolvableCount => searchableTitles.length;
}

/// Resolves a pasted list of dance titles into a reviewable — and deliberately
/// **uncommitted** — import batch (issue #823).
///
/// Reuses the program importer's first two stages and skips its third:
///
/// 1. [parsePlaintextProgram] matches each title against the local collection;
/// 2. anything the collection does not have is looked up online with
///    [lookupUniqueExactTitle] and, on a unique exact hit, previewed into an
///    `ImportRecordPlan`;
/// 3. `buildProgramSlots` is **never** called — it is the only program-coupled
///    stage, and this flow has no program.
///
/// The critical difference from the program path is that **nothing is written
/// here**. `resolveConfidentOnlineDanceId` imports as it goes, because a program
/// line has no user watching; a Collection import does, so every plan is handed
/// to `ImportReviewScreen` and committed only on the user's confirmation, where
/// an ambiguous verdict already defaults to skip and can never silently
/// duplicate.
///
/// Requests are issued **one at a time** (matching the program flow), reporting
/// through [onProgress] as `(done, total)` and checking [isCancelled] between
/// titles, so a long batch is visible and abandonable rather than an opaque
/// wait. A fetch failure for one title becomes a
/// [TitleListNotFoundReason.fetchError] row and the rest of the batch proceeds.
///
/// Throws [TitleListTooLargeException] — before any network access — when the
/// paste trips a hard cap, and [TitleListCancelled] when [isCancelled] goes
/// true.
Future<TitleListResolution> resolveTitleList(
  String pastedText, {
  required OnlineSearchService service,
  required CompendiumRepositories repos,
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
  DateTime? now,
}) async {
  final pre = preflightTitleList(pastedText);
  final rejection = pre.rejection;
  if (rejection != null) {
    throw TitleListTooLargeException(rejection, pre.rejectionCount);
  }

  final collection = await repos.dances.listIdsAndTitles();
  // Stage 1, reused verbatim rather than reimplemented: the searchable titles
  // are already trimmed and non-blank, so re-joining them on newlines round-
  // trips exactly and `parsed[i]` lines up with `searchableTitles[i]`.
  final searchable = pre.searchableTitles;
  final parsed = parsePlaintextProgram(
    searchable.join('\n'),
    collection: collection,
  );
  assert(
    parsed.length == searchable.length,
    'preflight already trimmed and dropped blanks, so stage 1 must not drop '
    'any further lines',
  );

  // One DedupeIndex snapshot for the whole batch, exactly as ImportPipeline.plan
  // does for every other multi-record source. Without it each title would
  // rebuild the index — two full collection loads apiece.
  final pipeline = ImportPipeline(repos.dances, repos.choreographers);
  final index = await pipeline.buildDedupeIndex();

  final total = parsed
      .where((p) => p.resolution == PlaintextLineResolution.unmatched)
      .length;
  var done = 0;
  Map<String, String>? authorNamesById;

  final rows = <TitleListRow>[];
  final plans = <ImportRecordPlan>[];
  var cursor = 0;
  for (final line in pre.lines) {
    final rejected = line.rejected;
    if (rejected != null) {
      rows.add(TitleListRow.notFound(title: line.title, reason: rejected));
      continue;
    }
    final parsedLine = parsed[cursor++];
    switch (parsedLine.resolution) {
      case PlaintextLineResolution.matched:
        rows.add(
          TitleListRow.alreadyInCollection(
            title: parsedLine.text,
            count: 1,
            authors: await _authorNamesFor(
              parsedLine.danceId!,
              repos: repos,
              cache: () => authorNamesById,
              store: (m) => authorNamesById = m,
            ),
          ),
        );
      case PlaintextLineResolution.ambiguous:
        // Several local dances share this title, so she demonstrably owns it —
        // more than once. The count is the useful fact; listing every author
        // would be noise.
        rows.add(
          TitleListRow.alreadyInCollection(
            title: parsedLine.text,
            count: parsedLine.matchCount,
          ),
        );
      case PlaintextLineResolution.unmatched:
        if (isCancelled?.call() ?? false) throw const TitleListCancelled();
        onProgress?.call(done, total);
        rows.add(
          await _resolveOne(
            parsedLine.text,
            service: service,
            repos: repos,
            index: index,
            plans: plans,
            now: now,
          ),
        );
        done++;
    }
  }
  onProgress?.call(done, total);

  return TitleListResolution(
    batch: ImportBatchResult(records: plans, dedupeIndex: index),
    rows: rows,
    duplicateLines: pre.duplicateLines,
  );
}

/// Looks [title] up online and, on a unique exact hit, previews it into a plan
/// appended to [plans]. Never writes. Any [Exception] from the preview becomes a
/// [TitleListNotFoundReason.fetchError] row so one unreachable dance cannot
/// abort the batch; `Error`s (programmer bugs) still surface.
Future<TitleListRow> _resolveOne(
  String title, {
  required OnlineSearchService service,
  required CompendiumRepositories repos,
  required DedupeIndex index,
  required List<ImportRecordPlan> plans,
  DateTime? now,
}) async {
  final lookup = await lookupUniqueExactTitle(title, service: service);
  if (lookup is OnlineTitleMiss) {
    return TitleListRow.notFound(
      title: title,
      reason: switch (lookup.failure) {
        OnlineTitleLookupFailure.noResults => TitleListNotFoundReason.noResults,
        OnlineTitleLookupFailure.noExactMatch =>
          TitleListNotFoundReason.noExactMatch,
        OnlineTitleLookupFailure.multipleExactMatches =>
          TitleListNotFoundReason.multipleExactMatches,
        OnlineTitleLookupFailure.fetchError =>
          TitleListNotFoundReason.fetchError,
      },
    );
  }
  try {
    final preview = await service.loadPreview(
      repos,
      (lookup as OnlineTitleHit).row,
      now: now,
      index: index,
    );
    plans.add(preview.plan);
    return TitleListRow.toImport(title: title, planIndex: plans.length - 1);
  } on Exception catch (_) {
    return TitleListRow.notFound(
      title: title,
      reason: TitleListNotFoundReason.fetchError,
    );
  }
}

/// Choreographer names for the locally-matched dance [danceId], loading the
/// name map at most once per batch and only when some title actually matched
/// locally. Degrades to an empty list rather than failing the row: the author is
/// a disambiguating nicety, not the point of the row.
Future<List<String>> _authorNamesFor(
  String danceId, {
  required CompendiumRepositories repos,
  required Map<String, String>? Function() cache,
  required void Function(Map<String, String>) store,
}) async {
  try {
    final dance = await repos.dances.getById(danceId);
    if (dance == null || dance.authorIds.isEmpty) return const [];
    var names = cache();
    if (names == null) {
      names = {
        for (final a in await repos.choreographers.listAll()) a.id: a.name,
      };
      store(names);
    }
    return [
      for (final id in dance.authorIds)
        if (names[id] != null) names[id]!,
    ];
  } on Exception catch (_) {
    return const [];
  }
}
