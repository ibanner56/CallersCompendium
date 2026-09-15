// Regenerates `test/storage/fixtures/v31.sqlite`, the schema-v31 database
// used to exercise the v31 -> v32 sync-local migration.
//
// Run from the package root:
//
//     fvm dart run test/storage/fixtures/generate_v31_fixture.dart
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
    'v31.sqlite',
  );
  final fixture = File(fixturePath);
  if (fixture.existsSync()) fixture.deleteSync();

  final db = CompendiumDatabase(NativeDatabase(fixture));
  await db.customStatement(
    'INSERT INTO settings (key, value_json) VALUES (?, ?)',
    ['v31_sync_migration_sentinel', '"present"'],
  );
  await db.close();

  final raw = sqlite3.sqlite3.open(fixturePath);
  for (final table in const [
    'baseline_state',
    'baseline_entries',
    'id_aliases',
    'pending_deletions',
    'review_queue',
    'published_records',
  ]) {
    raw.execute('DROP TABLE $table');
  }
  raw.execute('PRAGMA user_version = 31');
  raw.close();
  stdout.writeln('Wrote $fixturePath at schema v31.');
}
