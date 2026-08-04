// Regenerates `test/storage/fixtures/v22.sqlite` — the schema-v22 database that
// `migration_test.dart` opens through the real `onUpgrade` (v22 -> v23) path,
// which adds `custom_field_defs.shareable` (#780).
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v22_fixture.dart
//
// The current code is at schema v23, so opening a fresh `CompendiumDatabase`
// creates the v23 shape — `custom_field_defs.shareable` already present.
// We seed a custom field at v23 and then strip back to the v22 shape with raw
// SQL before stamping:
//   * ALTER TABLE custom_field_defs DROP COLUMN shareable  — remove the
//     v23-only column (SQLite >= 3.35; the bundled sqlite3 is 3.53+).
//   * PRAGMA user_version = 22.
//
// The seeded custom field is chosen so the v22→v23 upgrade is observable:
// after the migration `shareable = 1` (DEFAULT 1) on the pre-existing row,
// proving the column was added with the correct default.
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
    'v22.sqlite',
  );
  final file = File(fixturePath);
  if (file.existsSync()) file.deleteSync();

  final db = CompendiumDatabase(NativeDatabase(file));
  final repos = CompendiumRepositories(db, contraTaxonomy);

  // Seed one custom field so we can assert the default after migration.
  await repos.customFieldDefs.upsert(
    CustomFieldDef(
      id: 'cf-notes',
      key: 'notes',
      label: 'Session notes',
      type: CustomFieldType.text,
      showInList: false,
      searchable: true,
    ),
  );

  // Also seed a dance with a value for the field, to verify values are
  // unaffected by the schema migration.
  final now = DateTime.utc(2026, 1, 1);
  await repos.dances.create(
    Dance(
      id: 'dance-v22',
      title: 'Migration Test Dance',
      figures: [],
      customFields: [CustomFieldValue(fieldId: 'cf-notes', value: 'good fun')],
      createdAt: now,
      updatedAt: now,
    ),
  );

  await db.close();

  // Strip the v23-only column and stamp the file back to v22.
  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('ALTER TABLE custom_field_defs DROP COLUMN shareable');
  raw.execute('PRAGMA user_version = 22');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v22.');
}
