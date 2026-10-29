import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

/// The search bar's text index and custom fields (maintainer decision
/// search-index (a), 2026-10-29): it honours each field's Searchable setting,
/// and never indexes a yes/no value as the word "true" or "false".
void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repos;

  setUp(() {
    db = openTestDatabase();
    repos = CompendiumRepositories(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  CustomFieldDef textField({bool searchable = true}) => CustomFieldDef(
    id: 'f-venue-note',
    key: 'venue_note',
    label: 'Venue note',
    type: CustomFieldType.text,
    searchable: searchable,
  );

  final yesNoField = CustomFieldDef(
    id: 'f-teach',
    key: 'needs_teach',
    label: 'Needs a teach',
    type: CustomFieldType.boolean,
  );

  // `upsert` returns the id the definition occupies; these tests name it.
  Future<void> upsertDef(
    CustomFieldDef def, {
    bool localUserEdit = false,
  }) async {
    final _ = await repos.customFieldDefs.upsert(
      def,
      localUserEdit: localUserEdit,
    );
  }

  Future<void> createDance(String id, List<CustomFieldValue> values) => repos
      .dances
      .create(sampleDance(id: id, title: 'Dance $id', customFields: values));

  // The search bar's query: the omni full-text filter, which reaches
  // `custom_values` in both FTS tables.
  Future<List<String>> searchBar(String query) =>
      repos.dances.search(FullTextFilter(query));

  Future<String> indexedCustomValues(String danceId) async =>
      (await db
              .customSelect(
                'SELECT custom_values FROM dance_fts WHERE dance_id = ?',
                variables: [Variable<String>(danceId)],
              )
              .getSingle())
          .read<String>('custom_values');

  test('a searchable text field is found by the search bar', () async {
    await upsertDef(textField());
    await createDance('d1', [
      CustomFieldValue(fieldId: 'f-venue-note', value: 'Wobbly floorboards'),
    ]);

    expect(await searchBar('floorboards'), ['d1']);
  });

  test('a field with Searchable off is not found by the search bar', () async {
    await upsertDef(textField(searchable: false));
    await createDance('d1', [
      CustomFieldValue(fieldId: 'f-venue-note', value: 'Wobbly floorboards'),
    ]);

    expect(await searchBar('floorboards'), isEmpty);
    expect(await indexedCustomValues('d1'), isEmpty);
  });

  test('a yes/no value is not indexed as "true" or "false"', () async {
    await upsertDef(yesNoField);
    await createDance('d1', [
      CustomFieldValue(fieldId: 'f-teach', value: true),
    ]);
    await createDance('d2', [
      CustomFieldValue(fieldId: 'f-teach', value: false),
    ]);

    expect(await searchBar('true'), isEmpty);
    expect(await searchBar('false'), isEmpty);
    expect(await indexedCustomValues('d1'), isEmpty);
    // The field's own facet still finds the value.
    expect(
      await repos.dances.search(
        CustomFieldFilter(yesNoField, CustomFieldOp.is_, true),
      ),
      ['d1'],
    );
  });

  test('the bulk rebuild applies the same rule as a single write', () async {
    await upsertDef(textField(searchable: false));
    await upsertDef(yesNoField);
    await createDance('d1', [
      CustomFieldValue(fieldId: 'f-venue-note', value: 'Wobbly floorboards'),
      CustomFieldValue(fieldId: 'f-teach', value: true),
    ]);

    await repos.dances.rebuildAllDerived();

    expect(await indexedCustomValues('d1'), isEmpty);
  });

  group('switching Searchable on a local edit', () {
    test('off removes the field from the search bar at once', () async {
      await upsertDef(textField());
      await createDance('d1', [
        CustomFieldValue(fieldId: 'f-venue-note', value: 'Wobbly floorboards'),
      ]);
      expect(await searchBar('floorboards'), ['d1']);

      await upsertDef(textField(searchable: false), localUserEdit: true);

      expect(await searchBar('floorboards'), isEmpty);
    });

    test('back on restores it, trashed dances included', () async {
      await upsertDef(textField(searchable: false));
      await createDance('d1', [
        CustomFieldValue(fieldId: 'f-venue-note', value: 'Wobbly floorboards'),
      ]);
      await createDance('d2', [
        CustomFieldValue(fieldId: 'f-venue-note', value: 'Wobbly floorboards'),
      ]);
      await repos.dances.softDelete('d2', at: DateTime.utc(2026, 2, 1));

      await upsertDef(textField(), localUserEdit: true);

      expect(await searchBar('floorboards'), ['d1']);
      // A trashed dance's rows follow the rule too, as a full rebuild would
      // write them.
      expect(await indexedCustomValues('d2'), 'Wobbly floorboards');
    });
  });

  group('the one-shot repair of an index written before the rule', () {
    Future<void> clearMarker() => db.customStatement(
      'DELETE FROM settings WHERE key = ?',
      [customFieldIndexRepairDoneKey],
    );

    Future<bool> markerPresent() async =>
        (await db
                .customSelect(
                  'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',
                  variables: [Variable<String>(customFieldIndexRepairDoneKey)],
                )
                .get())
            .isNotEmpty;

    /// Leaves dance `d1` with an index row carrying [stale] in
    /// `custom_values`, as a build before the rule wrote it, and the repair
    /// marker absent, as on the first open after an upgrade.
    Future<void> seedStaleIndex(String stale) async {
      await repos.ensureMigrated();
      for (final table in const ['dance_fts', 'dance_substring_fts']) {
        await db.customStatement(
          'UPDATE $table SET custom_values = ? WHERE dance_id = ?',
          [stale, 'd1'],
        );
      }
      await clearMarker();
    }

    test('drops the values of a field with Searchable off', () async {
      await upsertDef(textField(searchable: false));
      await createDance('d1', [
        CustomFieldValue(fieldId: 'f-venue-note', value: 'Wobbly floorboards'),
      ]);
      await seedStaleIndex('Wobbly floorboards');
      expect(await searchBar('floorboards'), ['d1'], reason: 'precondition');

      await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();

      expect(await searchBar('floorboards'), isEmpty);
      expect(await markerPresent(), isTrue);
    });

    test('drops a yes/no value indexed as "true"', () async {
      await upsertDef(yesNoField);
      await createDance('d1', [
        CustomFieldValue(fieldId: 'f-teach', value: true),
      ]);
      await seedStaleIndex('true');
      expect(await searchBar('true'), ['d1'], reason: 'precondition');

      await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();

      expect(await searchBar('true'), isEmpty);
    });

    test('runs once: the marker stops a second pass', () async {
      await upsertDef(yesNoField);
      await createDance('d1', [
        CustomFieldValue(fieldId: 'f-teach', value: true),
      ]);
      await seedStaleIndex('true');
      await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();

      // Stale again, marker kept: a later open must leave the row alone.
      for (final table in const ['dance_fts', 'dance_substring_fts']) {
        await db.customStatement(
          'UPDATE $table SET custom_values = ? WHERE dance_id = ?',
          ['true', 'd1'],
        );
      }
      await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();

      expect(await indexedCustomValues('d1'), 'true');
    });
  });
}
