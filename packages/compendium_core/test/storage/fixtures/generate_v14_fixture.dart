// Regenerates `test/storage/fixtures/v14.sqlite` — the schema-v14 database that
// `migration_test.dart` opens through the real `onUpgrade` (v14 -> v15) path,
// which adds the additive `dances.walkthrough` column (issue #370).
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v14_fixture.dart
//
// Ordering trap (same as the v13 generator): the current code is already at
// schema v15, so opening a fresh `CompendiumDatabase` creates the v15 shape
// (with `dances.walkthrough` already present). Seeding at v15 would make the
// v14 -> v15 migration a no-op (`addColumn` would fail with "duplicate column
// name walkthrough"). So we seed realistic data at the current schema and then
// *strip back to the v14 shape* with raw SQL before stamping `user_version = 14`:
//   * ALTER TABLE dances DROP COLUMN walkthrough — remove the v15-only column
//     (SQLite >= 3.35; the bundled sqlite3 is 3.53+);
//   * PRAGMA user_version = 14.
// The v14 shape retains every earlier addition (the `venues` table +
// `programs.venue_id` from v14, etc.) — only the v15 walkthrough column is
// stripped — so the resulting file is a faithful v14 fixture: a pre-existing
// dance whose `walkthrough` must come back `''` after the upgrade.
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
    'v14.sqlite',
  );
  final file = File(fixturePath);
  if (file.existsSync()) file.deleteSync();

  final db = CompendiumDatabase(NativeDatabase(file));
  final repos = CompendiumRepositories(db, contraTaxonomy);

  final now = DateTime.utc(2026, 1, 1);
  await repos.choreographers.upsert(
    Choreographer(id: 'chor-1', name: 'Cary Ravitz'),
  );
  // A dance captured before the walkthrough field existed: its walkthrough must
  // materialise as `''` after the v14 -> v15 upgrade. `callingNotes` is seeded
  // to prove the migration leaves the neighbouring free-text column untouched.
  await repos.dances.create(
    Dance(
      id: 'dance-1',
      title: 'Ocean Motion',
      authorIds: const ['chor-1'],
      callingNotes: 'No balances in this dance.',
      figures: [
        Figure(move: 'swing', params: const {'who': 'partners', 'beats': 16}),
      ],
      createdAt: now,
      updatedAt: now,
    ),
  );

  await db.close();

  // Strip the v15-only walkthrough column and stamp the file back to v14.
  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('ALTER TABLE dances DROP COLUMN walkthrough');
  raw.execute('PRAGMA user_version = 14');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v14.');
}
