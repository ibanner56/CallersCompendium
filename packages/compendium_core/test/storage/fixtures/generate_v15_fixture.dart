// Regenerates `test/storage/fixtures/v15.sqlite` — the schema-v15 database that
// `migration_test.dart` opens through the real `onUpgrade` (v15 -> v16) path,
// which adds the `program_slots_dance_id` index (issue #627).
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v15_fixture.dart
//
// Ordering trap (same as the v13 generator): the current code is already at
// schema v16, so opening a fresh `CompendiumDatabase` creates the v16 shape
// (with `program_slots_dance_id` already present). Seeding at v16 would make
// the v15 -> v16 migration a no-op. So we seed realistic data at the current
// schema and then *strip back to the v15 shape* with raw SQL before stamping
// `user_version = 15`:
//   * DROP INDEX IF EXISTS program_slots_dance_id — remove the v16-only index
//     (index-only migration, so no column/table drop is needed);
//   * PRAGMA user_version = 15.
// The v15 shape retains every earlier addition (the `venues` table,
// `programs.venue_id`, `dances.walkthrough`, etc.) — only the v16
// `program_slots_dance_id` index is stripped — so the resulting file is a
// faithful v15 fixture: a pre-existing program slot referencing a dance,
// whose `dance_id` lookups must full-scan until the upgrade creates the index.
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
    'v15.sqlite',
  );
  final file = File(fixturePath);
  if (file.existsSync()) file.deleteSync();

  final db = CompendiumDatabase(NativeDatabase(file));
  final repos = CompendiumRepositories(db, contraTaxonomy);

  final now = DateTime.utc(2026, 1, 1);
  // ignore: unused_result
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
  // A program captured before the program_slots.dance_id index existed: its
  // slot's dance_id lookup must full-scan pre-upgrade and index-seek after.
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

  // Strip the v16-only index and stamp the file back to v15.
  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('DROP INDEX IF EXISTS program_slots_dance_id');
  raw.execute('PRAGMA user_version = 15');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v15.');
}
