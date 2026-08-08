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

  /// Largest stated match count for which [search] will re-request the complete
  /// result set with `show_all`.
  ///
  /// TCB caps a normal response at 50 rows. Filtering that capped page would
  /// hide matches the user never learns exist, so the full set is fetched
  /// instead — but only when it is small enough to be worth the payload.
  ///
  /// Derived from measurement, not taste. The delta between `?title=moon` and
  /// `?title=moon&show_all` is ~238 B per extra row on top of ~13 KB of page
  /// chrome, so 500 rows is roughly 120 KB. Broad queries are far past that:
  /// measured live, `?title=a` states **12,805** matches (~3.0 MB) and the
  /// by-phrase `balance` search states 10,287. Online search runs on a 500 ms
  /// as-you-type debounce, so an unconditional `show_all` would fire requests
  /// of that size repeatedly at a volunteer-run host while the user is still
  /// typing.
  ///
  /// Above this limit the capped page is filtered as-is. That truncation is not
  /// introduced here — such a query is already showing 50 of many thousands —
  /// but it is compounded by filtering, and the app does not yet say so. See
  /// issue #845.
  static const int showAllMatchLimit = 500;

  @override
  OnlineSource get source => OnlineSource.callersBox;

  /// Searches The Caller's Box by [OnlineSearchQuery.title] and/or by-phrase
  /// figure [OnlineSearchQuery.phrases] and returns the parsed result rows.
  /// Title and phrase criteria combine (TCB accepts both in one request). Throws
  /// a typed [UrlFetchException] on any fetch failure, or when
  /// there is nothing to search.
  ///
  /// Rows whose figures TCB will not serve are excluded unless the caller sets
  /// [OnlineSearchQuery.requireFigures] to `false` (issue #845). TCB's
  /// non-`full` permission tiers mean a dance imports as a metadata-only stub —
  /// title, formation, notes, no figures — which is almost never what a dance
  /// search was for, and is at its worst on a by-phrase search, where the user
  /// searched *by a figure* the result will then refuse to show. Roughly 31% of
  /// a live result set is affected (measured on `?title=moon&show_all`).
  ///
  /// The exclusion is a **search** policy only. Importing such a dance by its
  /// direct URL still works and still produces the stub with its
  /// `callersbox_search_tier` warning — [CallersBoxAdapter] is untouched.
  ///
  /// So that filtering cannot compound TCB's 50-row cap by shrinking an already
  /// truncated page, the search is **two-phase**: the normal request states the
  /// full match total, and when that total exceeds what came back but stays
  /// within [showAllMatchLimit], the complete set is re-requested with
  /// `show_all`. A missing or unreadable total simply skips the second request.
  @override
  Future<List<OnlineSearchResultRow>> search(OnlineSearchQuery query) async {
    final url = buildCallersBoxSearchUrl(query.title, phrases: query.phrases);
    var html = await _searchFetcher(url);
    var rows = parseCallersBoxSearchResults(html);

    final total = parseCallersBoxMatchCount(html);
    if (total != null && total > rows.length && total <= showAllMatchLimit) {
      final allUrl = buildCallersBoxSearchUrl(
        query.title,
        phrases: query.phrases,
        showAll: true,
      );
      html = await _searchFetcher(allUrl);
      rows = parseCallersBoxSearchResults(html);
    }

    return [
      for (final r in rows)
        if (r.figuresAvailable || !query.requireFigures)
          OnlineSearchResultRow(
            source: OnlineSource.callersBox,
            id: r.id,
            name: r.name,
            author: r.author,
            formation: r.formation,
            figuresAvailable: r.figuresAvailable,
          ),
    ];
  }

  /// Fetches the per-dance JSON for [result], parses it, and builds an
  /// [OnlinePreview] (detail data + dedupe plan). Throws a [UrlFetchException]
  /// on a fetch failure or when the dance can't be parsed. Pass [index] to plan
  /// against a shared `DedupeIndex` snapshot instead of building a fresh one
  /// (see [OnlineSearchService.loadPreview]).
  @override
  Future<OnlinePreview> loadPreview(
    CompendiumRepositories repos,
    OnlineSearchResultRow result, {
    DateTime? now,
    DedupeIndex? index,
  }) async {
    final jsonUrl = buildCallersBoxJsonUrl(result.id);
    final payload = await _jsonFetcher(jsonUrl);

    final pipeline = ImportPipeline(repos.dances, repos.choreographers);
    final batch = await pipeline.plan(
      CallersBoxAdapter(),
      ImportRequest(payload: payload, uri: jsonUrl),
      index: index,
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
  /// - a fuzzy near-match with a confident title+author candidate and differing
  ///   figures returns [OnlineImportKind.needsConfirmation] (nothing written)
  ///   so the caller can show a resolution dialog (issue #797);
  /// - a fuzzy near-match with a confident title+author candidate,
  ///   **canonically identical** figures (same moves and order; beats and notes
  ///   may differ), and a confirmed different source returns
  ///   [OnlineImportKind.needsConfirmationIdentical] (nothing written) so the
  ///   caller can show a cross-source duplicate dialog (issue #811); dances with
  ///   null provenance (hand-entered) fall through to the next case rather than
  ///   being falsely labelled "from a different source";
  /// - any other fuzzy near-match is imported as a new dance (the user
  ///   explicitly asked for this Caller's Box dance).
  ///
  /// Pass [ambiguousResolution] to skip the needsConfirmation check and commit
  /// immediately with the given resolution (used on the retry after the dialog).
  ///
  /// This is a strictly SINGLE-dance import (one previewed [plan]); the returned
  /// [OnlineImportResult.danceCount] reflects that so the UI can guard its
  /// "land on the imported dance" behavior on a single-dance import.
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
        // The exact re-import verdict carries the existing dance's id so the UI
        // can open it in the detail pane instead of leaving the user to hunt.
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
