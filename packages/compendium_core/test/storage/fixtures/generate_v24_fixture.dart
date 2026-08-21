// Regenerates `test/storage/fixtures/v24.sqlite` — the schema-v24 database that
// `migration_test.dart` opens through the real `onUpgrade` (v24 -> v25) path,
// which adds the Device Sync timestamp triple to eight tables (#898).
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v24_fixture.dart
//
// The current code is at schema v25, so opening a fresh `CompendiumDatabase`
// creates the v25 shape — the twenty new columns already present. We seed at
// v25 and then strip back to the v24 shape with raw SQL before stamping:
//   * ALTER TABLE ... DROP COLUMN for each of the twenty v25-only columns
//     (SQLite >= 3.35; the bundled sqlite3 is 3.53+).
//   * PRAGMA user_version = 24.
//
// WHAT THE SEED DATA IS FOR. The v24->v25 back-fill has three distinguishable
// outcomes, and the fixture has to be able to tell them apart — a fixture of one
// live dance could not:
//
//   * `existence_at` must be ONE constant T₀, IDENTICAL across every live row.
//     Two live dances written at *different* `updated_at` values prove the
//     back-fill did not copy `updated_at` per row: if it had, these two would
//     disagree. This is the mutation the guard test exists to catch, so the two
//     stamps below are deliberately years apart.
//   * An ALREADY-SOFT-DELETED row must take its OWN `deleted_at`, not T₀. Only
//     `dances` and `programs` can exercise this: the other six tables gain
//     `deleted_at` in the same migration, so every row of theirs is live by
//     construction. Hence the tombstoned dance and the tombstoned program.
//   * `existence_at` must NOT equal `updated_at` where those differ. The live
//     dances' `updated_at` values are historical, so T₀ (sampled at migration
//     time) differs from both.
//
// The six tables that gain all three columns get one row each, so the test can
// assert `updated_at` was stamped and `existence_at` took T₀ there too — and,
// for `tags`, that the tag survives with its `dance_tags` join row intact.
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// The twenty columns schema v25 adds, as `(table, column)`.
const _v25Columns = <(String, String)>[
  ('settings', 'updated_at'),
  ('settings', 'deleted_at'),
  ('settings', 'existence_at'),
  ('choreographers', 'updated_at'),
  ('choreographers', 'deleted_at'),
  ('choreographers', 'existence_at'),
  ('tags', 'updated_at'),
  ('tags', 'deleted_at'),
  ('tags', 'existence_at'),
  ('published_sources', 'updated_at'),
  ('published_sources', 'deleted_at'),
  ('published_sources', 'existence_at'),
  ('custom_field_defs', 'updated_at'),
  ('custom_field_defs', 'deleted_at'),
  ('custom_field_defs', 'existence_at'),
  ('venues', 'updated_at'),
  ('venues', 'deleted_at'),
  ('venues', 'existence_at'),
  ('dances', 'existence_at'),
  ('programs', 'existence_at'),
];

Future<void> main() async {
  final fixturePath = p.join(
    Directory.current.path,
    'test',
    'storage',
    'fixtures',
    'v24.sqlite',
  );
  final file = File(fixturePath);
  if (file.existsSync()) file.deleteSync();

  final db = CompendiumDatabase(NativeDatabase(file));
  final repos = CompendiumRepositories(db, contraTaxonomy);

  // Two live dances whose `updated_at` values are years apart, so a per-row
  // copy of `updated_at` into `existence_at` cannot masquerade as the constant
  // T₀ the back-fill is required to write.
  final early = DateTime.utc(2020, 3, 4, 5, 6, 7);
  final late_ = DateTime.utc(2026, 1, 1);
  await repos.dances.create(
    Dance(
      id: 'dance-v24-early',
      title: 'Early Dance',
      figures: [],
      createdAt: early,
      updatedAt: early,
    ),
  );
  await repos.dances.create(
    Dance(
      id: 'dance-v24-late',
      title: 'Late Dance',
      figures: [],
      createdAt: late_,
      updatedAt: late_,
    ),
  );

  // An already-soft-deleted dance, whose `existence_at` must come out as this
  // `deleted_at` rather than T₀.
  final deletedAt = DateTime.utc(2023, 7, 8, 9, 10, 11);
  await repos.dances.create(
    Dance(
      id: 'dance-v24-deleted',
      title: 'Deleted Dance',
      figures: [],
      createdAt: early,
      updatedAt: early,
    ),
  );
  await repos.dances.softDelete('dance-v24-deleted', at: deletedAt);

  await repos.programs.create(
    Program(
      id: 'program-v24-live',
      title: 'Live Program',
      createdAt: late_,
      updatedAt: late_,
    ),
  );
  await repos.programs.create(
    Program(
      id: 'program-v24-deleted',
      title: 'Deleted Program',
      createdAt: early,
      updatedAt: early,
    ),
  );
  await repos.programs.softDelete('program-v24-deleted', at: deletedAt);

  // One row in each of the six tables that gain all three columns, plus the
  // `dance_tags` join row that must survive the tag becoming soft-deletable.
  // ignore: unused_result
  await repos.choreographers.upsert(
    Choreographer(id: 'chor-v24', name: 'Migration Author'),
  );
  // ignore: unused_result
  await repos.tags.upsert(Tag(id: 'tag-v24', name: 'Migration Tag'));
  await repos.publishedSources.upsert(
    PublishedSource(id: 'src-v24', title: 'Migration Source'),
  );
  // ignore: unused_result
  await repos.customFieldDefs.upsert(
    CustomFieldDef(
      id: 'cfd-v24',
      key: 'migration_field',
      label: 'Migration Field',
      type: CustomFieldType.text,
    ),
  );
  await repos.venues.upsert(Venue(id: 'venue-v24', name: 'Migration Hall'));
  await repos.settings.set('migration_setting', 'kept');

  // Attach the tag and the author to a live dance so the join rows exist.
  final tagged = (await repos.dances.getById('dance-v24-early'))!;
  await repos.dances.update(
    tagged.copyWith(tagIds: ['tag-v24'], authorIds: ['chor-v24']),
  );

  await db.close();

  // Strip the v25-only columns and stamp the file back to v24.
  final raw = sqlite3.sqlite3.open(fixturePath);
  for (final (table, column) in _v25Columns) {
    raw.execute('ALTER TABLE $table DROP COLUMN $column');
  }
  raw.execute('PRAGMA user_version = 24');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v24.');
}
