/// The `, `-separated name lists in the spreadsheet exports (tags, tunes) and
/// the way the CSV import reads them back.
///
/// A name that holds a comma would split in two on re-import, so a list writes
/// a comma inside a name as `\,` and a backslash as `\\`. A name with neither
/// is written exactly as it always was, and a cell with no backslash splits as
/// it always did. A cell written before this existed reads the same, except
/// where a name itself held a backslash next to a comma or another backslash
/// (`a\, b` was two names, and is now one name `a, b`).
///
/// Reading: `\,` is a comma and `\\` a backslash, both part of the name. Any
/// other backslash (before another character, or last in the cell) stays a
/// literal backslash, so a hand-typed sheet is never mangled.
///
/// Only the comma can be protected. A tunes cell is also split on `;` and line
/// breaks ([splitNameList]'s `extraSeparators`), and a tune name holding one of
/// those still splits on re-import.
library;

/// The separator [joinNameList] writes between names.
const String csvNameListSeparator = ', ';

/// [name] with `\` written `\\` and `,` written `\,`.
String escapeNameListItem(String name) =>
    name.replaceAll(r'\', r'\\').replaceAll(',', r'\,');

/// [names] escaped by [escapeNameListItem] and joined with
/// [csvNameListSeparator].
String joinNameList(Iterable<String> names) =>
    names.map(escapeNameListItem).join(csvNameListSeparator);

/// Splits [cell] on every unescaped comma, and on each character of
/// [extraSeparators] (for example `;` and a line break in a tunes cell), then
/// unescapes `\,` and `\\` in each piece. Pieces are trimmed and empty ones
/// dropped.
///
/// [extraSeparators] are never escapable: a backslash before one stays literal.
List<String> splitNameList(
  String cell, {
  Set<String> extraSeparators = const {},
}) {
  final out = <String>[];
  final current = StringBuffer();
  void flush() {
    final name = current.toString().trim();
    if (name.isNotEmpty) out.add(name);
    current.clear();
  }

  for (var i = 0; i < cell.length; i++) {
    final c = cell[i];
    if (c == r'\' && i + 1 < cell.length) {
      final next = cell[i + 1];
      if (next == ',' || next == r'\') {
        current.write(next);
        i++;
        continue;
      }
    }
    if (c == ',' || extraSeparators.contains(c)) {
      flush();
    } else {
      current.write(c);
    }
  }
  flush();
  return out;
}
