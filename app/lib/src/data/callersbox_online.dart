import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

import '../search/dance_detail_data.dart';
import 'import_io.dart';
import 'online_search.dart';

/// App-layer orchestration for the **Caller's Box online search + direct import**
/// feature. Ties together the search transport ([CallersBoxSearchFetcher]), the
/// pure results parser ([parseCallersBoxSearchResults]), the per-dance JSON
/// fetch ([UrlFetcher]) + [CallersBoxAdapter] parse (via [ImportPipeline]), and
/// the dedup-aware commit.
///
/// Implements the source-neutral [OnlineSearchService] so the screen / shell can
/// drive it interchangeably with `ContraDbOnline`; the outcome and preview types
/// ([OnlineImportResult] / [OnlinePreview]) are shared across sources.
///
/// I/O is injected via seams so widget/unit tests never touch the network:
/// [searchFetcher] returns canned results HTML and [jsonFetcher] returns canned
/// per-dance JSON.
class CallersBoxOnline implements OnlineSearchService {
  CallersBoxOnline({
    CallersBoxSearchFetcher? searchFetcher,
    UrlFetcher? jsonFetcher,
  }) : _searchFetcher = searchFetcher ?? fetchCallersBoxSearch,
       _jsonFetcher = jsonFetcher ?? fetchImportUrl;

  final CallersBoxSearchFetcher _searchFetcher;
  final UrlFetcher _jsonFetcher;

  @override
  OnlineSource get source => OnlineSource.callersBox;

  /// Searches The Caller's Box by [OnlineSearchQuery.title] and/or by-phrase
  /// figure [OnlineSearchQuery.phrases] and returns the parsed result rows.
  /// Title and phrase criteria combine (TCB accepts both in one request). Throws
  /// a typed [UrlFetchException] on any fetch failure, or when
  /// there is nothing to search.
  @override
  Future<List<OnlineSearchResultRow>> search(OnlineSearchQuery query) async {
    final url = buildCallersBoxSearchUrl(query.title, phrases: query.phrases);
    final html = await _searchFetcher(url);
    return [
      for (final r in parseCallersBoxSearchResults(html))
        OnlineSearchResultRow(
          source: OnlineSource.callersBox,
          id: r.id,
          name: r.name,
          author: r.author,
          formation: r.formation,
        ),
    ];
  }

  /// Fetches the per-dance JSON for [result], parses it, and builds an
  /// [OnlinePreview] (detail data + dedupe plan). Throws a [UrlFetchException]
  /// on a fetch failure or when the dance can't be parsed.
  @override
  Future<OnlinePreview> loadPreview(
    CompendiumRepositories repos,
    OnlineSearchResultRow result, {
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
      // Never echo the lower-layer parse error into the UI (CWE-209); keep it
      // for debug logging only and surface a generic localized reason.
      if (kDebugMode && batch.errors.isNotEmpty) {
        debugPrint("Caller's Box import parse failed: ${batch.errors.first}");
      }
      throw const UrlFetchException(
        UrlFetchFailureReason.callersBoxNoImportableDance,
      );
    }

    final plan = batch.records.first;
    final detail = _detailFor(plan.draft, now: now ?? DateTime.now().toUtc());
    return OnlinePreview(result: result, detail: detail, plan: plan);
  }

  /// Commits [plan] into the local collection using the dedup-aware default:
  /// - a brand-new dance is created;
  /// - an exact re-import match is reported as already-in-collection (nothing
  ///   written — no silent duplicate);
  /// - a fuzzy near-match is imported as a new dance (the user explicitly asked
  ///   for this Caller's Box dance).
  ///
  /// This is a strictly SINGLE-dance import (one previewed [plan]); the returned
  /// [OnlineImportResult.danceCount] reflects that so the UI can guard its
  /// "land on the imported dance" behavior on a single-dance import.
  @override
  Future<OnlineImportResult> import(
    CompendiumRepositories repos,
    ImportRecordPlan plan, {
    DateTime? now,
  }) async {
    final title = plan.draft.dance.title;
    if (plan.verdict.kind == DedupeKind.reimport) {
      return OnlineImportResult(
        kind: OnlineImportKind.alreadyInCollection,
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
      // Keep the raw commit error for debug logging only; the UI gets a generic
      // localized message so no lower-layer detail leaks (CWE-209).
      if (kDebugMode && record.error != null) {
        debugPrint("Caller's Box import commit failed: ${record.error}");
      }
      throw const UrlFetchException(
        UrlFetchFailureReason.callersBoxImportFailed,
      );
    }
    return OnlineImportResult(
      kind: OnlineImportKind.created,
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
