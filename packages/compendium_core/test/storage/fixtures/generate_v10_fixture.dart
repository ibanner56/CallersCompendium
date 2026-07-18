// Regenerates `test/storage/fixtures/v10.sqlite` — the schema-v10 database that
// `migration_test.dart` opens through the real `onUpgrade` (v10 -> v11) path.
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v10_fixture.dart
//
// Strategy (mirrors `generate_v9_fixture.dart`): seed a fresh database at the
// *current* schema through the repositories (so the data is realistic and
// internally consistent), then strip the v11 addition back off with raw SQLite
// and reset `user_version` to 10. The v11 change is purely additive — a new
// `hide_alternates` column on `programs` — so the strip step drops that column
// and leaves a schema-v10 database seeded with a choreographer, a dance, and a
// **program** with a primary slot and a trailing ALT slot. The program predates
// the flag, so the migration test can assert existing programs survive the
// v10->v11 upgrade with `hideAlternates` defaulting to false and that the new
// column exists.
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
    'v10.sqlite',
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
        ProgramSlot(
          id: 'slot-2',
          position: 1,
          text: 'Backup reel',
          isAlt: true,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    ),
  );

  await db.close();

  // Strip the v11 addition (the `hide_alternates` column on `programs`) so the
  // fixture is a genuine schema-v10 database, then reset `user_version` to 10.
  // The v10->v11 migration re-adds the column via `m.addColumn`.
  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('ALTER TABLE programs DROP COLUMN hide_alternates');
  raw.execute('PRAGMA user_version = 10');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v10.');
}
