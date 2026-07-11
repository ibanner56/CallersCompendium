// Regenerates `test/storage/fixtures/v1.sqlite` — the schema-v1 database that
// `migration_test.dart` opens through the real `onUpgrade` path.
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v1_fixture.dart
//
// Strategy: seed a fresh database at the *current* schema through the
// repositories (so the data is realistic and internally consistent), then
// strip the v2 additions back off with raw SQLite — drop the
// `dance_figures.section` column and the two v2 indexes, and reset
// `user_version` to 1. The result is byte-for-byte a schema-v1 database
// (identical to what the v1 `onCreate` produced) seeded with two dances whose
// figures span phrase sections, an author, a tag, and a custom-field value.
//
// The migration test then opens it, drift observes `user_version` 1 < 2 and
// runs `onUpgrade`, and the post-open integrity pass back-fills `section`.
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
    'v1.sqlite',
  );
  final file = File(fixturePath);
  if (file.existsSync()) file.deleteSync();

  final db = CompendiumDatabase(NativeDatabase(file));
  final repos = CompendiumRepositories(db, contraTaxonomy);

  final now = DateTime.utc(2026, 1, 1);
  await repos.choreographers.upsert(Choreographer(id: 'auth-1', name: 'Alice'));
  await repos.tags.upsert(Tag(id: 'tag-1', name: 'chestnut'));
  await repos.customFieldDefs.upsert(
    CustomFieldDef(
      id: 'cf-1',
      key: 'origin',
      label: 'Origin',
      type: CustomFieldType.text,
    ),
  );

  // Standard 4x16 structure: figures land A1@0, A2@16, B1@32, B2@48.
  await repos.dances.create(
    Dance(
      id: 'dance-1',
      title: 'Petronella Reel',
      authorIds: ['auth-1'],
      tagIds: ['tag-1'],
      customFields: [CustomFieldValue(fieldId: 'cf-1', value: 'New England')],
      figures: [
        Figure(move: 'petronella', params: const {'beats': 16}), // A1
        Figure(move: 'swing', params: const {'who': 'partners', 'beats': 16}),
        Figure(move: 'balance', params: const {'beats': 16}), // B1
        Figure(move: 'long_lines', params: const {'beats': 16}), // B2
      ],
      createdAt: now,
      updatedAt: now,
    ),
  );
  await repos.dances.create(
    Dance(
      id: 'dance-2',
      title: 'Simple Circle',
      figures: [
        Figure(move: 'do_si_do', params: const {'beats': 8}),
      ],
      createdAt: now,
      updatedAt: now,
    ),
  );

  await db.close();

  // Strip the v2 additions so the fixture is a genuine schema-v1 database.
  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('DROP INDEX IF EXISTS dance_figures_move_section');
  raw.execute('DROP INDEX IF EXISTS dance_figures_dance_idx');
  raw.execute('ALTER TABLE dance_figures DROP COLUMN section');
  raw.execute('PRAGMA user_version = 1');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v1.');
}
