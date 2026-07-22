// Regenerates `test/storage/fixtures/v12.sqlite` — the schema-v12 database that
// `migration_test.dart` opens through the real `onUpgrade` (v12 -> v13) path.
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v12_fixture.dart
//
// Strategy (mirrors `generate_v13_fixture.dart`): the current code is already at
// schema v14, so opening a fresh `CompendiumDatabase` creates the v14 shape (with
// the `venues` table, the `programs.venue_id` column, and both the
// `programs_venue_id` and `dance_links_dance_id` indexes). Seeding at v14 and only
// rewinding `user_version` would leave those v13/v14 additions behind, so we seed
// realistic data at the current schema and then *strip back to the v12 shape* with
// raw SQL before stamping `user_version = 12`:
//   * DROP TABLE venues            — remove the v14-only table;
//   * DROP INDEX programs_venue_id — remove the v14-only lookup index, which must
//     go before the DROP COLUMN below (SQLite refuses to drop a column an index
//     still references);
//   * ALTER TABLE programs DROP COLUMN venue_id  — remove the v14-only column
//     (SQLite >= 3.35; the bundled sqlite3 is 3.53+);
//   * DROP INDEX dance_links_dance_id — remove the v13-only index (#455);
//   * PRAGMA user_version = 12.
// The result is a faithful v12 database: NO `venues` table, NO `programs.venue_id`,
// and neither the `programs_venue_id` nor the `dance_links_dance_id` index.
//
// The seeded dance carries a video `DanceLink`, so the fixture exercises the
// exact access path the new index accelerates: a `dance_links` row whose
// `dance_id` is looked up by the batched link loader.
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
    'v12.sqlite',
  );
  final file = File(fixturePath);
  if (file.existsSync()) file.deleteSync();

  final db = CompendiumDatabase(NativeDatabase(file));
  final repos = CompendiumRepositories(db, contraTaxonomy);

  final now = DateTime.utc(2026, 1, 1);
  await repos.choreographers.upsert(
    Choreographer(id: 'chor-1', name: 'Cary Ravitz'),
  );

  // A dance WITH a link — the row the v13 index accelerates.
  await repos.dances.create(
    Dance(
      id: 'dance-1',
      title: 'Ocean Motion',
      authorIds: const ['chor-1'],
      figures: [
        Figure(move: 'swing', params: const {'who': 'partners', 'beats': 16}),
      ],
      links: [
        DanceLink(
          id: 'link-1',
          kind: LinkKind.video,
          url: 'https://example.test/ocean-motion',
          label: 'Video',
        ),
      ],
      createdAt: now,
      updatedAt: now,
    ),
  );

  // A dance WITHOUT a link — proves link-less dances survive the migration.
  await repos.dances.create(
    Dance(
      id: 'dance-2',
      title: 'Plain Reel',
      authorIds: const ['chor-1'],
      figures: [
        Figure(move: 'swing', params: const {'who': 'neighbors', 'beats': 16}),
      ],
      createdAt: now,
      updatedAt: now,
    ),
  );

  await db.close();

  // Strip the v13 + v14 additions and stamp the file back to v12 so the fixture
  // is a faithful v12 database (none of the later structural changes present).
  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('DROP TABLE IF EXISTS venues');
  // Drop the v14-only lookup index first: SQLite refuses to DROP COLUMN while an
  // index still references it.
  raw.execute('DROP INDEX IF EXISTS programs_venue_id');
  raw.execute('ALTER TABLE programs DROP COLUMN venue_id');
  raw.execute('DROP INDEX IF EXISTS dance_links_dance_id');
  raw.execute('PRAGMA user_version = 12');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v12.');
}
