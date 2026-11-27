/// A small RFC 4180 CSV writer for the spreadsheet exports (#2332).
///
/// Pure Dart, no dependency. Every file it writes uses the same dialect,
/// whatever the device's region (maintainer decision on #2332): a comma
/// separator, CRLF line ends, and UTF-8 text that starts with a byte-order
/// mark so Excel reads accented and Japanese text correctly.
library;

/// The byte-order mark every CSV file starts with. Written as text, it encodes
/// to the UTF-8 bytes `EF BB BF`.
const String csvByteOrderMark = '\uFEFF';

/// The separator between cells. Always a comma, never the locale's list
/// separator.
const String csvSeparator = ',';

/// The line end between records (RFC 4180).
const String csvLineEnd = '\r\n';

/// The MIME type of a CSV file.
const String csvMimeType = 'text/csv';

/// The file-name extension of a CSV file.
const String csvExtension = 'csv';

/// A plain decimal number, which no spreadsheet reads as a formula even when
/// it starts with a minus sign.
final RegExp _plainNumber = RegExp(r'^-?[0-9]+(\.[0-9]+)?$');

/// Characters that make a spreadsheet read a cell as a formula when the cell
/// starts with one (OWASP "CSV Injection"): `=`, `+`, `-`, `@`, a tab and a
/// carriage return, plus their full-width forms, which some spreadsheets in
/// Japanese treat the same way.
const Set<String> _formulaTriggers = {
  '=',
  '+',
  '-',
  '@',
  '\t',
  '\r',
  '＝', // ＝
  '＋', // ＋
  '－', // －
  '＠', // ＠
};

/// [value] made safe to open in a spreadsheet: a cell that starts with a
/// formula trigger gets a leading apostrophe, so the spreadsheet shows it as
/// text instead of running it. A plain number such as `-3` is left alone,
/// because no spreadsheet runs it.
///
/// Titles and notes can come from imported files, so every cell is guarded,
/// not only the ones a user typed.
///
/// A value that already starts with apostrophes before a formula trigger
/// (`'=x`) gets one more (`''=x`), so the import can take the guard off again
/// without taking the value's own apostrophe with it (`unguardCsvFormula`).
String guardCsvFormula(String value) =>
    _needsFormulaGuard(value) ? "'$value" : value;

/// Whether [guardCsvFormula] puts an apostrophe before [value]: after any
/// leading apostrophes, it starts with a formula trigger and is not a plain
/// number.
bool _needsFormulaGuard(String value) {
  var start = 0;
  while (start < value.length && value[start] == "'") {
    start++;
  }
  if (start == value.length) return false;
  if (!_formulaTriggers.contains(value[start])) return false;
  return !_plainNumber.hasMatch(value.substring(start));
}

/// One cell, guarded ([guardCsvFormula]) and quoted when RFC 4180 needs it: a
/// cell holding a comma, a double quote, a carriage return or a line feed is
/// wrapped in double quotes, with each quote inside doubled.
String encodeCsvCell(String value) {
  final guarded = guardCsvFormula(value);
  final needsQuotes =
      guarded.contains(csvSeparator) ||
      guarded.contains('"') ||
      guarded.contains('\r') ||
      guarded.contains('\n');
  if (!needsQuotes) return guarded;
  return '"${guarded.replaceAll('"', '""')}"';
}

/// The whole CSV file for [rows], each row one record: cells encoded by
/// [encodeCsvCell], separated by [csvSeparator], records ended by
/// [csvLineEnd], and the file started by [csvByteOrderMark].
///
/// The first row is usually the header. Rows need not be the same length; a
/// caller that wants a rectangular file pads them itself.
String encodeCsv(Iterable<List<String>> rows) {
  final buffer = StringBuffer(csvByteOrderMark);
  for (final row in rows) {
    buffer
      ..write(row.map(encodeCsvCell).join(csvSeparator))
      ..write(csvLineEnd);
  }
  return buffer.toString();
}
