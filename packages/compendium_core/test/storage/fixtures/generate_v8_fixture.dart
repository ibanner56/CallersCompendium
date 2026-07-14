// Regenerates `test/storage/fixtures/v8.sqlite` — the schema-v8 database that
// `migration_test.dart` opens through the real `onUpgrade` (v8 -> v9) path.
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v8_fixture.dart
//
// Strategy (mirrors `generate_v7_fixture.dart`): seed a fresh database at the
// *current* schema through the repositories (so the data is realistic and
// internally consistent), then strip the v9 additions back off with raw
// SQLite and reset `user_version` to 8. The v9 change is purely the shape of
// the derived `dance_fts` table (it gains a `sources` column), so the strip
// step rebuilds `dance_fts` with the schema-v8 column set — copying the seven
// pre-v9 columns across — and leaves the (v8) `published_sources` /
// `dance_sources` tables and their rows intact. The result is byte-for-byte a
// schema-v8 database seeded with a choreographer, a published source, and a
// dance that CITES that source (but whose FTS row does NOT yet index the
// source), so the migration test can assert the v9 rebuild makes the dance
// findable by its source's title.
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

Future<void> main() async {
  final fixturePath = p.join(
    Directory.current.path,
    'test',
    'storage',
    'fixtures',
    'v8.sqlite',
  );
  final file = File(fixturePath);
  if (file.existsSync()) file.deleteSync();

  final db = CompendiumDatabase(NativeDatabase(file));
  final repos = CompendiumRepositories(db, contraTaxonomy);

  final now = DateTime.utc(2026, 1, 1);
  await repos.choreographers.upsert(
    Choreographer(
      id: 'chor-1',
      name: 'Cary Ravitz',
      website: 'https://ravitz.us',
      notes: 'prolific author',
    ),
  );

  await repos.publishedSources.upsert(
    PublishedSource(
      id: 'src-1',
      title: 'Zesty Contras',
      author: 'Larry Jennings',
      year: 1983,
    ),
  );

  await repos.dances.create(
    Dance(
      id: 'dance-1',
      title: 'Petronella Reel',
      authorIds: const ['chor-1'],
      level: DanceLevel.intermediate,
      rating: 4,
      composedOn: PartialDate(1989),
      figures: [
        Figure(move: 'petronella', params: const {'beats': 16}),
      ],
      sourceCitations: [SourceCitation(sourceId: 'src-1', page: '42')],
      createdAt: now,
      updatedAt: now,
    ),
  );

  await db.close();

  // Strip the v9 addition (the `dance_fts.sources` column) so the fixture is a
  // genuine schema-v8 database: rebuild `dance_fts` with the pre-v9 column set,
  // copying the seven columns across, then reset `user_version` to 8. The
  // seeded FTS row therefore does NOT index the cited source — the v8->v9
  // migration's derived rebuild is what makes it searchable.
  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('''
CREATE VIRTUAL TABLE dance_fts_v8 USING fts5(
  dance_id UNINDEXED,
  title, authors, hook, notes, figures_text, custom_values
)
''');
  raw.execute(
    'INSERT INTO dance_fts_v8'
    '(dance_id, title, authors, hook, notes, figures_text, custom_values) '
    'SELECT dance_id, title, authors, hook, notes, figures_text, custom_values '
    'FROM dance_fts',
  );
  raw.execute('DROP TABLE dance_fts');
  raw.execute('ALTER TABLE dance_fts_v8 RENAME TO dance_fts');
  raw.execute('PRAGMA user_version = 8');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v8.');
}
