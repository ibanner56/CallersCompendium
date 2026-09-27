import 'package:compendium_core/src/storage/database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

import 'generated/schema.dart';

void main() {
  test('v32 level names migrate to seeded stable IDs', () async {
    final raw = sqlite3.sqlite3.openInMemory();
    addTearDown(raw.close);

    final historical = GeneratedHelper().databaseForVersion(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      32,
    );
    await historical.customSelect('SELECT 1').get();
    for (final (id, level) in const [
      ('old-beginner', 'beginner'),
      ('old-intermediate', 'intermediate'),
      ('old-advanced', 'advanced'),
      ('old-unspecified', null),
    ]) {
      await historical.customStatement(
        'INSERT INTO dances '
        '(id, title, form, formation_shape, progression, status, '
        'created_at, updated_at, level) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, id, 'contra', 'dupleImproper', 'single', 'active', 0, 0, level],
      );
    }
    await historical.close();

    final migrated = CompendiumDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    addTearDown(migrated.close);
    await migrated.customSelect('SELECT 1').get();

    final levels = await migrated
        .customSelect(
          'SELECT id, label, position FROM difficulty_levels ORDER BY position',
        )
        .get();
    expect(
      [
        for (final row in levels)
          (
            row.read<String>('id'),
            row.read<String>('label'),
            row.read<int>('position'),
          ),
      ],
      [
        ('difficulty-beginner', 'Beginner', 0),
        ('difficulty-intermediate', 'Intermediate', 1),
        ('difficulty-advanced', 'Advanced', 2),
      ],
    );

    final migratedLevels = await migrated
        .customSelect('SELECT id, level_id FROM dances ORDER BY id')
        .get();
    expect(
      [
        for (final row in migratedLevels)
          (row.read<String>('id'), row.read<String?>('level_id')),
      ],
      [
        ('old-advanced', 'difficulty-advanced'),
        ('old-beginner', 'difficulty-beginner'),
        ('old-intermediate', 'difficulty-intermediate'),
        ('old-unspecified', null),
      ],
    );
  });

  test('legacy difficulty levels gain initialized sync timestamps, and a '
      'pre-existing difficulty_levels table does not skip the dances '
      'rewrite', () async {
    final raw = sqlite3.sqlite3.openInMemory();
    addTearDown(raw.close);

    // A v33 file whose `difficulty_levels` table already exists — the state a
    // crash between the v34 step's `createTable` and its `alterTable(dances)`
    // used to leave behind, before `onUpgrade` ran inside a transaction. The
    // v34 step must still rewrite `dances.level` into `level_id`: gating that
    // rewrite on the table's absence stamped such a file at head with the
    // legacy column intact, and every `dances` query failed from then on.
    final historical = GeneratedHelper().databaseForVersion(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      33,
    );
    await historical.customSelect('SELECT 1').get();
    await historical.customStatement(
      'INSERT INTO dances '
      '(id, title, form, formation_shape, progression, status, '
      'created_at, updated_at, level) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'd1',
        'd1',
        'contra',
        'dupleImproper',
        'single',
        'active',
        0,
        0,
        'beginner',
      ],
    );
    await historical.customStatement('''
      CREATE TABLE difficulty_levels (
        id TEXT NOT NULL,
        label TEXT NOT NULL UNIQUE,
        position INTEGER NOT NULL,
        PRIMARY KEY (id)
      )
    ''');
    await historical.customStatement(
      'INSERT INTO difficulty_levels (id, label, position) VALUES (?, ?, ?)',
      ['custom-level', 'Challenge', 3],
    );
    await historical.close();

    final migrated = CompendiumDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    addTearDown(migrated.close);
    await migrated.customSelect('SELECT 1').get();

    final row = await migrated
        .customSelect(
          'SELECT updated_at, deleted_at, existence_at '
          'FROM difficulty_levels WHERE id = ?',
          variables: [Variable.withString('custom-level')],
        )
        .getSingle();
    expect(row.read<int>('updated_at'), greaterThan(0));
    expect(row.read<int?>('deleted_at'), isNull);
    expect(row.read<int>('existence_at'), row.read<int>('updated_at'));

    final danceColumns = {
      for (final column
          in await migrated
              .customSelect("SELECT name FROM pragma_table_info('dances')")
              .get())
        column.read<String>('name'),
    };
    expect(
      danceColumns,
      contains('level_id'),
      reason: 'the v34 rewrite must run even when difficulty_levels exists',
    );
    expect(danceColumns, isNot(contains('level')));
    final dance = await migrated
        .customSelect(
          'SELECT level_id FROM dances WHERE id = ?',
          variables: [Variable.withString('d1')],
        )
        .getSingle();
    expect(dance.read<String?>('level_id'), 'difficulty-beginner');
    // The shipped vocabulary is seeded alongside the pre-existing row.
    final ids = await migrated
        .customSelect('SELECT id FROM difficulty_levels ORDER BY position')
        .get();
    expect(
      [for (final row in ids) row.read<String>('id')],
      [
        'difficulty-beginner',
        'difficulty-intermediate',
        'difficulty-advanced',
        'custom-level',
      ],
    );
  });
}
