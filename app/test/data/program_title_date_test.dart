import 'package:compendium_app/src/data/program_title_date.dart';
import 'package:compendium_app/src/data/regional_formats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detectEventDateFromTitle — high-confidence positives', () {
    test('ISO YYYY-MM-DD anywhere in the title', () {
      expect(
        detectEventDateFromTitle(
          '2024-03-15 Friday Contra',
          DateFormatPref.system,
        ),
        DateTime.utc(2024, 3, 15),
      );
    });

    test('ISO with slash and dot separators', () {
      expect(
        detectEventDateFromTitle(
          '2016/12/05: Louisville',
          DateFormatPref.system,
        ),
        DateTime.utc(2016, 12, 5),
      );
      expect(
        detectEventDateFromTitle('2019.01.07 Chicago', DateFormatPref.system),
        DateTime.utc(2019, 1, 7),
      );
    });

    test('month name then day and year', () {
      expect(
        detectEventDateFromTitle(
          'March 15 2024 Spring Fling',
          DateFormatPref.system,
        ),
        DateTime.utc(2024, 3, 15),
      );
      expect(
        detectEventDateFromTitle('Mar 15, 2024', DateFormatPref.system),
        DateTime.utc(2024, 3, 15),
      );
      expect(
        detectEventDateFromTitle(
          'December 1st, 2018 Harrisburg',
          DateFormatPref.system,
        ),
        DateTime.utc(2018, 12, 1),
      );
    });

    test('day then month name and year', () {
      expect(
        detectEventDateFromTitle(
          '15 March 2024 Barn Dance',
          DateFormatPref.system,
        ),
        DateTime.utc(2024, 3, 15),
      );
      expect(
        detectEventDateFromTitle('1st April 2023', DateFormatPref.system),
        DateTime.utc(2023, 4, 1),
      );
    });

    test('numeric 4-digit-year-last, order forced when a field > 12', () {
      // 15 cannot be a month → day=15, month=3.
      expect(
        detectEventDateFromTitle('3/15/2024 Contra', DateFormatPref.system),
        DateTime.utc(2024, 3, 15),
      );
      // 25 cannot be a month → day=25, month=12 (DMY forced).
      expect(
        detectEventDateFromTitle('25.12.2023', DateFormatPref.system),
        DateTime.utc(2023, 12, 25),
      );
    });

    test('ambiguous numeric resolved by mdy / dmy preference', () {
      expect(
        detectEventDateFromTitle('05/03/2024', DateFormatPref.mdy),
        DateTime.utc(2024, 5, 3),
      );
      expect(
        detectEventDateFromTitle('05/03/2024', DateFormatPref.dmy),
        DateTime.utc(2024, 3, 5),
      );
    });
  });

  group('detectEventDateFromTitle — conservative negatives (null)', () {
    test('two-digit year is not matched', () {
      expect(detectEventDateFromTitle('3/15/24', DateFormatPref.mdy), isNull);
      expect(
        detectEventDateFromTitle(
          '01.12.18-Harrisburg, Pa',
          DateFormatPref.system,
        ),
        isNull,
      );
    });

    test('season / loose text is not matched', () {
      expect(
        detectEventDateFromTitle("Spring Fling '24", DateFormatPref.system),
        isNull,
      );
      expect(
        detectEventDateFromTitle('Friday Night Contra', DateFormatPref.system),
        isNull,
      );
    });

    test('ambiguous numeric with system/ymd pref is skipped', () {
      expect(
        detectEventDateFromTitle('05/03/2024', DateFormatPref.system),
        isNull,
      );
      expect(
        detectEventDateFromTitle('05/03/2024', DateFormatPref.ymd),
        isNull,
      );
    });

    test('impossible calendar dates are rejected', () {
      expect(
        detectEventDateFromTitle('2024-02-30', DateFormatPref.system),
        isNull,
      );
      expect(
        detectEventDateFromTitle('2024-13-01', DateFormatPref.system),
        isNull,
      );
      expect(
        detectEventDateFromTitle('13/15/2024', DateFormatPref.mdy),
        isNull,
      );
    });

    test('out-of-range year is rejected', () {
      expect(
        detectEventDateFromTitle('1815-03-15', DateFormatPref.system),
        isNull,
      );
      expect(
        detectEventDateFromTitle('2999-03-15', DateFormatPref.system),
        isNull,
      );
    });

    test('empty title returns null', () {
      expect(detectEventDateFromTitle('', DateFormatPref.system), isNull);
    });
  });

  group('detectEventDateFromTitle — safety', () {
    test('adversarial long title returns quickly without hanging (ReDoS)', () {
      final hostile = '${'1/' * 5000}no date here';
      final sw = Stopwatch()..start();
      final result = detectEventDateFromTitle(hostile, DateFormatPref.mdy);
      sw.stop();
      expect(result, isNull);
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('first high-confidence match wins', () {
      expect(
        detectEventDateFromTitle(
          '2024-03-15 rescheduled from 2024-04-20',
          DateFormatPref.system,
        ),
        DateTime.utc(2024, 3, 15),
      );
    });
  });
}
