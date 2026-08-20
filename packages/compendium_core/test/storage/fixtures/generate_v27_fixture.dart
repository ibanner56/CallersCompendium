// Regenerates `test/storage/fixtures/v27.sqlite` — the schema-v27 database
// that `migration_test.dart` opens through the real v27 -> v28 path.
//
// Run from the package root:
//
//     fvm dart run test/storage/fixtures/generate_v27_fixture.dart
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
    'v27.sqlite',
  );
  final fixture = File(fixturePath);
  if (fixture.existsSync()) fixture.deleteSync();

  final db = CompendiumDatabase(NativeDatabase(fixture));
  final dances = DanceRepository(db, contraTaxonomy);
  await dances.create(
    Dance(
      id: 'dance-1',
      title: 'Fixture Dance',
      figures: [
        Figure(move: 'swing', params: const {'beats': 16}),
      ],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
  );
  await db.close();

  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('DROP TABLE dance_substring_fts');
  raw.execute('PRAGMA user_version = 27');
  raw.close();
  stdout.writeln('Wrote $fixturePath at schema v27.');
}
