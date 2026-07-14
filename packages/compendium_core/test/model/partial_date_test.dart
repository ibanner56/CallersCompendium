import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('construction', () {
    test('year-only is valid', () {
      final d = PartialDate(1989);
      expect(d.year, 1989);
      expect(d.month, isNull);
      expect(d.day, isNull);
      expect(d.precision, DatePrecision.year);
    });

    test('year+month is valid', () {
      final d = PartialDate(2004, 3);
      expect(d.month, 3);
      expect(d.day, isNull);
      expect(d.precision, DatePrecision.month);
    });

    test('full date is valid', () {
      final d = PartialDate(2004, 3, 15);
      expect(d.day, 15);
      expect(d.precision, DatePrecision.day);
    });

    test('rejects a day without a month', () {
      expect(() => PartialDate(2004, null, 15), throwsArgumentError);
    });

    test('rejects an out-of-range month', () {
      expect(() => PartialDate(2004, 0), throwsArgumentError);
      expect(() => PartialDate(2004, 13), throwsArgumentError);
    });

    test('rejects an out-of-range year', () {
      expect(() => PartialDate(0), throwsArgumentError);
      expect(() => PartialDate(10000), throwsArgumentError);
    });

    test('rejects impossible days', () {
      expect(() => PartialDate(2004, 2, 30), throwsArgumentError);
      expect(() => PartialDate(2004, 4, 31), throwsArgumentError);
      expect(() => PartialDate(2004, 1, 0), throwsArgumentError);
    });

    test('is leap-year aware for February', () {
      expect(PartialDate(2004, 2, 29).day, 29); // 2004 is a leap year
      expect(() => PartialDate(2005, 2, 29), throwsArgumentError);
      expect(() => PartialDate(1900, 2, 29), throwsArgumentError); // not leap
      expect(PartialDate(2000, 2, 29).day, 29); // divisible by 400
    });
  });

  group('serialization', () {
    test('renders sized to precision', () {
      expect(PartialDate(1989).serialize(), '1989');
      expect(PartialDate(2004, 3).serialize(), '2004-03');
      expect(PartialDate(2004, 3, 15).serialize(), '2004-03-15');
    });

    test('zero-pads the year', () {
      expect(PartialDate(89).serialize(), '0089');
    });

    test('round-trips through parse', () {
      for (final d in [
        PartialDate(1989),
        PartialDate(2004, 3),
        PartialDate(2004, 3, 15),
        PartialDate(89, 1, 1),
      ]) {
        expect(PartialDate.parse(d.serialize()), d);
      }
    });

    test('parse rejects malformed strings', () {
      expect(() => PartialDate.parse('89'), throwsFormatException);
      expect(() => PartialDate.parse('2004-3'), throwsFormatException);
      expect(() => PartialDate.parse('2004-03-5'), throwsFormatException);
      expect(() => PartialDate.parse('2004/03/15'), throwsFormatException);
      expect(() => PartialDate.parse('2004-03-15-01'), throwsFormatException);
      expect(() => PartialDate.parse(''), throwsFormatException);
    });

    test('parse rejects a well-shaped but invalid date', () {
      expect(() => PartialDate.parse('2005-02-29'), throwsArgumentError);
    });
  });

  group('equality', () {
    test('value equality and hashCode', () {
      expect(PartialDate(2004, 3, 15), PartialDate(2004, 3, 15));
      expect(
        PartialDate(2004, 3, 15).hashCode,
        PartialDate(2004, 3, 15).hashCode,
      );
      expect(PartialDate(2004, 3), isNot(PartialDate(2004, 3, 1)));
      expect(PartialDate(2004), isNot(PartialDate(2005)));
    });
  });

  group('ordering', () {
    test('chronological across years and precisions', () {
      final dates = [
        PartialDate(1990),
        PartialDate(1989, 3, 1),
        PartialDate(1989, 3),
        PartialDate(1989),
      ]..sort();
      expect(dates.map((d) => d.serialize()), [
        '1989', // year-only sorts before same-year month-qualified
        '1989-03',
        '1989-03-01',
        '1990',
      ]);
    });

    test('matches lexicographic order of serialize', () {
      final a = PartialDate(2004, 3);
      final b = PartialDate(2004, 3, 15);
      expect(a.compareTo(b), lessThan(0));
      expect(a.serialize().compareTo(b.serialize()), lessThan(0));
    });
  });
}
