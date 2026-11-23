import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'rfc4180_test_reader.dart';

void main() {
  group('encodeCsv', () {
    test('starts with a UTF-8 byte-order mark and ends records with CRLF', () {
      final csv = encodeCsv([
        ['a', 'b'],
        ['c', 'd'],
      ]);
      final bytes = utf8.encode(csv);
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(csv, '\uFEFFa,b\r\nc,d\r\n');
    });

    test('quotes commas, quotes and line breaks, and survives an RFC 4180 '
        'read', () {
      const rows = [
        ['Title', 'Notes'],
        ['Petronella, revised', 'Say "balance" early'],
        ['Rory O\'More', 'Line one\nLine two\r\nLine three'],
        ['Café à l\'école', 'ダンス・コール'],
        ['', ' leading and trailing space '],
      ];
      final csv = encodeCsv(rows);
      expect(csv, contains('"Petronella, revised"'));
      expect(csv, contains('"Say ""balance"" early"'));
      expect(readRfc4180(csv), rows);
    });

    test('writes accented and Japanese text as UTF-8', () {
      final csv = encodeCsv([
        ['Café', 'ダンス'],
      ]);
      expect(utf8.encode(csv), [
        0xEF, 0xBB, 0xBF, // byte-order mark
        ...utf8.encode('Café,ダンス'),
        0x0D, 0x0A,
      ]);
      expect(utf8.encode('é'), [0xC3, 0xA9]);
    });
  });

  group('guardCsvFormula', () {
    for (final value in [
      '=HYPERLINK("http://example.invalid","click")',
      '+1+1',
      '-1+1',
      '@SUM(A1)',
      '\t=1',
      '\r=1',
      '＝1+1',
      '＋1',
      '－1',
      '＠SUM(A1)',
    ]) {
      test('makes ${jsonEncode(value)} text', () {
        expect(guardCsvFormula(value), "'$value");
        final read = readRfc4180(
          encodeCsv([
            [value],
          ]),
        );
        expect(read.single.single, "'$value");
      });
    }

    for (final value in ['', 'Petronella', '-3', '-2.5', '42', "'quoted"]) {
      test('leaves ${jsonEncode(value)} as it is', () {
        expect(guardCsvFormula(value), value);
      });
    }
  });
}
