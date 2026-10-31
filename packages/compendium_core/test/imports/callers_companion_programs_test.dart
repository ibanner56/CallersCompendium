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
    expect(program.slots[0].danceMinutes, 8);
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

  test('titles a set as CC does, YYYY/MM/DD - Location (#1976)', () {
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
    expect(program.title, '2020/03/14 - Grange Hall');
    expect(program.venue, 'Grange Hall');
  });

  test('titles a set with no Location by its date alone', () {
    final result = build(
      _archive([CcSet(recordId: '1', eventDate: '3/14/2020', items: const [])]),
    );
    expect(result.programs.single.title, '2020/03/14');
  });

  test('pads the year to four digits', () {
    final result = build(
      _archive([
        CcSet(
          recordId: '1',
          location: 'Hall',
          eventDate: '0999-01-02',
          items: const [],
        ),
      ]),
    );
    expect(result.programs.single.title, '0999/01/02 - Hall');
  });

  test('a blank Location titles the set by its date alone', () {
    final result = build(
      _archive([
        CcSet(
          recordId: '1',
          location: '   ',
          eventDate: '3/14/2020',
          items: const [],
        ),
      ]),
    );
    expect(result.programs.single.title, '2020/03/14');
  });

  test('titles a set with no date by its Location alone', () {
    final result = build(
      _archive([
        CcSet(recordId: '1', location: 'Grange Hall', items: const []),
      ]),
    );
    expect(result.programs.single.title, 'Grange Hall');
  });

  test('an unparseable date leaves the Location as the title', () {
    final result = build(
      _archive([
        CcSet(
          recordId: '1',
          location: 'Grange Hall',
          eventDate: 'spring',
          items: const [],
        ),
      ]),
    );
    expect(result.programs.single.title, 'Grange Hall');
  });

  test('an unparseable date and no Location keep the raw date', () {
    final result = build(
      _archive([CcSet(recordId: '1', eventDate: 'spring', items: const [])]),
    );
    expect(result.programs.single.title, "Caller's Companion set — spring");
  });

  group('per-slot callers (#1976)', () {
    List<String?> slotCallers(String? setCaller, List<String?> names) {
      final result = build(
        _archive([
          CcSet(
            recordId: '1',
            caller: setCaller,
            items: [
              for (final (i, name) in names.indexed)
                CcSetItem(order: i, danceRecordId: '$i', guestCaller: name),
            ],
          ),
        ]),
        danceIds: {for (var i = 0; i < names.length; i++) '$i': 'd$i'},
      );
      return [for (final s in result.programs.single.slots) s.guestCaller];
    }

    test('dropped when every slot names the set caller by first name', () {
      expect(slotCallers('Michael Smith', ['Michael', 'michael', null]), [
        null,
        null,
        null,
      ]);
    });

    test('dropped when every slot names the set caller in full', () {
      expect(
        slotCallers('Michael Smith', ['Michael  Smith', 'Michael Smith']),
        [null, null],
      );
    });

    test('kept when the slots name more than one caller', () {
      expect(slotCallers('Michael Smith', ['Michael', 'Lisa', null]), [
        'Michael',
        'Lisa',
        null,
      ]);
    });

    test('kept when the only name is not the set caller', () {
      expect(slotCallers('Michael Smith', [null, 'Lisa', null]), [
        null,
        'Lisa',
        null,
      ]);
    });

    test('the set caller matches in other written forms', () {
      expect(slotCallers('Michael Smith, Jr', ['Michael']), [null]);
      expect(slotCallers('Michael Smith,', ['Michael']), [null]);
      expect(slotCallers('Michael Smith, Jr.', ['Michael Smith Jr']), [null]);
      expect(slotCallers('Michael Smith, Jr.', ['Michael Smith, Jr.']), [null]);
      expect(slotCallers('Michael Smith', ['Michael Smith Jr']), [
        'Michael Smith Jr',
      ]);
      expect(slotCallers('Andy Smith', ['Andy', 'Andy']), [null, null]);
      expect(slotCallers('J. Michael Smith', ['Michael']), [null]);
      expect(slotCallers('Mary Kate Olsen', ['Mary Kate']), [null]);
      expect(slotCallers('Mary-Kate Olsen', ['Mary-Kate']), [null]);
      expect(slotCallers('Michaela Smith', ['Michael']), ['Michael']);
      expect(slotCallers('Michael Smith, Jr.', ['Michael']), [null]);
      expect(slotCallers('Michael\u00A0Smith', ['Michael']), [null]);
    });

    test('a surname or middle name alone is a different caller', () {
      expect(slotCallers('Graham Christian', ['Christian']), ['Christian']);
      expect(slotCallers('Michael Smith', ['Smith']), ['Smith']);
      expect(slotCallers('Mary Kate Olsen', ['Kate']), ['Kate']);
    });

    test('two spellings of the set caller count as one caller', () {
      expect(slotCallers('Michael Smith', ['Michael', 'Michael Smith']), [
        null,
        null,
      ]);
    });

    test('a longer name than the set caller may be someone else', () {
      expect(slotCallers('Mary', ['Mary Kate', 'Mary Lou']), [
        'Mary Kate',
        'Mary Lou',
      ]);
      expect(slotCallers('Michael', ['Michael Smith']), ['Michael Smith']);
    });

    test('initials never reduce a name to its surname', () {
      expect(slotCallers('B. Smith', ['A. Smith', 'A. Smith']), [
        'A. Smith',
        'A. Smith',
      ]);
      expect(slotCallers('J. R. Smith', ['Smith']), ['Smith']);
      expect(slotCallers('A Lisa', ['Lisa']), ['Lisa']);
      expect(slotCallers('J. Smith, Jr.', ['Smith']), ['Smith']);
      expect(slotCallers('J. Smith Jr.', ['Smith']), ['Smith']);
    });

    test('a slot name of only punctuation names nobody', () {
      expect(slotCallers('Michael Smith', ['Michael', '.']), [null, null]);
    });

    test('a set called by several people keeps its slot callers', () {
      for (final caller in [
        'Michael & Lisa Smith',
        'Michael and Lisa',
        'Michael/Lisa',
        'Michael + Lisa',
        'Michael Smith, Lisa Greenleaf',
        'Michael, Lisa',
        'Smith, Michael',
        'Michael, Lisa, Bob',
        'Michael Smith, Jr., Lisa Greenleaf',
        'Michael with Lisa',
        'Michael Smith; Lisa Greenleaf',
      ]) {
        expect(slotCallers(caller, ['Michael', 'Michael']), [
          'Michael',
          'Michael',
        ], reason: caller);
      }
    });

    test('a co-called set keeps the other caller', () {
      expect(slotCallers('Michael Smith & Lisa Greenleaf', [null, 'Lisa']), [
        null,
        'Lisa',
      ]);
    });

    test("a skipped empty item's caller does not count", () {
      final result = build(
        _archive([
          CcSet(
            recordId: '1',
            caller: 'Michael Smith',
            items: [
              CcSetItem(order: 0, danceRecordId: '0', guestCaller: 'Michael'),
              CcSetItem(order: 1, guestCaller: 'Lisa'),
            ],
          ),
        ]),
        danceIds: {'0': 'd0'},
      );
      final slots = result.programs.single.slots;
      expect(slots, hasLength(1));
      expect(slots.single.guestCaller, isNull);
    });

    test('kept when the set has no caller', () {
      expect(slotCallers(null, ['Michael', 'Michael']), ['Michael', 'Michael']);
    });
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
