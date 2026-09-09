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

  test('v33 difficulty levels gain initialized sync timestamps', () async {
    final raw = sqlite3.sqlite3.openInMemory();
    addTearDown(raw.close);

    final historical = GeneratedHelper().databaseForVersion(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      33,
    );
    await historical.customSelect('SELECT 1').get();
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
  });
}
