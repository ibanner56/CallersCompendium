// Regenerates `test/storage/fixtures/v23.sqlite` — the schema-v23 database that
// `migration_test.dart` opens through the real `onUpgrade` (v23 -> v24) path,
// which adds `dances.mixer` (#732).
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v23_fixture.dart
//
// The current code is at schema v24, so opening a fresh `CompendiumDatabase`
// creates the v24 shape — `dances.mixer` already present. We seed a dance at
// v24 and then strip back to the v23 shape with raw SQL before stamping:
//   * ALTER TABLE dances DROP COLUMN mixer  — remove the v24-only column
//     (SQLite >= 3.35; the bundled sqlite3 is 3.53+).
//   * PRAGMA user_version = 23.
//
// The seeded dance is chosen so the v23→v24 upgrade is observable: after the
// migration `mixer = 0` (DEFAULT 0) on the pre-existing row, proving the column
// was added with the correct default (a pre-v24 dance was never a mixer, and
// stays that way).
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
    'v23.sqlite',
  );
  final file = File(fixturePath);
  if (file.existsSync()) file.deleteSync();

  final db = CompendiumDatabase(NativeDatabase(file));
  final repos = CompendiumRepositories(db, contraTaxonomy);

  // Seed one dance so we can assert the mixer default after migration.
  final now = DateTime.utc(2026, 1, 1);
  await repos.dances.create(
    Dance(
      id: 'dance-v23',
      title: 'Migration Test Dance',
      figures: [],
      createdAt: now,
      updatedAt: now,
    ),
  );

  await db.close();

  // Strip the v24-only column and stamp the file back to v23.
  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('ALTER TABLE dances DROP COLUMN mixer');
  raw.execute('PRAGMA user_version = 23');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v23.');
}
