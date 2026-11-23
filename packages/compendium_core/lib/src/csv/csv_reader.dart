/// A small RFC 4180 CSV reader for the spreadsheet import (#2329), beside the
/// writer the exports use (`csv_writer.dart`).
///
/// Pure Dart, no dependency. The file is untrusted, so every read is bounded:
/// [decodeCsvBytes] caps the bytes and refuses text that is not UTF-8, and
/// [readCsv] caps the rows, the columns and the length of one cell. Each limit
/// fails with a typed [CsvReadException] the app turns into its own message.
///
/// Excel in Danish, German, French and Dutch writes `;` between cells, so the
/// separator is detected from the header line ([detectCsvSeparator]) rather
/// than assumed.
library;

import 'dart:convert';

import 'csv_writer.dart' show csvByteOrderMark;

/// The most bytes a CSV import reads, as a shared archive's limit
/// (`kMaxIncomingArchiveBytes` in the app).
const int kMaxCsvImportBytes = 25 * 1024 * 1024;

/// The most records (rows, the header among them) a CSV import reads.
const int kMaxCsvImportRows = 20000;

/// The most columns one row may have.
const int kMaxCsvImportColumns = 200;

/// The most characters one cell may hold.
const int kMaxCsvImportCellChars = 65536;

/// The separators a CSV import recognises: comma, semicolon and tab.
const List<String> csvImportSeparators = [',', ';', '\t'];

/// Why a CSV could not be read.
enum CsvReadFailure {
  /// More bytes than [kMaxCsvImportBytes].
  tooLarge,

  /// Bytes that are not valid UTF-8, such as an old Excel "CSV" saved in
  /// Windows-1252.
  notUtf8,

  /// More rows than [kMaxCsvImportRows].
  tooManyRows,

  /// A row with more cells than [kMaxCsvImportColumns].
  tooManyColumns,

  /// A cell longer than [kMaxCsvImportCellChars].
  cellTooLong,

  /// A quoted cell that never closes.
  unterminatedQuote,
}

/// A CSV that could not be read, and why. [limit] is the cap that was passed,
/// for the message; [row] is the 1-based record where reading stopped, when
/// known.
class CsvReadException implements Exception {
  const CsvReadException(this.reason, {this.limit, this.row});

  final CsvReadFailure reason;
  final int? limit;
  final int? row;

  @override
  String toString() =>
      'CsvReadException(${reason.name}'
      '${limit == null ? '' : ', limit $limit'}'
      '${row == null ? '' : ', row $row'})';
}

/// [bytes] as text: refused when longer than [maxBytes] or not valid UTF-8,
/// with one leading byte-order mark removed.
String decodeCsvBytes(List<int> bytes, {int maxBytes = kMaxCsvImportBytes}) {
  if (bytes.length > maxBytes) {
    throw CsvReadException(CsvReadFailure.tooLarge, limit: maxBytes);
  }
  final String text;
  try {
    text = const Utf8Decoder(allowMalformed: false).convert(bytes);
  } on FormatException {
    throw const CsvReadException(CsvReadFailure.notUtf8);
  }
  return text.startsWith(csvByteOrderMark) ? text.substring(1) : text;
}

/// The separator [text] most likely uses: whichever of `,`, `;` and tab
/// occurs most often outside quotes on its first line (the header). A tie, or
/// a line with none, reads as a comma.
String detectCsvSeparator(String text) {
  final counts = {for (final s in csvImportSeparators) s: 0};
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') {
      inQuotes = !inQuotes;
    } else if (!inQuotes && (c == '\n' || c == '\r')) {
      break;
    } else if (!inQuotes && counts.containsKey(c)) {
      counts[c] = counts[c]! + 1;
    }
  }
  var best = ',';
  for (final s in csvImportSeparators) {
    if (counts[s]! > counts[best]!) best = s;
  }
  return best;
}

/// The records of [text], split on [separator] by RFC 4180's rules: a cell in
/// double quotes may hold the separator, line breaks and doubled quotes; a
/// record ends at CRLF, LF or CR. A leading byte-order mark is skipped, and a
/// final line break does not make an empty last record.
///
/// Throws [CsvReadException] past [maxRows], [maxColumns] or [maxCellChars],
/// or for a quoted cell that never closes.
List<List<String>> readCsv(
  String text, {
  String separator = ',',
  int maxRows = kMaxCsvImportRows,
  int maxColumns = kMaxCsvImportColumns,
  int maxCellChars = kMaxCsvImportCellChars,
}) {
  if (separator.length != 1) {
    throw ArgumentError.value(separator, 'separator', 'must be one character');
  }
  final input = text.startsWith(csvByteOrderMark) ? text.substring(1) : text;
  final records = <List<String>>[];
  var record = <String>[];
  final cell = StringBuffer();
  var cellLength = 0;
  var inQuotes = false;
  var quotedCellOpen = false;
  var recordHasContent = false;

  void addChar(String c) {
    cellLength++;
    if (cellLength > maxCellChars) {
      throw CsvReadException(
        CsvReadFailure.cellTooLong,
        limit: maxCellChars,
        row: records.length + 1,
      );
    }
    cell.write(c);
  }

  void endCell() {
    record.add(cell.toString());
    cell.clear();
    cellLength = 0;
    quotedCellOpen = false;
    if (record.length > maxColumns) {
      throw CsvReadException(
        CsvReadFailure.tooManyColumns,
        limit: maxColumns,
        row: records.length + 1,
      );
    }
  }

  void endRecord() {
    endCell();
    records.add(record);
    record = <String>[];
    recordHasContent = false;
    if (records.length > maxRows) {
      throw CsvReadException(CsvReadFailure.tooManyRows, limit: maxRows);
    }
  }

  var i = 0;
  while (i < input.length) {
    final c = input[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          addChar('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      addChar(c);
      i++;
      continue;
    }
    if (c == '"' && cellLength == 0 && !quotedCellOpen) {
      inQuotes = true;
      quotedCellOpen = true;
      recordHasContent = true;
      i++;
    } else if (c == separator) {
      endCell();
      recordHasContent = true;
      i++;
    } else if (c == '\r' || c == '\n') {
      endRecord();
      i += (c == '\r' && i + 1 < input.length && input[i + 1] == '\n') ? 2 : 1;
    } else {
      addChar(c);
      recordHasContent = true;
      i++;
    }
  }
  if (inQuotes) {
    throw CsvReadException(
      CsvReadFailure.unterminatedQuote,
      row: records.length + 1,
    );
  }
  if (recordHasContent || cellLength > 0 || record.isNotEmpty) endRecord();
  return records;
}
