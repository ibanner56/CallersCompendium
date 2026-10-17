import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/imports/callers_companion_user_fields.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';
import 'support/fmp_fixture_builder.dart';

/// One CC dance row for [_usrBytes]: its `zk_Dance_ID`, name and the three
/// `UserDefined_N` / `UserDefined_N_Name` pairs (null = column left empty).
typedef _Row = ({
  String id,
  String name,
  List<(String? value, String? label)> user,
});

Uint8List _usrBytes(List<_Row> rows) => buildFmp12Fixture([
  FmpFixtureTable(
    index: 1,
    name: 'Dance',
    columnNames: [
      'zk_Dance_ID',
      'Name',
      'UserDefined_1',
      'UserDefined_1_Name',
      'UserDefined_2',
      'UserDefined_2_Name',
      'UserDefined_3',
      'UserDefined_3_Name',
    ],
    rows: [
      for (var i = 0; i < rows.length; i++)
        MapEntry(10 + i, {
          1: rows[i].id,
          2: rows[i].name,
          for (var n = 0; n < rows[i].user.length; n++) ...{
            if (rows[i].user[n].$1 != null) 3 + 2 * n: rows[i].user[n].$1!,
            if (rows[i].user[n].$2 != null) 4 + 2 * n: rows[i].user[n].$2!,
          },
        }),
    ],
  ),
]);

void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;
  late CustomFieldDefRepository defs;
  late CallersCompanionUsrAdapter adapter;
  late CallersCompanionUsrImporter importer;
  late String Function() nextId;
  final now = DateTime.utc(2026, 7, 15);

  CallersCompanionUsrImporter importerWith({ProgramRepository? programs}) =>
      CallersCompanionUsrImporter(
        ImportPipeline(dances, ChoreographerRepository(db)),
        programs ?? ProgramRepository(db),
        VenueRepository(db),
        defs,
        adapter: adapter,
      );

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
    defs = CustomFieldDefRepository(db);
    adapter = CallersCompanionUsrAdapter();
    importer = importerWith();
    var n = 0;
    nextId = () => 'id-${++n}';
  });

  tearDown(() => db.close());

  Future<CcUsrImportResult> run(Uint8List bytes) =>
      importer.import(bytes, now: now, venueEntityMode: false, newId: nextId);

  Future<Dance> danceNamed(String name) async =>
      (await dances.listAll()).singleWhere((d) => d.title == name);

  Future<Map<String, Object>> valuesByKey(Dance dance) async {
    final all = {for (final f in await defs.listAll()) f.id: f.key};
    return {for (final v in dance.customFields) all[v.fieldId]!: v.value};
  }

  Future<void> seed(CustomFieldDef def) async {
    final _ = await defs.upsert(def);
  }

  _Row row(String id, String name, List<(String?, String?)> user) =>
      (id: id, name: name, user: user);

  group('key derivation', () {
    test('slugs a label to a valid lower-case key', () {
      expect(ccUserFieldKeyForLabel('Card colour'), 'card_colour');
      expect(ccUserFieldKeyForLabel('  Tempo (bpm)! '), 'tempo_bpm');
      expect(ccUserFieldKeyForLabel('3rd couple'), 'f_3rd_couple');
      expect(isValidCustomFieldKey(ccUserFieldKeyForLabel('3rd couple')), true);
    });

    test('a label with no key characters falls back to a stable hash', () {
      final a = ccUserFieldKeyForLabel('温度');
      expect(a, startsWith('cc_'));
      expect(isValidCustomFieldKey(a), isTrue);
      expect(ccUserFieldKeyForLabel('温度'), a, reason: 'deterministic');
      expect(ccUserFieldKeyForLabel('湿度'), isNot(a));
      expect(ccUserFieldKeyForLabel('!!!'), startsWith('cc_'));
    });

    test('a long label is bounded', () {
      final key = ccUserFieldKeyForLabel('a' * 200);
      expect(key.length, kCcUserFieldMaxKeyLength);
    });

    test('labels that slug alike in one dance get distinct keys + a note', () {
      final plan = planCcUserFields(const [
        CcUserField(label: 'Tempo', value: 'fast'),
        CcUserField(label: 'tempo!', value: 'slow'),
      ]);
      expect([for (final f in plan.fields) f.key], ['tempo', 'tempo_2']);
      expect(plan.fields[1].label, 'tempo!');
      expect(plan.issues.single.code, 'cc_user_field_key_adjusted');
      expect(plan.issues.single.severity, ImportIssueSeverity.warning);
    });

    test('a label is cut to its display bound, the key stays valid', () {
      final plan = planCcUserFields([
        CcUserField(label: 'x' * 500, value: 'v'),
      ]);
      expect(plan.fields.single.label.length, kCcUserFieldMaxLabelLength);
      expect(plan.fields.single.key.length, kCcUserFieldMaxKeyLength);
    });

    test('a source-blank label is noted as info', () {
      final plan = planCcUserFields(const [
        CcUserField(label: 'User field 2', value: 'x', labelWasBlank: true),
      ]);
      expect(plan.fields.single.key, 'user_field_2');
      expect(plan.issues.single.code, 'cc_user_field_label_missing');
      expect(plan.issues.single.severity, ImportIssueSeverity.info);
    });

    test('a blank label becomes "Note" and empty values are dropped', () {
      final plan = planCcUserFields(const [
        CcUserField(label: '  ', value: 'x'),
        CcUserField(label: 'Empty', value: '   '),
      ]);
      expect(plan.fields.single.key, 'note');
      expect(plan.fields.single.label, 'Note');
    });
  });

  group('mapper', () {
    test(
      'strips control, bidi and invisible characters from label and value',
      () {
        final mapping = mapCallersCompanionDance(
          CcDanceRecord(
            name: 'A',
            userFields: const [
              CcUserField(
                label: 'Card\u200B col\u202Eour\u0007',
                value: 'bl\u202Eue\u0007',
              ),
            ],
          ),
        );
        final value = mapping.dance.customFields.single;
        expect(value.value, 'blue');
        final field = ccUserFieldOfPlaceholder(value.fieldId)!;
        expect(field.label, 'Card colour');
        expect(field.key, 'card_colour');
      },
    );
  });

  group('import', () {
    test('lands as typed values, not calling-note lines', () async {
      final result = await run(
        _usrBytes([
          row('4', 'Swing', [
            ('blue', 'Card colour'),
            ('loud', null),
            (null, null),
          ]),
        ]),
      );

      final dance = await danceNamed('Swing');
      expect(await valuesByKey(dance), {
        'card_colour': 'blue',
        'user_field_2': 'loud',
      });
      expect(dance.callingNotes, isEmpty);
      final created = await defs.listAll();
      expect(
        created.map((f) => (f.key, f.label, f.type, f.shareable)),
        unorderedEquals([
          ('card_colour', 'Card colour', CustomFieldType.text, true),
          ('user_field_2', 'User field 2', CustomFieldType.text, true),
        ]),
      );
      expect(result.insertedCustomFieldIds, hasLength(2));
    });

    test('two dances sharing a label share one definition', () async {
      await run(
        _usrBytes([
          row('4', 'A', [('red', 'Tempo')]),
          row('7', 'B', [('slow', 'Tempo')]),
        ]),
      );
      expect(await defs.listAll(), hasLength(1));
      expect(await valuesByKey(await danceNamed('A')), {'tempo': 'red'});
      expect(await valuesByKey(await danceNamed('B')), {'tempo': 'slow'});
    });

    test(
      'same-key labels in one dance keep both values + a draft note',
      () async {
        final bytes = _usrBytes([
          row('4', 'A', [('fast', 'Tempo'), ('slow', 'tempo!')]),
        ]);
        final batch = await importer.plan(bytes);
        expect(
          batch.records.single.draft.issues.map((i) => i.code),
          contains('cc_user_field_key_adjusted'),
        );
        await run(bytes);
        expect(await valuesByKey(await danceNamed('A')), {
          'tempo': 'fast',
          'tempo_2': 'slow',
        });
      },
    );

    test('a non-Latin label imports under a stable fallback key', () async {
      await run(
        _usrBytes([
          row('4', 'A', [('20', '温度')]),
          row('7', 'B', [('30', '温度')]),
        ]),
      );
      // The fixture builder is not byte-faithful for non-ASCII, so the exact
      // hash is covered by the unit test above; here: one shared, valid key.
      final keys = [for (final f in await defs.listAll()) f.key];
      expect(keys, hasLength(1));
      expect(keys.single, startsWith('cc_'));
      expect(isValidCustomFieldKey(keys.single), isTrue);
    });

    test('matches an existing key case-insensitively', () async {
      await seed(
        CustomFieldDef(
          id: 'typed',
          key: 'Tempo',
          label: 'My tempo',
          type: CustomFieldType.text,
        ),
      );
      final result = await run(
        _usrBytes([
          row('4', 'A', [('fast', 'Tempo')]),
        ]),
      );
      expect(result.insertedCustomFieldIds, isEmpty);
      expect([for (final f in await defs.listAll()) f.id], ['typed']);
      expect((await danceNamed('A')).customFields.single.fieldId, 'typed');
    });

    test('reuses a live text definition with the same key', () async {
      await seed(
        CustomFieldDef(
          id: 'mine',
          key: 'tempo',
          label: 'My tempo',
          type: CustomFieldType.text,
          shareable: false,
        ),
      );
      final result = await run(
        _usrBytes([
          row('4', 'A', [('fast', 'Tempo')]),
        ]),
      );
      expect(result.insertedCustomFieldIds, isEmpty);
      expect(result.customFieldIssues, isEmpty);
      final all = await defs.listAll();
      expect(all.single.id, 'mine');
      expect(all.single.label, 'My tempo', reason: 'existing is untouched');
      expect(all.single.shareable, isFalse);
      expect((await danceNamed('A')).customFields.single.fieldId, 'mine');
    });

    test(
      'a key held by another type is not reused: suffixed + noted',
      () async {
        await seed(
          CustomFieldDef(
            id: 'num',
            key: 'tempo',
            label: 'Tempo',
            type: CustomFieldType.number,
          ),
        );
        final result = await run(
          _usrBytes([
            row('4', 'A', [('fast', 'Tempo')]),
          ]),
        );
        final dance = await danceNamed('A');
        expect(await valuesByKey(dance), {'tempo_2': 'fast'});
        expect(
          result.customFieldIssues.single.code,
          'cc_user_field_key_conflict',
        );
        expect(
          (await defs.getById('num'))!.type,
          CustomFieldType.number,
          reason: 'the existing field is never changed',
        );
      },
    );

    test('a second column cannot share a suffixed definition', () async {
      await seed(
        CustomFieldDef(
          id: 'num',
          key: 'tempo',
          label: 'Tempo',
          type: CustomFieldType.number,
        ),
      );
      // "Tempo" → tempo_2 (conflict), and a literal "Tempo 2" slugs tempo_2.
      await run(
        _usrBytes([
          row('4', 'A', [('fast', 'Tempo'), ('two', 'Tempo 2')]),
        ]),
      );
      final dance = await danceNamed('A');
      expect(dance.customFields, hasLength(2));
      expect(
        dance.customFields.map((v) => v.fieldId).toSet(),
        hasLength(2),
        reason: 'distinct columns keep distinct definitions',
      );
    });

    test(
      'revives a tombstoned text definition and re-tombstones on undo',
      () async {
        await seed(
          CustomFieldDef(
            id: 'old',
            key: 'tempo',
            label: 'Tempo',
            type: CustomFieldType.text,
          ),
        );
        await defs.delete('old', at: DateTime.utc(2026, 1, 1));
        final result = await run(
          _usrBytes([
            row('4', 'A', [('fast', 'Tempo')]),
          ]),
        );
        expect(result.restoredCustomFieldIds, ['old']);
        expect((await defs.listAll()).single.id, 'old');

        await importer.undo(result);
        expect(await defs.listAll(), isEmpty);
        expect(
          (await defs.listAllWithDeleted()).map((f) => (f.field.id, f.deleted)),
          [('old', true)],
          reason: 'the row survives, tombstoned as it was',
        );
      },
    );
  });

  group('undo', () {
    test('removes exactly the definitions this import created', () async {
      await seed(
        CustomFieldDef(
          id: 'mine',
          key: 'tempo',
          label: 'Tempo',
          type: CustomFieldType.text,
        ),
      );
      final result = await run(
        _usrBytes([
          row('4', 'A', [('fast', 'Tempo'), ('blue', 'Card colour')]),
        ]),
      );
      expect(result.insertedCustomFieldIds, hasLength(1));
      await importer.undo(result);
      expect([for (final f in await defs.listAll()) f.id], ['mine']);
      expect(await dances.listAll(), isEmpty);
    });

    test('leaves a definition another dance now holds a value for', () async {
      final result = await run(
        _usrBytes([
          row('4', 'A', [('blue', 'Card colour')]),
        ]),
      );
      final fieldId = result.insertedCustomFieldIds.single;
      await dances.create(
        Dance(
          id: 'other',
          title: 'Other',
          customFields: [CustomFieldValue(fieldId: fieldId, value: 'red')],
          createdAt: now,
          updatedAt: now,
        ),
      );
      await importer.undo(result);
      expect((await defs.listAll()).single.id, fieldId);
      expect((await dances.getById('other'))!.customFields, hasLength(1));
    });
  });

  group('commit compensation', () {
    test('a failed program write leaves no definitions behind', () async {
      final failing = importerWith(programs: _FailingProgramRepository(db));
      final bytes = Uint8List.fromList(
        buildFmp12Fixture([
          FmpFixtureTable(
            index: 1,
            name: 'Dance',
            columnNames: [
              'zk_Dance_ID',
              'Name',
              'UserDefined_1',
              'UserDefined_1_Name',
            ],
            rows: [
              MapEntry(10, {1: '4', 2: 'A', 3: 'blue', 4: 'Card colour'}),
            ],
          ),
          FmpFixtureTable(
            index: 2,
            name: 'Set',
            columnNames: [
              'zk_Set_ID',
              'Date',
              'Location',
              'Band',
              'Caller',
              'Notes',
            ],
            rows: [
              MapEntry(20, {
                1: '1',
                2: '3/14/2020',
                3: 'Hall',
                4: 'B',
                5: 'J',
                6: 'n',
              }),
            ],
          ),
          FmpFixtureTable(
            index: 3,
            name: 'SetItem',
            columnNames: [
              'zk_Set_ID',
              'zk_SetItem_ID',
              'zk_Dance_ID',
              'Order',
              'Time',
              'Break',
            ],
            rows: [
              MapEntry(30, {1: '1', 2: '101', 3: '4', 4: '1', 5: '8'}),
            ],
          ),
        ]),
      );
      await expectLater(
        failing.import(bytes, now: now, venueEntityMode: false, newId: nextId),
        throwsA(isA<StateError>()),
      );
      expect(await dances.listAll(includeDeleted: true), isEmpty);
      expect(await defs.listAllWithDeleted(), isEmpty);
    });

    test(
      'a failure while pruning unused definitions reverts the import',
      () async {
        final throwing = CallersCompanionUsrImporter(
          ImportPipeline(dances, ChoreographerRepository(db)),
          ProgramRepository(db),
          VenueRepository(db),
          _ThrowingInUseDefs(db),
          adapter: adapter,
        );
        await expectLater(
          throwing.import(
            _usrBytes([
              row('4', 'A', [('blue', 'Card colour')]),
            ]),
            now: now,
            venueEntityMode: false,
            newId: nextId,
          ),
          throwsA(isA<StateError>()),
        );
        expect(await dances.listAll(includeDeleted: true), isEmpty);
        expect(await defs.listAllWithDeleted(), isEmpty);
      },
    );

    test('a definition no committed dance uses is not left behind', () async {
      // An untracked dance of the same title makes the CC row ambiguous, and an
      // ambiguous row with no resolution is skipped.
      await dances.create(
        Dance(id: 'native', title: 'A', createdAt: now, updatedAt: now),
      );
      final result = await run(
        _usrBytes([
          row('4', 'A', [('blue', 'Card colour')]),
        ]),
      );
      expect(result.danceSession.insertedDanceIds, isEmpty);
      expect(result.insertedCustomFieldIds, isEmpty);
      expect(await defs.listAllWithDeleted(), isEmpty);
    });
  });

  group('re-import', () {
    test(
      'keeps a custom value the person added since the first import',
      () async {
        final bytes = _usrBytes([
          row('4', 'A', [('blue', 'Card colour')]),
        ]);
        await run(bytes);
        final imported = await danceNamed('A');

        await seed(
          CustomFieldDef(
            id: 'mine',
            key: 'venue_notes',
            label: 'Venue notes',
            type: CustomFieldType.text,
          ),
        );
        await dances.update(
          imported.copyWith(
            customFields: [
              ...imported.customFields,
              CustomFieldValue(fieldId: 'mine', value: 'steep stairs'),
            ],
          ),
        );

        await run(bytes);

        final after = await danceNamed('A');
        expect(await valuesByKey(after), {
          'card_colour': 'blue',
          'venue_notes': 'steep stairs',
        });
      },
    );

    test('the file wins for a column it carries', () async {
      await run(
        _usrBytes([
          row('4', 'A', [('blue', 'Card colour')]),
        ]),
      );
      await run(
        _usrBytes([
          row('4', 'A', [('green', 'Card colour')]),
        ]),
      );
      expect(await valuesByKey(await danceNamed('A')), {
        'card_colour': 'green',
      });
    });
  });
}

class _FailingProgramRepository extends ProgramRepository {
  _FailingProgramRepository(super.db);

  @override
  Future<void> create(Program program, {LiveVenueIds? knownVenueIds}) async =>
      throw StateError('simulated program persist failure');
}

class _ThrowingInUseDefs extends CustomFieldDefRepository {
  _ThrowingInUseDefs(super.db);

  @override
  Future<bool> isInUse(String id) async =>
      throw StateError('simulated in-use check failure');
}
