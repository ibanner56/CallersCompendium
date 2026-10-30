import 'dart:ui' show Locale;

import 'package:compendium_app/l10n/app_localizations_en.dart';
import 'package:compendium_app/src/data/custom_date_pattern.dart';
import 'package:compendium_app/src/data/regional_formats.dart';
import 'package:flutter/material.dart' show DefaultMaterialLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalMaterialLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;

void main() {
  // The app registers date symbols for every locale Flutter ships when its
  // localizations delegate first loads; do the same so the region lookup under
  // test sees the data it sees at runtime.
  setUpAll(() => GlobalMaterialLocalizations.delegate.load(const Locale('en')));

  group('dateFormatPrefFromStored', () {
    test('defaults to system when unset (null)', () {
      expect(dateFormatPrefFromStored(null), DateFormatPref.system);
    });

    test('resolves each known token to its enum', () {
      expect(dateFormatPrefFromStored('system'), DateFormatPref.system);
      expect(dateFormatPrefFromStored('ymd'), DateFormatPref.ymd);
      expect(dateFormatPrefFromStored('dmy'), DateFormatPref.dmy);
      expect(dateFormatPrefFromStored('mdy'), DateFormatPref.mdy);
      expect(dateFormatPrefFromStored('custom'), DateFormatPref.custom);
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
      expect(
        formatDatePattern(date, DateFormatSetting(DateFormatPref.system)),
        isNull,
      );
    });

    test('formats the fixed tokens with zero-padding', () {
      expect(
        formatDatePattern(date, DateFormatSetting(DateFormatPref.ymd)),
        '2026-07-15',
      );
      expect(
        formatDatePattern(date, DateFormatSetting(DateFormatPref.dmy)),
        '15/07/2026',
      );
      expect(
        formatDatePattern(date, DateFormatSetting(DateFormatPref.mdy)),
        '07/15/2026',
      );
    });

    test('zero-pads single-digit month and day', () {
      final early = DateTime(2026, 1, 3);
      expect(
        formatDatePattern(early, DateFormatSetting(DateFormatPref.ymd)),
        '2026-01-03',
      );
      expect(
        formatDatePattern(early, DateFormatSetting(DateFormatPref.dmy)),
        '03/01/2026',
      );
      expect(
        formatDatePattern(early, DateFormatSetting(DateFormatPref.mdy)),
        '01/03/2026',
      );
    });

    test('renders a valid custom pattern; falls back (null) when invalid', () {
      expect(
        formatDatePattern(
          date,
          DateFormatSetting(DateFormatPref.custom, customPattern: 'MM.dd.yy'),
        ),
        '07.15.26',
      );
      expect(
        formatDatePattern(
          date,
          DateFormatSetting(DateFormatPref.custom, customPattern: 'yyyy/MM/dd'),
        ),
        '2026/07/15',
      );
      // Invalid pattern ⇒ null ⇒ caller uses the platform locale (system).
      expect(
        formatDatePattern(
          date,
          DateFormatSetting(DateFormatPref.custom, customPattern: 'nope'),
        ),
        isNull,
      );
      // Custom pref with a null pattern also defers to the system default.
      expect(
        formatDatePattern(date, DateFormatSetting(DateFormatPref.custom)),
        isNull,
      );
    });
  });

  group('formatEventDate', () {
    const material = DefaultMaterialLocalizations();
    final l10n = AppLocalizationsEn();

    test('uses the fixed pattern for non-system prefs', () {
      final date = DateTime(2026, 7, 15);
      expect(
        formatEventDate(
          date,
          DateFormatSetting(DateFormatPref.ymd),
          material,
          l10n,
        ),
        '2026-07-15',
      );
      expect(
        formatEventDate(
          date,
          DateFormatSetting(DateFormatPref.dmy),
          material,
          l10n,
        ),
        '15/07/2026',
      );
      expect(
        formatEventDate(
          date,
          DateFormatSetting(DateFormatPref.mdy),
          material,
          l10n,
        ),
        '07/15/2026',
      );
    });

    test('renders a valid custom pattern', () {
      final date = DateTime(2026, 7, 15);
      expect(
        formatEventDate(
          date,
          DateFormatSetting(DateFormatPref.custom, customPattern: 'MM.DD.YY'),
          material,
          l10n,
        ),
        '07.15.26',
      );
    });

    test('renders localized written-out month tokens (MMM / MMMM)', () {
      final date = DateTime(2026, 7, 15);
      expect(
        formatEventDate(
          date,
          DateFormatSetting(
            DateFormatPref.custom,
            customPattern: 'dd MMM yyyy',
          ),
          material,
          l10n,
        ),
        '15 Jul 2026',
      );
      expect(
        formatEventDate(
          date,
          DateFormatSetting(
            DateFormatPref.custom,
            customPattern: 'MMMM dd yyyy',
          ),
          material,
          l10n,
        ),
        'July 15 2026',
      );
    });

    final date = DateTime(2026, 7, 15);
    const system = DateFormatSetting.system;

    String sys(Locale platform, [DateFormatSetting setting = system]) =>
        formatEventDate(
          date,
          setting,
          material,
          l10n,
          platformLocale: platform,
        );

    test('system carries the year in the device locale\'s order', () {
      expect(sys(const Locale('en', 'US')), '7/15/2026');
      expect(sys(const Locale('en', 'GB')), '15/07/2026');
      expect(sys(const Locale('da', 'DK')), '15.7.2026');
      expect(sys(const Locale('ja', 'JP')), '2026/7/15');
    });

    test('system follows the region, not the app language (PLAT-12)', () {
      // l10n is English; the Danish-region phone still gets Danish numerals
      // order, and no month name from either language appears.
      final out = sys(const Locale('da', 'DK'));
      expect(out, isNot('7/15/2026'));
      expect(out, isNot(contains('Jul')));
      expect(out, isNot(contains('jul')));
    });

    test('a locale tag with a script subtag still resolves', () {
      expect(
        sys(
          Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hans',
            countryCode: 'CN',
          ),
        ),
        '2026/7/15',
      );
    });

    test('an unresolvable tag falls back to the app-language short date', () {
      expect(sys(const Locale('xx', 'YY')), material.formatShortDate(date));
    });

    test('a shipped regional variant is honoured (en_GB, fr_CA)', () {
      expect(sys(const Locale('en', 'GB')), '15/07/2026');
      expect(sys(const Locale('fr', 'CA')), '2026-07-15');
    });

    test('an English device in a country with no English variant follows the '
        'country, not US order (en_DK, en_SE, en_NL)', () {
      expect(sys(const Locale('en', 'DK')), '15.7.2026');
      expect(sys(const Locale('en', 'SE')), '2026-07-15');
      expect(sys(const Locale('en', 'NL')), '15-7-2026');
      expect(sys(const Locale('en', 'DE')), '15.7.2026');
    });

    test('a country with exactly one shipped variant uses it (en_MX)', () {
      // es_MX is the only `_MX` set, and has day-first order; plain `en` is US.
      expect(sys(const Locale('en', 'MX')), '15/7/2026');
    });

    test('a multilingual or unlisted country keeps the language default', () {
      // BE is deliberately not in kRegionDateLocales (nl, fr and de all apply);
      // a country-code-equals-language-code rule would wrongly pick Belarusian.
      expect(sys(const Locale('en', 'BE')), '7/15/2026');
      expect(sys(const Locale('en', 'ZZ')), '7/15/2026');
    });

    test('a language-only device locale uses the language default', () {
      expect(sys(const Locale('en')), '7/15/2026');
      expect(sys(const Locale('da')), '15.7.2026');
    });

    test('an invalid custom pattern follows the device locale too', () {
      expect(
        sys(
          const Locale('da', 'DK'),
          DateFormatSetting(DateFormatPref.custom, customPattern: 'bogus'),
        ),
        '15.7.2026',
      );
    });
  });

  group('dateFormatSettingFromStored (#584)', () {
    test('resolves fixed prefs, ignoring any stray custom pattern', () {
      final setting = dateFormatSettingFromStored('ymd', 'MM.DD.YY');
      expect(setting.pref, DateFormatPref.ymd);
      expect(setting.customPattern, isNull);
    });

    test('carries a short custom pattern for the custom pref', () {
      final setting = dateFormatSettingFromStored('custom', 'MM.DD.YY');
      expect(setting.pref, DateFormatPref.custom);
      expect(setting.customPattern, 'MM.DD.YY');
      expect(setting.effectivePattern, isNotNull);
    });

    test('carries a short-but-unparseable pattern so the UI can show it, but '
        'consumers treat it as system', () {
      final setting = dateFormatSettingFromStored('custom', 'nope');
      expect(setting.pref, DateFormatPref.custom);
      expect(setting.customPattern, 'nope');
      expect(setting.effectivePattern, isNull);
      expect(setting.hasInvalidCustomPattern, isTrue);
    });

    test('custom pref with a null/non-string/empty pattern collapses to '
        'system', () {
      expect(
        dateFormatSettingFromStored('custom', null),
        DateFormatSetting.system,
      );
      expect(
        dateFormatSettingFromStored('custom', 3),
        DateFormatSetting.system,
      );
      expect(
        dateFormatSettingFromStored('custom', ''),
        DateFormatSetting.system,
      );
    });

    test('custom pref with an over-long pattern collapses to system', () {
      final tooLong = 'y' * (kMaxCustomDatePatternLength + 1);
      expect(
        dateFormatSettingFromStored('custom', tooLong),
        DateFormatSetting.system,
      );
    });

    test('garbage/unknown pref token resolves to system', () {
      expect(
        dateFormatSettingFromStored('nope', null),
        DateFormatSetting.system,
      );
      expect(dateFormatSettingFromStored(null, null), DateFormatSetting.system);
      expect(
        dateFormatSettingFromStored(7, 'MM.DD.YY'),
        DateFormatSetting.system,
      );
    });
  });

  group('DateFormatSetting value semantics', () {
    test('equality is by pref + customPattern', () {
      expect(
        DateFormatSetting(DateFormatPref.custom, customPattern: 'MM.DD.YY'),
        DateFormatSetting(DateFormatPref.custom, customPattern: 'MM.DD.YY'),
      );
      expect(
        DateFormatSetting(DateFormatPref.custom, customPattern: 'MM.DD.YY'),
        isNot(
          DateFormatSetting(DateFormatPref.custom, customPattern: 'DD.MM.YY'),
        ),
      );
      expect(
        DateFormatSetting.system,
        DateFormatSetting(DateFormatPref.system),
      );
    });
  });

  group('regional-format constants (G.8)', () {
    test('use their stable stored key', () {
      expect(kDateFormatKey, 'date_format');
      expect(kDateFormatCustomPatternKey, 'date_format_custom');
      expect(kFirstDayOfWeekKey, 'first_day_of_week');
    });

    test('enum tokens are stable', () {
      expect(DateFormatPref.system.token, 'system');
      expect(DateFormatPref.ymd.token, 'ymd');
      expect(DateFormatPref.dmy.token, 'dmy');
      expect(DateFormatPref.mdy.token, 'mdy');
      expect(DateFormatPref.custom.token, 'custom');
    });
  });

  group('firstDayOfWeekPrefFromStored', () {
    test('defaults to system when unset (null)', () {
      expect(firstDayOfWeekPrefFromStored(null), FirstDayOfWeekPref.system);
    });

    test('resolves each known token to its enum', () {
      expect(firstDayOfWeekPrefFromStored('system'), FirstDayOfWeekPref.system);
      expect(firstDayOfWeekPrefFromStored('sunday'), FirstDayOfWeekPref.sunday);
      expect(firstDayOfWeekPrefFromStored('monday'), FirstDayOfWeekPref.monday);
      expect(
        firstDayOfWeekPrefFromStored('saturday'),
        FirstDayOfWeekPref.saturday,
      );
    });

    test('falls back to system for garbage: unknown token, non-string', () {
      expect(firstDayOfWeekPrefFromStored('nope'), FirstDayOfWeekPref.system);
      expect(firstDayOfWeekPrefFromStored(''), FirstDayOfWeekPref.system);
      expect(firstDayOfWeekPrefFromStored(7), FirstDayOfWeekPref.system);
      expect(
        firstDayOfWeekPrefFromStored(<String>['monday']),
        FirstDayOfWeekPref.system,
      );
    });

    test('startWeekday maps to the DateTime weekday constant (null for '
        'system)', () {
      expect(FirstDayOfWeekPref.system.startWeekday, isNull);
      expect(FirstDayOfWeekPref.sunday.startWeekday, DateTime.sunday);
      expect(FirstDayOfWeekPref.monday.startWeekday, DateTime.monday);
      expect(FirstDayOfWeekPref.saturday.startWeekday, DateTime.saturday);
    });

    test('tokens are stable', () {
      expect(FirstDayOfWeekPref.system.token, 'system');
      expect(FirstDayOfWeekPref.sunday.token, 'sunday');
      expect(FirstDayOfWeekPref.monday.token, 'monday');
      expect(FirstDayOfWeekPref.saturday.token, 'saturday');
    });
  });

  group('orderedWeekdays (ROADMAP G.8 consumer)', () {
    const material = DefaultMaterialLocalizations();

    test('starts at the preference for each fixed option', () {
      expect(orderedWeekdays(FirstDayOfWeekPref.monday, material), [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
      ]);
      expect(orderedWeekdays(FirstDayOfWeekPref.sunday, material), [
        7,
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
      expect(orderedWeekdays(FirstDayOfWeekPref.saturday, material), [
        6,
        7,
        1,
        2,
        3,
        4,
        5,
      ]);
    });

    test('system falls back to the locale (DefaultMaterialLocalizations is '
        'Sunday-first)', () {
      expect(
        orderedWeekdays(FirstDayOfWeekPref.system, material),
        orderedWeekdays(FirstDayOfWeekPref.sunday, material),
      );
    });

    test('always returns all seven weekdays exactly once', () {
      for (final pref in FirstDayOfWeekPref.values) {
        final order = orderedWeekdays(pref, material);
        expect(order.length, 7);
        expect(order.toSet(), {1, 2, 3, 4, 5, 6, 7});
      }
    });
  });

  group('kRegionDateLocales drift', () {
    test('every value is a date-symbol locale intl ships', () {
      for (final MapEntry(:key, :value) in kRegionDateLocales.entries) {
        expect(
          DateFormat.localeExists(value),
          isTrue,
          reason: '$key maps to $value, which intl has no date symbols for',
        );
      }
    });

    test('every key is an upper-case ISO region code', () {
      for (final key in kRegionDateLocales.keys) {
        expect(key, matches(RegExp(r'^[A-Z]{2}$')));
      }
    });

    test('no key already has its own shipped regional variant', () {
      // Such a country is resolved by resolveDateLocale before the table, so an
      // entry would be dead and would hide a later change to the shipped list.
      final shipped = DateFormat.allLocalesWithSymbols();
      for (final key in kRegionDateLocales.keys) {
        expect(
          shipped.where((l) => l.toUpperCase().endsWith('_$key')),
          isEmpty,
          reason: '$key now has a shipped variant; drop it from the table',
        );
      }
    });
  });
}
