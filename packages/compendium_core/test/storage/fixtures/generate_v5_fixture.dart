// Regenerates `test/storage/fixtures/v5.sqlite` — the schema-v5 database that
// `migration_test.dart` opens through the real `onUpgrade` (v5 -> v6) path.
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v5_fixture.dart
//
// Strategy (mirrors `generate_v4_fixture.dart`): seed a fresh database at the
// *current* schema through the repositories (so the data is realistic and
// internally consistent), then strip the v6 addition back off with raw
// SQLite — drop the CC-parity `rating` column — and reset `user_version` to 5.
// The result is byte-for-byte a schema-v5 database seeded with a dance (with
// level + composed/revised dates) plus a program, so the migration test can
// assert those rows survive and the new `dances.rating` column defaults to
// NULL.
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
    'v5.sqlite',
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
      level: DanceLevel.intermediate,
      composedOn: PartialDate(1989),
      revisedOn: PartialDate(2004, 3),
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

  // Strip the v6 addition so the fixture is a genuine schema-v5 database.
  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('ALTER TABLE dances DROP COLUMN rating');
  raw.execute('PRAGMA user_version = 5');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v5.');
}
