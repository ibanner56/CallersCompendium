/// `Label: value` lines and `by …` author lines, as a dance written out as
/// text carries its details: shared by the Caller's Companion text adapter and
/// the text and Markdown file import (#2330).
library;

/// An author line written `by Name` (any case).
final RegExp _byLine = RegExp(r'^by\s+(.+)$', caseSensitive: false);

/// Splits a `Label: value` line into its label, trimmed and as written, and
/// its trimmed value; null when [line] is not one.
///
/// The label is what comes before the first `:`. It must be non-empty and at
/// most [maxWords] words, so a sentence that happens to hold a colon is not
/// read as a label. The Caller's Companion text adapter keeps its one-word
/// labels (`Formation:`, `DateComposed:`); a text file's labels may be a few
/// words (`Calling notes:`).
(String, String)? splitLabelLine(String line, {int maxWords = 1}) {
  final idx = line.indexOf(':');
  if (idx <= 0) return null;
  final label = line.substring(0, idx).trim();
  final value = line.substring(idx + 1).trim();
  if (label.isEmpty) return null;
  if (label.split(_spaces).length > maxWords) return null;
  return (label, value);
}

/// The names part of a `by Name` author line, trimmed, or null when [line] is
/// not one. The names are one raw field: splitting several names is the
/// shared author tokenizer's job (`splitAuthorNames`).
String? splitByLine(String line) {
  final names = _byLine.firstMatch(line)?.group(1)?.trim();
  return names == null || names.isEmpty ? null : names;
}

final RegExp _spaces = RegExp(r'\s+');
