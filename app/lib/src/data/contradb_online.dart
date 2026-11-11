import 'dart:convert';

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
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _searchFetcher =
           searchFetcher ??
           ((request) => fetchContraDbSearch(
             request.query,
             filter: request.filter,
             expression: request.expression,
             offset: request.offset,
           )),
       _htmlFetcher = htmlFetcher ?? fetchImportUrl;

  final ContraDbSearchFetcher _searchFetcher;
  final UrlFetcher _htmlFetcher;
  final DateTime Function() _clock;

  /// How long the last successful search answers an identical request without
  /// asking ContraDB again. ContraDB scans every dance for each request, so a
  /// repeat (an Advanced edit that did not change the expression sent, a page
  /// scrolled back to) should not cost one.
  static const Duration _repeatWindow = Duration(seconds: 60);

  String? _lastKey;
  DateTime? _lastAt;
  List<OnlineSearchResultRow> _lastRows = const [];

  @override
  OnlineSource get source => OnlineSource.contraDb;

  /// Searches ContraDB by the selected title, author, or exact canonical figure
  /// criterion and/or the Advanced builder's figure query ([OnlineSearchQuery.advanced]),
  /// and returns the parsed result rows. A text criterion with an Advanced query
  /// is sent as one `and` expression. Figure input accepts
  /// case/whitespace variants and is resolved to ContraDB's source spelling
  /// before the request. Title and author text containing an apostrophe or
  /// double quote is searched in both its ASCII and its curly spelling
  /// ([contraDbTitleQueryVariants]) — two requests — and the rows are merged
  /// by id; a failure of the curly request alone is ignored. Throws a typed
  /// [UrlFetchException] on any other fetch
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
    final translation = _advancedTranslation(query.advanced);
    final advanced = translation?.expression;
    final hasText = textCriteria == 1;
    if (!hasText && advanced == null) {
      throw const UrlFetchException(UrlFetchFailureReason.contraDbEmptyTitle);
    }
    final queryText = title.isNotEmpty
        ? title
        : author.isNotEmpty
        ? author
        : (canonicalFigure ?? '');
    final filter = title.isNotEmpty
        ? 'title'
        : author.isNotEmpty
        ? 'choreographer'
        : 'figure';
    // ContraDB matches punctuation exactly and stores both `'` and `’` (and
    // both `"` and `“”`), so free text is sent in each spelling and the
    // results merged. A figure is already its canonical source spelling.
    final variants = !hasText
        ? [queryText]
        : filter == 'figure'
        ? [queryText]
        : contraDbTitleQueryVariants(queryText);
    // A text criterion and the Advanced filter must both hold, which is
    // ContraDB's dance-level `and`; either alone is sent as it is.
    ContraDbSearchRequest requestFor(String variant) {
      if (advanced == null) {
        return ContraDbSearchRequest(
          query: variant,
          filter: filter,
          offset: query.offset,
        );
      }
      if (!hasText) {
        return ContraDbSearchRequest.expression(advanced, offset: query.offset);
      }
      return ContraDbSearchRequest.expression(<Object?>[
        'and',
        <Object?>[filter, variant],
        advanced,
      ], offset: query.offset);
    }

    // The same request again, soon after it was answered: answer from that.
    // The parameters the translation left out are part of the key: they change
    // no expression sent, but they decide the rows' `advancedPartlyApplied`, so
    // an edit to only such a parameter must not be answered with the old flag.
    final key = jsonEncode([
      [
        for (final variant in variants)
          () {
            final request = requestFor(variant);
            return [
              request.filter,
              request.query,
              request.expression,
              request.offset,
            ];
          }(),
      ],
      (translation?.ignoredParams.toList() ?? <String>[])..sort(),
    ]);
    final lastAt = _lastAt;
    if (key == _lastKey &&
        lastAt != null &&
        _clock().difference(lastAt) < _repeatWindow) {
      return List.of(_lastRows);
    }

    Future<String> fetch(String variant) => _searchFetcher(requestFor(variant));
    // On the first page only the first (ASCII) spelling decides whether the
    // search failed. The curly spelling is a widening: if it alone fails, the
    // search returns what it would have returned before that spelling was sent
    // at all. A later page cannot do that: both spellings are paged at the same
    // offset, so a page that lost one would be counted as loaded and the
    // missing spelling's rows at that offset would never be asked for again.
    // There a failed spelling fails the page, and the caller shows Try again.
    final firstPage = query.offset == 0;
    Future<String?> widen(String variant) async {
      if (!firstPage) return fetch(variant);
      try {
        return await fetch(variant);
      } on Exception {
        // diagnostics: silent — optional widening request; the primary request's own failure still surfaces to the caller
        return null;
      }
    }

    final bodies = await Future.wait<String?>([
      fetch(variants.first),
      for (final variant in variants.skip(1)) widen(variant),
    ]);
    final pages = [
      for (final body in bodies.nonNulls) parseContraDbSearchResults(body),
    ];
    // A response that came back with a whole page may have been cut off. This
    // is judged per response: the merged count of two short pages (the two
    // spellings of an apostrophe query) says nothing about either being full.
    final mayHaveMore = pages.any((page) => page.length >= contraDbSearchCount);
    // The source's own total, only when a single response answered: two
    // spelling variants may both count a dance that matches either, so their
    // totals cannot be added.
    final totalMatching = bodies.nonNulls.length == 1
        ? parseContraDbNumberMatching(bodies.nonNulls.single)
        : null;
    final seenIds = <String>{};
    final rows = [
      for (final page in pages)
        for (final r in page)
          if (seenIds.add(r.id))
            OnlineSearchResultRow(
              source: OnlineSource.contraDb,
              id: r.id,
              name: r.name,
              author: r.author,
              formation: r.formation,
              mayHaveMore: mayHaveMore,
              totalMatching: totalMatching,
              advancedPartlyApplied:
                  translation?.ignoredParams.isNotEmpty ?? false,
            ),
    ];
    // Each response is already title-sorted; re-sort only a merged set, by
    // titleMatchKey so `’` and `'` titles interleave rather than group. The
    // id tie-break makes equal titles deterministic (List.sort is unstable).
    if (bodies.nonNulls.length > 1) {
      rows.sort((a, b) {
        final byTitle = titleMatchKey(a.name).compareTo(titleMatchKey(b.name));
        return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
      });
    }
    // A search whose extra spelling failed answered less than it should, so it
    // is not remembered: the repeat asks for that spelling again.
    if (bodies.nonNulls.length == variants.length) {
      _lastKey = key;
      _lastAt = _clock();
      _lastRows = List.of(rows);
    }
    return rows;
  }

  /// The ContraDB filter for the Advanced builder's [filter], or `null` when it
  /// has none. Throws [UrlFetchFailureReason.contraDbUnsupportedAdvanced] when it
  /// holds a condition ContraDB cannot express with the same meaning
  /// ([translateDanceFilterToContraDb]); the search is refused rather than
  /// sent with that condition dropped, which would return a wider result set
  /// than the panel describes. The exception is a figure parameter with no
  /// ContraDB counterpart: it is left out and reported in
  /// [ContraDbAdvancedExpression.ignoredParams], carried on the rows as
  /// `advancedPartlyApplied`.
  static ContraDbAdvancedExpression? _advancedTranslation(DanceFilter? filter) {
    if (filter == null) return null;
    return switch (translateDanceFilterToContraDb(filter)) {
      final ContraDbAdvancedExpression expression => expression,
      ContraDbAdvancedRefused() => throw const UrlFetchException(
        UrlFetchFailureReason.contraDbUnsupportedAdvanced,
      ),
    };
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
  /// (identical policy to [CallersBoxOnline.import]): a dance that matches
  /// nothing is created; an exact re-import match is reported as already-in-collection
  /// (nothing written); a fuzzy near-match with a confident title+author
  /// candidate and differing figures returns
  /// [OnlineImportKind.needsConfirmation] (nothing written) so the caller can
  /// show a resolution dialog (issue #797); a fuzzy near-match with a confident
  /// title+author candidate, **canonically identical** figures (same moves and
  /// order; beats and notes may differ), and either a different source or a
  /// hand-entered existing dance returns
  /// [OnlineImportKind.needsConfirmationIdentical] (nothing written) so the
  /// caller can show the duplicate dialog (issue #811; INTAKE-5); with no
  /// confident candidate, a possible match under
  /// another title returns [OnlineImportKind.needsPossibleMatchChoice]
  /// (nothing written, issue #1907); any other fuzzy near-match is imported as
  /// a new dance.
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
