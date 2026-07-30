import 'package:compendium_app/src/data/program_title_date.dart';
import 'package:compendium_app/src/data/regional_formats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detectEventDateFromTitle — high-confidence positives', () {
    test('ISO YYYY-MM-DD anywhere in the title', () {
      expect(
        detectEventDateFromTitle(
          '2024-03-15 Friday Contra',
          DateFormatSetting(DateFormatPref.system),
        ),
        DateTime.utc(2024, 3, 15),
      );
    });

    test('ISO with slash and dot separators', () {
      expect(
        detectEventDateFromTitle(
          '2016/12/05: Louisville',
          DateFormatSetting(DateFormatPref.system),
        ),
        DateTime.utc(2016, 12, 5),
      );
      expect(
        detectEventDateFromTitle(
          '2019.01.07 Chicago',
          DateFormatSetting(DateFormatPref.system),
        ),
        DateTime.utc(2019, 1, 7),
      );
    });

    test('month name then day and year', () {
      expect(
        detectEventDateFromTitle(
          'March 15 2024 Spring Fling',
          DateFormatSetting(DateFormatPref.system),
        ),
        DateTime.utc(2024, 3, 15),
      );
      expect(
        detectEventDateFromTitle(
          'Mar 15, 2024',
          DateFormatSetting(DateFormatPref.system),
        ),
        DateTime.utc(2024, 3, 15),
      );
      expect(
        detectEventDateFromTitle(
          'December 1st, 2018 Harrisburg',
          DateFormatSetting(DateFormatPref.system),
        ),
        DateTime.utc(2018, 12, 1),
      );
    });

    test('day then month name and year', () {
      expect(
        detectEventDateFromTitle(
          '15 March 2024 Barn Dance',
          DateFormatSetting(DateFormatPref.system),
        ),
        DateTime.utc(2024, 3, 15),
      );
      expect(
        detectEventDateFromTitle(
          '1st April 2023',
          DateFormatSetting(DateFormatPref.system),
        ),
        DateTime.utc(2023, 4, 1),
      );
    });

    test('numeric 4-digit-year-last, order forced when a field > 12', () {
      // 15 cannot be a month → day=15, month=3.
      expect(
        detectEventDateFromTitle(
          '3/15/2024 Contra',
          DateFormatSetting(DateFormatPref.system),
        ),
        DateTime.utc(2024, 3, 15),
      );
      // 25 cannot be a month → day=25, month=12 (DMY forced).
      expect(
        detectEventDateFromTitle(
          '25.12.2023',
          DateFormatSetting(DateFormatPref.system),
        ),
        DateTime.utc(2023, 12, 25),
      );
    });

    test('ambiguous numeric resolved by mdy / dmy preference', () {
      expect(
        detectEventDateFromTitle(
          '05/03/2024',
          DateFormatSetting(DateFormatPref.mdy),
        ),
        DateTime.utc(2024, 5, 3),
      );
      expect(
        detectEventDateFromTitle(
          '05/03/2024',
          DateFormatSetting(DateFormatPref.dmy),
        ),
        DateTime.utc(2024, 3, 5),
      );
    });
  });

  group('detectEventDateFromTitle — conservative negatives (null)', () {
    test('two-digit year is not matched', () {
      expect(
        detectEventDateFromTitle(
          '3/15/24',
          DateFormatSetting(DateFormatPref.mdy),
        ),
        isNull,
      );
      expect(
        detectEventDateFromTitle(
          '01.12.18-Harrisburg, Pa',
          DateFormatSetting(DateFormatPref.system),
        ),
        isNull,
      );
    });

    test('season / loose text is not matched', () {
      expect(
        detectEventDateFromTitle(
          "Spring Fling '24",
          DateFormatSetting(DateFormatPref.system),
        ),
        isNull,
      );
      expect(
        detectEventDateFromTitle(
          'Friday Night Contra',
          DateFormatSetting(DateFormatPref.system),
        ),
        isNull,
      );
    });

    test('ambiguous numeric with system/ymd pref is skipped', () {
      expect(
        detectEventDateFromTitle(
          '05/03/2024',
          DateFormatSetting(DateFormatPref.system),
        ),
        isNull,
      );
      expect(
        detectEventDateFromTitle(
          '05/03/2024',
          DateFormatSetting(DateFormatPref.ymd),
        ),
        isNull,
      );
    });

    test('impossible calendar dates are rejected', () {
      expect(
        detectEventDateFromTitle(
          '2024-02-30',
          DateFormatSetting(DateFormatPref.system),
        ),
        isNull,
      );
      expect(
        detectEventDateFromTitle(
          '2024-13-01',
          DateFormatSetting(DateFormatPref.system),
        ),
        isNull,
      );
      expect(
        detectEventDateFromTitle(
          '13/15/2024',
          DateFormatSetting(DateFormatPref.mdy),
        ),
        isNull,
      );
    });

    test('out-of-range year is rejected', () {
      expect(
        detectEventDateFromTitle(
          '1815-03-15',
          DateFormatSetting(DateFormatPref.system),
        ),
        isNull,
      );
      expect(
        detectEventDateFromTitle(
          '2999-03-15',
          DateFormatSetting(DateFormatPref.system),
        ),
        isNull,
      );
    });

    test('empty title returns null', () {
      expect(
        detectEventDateFromTitle('', DateFormatSetting(DateFormatPref.system)),
        isNull,
      );
    });
  });

  group('detectEventDateFromTitle — safety', () {
    test('adversarial long title returns quickly without hanging (ReDoS)', () {
      final hostile = '${'1/' * 5000}no date here';
      final sw = Stopwatch()..start();
      final result = detectEventDateFromTitle(
        hostile,
        DateFormatSetting(DateFormatPref.mdy),
      );
      sw.stop();
      expect(result, isNull);
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('first high-confidence match wins', () {
      expect(
        detectEventDateFromTitle(
          '2024-03-15 rescheduled from 2024-04-20',
          DateFormatSetting(DateFormatPref.system),
        ),
        DateTime.utc(2024, 3, 15),
      );
    });
  });

  group('detectEventDateFromTitle — custom pattern (#584)', () {
    DateFormatSetting custom(String pattern) =>
        DateFormatSetting(DateFormatPref.custom, customPattern: pattern);

    test('MM.DD.YY resolves a two-digit-year numeric title', () {
      // Two-digit years are normally skipped, but an explicit custom pattern
      // declares the century (20xx) and field order.
      expect(
        detectEventDateFromTitle('07.15.26 Summer Contra', custom('MM.DD.YY')),
        DateTime.utc(2026, 7, 15),
      );
    });

    test('DD.MM.YY reads day-first under the same two-digit form', () {
      expect(
        detectEventDateFromTitle('05.03.24', custom('DD.MM.YY')),
        DateTime.utc(2024, 3, 5),
      );
    });

    test('custom field order disambiguates a 4-digit-year numeric title', () {
      // Both leading fields <= 12: order comes from the custom pattern.
      expect(
        detectEventDateFromTitle('05/03/2024', custom('MM/dd/yyyy')),
        DateTime.utc(2024, 5, 3),
      );
      expect(
        detectEventDateFromTitle('05/03/2024', custom('dd/MM/yyyy')),
        DateTime.utc(2024, 3, 5),
      );
    });

    test('ISO and month-name still win over the custom numeric tier', () {
      expect(
        detectEventDateFromTitle('2024-03-15', custom('MM.DD.YY')),
        DateTime.utc(2024, 3, 15),
      );
      expect(
        detectEventDateFromTitle('March 15 2024', custom('DD.MM.YY')),
        DateTime.utc(2024, 3, 15),
      );
    });

    test('an invalid custom pattern behaves exactly like system', () {
      // Unknown token → invalid → ambiguous numeric is skipped (like system).
      expect(
        detectEventDateFromTitle('05/03/2024', custom('QQ/DD/YY')),
        isNull,
      );
      // A forced-order numeric still resolves, exactly as under system.
      expect(
        detectEventDateFromTitle('25.12.2023', custom('nonsense')),
        DateTime.utc(2023, 12, 25),
      );
      // Two-digit years stay unmatched when the pattern is invalid.
      expect(detectEventDateFromTitle('07.15.26', custom('!!!')), isNull);
    });

    test('a custom two-digit-year matcher rejects impossible dates', () {
      expect(detectEventDateFromTitle('13.40.26', custom('MM.DD.YY')), isNull);
    });

    test('adversarial title stays fast under a custom pattern (ReDoS)', () {
      final hostile = '${'1.' * 5000}no date here';
      final sw = Stopwatch()..start();
      final result = detectEventDateFromTitle(hostile, custom('MM.DD.YY'));
      sw.stop();
      expect(result, isNull);
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });
  });
}
