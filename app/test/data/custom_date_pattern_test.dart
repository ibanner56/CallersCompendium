import 'package:compendium_app/src/data/custom_date_pattern.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCustomDatePattern — acceptance', () {
    test('accepts the canonical legend tokens and common layouts', () {
      for (final pattern in [
        'yyyy-MM-dd',
        'MM/dd/yyyy',
        'dd.MM.yyyy',
        'MM.DD.YY', // case-insensitive letters
        'yy MM dd',
        'dd MMM yyyy', // abbreviated month name (#632)
        'MMMM dd yyyy', // full month name (#632)
        'yyyy MMM dd',
        'MMMM-dd-yyyy',
        'MMMM d, yyyy', // comma separator + single-d day (#668)
        'd MMMM yyyy', // single-d day, day-first (#668)
        'd/MMMM, yyyy', // mixed separators: slash then comma (#668)
      ]) {
        expect(parseCustomDatePattern(pattern), isNotNull, reason: pattern);
      }
    });

    test('exposes the month style for numeric / abbreviated / full tokens', () {
      MonthStyle styleOf(String raw) => parseCustomDatePattern(raw)!.monthStyle;

      expect(styleOf('yyyy-MM-dd'), MonthStyle.numeric);
      expect(styleOf('dd MMM yyyy'), MonthStyle.abbreviated);
      expect(styleOf('MMMM dd yyyy'), MonthStyle.full);
      // Case-insensitive, matching #584's token handling.
      expect(styleOf('dd mmm yyyy'), MonthStyle.abbreviated);
    });

    test('exposes field order and month/day precedence', () {
      final mdy = parseCustomDatePattern('MM/dd/yyyy')!;
      expect(mdy.fieldOrder, [
        DateFieldKind.month,
        DateFieldKind.day,
        DateFieldKind.year,
      ]);
      expect(mdy.monthBeforeDay, isTrue);
      expect(mdy.yearWidth, 4);

      final dmy = parseCustomDatePattern('dd.MM.yy')!;
      expect(dmy.monthBeforeDay, isFalse);
      expect(dmy.yearWidth, 2);
    });
  });

  group('parseCustomDatePattern — defensive rejection (OWASP allowlist)', () {
    test('rejects null, empty, and over-long input', () {
      expect(parseCustomDatePattern(null), isNull);
      expect(parseCustomDatePattern(''), isNull);
      expect(
        parseCustomDatePattern('y' * (kMaxCustomDatePatternLength + 1)),
        isNull,
      );
    });

    test('rejects unknown characters and tokens', () {
      expect(parseCustomDatePattern('MM/DD/YY!'), isNull); // stray char
      expect(parseCustomDatePattern('QQ.DD.YY'), isNull); // unknown token
      expect(parseCustomDatePattern('MM_DD_YY'), isNull); // disallowed sep
      expect(parseCustomDatePattern('<script>'), isNull);
    });

    test('rejects unrecognized token widths', () {
      expect(parseCustomDatePattern('yyy-MM-dd'), isNull); // 3 y's
      expect(parseCustomDatePattern('yyyy-M-dd'), isNull); // single M
      expect(parseCustomDatePattern('yyyy-MM-ddd'), isNull); // 3 d's (#668)
      expect(parseCustomDatePattern('yyyy-MMMMM-dd'), isNull); // 5 M's (#632)
    });

    test('rejects missing or duplicated fields', () {
      expect(parseCustomDatePattern('MM/dd'), isNull); // no year
      expect(parseCustomDatePattern('yyyy/MM'), isNull); // no day
      expect(parseCustomDatePattern('MM/MM/yyyy'), isNull); // duplicate month
      expect(parseCustomDatePattern('yyyy/yy/MM'), isNull); // duplicate year
      // A numeric and a written-out month together is still a duplicate month.
      expect(parseCustomDatePattern('MMM MM yyyy dd'), isNull);
      expect(parseCustomDatePattern('MMMM MMM dd yyyy'), isNull);
      // d and dd together is still a duplicate day (#668).
      expect(parseCustomDatePattern('d dd MM yyyy'), isNull);
      expect(parseCustomDatePattern('dd d MM yyyy'), isNull);
    });

    test('unknown separators are still rejected alongside the new comma '
        '(#668)', () {
      expect(parseCustomDatePattern('MM;dd;yyyy'), isNull);
      expect(parseCustomDatePattern('MM_dd_yyyy'), isNull);
    });
  });

  group('formatWithCustomPattern', () {
    final date = DateTime.utc(2026, 7, 5);

    test('zero-pads month and day and honors year width', () {
      expect(
        formatWithCustomPattern(date, parseCustomDatePattern('yyyy-MM-dd')!),
        '2026-07-05',
      );
      expect(
        formatWithCustomPattern(date, parseCustomDatePattern('MM.DD.YY')!),
        '07.05.26',
      );
      expect(
        formatWithCustomPattern(date, parseCustomDatePattern('dd/MM/yyyy')!),
        '05/07/2026',
      );
    });

    test('yy renders the last two digits of the year', () {
      final y2001 = DateTime.utc(2001, 1, 1);
      expect(
        formatWithCustomPattern(y2001, parseCustomDatePattern('yy.MM.dd')!),
        '01.01.01',
      );
    });

    test('renders localized abbreviated / full month names (#632)', () {
      expect(
        formatWithCustomPattern(
          DateTime.utc(2026, 6, 3),
          parseCustomDatePattern('dd MMM yyyy')!,
          monthNames: _enMonthNames,
        ),
        '03 Jun 2026',
      );
      expect(
        formatWithCustomPattern(
          DateTime.utc(2026, 6, 3),
          parseCustomDatePattern('MMMM dd yyyy')!,
          monthNames: _enMonthNames,
        ),
        'June 03 2026',
      );
    });

    test('name-style month degrades to a number when names are absent', () {
      // Never throws when a name-style token is present but no table is given.
      expect(
        formatWithCustomPattern(
          DateTime.utc(2026, 6, 3),
          parseCustomDatePattern('dd MMMM yyyy')!,
        ),
        '03 06 2026',
      );
    });

    group('comma separator and single-d day (#668)', () {
      test('MMMM d, yyyy renders a single-digit day with no padding', () {
        expect(
          formatWithCustomPattern(
            DateTime.utc(2026, 6, 3),
            parseCustomDatePattern('MMMM d, yyyy')!,
            monthNames: _enMonthNames,
          ),
          'June 3, 2026',
        );
      });

      test('d MMMM yyyy renders a single-digit day, day-first layout', () {
        expect(
          formatWithCustomPattern(
            DateTime.utc(2026, 6, 3),
            parseCustomDatePattern('d MMMM yyyy')!,
            monthNames: _enMonthNames,
          ),
          '3 June 2026',
        );
      });

      test('single-d still renders a two-digit day in full', () {
        expect(
          formatWithCustomPattern(
            DateTime.utc(2026, 12, 25),
            parseCustomDatePattern('d MMMM yyyy')!,
            monthNames: _enMonthNames,
          ),
          '25 December 2026',
        );
      });

      test('dd still zero-pads (no regression alongside the new d token)', () {
        expect(
          formatWithCustomPattern(
            DateTime.utc(2026, 6, 3),
            parseCustomDatePattern('dd MMMM yyyy')!,
            monthNames: _enMonthNames,
          ),
          '03 June 2026',
        );
      });
    });
  });

  group('matchTitleWithCustomPattern', () {
    test('matches a two-digit-year title and expands the century', () {
      final p = parseCustomDatePattern('MM.DD.YY')!;
      expect(
        matchTitleWithCustomPattern('07.15.26 Contra', p),
        DateTime.utc(2026, 7, 15),
      );
    });

    test('tolerates non-zero-padded month/day and extra separator spacing', () {
      final p = parseCustomDatePattern('MM/dd/yyyy')!;
      expect(
        matchTitleWithCustomPattern('7/5/2026', p),
        DateTime.utc(2026, 7, 5),
      );
    });

    test('rejects impossible and out-of-range dates', () {
      final p = parseCustomDatePattern('MM.DD.YY')!;
      expect(matchTitleWithCustomPattern('13.01.26', p), isNull); // month 13
      expect(matchTitleWithCustomPattern('02.30.26', p), isNull); // Feb 30
    });

    test('returns null when nothing matches', () {
      final p = parseCustomDatePattern('MM.DD.YY')!;
      expect(matchTitleWithCustomPattern('Friday Night Contra', p), isNull);
    });

    test('adversarial input stays fast (ReDoS)', () {
      final p = parseCustomDatePattern('MM.DD.YY')!;
      final hostile = '${'1.' * 10000}x';
      final sw = Stopwatch()..start();
      final result = matchTitleWithCustomPattern(hostile, p);
      sw.stop();
      expect(result, isNull);
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    group('written-out month tokens (#632)', () {
      test('matches full and abbreviated month names in a title', () {
        final p = parseCustomDatePattern('dd MMM yyyy')!;
        expect(
          matchTitleWithCustomPattern(
            '12 May 2026 Contra',
            p,
            monthNames: _enMonthFullNames,
          ),
          DateTime.utc(2026, 5, 12),
        );
        // A full name is also accepted for an abbreviated token (and vice
        // versa), mirroring the detector's existing month-name tiers.
        expect(
          matchTitleWithCustomPattern(
            'Spring 15 March 2024',
            p,
            monthNames: _enMonthFullNames,
          ),
          DateTime.utc(2024, 3, 15),
        );
      });

      test('MMMM renders/parses the full month, month-first layout', () {
        final p = parseCustomDatePattern('MMMM dd yyyy')!;
        expect(
          matchTitleWithCustomPattern(
            'June 03 2026 gig',
            p,
            monthNames: _enMonthFullNames,
          ),
          DateTime.utc(2026, 6, 3),
        );
      });

      test('is case-insensitive on the month name', () {
        final p = parseCustomDatePattern('dd MMMM yyyy')!;
        expect(
          matchTitleWithCustomPattern(
            '01 DECEMBER 2025',
            p,
            monthNames: _enMonthFullNames,
          ),
          DateTime.utc(2025, 12, 1),
        );
      });

      test('a name-style token cannot match without an allowlist', () {
        final p = parseCustomDatePattern('dd MMM yyyy')!;
        // No monthNames supplied ⇒ the name-style token has no allowlist ⇒ the
        // whole pattern cannot match (no unbounded/free matching over text).
        expect(matchTitleWithCustomPattern('12 May 2026', p), isNull);
      });

      test('rejects an unknown / non-allowlisted month word', () {
        final p = parseCustomDatePattern('dd MMM yyyy')!;
        expect(
          matchTitleWithCustomPattern(
            '12 Smarch 2026',
            p,
            monthNames: _enMonthFullNames,
          ),
          isNull,
        );
      });

      test('rejects an impossible day with a valid month name', () {
        final p = parseCustomDatePattern('MMMM dd yyyy')!;
        expect(
          matchTitleWithCustomPattern(
            'February 30 2026',
            p,
            monthNames: _enMonthFullNames,
          ),
          isNull,
        );
      });

      test('month-name matching stays fast on adversarial input (ReDoS)', () {
        final p = parseCustomDatePattern('dd MMMM yyyy')!;
        // A long run of letters/separators that never completes a date.
        final hostile = '${'May ' * 10000}x';
        final sw = Stopwatch()..start();
        final result = matchTitleWithCustomPattern(
          hostile,
          p,
          monthNames: _enMonthFullNames,
        );
        sw.stop();
        expect(result, isNull);
        expect(sw.elapsedMilliseconds, lessThan(1000));
      });
    });

    group('comma separator and single-d day (#668)', () {
      test('matches a comma-separated title with a single-digit day', () {
        final p = parseCustomDatePattern('MMMM d, yyyy')!;
        expect(
          matchTitleWithCustomPattern(
            'Spring Fling — June 3, 2026',
            p,
            monthNames: _enMonthFullNames,
          ),
          DateTime.utc(2026, 6, 3),
        );
      });

      test('matches a day-first, single-d, space-separated title', () {
        final p = parseCustomDatePattern('d MMMM yyyy')!;
        expect(
          matchTitleWithCustomPattern(
            '3 June 2026 Contra',
            p,
            monthNames: _enMonthFullNames,
          ),
          DateTime.utc(2026, 6, 3),
        );
      });

      test('a single-d pattern still matches a zero-padded day in text', () {
        // The title-match day group already accepts \d{1,2} regardless of the
        // declared width, so a `d`-declared pattern still matches "03".
        final p = parseCustomDatePattern('d MMMM yyyy')!;
        expect(
          matchTitleWithCustomPattern(
            '03 June 2026',
            p,
            monthNames: _enMonthFullNames,
          ),
          DateTime.utc(2026, 6, 3),
        );
      });
    });
  });
}

/// Full English month names (January first) — the allowlist the title-date
/// detector reuses for written-out month tokens (#632).
const List<String> _enMonthFullNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// A localized-name fixture for rendering tests (abbreviated + full).
final MonthNames _enMonthNames = MonthNames(
  abbreviated: [for (final name in _enMonthFullNames) name.substring(0, 3)],
  full: _enMonthFullNames,
);
