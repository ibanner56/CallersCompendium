// Regenerates `test/storage/fixtures/v9.sqlite` — the schema-v9 database that
// `migration_test.dart` opens through the real `onUpgrade` (v9 -> v10) path.
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v9_fixture.dart
//
// Strategy (mirrors `generate_v8_fixture.dart`): seed a fresh database at the
// *current* schema through the repositories (so the data is realistic and
// internally consistent), then strip the v10 addition back off with raw SQLite
// and reset `user_version` to 9. The v10 change is purely additive — a new
// `program_provenance` table — so the strip step drops that table and leaves a
// schema-v9 database seeded with a choreographer, a dance, and a **program**
// (with a slot referencing the dance). The program has no provenance row, so
// the migration test can assert existing programs survive the v9->v10 upgrade
// with null provenance and that the new `program_provenance` table exists.
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
    'v9.sqlite',
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
      title: 'Petronella Reel',
      authorIds: const ['chor-1'],
      figures: [
        Figure(move: 'petronella', params: const {'beats': 16}),
      ],
      createdAt: now,
      updatedAt: now,
    ),
  );

  await repos.programs.create(
    Program(
      id: 'prog-1',
      title: 'Spring Contra 2026',
      venue: 'Grange Hall',
      slots: [
        ProgramSlot(id: 'slot-1', position: 0, danceId: 'dance-1'),
        ProgramSlot(id: 'slot-2', position: 1, text: 'Waltz break'),
      ],
      createdAt: now,
      updatedAt: now,
    ),
  );

  await db.close();

  // Strip the v10 addition (the `program_provenance` table) so the fixture is a
  // genuine schema-v9 database, then reset `user_version` to 9. The v9->v10
  // migration recreates the table via `m.createTable`.
  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('DROP TABLE IF EXISTS program_provenance');
  raw.execute('PRAGMA user_version = 9');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v9.');
}
