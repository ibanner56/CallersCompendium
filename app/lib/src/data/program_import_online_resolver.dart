import 'package:compendium_core/compendium_core.dart';

import 'online_search.dart';
import 'online_title_lookup.dart';
import 'plaintext_program_import.dart';
import 'program_import_rollback.dart';

/// Resolves the `unmatched` lines of a parsed plaintext program against an
/// ordered chain of online sources — The Caller's Box first (epic #291,
/// sub-issue #313), then any [fallbacks] in order (issue #943, e.g. ContraDB) —
/// stopping at the first source that resolves a line confidently.
///
/// For each [PlaintextLineResolution.unmatched] line, each source in turn (see
/// [_resolveLineAcrossSources]) is asked to [OnlineSearchService.search] by the
/// line's title. A line is only auto-linked on a **confident match** — a
/// UNIQUE exact-title hit: exactly one result whose
/// [OnlineSearchResultRow.name] equals the line text under `titleMatchKey`
/// (case, whitespace and quote/dash style folded) — from whichever source
/// produces one first. On such a hit
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
///
/// **Stopping.** A source that cannot be reached (offline, timed out, or its
/// search answering an HTTP error — see `isConnectionFailure`) says nothing
/// about the title, and the next title would fail the same way, so the pass
/// stops at the first such failure, as the Collection title-list import does.
/// The lines already resolved are kept, every line not yet looked up comes
/// back unchanged, and [ProgramOnlineResolution.stoppedAfterConnectionFailure]
/// is set so the screen can say "couldn't reach" rather than "no matches".
/// [isCancelled] is checked before each title and each source; once it
/// returns true the pass stops the same way and sets
/// [ProgramOnlineResolution.cancelled]. [onProgress] reports `(done, total)`
/// over the unmatched lines.
///
/// **Undo.** Every dance this pass writes is recorded in [rollback] when one
/// is supplied, so the program import can take it back out on Undo or when
/// the user backs out without creating the program (see
/// [ProgramImportRollback]).
Future<ProgramOnlineResolution> resolveUnmatchedOnline(
  List<ParsedProgramLine> lines, {
  required OnlineSearchService service,
  List<OnlineSearchService> fallbacks = const [],
  required CompendiumRepositories repos,
  DateTime? now,
  ProgramImportRollback? rollback,
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final services = [service, ...fallbacks];
  final total = lines
      .where((l) => l.resolution == PlaintextLineResolution.unmatched)
      .length;
  var done = 0;
  var stopped = false;
  var cancelled = false;
  if (total > 0) onProgress?.call(done, total);
  final resolved = <ParsedProgramLine>[];
  for (final line in lines) {
    if (line.resolution != PlaintextLineResolution.unmatched ||
        stopped ||
        cancelled) {
      resolved.add(line);
      continue;
    }
    try {
      resolved.add(
        await _resolveLineAcrossSources(
          line,
          services: services,
          repos: repos,
          now: now,
          rollback: rollback,
          isCancelled: isCancelled,
        ),
      );
    } on ProgramImportConnectionFailed {
      // diagnostics: silent — reported through stoppedAfterConnectionFailure
      stopped = true;
      resolved.add(line);
      continue;
    } on ProgramImportCancelled {
      // diagnostics: silent — user-initiated, reported through `cancelled`
      cancelled = true;
      resolved.add(line);
      continue;
    }
    done++;
    onProgress?.call(done, total);
  }
  return ProgramOnlineResolution(
    lines: resolved,
    stoppedAfterConnectionFailure: stopped,
    cancelled: cancelled,
  );
}

/// What [resolveUnmatchedOnline] produced: the [lines] (one per input line, in
/// order) and whether the pass ended early.
class ProgramOnlineResolution {
  const ProgramOnlineResolution({
    required this.lines,
    this.stoppedAfterConnectionFailure = false,
    this.cancelled = false,
  });

  final List<ParsedProgramLine> lines;

  /// An online source could not be reached, so the pass stopped; lines after
  /// that point were not looked up and come back unchanged.
  final bool stoppedAfterConnectionFailure;

  /// The `isCancelled` callback tripped, so the pass stopped; lines after that
  /// point were not looked up and come back unchanged.
  final bool cancelled;
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
///
/// Throws [ProgramImportConnectionFailed] when a source cannot be reached, and
/// [ProgramImportCancelled] when [isCancelled] trips before a source is asked.
Future<ParsedProgramLine> _resolveLineAcrossSources(
  ParsedProgramLine line, {
  required List<OnlineSearchService> services,
  required CompendiumRepositories repos,
  DateTime? now,
  ProgramImportRollback? rollback,
  bool Function()? isCancelled,
}) async {
  final ambiguousCandidates = <OnlineSearchResultRow>[];
  for (final service in services) {
    if (isCancelled?.call() ?? false) throw const ProgramImportCancelled();
    final attempt = await _attemptSource(
      line.text,
      service: service,
      repos: repos,
      now: now,
      rollback: rollback,
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
/// (only fuzzy/substring matches), a fetch/parse/import error that is not a
/// connection failure, or an import that yielded no dance id. Advances to the
/// next source.
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
///
/// Every dance it writes is recorded in [rollback]. A source that cannot be
/// reached throws [ProgramImportConnectionFailed] rather than reading as a
/// miss: "offline" and "the archive has no such dance" need different words.
Future<_SourceAttempt> _attemptSource(
  String title, {
  required OnlineSearchService service,
  required CompendiumRepositories repos,
  DateTime? now,
  ProgramImportRollback? rollback,
}) async {
  // requireFigures is left at its #845 default (true), as the Collection
  // title-list import leaves it: a title held only by a dance the source will
  // not hand over with its figures is not something to import unattended into
  // a program slot (imports.md, "a list of titles"). It can turn two exact
  // hits, one of them figure-hidden, into a single confident hit; that hit is
  // then the only one of the two worth having.
  final lookup = await lookupUniqueExactTitle(title, service: service);
  if (lookup is OnlineTitleMiss) {
    switch (lookup.failure) {
      case OnlineTitleLookupFailure.multipleExactMatches:
        return _SourceAmbiguous(lookup.candidates);
      case OnlineTitleLookupFailure.unreachable:
        throw const ProgramImportConnectionFailed();
      case OnlineTitleLookupFailure.noResults ||
          OnlineTitleLookupFailure.noExactMatch ||
          OnlineTitleLookupFailure.fetchError:
        return const _SourceMiss();
    }
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
      // Both sides must be readable for the comparison below to mean anything.
      // This path is UNATTENDED: `identical` declines, and `!identical` auto
      // -imports a variation with no user present. An undecodable target would
      // otherwise take the second branch by default — acting on a comparison
      // that was never actually performed. Declining instead leaves the
      // note-slot fallback (#312), which is what this code already does
      // whenever it cannot be sure.
      final oldFigures = switch (target.figuresSource) {
        DecodedFigures(:final figures) => figures,
        UnreadableFigures() => null,
      };
      final newFigures = switch (draftDance.figuresSource) {
        DecodedFigures(:final figures) => figures,
        UnreadableFigures() => null,
      };
      if (oldFigures == null || newFigures == null) {
        return const _SourceDeclined();
      }
      final identical = figuresCanonicallyIdentical(
        oldFigures: oldFigures,
        newFigures: newFigures,
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
      final pipeline = ImportPipeline(
        repos.dances,
        repos.choreographers,
        difficultyLevels: repos.difficultyLevels,
      );
      final session = await pipeline.commit(
        ImportBatchResult(records: [preview.plan]),
        now: now ?? DateTime.now().toUtc(),
        newId: uuidV4,
        resolutions: {0: DedupeResolution.variation(targetId)},
      );
      await rollback?.record(session);
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
      // the real services here. #1907's needsPossibleMatchChoice *could* be
      // (it needs no confident match), and only a supplied resolution rules it
      // out, so passing duplicate() is what keeps this path unattended, not
      // merely an explicit opt-out.
      ambiguousResolution: DedupeResolution.duplicate(),
    );
    final session = result.session;
    if (session != null) await rollback?.record(session);
    final danceId = result.danceId;
    return danceId != null ? _SourceImported(danceId) : const _SourceMiss();
  } on Exception catch (e) {
    // No HTTP-status reasons: a 404 on one dance's page is about that dance,
    // not the connection (the same split `title_list_import.dart` makes).
    if (isConnectionFailure(e)) throw const ProgramImportConnectionFailed();
    // diagnostics: silent — fetch/import failure returns _SourceMiss; surfaced as unmatched/note slot to import review
    return const _SourceMiss();
  }
}

/// Searches [service] by [title] and, on a **confident match** — a UNIQUE
/// exact-title hit (exactly one result whose name equals [title] under
/// `titleMatchKey`, found by [lookupUniqueExactTitle]) — imports that dance
/// and returns its new dance id.
///
/// Returns null when there is no confident match (no results, only fuzzy hits,
/// or more than one exact hit), when the previewed dance is already a
/// **confident local duplicate** (issue #685 — exact-normalized-title with an
/// overlapping tokenized author set, see [DedupeVerdict.hasConfidentMatch]),
/// or when the import yields no id. Any other fetch / parse / import
/// [Exception] is swallowed and returns null so one bad title can't abort a
/// batch; `Error`s (assertion/programmer bugs) still surface. The one
/// exception is a source that cannot be reached at all (`isConnectionFailure`):
/// that throws [ProgramImportConnectionFailed], because it says nothing about
/// this title and the caller should stop rather than keep asking.
///
/// Every dance it writes is recorded in [rollback] when one is supplied.
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
  ProgramImportRollback? rollback,
}) async {
  final attempt = await _attemptSource(
    title,
    service: service,
    repos: repos,
    now: now,
    rollback: rollback,
  );
  return switch (attempt) {
    _SourceImported(:final danceId) => danceId,
    _SourceDeclined() || _SourceMiss() || _SourceAmbiguous() => null,
  };
}
