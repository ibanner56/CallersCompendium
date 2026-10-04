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
///   not a GET — handled by [fetchContraDbSearch]. ContraDB supports title,
///   choreographer, and figure filters but has no by-phrase API, so
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
  }) : _searchFetcher =
           searchFetcher ??
           ((request) =>
               fetchContraDbSearch(request.query, filter: request.filter)),
       _htmlFetcher = htmlFetcher ?? fetchImportUrl;

  final ContraDbSearchFetcher _searchFetcher;
  final UrlFetcher _htmlFetcher;

  @override
  OnlineSource get source => OnlineSource.contraDb;

  /// Searches ContraDB by the selected title, author, or exact canonical figure
  /// criterion and returns the parsed result rows. Figure input accepts
  /// case/whitespace variants and is resolved to ContraDB's source spelling
  /// before the request. Throws a typed [UrlFetchException] on any fetch
  /// failure, unsupported Figure input, or when there is nothing to search.
  @override
  Future<List<OnlineSearchResultRow>> search(OnlineSearchQuery query) async {
    final title = query.title.trim();
    final author = query.author.trim();
    final figure = query.figure.trim();
    final canonicalFigure = figure.isEmpty
        ? null
        : canonicalContraDbFigureQuery(figure);
    final textCriteria = [
      title,
      author,
      figure,
    ].where((criterion) => criterion.isNotEmpty).length;
    if (textCriteria > 1) {
      throw ArgumentError('title, author, and figure cannot be combined');
    }
    if (figure.isNotEmpty && canonicalFigure == null) {
      throw const UrlFetchException(
        UrlFetchFailureReason.contraDbUnsupportedFigure,
      );
    }
    if (title.isEmpty && author.isEmpty && figure.isEmpty) {
      throw const UrlFetchException(UrlFetchFailureReason.contraDbEmptyTitle);
    }
    final queryText = title.isNotEmpty
        ? title
        : author.isNotEmpty
        ? author
        : canonicalFigure!;
    final filter = title.isNotEmpty
        ? 'title'
        : author.isNotEmpty
        ? 'choreographer'
        : 'figure';
    final body = await _searchFetcher(
      ContraDbSearchRequest(query: queryText, filter: filter),
    );
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

    final pipeline = ImportPipeline(
      repos.dances,
      repos.choreographers,
      difficultyLevels: repos.difficultyLevels,
    );
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
  /// The policy lives in [commitPreviewedOnlinePlan], including the rule that an
  /// undecodable transcription never compares as identical (#1347).
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
    List<String> defaultTagIds = const [],
  }) async {
    // The commit flow (reimport / needs-confirmation / unreadable-figures
    // guard / pipeline commit) is shared with the other online source.
    return commitPreviewedOnlinePlan(
      repos,
      plan,
      now: now,
      ambiguousResolution: ambiguousResolution,
      defaultTagIds: defaultTagIds,
      importFailedReason: UrlFetchFailureReason.contraDbImportFailed,
      debugLabel: 'ContraDB',
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
      crossRefLinker: DanceTitleLinker.build(const [], excludeId: ''),
    );
  }
}
