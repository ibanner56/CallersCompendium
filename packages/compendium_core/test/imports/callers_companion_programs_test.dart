import 'package:compendium_core/src/imports/callers_companion_programs.dart';
import 'package:compendium_core/src/imports/callers_companion_usr_archive.dart';
import 'package:compendium_core/src/imports/structured_draft.dart';
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
}
