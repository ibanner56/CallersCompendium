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
      ]) {
        expect(parseCustomDatePattern(pattern), isNotNull, reason: pattern);
      }
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
      expect(parseCustomDatePattern('yyyy-MM-d'), isNull); // single d
      expect(parseCustomDatePattern('yyyy-MM-ddd'), isNull); // 3 d's
    });

    test('rejects missing or duplicated fields', () {
      expect(parseCustomDatePattern('MM/dd'), isNull); // no year
      expect(parseCustomDatePattern('yyyy/MM'), isNull); // no day
      expect(parseCustomDatePattern('MM/MM/yyyy'), isNull); // duplicate month
      expect(parseCustomDatePattern('yyyy/yy/MM'), isNull); // duplicate year
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
  });
}
