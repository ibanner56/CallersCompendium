import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  const rows = [
    ['Title', 'Authors', 'Figures'],
    ['Petronella, revised', 'Mary "May" Example', 'A1 Balance\nA2 Swing'],
    ['Café à l\'école', 'ダンス', ''],
  ];

  group('readCsv', () {
    test('reads back what the writer writes', () {
      expect(readCsv(encodeCsv(rows)), rows);
    });

    for (final separator in [',', ';', '\t']) {
      test('reads cells split on ${jsonEncode(separator)} with quoted cells, '
          'embedded newlines, doubled quotes and a BOM', () {
        final text =
            '\uFEFF'
            'Title${separator}Notes\r\n'
            '"A$separator B"$separator"say ""hi""\nthen go"\r\n'
            'Plain${separator}x\n';
        expect(readCsv(text, separator: separator), [
          ['Title', 'Notes'],
          ['A$separator B', 'say "hi"\nthen go'],
          ['Plain', 'x'],
        ]);
      });
    }

    test('reads LF, CRLF and CR line ends, and no trailing record', () {
      expect(readCsv('a,b\nc,d\r\ne,f\rg,h\n'), [
        ['a', 'b'],
        ['c', 'd'],
        ['e', 'f'],
        ['g', 'h'],
      ]);
      expect(readCsv('a,b'), [
        ['a', 'b'],
      ]);
      expect(readCsv(''), isEmpty);
    });

    test('keeps empty cells', () {
      expect(readCsv('a,,c,\n'), [
        ['a', '', 'c', ''],
      ]);
    });

    test('refuses a quoted cell that never closes', () {
      expect(
        () => readCsv('a,"open\nstill open'),
        throwsA(
          isA<CsvReadException>().having(
            (e) => e.reason,
            'reason',
            CsvReadFailure.unterminatedQuote,
          ),
        ),
      );
    });

    test('refuses more rows than the cap', () {
      final text = List.filled(4, 'a,b').join('\n');
      expect(readCsv(text, maxRows: 4), hasLength(4));
      expect(
        () => readCsv(text, maxRows: 3),
        throwsA(
          isA<CsvReadException>()
              .having((e) => e.reason, 'reason', CsvReadFailure.tooManyRows)
              .having((e) => e.limit, 'limit', 3),
        ),
      );
    });

    test('refuses a row with more columns than the cap', () {
      expect(readCsv('a,b,c', maxColumns: 3).single, hasLength(3));
      expect(
        () => readCsv('a,b,c', maxColumns: 2),
        throwsA(
          isA<CsvReadException>().having(
            (e) => e.reason,
            'reason',
            CsvReadFailure.tooManyColumns,
          ),
        ),
      );
    });

    test('refuses a cell longer than the cap', () {
      expect(readCsv('"abcd",e', maxCellChars: 4).single, ['abcd', 'e']);
      expect(
        () => readCsv('"abcde",e', maxCellChars: 4),
        throwsA(
          isA<CsvReadException>().having(
            (e) => e.reason,
            'reason',
            CsvReadFailure.cellTooLong,
          ),
        ),
      );
    });
  });

  group('detectCsvSeparator', () {
    test('picks the separator the header line uses most', () {
      expect(detectCsvSeparator('Title;Authors;Notes\na,b;c'), ';');
      expect(detectCsvSeparator('Title\tAuthors\tNotes\n'), '\t');
      expect(detectCsvSeparator('Title,Authors,Notes\n'), ',');
    });

    test('ignores separators inside quotes, and defaults to a comma', () {
      expect(detectCsvSeparator('"a;b;c;d",x,y\n'), ',');
      expect(detectCsvSeparator('Title\n'), ',');
    });
  });

  group('decodeCsvBytes', () {
    test('decodes UTF-8 and drops a byte-order mark', () {
      expect(
        decodeCsvBytes([0xEF, 0xBB, 0xBF, ...utf8.encode('Café')]),
        'Café',
      );
      expect(decodeCsvBytes(utf8.encode('Café')), 'Café');
    });

    test('refuses bytes that are not UTF-8', () {
      // "Café" in Windows-1252: 0xE9 alone is not valid UTF-8.
      expect(
        () => decodeCsvBytes([0x43, 0x61, 0x66, 0xE9]),
        throwsA(
          isA<CsvReadException>().having(
            (e) => e.reason,
            'reason',
            CsvReadFailure.notUtf8,
          ),
        ),
      );
    });

    test('refuses more bytes than the cap', () {
      expect(decodeCsvBytes(List.filled(8, 0x61), maxBytes: 8), 'aaaaaaaa');
      expect(
        () => decodeCsvBytes(List.filled(9, 0x61), maxBytes: 8),
        throwsA(
          isA<CsvReadException>().having(
            (e) => e.reason,
            'reason',
            CsvReadFailure.tooLarge,
          ),
        ),
      );
    });
  });
}
