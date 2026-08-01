// Regenerates `test/storage/fixtures/v11.sqlite` — the schema-v11 database that
// `migration_test.dart` opens through the real `onUpgrade` (v11 -> v12) path.
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v11_fixture.dart
//
// Strategy (mirrors `generate_v10_fixture.dart`): seed a fresh database at the
// *current* schema through the repositories (so the choreographer/dance rows are
// realistic), then raw-SQL overwrite the seeded dance's `figures_json` with a
// LEGACY blob that references `form_an_ocean_wave` (removed from the taxonomy at
// v14) and reset `user_version` to 11. The v11 -> v12 migration is a *data*
// rewrite — it adds no columns/tables — so the v11 and v12 schemas are
// structurally identical and no strip step is needed; only the stored
// `figures_json` content and `user_version` differ.
//
// The injected blob exercises every migration branch:
//   * a `passThru: true` figure (+ balance/center/centerHand/sides/beats) — must
//     become `pass_the_ocean` carrying those params;
//   * a `passThru: false` figure — the v12 step writes the then-current
//     `form_a_short_wave`, which the v19 rename step rewrites, so the fully
//     upgraded blob holds `form_short_waves`;
//   * a `passThru`-less figure with note/progression — defaults to
//     `pass_the_ocean`, preserving note/progression, dropping the empty params;
//   * a control `swing` figure — must be left byte-identical;
//   * an already-unknown move (`some_removed_move`) — the migration does not
//     touch it and the derived rebuild renders it losslessly via the #358
//     non-throwing raw-id fallback rather than crashing.
import 'dart:convert';
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
    'v11.sqlite',
  );
  final file = File(fixturePath);
  if (file.existsSync()) file.deleteSync();

  final db = CompendiumDatabase(NativeDatabase(file));
  final repos = CompendiumRepositories(db, contraTaxonomy);

  final now = DateTime.utc(2026, 1, 1);
  await repos.choreographers.upsert(
    Choreographer(id: 'chor-1', name: 'Cary Ravitz'),
  );

  // Seed the dance with a placeholder figure; its `figures_json` is overwritten
  // below with the legacy blob (raw SQL, so it can hold the removed move id).
  await repos.dances.create(
    Dance(
      id: 'dance-1',
      title: 'Ocean Motion',
      authorIds: const ['chor-1'],
      figures: [
        Figure(move: 'swing', params: const {'who': 'partners', 'beats': 16}),
      ],
      createdAt: now,
      updatedAt: now,
    ),
  );

  await db.close();

  // The legacy figures_json blob referencing the removed `form_an_ocean_wave`.
  final legacyFigures = jsonEncode([
    {
      'schemaVersion': 1,
      'move': 'form_an_ocean_wave',
      'params': {
        'passThru': true,
        'balance': true,
        'center': 'role2s',
        'centerHand': 'right',
        'sides': 'neighbors',
        'beats': 8,
      },
    },
    {
      'schemaVersion': 1,
      'move': 'form_an_ocean_wave',
      'params': {'passThru': false, 'centerHand': 'left', 'beats': 4},
    },
    {
      'schemaVersion': 1,
      'move': 'form_an_ocean_wave',
      'params': {'passThru': true},
      'note': 'scoop',
      'progression': true,
    },
    {
      'schemaVersion': 1,
      'move': 'swing',
      'params': {'who': 'partners', 'beats': 16},
    },
    {
      'schemaVersion': 1,
      'move': 'some_removed_move',
      'params': {'beats': 8},
    },
  ]);

  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('UPDATE dances SET figures_json = ? WHERE id = ?', [
    legacyFigures,
    'dance-1',
  ]);
  raw.execute('PRAGMA user_version = 11');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v11.');
}
