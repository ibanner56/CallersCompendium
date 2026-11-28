import 'free_text_entry.dart' show maxFreeTextEntryLength;

/// A phrase label at the start of a line (`A1`…`C2`), with an optional
/// closing mark (`A1.`, `B2:`, `A1)`, `B1-`), then the rest of the line.
/// Built once: the Caller's Companion text adapter runs it on every line of a
/// file.
final RegExp _leadingPhraseLabel = RegExp(
  r'^([ABC][12])\b[.:)\-]?\s*(.*)$',
  caseSensitive: false,
);

/// Splits a leading phrase label (`A1`…`C2`, any case, optionally followed by
/// `.`, `:`, `)` or `-`) from the rest of [line]. Returns the label upper-cased
/// and the trimmed rest, or `(null, line)` when [line] does not open with one.
///
/// A label must stand as its own word: `A12 …` and `B1s …` are not labelled.
/// Shared by the Caller's Companion text adapter, which reads its sections
/// from these labels, and the dance editor's **Add figures from text** sheet
/// (#2326), which drops them from contra and square lines before parsing,
/// except a corner code (`C2 corner …`, [splitFigureTextLines]).
(String?, String) splitPhraseLabel(String line) {
  final match = _leadingPhraseLabel.firstMatch(line);
  if (match == null) return (null, line);
  return (match.group(1)!.toUpperCase(), match.group(2)!.trim());
}

/// Most lines the **Add figures from text** sheet reads at once (#2326). A
/// card or a dance's figure list is a few dozen lines; this is far beyond any
/// real dance, and keeps a hostile or mistaken paste from driving thousands of
/// parses. Counted over non-empty lines only.
const int maxFigureTextLines = 200;

/// Most characters the **Add figures from text** sheet reads at once (#2326).
/// Each line is also held to [maxFreeTextEntryLength] by the parser itself.
const int maxFigureTextLength = 20000;

/// Why [splitFigureTextLines] read nothing.
enum FigureTextRefusal {
  /// The text is longer than [maxFigureTextLength].
  tooLong,

  /// The text holds more than [maxFigureTextLines] figure lines.
  tooManyLines,

  /// A line is longer than [maxFreeTextEntryLength], which the parser would
  /// read as nothing.
  lineTooLong,
}

/// One figure line of the **Add figures from text** sheet, ready for
/// `parseFreeTextFigureEntry`.
class FigureTextLine {
  const FigureTextLine({required this.text, this.label});

  /// What the parser reads: the trimmed line, with any phrase label that
  /// [splitFigureTextLines] dropped removed.
  final String text;

  /// The phrase label dropped from the line's start, or null when none was.
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is FigureTextLine && other.text == text && other.label == label;

  @override
  int get hashCode => Object.hash(text, label);

  @override
  String toString() => 'FigureTextLine($label, $text)';
}

/// The result of [splitFigureTextLines]: the lines to parse, or why there are
/// none.
class FigureTextLines {
  const FigureTextLines._(this.lines, this.refusal);

  /// The figure lines, in order. Empty when [refusal] is set.
  final List<FigureTextLine> lines;

  /// Set when the text was over a cap and nothing was read.
  final FigureTextRefusal? refusal;
}

/// Splits [text] typed or pasted into the **Add figures from text** sheet
/// (#2326) into figure lines: one per non-empty line, trimmed. A line that is
/// only a phrase label (`A1`) is skipped. With [dropPhraseLabels] (contra
/// and square dances), a leading `A1`…`C2` label is dropped so the parser
/// sees the line without it. English dances keep the label, because the
/// parser reads one in front of a bar range (`A1 1-8 lead up`). A `C1` or
/// `C2` followed by `corner` or `corners` is a corner dancer, as The Caller's
/// Box writes one (`C2 corner allemande left 1`), not a label, so it is kept
/// and the line is read as the Move box reads it.
///
/// The text is untrusted input, as an import is: text over
/// [maxFigureTextLength] characters, with more than [maxFigureTextLines]
/// figure lines, or with a line over [maxFreeTextEntryLength] characters (which
/// the parser would read as nothing), is refused whole, so nothing from it is
/// inserted.
FigureTextLines splitFigureTextLines(
  String text, {
  required bool dropPhraseLabels,
}) {
  if (text.length > maxFigureTextLength) {
    return const FigureTextLines._([], FigureTextRefusal.tooLong);
  }
  final lines = <FigureTextLine>[];
  for (final raw in text.split(_lineBreak)) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;
    // A line that is only a phrase label (a card's `A1` heading) names no
    // figure, in any form.
    final (label, rest) = splitPhraseLabel(trimmed);
    if (label != null && rest.isEmpty) continue;
    final line =
        dropPhraseLabels && label != null && !_cornerCode.hasMatch(trimmed)
        ? FigureTextLine(text: rest, label: label)
        : FigureTextLine(text: trimmed);
    if (line.text.length > maxFreeTextEntryLength) {
      return const FigureTextLines._([], FigureTextRefusal.lineTooLong);
    }
    if (lines.length == maxFigureTextLines) {
      return const FigureTextLines._([], FigureTextRefusal.tooManyLines);
    }
    lines.add(line);
  }
  return FigureTextLines._(lines, null);
}

/// `C1 corner …` or `C2 corners …`: a corner dancer's code, which is also a
/// phrase label's spelling.
final RegExp _cornerCode = RegExp(r'^c[12]\s+corners?\b', caseSensitive: false);

/// A line break of any platform: `\r\n`, `\n`, a lone `\r`, and the Unicode
/// line and paragraph separators some apps put in copied text.
final RegExp _lineBreak = RegExp('\r\n|[\n\r\u2028\u2029\u0085]');
