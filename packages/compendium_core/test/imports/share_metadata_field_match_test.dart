// INTAKE-2: how a shared file's custom field is matched to the receiver's.
// Key, type and (for a choice field) the set of choices decide; the receiver's
// label, choice order and display settings are theirs and never block a match.
// A field that differs goes in under `<key>_2` with a review note (maintainer
// decisions, 2026-10-29 and its round 2).
import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';

final _now = DateTime.utc(2026, 1, 1);

ShareMetadataImporter _importer(CompendiumDatabase db) => ShareMetadataImporter(
  tags: TagRepository(db),
  sources: PublishedSourceRepository(db),
  customFields: CustomFieldDefRepository(db),
);

CompendiumArchive _archive(List<CustomFieldDef> fields) =>
    CompendiumArchive(exportedAt: _now, customFields: fields);

String Function() _ids(String prefix) {
  var next = 0;
  return () => '$prefix-${++next}';
}

void main() {
  test('a field that differs only in label and display settings is the '
      "receiver's own, untouched", () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final fields = CustomFieldDefRepository(db);
    final local = CustomFieldDef(
      id: 'local-card',
      key: 'card',
      label: 'Card',
      type: CustomFieldType.choice,
      choices: const ['A', 'B', 'C'],
      showInList: true,
      searchable: false,
      shareable: false,
    );
    await fields.upsert(local);

    final result = await _importer(db).commit(
      _archive([
        // Caller's Companion's "card" label makes the same key; the order of
        // the choices and all three settings differ too.
        CustomFieldDef(
          id: 'archive-card',
          key: 'card',
          label: 'card',
          type: CustomFieldType.choice,
          choices: const ['C', 'A', 'B'],
        ),
      ]),
      now: _now,
      newId: _ids('fresh'),
    );

    expect(result.fieldIdByArchiveId['archive-card'], 'local-card');
    expect(result.insertedFieldIds, isEmpty);
    expect(result.issues, isEmpty);
    final after = (await fields.listAll()).single;
    expect(after.label, 'Card');
    expect(after.choices, ['A', 'B', 'C']);
    expect(after.showInList, isTrue);
    expect(after.searchable, isFalse);
    expect(after.shareable, isFalse);
  });

  test('a choice field with other choices goes in under <key>_2', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final fields = CustomFieldDefRepository(db);
    await fields.upsert(
      CustomFieldDef(
        id: 'local-card',
        key: 'card',
        label: 'Card',
        type: CustomFieldType.choice,
        choices: const ['A', 'B'],
      ),
    );

    final result = await _importer(db).commit(
      _archive([
        CustomFieldDef(
          id: 'archive-card',
          key: 'card',
          label: 'Card',
          type: CustomFieldType.choice,
          choices: const ['A', 'B', 'C'],
        ),
      ]),
      now: _now,
      newId: _ids('fresh'),
    );

    final added = (await fields.getById(
      result.fieldIdByArchiveId['archive-card']!,
    ))!;
    expect(added.key, 'card_2');
    expect(added.choices, ['A', 'B', 'C']);
    expect((await fields.getById('local-card'))!.choices, ['A', 'B']);
    expect(result.issues.single.data, {'label': 'Card', 'key': 'card_2'});
  });

  test(
    'receiving the same file again lands on the same <key>_2 field',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final fields = CustomFieldDefRepository(db);
      await fields.upsert(
        CustomFieldDef(
          id: 'local-tempo',
          key: 'tempo',
          label: 'Tempo',
          type: CustomFieldType.text,
        ),
      );
      final archive = _archive([
        CustomFieldDef(
          id: 'archive-tempo',
          key: 'tempo',
          label: 'Tempo',
          type: CustomFieldType.number,
        ),
      ]);

      final first = await _importer(
        db,
      ).commit(archive, now: _now, newId: _ids('first'));
      final second = await _importer(
        db,
      ).commit(archive, now: _now, newId: _ids('second'));

      expect(
        second.fieldIdByArchiveId['archive-tempo'],
        first.fieldIdByArchiveId['archive-tempo'],
      );
      expect(second.insertedFieldIds, isEmpty);
      expect((await fields.listAll()).map((f) => f.key).toSet(), {
        'tempo',
        'tempo_2',
      });
      // Still noted: the values go into tempo_2, not the field named tempo.
      expect(second.issues.single.data, {'label': 'Tempo', 'key': 'tempo_2'});
    },
  );

  test('a <key>_2 that differs too moves on to <key>_3', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final fields = CustomFieldDefRepository(db);
    await fields.upsert(
      CustomFieldDef(
        id: 'local-tempo',
        key: 'tempo',
        label: 'Tempo',
        type: CustomFieldType.text,
      ),
    );
    await fields.upsert(
      CustomFieldDef(
        id: 'local-tempo-2',
        key: 'tempo_2',
        label: 'Tempo 2',
        type: CustomFieldType.boolean,
      ),
    );

    final result = await _importer(db).commit(
      _archive([
        CustomFieldDef(
          id: 'archive-tempo',
          key: 'tempo',
          label: 'Tempo',
          type: CustomFieldType.number,
        ),
      ]),
      now: _now,
      newId: _ids('fresh'),
    );

    expect(
      (await fields.getById(result.fieldIdByArchiveId['archive-tempo']!))!.key,
      'tempo_3',
    );
    // The note names the field whose key was taken first.
    expect(result.issues.single.data, {'label': 'Tempo', 'key': 'tempo_3'});
  });

  test('a clash between two fields of the same file names neither', () async {
    final db = openTestDatabase();
    addTearDown(db.close);

    final result = await _importer(db).commit(
      _archive([
        CustomFieldDef(
          id: 'a',
          key: 'tempo',
          label: 'Tempo',
          type: CustomFieldType.text,
        ),
        CustomFieldDef(
          id: 'b',
          key: 'tempo',
          label: 'Other tempo',
          type: CustomFieldType.number,
        ),
      ]),
      now: _now,
      newId: _ids('fresh'),
    );

    expect(result.insertedFieldIds, hasLength(2));
    final note = result.issues.single;
    expect(note.code, 'archive_custom_field_key_conflict');
    // The clashing row is the file's own text, which a note must not echo.
    expect(note.data, isEmpty);
  });

  test('preview raises the notes commit would, and writes nothing', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final fields = CustomFieldDefRepository(db);
    await fields.upsert(
      CustomFieldDef(
        id: 'local-tempo',
        key: 'tempo',
        label: 'Tempo',
        type: CustomFieldType.text,
      ),
    );
    final archive = _archive([
      CustomFieldDef(
        id: 'archive-tempo',
        key: 'tempo',
        label: 'Tempo',
        type: CustomFieldType.number,
      ),
      CustomFieldDef(
        id: 'archive-new',
        key: 'teach',
        label: 'Teach',
        type: CustomFieldType.text,
      ),
    ]);

    final preview = await _importer(db).preview(archive);

    expect((await fields.listAll()).single.id, 'local-tempo');
    final committed = await _importer(
      db,
    ).commit(archive, now: _now, newId: _ids('fresh'));
    expect(preview.map((i) => i.code), committed.issues.map((i) => i.code));
    expect(preview.map((i) => i.data), committed.issues.map((i) => i.data));
    expect(preview, hasLength(1));
  });

  test('a shared dance keeps its value in the <key>_2 field, and Undo '
      'removes that field', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final dances = DanceRepository(db, contraTaxonomy);
    final fields = CustomFieldDefRepository(db);
    await fields.upsert(
      CustomFieldDef(
        id: 'local-tempo',
        key: 'tempo',
        label: 'Tempo',
        type: CustomFieldType.text,
      ),
    );
    final importer = CompendiumArchiveImporter(
      ImportPipeline(dances, ChoreographerRepository(db)),
      ProgramRepository(db),
      VenueRepository(db),
      repositories: CompendiumRepositories(db, contraTaxonomy),
      tags: TagRepository(db),
      sources: PublishedSourceRepository(db),
      customFields: fields,
    );
    final archive = CompendiumArchive(
      exportedAt: _now,
      dances: [
        Dance(
          id: 'd1',
          title: 'Shared dance',
          customFields: [CustomFieldValue(fieldId: 'f1', value: 120)],
          createdAt: _now,
          updatedAt: _now,
        ),
      ],
      customFields: [
        CustomFieldDef(
          id: 'f1',
          key: 'tempo',
          label: 'Tempo',
          type: CustomFieldType.number,
        ),
      ],
    );

    final planned = await importer.planMetadataIssues(archive);
    expect(planned.single.data, {'label': 'Tempo', 'key': 'tempo_2'});

    final result = await importer.import(
      encodeArchive(archive),
      archive,
      now: _now,
      newId: _ids('receiver'),
    );

    final value = (await dances.listAll()).single.customFields.single;
    expect(value.value, 120);
    expect((await fields.getById(value.fieldId))!.key, 'tempo_2');
    expect(result.metadata!.issues.single.data['key'], 'tempo_2');

    await importer.undo(result);

    expect((await fields.listAll()).single.id, 'local-tempo');
  });
}
