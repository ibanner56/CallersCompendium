/// A deliberately literal RFC 4180 reader for tests: comma separator, quoted
/// cells with doubled quotes, CRLF record ends, and a leading UTF-8 byte-order
/// mark skipped. It shares no code with the writer, so a round trip through it
/// checks the writer against the RFC rather than against itself.
List<List<String>> readRfc4180(String text) {
  var input = text;
  if (input.startsWith('﻿')) input = input.substring(1);
  final records = <List<String>>[];
  var record = <String>[];
  final cell = StringBuffer();
  var i = 0;
  var inQuotes = false;
  var atRecordStart = true;
  while (i < input.length) {
    final c = input[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          cell.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      cell.write(c);
      i++;
      continue;
    }
    if (c == '"' && cell.isEmpty) {
      inQuotes = true;
      atRecordStart = false;
      i++;
    } else if (c == ',') {
      record.add(cell.toString());
      cell.clear();
      atRecordStart = false;
      i++;
    } else if (c == '\r' && i + 1 < input.length && input[i + 1] == '\n') {
      record.add(cell.toString());
      cell.clear();
      records.add(record);
      record = <String>[];
      atRecordStart = true;
      i += 2;
    } else {
      cell.write(c);
      atRecordStart = false;
      i++;
    }
  }
  if (!atRecordStart) {
    record.add(cell.toString());
    records.add(record);
  }
  return records;
}
