import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repos;

  setUp(() {
    db = openTestDatabase();
    repos = CompendiumRepositories(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  test('backfill normalizes duplicate non-unique text independently', () async {
    const decomposed = 'cafe\u0301';
    await db.customStatement(
      'INSERT INTO published_sources (id, title) VALUES (?, ?)',
      ['source-1', decomposed],
    );
    await db.customStatement(
      'INSERT INTO published_sources (id, title) VALUES (?, ?)',
      ['source-2', decomposed],
    );

    await repos.ensureMigrated();

    final rows = await db
        .customSelect('SELECT title FROM published_sources ORDER BY id')
        .get();
    expect(
      [for (final row in rows) row.read<String>('title')],
      ['café', 'café'],
    );
    expect(
      await db.customSelect('SELECT 1 FROM normalisation_skips').get(),
      isEmpty,
    );
  });

  test('backfill leaves identity columns untouched', () async {
    await db.customStatement('INSERT INTO tags (id, name) VALUES (?, ?)', [
      'id\u0301',
      'tag',
    ]);
    await repos.ensureMigrated();

    final row = await db
        .customSelect('SELECT id FROM tags LIMIT 1')
        .getSingle();
    expect(row.read<String>('id'), 'id\u0301');
  });
}
