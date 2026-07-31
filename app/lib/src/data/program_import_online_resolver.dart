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
/// ### Confident-local-duplicate guard (issue #685, Option 2 — locked)
///
/// This resolver is **non-interactive** (no user is present to disambiguate a
/// program line), so it must never force an online-resolved dance to import
/// as a fresh dance when it's actually a confident local duplicate — that
/// would silently create a duplicate. [OnlineSearchService.loadPreview]
/// already runs the previewed dance through the full local [DedupeIndex]
/// (title + tokenized authors) to build `preview.plan.verdict`, so consulting
/// [DedupeVerdict.hasConfidentMatch] here costs no extra index build. When it
/// fires, this returns `null` (Option 2: non-interactive → skip) instead of
/// calling [OnlineSearchService.import] — deliberately **not** reusing
/// [CallersBoxOnline.import] / [ContraDbOnline.import]'s force-`duplicate()`
/// override, since that override is only correct for the genuinely
/// interactive single-dance "search → tap Import" flow (an explicit user
/// pick), not for this batch/non-interactive path. The line falls back to the
/// existing note-slot behavior (#312); a user can resolve it manually later
/// (e.g. via the batch review screen or a manual link).
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
    if (preview.plan.verdict.hasConfidentMatch) {
      // Non-interactive path: never silently duplicate a confident local
      // match (#685 Option 2). Leave the line unresolved (note-slot
      // fallback) rather than force-importing or force-duplicating it.
      return null;
    }
    final result = await service.import(repos, preview.plan, now: now);
    return result.danceId;
  } on Exception catch (_) {
    return null;
  }
}
