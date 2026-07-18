import 'package:compendium_core/compendium_core.dart';

/// How a single pasted line resolved against the local collection.
enum PlaintextLineResolution {
  /// Exactly one local dance matched the title (case-insensitive) — the slot
  /// links to that dance.
  matched,

  /// More than one local dance shares the title — ambiguous. For this slice we
  /// do not force a choice; the line is kept as a free-text note slot (later
  /// sub-issues add a resolver). See #312.
  ambiguous,

  /// No local dance matched — the line becomes a free-text note slot.
  unmatched,
}

/// One parsed, resolved line from the pasted plaintext block. Blank lines are
/// dropped by the parser and never produce a [ParsedProgramLine].
class ParsedProgramLine {
  const ParsedProgramLine({
    required this.text,
    required this.resolution,
    this.danceId,
    this.matchCount = 0,
  }) : assert(
         // matched ⇒ exactly one dance, id present; note resolutions
         // (unmatched/ambiguous) ⇒ no id, so buildProgramSlots always has a
         // valid ProgramSlot (danceId xor text), never both-null.
         resolution == PlaintextLineResolution.matched
             ? (danceId != null && matchCount == 1)
             : (danceId == null),
         'matched requires danceId and matchCount == 1; '
         'note resolutions require danceId == null',
       ),
       assert(
         // ambiguous means more than one local match; unmatched means none.
         resolution == PlaintextLineResolution.ambiguous
             ? matchCount > 1
             : (resolution == PlaintextLineResolution.unmatched
                   ? matchCount == 0
                   : true),
         'ambiguous requires matchCount > 1; unmatched requires matchCount == 0',
       );

  /// The trimmed line text as the user typed it.
  final String text;

  final PlaintextLineResolution resolution;

  /// The linked dance id when [resolution] is [PlaintextLineResolution.matched];
  /// null otherwise.
  final String? danceId;

  /// How many local dances matched the title. `1` for [matched], `>1` for
  /// [ambiguous], `0` for [unmatched]. Lets the preview surface why an
  /// ambiguous line fell back to a note.
  final int matchCount;

  /// Whether this line will become a free-text note slot (unmatched or
  /// ambiguous) rather than a dance-linked slot.
  bool get isNote => resolution != PlaintextLineResolution.matched;
}

/// Parses a newline-separated block of dance titles into ordered, resolved
/// lines, one per non-blank input line. Ordering is preserved exactly; blank
/// or whitespace-only lines are skipped so they never create empty slots.
///
/// Each line is matched case-insensitively (after trimming) against
/// [collection] — the local `(id, title)` listing from
/// `DanceRepository.listIdsAndTitles`. Exactly one match links to that dance;
/// more than one is [PlaintextLineResolution.ambiguous]; none is
/// [PlaintextLineResolution.unmatched]. Ambiguous and unmatched lines both
/// become note slots for this slice (#312).
List<ParsedProgramLine> parsePlaintextProgram(
  String text, {
  required List<({String id, String title})> collection,
}) {
  final index = <String, List<String>>{};
  for (final entry in collection) {
    final key = entry.title.trim().toLowerCase();
    if (key.isEmpty) continue;
    (index[key] ??= <String>[]).add(entry.id);
  }

  final lines = <ParsedProgramLine>[];
  for (final raw in text.split('\n')) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;
    final matches = index[trimmed.toLowerCase()] ?? const <String>[];
    if (matches.length == 1) {
      lines.add(
        ParsedProgramLine(
          text: trimmed,
          resolution: PlaintextLineResolution.matched,
          danceId: matches.first,
          matchCount: 1,
        ),
      );
    } else if (matches.length > 1) {
      lines.add(
        ParsedProgramLine(
          text: trimmed,
          resolution: PlaintextLineResolution.ambiguous,
          matchCount: matches.length,
        ),
      );
    } else {
      lines.add(
        ParsedProgramLine(
          text: trimmed,
          resolution: PlaintextLineResolution.unmatched,
        ),
      );
    }
  }
  return lines;
}

/// Builds ordered [ProgramSlot]s from parsed [lines]. Matched lines produce a
/// dance-linked slot; note lines (unmatched/ambiguous) produce a free-text slot
/// carrying the original line text — the same note-style slot path that
/// announcements and breaks use. Positions are numbered `0..n-1` in input
/// order. [newSlotId] mints a fresh id per slot.
List<ProgramSlot> buildProgramSlots(
  List<ParsedProgramLine> lines, {
  required String Function() newSlotId,
}) {
  final slots = <ProgramSlot>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    slots.add(
      ProgramSlot(
        id: newSlotId(),
        position: i,
        danceId: line.isNote ? null : line.danceId,
        text: line.isNote ? line.text : null,
      ),
    );
  }
  return slots;
}
