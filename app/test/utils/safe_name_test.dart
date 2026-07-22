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
  });
}
