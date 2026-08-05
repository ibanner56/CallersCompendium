import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

import '../search/dance_detail_data.dart';
import 'import_io.dart';
import 'online_search.dart';

/// App-layer orchestration for the **ContraDB online search + direct import**
/// feature. The ContraDB parallel to `CallersBoxOnline`: it ties together the
/// JSON search transport ([ContraDbSearchFetcher]), the pure results parser
/// ([parseContraDbSearchResults]), the per-dance HTML fetch ([UrlFetcher]) +
/// [ContraDbHtmlAdapter] parse (via [ImportPipeline]), and the dedup-aware
/// commit.
///
/// Implements the source-neutral [OnlineSearchService] so the screen / shell can
/// drive it interchangeably with `CallersBoxOnline`.
///
/// Two transport differences from the Caller's Box flow:
/// - **search** is an HTTP POST with a JSON body (ContraDB's `/api/v1/dances`),
///   not a GET — handled by [fetchContraDbSearch]. ContraDB search is title-only
///   ([OnlineSource.contraDb] has `supportsByPhrase == false`), so
///   [OnlineSearchQuery.phrases] is ignored.
/// - **import** reuses the EXISTING `contradb.com/dances/{id}` HTML-scrape path
///   ([buildContraDbUrl] + [ContraDbHtmlAdapter]); ContraDB serves no per-dance
///   JSON. The search result's id bridges search→import.
///
/// I/O is injected via seams so widget/unit tests never touch the network:
/// [searchFetcher] returns canned results JSON and [htmlFetcher] returns canned
/// per-dance HTML.
class ContraDbOnline implements OnlineSearchService {
  ContraDbOnline({
    ContraDbSearchFetcher? searchFetcher,
    UrlFetcher? htmlFetcher,
  }) : _searchFetcher = searchFetcher ?? fetchContraDbSearch,
       _htmlFetcher = htmlFetcher ?? fetchImportUrl;

  final ContraDbSearchFetcher _searchFetcher;
  final UrlFetcher _htmlFetcher;

  @override
  OnlineSource get source => OnlineSource.contraDb;

  /// Searches ContraDB by [OnlineSearchQuery.title] (case-insensitive substring
  /// match, server side) and returns the parsed result rows. Throws a
  /// typed [UrlFetchException] on any fetch failure, or when
  /// there is nothing to search.
  @override
  Future<List<OnlineSearchResultRow>> search(OnlineSearchQuery query) async {
    final title = query.title.trim();
    if (title.isEmpty) {
      throw const UrlFetchException(UrlFetchFailureReason.contraDbEmptyTitle);
    }
    final body = await _searchFetcher(title);
    return [
      for (final r in parseContraDbSearchResults(body))
        OnlineSearchResultRow(
          source: OnlineSource.contraDb,
          id: r.id,
          name: r.name,
          author: r.author,
          formation: r.formation,
        ),
    ];
  }

  /// Fetches the per-dance HTML for [result], parses it with
  /// [ContraDbHtmlAdapter], and builds an [OnlinePreview] (detail data + dedupe
  /// plan). Throws a [UrlFetchException] on a fetch failure or when the dance
  /// can't be parsed. Pass [index] to plan against a shared `DedupeIndex`
  /// snapshot instead of building a fresh one (see
  /// [OnlineSearchService.loadPreview]).
  @override
  Future<OnlinePreview> loadPreview(
    CompendiumRepositories repos,
    OnlineSearchResultRow result, {
    DateTime? now,
    DedupeIndex? index,
  }) async {
    final url = buildContraDbUrl(result.id);
    final payload = await _htmlFetcher(url);

    final pipeline = ImportPipeline(repos.dances, repos.choreographers);
    final batch = await pipeline.plan(
      ContraDbHtmlAdapter(),
      ImportRequest(payload: payload, uri: url),
      index: index,
    );
    if (batch.records.isEmpty) {
      // Never echo the lower-layer parse error into the UI (CWE-209); keep it
      // for debug logging only and surface a generic localized reason.
      if (kDebugMode && batch.errors.isNotEmpty) {
        debugPrint('ContraDB import parse failed: ${batch.errors.first}');
      }
      throw const UrlFetchException(
        UrlFetchFailureReason.contraDbNoImportableDance,
      );
    }

    final plan = batch.records.first;
    final detail = _detailFor(plan.draft, now: now ?? DateTime.now().toUtc());
    return OnlinePreview(result: result, detail: detail, plan: plan);
  }

  /// Commits [plan] into the local collection using the dedup-aware default
  /// (identical policy to [CallersBoxOnline.import]): a brand-new dance is
  /// created; an exact re-import match is reported as already-in-collection
  /// (nothing written); a fuzzy near-match with a confident title+author
  /// candidate and differing figures returns
  /// [OnlineImportKind.needsConfirmation] (nothing written) so the caller can
  /// show a resolution dialog (issue #797); a fuzzy near-match with a confident
  /// title+author candidate, **canonically identical** figures (same moves and
  /// order; beats and notes may differ), and a confirmed different source
  /// returns [OnlineImportKind.needsConfirmationIdentical] (nothing written) so
  /// the caller can show a cross-source duplicate dialog (issue #811); dances
  /// with null provenance fall through rather than being falsely labelled "from
  /// a different source"; any other fuzzy near-match is imported as a new dance.
  ///
  /// Pass [ambiguousResolution] to skip the needsConfirmation check and commit
  /// immediately with the given resolution (used on the retry after the dialog).
  ///
  /// This is a strictly SINGLE-dance import (one previewed [plan]); the returned
  /// [OnlineImportResult.danceCount] reflects that.
  @override
  Future<OnlineImportResult> import(
    CompendiumRepositories repos,
    ImportRecordPlan plan, {
    DateTime? now,
    DedupeResolution? ambiguousResolution,
  }) async {
    final title = plan.draft.dance.title;
    if (plan.verdict.kind == DedupeKind.reimport) {
      return OnlineImportResult(
        kind: OnlineImportKind.alreadyInCollection,
        title: title,
        danceId: plan.verdict.targetDanceId,
        danceCount: 1,
      );
    }

    // When the verdict is ambiguous and a confident candidate exists, check
    // whether the figures differ. If they do and no resolution has been
    // supplied yet, return needsConfirmation so the caller can prompt the user
    // before writing anything (issue #797). Mirrors the detection in
    // program_import_online_resolver.dart:resolveConfidentOnlineDanceId.
    if (ambiguousResolution == null &&
        plan.verdict.kind == DedupeKind.ambiguous &&
        plan.verdict.hasConfidentMatch) {
      final candidateId = plan.verdict.candidates
          .firstWhere((c) => c.confident)
          .danceId;
      final existing = await repos.dances.getById(candidateId);
      if (existing != null) {
        final identical = figuresCanonicallyIdentical(
          oldFigures: existing.figures,
          newFigures: plan.draft.dance.figures,
          taxonomy: contraTaxonomy,
        );
        if (!identical) {
          return OnlineImportResult(
            kind: OnlineImportKind.needsConfirmation,
            title: title,
            danceId: candidateId,
            danceCount: 1,
          );
        } else if (existing.provenance?.source != null &&
            plan.draft.raw.source != existing.provenance!.source) {
          // Canonically identical figures (same moves and order; beats and
          // notes may differ) from a confirmed different source: prompt the
          // user instead of silently creating a second copy (issue #811).
          // Condition guards are:
          //   - existing.provenance.source != null: skip hand-entered dances
          //     (null provenance) so we never claim they are "from a different
          //     source".
          //   - sources differ: a same-source re-import with a drifted
          //     externalId stays silent (DedupeResolution.duplicate() below).
          return OnlineImportResult(
            kind: OnlineImportKind.needsConfirmationIdentical,
            title: title,
            danceId: candidateId,
            danceCount: 1,
          );
        }
      }
    }

    final resolutions = plan.verdict.kind == DedupeKind.ambiguous
        ? {0: ambiguousResolution ?? DedupeResolution.duplicate()}
        : const <int, DedupeResolution>{};

    final pipeline = ImportPipeline(repos.dances, repos.choreographers);
    final session = await pipeline.commit(
      ImportBatchResult(records: [plan]),
      now: now ?? DateTime.now().toUtc(),
      newId: uuidV4,
      resolutions: resolutions,
    );

    final record = session.records.first;
    if (!record.succeeded || record.danceId == null) {
      // Keep the raw commit error for debug logging only; the UI gets a generic
      // localized message so no lower-layer detail leaks (CWE-209).
      if (kDebugMode && record.error != null) {
        debugPrint('ContraDB import commit failed: ${record.error}');
      }
      throw const UrlFetchException(UrlFetchFailureReason.contraDbImportFailed);
    }
    return OnlineImportResult(
      kind: OnlineImportKind.created,
      title: title,
      danceId: record.danceId,
      danceCount: session.committedCount,
    );
  }

  /// Builds [DanceDetailData] for a non-persisted online dance from its parsed
  /// [draft], attaching a synthetic ContraDB [Provenance] so the detail's
  /// provenance line shows the "via ContraDB" attribution (the pipeline only
  /// attaches provenance at commit, so the parsed dance carries none yet).
  /// Mirrors [CallersBoxOnline]'s detail builder.
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
