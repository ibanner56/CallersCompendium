import '../model/figure.dart';
import '../taxonomy/taxonomy.dart';
import 'figure_parser.dart';
import 'shorthand_mappings.dart';

/// Longest inline beat count we will read from a free-text line. Bounds the
/// captured digit run so a hostile/absurd value (`(999999999999)`) can never
/// overflow an int or drive downstream duration math off the rails — anything
/// past four digits is treated as ordinary text, not a beat count. Four digits
/// (≤ 9999) comfortably covers any real contra figure while staying safe.
const int _maxInlineBeatDigits = 4;

/// Upper bound on the length of a single free-text entry line we will feed
/// through the parser. A real figure line — even a `;`-compound — is at most a
/// few dozen characters; anything beyond this is treated as malformed/hostile
/// input and yields nothing rather than driving unbounded recognition work.
/// This mirrors the OWASP "bounded input" posture of the rest of the import
/// path (see `maxReparseTextLength`): even though the text is typed locally we
/// treat it as untrusted, and the guard is enforced in core (defense in depth)
/// rather than relying on any UI-side field limit.
const int maxFreeTextEntryLength = 2000;

/// A leading bare beat count: `16 balance and swing`. The digits must be
/// followed by whitespace AND a non-empty remainder, so a fraction/positional
/// token glued to the digits (`1/2 hey`, `1s cross`) is NOT mistaken for a
/// count (there is no space after the leading digits in those).
final RegExp _leadingBeats = RegExp(
  '^(\\d{1,$_maxInlineBeatDigits})\\s+(\\S.*)\$',
);

/// A trailing parenthesised beat count: `balance and swing (16)`. Only a
/// digits-only parenthesised group at the very end counts — a trailing prose
/// annotation (`allemande (once)`) is left untouched because its contents are
/// not all digits.
final RegExp _trailingBeats = RegExp(
  '^(.*\\S)\\s*\\((\\d{1,$_maxInlineBeatDigits})\\)\$',
);

/// Result of splitting an optional inline beat count off a free-text line.
class _BeatSplit {
  const _BeatSplit(this.text, this.beats);

  /// The line with any recognised inline beat token removed.
  final String text;

  /// The extracted beat count, or 0 when the line stated none (0 is treated as
  /// "unspecified" everywhere downstream — see [parseFigureLine]).
  final int beats;
}

/// Extracts an optional inline beat count from a trimmed free-text [line]. A
/// trailing `(N)` is checked first (it is unambiguous — digits inside parens at
/// the end), then a leading `N `. Returns the line unchanged with 0 beats when
/// neither form is present — or when the stated count parses to 0. Because 0 is
/// "unspecified" downstream, stripping a `(0)`/`0 ` token would silently mutate
/// the user's text for no gain, so a zero count leaves the whole line intact
/// (it flows into the parser verbatim — e.g. as an honest custom).
_BeatSplit _splitInlineBeats(String line) {
  final trailing = _trailingBeats.firstMatch(line);
  if (trailing != null) {
    final beats = int.tryParse(trailing.group(2)!);
    if (beats != null && beats > 0) {
      return _BeatSplit(trailing.group(1)!.trim(), beats);
    }
  }
  final leading = _leadingBeats.firstMatch(line);
  if (leading != null) {
    final beats = int.tryParse(leading.group(1)!);
    if (beats != null && beats > 0) {
      return _BeatSplit(leading.group(2)!.trim(), beats);
    }
  }
  return _BeatSplit(line, 0);
}

/// Parses one free-text figure line typed in the editor's opt-in "Free-text
/// entry" mode (issue #419) into structured/custom [Figure]s.
///
/// When a [shorthands] store is supplied it is consulted FIRST (issue #420):
/// the whole trimmed line is matched against the user's shorthand tokens as an
/// EXACT, whole-line token (case-insensitive + trim-insensitive; no mid-line or
/// substring substitution, keeping expansion deterministic). On a hit the line
/// expands to the mapped figure(s) and those are returned verbatim — inline
/// beat parsing is skipped because a shorthand's targets carry their own beats.
/// On a miss (or when no store is given) the line falls through to the normal
/// #419 parser path below.
///
/// This is the local-typed counterpart to the import adapters: it reuses the
/// SAME hardened, bounded, never-throw core parser ([parseFigureLines]) rather
/// than any "trusted-local" fast-path, so a typed line behaves identically to
/// the same line arriving from an import — `;`-compounds split all-or-nothing
/// and a top-level `||` stays whole-custom.
///
/// Before parsing, an optional inline beat count is peeled off the line and
/// passed as the `beats` argument:
/// - a **leading** `16 …` (a bare integer + space), or
/// - a **trailing** `… (16)` (a parenthesised integer at the end).
///
/// Only ONE inline form is honoured per line: a trailing `(N)` is checked
/// first and wins, so a line that redundantly supplies both (`16 … (8)`) keeps
/// the leftover leading digits in its text (and typically degrades to a
/// verbatim custom) rather than guessing which count the caller meant.
///
/// When the line states no inline count the beats argument is left at 0, which
/// [parseFigureLine] treats as "unspecified": a matched structured figure then
/// derives its move/param default beats on read via [Taxonomy.effectiveParams]
/// (never forced to a literal 0), and an unrecognised line stays a beats-absent
/// custom.
///
/// Returns an empty list when the line is empty after trimming/scrubbing
/// (nothing to insert) or when it exceeds [maxFreeTextEntryLength] (treated as
/// malformed/hostile input). Matched lines yield structured taxonomy figures;
/// unrecognised lines yield [customMove] figures tagged
/// [CustomOrigin.importGap] (via [parseFigureLine]) so they surface the #398
/// parser-gap marker and remain eligible for the reparse-customs upgrade.
List<Figure> parseFreeTextFigureEntry(
  String input, {
  Taxonomy? taxonomy,
  ShorthandMappings? shorthands,
}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty || trimmed.length > maxFreeTextEntryLength) {
    return const [];
  }
  // Shorthand resolution runs FIRST (issue #420): a whole-line exact-token hit
  // expands to the mapped figure(s) and short-circuits the parser. A miss (or
  // no store) falls through to the normal #419 recognition below.
  if (shorthands != null) {
    final expanded = shorthands.resolve(trimmed);
    if (expanded != null) return expanded;
  }
  final split = _splitInlineBeats(trimmed);
  return parseFigureLines(split.text, beats: split.beats, taxonomy: taxonomy);
}
