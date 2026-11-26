// The tables of keys a record body may leave out when empty, which Device
// Sync fills in on receipt (`syncInboundKnownBody`). The behaviour each table
// buys is pinned in `sync_cleared_program_fields_test.dart`; these pin the
// tables themselves against the encoders and the privacy registry.
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/serialization/archive_entity_codec.dart'
    show
        archiveProgramToJson,
        omittedDanceDefaults,
        omittedProgramDefaults,
        withOmittedProgramDefaults;
import 'package:compendium_core/src/sync/sync_event_rule_body.dart'
    show
        omittedEventRuleDefaults,
        syncEventRuleBody,
        withOmittedEventRuleDefaults;
import 'package:test/test.dart';

void main() {
  final at = DateTime.utc(2026, 11, 1, 12);

  // Every top-level key the wire mapping syncs for [kind] that [emptyBody], a
  // body with nothing optional set, does not carry. The wire mapping is held
  // to the privacy registry by its own ratchets, so a new column cannot be
  // left out of it, and a key the encoder starts leaving out when empty shows
  // up here without anyone remembering to set it in a fixture.
  Set<String> leftOutWhenEmpty(
    SyncRecordKind kind,
    Map<String, Object?> emptyBody,
  ) => {
    for (final field in syncWireFields[kind]!)
      if (!field.path.contains('.') && !emptyBody.containsKey(field.path))
        field.path,
  };

  test('the program table names every key a sync body leaves out when '
      'empty', () {
    // A key left out without an entry here would not be cleared on the other
    // devices when it is emptied.
    final empty = archiveProgramToJson(
      Program(id: 'p0', title: 'Empty', createdAt: at, updatedAt: at),
      includeOptionalFields: true,
    );
    expect(
      leftOutWhenEmpty(SyncRecordKind.program, empty),
      omittedProgramDefaults.keys.toSet(),
    );
  });

  test('the event rule table names every key a sync body leaves out when '
      'empty', () {
    final empty = syncEventRuleBody(
      EventRule.of(
        id: 'r1',
        savedSearchId: 's1',
        quantifier: EventRuleQuantifier.atMost,
        count: 1,
        scope: EventRuleScope.wholeProgram,
        position: 0,
      ),
    );
    expect(
      leftOutWhenEmpty(SyncRecordKind.eventRule, empty),
      omittedEventRuleDefaults.keys.toSet(),
    );
  });

  test('every key filled on receipt is one this build syncs', () {
    // A key this build keeps private is never written into the device's own
    // column from a peer (spec §6.7); filling one with its empty value would
    // do exactly that.
    for (final (kind, table) in [
      (SyncRecordKind.dance, omittedDanceDefaults),
      (SyncRecordKind.program, omittedProgramDefaults),
      (SyncRecordKind.eventRule, omittedEventRuleDefaults),
    ]) {
      for (final key in table.keys) {
        expect(
          isShareableWirePath(kind, key),
          isTrue,
          reason: '${kind.name}.$key',
        );
      }
    }
  });

  test('a body that is not a whole record is not filled', () {
    expect(withOmittedProgramDefaults({'id': 'p1'}), {'id': 'p1'});
    expect(withOmittedEventRuleDefaults({'id': 'r1'}), {'id': 'r1'});
  });

  test('a key the body carries is never overwritten by its default', () {
    expect(
      withOmittedProgramDefaults({
        'slots': const <Object?>[],
        'archivedAt': '2026-11-01T12:00:00.000Z',
      })['archivedAt'],
      '2026-11-01T12:00:00.000Z',
    );
    expect(
      withOmittedEventRuleDefaults({
        'savedSearchId': 's1',
        'nickname': 'One petronella',
      })['nickname'],
      'One petronella',
    );
  });
}
