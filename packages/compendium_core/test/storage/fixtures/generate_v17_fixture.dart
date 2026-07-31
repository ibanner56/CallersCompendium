// Regenerates `test/storage/fixtures/v17.sqlite` — the schema-v17 database that
// `migration_test.dart` opens through the real `onUpgrade` (v17 -> v18) path
// (issue #295: the fused `allemande_orbit` move was retired at taxonomy v19 and
// its stored figures are rewritten to `meanwhile[allemande, orbit]`).
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v17_fixture.dart
//
// Strategy (mirrors `generate_v11_fixture.dart`): seed a fresh database at the
// *current* schema through the repositories (so the choreographer/dance rows are
// realistic), then raw-SQL overwrite the seeded dance's `figures_json` with a
// LEGACY blob that references `allemande_orbit` (removed from the taxonomy at
// v19) and reset `user_version` to 17. The v17 -> v18 migration is a *data*
// rewrite — it adds no columns/tables — so the v17 and v18 schemas are
// structurally identical and no strip step is needed; only the stored
// `figures_json` content and `user_version` differ.
//
// The injected blob exercises every migration branch:
//   * a fully-specified figure (who/hand/inner/outer/beats) + note/progression —
//     must become meanwhile[allemande{ones,left,1.5}, orbit{twos,clockwise,0.5}],
//     carrying beats 8 and preserving the note/progression;
//   * a hand:right figure — orbit direction must derive to `counterclockwise`
//     and the orbiting pair to `role2s` (invert of role1s), with the absent
//     inner/outer filled from the fused defaults (1.5 / 0.5);
//   * a params-less figure — all fused defaults apply
//     (meanwhile[allemande{ones,left,1.5}, orbit{twos,clockwise,0.5}], beats 8);
//   * a control `swing` figure — must be left byte-identical;
//   * a wildcard `hand: '*'` figure — unmappable direction, so the migration
//     leaves it byte-identical and the derived rebuild renders it losslessly via
//     the #358 non-throwing raw-id fallback rather than fabricating a direction.
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
    'v17.sqlite',
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
      title: 'Another Orbit for Liz',
      authorIds: const ['chor-1'],
      figures: [
        Figure(move: 'swing', params: const {'who': 'partners', 'beats': 16}),
      ],
      createdAt: now,
      updatedAt: now,
    ),
  );

  await db.close();

  // The legacy figures_json blob referencing the removed `allemande_orbit`.
  final legacyFigures = jsonEncode([
    {
      'schemaVersion': 1,
      'move': 'allemande_orbit',
      'params': {
        'who': 'ones',
        'hand': 'left',
        'inner': 1.5,
        'outer': 0.5,
        'beats': 8,
      },
      'note': 'scoop',
      'progression': true,
    },
    {
      'schemaVersion': 1,
      'move': 'allemande_orbit',
      'params': {'who': 'role1s', 'hand': 'right', 'beats': 8},
    },
    {
      'schemaVersion': 1,
      'move': 'allemande_orbit',
      'params': <String, Object?>{},
    },
    {
      'schemaVersion': 1,
      'move': 'swing',
      'params': {'who': 'partners', 'beats': 16},
    },
    {
      'schemaVersion': 1,
      'move': 'allemande_orbit',
      'params': {'who': 'ones', 'hand': '*', 'beats': 8},
    },
  ]);

  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('UPDATE dances SET figures_json = ? WHERE id = ?', [
    legacyFigures,
    'dance-1',
  ]);
  raw.execute('PRAGMA user_version = 17');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v17.');
}
