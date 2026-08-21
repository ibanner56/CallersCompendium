import 'package:compendium_core/compendium_core.dart';

import 'online_search.dart';
import 'online_title_lookup.dart';
import 'plaintext_program_import.dart';

/// Resolves the `unmatched` lines of a parsed plaintext program against an
/// ordered chain of online sources — The Caller's Box first (epic #291,
/// sub-issue #313), then any [fallbacks] in order (issue #943, e.g. ContraDB) —
/// stopping at the first source that resolves a line confidently.
///
/// For each [PlaintextLineResolution.unmatched] line, each source in turn (see
/// [_resolveLineAcrossSources]) is asked to [OnlineSearchService.search] by the
/// line's title. A line is only auto-linked on a **confident match** — a
/// UNIQUE exact-title hit: exactly one result whose
/// [OnlineSearchResultRow.name] equals the line text (trimmed,
/// case-insensitive) — from whichever source produces one first. On such a hit
/// the dance is imported via [OnlineSearchService.loadPreview] +
/// [OnlineSearchService.import] and the returned dance id is linked into the
/// slot (a fresh [PlaintextLineResolution.matched] line with
/// [ParsedProgramLine.importedOnline] set), and no further source is tried.
///
/// A source that finds no confident match does not necessarily end the
/// search — see [_resolveLineAcrossSources] for the exact per-source outcomes
/// and which of them stop the chain versus advance to the next source.
///
/// Anything that exhausts every source preserves the sub-issue #312 note-slot
/// fallback and returns the line unchanged, except that a line **any** source
/// found several exact-title hits for (and no source ever resolved
/// confidently) carries those hits in [ParsedProgramLine.onlineCandidates] so
/// the caller can offer a review step instead of a plain note (issue #943).
/// This does not require more than one source to be ambiguous: a title that
/// is ambiguous on Caller's Box and simply misses on ContraDB still carries
/// Caller's Box's candidates.
///
/// Non-`unmatched` lines (local `matched` / `ambiguous`) pass through untouched:
/// online resolution only fills the gap where the local collection had nothing.
///
/// Only a single search fetch per title *per source* and a single JSON fetch
/// per confident import are performed — no crawling (import fidelity rule).
/// Sources are tried strictly one at a time, sequentially, with no delay
/// between them (issue #943's ruling on network cost: reuse the existing
/// pacing, which is none).
Future<List<ParsedProgramLine>> resolveUnmatchedOnline(
  List<ParsedProgramLine> lines, {
  required OnlineSearchService service,
  List<OnlineSearchService> fallbacks = const [],
  required CompendiumRepositories repos,
  DateTime? now,
}) async {
  final services = [service, ...fallbacks];
  final resolved = <ParsedProgramLine>[];
  for (final line in lines) {
    if (line.resolution != PlaintextLineResolution.unmatched) {
      resolved.add(line);
      continue;
    }
    resolved.add(
      await _resolveLineAcrossSources(
        line,
        services: services,
        repos: repos,
        now: now,
      ),
    );
  }
  return resolved;
}

/// Tries each of [services] in order for [line]'s title, stopping at the
/// first [_SourceImported] or [_SourceDeclined] outcome (see [_attemptSource]).
///
/// [_SourceDeclined] stops the chain **without trying later sources**: it means
/// the local collection already has this exact dance (issue #685's rule), which
/// is a fact about the user's collection, not about which source produced the
/// hit — a second source cannot make it false, so asking one is wasted work at
/// best and, worse, risks #686's variation branch treating a different
/// source's rendition of the SAME dance as a "genuinely different
/// choreography" and auto-importing a duplicate the first source correctly
/// declined.
///
/// [_SourceAmbiguous] and [_SourceMiss] both advance to the next source — only
/// a confident single match stops the chain (issue #943 ruling 1). Every
/// [_SourceAmbiguous] source's candidate rows are accumulated; if the chain is
/// exhausted with no confident match and no decline, those accumulated rows
/// (empty if every source simply missed) become
/// [ParsedProgramLine.onlineCandidates] on the returned line.
Future<ParsedProgramLine> _resolveLineAcrossSources(
  ParsedProgramLine line, {
  required List<OnlineSearchService> services,
  required CompendiumRepositories repos,
  DateTime? now,
}) async {
  final ambiguousCandidates = <OnlineSearchResultRow>[];
  for (final service in services) {
    final attempt = await _attemptSource(
      line.text,
      service: service,
      repos: repos,
      now: now,
    );
    switch (attempt) {
      case _SourceImported(:final danceId):
        return ParsedProgramLine(
          text: line.text,
          resolution: PlaintextLineResolution.matched,
          danceId: danceId,
          matchCount: 1,
          importedOnline: true,
        );
      case _SourceDeclined():
        // #685, applied regardless of source: never silently create a
        // duplicate of a dance the user already has. See this method's doc.
        //
        // Rebuilt rather than returning `line` verbatim: `line` may be a
        // *previous* resolve pass's result (a user can tap "Resolve unmatched
        // online" more than once on the same unresolved text — the screen's
        // `_effectiveLines` re-feeds `_resolvedOverride` in) and could already
        // carry a stale, non-empty `onlineCandidates` from that earlier run.
        // Returning it unchanged here would leave this run's decline still
        // reporting the previous run's candidates, which is exactly the kind
        // of resolution/evidence mismatch that made this trap worth
        // documenting in the first place.
        return ParsedProgramLine(
          text: line.text,
          resolution: PlaintextLineResolution.unmatched,
        );
      case _SourceAmbiguous(:final rows):
        ambiguousCandidates.addAll(rows);
      case _SourceMiss():
        break;
    }
  }
  // Every source missed, or was ambiguous, and none was confident or
  // declined. `onlineCandidates` defaults to empty, so a line whose sources
  // all now miss cleanly (even if a PRIOR resolve pass had left it carrying
  // candidates) is correctly reported as a plain unmatched note, not a stale
  // ambiguity — see the _SourceDeclined case above for why `line` is never
  // returned verbatim here either.
  return ParsedProgramLine(
    text: line.text,
    resolution: PlaintextLineResolution.unmatched,
    onlineCandidates: ambiguousCandidates,
  );
}

/// One online source's outcome for one program line's title (issue #943's
/// fallback chain). Distinguishes a genuine miss — try the next source — from
/// a deliberate #685 decline — stop, no source can override it — from an
/// ambiguous hit — collect candidates, but still try the next source, since
/// only a *confident* single match is allowed to stop the chain (ruling 1).
sealed class _SourceAttempt {
  const _SourceAttempt();
}

/// A confident single match was imported — either directly, or (issue #686)
/// as an auto-imported variation of a confident local duplicate whose figures
/// genuinely differ. Stops the chain.
class _SourceImported extends _SourceAttempt {
  const _SourceImported(this.danceId);

  final String danceId;
}

/// #685's conservative skip fired: a confident local duplicate whose figures
/// are canonically identical, or whose target dance could not be loaded to
/// check. Stops the chain — see [_resolveLineAcrossSources]'s doc for why.
class _SourceDeclined extends _SourceAttempt {
  const _SourceDeclined();
}

/// No usable result from this source alone: no results, no exact-title hit
/// (only fuzzy/substring matches), a fetch/parse/import error, or an import
/// that yielded no dance id. Advances to the next source.
class _SourceMiss extends _SourceAttempt {
  const _SourceMiss();
}

/// This source returned more than one exact-title hit. Advances to the next
/// source (ruling 1: only a confident match stops the chain), carrying [rows]
/// in case no source ever resolves confidently.
class _SourceAmbiguous extends _SourceAttempt {
  const _SourceAmbiguous(this.rows);

  final List<OnlineSearchResultRow> rows;
}

/// Tries a single [service] for [title], applying the exact #685/#686 rules
/// [resolveConfidentOnlineDanceId] has always applied — this function is that
/// logic, factored out so [_resolveLineAcrossSources] can drive it once per
/// source in the fallback chain while [resolveConfidentOnlineDanceId] stays a
/// single-source, single-call wrapper for its other caller
/// ([contradb_program_import.dart]'s Caller's Box fallback, issue #314) and its
/// own test suite.
Future<_SourceAttempt> _attemptSource(
  String title, {
  required OnlineSearchService service,
  required CompendiumRepositories repos,
  DateTime? now,
}) async {
  // requireFigures: false — this path is NON-INTERACTIVE and commits on its
  // own (see the #685/#686 rules below), so it deliberately keeps the wider,
  // pre-#845 result set. Narrowing it can promote an ambiguous
  // multipleExactMatches — which is a considered no-op — into a single
  // confident hit that this function then imports with nobody watching.
  // Changing what an unattended committer finds is a bigger decision than
  // changing what a search screen shows, so it is not made here.
  final lookup = await lookupUniqueExactTitle(
    title,
    service: service,
    requireFigures: false,
  );
  if (lookup is OnlineTitleMiss) {
    if (lookup.failure == OnlineTitleLookupFailure.multipleExactMatches) {
      return _SourceAmbiguous(lookup.candidates);
    }
    return const _SourceMiss();
  }
  try {
    final hit = lookup as OnlineTitleHit;
    final preview = await service.loadPreview(repos, hit.row, now: now);
    final verdict = preview.plan.verdict;
    if (verdict.hasConfidentMatch) {
      final targetId = verdict.candidates
          .firstWhere((c) => c.confident)
          .danceId;
      final target = await repos.dances.getById(targetId);
      if (target == null) {
        // Can't confirm identical vs. differing without the target's
        // figures — the conservative (#685-consistent) choice is to decline,
        // same as if it were identical.
        return const _SourceDeclined();
      }
      final draftDance = preview.plan.draft.dance;
      final identical = figuresCanonicallyIdentical(
        oldFigures: target.figures,
        newFigures: draftDance.figures,
        taxonomy: contraTaxonomy,
      );
      if (identical) {
        // #685, UNCHANGED: a true duplicate must never be silently created
        // non-interactively — decline, leaving the note-slot fallback (#312).
        return const _SourceDeclined();
      }
      // #686: figures genuinely differ — auto-import as a distinct
      // variation, linked back to the matched dance, same outcome as the
      // interactive "Import as a variation" choice, applied unattended.
      final pipeline = ImportPipeline(repos.dances, repos.choreographers);
      final session = await pipeline.commit(
        ImportBatchResult(records: [preview.plan]),
        now: now ?? DateTime.now().toUtc(),
        newId: uuidV4,
        resolutions: {0: DedupeResolution.variation(targetId)},
      );
      final record = session.records.first;
      return record.succeeded && record.danceId != null
          ? _SourceImported(record.danceId!)
          : const _SourceMiss();
    }
    final result = await service.import(
      repos,
      preview.plan,
      now: now,
      // Program import is non-interactive — no per-dance prompt (#797/#811).
      // The verdict at this point has !hasConfidentMatch (the block above
      // handles the confident case without calling import()), so neither
      // needsConfirmation nor needsConfirmationIdentical can be returned by
      // the real services here. Passing duplicate() makes the opt-out explicit
      // and safe against future refactors that might change that structural
      // guarantee.
      ambiguousResolution: DedupeResolution.duplicate(),
    );
    final danceId = result.danceId;
    return danceId != null ? _SourceImported(danceId) : const _SourceMiss();
  } on Exception catch (_) {
    // diagnostics: silent — fetch/import failure returns _SourceMiss; surfaced as unmatched/note slot to import review
    return const _SourceMiss();
  }
}

/// Searches [service] by [title] and, on a **confident match** — a UNIQUE
/// exact-title hit (exactly one result whose name equals [title], trimmed and
/// case-insensitive, found by [lookupUniqueExactTitle]) — imports that dance
/// and returns its new dance id.
///
/// Returns null when there is no confident match (no results, only fuzzy hits,
/// or more than one exact hit), when the previewed dance is already a
/// **confident local duplicate** (issue #685 — exact-normalized-title with an
/// overlapping tokenized author set, see [DedupeVerdict.hasConfidentMatch]),
/// or when the import yields no id. Any fetch / parse / import [Exception] is
/// swallowed and returns null so one bad title can't abort a batch; `Error`s
/// (assertion/programmer bugs) still surface. The search step's own failures are
/// already folded into an [OnlineTitleMiss]; every miss reason maps to the same
/// null here, because a program line has no user present to tell them apart.
///
/// This is the **single-source** entry point: [resolveUnmatchedOnline]'s
/// multi-source fallback chain (issue #943) drives the shared [_attemptSource]
/// logic directly instead of calling this once per source, so this function's
/// behaviour for its one call is unchanged from before #943 — a thin wrapper
/// kept for [contradb_program_import.dart]'s Caller's Box fallback (#314) and
/// this function's own test suite, neither of which needs the ordered chain.
///
/// This is the shared online-title→dance **import** used by both the plaintext
/// program import (#313) and the ContraDB program import's Caller's Box fallback
/// (#314). The Collection-side title-list import (#823) deliberately does **not**
/// call it — it shares only the non-committing [lookupUniqueExactTitle] step and
/// routes commits through the review screen instead. Performs a single search
/// fetch plus, on a confident hit, a single import fetch — no crawling
/// (import-fidelity rule).
///
/// ### Confident-match figure-variation handling (issue #686, owner-locked)
///
/// This resolver is **non-interactive** (no user is present to adjudicate a
/// program line), so a confident title+author match ([DedupeVerdict.hasConfidentMatch])
/// is never allowed to silently create an ordinary duplicate. But #685's
/// blanket "always skip" rule left no room for a confident match that is
/// actually a genuinely different choreography under the same/similar name —
/// #686 narrows that by comparing the matched dance's figures against the
/// previewed dance's figures ([figuresCanonicallyIdentical], built on
/// [figureCanonicalKey]). This non-interactive path only needs the
/// identical/differ answer, never a rendered diff, so it deliberately avoids
/// [diffFigures]'s `O(n·m)` LCS pass and rendering — the comparison stays
/// canonicalization-aware either way: dialect wording, beats, and
/// progression never count as a difference.
///
/// - **Identical figures** → still returns `null` (#685's rule, UNCHANGED —
///   a true duplicate must never be silently created, non-interactively).
/// - **Differing figures** → auto-imports the previewed dance as a new,
///   distinct **variation** dance (`DedupeResolution.variation`, symmetric
///   `relatedDance` link-back on by default) and returns its id — the exact
///   same outcome a user would get by picking "Import as a variation" in the
///   interactive review prompt, just applied unattended. There is
///   deliberately **no cap** on how many variations one batch may create
///   (owner-declined; #686's narrow figure-key definition already keeps this
///   trigger rare — timing/progression-only differences do NOT count).
///
/// **These two branches must stay explicit and distinct** — collapsing them
/// back into one skip (or one auto-import) would either reintroduce #685's
/// silent-duplicate bug (import path) or defeat #686's variation detection
/// (skip path).
///
/// A missing/deleted target dance (fetched via `repos.dances.getById`) is
/// treated the same as "cannot confirm identical": conservatively falls back
/// to the pre-#686 skip, deliberately **not reusing**
/// [CallersBoxOnline.import] / [ContraDbOnline.import]'s force-`duplicate()`
/// override, since that override is only correct for the genuinely
/// interactive single-dance "search → tap Import" flow (an explicit user
/// pick), not for this batch/non-interactive path.
Future<String?> resolveConfidentOnlineDanceId(
  String title, {
  required OnlineSearchService service,
  required CompendiumRepositories repos,
  DateTime? now,
}) async {
  final attempt = await _attemptSource(
    title,
    service: service,
    repos: repos,
    now: now,
  );
  return switch (attempt) {
    _SourceImported(:final danceId) => danceId,
    _SourceDeclined() || _SourceMiss() || _SourceAmbiguous() => null,
  };
}
