// A program or event rule body leaves a key out when its value is empty
// (`archiveProgramToJson`, `syncEventRuleBody`), and Device Sync applies an
// inbound body by overlaying it on the stored record key by key. These pin
// that clearing such a value on one device clears it on the others, and that
// the two devices then hold the same bytes, so neither queues a conflict.
// The dance fields have the same rule (`withOmittedDanceDefaults`).
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/serialization/archive_entity_codec.dart'
    show archiveProgramToJson;
import 'package:test/test.dart';

import '../storage/test_database.dart';

void main() {
  late CompendiumRepositories a;
  late CompendiumRepositories b;
  final created = DateTime.utc(2026, 11, 1, 12);
  final edited = DateTime.utc(2026, 11, 2, 12);
  final cleared = DateTime.utc(2026, 11, 3, 12);
  const address = (kind: SyncRecordKind.program, recordId: 'p1');

  setUp(() {
    a = CompendiumRepositories(openTestDatabase(), contraTaxonomy);
    b = CompendiumRepositories(openTestDatabase(), contraTaxonomy);
  });
  tearDown(() async {
    await a.db.close();
    await b.db.close();
  });

  Future<SyncMergeCandidate> held(
    CompendiumRepositories repos, [
    SyncRecordAddress at = address,
  ]) async => (await CompendiumSyncStorage(repos).snapshot()).local[at]!;

  Future<void> receive(SyncMergeCandidate candidate) async {
    final result = await const SyncApplyEngine().apply(
      candidates: [SyncMergeCandidate(blob: candidate.blob)],
      storage: CompendiumSyncStorage(b),
    );
    expect(result.reports, isEmpty);
    expect(result.applied, [candidate.address]);
  }

  Program full() => Program(
    id: 'p1',
    title: 'Saturday',
    dialectName: 'Larks and Robins',
    payMinorUnits: 15000,
    payCurrency: 'USD',
    startMinute: 1170,
    endMinute: 1320,
    lessonMinute: 1140,
    arrivalMinute: 1110,
    archivedAt: edited,
    calendarEventKey: 'a' * 64,
    calendarEventFingerprint: 'b' * 64,
    calendarWrittenAt: edited,
    calendarFlag: 'cancelled',
    eventRuleIds: const ['r1'],
    slots: [ProgramSlot(id: 's1', position: 0, text: 'Opener')],
    createdAt: created,
    updatedAt: edited,
  );

  // Each key a program body leaves out when empty, cleared on A the way the
  // app clears it: the keys the cleared body no longer carries, the edit, and
  // the value that must end up empty. B must end up with the empty value and
  // A's bytes. The last test below checks that these cover every such key.
  final cases =
      <
        String,
        (Set<String>, Program Function(Program), Object? Function(Program))
      >{
        'un-archiving': (
          {'archivedAt'},
          (p) => p.copyWith(clearArchivedAt: true),
          (p) => p.archivedAt,
        ),
        'clearing the start time': (
          {'startMinute'},
          (p) => p.copyWith(clearStartMinute: true),
          (p) => p.startMinute,
        ),
        'clearing the end time': (
          {'endMinute'},
          (p) => p.copyWith(clearEndMinute: true),
          (p) => p.endMinute,
        ),
        'clearing the lesson time': (
          {'lessonMinute'},
          (p) => p.copyWith(clearLessonMinute: true),
          (p) => p.lessonMinute,
        ),
        'clearing the arrival time': (
          {'arrivalMinute'},
          (p) => p.copyWith(clearArrivalMinute: true),
          (p) => p.arrivalMinute,
        ),
        'removing the last event rule': (
          {'eventRuleIds'},
          (p) => p.copyWith(eventRuleIds: const []),
          (p) => p.eventRuleIds.isEmpty ? null : p.eventRuleIds,
        ),
        'clearing the calendar flag': (
          {'calendarFlag'},
          (p) => p.copyWith(clearCalendarFlag: true),
          (p) => p.calendarFlag,
        ),
        'unlinking the calendar event': (
          {
            'calendarEventKey',
            'calendarEventFingerprint',
            'calendarWrittenAt',
            'calendarFlag',
          },
          (p) => p.copyWith(clearCalendarEventKey: true),
          (p) => [
            p.calendarEventKey,
            p.calendarEventFingerprint,
            p.calendarWrittenAt,
            p.calendarFlag,
          ].nonNulls.firstOrNull,
        ),
        'clearing the pay': (
          {'payMinorUnits', 'payCurrency'},
          (p) => p.copyWith(clearPay: true),
          (p) => p.payMinorUnits ?? p.payCurrency,
        ),
        'clearing the dialect': (
          {'dialectName'},
          (p) => p.copyWith(clearDialectName: true),
          (p) => p.dialectName,
        ),
      };

  group('a program value cleared on one device is cleared on the other', () {
    for (final MapEntry(key: name, value: (keys, clear, valueOf))
        in cases.entries) {
      test(name, () async {
        await a.programs.create(full());
        await receive(await held(a));
        expect((await held(b)).wireHash, (await held(a)).wireHash);
        expect(valueOf((await b.programs.getById('p1'))!), isNotNull);
        expect(keys.every((await held(a)).blob.body.containsKey), isTrue);

        final mine = (await a.programs.getById('p1'))!;
        await a.programs.update(clear(mine).copyWith(updatedAt: cleared));
        expect(valueOf((await a.programs.getById('p1'))!), isNull);
        final newer = await held(a);
        expect(
          keys.where(newer.blob.body.containsKey),
          isEmpty,
          reason: 'the cleared body leaves the keys out',
        );
        await receive(newer);

        final onB = (await b.programs.getById('p1'))!;
        expect(onB.updatedAt, cleared);
        expect(valueOf(onB), isNull);
        expect((await held(b)).wireHash, newer.wireHash);
      });
    }
  });

  test('the cases cover every key a program body leaves out when empty', () {
    // Derived from the wire mapping, which its own ratchets hold to the
    // privacy registry, rather than from a fixture someone must remember.
    final empty = archiveProgramToJson(
      Program(id: 'p0', title: 'Empty', createdAt: created, updatedAt: created),
      includeOptionalFields: true,
    );
    final leftOut = {
      for (final field in syncWireFields[SyncRecordKind.program]!)
        if (!field.path.contains('.') && !empty.containsKey(field.path))
          field.path,
    };
    expect({for (final (keys, _, _) in cases.values) ...keys}, leftOut);
  });

  test('removing an event rule\'s nickname reaches the other device', () async {
    final search = await a.savedSearches.create(
      name: 'Petronellas',
      spec: SavedSearchSpec.fromPanelState(
        CollectionPanelState(text: 'petronella'),
        today: DateTime.utc(2026, 11, 1),
      ).value!,
      at: created,
    );
    final rule = await a.eventRules.create(
      savedSearchId: search.id,
      quantifier: EventRuleQuantifier.atMost,
      count: 1,
      scope: EventRuleScope.wholeProgram,
      nickname: 'One petronella',
      at: edited,
    );
    final ruleAddress = (kind: SyncRecordKind.eventRule, recordId: rule.id);
    await receive(await held(a, ruleAddress));
    expect((await b.eventRules.get(rule.id))!.nickname, 'One petronella');

    await a.eventRules.save(
      EventRule.of(
        id: rule.id,
        savedSearchId: search.id,
        quantifier: EventRuleQuantifier.atMost,
        count: 1,
        scope: EventRuleScope.wholeProgram,
        position: rule.position,
      ),
      at: cleared,
    );
    expect((await a.eventRules.get(rule.id))!.nickname, isNull);
    final newer = await held(a, ruleAddress);
    expect(newer.blob.body.containsKey('nickname'), isFalse);
    await receive(newer);
    expect((await b.eventRules.get(rule.id))!.nickname, isNull);
    expect((await held(b, ruleAddress)).wireHash, newer.wireHash);
  });

  // Bodies a v0.10.0-beta build sent, byte for byte, in a run where it
  // received `p1` and `p2` from this build (with every key above set), then
  // the caller edited p1's notes and cleared p2's pay there an hour later.
  // That build does not know the keys added after it; it keeps them aside and
  // sends them back with its edit, so filling a missing key on receipt does
  // not clear them. It does know pay, and leaves pay out once it is cleared.
  group('an edit from a v0.10.0-beta device', () {
    const ruleId = 'f799ffd3-27a3-44fc-93db-fb67106f05d8';
    final at = DateTime.utc(2026, 11, 10, 12);
    Program sent(String id) => Program(
      id: id,
      title: 'Saturday $id',
      notes: 'from the new build',
      dialectName: 'Larks and Robins',
      payMinorUnits: 15000,
      payCurrency: 'USD',
      startMinute: 1170,
      endMinute: 1320,
      lessonMinute: 1140,
      arrivalMinute: 1110,
      archivedAt: at,
      calendarEventKey: 'a' * 64,
      calendarEventFingerprint: 'b' * 64,
      calendarWrittenAt: at,
      calendarFlag: 'cancelled',
      eventRuleIds: const [ruleId],
      slots: [ProgramSlot(id: 's-$id', position: 0, text: 'Opener')],
      createdAt: at,
      updatedAt: at,
    );
    final aBody =
        '"archivedAt":"2026-11-10T12:00:00.000Z","arrivalMinute":1110,'
        '"band":null,"calendarEventFingerprint":"${'b' * 64}",'
        '"calendarEventKey":"${'a' * 64}","calendarFlag":"cancelled",'
        '"calendarWrittenAt":"2026-11-10T12:00:00.000Z","caller":null,'
        '"createdAt":"2026-11-10T12:00:00.000Z","dancerLevel":null,'
        '"deletedAt":null,"dialectName":"Larks and Robins","endMinute":1320,'
        '"eventDate":null,"eventRuleIds":["$ruleId"],"hideAlternates":false,';
    final fromTag = {
      'p1':
          '{"body":{$aBody"id":"p1","lessonMinute":1140,'
          '"notes":"edited on 0.10.0","payCurrency":"USD",'
          '"payMinorUnits":15000,"provenance":null,"slots":[{"danceId":null,'
          '"danceMinutes":null,"guestCaller":null,"id":"s-p1","isAlt":false,'
          '"isPurgedDance":false,"performedAt":null,"position":0,'
          '"text":"Opener","walkthroughMinutes":null}],"startMinute":1170,'
          '"status":"draft","title":"Saturday p1",'
          '"updatedAt":"2026-11-10T13:00:00.000Z","venue":null,'
          '"venueId":null},"deletedAt":null,'
          '"existenceAt":"2026-11-10T12:00:00.000Z","id":"p1",'
          '"kind":"program","updatedAt":"2026-11-10T13:00:00.000Z","v":1}',
      'p2':
          '{"body":{$aBody"id":"p2","lessonMinute":1140,'
          '"notes":"from the new build","provenance":null,'
          '"slots":[{"danceId":null,"danceMinutes":null,"guestCaller":null,'
          '"id":"s-p2","isAlt":false,"isPurgedDance":false,'
          '"performedAt":null,"position":0,"text":"Opener",'
          '"walkthroughMinutes":null}],"startMinute":1170,"status":"draft",'
          '"title":"Saturday p2","updatedAt":"2026-11-10T13:00:00.000Z",'
          '"venue":null,"venueId":null},"deletedAt":null,'
          '"existenceAt":"2026-11-10T12:00:00.000Z","id":"p2",'
          '"kind":"program","updatedAt":"2026-11-10T13:00:00.000Z","v":1}',
    };
    // The hashes each build computed in that run: what this build sent, and
    // what v0.10.0-beta sent back.
    const sentHash = {
      'p1': '70a476e0b17378012495ed177a9d12c78dd888888beab37951345c331490379e',
      'p2': 'ca1c4fff49264567fa8dbb120c7a89de7ce3ee1d1d4dd2e1987263178c5b6d6a',
    };
    const tagHash = {
      'p1': '6a38a6cfc02f6da197d02c955d09afe447cc4b8edc3a904c81e8e577818c37f1',
      'p2': 'd4b5bb828ad7533db7f9ffcfe73991bfd93f93ca4b3d3ffff5598f14544b65d9',
    };

    Future<Program> roundTrip(String id) async {
      await b.programs.create(sent(id));
      final at = (kind: SyncRecordKind.program, recordId: id);
      expect(
        (await CompendiumSyncStorage(b).snapshot()).local[at]!.wireHash,
        sentHash[id],
      );
      final incoming = SyncMergeCandidate(
        blob: decodeSyncRecordBlob(fromTag[id]!),
      );
      expect(incoming.wireHash, tagHash[id]);
      await receive(incoming);
      expect(
        (await CompendiumSyncStorage(b).snapshot()).local[at]!.wireHash,
        tagHash[id],
        reason: 'this device holds what v0.10.0-beta sent',
      );
      return (await b.programs.getById(id))!;
    }

    test('keeps every value that build kept aside', () async {
      final p = await roundTrip('p1');
      expect(p.notes, 'edited on 0.10.0');
      expect(p.archivedAt, at);
      expect(
        [p.startMinute, p.endMinute, p.lessonMinute, p.arrivalMinute],
        [1170, 1320, 1140, 1110],
      );
      expect(p.eventRuleIds, [ruleId]);
      expect(p.calendarEventKey, 'a' * 64);
      expect(p.calendarEventFingerprint, 'b' * 64);
      expect(p.calendarWrittenAt, at);
      expect(p.calendarFlag, 'cancelled');
      expect(p.payMinorUnits, 15000);
      expect(p.dialectName, 'Larks and Robins');
    });

    test('clears the pay that build cleared, and keeps the rest', () async {
      final p = await roundTrip('p2');
      expect(p.payMinorUnits, isNull);
      expect(p.payCurrency, isNull);
      expect(p.archivedAt, at);
      expect(p.eventRuleIds, [ruleId]);
      expect(p.calendarFlag, 'cancelled');
    });
  });
}
