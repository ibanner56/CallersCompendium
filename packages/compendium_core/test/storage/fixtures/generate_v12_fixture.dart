// Regenerates `test/storage/fixtures/v12.sqlite` — the schema-v12 database that
// `migration_test.dart` opens through the real `onUpgrade` (v12 -> v13) path.
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v12_fixture.dart
//
// Strategy (mirrors `generate_v11_fixture.dart`): seed a fresh database at the
// *current* schema through the repositories (so the choreographer/dance/link
// rows are realistic), then raw-SQL strip the one structural difference the
// v12 -> v13 migration introduces — the `dance_links_dance_id` index — and reset
// `user_version` to 12. v13 adds no columns/tables and rewrites no data (it only
// creates that index), so dropping the index and rewinding `user_version` yields
// a structurally-faithful v12 database.
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

  // Strip the v13 index and rewind user_version so the fixture is a faithful
  // v12 database (structurally identical to v12: v13's only change is the index).
  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('DROP INDEX IF EXISTS dance_links_dance_id');
  raw.execute('PRAGMA user_version = 12');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v12.');
}
