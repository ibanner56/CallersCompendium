import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';
import 'fixtures.dart';

void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;
  late CustomFieldDefRepository defs;

  final now = DateTime.utc(2026, 6, 1);

  final textDef = CustomFieldDef(
    id: 'f-text',
    key: 'origin',
    label: 'Origin',
    type: CustomFieldType.text,
  );
  final numberDef = CustomFieldDef(
    id: 'f-num',
    key: 'year',
    label: 'Year',
    type: CustomFieldType.number,
  );
  final choiceDef = CustomFieldDef(
    id: 'f-choice',
    key: 'mood',
    label: 'Mood',
    type: CustomFieldType.choice,
    choices: const ['calm', 'lively'],
  );

  setUp(() async {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
    defs = CustomFieldDefRepository(db);
    await defs.upsert(textDef);
    await defs.upsert(numberDef);
    await defs.upsert(choiceDef);
  });

  tearDown(() => db.close());

  group('upsertCustomFieldForMany', () {
    test('adds the field to dances that lack it', () async {
      await dances.create(sampleDance(id: 'a', title: 'Alpha'));
      await dances.create(sampleDance(id: 'b', title: 'Bravo'));

      final changed = await dances.upsertCustomFieldForMany(
        ['a', 'b'],
        def: textDef,
        value: 'New England',
        now: now,
      );

      expect(changed, 2);
      expect((await dances.getById('a'))!.customFields, [
        CustomFieldValue(fieldId: 'f-text', value: 'New England'),
      ]);
    });

    test('overwrites the chosen key but leaves other keys untouched', () async {
      await dances.create(
        sampleDance(
          id: 'a',
          title: 'Alpha',
          customFields: [
            CustomFieldValue(fieldId: 'f-text', value: 'Old'),
            CustomFieldValue(fieldId: 'f-num', value: 1990),
          ],
        ),
      );

      final changed = await dances.upsertCustomFieldForMany(
        ['a'],
        def: textDef,
        value: 'Updated',
        now: now,
      );

      expect(changed, 1);
      final fields = (await dances.getById('a'))!.customFields;
      // The other key survives with its value.
      expect(
        fields,
        containsAll([
          CustomFieldValue(fieldId: 'f-text', value: 'Updated'),
          CustomFieldValue(fieldId: 'f-num', value: 1990),
        ]),
      );
      expect(fields.length, 2);
    });

    test(
      'is idempotent — skips dances whose key already equals the value',
      () async {
        await dances.create(
          sampleDance(
            id: 'a',
            title: 'Alpha',
            customFields: [CustomFieldValue(fieldId: 'f-text', value: 'Same')],
          ),
        );
        await dances.create(sampleDance(id: 'b', title: 'Bravo'));

        final changed = await dances.upsertCustomFieldForMany(
          ['a', 'b'],
          def: textDef,
          value: 'Same',
          now: now,
        );

        // Only b changes; a already holds "Same".
        expect(changed, 1);
      },
    );

    test('accepts a valid choice value', () async {
      await dances.create(sampleDance(id: 'a', title: 'Alpha'));

      final changed = await dances.upsertCustomFieldForMany(
        ['a'],
        def: choiceDef,
        value: 'lively',
        now: now,
      );

      expect(changed, 1);
      expect((await dances.getById('a'))!.customFields, [
        CustomFieldValue(fieldId: 'f-choice', value: 'lively'),
      ]);
    });

    test('rejects a value whose type does not match the field', () async {
      await dances.create(sampleDance(id: 'a', title: 'Alpha'));

      // Text value for a number field.
      expect(
        () => dances.upsertCustomFieldForMany(
          ['a'],
          def: numberDef,
          value: 'not a number',
          now: now,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect((await dances.getById('a'))!.customFields, isEmpty);
    });

    test('rejects a choice value outside the declared choices', () async {
      await dances.create(sampleDance(id: 'a', title: 'Alpha'));

      expect(
        () => dances.upsertCustomFieldForMany(
          ['a'],
          def: choiceDef,
          value: 'furious',
          now: now,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect((await dances.getById('a'))!.customFields, isEmpty);
    });

    test('no-op for empty ids and unknown ids', () async {
      await dances.create(sampleDance(id: 'a', title: 'Alpha'));

      expect(
        await dances.upsertCustomFieldForMany(
          const [],
          def: textDef,
          value: 'x',
          now: now,
        ),
        0,
      );
      expect(
        await dances.upsertCustomFieldForMany(
          ['does-not-exist'],
          def: textDef,
          value: 'x',
          now: now,
        ),
        0,
      );
      expect((await dances.getById('a'))!.customFields, isEmpty);
    });
  });

  group('clearCustomFieldForMany', () {
    test('removes only the chosen key, leaving other keys untouched', () async {
      await dances.create(
        sampleDance(
          id: 'a',
          title: 'Alpha',
          customFields: [
            CustomFieldValue(fieldId: 'f-text', value: 'keep-me?'),
            CustomFieldValue(fieldId: 'f-num', value: 2001),
          ],
        ),
      );

      final changed = await dances.clearCustomFieldForMany(
        ['a'],
        fieldId: 'f-text',
        now: now,
      );

      expect(changed, 1);
      expect((await dances.getById('a'))!.customFields, [
        CustomFieldValue(fieldId: 'f-num', value: 2001),
      ]);
    });

    test('is idempotent — skips dances lacking the key', () async {
      await dances.create(
        sampleDance(
          id: 'a',
          title: 'Alpha',
          customFields: [CustomFieldValue(fieldId: 'f-text', value: 'x')],
        ),
      );
      await dances.create(sampleDance(id: 'b', title: 'Bravo'));

      final changed = await dances.clearCustomFieldForMany(
        ['a', 'b'],
        fieldId: 'f-text',
        now: now,
      );

      // Only a has the key.
      expect(changed, 1);
      expect((await dances.getById('a'))!.customFields, isEmpty);
    });

    test('no-op for empty ids and unknown ids', () async {
      await dances.create(
        sampleDance(
          id: 'a',
          title: 'Alpha',
          customFields: [CustomFieldValue(fieldId: 'f-text', value: 'x')],
        ),
      );

      expect(
        await dances.clearCustomFieldForMany(
          const [],
          fieldId: 'f-text',
          now: now,
        ),
        0,
      );
      expect(
        await dances.clearCustomFieldForMany(
          ['does-not-exist'],
          fieldId: 'f-text',
          now: now,
        ),
        0,
      );
      expect((await dances.getById('a'))!.customFields.length, 1);
    });
  });
}
