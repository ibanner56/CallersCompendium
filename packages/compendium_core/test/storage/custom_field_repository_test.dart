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

  group('permanent delete keeps a tombstoned dance whole (#1357)', () {
    Future<int> valueRows(String fieldId) async {
      final rows = await (db.select(
        db.customFieldValues,
      )..where((t) => t.fieldId.equals(fieldId))).get();
      return rows.length;
    }

    Future<void> seedTombstonedValue() async {
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
          title: 'Dance',
          customFields: [CustomFieldValue(fieldId: 'f1', value: 'some note')],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      await dances.softDelete('d1', at: DateTime.utc(2026, 2));
    }

    test('tombstones the definition instead of erasing it', () async {
      // `custom_field_values` is ON DELETE CASCADE, so erasing here destroyed
      // the tombstoned dance's value outright.
      await seedTombstonedValue();

      await repo.delete('f1', permanent: true);

      final row = await (db.select(
        db.customFieldDefs,
      )..where((t) => t.id.equals('f1'))).getSingleOrNull();
      expect(row, isNotNull, reason: 'the row must survive the rollback');
      expect(row!.deletedAt, isNotNull, reason: 'as a tombstone');
      expect(await valueRows('f1'), 1, reason: 'the value must survive too');
      expect(
        await repo.getById('f1'),
        isNull,
        reason: 'and still leave every live view, which is what undo needs',
      );
    });

    test('a restored dance keeps its field value, once the definition is '
        'restored too', () async {
      // `_customFieldsForMany` inner-joins on
      // `custom_field_defs.deleted_at IS NULL`, so the dance-only restore shows
      // nothing. Asserted so the release note's two-row requirement cannot
      // quietly become "restoring the dance is enough".
      await seedTombstonedValue();

      await repo.delete('f1', permanent: true);

      await dances.restore('d1', at: DateTime.utc(2026, 3));
      expect(
        (await dances.getById('d1'))!.customFields,
        isEmpty,
        reason: 'a tombstoned definition stays hidden until it is restored',
      );

      await repo.restore('f1', at: DateTime.utc(2026, 3));
      final restored = (await dances.getById('d1'))!.customFields.single;
      expect(restored.fieldId, 'f1');
      expect(restored.value, 'some note');
    });

    test('still erases an unreferenced, unpublished definition', () async {
      // ignore: unused_result
      await repo.upsert(
        CustomFieldDef(
          id: 'f1',
          key: 'origin',
          label: 'Origin',
          type: CustomFieldType.text,
        ),
      );

      await repo.delete('f1', permanent: true);

      final row = await (db.select(
        db.customFieldDefs,
      )..where((t) => t.id.equals('f1'))).getSingleOrNull();
      expect(row, isNull, reason: 'a rollback still leaves nothing behind');
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

  group('finite number values', () {
    final def = CustomFieldDef(
      id: 'f1',
      key: 'number',
      label: 'Number',
      type: CustomFieldType.number,
    );

    test('round-trips finite values', () {
      expect(
        encodeCustomFieldValue(
          CustomFieldValue(fieldId: 'f1', value: 3.5),
          def,
        ),
        (null, 3.5),
      );
    });

    for (final raw in [double.nan, double.infinity, double.negativeInfinity]) {
      test('rejects $raw', () {
        expect(
          () => encodeCustomFieldValue(
            CustomFieldValue(fieldId: 'f1', value: raw),
            def,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    }
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

  group('creating onto a live natural key', _liveKeyCollisionOnCreate);
}

// ---------------------------------------------------------------------------
// Creating a definition whose key a LIVE definition already holds.
//
// `_write` only consults `resolveNaturalKeyCollision` when `current != null`,
// and a creation carries an id no row holds — so the #1348 decision was never
// reached and the insert fell through to SQLite, which refused it with a raw
// `SqliteException`. `CustomFieldDefRepository` is the one natural-keyed kind
// whose screen lets a user reach that: the key field's validator checks format
// only, and `custom_fields_screen._openForm` catches `DuplicateNaturalKeyError`
// alone, so the field was silently not created.
void _liveKeyCollisionOnCreate() {
  late CompendiumDatabase db;
  late CustomFieldDefRepository repo;

  setUp(() {
    db = openTestDatabase();
    repo = CustomFieldDefRepository(db);
  });
  tearDown(() => db.close());

  CustomFieldDef def(String id, String key, {String label = 'Mood'}) =>
      CustomFieldDef(
        id: id,
        key: key,
        label: label,
        type: CustomFieldType.text,
      );

  test('refuses a creation onto a live key, typed, before any write', () async {
    // ignore: unused_result
    await repo.upsert(def('incumbent', 'mood'), at: DateTime.utc(2020));

    await expectLater(
      repo.upsert(def('newcomer', 'mood', label: 'Other')),
      throwsA(
        isA<DuplicateNaturalKeyError>()
            .having((e) => e.table, 'table', 'custom_field_defs')
            .having((e) => e.column, 'column', 'key')
            .having((e) => e.value, 'value', 'mood')
            .having((e) => e.holderId, 'holderId', 'incumbent'),
      ),
    );

    // The incumbent is untouched and the newcomer does not exist. Asserting the
    // whole row rather than its key: a takeover would rewrite the primary key,
    // and a partial write would move `label` or `updated_at`.
    final rows = await db.select(db.customFieldDefs).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, 'incumbent');
    expect(rows.single.key, 'mood');
    expect(rows.single.label, 'Mood');
    expect(rows.single.updatedAt, DateTime.utc(2020).toLocal());
    // A refusal leaves nothing to re-attempt, so it records no skip — the same
    // rule `resolveNaturalKeyCollision` states for a colliding rename.
    expect(
      await db.customSelect('SELECT 1 FROM normalisation_skips').get(),
      isEmpty,
    );
  });

  test('still ADOPTS a tombstoned holder rather than refusing', () async {
    // The precondition for the whole guard: the refusal must discriminate live
    // from tombstoned, or it breaks `adoptTombstonedNaturalKey`'s entire reason
    // for existing (delete a field, create it again under a fresh UUID).
    // ignore: unused_result
    await repo.upsert(def('incumbent', 'mood'), at: DateTime.utc(2020));
    await repo.delete('incumbent', at: DateTime.utc(2021));
    expect(
      (await (db.select(
        db.customFieldDefs,
      )..where((t) => t.id.equals('incumbent'))).getSingle()).deletedAt,
      isNotNull,
      reason: 'the fixture must actually be a tombstone, not a deleted row',
    );

    final written = await repo.upsert(
      def('newcomer', 'mood', label: 'Revived'),
      at: DateTime.utc(2022),
    );
    expect(written, 'incumbent', reason: 'the tombstone was adopted');
    final live = await repo.listAll();
    expect(live, hasLength(1));
    expect(live.single.label, 'Revived');
  });

  test(
    'a case-different key is not a collision and creates a second row',
    () async {
      // `custom_field_defs.key` carries a plain UNIQUE with no NOCASE collation,
      // so "Mood" and "mood" are two keys. The guard must not widen to a
      // case-insensitive rule the index does not implement.
      // ignore: unused_result
      await repo.upsert(def('incumbent', 'mood'));
      // ignore: unused_result
      await repo.upsert(def('newcomer', 'Mood', label: 'Other'));
      expect(await repo.listAll(), hasLength(2));
    },
  );

  test(
    'writeFromSync keeps refusing with StateError, not the typed error',
    () async {
      // §6.7 owns identity for an inbound record: it reports the record to
      // reconciliation and is never shown to anybody. The create-collision guard
      // is `!fromSync` for exactly that reason, and this is what would catch a
      // future simplification that drops the flag.
      // ignore: unused_result
      await repo.upsert(def('incumbent', 'mood'));
      await expectLater(
        repo.writeFromSync(def('inbound', 'mood')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('wants a name held by'),
          ),
        ),
      );
    },
  );
}
