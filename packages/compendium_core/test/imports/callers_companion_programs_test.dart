import 'package:compendium_core/src/imports/callers_companion_programs.dart';
import 'package:compendium_core/src/imports/callers_companion_usr_archive.dart';
import 'package:compendium_core/src/imports/structured_draft.dart';
import 'package:compendium_core/src/model/enums.dart';
import 'package:test/test.dart';

/// Tests for [buildCcPrograms] — the pure Set/SetItem → Program builder. Built
/// against hand-constructed [CcUsrArchive]s (its public constructors) so it is
/// hermetic and Flutter-free.
CcUsrArchive _archive(List<CcSet> sets) =>
    CcUsrArchive(dances: const [], sets: sets, warnings: const []);

var _slot = 0;
var _prog = 0;

void main() {
  setUp(() {
    _slot = 0;
    _prog = 0;
  });

  String mintId() => 'prog-${_prog++}';
  String mintSlot() => 'slot-${_slot++}';

  CcProgramsResult build(
    CcUsrArchive archive, {
    Map<String, String> danceIds = const {},
  }) => buildCcPrograms(
    archive,
    danceIdByCcRowId: danceIds,
    newId: mintId,
    newSlotId: mintSlot,
    now: DateTime.utc(2020),
  );

  test('builds a program with dance and text slots, in order', () {
    final result = build(
      _archive([
        CcSet(
          recordId: '100',
          title: 'Friday Contra',
          eventDate: '3/14/2020',
          location: 'Grange Hall',
          band: 'The Band',
          caller: 'Jane',
          items: [
            CcSetItem(order: 0, danceRecordId: '7', minutes: 8),
            CcSetItem(order: 1, breakText: 'Waltz break'),
          ],
        ),
      ]),
      danceIds: {'7': 'dance-uuid-7'},
    );

    expect(result.programs, hasLength(1));
    final program = result.programs.single;
    expect(program.title, 'Friday Contra');
    expect(program.eventDate, DateTime.utc(2020, 3, 14));
    expect(program.venue, 'Grange Hall');
    expect(program.band, 'The Band');
    expect(program.caller, 'Jane');

    expect(program.slots, hasLength(2));
    expect(program.slots[0].danceId, 'dance-uuid-7');
    expect(program.slots[0].position, 0);
    expect(program.slots[0].plannedMinutes, 8);
    expect(program.slots[1].text, 'Waltz break');
    expect(program.slots[1].position, 1);
    expect(program.slots[1].danceId, isNull);
  });

  test(
    'unresolved dance reference degrades to a text placeholder + warning',
    () {
      final result = build(
        _archive([
          CcSet(
            recordId: '100',
            title: 'Set',
            items: [CcSetItem(order: 0, danceRecordId: '999')],
          ),
        ]),
        // Empty map → dance 999 was never imported.
      );

      final slot = result.programs.single.slots.single;
      expect(slot.danceId, isNull);
      expect(slot.text, contains('999'));
      expect(
        result.issues.any((i) => i.code == 'cc_program_unresolved_dance'),
        isTrue,
      );
    },
  );

  test('empty slots are skipped with an info issue', () {
    final result = build(
      _archive([
        CcSet(recordId: '100', title: 'Set', items: [CcSetItem(order: 0)]),
      ]),
    );
    expect(result.programs.single.slots, isEmpty);
    expect(result.issues.any((i) => i.code == 'cc_program_empty_slot'), isTrue);
  });

  test('an unparseable event date is left unset with a warning', () {
    final result = build(
      _archive([
        CcSet(
          recordId: '100',
          title: 'Set',
          eventDate: 'sometime in spring',
          items: const [],
        ),
      ]),
    );
    expect(result.programs.single.eventDate, isNull);
    expect(
      result.issues.any((i) => i.code == 'cc_program_unparsed_date'),
      isTrue,
    );
  });

  test('synthesises a title when the set has none', () {
    final result = build(_archive([CcSet(recordId: '42', items: const [])]));
    expect(result.programs.single.title, "Caller's Companion set #42");
  });

  test('derives the title from Location when the set has no title', () {
    final result = build(
      _archive([
        CcSet(
          recordId: '1',
          location: 'Grange Hall',
          eventDate: '3/14/2020',
          items: const [],
        ),
      ]),
    );
    final program = result.programs.single;
    expect(program.title, 'Grange Hall');
    expect(program.venue, 'Grange Hall');
  });

  test('falls back to the date-based title when there is no Location', () {
    final result = build(
      _archive([CcSet(recordId: '1', eventDate: '3/14/2020', items: const [])]),
    );
    expect(result.programs.single.title, "Caller's Companion set — 3/14/2020");
  });

  test('an impossible calendar date (2/31) is rejected as unparseable', () {
    final result = build(
      _archive([
        CcSet(
          recordId: '1',
          title: 'S',
          eventDate: '2/31/2020',
          items: const [],
        ),
      ]),
    );
    expect(result.programs.single.eventDate, isNull);
    expect(
      result.issues.any((i) => i.code == 'cc_program_unparsed_date'),
      isTrue,
    );
  });

  test('parses ISO event dates too', () {
    final result = build(
      _archive([
        CcSet(
          recordId: '1',
          title: 'S',
          eventDate: '2021-07-04',
          items: const [],
        ),
      ]),
    );
    expect(result.programs.single.eventDate, DateTime.utc(2021, 7, 4));
  });

  test('no sets yields no programs', () {
    final result = build(_archive(const []));
    expect(result.programs, isEmpty);
    expect(result.issues, isEmpty);
  });

  // Sanity: the result exposes ImportIssue instances (shared pipeline type).
  test('issues are ImportIssue instances', () {
    final result = build(
      _archive([
        CcSet(recordId: '1', title: 'S', items: [CcSetItem(order: 0)]),
      ]),
    );
    expect(result.issues, everyElement(isA<ImportIssue>()));
  });

  test('stamps provenance keyed on the CC zk_Set_ID (recordId)', () {
    final result = build(
      _archive([
        CcSet(recordId: '42', title: 'Friday Contra', items: const []),
      ]),
    );
    final prov = result.programs.single.provenance;
    expect(prov, isNotNull);
    expect(prov!.source, ProvenanceSource.callersCompanion);
    expect(prov.externalId, '42');
    expect(prov.sourceVersion, ccUsrSourceVersion);
    expect(prov.importedAt, DateTime.utc(2020));
  });

  group('#611 bidi/zero-width sanitization', () {
    // U+202E RIGHT-TO-LEFT OVERRIDE and U+200B ZERO WIDTH SPACE — the same
    // spoofing characters #444 strips from the CC dance import path.
    const rlo = '\u202E';
    const zwsp = '\u200B';

    test('strips bidi/zero-width characters from every single-line program '
        'field', () {
      final result = build(
        _archive([
          CcSet(
            recordId: '1',
            title: '${rlo}Evil${zwsp}Set',
            location: '${rlo}Evil${zwsp}Hall',
            band: '${rlo}Evil${zwsp}Band',
            caller: '${rlo}Evil${zwsp}Caller',
            dancerLevel: '${rlo}Evil${zwsp}Level',
            items: [
              CcSetItem(
                order: 0,
                danceRecordId: '7',
                guestCaller: '${rlo}Evil${zwsp}Guest',
              ),
            ],
          ),
        ]),
        danceIds: {'7': 'dance-uuid-7'},
      );

      final program = result.programs.single;
      expect(program.title, 'EvilSet');
      expect(program.venue, 'EvilHall');
      expect(program.band, 'EvilBand');
      expect(program.caller, 'EvilCaller');
      expect(program.dancerLevel, 'EvilLevel');
      expect(program.slots.single.guestCaller, 'EvilGuest');
    });

    test(
      'strips bidi/zero-width characters from notes and break-text slots',
      () {
        final result = build(
          _archive([
            CcSet(
              recordId: '1',
              title: 'Set',
              notes: '${rlo}Evil${zwsp}notes',
              items: [CcSetItem(order: 0, breakText: '${rlo}Evil${zwsp}break')],
            ),
          ]),
        );

        final program = result.programs.single;
        expect(program.notes, 'Evilnotes');
        expect(program.slots.single.text, 'Evilbreak');
      },
    );

    test(
      'strips bidi/zero-width characters from the Location-derived title',
      () {
        final result = build(
          _archive([
            CcSet(
              recordId: '1',
              location: '${rlo}Evil${zwsp}Hall',
              items: const [],
            ),
          ]),
        );
        expect(result.programs.single.title, 'EvilHall');
      },
    );

    test('an unresolved-dance placeholder built from sanitized break text', () {
      final result = build(
        _archive([
          CcSet(
            recordId: '1',
            title: 'Set',
            items: [
              CcSetItem(
                order: 0,
                danceRecordId: '999',
                breakText: '${rlo}Evil${zwsp}note',
              ),
            ],
          ),
        ]),
      );
      expect(result.programs.single.slots.single.text, 'Evilnote');
    });

    test('clean input is unchanged (byte-stable)', () {
      final result = build(
        _archive([
          CcSet(
            recordId: '100',
            title: 'Friday Contra',
            eventDate: '3/14/2020',
            location: 'Grange Hall',
            band: 'The Band',
            caller: 'Jane',
            dancerLevel: 'B/A',
            notes: 'Bring extra chairs.',
            items: [
              CcSetItem(
                order: 0,
                danceRecordId: '7',
                minutes: 8,
                guestCaller: 'Guest Caller',
              ),
              CcSetItem(order: 1, breakText: 'Waltz break'),
            ],
          ),
        ]),
        danceIds: {'7': 'dance-uuid-7'},
      );

      final program = result.programs.single;
      expect(program.title, 'Friday Contra');
      expect(program.venue, 'Grange Hall');
      expect(program.band, 'The Band');
      expect(program.caller, 'Jane');
      expect(program.dancerLevel, 'B/A');
      expect(program.notes, 'Bring extra chairs.');
      expect(program.slots[0].guestCaller, 'Guest Caller');
      expect(program.slots[1].text, 'Waltz break');
    });
  });
}
