// Regenerates `test/storage/fixtures/v21.sqlite` — the schema-v21 database that
// `migration_test.dart` opens through the real `onUpgrade` (v21 -> v22) path,
// which adds the derived `dance_figures.group_idx` correlation column (#748) and
// schedules a derived rebuild to repopulate it.
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v21_fixture.dart
//
// Ordering trap: the current code is already at schema v22, so opening a fresh
// `CompendiumDatabase` creates the v22 shape — `dance_figures.group_idx` already
// present, and already populated by the indexer. Seeding at v22 and then
// stamping `user_version = 21` would leave the column in place, so the
// v21 -> v22 `addColumn(groupIdx)` step would fail with "duplicate column
// name". So we seed realistic data at the current schema and then *strip back
// to the v21 shape* with raw SQL before stamping:
//   * ALTER TABLE dance_figures DROP COLUMN group_idx  — remove the v22-only
//     column (SQLite >= 3.35; the bundled sqlite3 is 3.53+). No index
//     references it, so no DROP INDEX is needed first.
//   * PRAGMA user_version = 21.
//
// The seeded data is chosen so the rebuild is *observable*: a dance whose
// figures are a `meanwhile` container (two concurrent sides) followed by a
// top-level figure. After the v22 rebuild, the two sides must share one
// `group_idx` and the trailing figure must get a higher one — proving the
// migration repopulated the column from `figures_json` rather than leaving every
// row at the `addColumn` DEFAULT of 0.
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
    'v21.sqlite',
  );
  final file = File(fixturePath);
  if (file.existsSync()) file.deleteSync();

  final db = CompendiumDatabase(NativeDatabase(file));
  final repos = CompendiumRepositories(db, contraTaxonomy);

  final now = DateTime.utc(2026, 1, 1);

  // A dance exercising the meanwhile flatten: [meanwhile(petronella, swing),
  // long_lines]. After the v22 rebuild the two concurrent sides share group 0
  // and the trailing long_lines is group 1.
  await repos.dances.create(
    Dance(
      id: 'dance-mw',
      title: 'Concurrent Sides',
      figures: [
        Figure.meanwhile(
          figures: [
            Figure(move: 'petronella'),
            Figure(move: 'swing', params: const {'who': 'partners'}),
          ],
          beats: 8,
        ),
        Figure(move: 'long_lines', params: const {'beats': 16}),
      ],
      createdAt: now,
      updatedAt: now,
    ),
  );

  // A plain sequential dance as a control: petronella then swing.
  await repos.dances.create(
    Dance(
      id: 'dance-seq',
      title: 'Real Sequence',
      figures: [
        Figure(move: 'petronella', params: const {'beats': 16}),
        Figure(move: 'swing', params: const {'who': 'partners', 'beats': 16}),
      ],
      createdAt: now,
      updatedAt: now,
    ),
  );

  await db.close();

  // Strip the v22-only column and stamp the file back to v21. No index
  // references `group_idx`, so it can be dropped directly.
  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('ALTER TABLE dance_figures DROP COLUMN group_idx');
  raw.execute('PRAGMA user_version = 21');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v21.');
}
