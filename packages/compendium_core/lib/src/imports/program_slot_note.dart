/// The prefix every "referenced dance could not be resolved" placeholder note
/// starts with, shared by every import path that mints one so a downstream
/// reader (like [danceTitleFromSlotNote]) can recognize and strip it without
/// drifting from the producers.
///
/// Used verbatim by [compendium_archive_import.dart] (`'$kUnresolvedDanceMarkerPrefix${slot.danceId})'`)
/// and by [callers_companion_programs.dart] (`"$kUnresolvedDanceMarkerPrefix"
/// "Caller's Companion dance #${item.danceRecordId})"`).
const String kUnresolvedDanceMarkerPrefix = 'Dance not imported (';

/// Upper bound on the extracted title's length before it's handed to the
/// dance editor. Mirrors [ProgramImportMarkerIndex._maxTitleLength]'s
/// resource-exhaustion rationale — the note text can originate from an
/// untrusted downloaded archive or web page, so it is capped before any work
/// rather than trusted to be short.
const int _maxExtractedTitleLength = 512;

/// Derives a reasonable dance-editor title seed from a program slot's
/// free-text note (issue #881's "create a dance from this" action).
///
/// A note slot's text is not reliably a bare title — it can be:
/// - a bare pasted title (title-list / plaintext import);
/// - `"<title> — <note>"` (ContraDB import) — deliberately NOT split here, so
///   the note half is not silently discarded from the seed's source text;
/// - `"<text>\n\n$kUnresolvedDanceMarkerPrefix<id>)"` or just the marker on
///   its own (archive / Caller's Companion imports for an unresolved dance
///   reference);
/// - a hand-typed announcement.
///
/// This takes the first non-blank line and, if that line (and only that
/// line — the marker producers always put it on its own line, separated by a
/// blank line from any real text, so this never touches a later line) is
/// exactly an unresolved-dance marker, strips it to leave nothing. Otherwise
/// the first non-blank line — real note text, when there is any — is
/// returned trimmed and capped. The extracted value is only ever a *seed* the
/// user reviews and can edit before saving, never written unattended.
///
/// Deliberately non-backtracking (no regex, just `indexOf`/substring/split on
/// literal newlines) so a pathological untrusted note can't cause unbounded
/// work — the length cap below also runs before the split.
String danceTitleFromSlotNote(String note) {
  final capped = note.length > _maxExtractedTitleLength
      ? note.substring(0, _maxExtractedTitleLength)
      : note;

  // First non-blank line.
  String firstLine = '';
  for (final line in capped.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) {
      firstLine = trimmed;
      break;
    }
  }

  // Clear the first line entirely, but ONLY when that whole line IS an
  // unresolved-dance marker (starts with the shared prefix, ends with the
  // closing paren) — never when the prefix merely appears as a substring
  // somewhere inside otherwise-real content (e.g. a ContraDB "<title> —
  // <note>" join whose note half happens to mention it). The producers
  // always emit the marker as the ENTIRE line — see the constant's doc
  // comment — so anchoring on the whole line rather than searching for the
  // substring can't false-positive on real content.
  if (firstLine.startsWith(kUnresolvedDanceMarkerPrefix) &&
      firstLine.endsWith(')')) {
    firstLine = '';
  }

  return firstLine.length > _maxExtractedTitleLength
      ? firstLine.substring(0, _maxExtractedTitleLength)
      : firstLine;
}
