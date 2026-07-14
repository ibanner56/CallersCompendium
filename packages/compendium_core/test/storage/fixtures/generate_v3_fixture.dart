// Regenerates `test/storage/fixtures/v3.sqlite` — the schema-v3 database that
// `migration_test.dart` opens through the real `onUpgrade` (v3 -> v4) path.
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v3_fixture.dart
//
// Strategy (mirrors `generate_v2_fixture.dart`): seed a fresh database at the
// *current* schema through the repositories (so the data is realistic and
// internally consistent), then strip the v4 additions back off with raw
// SQLite — drop the two CC-parity dance difficulty columns — and reset
// `user_version` to 3. The result is byte-for-byte a schema-v3 database seeded
// with a dance plus a program, so the migration test can assert those rows
// survive and the new `dances.level` / `dances.mixed_level` columns default to
// NULL / false.
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
    'v3.sqlite',
  );
  final file = File(fixturePath);
  if (file.existsSync()) file.deleteSync();

  final db = CompendiumDatabase(NativeDatabase(file));
  final repos = CompendiumRepositories(db, contraTaxonomy);

  final now = DateTime.utc(2026, 1, 1);
  await repos.dances.create(
    Dance(
      id: 'dance-1',
      title: 'Petronella Reel',
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
      title: 'Spring Dance 2026',
      eventDate: DateTime.utc(2026, 3, 15),
      venue: 'Grange Hall',
      notes: 'A lovely night',
      slots: [
        ProgramSlot(id: 'slot-1', position: 0, danceId: 'dance-1'),
        ProgramSlot(
          id: 'slot-2',
          position: 1,
          text: 'Waltz break',
          isAlt: true,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    ),
  );

  await db.close();

  // Strip the v4 additions so the fixture is a genuine schema-v3 database.
  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('ALTER TABLE dances DROP COLUMN level');
  raw.execute('ALTER TABLE dances DROP COLUMN mixed_level');
  raw.execute('PRAGMA user_version = 3');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v3.');
}
