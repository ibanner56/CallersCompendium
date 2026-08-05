// Writes a freshly-created [CompendiumDatabase] to a file so that
// `drift_dev schema dump` can capture the *current* schema as a drift schema
// dump (`drift_schemas/generated/drift_schema_v<head>.json`).
//
// Run from the package root:
//
//     dart run tool/write_head_database.dart <output-path>
//
// Why a real database file rather than dumping the Dart source
// (`drift_dev schema dump lib/src/storage/database.dart …`), which is drift's
// more usual invocation:
//
//   * A source dump captures only drift-*managed* entities. Five entities in
//     this schema are created by raw `customStatement` DDL in `onCreate` — the
//     `dance_fts` FTS5 virtual table and the four lookup indices
//     (`dance_figures_move_section`, `dance_links_dance_id`,
//     `programs_venue_id`, `program_slots_dance_id`) — so a source dump omits
//     exactly the entities that are maintained by hand in two places and are
//     therefore the likeliest to diverge.
//   * The historical dumps are taken from the committed `test/storage/fixtures/
//     v*.sqlite` databases, which *do* contain those five. Dumping head the
//     same way keeps every dump in `drift_schemas/generated/` homogeneous; a
//     source-dumped head would be the one file in the set with a different
//     meaning.
//   * Running `drift_dev` against Dart source requires it to resolve this
//     package, and the workspace cannot currently resolve a `drift_dev` new
//     enough to run at all (see `drift_schemas/README.md`). Dumping a database
//     file needs no analysis of our sources, so it works from an isolated
//     project.
//
// The database is created and immediately closed: `onCreate` alone establishes
// the schema, and no rows are inserted, because a schema dump reads structure
// only.
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/write_head_database.dart <output>');
    exitCode = 2;
    return;
  }

  final file = File(args.single);
  if (file.existsSync()) file.deleteSync();
  file.parent.createSync(recursive: true);

  // Opening runs `onCreate` (plus `beforeOpen`), which is what establishes the
  // full head schema including the raw-SQL entities.
  final db = CompendiumDatabase(NativeDatabase(file));
  await db.customSelect('SELECT 1').get();

  final stamped = await db
      .customSelect('PRAGMA user_version')
      .map((row) => row.read<int>('user_version'))
      .getSingle();
  await db.close();

  if (stamped != kCompendiumSchemaVersion) {
    stderr.writeln(
      'refusing to write $file: a freshly created database stamped '
      'user_version=$stamped, but kCompendiumSchemaVersion is '
      '$kCompendiumSchemaVersion',
    );
    file.deleteSync();
    exitCode = 1;
    return;
  }

  stdout.writeln('Wrote ${file.path} at schema v$stamped.');
}
