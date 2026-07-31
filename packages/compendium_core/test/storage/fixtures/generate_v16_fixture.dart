// Regenerates `test/storage/fixtures/v16.sqlite` — the schema-v16 database that
// `migration_test.dart` opens through the real `onUpgrade` (v16 -> v17) path,
// which retroactively canonicalizes hand-typed prose (`hook`/`calling_notes`/
// `walkthrough`) so storage/search become dialect-agnostic (issue #613,
// audit-3 F-4).
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v16_fixture.dart
//
// Ordering trap: the current code is already at schema v17, so opening a fresh
// `CompendiumDatabase` creates the v17 shape and stamps `user_version = 17`.
// v17 is a DATA-ONLY migration (it rewrites prose column *values*; it adds no
// columns/tables/indexes), so the v16 and v17 shapes are IDENTICAL. We
// therefore seed a dance whose prose is written VERBATIM in the Larks/Robins
// dialect (exactly how a beta user's data looks pre-#613 — the repository never
// canonicalized on write, only the editor was supposed to) and then stamp the
// file back to `user_version = 16`. Opening it through the v17 `onUpgrade` must
// canonicalize the role terms (Larks -> role1s, Robins -> role2s) while leaving
// the surrounding prose byte-identical.
//
// The active dialect is seeded under the app-layer key `active_dialect` (the
// resolved dialect's JSON blob) so the migration reads a realistic global
// dialect rather than falling back to the default.
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
    'v16.sqlite',
  );
  final file = File(fixturePath);
  if (file.existsSync()) file.deleteSync();

  final db = CompendiumDatabase(NativeDatabase(file));
  final repos = CompendiumRepositories(db, contraTaxonomy);

  final now = DateTime.utc(2026, 1, 1);
  await repos.choreographers.upsert(
    Choreographer(id: 'chor-1', name: 'Cary Ravitz'),
  );
  // Prose typed in the Larks/Robins dialect and stored VERBATIM (the pre-#613
  // bug). Each field mixes role terms (which must canonicalize) with ordinary
  // prose (which must survive byte-for-byte).
  await repos.dances.create(
    Dance(
      id: 'dance-1',
      title: 'Ocean Motion',
      authorIds: const ['chor-1'],
      hook: 'Larks and Robins balance the ring.',
      callingNotes: 'Robins chain across, then Larks turn back.',
      walkthrough:
          'A1: Larks allemande left once and a half. Balance the ring and '
          'petronella.',
      figures: [
        Figure(move: 'swing', params: const {'who': 'partners', 'beats': 16}),
      ],
      createdAt: now,
      updatedAt: now,
    ),
  );
  // A second dance with NO role terms in its prose: the migration must leave it
  // completely untouched (no spurious UPDATE / rewrite).
  await repos.dances.create(
    Dance(
      id: 'dance-2',
      title: 'Plain Sailing',
      hook: 'Balance and swing your partner.',
      callingNotes: 'Circle left three places, then pass through.',
      walkthrough: 'A1: Long lines forward and back. Star right once around.',
      createdAt: now,
      updatedAt: now,
    ),
  );

  // Seed the global active dialect the migration will read (app key contract).
  await repos.settings.set('active_dialect', Dialect.larksRobins.toJson());

  await db.close();

  // Stamp the file back to v16 so the v16 -> v17 migration actually fires when
  // the test opens it. v17 adds no schema objects, so nothing to strip.
  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('PRAGMA user_version = 16');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v16.');
}
