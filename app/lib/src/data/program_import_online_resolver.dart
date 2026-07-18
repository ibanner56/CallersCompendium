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
  final wanted = line.text.trim().toLowerCase();
  try {
    final rows = await service.search(OnlineSearchQuery(title: line.text));
    final exact = rows
        .where((r) => r.name.trim().toLowerCase() == wanted)
        .toList();
    // Confident match ⇔ a single exact-title hit. Zero, fuzzy-only, or multiple
    // exact hits stay a note.
    if (exact.length != 1) return line;

    final preview = await service.loadPreview(repos, exact.single, now: now);
    final result = await service.import(repos, preview.plan, now: now);
    final danceId = result.danceId;
    if (danceId == null) return line;

    return ParsedProgramLine(
      text: line.text,
      resolution: PlaintextLineResolution.matched,
      danceId: danceId,
      matchCount: 1,
      importedOnline: true,
    );
  } on Exception catch (_) {
    // A fetch/parse/import *failure* keeps the note-slot fallback (#312). Only
    // Exceptions are swallowed; Errors (assertion/programmer bugs) surface.
    return line;
  }
}
