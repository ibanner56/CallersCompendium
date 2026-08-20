// Regenerates `test/storage/fixtures/v26.sqlite` — the schema-v26 database
// that `migration_test.dart` opens through the real v26 -> v27 path, which
// adds `collection_import_events` (issue #862).
//
// Run from the package root:
//
//     fvm dart run test/storage/fixtures/generate_v26_fixture.dart
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
    'v26.sqlite',
  );
  final file = File(fixturePath);
  if (file.existsSync()) file.deleteSync();

  final db = CompendiumDatabase(NativeDatabase(file));
  await db.customSelect('SELECT 1').get();
  await db.close();

  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('DROP TABLE IF EXISTS collection_import_events');
  raw.execute('PRAGMA user_version = 26');
  raw.close();
  stdout.writeln('Wrote $fixturePath at schema v26.');
}
