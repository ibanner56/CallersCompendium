// Regenerates `test/storage/fixtures/v12.sqlite` — the schema-v12 database that
// `migration_test.dart` opens through the real `onUpgrade` (v12 -> v13) path,
// which adds the `venues` table and the `programs.venue_id` column.
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v12_fixture.dart
//
// Ordering trap: the current code is already at schema v13, so opening a fresh
// `CompendiumDatabase` creates the v13 shape (with `venues` + `programs.venue_id`
// already present). Seeding at v13 would make the v12 -> v13 migration a no-op
// (or make `createTable(venues)` fail with "table venues already exists"). So we
// seed realistic data at the current schema and then *strip back to the v12
// shape* with raw SQL before stamping `user_version = 12`:
//   * DROP TABLE venues            — remove the v13-only table;
//   * ALTER TABLE programs DROP COLUMN venue_id  — remove the v13-only column
//     (SQLite >= 3.35; the bundled sqlite3 is 3.53+);
//   * PRAGMA user_version = 12.
// v11 and v12 are structurally identical (v12 only rewrote `figures_json`
// content), so the resulting file is a valid v12 fixture: NO `venues` table, NO
// `programs.venue_id`, and a pre-existing program whose `venue_id` must come
// back null after the upgrade.
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
    'v12.sqlite',
  );
  final file = File(fixturePath);
  if (file.existsSync()) file.deleteSync();

  final db = CompendiumDatabase(NativeDatabase(file));
  final repos = CompendiumRepositories(db, contraTaxonomy);

  final now = DateTime.utc(2026, 1, 1);
  await repos.choreographers.upsert(
    Choreographer(id: 'chor-1', name: 'Cary Ravitz'),
  );
  await repos.dances.create(
    Dance(
      id: 'dance-1',
      title: 'Ocean Motion',
      authorIds: const ['chor-1'],
      figures: [
        Figure(move: 'swing', params: const {'who': 'partners', 'beats': 16}),
      ],
      createdAt: now,
      updatedAt: now,
    ),
  );
  // A program captured before the venue entity existed: its reference to a
  // venue must materialise as a null `venueId` after the v12 -> v13 upgrade.
  await repos.programs.create(
    Program(
      id: 'prog-1',
      title: 'Second Saturday Contra',
      eventDate: DateTime.utc(2026, 3, 14),
      venue: 'Guiding Star Grange',
      slots: [ProgramSlot(id: 'slot-1', position: 0, danceId: 'dance-1')],
      createdAt: now,
      updatedAt: now,
    ),
  );

  await db.close();

  // Strip the v13-only additions and stamp the file back to v12.
  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('DROP TABLE IF EXISTS venues');
  raw.execute('ALTER TABLE programs DROP COLUMN venue_id');
  raw.execute('PRAGMA user_version = 12');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v12.');
}
