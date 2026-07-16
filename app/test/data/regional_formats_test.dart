import 'package:compendium_app/src/data/regional_formats.dart';
import 'package:flutter/material.dart' show DefaultMaterialLocalizations;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dateFormatPrefFromStored', () {
    test('defaults to system when unset (null)', () {
      expect(dateFormatPrefFromStored(null), DateFormatPref.system);
    });

    test('resolves each known token to its enum', () {
      expect(dateFormatPrefFromStored('system'), DateFormatPref.system);
      expect(dateFormatPrefFromStored('ymd'), DateFormatPref.ymd);
      expect(dateFormatPrefFromStored('dmy'), DateFormatPref.dmy);
      expect(dateFormatPrefFromStored('mdy'), DateFormatPref.mdy);
    });

    test('falls back to system for garbage: unknown token, non-string', () {
      expect(dateFormatPrefFromStored('nope'), DateFormatPref.system);
      expect(dateFormatPrefFromStored(''), DateFormatPref.system);
      expect(dateFormatPrefFromStored(3), DateFormatPref.system);
      expect(dateFormatPrefFromStored(<String>['ymd']), DateFormatPref.system);
    });
  });

  group('formatDatePattern', () {
    final date = DateTime(2026, 7, 15);

    test('returns null for system (defers to the platform locale)', () {
      expect(formatDatePattern(date, DateFormatPref.system), isNull);
    });

    test('formats the fixed tokens with zero-padding', () {
      expect(formatDatePattern(date, DateFormatPref.ymd), '2026-07-15');
      expect(formatDatePattern(date, DateFormatPref.dmy), '15/07/2026');
      expect(formatDatePattern(date, DateFormatPref.mdy), '07/15/2026');
    });

    test('zero-pads single-digit month and day', () {
      final early = DateTime(2026, 1, 3);
      expect(formatDatePattern(early, DateFormatPref.ymd), '2026-01-03');
      expect(formatDatePattern(early, DateFormatPref.dmy), '03/01/2026');
      expect(formatDatePattern(early, DateFormatPref.mdy), '01/03/2026');
    });
  });

  group('formatEventDate', () {
    const l10n = DefaultMaterialLocalizations();

    test('uses the fixed pattern for non-system prefs', () {
      final date = DateTime(2026, 7, 15);
      expect(formatEventDate(date, DateFormatPref.ymd, l10n), '2026-07-15');
      expect(formatEventDate(date, DateFormatPref.dmy, l10n), '15/07/2026');
      expect(formatEventDate(date, DateFormatPref.mdy, l10n), '07/15/2026');
    });

    test('defers to the localization medium date for system', () {
      final date = DateTime(2026, 7, 15);
      expect(
        formatEventDate(date, DateFormatPref.system, l10n),
        l10n.formatMediumDate(date),
      );
    });
  });

  group('regional-format constants (G.8)', () {
    test('use their stable stored key', () {
      expect(kDateFormatKey, 'date_format');
    });

    test('enum tokens are stable', () {
      expect(DateFormatPref.system.token, 'system');
      expect(DateFormatPref.ymd.token, 'ymd');
      expect(DateFormatPref.dmy.token, 'dmy');
      expect(DateFormatPref.mdy.token, 'mdy');
    });
  });
}
