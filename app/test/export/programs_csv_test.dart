import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/export/programs_csv.dart';
import 'package:compendium_app/src/export/share_sanitization.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'rfc4180_test_reader.dart';

/// The programs CSV export (#2333): what it carries, pay included, what it
/// leaves out, and the file format it always writes.
void main() {
  final stamp = DateTime.utc(2026, 11, 23);
  final en = lookupAppLocalizations(const Locale('en'));

  final hall = Venue(
    id: 'v1',
    name: 'Grange Hall',
    address1: '12 Secret Lane',
    city: 'Hiddenford',
    stateProv: 'Nowhereshire',
    country: 'Elsewhere',
    postalCode: 'ZZ9 9ZZ',
    contact1Name: 'Connie Contact',
    contact1Phone: '+1 555 0100',
    contact1Email: 'connie.secret@example.invalid',
    contact2Name: 'Second Person',
  );
  final dances = {
    'd1': Dance(id: 'd1', title: 'Alpha', createdAt: stamp, updatedAt: stamp),
    'd2': Dance(id: 'd2', title: 'Bravo', createdAt: stamp, updatedAt: stamp),
    'd3': Dance(id: 'd3', title: 'Charlie', createdAt: stamp, updatedAt: stamp),
  };

  Program program({
    String id = 'p1',
    String title = 'Friday dance',
    DateTime? eventDate,
    int? pay,
    String? currency,
    String notes = '',
    bool hideAlternates = false,
    List<ProgramSlot>? slots,
  }) => Program(
    id: id,
    title: title,
    eventDate: eventDate ?? DateTime.utc(2026, 3, 1),
    venueId: hall.id,
    caller: 'Cal Caller',
    band: 'The Band',
    dancerLevel: 'Mixed',
    notes: notes,
    status: ProgramStatus.performed,
    dialectName: 'MY-SECRET-DIALECT',
    payMinorUnits: pay,
    payCurrency: currency,
    hideAlternates: hideAlternates,
    archivedAt: DateTime.utc(2026, 4, 1),
    slots:
        slots ??
        [
          ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
          ProgramSlot(id: 's2', position: 1, danceId: 'd2', isAlt: true),
          ProgramSlot(id: 's3', position: 2, text: 'Break'),
          ProgramSlot(id: 's4', position: 3, danceId: 'gone'),
          ProgramSlot(id: 's5', position: 4, danceId: 'd3'),
        ],
    createdAt: stamp,
    updatedAt: stamp,
  );

  String build(List<Program> programs, {AppLocalizations? l10n}) =>
      buildProgramsCsv(
        programs,
        l10n: l10n ?? en,
        danceFor: (id) => dances[id],
        venuesById: {hall.id: hall},
      );

  group('pay', () {
    test('a program with pay exports its amount and currency; one without '
        'pay exports empty cells', () {
      final rows = csvRecords(
        build([
          program(id: 'p1', title: 'Paid', pay: 25050, currency: 'USD'),
          program(id: 'p2', title: 'Yen', pay: 5000, currency: 'JPY'),
          program(id: 'p3', title: 'Unpaid'),
        ]),
      );
      expect(rows.map((r) => r[en.csvColumnTitle]), ['Paid', 'Yen', 'Unpaid']);
      expect(rows[0][en.csvColumnPayAmount], '250.50');
      expect(rows[0][en.csvColumnPayCurrency], 'USD');
      expect(rows[1][en.csvColumnPayAmount], '5000');
      expect(rows[1][en.csvColumnPayCurrency], 'JPY');
      expect(rows[2][en.csvColumnPayAmount], '');
      expect(rows[2][en.csvColumnPayCurrency], '');
    });

    test('the CSV sanitiser and the share sanitiser differ only in pay', () {
      final full = program(pay: 25050, currency: 'USD');
      final csv = sanitizeProgramForCsv(full);
      final share = sanitizeProgramForShare(full);

      expect(csv.payMinorUnits, 25050);
      expect(csv.payCurrency, 'USD');
      expect(share.payMinorUnits, isNull);
      expect(share.payCurrency, isNull);
      expect(share, csv.copyWith(clearPay: true));
      for (final p in [csv, share]) {
        expect(p.dialectName, isNull);
        expect(p.archivedAt, isNull);
      }
      expect(
        csv,
        full.copyWith(
          clearDialectName: true,
          clearArchivedAt: true,
          clearCalendarEventKey: true,
        ),
        reason: 'the CSV sanitiser drops nothing else',
      );
    });
  });

  group('while pay is hidden (Show pay off, #2355)', () {
    test('the file has no pay columns, and the amount and currency appear '
        'nowhere in it', () {
      final paid = program(pay: 98765, currency: 'CHF');
      final hidden = buildProgramsCsv(
        [paid],
        l10n: en,
        danceFor: (id) => dances[id],
        venuesById: {hall.id: hall},
        includePay: false,
      );
      final header = readRfc4180(hidden).first;
      expect(header, isNot(contains(en.csvColumnPayAmount)));
      expect(header, isNot(contains(en.csvColumnPayCurrency)));
      expect(hidden, isNot(contains('987.65')));
      expect(hidden, isNot(contains('98765')));
      expect(hidden, isNot(contains('CHF')));
      final row = csvRecords(hidden).single;
      expect(row.length, header.length);
      expect(row[en.csvColumnNotes], '', reason: 'columns still line up');

      final shown = csvRecords(build([paid])).single;
      expect(shown[en.csvColumnPayAmount], '987.65');
      expect(shown[en.csvColumnPayCurrency], 'CHF');
    });
  });

  group('what stays private', () {
    test("a venue's address and contacts never appear; its name does", () {
      final csv = build([program()]);
      for (final secret in [
        '12 Secret Lane',
        'Hiddenford',
        'Nowhereshire',
        'Elsewhere',
        'ZZ9 9ZZ',
        'Connie Contact',
        '555 0100',
        'connie.secret@example.invalid',
        'Second Person',
      ]) {
        expect(csv, isNot(contains(secret)), reason: secret);
      }
      expect(csvRecords(csv).single[en.csvColumnVenue], 'Grange Hall');
    });

    test('the Perform dialect never appears', () {
      expect(build([program()]), isNot(contains('MY-SECRET-DIALECT')));
    });
  });

  test('the dances are listed in order, alternates marked, a missing dance '
      'named as deleted, and only main dances counted', () {
    final row = csvRecords(build([program()])).single;
    expect(
      row[en.csvColumnDances],
      'Alpha\nAlternate: Bravo\nDeleted dance\nCharlie',
    );
    expect(row[en.csvColumnDanceCount], '3');
    expect(row[en.csvColumnCaller], 'Cal Caller');
    expect(row[en.csvColumnBand], 'The Band');
    expect(row[en.csvColumnDancerLevel], 'Mixed');
    expect(row[en.csvColumnStatus], 'Performed');
  });

  test('a leading alternate is marked and not counted, as the set list marks '
      'it', () {
    final row = csvRecords(
      build([
        program(
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd2', isAlt: true),
            ProgramSlot(id: 's2', position: 1, danceId: 'd1'),
          ],
        ),
      ]),
    ).single;
    expect(row[en.csvColumnDances], 'Alternate: Bravo\nAlpha');
    expect(row[en.csvColumnDanceCount], '1');
  });

  test('the alternate label takes the language\'s own separator', () {
    final fr = lookupAppLocalizations(const Locale('fr'));
    final row = csvRecords(build([program()], l10n: fr)).single;
    expect(
      row[fr.csvColumnDances]!.split('\n')[1],
      '${fr.exportIncludeFiguresAlternate}${fr.exportLabelSeparator}Bravo',
    );
  });

  test('a program that hides its alternates lists none', () {
    final row = csvRecords(build([program(hideAlternates: true)])).single;
    expect(row[en.csvColumnDances], 'Alpha\nDeleted dance\nCharlie');
  });

  group('the file format never follows the region', () {
    for (final locale in ['da', 'de', 'fr', 'nl', 'ja']) {
      test('commas, UTF-8 with a BOM, ISO dates and a decimal point under '
          '$locale', () {
        final previous = Intl.defaultLocale;
        Intl.defaultLocale = locale;
        addTearDown(() => Intl.defaultLocale = previous);
        final l10n = lookupAppLocalizations(Locale(locale));
        final csv = build([
          program(
            eventDate: DateTime.utc(2026, 12, 31),
            pay: 12345,
            currency: 'EUR',
          ),
        ], l10n: l10n);

        expect(utf8.encode(csv).take(3), [0xEF, 0xBB, 0xBF]);
        expect(csv, isNot(contains(';')));
        final rows = readRfc4180(csv);
        expect(rows.first.first, l10n.csvColumnTitle);
        expect(rows[1].length, rows.first.length);
        final row = csvRecords(csv).single;
        expect(row[l10n.csvColumnEventDate], '2026-12-31');
        expect(row[l10n.csvColumnPayAmount], '123.45');
      });
    }
  });

  test('an event date is its own calendar date, whatever the time of day it '
      'carries', () {
    // A stored date is UTC midnight; a late local time must not roll into the
    // next day, nor an early UTC one into the previous. A test cannot change
    // the process's time zone, so on a UTC machine this cannot catch a
    // `toLocal()` slipped into the writer: it was run by hand under
    // TZ=Pacific/Kiritimati (+14) and TZ=Pacific/Pago_Pago (-11), and the
    // `toLocal()` mutation fails it under Pago_Pago (#2333).
    final rows = csvRecords(
      build([
        program(id: 'a', title: 'A', eventDate: DateTime.utc(2026, 1, 5)),
        program(id: 'b', title: 'B', eventDate: DateTime(2026, 1, 5, 23, 59)),
        program(id: 'c', title: 'C', eventDate: DateTime.utc(2026, 1, 5, 0, 1)),
      ]),
    );
    expect(rows.map((r) => r[en.csvColumnEventDate]), [
      '2026-01-05',
      '2026-01-05',
      '2026-01-05',
    ]);
  });

  test('formula-like titles and notes are written as text', () {
    final rows = csvRecords(
      build([
        program(id: 'p1', title: '=HYPERLINK("http://example.invalid","x")'),
        program(id: 'p2', title: 'Plus', notes: '+1+1'),
        program(id: 'p3', title: 'At', notes: '@SUM(A1)'),
      ]),
    );
    expect(rows[0][en.csvColumnTitle], startsWith("'="));
    expect(rows[1][en.csvColumnNotes], "'+1+1");
    expect(rows[2][en.csvColumnNotes], "'@SUM(A1)");
  });

  test('the file name is the localized stem and the date', () {
    expect(
      programsCsvFileName('programs', DateTime(2026, 11, 23)),
      'programs_2026-11-23.csv',
    );
  });
}
