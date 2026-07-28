import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Unit tests for the CC composed/revised date mapping (`_mapDate`, exercised
/// through the public [mapCallersCompanionDance]). Covers issue #467: extend
/// the ISO-only parser to accept common human/locale shapes, degrade to
/// year-only when only the year is safely recoverable, and reject (with a
/// warning, never a silent drop) anything still unparseable. Input is untrusted
/// (imported `.USR`/CC data), so rejection/robustness cases are covered too.
void main() {
  CcDanceMapping mapComposed(String? composed) =>
      mapCallersCompanionDance(CcDanceRecord(name: 'D', composed: composed));

  bool hasCode(CcDanceMapping m, String code) =>
      m.issues.any((i) => i.code == code);

  group('ISO canonical (unchanged)', () {
    test('bare year', () {
      final m = mapComposed('2004');
      expect(m.dance.composedOn, PartialDate(2004));
      expect(m.issues, isEmpty);
    });

    test('year-month', () {
      final m = mapComposed('2004-03');
      expect(m.dance.composedOn, PartialDate(2004, 3));
      expect(m.issues, isEmpty);
    });

    test('year-month-day', () {
      final m = mapComposed('2004-03-15');
      expect(m.dance.composedOn, PartialDate(2004, 3, 15));
      expect(m.issues, isEmpty);
    });

    test('well-shaped but invalid ISO month is rejected', () {
      final m = mapComposed('2004-13');
      expect(m.dance.composedOn, isNull);
      expect(hasCode(m, 'cc_unparsed_date'), isTrue);
    });
  });

  group('month-name formats (full precision, unambiguous)', () {
    test('full month name + year → month precision', () {
      expect(mapComposed('March 2004').dance.composedOn, PartialDate(2004, 3));
    });

    test('abbreviated month + year', () {
      expect(mapComposed('Mar 2004').dance.composedOn, PartialDate(2004, 3));
    });

    test('abbreviation with trailing dot', () {
      expect(mapComposed('Mar. 2004').dance.composedOn, PartialDate(2004, 3));
    });

    test('case-insensitive', () {
      expect(mapComposed('MARCH 2004').dance.composedOn, PartialDate(2004, 3));
    });

    test('comma after month name', () {
      expect(mapComposed('March, 2004').dance.composedOn, PartialDate(2004, 3));
    });

    test('Sept abbreviation', () {
      expect(mapComposed('Sept 2004').dance.composedOn, PartialDate(2004, 9));
    });

    test('month name + day + year → day precision', () {
      expect(
        mapComposed('March 15, 2004').dance.composedOn,
        PartialDate(2004, 3, 15),
      );
    });

    test('month name + day + year, no comma', () {
      expect(
        mapComposed('Mar 15 2004').dance.composedOn,
        PartialDate(2004, 3, 15),
      );
    });

    test('day + month name + year', () {
      expect(
        mapComposed('15 March 2004').dance.composedOn,
        PartialDate(2004, 3, 15),
      );
    });

    test('day + abbreviated month + year', () {
      expect(
        mapComposed('15 Mar 2004').dance.composedOn,
        PartialDate(2004, 3, 15),
      );
    });

    test('all accepted month-name formats emit no issues', () {
      for (final v in const [
        'March 2004',
        'Mar 2004',
        'March 15, 2004',
        '15 March 2004',
      ]) {
        expect(mapComposed(v).issues, isEmpty, reason: v);
      }
    });

    test('invalid calendar day is rejected, not stored', () {
      final m = mapComposed('February 30, 2004');
      expect(m.dance.composedOn, isNull);
      expect(hasCode(m, 'cc_unparsed_date'), isTrue);
    });

    test('unknown month word degrades to the recoverable year', () {
      final m = mapComposed('Smarch 2004');
      expect(m.dance.composedOn, PartialDate(2004));
      expect(hasCode(m, 'cc_date_reduced_precision'), isTrue);
    });
  });

  group('numeric slash/dot/hyphen dates with a 4-digit year', () {
    test('MM/DD/YYYY where day > 12 disambiguates deterministically', () {
      final m = mapComposed('3/15/2004');
      expect(m.dance.composedOn, PartialDate(2004, 3, 15));
      expect(hasCode(m, 'cc_date_assumed_mdy'), isFalse);
    });

    test('DD/MM/YYYY where day > 12 disambiguates deterministically', () {
      final m = mapComposed('15/03/2004');
      expect(m.dance.composedOn, PartialDate(2004, 3, 15));
      expect(hasCode(m, 'cc_date_assumed_mdy'), isFalse);
    });

    test('dot separators', () {
      expect(
        mapComposed('15.03.2004').dance.composedOn,
        PartialDate(2004, 3, 15),
      );
    });

    test('hyphen separators (non-ISO ordering)', () {
      expect(
        mapComposed('15-03-2004').dance.composedOn,
        PartialDate(2004, 3, 15),
      );
    });

    test('genuinely ambiguous date assumes US MM/DD and flags it', () {
      final m = mapComposed('3/4/2004');
      expect(m.dance.composedOn, PartialDate(2004, 3, 4));
      expect(hasCode(m, 'cc_date_assumed_mdy'), isTrue);
      expect(
        m.issues.singleWhere((i) => i.code == 'cc_date_assumed_mdy').severity,
        ImportIssueSeverity.info,
      );
    });

    test('year-first numeric is read as Y/M/D by position', () {
      expect(
        mapComposed('2004/3/15').dance.composedOn,
        PartialDate(2004, 3, 15),
      );
    });

    test('month/year (M/YYYY) → month precision', () {
      expect(mapComposed('3/2004').dance.composedOn, PartialDate(2004, 3));
    });

    test('year/month (YYYY/M) → month precision', () {
      expect(mapComposed('2004/3').dance.composedOn, PartialDate(2004, 3));
    });

    test('both components > 12 is rejected (no valid month)', () {
      final m = mapComposed('13/14/2004');
      expect(m.dance.composedOn, isNull);
      expect(hasCode(m, 'cc_unparsed_date'), isTrue);
    });

    test('impossible calendar date (2/31/2004) is rejected', () {
      final m = mapComposed('2/31/2004');
      expect(m.dance.composedOn, isNull);
      expect(hasCode(m, 'cc_unparsed_date'), isTrue);
    });
  });

  group('year-only degrade', () {
    test('descriptive text with a single year recovers the year', () {
      final m = mapComposed('Spring 2004');
      expect(m.dance.composedOn, PartialDate(2004));
      expect(hasCode(m, 'cc_date_reduced_precision'), isTrue);
      expect(
        m.issues
            .singleWhere((i) => i.code == 'cc_date_reduced_precision')
            .severity,
        ImportIssueSeverity.info,
      );
    });

    test('circa prefix', () {
      expect(mapComposed('c. 2004').dance.composedOn, PartialDate(2004));
    });

    test('year with trailing punctuation', () {
      expect(mapComposed('2004?').dance.composedOn, PartialDate(2004));
    });

    test('a year range is NOT degraded (ambiguous) and warns', () {
      final m = mapComposed('2004-2005');
      expect(m.dance.composedOn, isNull);
      expect(hasCode(m, 'cc_unparsed_date'), isTrue);
      expect(hasCode(m, 'cc_date_reduced_precision'), isFalse);
    });
  });

  group('rejection / robustness (untrusted input)', () {
    test('empty/blank yields no date and no issue', () {
      expect(mapComposed(null).dance.composedOn, isNull);
      expect(mapComposed(null).issues, isEmpty);
      expect(mapComposed('   ').dance.composedOn, isNull);
      expect(mapComposed('   ').issues, isEmpty);
    });

    test('pure junk warns and drops', () {
      final m = mapComposed('not a date');
      expect(m.dance.composedOn, isNull);
      expect(hasCode(m, 'cc_unparsed_date'), isTrue);
    });

    test('a 5-digit run is not a year', () {
      final m = mapComposed('20045');
      expect(m.dance.composedOn, isNull);
      expect(hasCode(m, 'cc_unparsed_date'), isTrue);
    });

    test('an over-long string is rejected without heavy parsing', () {
      final m = mapComposed('${'a' * 200} 2004');
      expect(m.dance.composedOn, isNull);
      expect(hasCode(m, 'cc_unparsed_date'), isTrue);
    });
  });

  group('revised path is mapped the same way', () {
    test('revised accepts a month-name format', () {
      final m = mapCallersCompanionDance(
        CcDanceRecord(name: 'D', revised: 'March 2004'),
      );
      expect(m.dance.revisedOn, PartialDate(2004, 3));
    });

    test('revised warning names the revised field', () {
      final m = mapCallersCompanionDance(
        CcDanceRecord(name: 'D', revised: 'not a date'),
      );
      expect(m.dance.revisedOn, isNull);
      final issue = m.issues.singleWhere((i) => i.code == 'cc_unparsed_date');
      expect(issue.message, contains('revised'));
    });
  });
}
