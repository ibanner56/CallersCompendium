import 'package:compendium_core/compendium_core.dart';

import '../search/dance_detail_data.dart';
import 'import_io.dart';

/// What a direct online import ended up doing (drives the result snackbar).
enum CallersBoxImportKind {
  /// A brand-new dance was written to the collection.
  created,

  /// The exact Caller's Box dance was already imported before; nothing written.
  alreadyInCollection,
}

/// Outcome of [CallersBoxOnline.import].
class CallersBoxImportResult {
  const CallersBoxImportResult({
    required this.kind,
    required this.title,
    this.danceId,
    this.danceCount = 1,
  });

  final CallersBoxImportKind kind;
  final String title;

  /// Id of the imported dance for [CallersBoxImportKind.created], or the id of
  /// the existing matching dance for [CallersBoxImportKind.alreadyInCollection]
  /// when it can be resolved (an exact re-import carries its target id). `null`
  /// when no dance id is available (e.g. an unresolved already-in-collection).
  final String? danceId;

  /// Number of dances this import created or matched. Always `1` for the
  /// single-dance online-preview flow (it commits exactly one previewed dance).
  /// The UI auto-opens the imported dance ONLY when this is exactly `1`, so the
  /// "land on the imported dance" behavior can never fire for a multi-dance
  /// result — multi-dance batch/URL imports go through `ImportReviewScreen`,
  /// which keeps its result summary + Done affordance instead.
  final int danceCount;
}

/// User-facing snackbar message for an online import [result]. Shared by the
/// split-pane shell and the narrow-mode list so both report imports identically.
String callersBoxImportMessage(CallersBoxImportResult result) =>
    result.kind == CallersBoxImportKind.alreadyInCollection
    ? '"${result.title}" is already in your collection.'
    : 'Imported "${result.title}".';

/// A Caller's Box dance loaded for preview in the detail pane, plus the planned
/// import decision so the Import button can commit it without re-fetching.
class CallersBoxPreview {
  const CallersBoxPreview({
    required this.result,
    required this.detail,
    required this.plan,
  });

  final CallersBoxSearchResult result;

  /// Detail data for the (non-persisted) online dance, ready for
  /// `DanceDetailScreen.preview`.
  final DanceDetailData detail;

  /// The dedup-aware plan (draft + verdict) for this dance.
  final ImportRecordPlan plan;

  /// Whether the exact Caller's Box dance is already in the local collection
  /// (an exact `(source, externalId)` re-import match). The Import button uses
  /// this to short-circuit to an "already in your collection" message.
  bool get alreadyInCollection => plan.verdict.kind == DedupeKind.reimport;
}

/// App-layer orchestration for the **Caller's Box online search + direct import**
/// feature. Ties together the search transport ([CallersBoxSearchFetcher]), the
/// pure results parser ([parseCallersBoxSearchResults]), the per-dance JSON
/// fetch ([UrlFetcher]) + [CallersBoxAdapter] parse (via [ImportPipeline]), and
/// the dedup-aware commit.
///
/// I/O is injected via seams so widget/unit tests never touch the network:
/// [searchFetcher] returns canned results HTML and [jsonFetcher] returns canned
/// per-dance JSON.
class CallersBoxOnline {
  CallersBoxOnline({
    CallersBoxSearchFetcher? searchFetcher,
    UrlFetcher? jsonFetcher,
  }) : _searchFetcher = searchFetcher ?? fetchCallersBoxSearch,
       _jsonFetcher = jsonFetcher ?? fetchImportUrl;

  final CallersBoxSearchFetcher _searchFetcher;
  final UrlFetcher _jsonFetcher;

  /// Searches The Caller's Box by [title] and returns the parsed result rows.
  /// Throws a [UrlFetchException] (message safe to show) on any fetch failure.
  Future<List<CallersBoxSearchResult>> search(String title) async {
    final url = buildCallersBoxSearchUrl(title);
    final html = await _searchFetcher(url);
    return parseCallersBoxSearchResults(html);
  }

  /// Fetches the per-dance JSON for [result], parses it, and builds a
  /// [CallersBoxPreview] (detail data + dedupe plan). Throws a
  /// [UrlFetchException] on a fetch failure or when the dance can't be parsed.
  Future<CallersBoxPreview> loadPreview(
    CompendiumRepositories repos,
    CallersBoxSearchResult result, {
    DateTime? now,
  }) async {
    final jsonUrl = buildCallersBoxJsonUrl(result.id);
    final payload = await _jsonFetcher(jsonUrl);

    final pipeline = ImportPipeline(repos.dances, repos.choreographers);
    final batch = await pipeline.plan(
      CallersBoxAdapter(),
      ImportRequest(payload: payload, uri: jsonUrl),
    );
    if (batch.records.isEmpty) {
      final reason = batch.errors.isNotEmpty
          ? batch.errors.first.message
          : "The Caller's Box returned no importable dance.";
      throw UrlFetchException(reason);
    }

    final plan = batch.records.first;
    final detail = _detailFor(plan.draft, now: now ?? DateTime.now().toUtc());
    return CallersBoxPreview(result: result, detail: detail, plan: plan);
  }

  /// Commits [plan] into the local collection using the dedup-aware default:
  /// - a brand-new dance is created;
  /// - an exact re-import match is reported as already-in-collection (nothing
  ///   written — no silent duplicate);
  /// - a fuzzy near-match is imported as a new dance (the user explicitly asked
  ///   for this Caller's Box dance).
  ///
  /// This is a strictly SINGLE-dance import (one previewed [plan]); the returned
  /// [CallersBoxImportResult.danceCount] reflects that so the UI can guard its
  /// "land on the imported dance" behavior on a single-dance import. Multi-dance
  /// batch/URL imports are not handled here — they go through the
  /// [ImportPipeline] + `ImportReviewScreen` report flow.
  Future<CallersBoxImportResult> import(
    CompendiumRepositories repos,
    ImportRecordPlan plan, {
    DateTime? now,
  }) async {
    final title = plan.draft.dance.title;
    if (plan.verdict.kind == DedupeKind.reimport) {
      return CallersBoxImportResult(
        kind: CallersBoxImportKind.alreadyInCollection,
        title: title,
        // The exact re-import verdict carries the existing dance's id so the UI
        // can open it in the detail pane instead of leaving the user to hunt.
        danceId: plan.verdict.targetDanceId,
        danceCount: 1,
      );
    }

    final resolutions = plan.verdict.kind == DedupeKind.ambiguous
        ? {0: DedupeResolution.duplicate()}
        : const <int, DedupeResolution>{};

    final pipeline = ImportPipeline(repos.dances, repos.choreographers);
    final session = await pipeline.commit(
      ImportBatchResult(records: [plan]),
      now: now ?? DateTime.now().toUtc(),
      newId: uuidV4,
      resolutions: resolutions,
    );

    // A single-record batch: surface a failed/skipped commit as a user-safe
    // error instead of letting `firstWhere` throw an opaque StateError.
    final record = session.records.first;
    if (!record.succeeded || record.danceId == null) {
      throw UrlFetchException(
        record.error?.message ?? "The Caller's Box dance couldn't be imported.",
      );
    }
    return CallersBoxImportResult(
      kind: CallersBoxImportKind.created,
      title: title,
      danceId: record.danceId,
      // Committed exactly this one previewed dance (single-record batch).
      danceCount: session.committedCount,
    );
  }

  /// Builds [DanceDetailData] for a non-persisted online dance from its parsed
  /// [draft]. Collection-only associations (related dances, cited sources,
  /// calling history, cross-reference linking) are empty. A synthetic Caller's
  /// Box [Provenance] is attached so the detail's provenance line shows the
  /// "via The Caller's Box" attribution (the pipeline only attaches provenance
  /// at commit, so the parsed dance carries none yet).
  DanceDetailData _detailFor(StructuredDraft draft, {required DateTime now}) {
    final raw = draft.raw;
    final dance = draft.dance.copyWith(
      provenance: Provenance(
        source: raw.source,
        externalId: raw.externalId,
        importedAt: now,
        permission: raw.permission,
        license: raw.license,
      ),
    );
    return DanceDetailData(
      dance: dance,
      authorNames: const [],
      tagNames: const [],
      customFields: const [],
      relatedDanceTitles: const {},
      sourcesById: const {},
      callingHistory: const [],
      crossRefLinker: DanceTitleLinker.build(const [], excludeId: ''),
    );
  }
}
