import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  group('CompendiumDatabase schema', () {
    test('onCreate builds every table and the FTS5 index', () async {
      final db = openTestDatabase();
      addTearDown(db.close);

      final tableNames = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '%_fts_%'",
          )
          .get();
      final names = tableNames.map((r) => r.read<String>('name')).toSet();
      expect(
        names,
        containsAll(<String>{
          'dances',
          'choreographers',
          'dance_authors',
          'dance_figures',
          'programs',
          'program_slots',
          'custom_field_defs',
          'custom_field_values',
          'tags',
          'dance_tags',
          'dance_links',
          'provenance',
          'settings',
          'dance_fts',
        }),
      );

      // A fresh database must NOT create the storage removed at v21 (#781,
      // #782) — `containsAll` above would pass whether or not they exist, so
      // the negative is asserted explicitly. This catches a reintroduction via
      // `createAll()` that the migration path alone would not.
      expect(names, isNot(contains('snapshots')));
    });

    test('foreign keys are enforced', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final fkRows = await db.customSelect('PRAGMA foreign_keys').get();
      expect(fkRows.single.data.values.first, 1);
    });

    test('quickCheck reports ok on a fresh database', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      expect(await db.quickCheck(), isTrue);
    });
  });
}
