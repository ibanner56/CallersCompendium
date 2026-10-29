import 'dart:convert';

import 'package:compendium_app/src/utils/safe_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('replaceUnsafeNameChars', () {
    test('replaces path separators and other unsafe characters with _', () {
      expect(replaceUnsafeNameChars('a/b\\c'), 'a_b_c');
      expect(
        replaceUnsafeNameChars('Friday Contra: 3/9'),
        'Friday_Contra__3_9',
      );
    });

    test('preserves the safe [A-Za-z0-9._-] set', () {
      expect(
        replaceUnsafeNameChars('spring-fling_2026.v1'),
        'spring-fling_2026.v1',
      );
    });

    test('replaces control characters', () {
      expect(replaceUnsafeNameChars('a\u0000b\tc\nd'), 'a_b_c_d');
    });
  });

  group('sanitizeExportName', () {
    test('replaces path separators so no traversal reaches the name', () {
      final name = sanitizeExportName('../../etc/passwd');
      expect(name.contains('/'), isFalse);
      expect(name.contains('..'), isFalse, reason: 'leading dots are stripped');
      expect(name, 'etc_passwd');
    });

    test('strips control characters and spaces', () {
      expect(sanitizeExportName('Rory O\u0007More'), 'Rory_O_More');
    });

    test('keeps safe characters untouched', () {
      expect(
        sanitizeExportName('spring-fling_2026.v1'),
        'spring-fling_2026.v1',
      );
    });

    test('trims surrounding whitespace before sanitizing', () {
      expect(sanitizeExportName('  Mad Robin  '), 'Mad_Robin');
    });

    test('strips leading/trailing dots so the name is never a dotfile', () {
      expect(sanitizeExportName('...hidden...'), 'hidden');
      expect(sanitizeExportName('.'), 'export');
      expect(sanitizeExportName('..'), 'export');
    });

    test('falls back for empty, whitespace-only, or all-illegal input', () {
      expect(sanitizeExportName(''), 'export');
      expect(sanitizeExportName('   '), 'export');
      expect(sanitizeExportName('///'), 'export');
    });

    test('honours a caller-provided fallback', () {
      expect(sanitizeExportName('', fallback: 'dance'), 'dance');
      expect(sanitizeExportName('///', fallback: 'program'), 'program');
    });

    test('sanitizes an unsafe fallback rather than returning it raw', () {
      // Regression (#468 review): a caller-supplied fallback must not bypass
      // the sanitizer. 'Programming matrix' carries a space — it must be
      // reduced to the safe set, never leaked into the print-job name.
      expect(
        sanitizeExportName('', fallback: 'Programming matrix'),
        'Programming_matrix',
      );
      expect(sanitizeExportName('   ', fallback: 'my/report'), 'my_report');
      final matrix = sanitizeExportName('///', fallback: 'Programming matrix');
      expect(matrix.contains(' '), isFalse);
      expect(matrix.contains('/'), isFalse);
    });

    test(
      'falls back to the stable "export" when the fallback is also unsafe',
      () {
        expect(sanitizeExportName('', fallback: '///'), 'export');
        expect(sanitizeExportName('///', fallback: '   '), 'export');
        expect(sanitizeExportName('', fallback: '..'), 'export');
      },
    );
  });

  group('shareFileBaseName', () {
    test('keeps letters and digits of any script', () {
      expect(
        shareFileBaseName('Contredanse à la française', fallback: 'dance'),
        'Contredanse_à_la_française',
      );
      expect(shareFileBaseName('春のコントラ 2', fallback: 'dance'), '春のコントラ_2');
      // A decomposed accent (letter + combining mark) survives intact.
      expect(shareFileBaseName('Cafe\u0301', fallback: 'dance'), 'Cafe\u0301');
    });

    test('strips leading and trailing separators', () {
      expect(
        shareFileBaseName("Ain't She Sweet?", fallback: 'd'),
        'Ain_t_She_Sweet',
      );
      expect(shareFileBaseName('..hidden..', fallback: 'd'), 'hidden');
    });

    test('never lets a path separator or control character through', () {
      final name = shareFileBaseName('a/b\\c\u0000d\u202ee', fallback: 'd');
      expect(name, 'a_b_c_d_e');
    });

    test('falls back when no letter or digit remains', () {
      expect(shareFileBaseName('   ', fallback: 'dance'), 'dance');
      expect(shareFileBaseName('?!/', fallback: 'dance'), 'dance');
      expect(shareFileBaseName('..', fallback: 'dance'), 'dance');
    });

    test('cuts a long title so the whole name fits a file system', () {
      final name = shareFileBaseName('あ' * 200, fallback: 'd');
      expect(name, 'あ' * 64);
      // The date and extension still fit in 255 bytes of UTF-8.
      expect(
        utf8
            .encode(
              '${shareFileBaseName('あ' * 200, fallback: 'd', eventDate: DateTime(2026, 3, 9))}.ccshare',
            )
            .length,
        lessThan(255),
      );
      // A cut that lands on a separator does not leave one at the end.
      expect(shareFileBaseName('${'a' * 63}?tail', fallback: 'd'), 'a' * 63);
    });

    test('appends the event date', () {
      expect(
        shareFileBaseName(
          'Sat',
          fallback: 'p',
          eventDate: DateTime(2026, 3, 9),
        ),
        'Sat_2026-03-09',
      );
    });
  });

  group('programPdfJobName', () {
    test('is the sanitized title with the event date', () {
      expect(
        programPdfJobName(
          'Saturday Contra',
          fallback: 'program',
          eventDate: DateTime(2026, 10, 31),
        ),
        'Saturday_Contra_2026-10-31',
      );
    });

    test('the matrix suffix keeps it apart from the set-list job name', () {
      final date = DateTime(2026, 10, 31);
      final setList = programPdfJobName(
        'Night',
        fallback: 'program',
        eventDate: date,
      );
      final matrix = programPdfJobName(
        'Night',
        fallback: 'program',
        suffix: 'Programming matrix',
        eventDate: date,
      );
      expect(matrix, 'Night_Programming_matrix_2026-10-31');
      expect(matrix, isNot(setList));
    });

    test('a non-Latin suffix still names the matrix', () {
      expect(
        programPdfJobName(
          'Night',
          fallback: 'program',
          suffix: 'プログラミングマトリックス',
          eventDate: DateTime(2026, 10, 31),
        ),
        'Night_Programming_matrix_2026-10-31',
      );
    });

    test('an untitled matrix in a non-Latin locale is not named "export"', () {
      expect(
        programPdfJobName(
          '',
          fallback: 'プログラミングマトリックス',
          suffix: 'プログラミングマトリックス',
        ),
        'Programming_matrix',
      );
    });

    test('an untitled matrix is not named twice', () {
      expect(
        programPdfJobName(
          '',
          fallback: 'Programming matrix',
          suffix: 'Programming matrix',
        ),
        'Programming_matrix',
      );
    });

    test('uses the fallback for an untitled program', () {
      expect(programPdfJobName('', fallback: 'program'), 'program');
    });
  });
}
