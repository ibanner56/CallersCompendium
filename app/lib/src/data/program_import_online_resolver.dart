import 'package:compendium_core/compendium_core.dart';

import 'online_search.dart';
import 'plaintext_program_import.dart';

/// Resolves the `unmatched` lines of a parsed plaintext program against The
/// Caller's Box (epic #291, sub-issue #313).
///
/// For each [PlaintextLineResolution.unmatched] line the [service] is asked to
/// [OnlineSearchService.search] by the line's title. A line is only auto-linked
/// on a **confident match** — a UNIQUE exact-title hit: exactly one result whose
/// [OnlineSearchResultRow.name] equals the line text (trimmed, case-insensitive).
/// On such a hit the dance is imported via
/// [OnlineSearchService.loadPreview] + [OnlineSearchService.import] and the
/// returned dance id is linked into the slot (a fresh
/// [PlaintextLineResolution.matched] line with [ParsedProgramLine.importedOnline]
/// set).
///
/// Anything else preserves the sub-issue #312 note-slot fallback and returns the
/// line unchanged:
/// - no results, or no exact-title hit (only fuzzy/substring matches);
/// - more than one exact-title hit (ambiguous online);
/// - an import that yields no dance id;
/// - any fetch/parse error (swallowed per-title so one bad title can't abort the
///   whole batch).
///
/// Non-`unmatched` lines (local `matched` / `ambiguous`) pass through untouched:
/// online resolution only fills the gap where the local collection had nothing.
///
/// Only a single search fetch per title and a single JSON fetch per confident
/// import are performed — no crawling (import fidelity rule).
Future<List<ParsedProgramLine>> resolveUnmatchedOnline(
  List<ParsedProgramLine> lines, {
  required OnlineSearchService service,
  required CompendiumRepositories repos,
  DateTime? now,
}) async {
  final resolved = <ParsedProgramLine>[];
  for (final line in lines) {
    if (line.resolution != PlaintextLineResolution.unmatched) {
      resolved.add(line);
      continue;
    }
    resolved.add(
      await _resolveLine(line, service: service, repos: repos, now: now),
    );
  }
  return resolved;
}

Future<ParsedProgramLine> _resolveLine(
  ParsedProgramLine line, {
  required OnlineSearchService service,
  required CompendiumRepositories repos,
  DateTime? now,
}) async {
  final danceId = await resolveConfidentOnlineDanceId(
    line.text,
    service: service,
    repos: repos,
    now: now,
  );
  // No confident match keeps the note-slot fallback (#312).
  if (danceId == null) return line;
  return ParsedProgramLine(
    text: line.text,
    resolution: PlaintextLineResolution.matched,
    danceId: danceId,
    matchCount: 1,
    importedOnline: true,
  );
}

/// Searches [service] by [title] and, on a **confident match** — a UNIQUE
/// exact-title hit (exactly one result whose name equals [title], trimmed and
/// case-insensitive) — imports that dance and returns its new dance id.
///
/// Returns null when there is no confident match (no results, only fuzzy hits,
/// or more than one exact hit), when the previewed dance is already a
/// **confident local duplicate** (issue #685 — exact-normalized-title with an
/// overlapping tokenized author set, see [DedupeVerdict.hasConfidentMatch]),
/// or when the import yields no id. Any fetch / parse / import [Exception] is
/// swallowed and returns null so one bad title can't abort a batch; `Error`s
/// (assertion/programmer bugs) still surface.
///
/// This is the shared online-title→dance resolution used by both the plaintext
/// program import (#313) and the ContraDB program import's Caller's Box fallback
/// (#314). Performs a single search fetch plus, on a confident hit, a single
/// import fetch — no crawling (import-fidelity rule).
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
  final wanted = title.trim().toLowerCase();
  try {
    final rows = await service.search(OnlineSearchQuery(title: title));
    final exact = rows
        .where((r) => r.name.trim().toLowerCase() == wanted)
        .toList();
    if (exact.length != 1) return null;

    final preview = await service.loadPreview(repos, exact.single, now: now);
    final verdict = preview.plan.verdict;
    if (verdict.hasConfidentMatch) {
      final targetId = verdict.candidates
          .firstWhere((c) => c.confident)
          .danceId;
      final target = await repos.dances.getById(targetId);
      if (target == null) {
        // Can't confirm identical vs. differing without the target's
        // figures — the conservative (#685-consistent) choice is to skip,
        // same as if it were identical.
        return null;
      }
      final draftDance = preview.plan.draft.dance;
      final identical = figuresCanonicallyIdentical(
        oldFigures: target.figures,
        newFigures: draftDance.figures,
        taxonomy: contraTaxonomy,
      );
      if (identical) {
        // #685, UNCHANGED: a true duplicate must never be silently created
        // non-interactively — skip, leaving the note-slot fallback (#312).
        return null;
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
      return record.succeeded ? record.danceId : null;
    }
    final result = await service.import(
      repos,
      preview.plan,
      now: now,
      // Program import is non-interactive — no per-dance prompt (#797).
      // The verdict at this point has !hasConfidentMatch (the block above
      // handles the confident case without calling import()), so
      // needsConfirmation cannot be returned by the real services here.
      // Passing duplicate() makes the opt-out explicit and safe against
      // future refactors that might change that structural guarantee.
      ambiguousResolution: DedupeResolution.duplicate(),
    );
    return result.danceId;
  } on Exception catch (_) {
    return null;
  }
}
