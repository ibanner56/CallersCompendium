import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/storage/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  late CompendiumDatabase db;
  late CustomFieldDefRepository repo;
  late DanceRepository dances;

  setUp(() {
    db = openTestDatabase();
    repo = CustomFieldDefRepository(db);
    dances = DanceRepository(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  test('round-trips a text field', () async {
    final def = CustomFieldDef(
      id: 'f1',
      key: 'origin',
      label: 'Origin',
      type: CustomFieldType.text,
    );
    // ignore: unused_result
    await repo.upsert(def);
    final loaded = await repo.getById('f1');
    expect(loaded!.id, 'f1');
    expect(loaded.key, 'origin');
    expect(loaded.type, CustomFieldType.text);
    expect(loaded.choices, isNull);
  });

  test('round-trips a choice field with its choices', () async {
    final def = CustomFieldDef(
      id: 'f1',
      key: 'difficulty',
      label: 'Difficulty',
      type: CustomFieldType.choice,
      choices: const ['easy', 'medium', 'hard'],
      showInList: true,
      searchable: false,
    );
    // ignore: unused_result
    await repo.upsert(def);
    final loaded = await repo.getById('f1');
    expect(loaded!.choices, ['easy', 'medium', 'hard']);
    expect(loaded.showInList, isTrue);
    expect(loaded.searchable, isFalse);
  });

  test('listAll orders by label', () async {
    // ignore: unused_result
    await repo.upsert(
      CustomFieldDef(
        id: 'f1',
        key: 'z',
        label: 'Zebra',
        type: CustomFieldType.text,
      ),
    );
    // ignore: unused_result
    await repo.upsert(
      CustomFieldDef(
        id: 'f2',
        key: 'a',
        label: 'Apple',
        type: CustomFieldType.text,
      ),
    );
    expect((await repo.listAll()).map((d) => d.label), ['Apple', 'Zebra']);
  });

  test('delete throws if any dance still has a value set', () async {
    // ignore: unused_result
    await repo.upsert(
      CustomFieldDef(
        id: 'f1',
        key: 'origin',
        label: 'Origin',
        type: CustomFieldType.text,
      ),
    );
    await dances.create(
      Dance(
        id: 'd1',
        title: 'Some Dance',
        customFields: [CustomFieldValue(fieldId: 'f1', value: 'New England')],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
    await expectLater(repo.delete('f1'), throwsA(isA<StateError>()));
  });

  test('delete succeeds once the referencing dance clears the value', () async {
    // ignore: unused_result
    await repo.upsert(
      CustomFieldDef(
        id: 'f1',
        key: 'origin',
        label: 'Origin',
        type: CustomFieldType.text,
      ),
    );
    final dance = Dance(
      id: 'd1',
      title: 'Some Dance',
      customFields: [CustomFieldValue(fieldId: 'f1', value: 'New England')],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await dances.create(dance);
    await dances.update(dance.copyWith(customFields: const []));

    await repo.delete('f1');
    expect(await repo.getById('f1'), isNull);
  });

  test('delete succeeds once no dance references the field', () async {
    // ignore: unused_result
    await repo.upsert(
      CustomFieldDef(
        id: 'f1',
        key: 'origin',
        label: 'Origin',
        type: CustomFieldType.text,
      ),
    );
    await repo.delete('f1');
    expect(await repo.getById('f1'), isNull);
  });

  group('isInUse', () {
    test('returns false when no dance has a value for the field', () async {
      // ignore: unused_result
      await repo.upsert(
        CustomFieldDef(
          id: 'f1',
          key: 'notes',
          label: 'Notes',
          type: CustomFieldType.text,
        ),
      );
      expect(await repo.isInUse('f1'), isFalse);
    });

    test('returns true when at least one dance has a value', () async {
      // ignore: unused_result
      await repo.upsert(
        CustomFieldDef(
          id: 'f1',
          key: 'notes',
          label: 'Notes',
          type: CustomFieldType.text,
        ),
      );
      await dances.create(
        Dance(
          id: 'd1',
          title: 'Dance',
          customFields: [CustomFieldValue(fieldId: 'f1', value: 'some note')],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      expect(await repo.isInUse('f1'), isTrue);
    });

    test('returns false for an unknown field id', () async {
      expect(await repo.isInUse('nonexistent'), isFalse);
    });
  });

  group('listUsedChoiceValues', () {
    test('returns empty set when field has no values on any dance', () async {
      // ignore: unused_result
      await repo.upsert(
        CustomFieldDef(
          id: 'f1',
          key: 'level',
          label: 'Level',
          type: CustomFieldType.choice,
          choices: const ['easy', 'hard'],
        ),
      );
      expect(await repo.listUsedChoiceValues('f1'), isEmpty);
    });

    test(
      'returns the set of distinct choice strings stored on dances',
      () async {
        // ignore: unused_result
        await repo.upsert(
          CustomFieldDef(
            id: 'f1',
            key: 'level',
            label: 'Level',
            type: CustomFieldType.choice,
            choices: const ['easy', 'medium', 'hard'],
          ),
        );
        await dances.create(
          Dance(
            id: 'd1',
            title: 'Dance A',
            customFields: [CustomFieldValue(fieldId: 'f1', value: 'easy')],
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );
        await dances.create(
          Dance(
            id: 'd2',
            title: 'Dance B',
            customFields: [CustomFieldValue(fieldId: 'f1', value: 'hard')],
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );
        // 'medium' is defined but not used.
        expect(await repo.listUsedChoiceValues('f1'), {'easy', 'hard'});
      },
    );
  });
  group('tolerant decode of a corrupt stored choicesJson', () {
    Future<void> writeRawRow({
      required String id,
      required String key,
      required String type,
      String? choicesJson,
    }) => db
        .into(db.customFieldDefs)
        .insertOnConflictUpdate(
          CustomFieldDefsCompanion.insert(
            id: id,
            key: key,
            label: key,
            type: CustomFieldType.values.byName(type),
            choicesJson: Value(choicesJson),
          ),
        );

    test('a malformed (non-JSON) choicesJson decodes to null instead of '
        'throwing', () async {
      await writeRawRow(
        id: 'f1',
        key: 'level',
        type: 'choice',
        choicesJson: '{not valid json',
      );
      expect(await repo.getById('f1'), isNull);
      expect(await repo.listAll(), isEmpty);
    });

    test('a choicesJson holding a non-string element decodes to null instead '
        'of throwing', () async {
      await writeRawRow(
        id: 'f1',
        key: 'level',
        type: 'choice',
        choicesJson: '[1, 2, 3]',
      );
      expect(await repo.getById('f1'), isNull);
    });

    test('a choice field whose choicesJson decodes to an empty list decodes to '
        'null instead of throwing the "must declare at least one choice" '
        'invariant', () async {
      await writeRawRow(
        id: 'f1',
        key: 'level',
        type: 'choice',
        choicesJson: '[]',
      );
      expect(await repo.getById('f1'), isNull);
    });

    test(
      'one corrupt row does not prevent other, valid rows from loading',
      () async {
        await writeRawRow(
          id: 'f1',
          key: 'corrupt',
          type: 'choice',
          choicesJson: 'not json',
        );
        // ignore: unused_result
        await repo.upsert(
          CustomFieldDef(
            id: 'f2',
            key: 'level',
            label: 'Level',
            type: CustomFieldType.choice,
            choices: const ['easy', 'hard'],
          ),
        );
        final all = await repo.listAll();
        expect(all.map((d) => d.id), ['f2']);
      },
    );

    test('a valid choicesJson still round-trips correctly', () async {
      await writeRawRow(
        id: 'f1',
        key: 'level',
        type: 'choice',
        choicesJson: '["easy","medium","hard"]',
      );
      final loaded = await repo.getById('f1');
      expect(loaded!.choices, ['easy', 'medium', 'hard']);
    });
  });
}
