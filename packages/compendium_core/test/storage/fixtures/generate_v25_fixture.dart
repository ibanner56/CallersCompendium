// Regenerates `test/storage/fixtures/v25.sqlite` — the schema-v25 database that
// `migration_test.dart` opens through the real `onUpgrade` (v25 -> v26) path,
// which adds the `venue_provenance` table (issue #899).
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v25_fixture.dart
//
// The current code is at schema v26, so opening a fresh `CompendiumDatabase`
// creates the v26 shape — the `venue_provenance` table already present. We seed
// at v26 and then strip back to the v25 shape with raw SQL before stamping:
//   * DROP TABLE venue_provenance
//   * PRAGMA user_version = 25.
//
// WHAT THE SEED DATA IS FOR. The v25->v26 migration is purely additive (a new
// `venue_provenance` table, no data back-fill), so the fixture just needs a live
// venue so the test can confirm existing data survives the migration intact.
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
    'v25.sqlite',
  );
  final file = File(fixturePath);
  if (file.existsSync()) file.deleteSync();

  final db = CompendiumDatabase(NativeDatabase(file));
  final repos = CompendiumRepositories(db, contraTaxonomy);

  // One live venue so the migration test can confirm it survives intact.
  await repos.venues.upsert(Venue(id: 'venue-v25', name: 'Migration Hall v25'));

  await db.close();

  // Drop the v26-only table and stamp the file back to v25.
  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('DROP TABLE IF EXISTS venue_provenance');
  raw.execute('PRAGMA user_version = 25');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v25.');
}
