import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/export/program_calendar_export.dart';
import 'package:compendium_app/src/export/share_file.dart';
import 'package:compendium_app/src/export/share_sanitization.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:share_plus/share_plus.dart';

import '../support/l10n_harness.dart';

final _now = DateTime.utc(2026, 11, 23, 12);

Program _program({
  String id = 'p1',
  String title = 'Friday Contra',
  DateTime? eventDate,
  bool noDate = false,
  String? venue,
  String? venueId,
  DateTime? archivedAt,
  DateTime? deletedAt,
  DateTime? updatedAt,
  int? start,
  int? end,
  int? lesson,
  int? arrival,
}) => Program(
  id: id,
  title: title,
  eventDate: noDate ? null : (eventDate ?? DateTime.utc(2026, 12, 5)),
  venue: venue,
  venueId: venueId,
  band: 'The Ripplers',
  caller: 'Robin Caller',
  notes: 'Secret program note',
  payMinorUnits: 987654,
  payCurrency: 'USD',
  archivedAt: archivedAt,
  deletedAt: deletedAt,
  createdAt: _now,
  updatedAt: updatedAt ?? _now,
  startMinute: start,
  endMinute: end,
  lessonMinute: lesson,
  arrivalMinute: arrival,
);

/// A venue with every address part and two contacts, each value distinctive
/// enough that finding it anywhere in the file can only mean a leak.
final _venue = Venue(
  id: 'v1',
  name: 'Grange Hall',
  address1: '123 Main St',
  address2: 'Room 2',
  city: 'Montpelier',
  stateProv: 'VT',
  country: 'USA',
  postalCode: '05602',
  plus4: '1234',
  time: '8–11 pm',
  contact1Name: 'Pat Contact',
  contact1Phone: '555-0100',
  contact1Email: 'pat@example.com',
  contact2Name: 'Sam Contact',
  contact2Phone: '555-0199',
  contact2Email: 'sam@example.com',
);

const _addressParts = [
  '123 Main St',
  'Room 2',
  'Montpelier',
  'VT',
  'USA',
  '05602',
  '1234',
];
const _contactValues = [
  'Pat Contact',
  '555-0100',
  'pat@example.com',
  'Sam Contact',
  '555-0199',
  'sam@example.com',
];
const _payValues = ['987654', '9876.54', '9,876.54', 'USD'];
const _otherPrivate = ['Secret program note', 'The Ripplers', 'Robin Caller'];

/// The file with RFC 5545 folding undone, so a value split across a fold is
/// still found.
String _unfolded(String ics) => ics.replaceAll('\r\n ', '');

/// Text values unescaped too, so `123 Main St\, Room 2` matches.
String _plain(String ics) => _unfolded(
  ics,
).replaceAll(r'\,', ',').replaceAll(r'\;', ';').replaceAll(r'\\', r'\');

String? _location(String ics) {
  for (final line in _unfolded(ics).split('\r\n')) {
    if (line.startsWith('LOCATION:')) {
      return line
          .substring('LOCATION:'.length)
          .replaceAll(r'\,', ',')
          .replaceAll(r'\;', ';');
    }
  }
  return null;
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  // The times are formatted with intl's DateFormat, whose symbols the app
  // loads through Flutter's localizations; a plain test loads them here.
  setUpAll(() => initializeDateFormatting('en'));

  String build(
    List<Program> programs, {
    bool includeAddress = false,
    Map<String, Venue>? venues,
    bool use24Hour = false,
  }) => buildProgramsCalendar(
    l10n,
    programs,
    venuesById: venues ?? {'v1': _venue},
    includeAddress: includeAddress,
    use24Hour: use24Hour,
    now: _now,
  );

  group('privacy', () {
    test('guard: with the address opt-in unticked, no address part, contact '
        'value, pay amount, note, band or caller is in the file', () {
      final ics = _plain(build([_program(venueId: 'v1')]));
      for (final value in [
        ..._addressParts,
        ..._contactValues,
        ..._payValues,
        ..._otherPrivate,
      ]) {
        expect(ics.contains(value), isFalse, reason: '"$value" leaked');
      }
      expect(_location(build([_program(venueId: 'v1')])), 'Grange Hall');
    });

    test('guard: with the address opt-in ticked, the address is in LOCATION, '
        'and still no contact value or pay amount is anywhere', () {
      final raw = build([_program(venueId: 'v1')], includeAddress: true);
      expect(
        _location(raw),
        'Grange Hall, 123 Main St, Room 2, Montpelier, VT, 05602-1234, USA',
      );
      final ics = _plain(raw);
      for (final value in [
        ..._contactValues,
        ..._payValues,
        ..._otherPrivate,
      ]) {
        expect(ics.contains(value), isFalse, reason: '"$value" leaked');
      }
    });

    test('the address appears only in LOCATION', () {
      final lines = _plain(
        build([_program(venueId: 'v1')], includeAddress: true),
      ).split('\r\n');
      for (final line in lines) {
        if (line.startsWith('LOCATION:')) continue;
        expect(line.contains('123 Main St'), isFalse, reason: line);
      }
    });

    test('sanitizeVenueForShare without the flag still clears the address', () {
      final shared = sanitizeVenueForShare(_venue);
      expect(shared.address1, isNull);
      expect(shared.address2, isNull);
      expect(shared.city, isNull);
      expect(shared.stateProv, isNull);
      expect(shared.country, isNull);
      expect(shared.postalCode, isNull);
      expect(shared.plus4, isNull);
      expect(shared.name, 'Grange Hall');
    });

    test('includeAddress keeps the address but never the contacts', () {
      final shared = sanitizeVenueForShare(_venue, includeAddress: true);
      expect(shared.address1, '123 Main St');
      expect(shared.plus4, '1234');
      expect(shared.contact1Name, isNull);
      expect(shared.contact1Phone, isNull);
      expect(shared.contact1Email, isNull);
      expect(shared.contact2Name, isNull);
      expect(shared.contact2Phone, isNull);
      expect(shared.contact2Email, isNull);
    });

    test('needs consent only when a chosen linked venue has an address', () {
      final venues = {
        'v1': _venue,
        'v2': Venue(id: 'v2', name: 'Bare Hall', contact1Name: 'Pat'),
      };
      expect(
        calendarExportNeedsAddressConsent([_program(venueId: 'v1')], venues),
        isTrue,
      );
      expect(
        calendarExportNeedsAddressConsent([_program(venueId: 'v2')], venues),
        isFalse,
      );
      expect(
        calendarExportNeedsAddressConsent([
          _program(venue: '1 Typed St'),
        ], venues),
        isFalse,
      );
      expect(
        calendarExportNeedsAddressConsent([_program(venueId: 'gone')], venues),
        isFalse,
      );
    });
  });

  group('LOCATION and DESCRIPTION', () {
    test('falls back to the typed venue label when no venue is linked', () {
      expect(_location(build([_program(venue: 'Town Hall')])), 'Town Hall');
    });

    test('falls back to the typed label when the link does not resolve', () {
      expect(
        _location(build([_program(venue: 'Town Hall', venueId: 'gone')])),
        'Town Hall',
      );
    });

    test('is omitted when there is neither', () {
      expect(_location(build([_program()])), isNull);
    });

    test('DESCRIPTION has the localized status and the venue time', () {
      final ics = _plain(build([_program(venueId: 'v1')]));
      expect(ics, contains(r'DESCRIPTION:Draft\n8–11 pm'));
    });
  });

  test('one VEVENT per program, UID from the program id', () {
    final ics = build([_program(id: 'a'), _program(id: 'b')]);
    expect('BEGIN:VEVENT'.allMatches(ics), hasLength(2));
    expect(ics, contains('UID:a@callers-compendium'));
    expect(ics, contains('UID:b@callers-compendium'));
    // A program with no start time is an all-day event.
    expect(ics, contains('DTSTART;VALUE=DATE:20261205'));
  });

  group('the program\'s times (#2350)', () {
    test('a start and end make a timed event in floating local time', () {
      final ics = _unfolded(build([_program(start: 1170, end: 1350)]));
      expect(ics, contains('DTSTART:20261205T193000\r\n'));
      expect(ics, contains('DTEND:20261205T223000\r\n'));
      expect(ics, isNot(contains('VALUE=DATE')));
    });

    test('an end before the start ends the next day', () {
      final ics = _unfolded(build([_program(start: 1260, end: 60)]));
      expect(ics, contains('DTSTART:20261205T210000\r\n'));
      expect(ics, contains('DTEND:20261206T010000\r\n'));
    });

    test('a start alone has no DTEND', () {
      final ics = _unfolded(build([_program(start: 1170)]));
      expect(ics, contains('DTSTART:20261205T193000\r\n'));
      expect(ics, isNot(contains('DTEND')));
    });

    test('an end alone stays all-day, with the end in DESCRIPTION', () {
      final ics = _unfolded(build([_program(end: 1350)]));
      expect(ics, contains('DTSTART;VALUE=DATE:20261205'));
      expect(
        _plain(ics).replaceAll('\u202f', ' '),
        contains('Dance until 10:30 PM'),
      );
    });

    test('the lesson and Arrive by go in DESCRIPTION, and a start replaces '
        'the venue\'s usual time there', () {
      final ics = _plain(
        build([
          _program(venueId: 'v1', start: 1170, lesson: 1140, arrival: 1110),
        ]),
      ).replaceAll('\u202f', ' ');
      expect(ics, contains(r'Lesson 7:00 PM · Arrive by 6:30 PM'));
      expect(ics, isNot(contains('8–11 pm')));
    });

    test("on a 24-hour device the notes' times are 24-hour (D1a-02)", () {
      final ics = _plain(
        build([
          _program(lesson: 1140, arrival: 1110, end: 1350),
        ], use24Hour: true),
      );
      expect(
        ics,
        contains(r'Lesson 19:00 · Dance until 22:30 · Arrive by 18:30'),
      );
    });
  });

  test('re-exporting an edited program keeps its UID and raises SEQUENCE', () {
    int sequence(String ics) =>
        int.parse(RegExp(r'SEQUENCE:(\d+)').firstMatch(ics)!.group(1)!);
    final before = build([_program()]);
    final after = build([
      _program(
        eventDate: DateTime.utc(2026, 12, 6),
        updatedAt: _now.add(const Duration(hours: 1)),
      ),
    ]);
    expect(
      RegExp(r'UID:.*').stringMatch(after),
      RegExp(r'UID:.*').stringMatch(before),
    );
    expect(sequence(after), greaterThan(sequence(before)));
  });

  group('calendarExportCandidates', () {
    final today = DateTime(2026, 11, 23);

    test('today is upcoming, yesterday is past', () {
      final c = calendarExportCandidates([
        _program(id: 'today', eventDate: DateTime.utc(2026, 11, 23)),
        _program(id: 'yesterday', eventDate: DateTime.utc(2026, 11, 22)),
      ], today);
      expect(c.upcoming.map((p) => p.id), ['today']);
      expect(c.past.map((p) => p.id), ['yesterday']);
    });

    test('upcoming leaves out archived, deleted and undated programs; past '
        'leaves out deleted and undated', () {
      final c = calendarExportCandidates([
        _program(id: 'live', eventDate: DateTime.utc(2026, 12, 1)),
        _program(
          id: 'archived-upcoming',
          eventDate: DateTime.utc(2026, 12, 1),
          archivedAt: _now,
        ),
        _program(
          id: 'deleted-upcoming',
          eventDate: DateTime.utc(2026, 12, 1),
          deletedAt: _now,
        ),
        _program(id: 'undated', noDate: true),
        _program(
          id: 'archived-past',
          eventDate: DateTime.utc(2026, 1, 1),
          archivedAt: _now,
        ),
        _program(
          id: 'deleted-past',
          eventDate: DateTime.utc(2026, 1, 1),
          deletedAt: _now,
        ),
      ], today);
      expect(c.upcoming.map((p) => p.id), ['live']);
      expect(c.past.map((p) => p.id), ['archived-past']);
    });

    test('upcoming soonest first, past most recent first', () {
      final c = calendarExportCandidates([
        _program(id: 'u2', eventDate: DateTime.utc(2027, 1, 2)),
        _program(id: 'u1', eventDate: DateTime.utc(2026, 12, 1)),
        _program(id: 'p1', eventDate: DateTime.utc(2026, 1, 1)),
        _program(id: 'p2', eventDate: DateTime.utc(2026, 10, 1)),
      ], today);
      expect(c.upcoming.map((p) => p.id), ['u1', 'u2']);
      expect(c.past.map((p) => p.id), ['p2', 'p1']);
    });
  });

  group('CalendarExportDelivery', () {
    late bool Function() savedUnsupported;
    setUp(() {
      savedUnsupported = isBundleShareUnsupported;
      isBundleShareUnsupported = () => false;
    });
    tearDown(() => isBundleShareUnsupported = savedUnsupported);

    Future<void> run(
      WidgetTester tester,
      CalendarExportDelivery delivery,
      List<Program> programs,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => delivery.export(
                  context,
                  programs: programs,
                  venuesById: {'v1': _venue},
                  fileName: 'x.ics',
                  subject: 'Subject',
                  sharePositionOrigin: null,
                ),
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
    }

    testWidgets('dismissing the address dialog writes nothing', (tester) async {
      var writes = 0;
      var choices = 0;
      await run(
        tester,
        CalendarExportDelivery(
          choicePicker: (_) async {
            choices++;
            return CalendarExportChoice.save;
          },
          saveInvoker: (ics, name) async {
            writes++;
            return null;
          },
        ),
        [_program(venueId: 'v1')],
      );
      expect(find.byKey(const ValueKey('calendar-address-dialog')), findsOne);
      // The address box starts unticked.
      final box = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('calendar-address-include')),
      );
      expect(box.value, isFalse);
      await tester.tapAt(const Offset(4, 4)); // the barrier
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('calendar-address-dialog')),
        findsNothing,
      );
      expect(choices, 0);
      expect(writes, 0);
    });

    testWidgets('ticking the address puts it in the saved file', (
      tester,
    ) async {
      String? saved;
      await run(
        tester,
        CalendarExportDelivery(
          choicePicker: (_) async => CalendarExportChoice.save,
          saveInvoker: (ics, name) async {
            saved = ics;
            return JsonSaveResult(path: '/tmp/$name', fileName: name);
          },
        ),
        [_program(venueId: 'v1')],
      );
      await tester.tap(find.byKey(const ValueKey('calendar-address-include')));
      await tester.tap(find.byKey(const ValueKey('calendar-address-confirm')));
      await tester.pumpAndSettle();
      expect(_location(saved!), contains('123 Main St'));
      expect(find.text('"x.ics" saved to /tmp/x.ics.'), findsOneWidget);
    });

    testWidgets('continuing unticked leaves the address out', (tester) async {
      String? saved;
      await run(
        tester,
        CalendarExportDelivery(
          choicePicker: (_) async => CalendarExportChoice.save,
          saveInvoker: (ics, name) async {
            saved = ics;
            return null;
          },
        ),
        [_program(venueId: 'v1')],
      );
      await tester.tap(find.byKey(const ValueKey('calendar-address-confirm')));
      await tester.pumpAndSettle();
      expect(_location(saved!), 'Grange Hall');
    });

    testWidgets('no address dialog when no chosen venue has an address', (
      tester,
    ) async {
      String? shared;
      String? mime;
      await run(
        tester,
        CalendarExportDelivery(
          choicePicker: (_) async => CalendarExportChoice.share,
          fileWriter: (ics, name) async {
            shared = ics;
            return XFile('/tmp/$name', mimeType: calendarMimeType);
          },
          shareInvoker: (params) async => mime = params.files!.single.mimeType,
        ),
        [_program(venue: 'Town Hall')],
      );
      expect(
        find.byKey(const ValueKey('calendar-address-dialog')),
        findsNothing,
      );
      expect(shared, contains('LOCATION:Town Hall'));
      expect(mime, 'text/calendar');
    });

    testWidgets('cancelling the delivery choice writes nothing', (
      tester,
    ) async {
      var writes = 0;
      await run(
        tester,
        CalendarExportDelivery(
          saveInvoker: (ics, name) async {
            writes++;
            return null;
          },
        ),
        [_program()],
      );
      expect(
        find.byKey(const ValueKey('calendar-export-choice-dialog')),
        findsOne,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(writes, 0);
    });
  });
}
