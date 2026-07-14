// Regenerates `test/storage/fixtures/v7.sqlite` — the schema-v7 database that
// `migration_test.dart` opens through the real `onUpgrade` (v7 -> v8) path.
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v7_fixture.dart
//
// Strategy (mirrors `generate_v6_fixture.dart`): seed a fresh database at the
// *current* schema through the repositories (so the data is realistic and
// internally consistent), then strip the v8 additions back off with raw
// SQLite — drop the brand-new `published_sources` / `dance_sources` tables —
// and reset `user_version` to 7. The result is byte-for-byte a schema-v7
// database seeded with a choreographer, a dance, and a program, so the
// migration test can assert those rows survive and the new published-source
// tables are created by the migration.
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
    'v7.sqlite',
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

  // Strip the v8 additions so the fixture is a genuine schema-v7 database.
  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('DROP TABLE dance_sources');
  raw.execute('DROP TABLE published_sources');
  raw.execute('PRAGMA user_version = 7');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v7.');
}
