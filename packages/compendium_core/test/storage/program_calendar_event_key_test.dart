import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/serialization/archive_entity_codec.dart';
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  late CompendiumDatabase db;
  late ProgramRepository repo;
  final now = DateTime.utc(2026, 1, 1);
  final keyA = calendarEventKey('a@example.com', '');
  final keyB = calendarEventKey('b@example.com', '20300615');

  Program program(String id, {String? key, DateTime? updatedAt}) => Program(
    id: id,
    title: 'Program $id',
    eventDate: DateTime.utc(2030, 6, 15),
    calendarEventKey: key,
    createdAt: now,
    updatedAt: updatedAt ?? now,
  );

  setUp(() {
    db = openTestDatabase();
    repo = ProgramRepository(db);
  });
  tearDown(() => db.close());

  test('the key is stored and read back', () async {
    await repo.create(program('p1', key: keyA));
    expect((await repo.getById('p1'))!.calendarEventKey, keyA);
    await repo.create(program('p2'));
    expect((await repo.getById('p2'))!.calendarEventKey, isNull);
  });

  test('calendarEventKeyStates: live, deleted, absent', () async {
    await repo.create(program('live', key: keyA));
    await repo.create(program('trashed', key: keyB));
    await repo.softDelete('trashed', at: now.add(const Duration(hours: 1)));
    final states = await repo.calendarEventKeyStates([
      keyA,
      keyB,
      calendarEventKey('nobody', ''),
    ]);
    expect(states, {keyA: false, keyB: true});
  });

  test('a key held by a live and a deleted program counts as live', () async {
    await repo.create(program('old', key: keyA));
    await repo.softDelete('old', at: now.add(const Duration(hours: 1)));
    await repo.create(program('new', key: keyA));
    expect(await repo.calendarEventKeyStates([keyA]), {keyA: false});
  });

  test('a permanently deleted program no longer holds its key', () async {
    await repo.create(program('gone', key: keyA));
    await repo.softDelete('gone', at: now.add(const Duration(hours: 1)));
    await repo.permanentlyDelete(
      'gone',
      now: now.add(const Duration(hours: 2)),
    );
    expect(await repo.calendarEventKeyStates([keyA]), isEmpty);
    expect(await repo.programDeletedStates(['gone']), isEmpty);
  });

  test('programDeletedStates', () async {
    await repo.create(program('live'));
    await repo.create(program('trashed'));
    await repo.softDelete('trashed', at: now.add(const Duration(hours: 1)));
    expect(await repo.programDeletedStates(['live', 'trashed', 'missing']), {
      'live': false,
      'trashed': true,
    });
  });

  test('a program synced from another device carries its key, so this '
      'device recognises the import', () async {
    await repo.writeFromSync(program('synced', key: keyA));
    expect(await repo.calendarEventKeyStates([keyA]), {keyA: false});
  });

  test('a duplicate does not keep the key', () {
    final copy = program(
      'p1',
      key: keyA,
    ).duplicate(newId: 'p2', newSlotId: () => 's', now: now);
    expect(copy.calendarEventKey, isNull);
  });

  test('the archive codec round-trips the key and drops a malformed one', () {
    final json = archiveProgramToJson(program('p1', key: keyA));
    expect(json['calendarEventKey'], keyA);
    expect(
      archiveProgramToJson(program('p2')).containsKey('calendarEventKey'),
      isFalse,
      reason: 'absent when unset, so other programs keep their wire hash',
    );
    Map<String, Object?> envelope(Map<String, Object?> programJson) => {
      'schemaVersion': archiveSchemaVersion,
      'exportedAt': '2026-04-05T00:00:00.000Z',
      'programs': [programJson],
    };
    final decoded = decodeArchive(jsonEncode(envelope(json)));
    expect(decoded.hasErrors, isFalse);
    expect(decoded.archive.programs.single.calendarEventKey, keyA);

    final bad = decodeArchive(
      jsonEncode(envelope({...json, 'calendarEventKey': 'pat@example.com'})),
    );
    expect(bad.hasErrors, isFalse, reason: 'the program is not refused');
    expect(bad.archive.programs.single.calendarEventKey, isNull);
  });
}
