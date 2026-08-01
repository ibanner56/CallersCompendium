// Regenerates `test/storage/fixtures/v19.sqlite` — the schema-v19 database that
// `migration_test.dart` opens through the real `onUpgrade` (v19 -> v20) path
// (the gate merge: `gate` and `rotation_gate` became one `gate` move at taxonomy
// v22 and their stored figures are rewritten onto it).
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v19_fixture.dart
//
// Strategy (mirrors `generate_v17_fixture.dart`): seed a fresh database at the
// *current* schema through the repositories (so the choreographer/dance rows are
// realistic), then raw-SQL overwrite the seeded dance's `figures_json` with a
// LEGACY blob referencing both retired shapes, and reset `user_version` to 19.
// Neither the v19 (`form_a_short_wave` move rename) nor the v20 (gate merge)
// migration adds a column or table — both are *data* rewrites — so the v18, v19
// and v20 schemas are structurally identical and no strip step is needed; only
// the stored `figures_json` content and `user_version` differ. The blob below
// holds no `form_a_short_wave` figure, so the v19 step is a no-op on it and the
// fixture isolates the v20 gate rewrite.
//
// The injected blob exercises every migration branch:
//   * a fully-specified `rotation_gate` (who/direction/turn/beats) + note and
//     progression — `who` must land on `pair` (NOT `who`), the rest carry over,
//     and the note/progression survive;
//   * a params-less `rotation_gate` — the retired move's own defaults must be
//     materialized explicitly (pair `neighbors`, direction `counterclockwise`,
//     turn 0.5), since the merged move defaults every slot to `unspecified`;
//   * a fully-specified legacy `gate` (who/whom/face/beats) — must be left
//     byte-identical (same move id, same slots, same meaning);
//   * a partially-specified legacy `gate` (only `beats`) — the retired move's
//     defaults (who `ones`, whom `neighbors`, face `up`) must be materialized;
//   * a `meanwhile` container holding a `rotation_gate` side — the migration
//     must recurse into `params.figures` and preserve the container's shared
//     `beats`;
//   * a control `swing` figure — must be left byte-identical.
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
    'v19.sqlite',
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
      title: 'Gate Expectations',
      authorIds: const ['chor-1'],
      figures: [
        Figure(move: 'swing', params: const {'who': 'partners', 'beats': 16}),
      ],
      createdAt: now,
      updatedAt: now,
    ),
  );

  await db.close();

  // The legacy figures_json blob referencing both retired gate shapes.
  final legacyFigures = jsonEncode([
    {
      'schemaVersion': 1,
      'move': 'rotation_gate',
      'params': {
        'who': 'nextNeighbors',
        'direction': 'counterclockwise',
        'turn': 0.5,
        'beats': 4,
      },
      'note': 'ones forward',
      'progression': true,
    },
    {
      'schemaVersion': 1,
      'move': 'rotation_gate',
      'params': <String, Object?>{},
    },
    {
      'schemaVersion': 1,
      'move': 'gate',
      'params': {
        'who': 'ones',
        'whom': 'neighbors',
        'face': 'down',
        'beats': 8,
      },
    },
    {
      'schemaVersion': 1,
      'move': 'gate',
      'params': {'beats': 8},
    },
    {
      'schemaVersion': 1,
      'move': 'meanwhile',
      'params': {
        'beats': 4,
        'figures': [
          {
            'schemaVersion': 1,
            'move': 'rotation_gate',
            'params': {
              'who': 'partners',
              'direction': 'clockwise',
              'turn': 0.25,
            },
          },
          {
            'schemaVersion': 1,
            'move': 'swing',
            'params': {'who': 'neighbors'},
          },
        ],
      },
    },
    {
      'schemaVersion': 1,
      'move': 'swing',
      'params': {'who': 'partners', 'beats': 16},
    },
  ]);

  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('UPDATE dances SET figures_json = ? WHERE id = ?', [
    legacyFigures,
    'dance-1',
  ]);
  raw.execute('PRAGMA user_version = 19');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v19.');
}
