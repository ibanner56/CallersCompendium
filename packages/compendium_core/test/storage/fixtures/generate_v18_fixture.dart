// Regenerates `test/storage/fixtures/v18.sqlite` — the schema-v18 database that
// `migration_test.dart` opens through the real `onUpgrade` (v18 -> v19) path
// (issue #295: `form_a_short_wave` was RENAMED `form_short_waves` at taxonomy
// v21, so stored figures carrying the old id are rewritten).
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v18_fixture.dart
//
// Strategy (mirrors `generate_v17_fixture.dart`): seed a fresh database at the
// *current* schema through the repositories (so the choreographer/dance rows are
// realistic), then raw-SQL overwrite the seeded dance's `figures_json` with a
// LEGACY blob that references `form_a_short_wave` (renamed at taxonomy v21) and
// reset `user_version` to 18. The v18 -> v19 migration is a *data* rewrite — it
// adds no columns/tables — so the v18 and v19 schemas are structurally
// identical and no strip step is needed; only the stored `figures_json` content
// and `user_version` differ.
//
// The injected blob exercises every migration branch:
//   * a fully-specified figure (dir/balance/center/centerHand/sides/beats) plus
//     note/progression — the move id must change and everything else must be
//     preserved byte-for-byte;
//   * a params-less figure — renamed with no `params` key invented;
//   * a `meanwhile` container holding a legacy side — the NESTED side must be
//     renamed too (the schema-v18 rewrite can itself produce such containers);
//   * a control `swing` figure — must be left byte-identical;
//   * a figure under an unknown move id — must survive verbatim and ride the
//     #358 non-destructive unknown-move path.
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
    'v18.sqlite',
  );
  final file = File(fixturePath);
  if (file.existsSync()) file.deleteSync();

  final db = CompendiumDatabase(NativeDatabase(file));
  final repos = CompendiumRepositories(db, contraTaxonomy);

  final now = DateTime.utc(2026, 1, 1);
  await repos.choreographers.upsert(
    Choreographer(id: 'chor-1', name: 'Becky Hill'),
  );

  // Seed the dance with a placeholder figure; its `figures_json` is overwritten
  // below with the legacy blob (raw SQL, so it can hold the renamed move id).
  await repos.dances.create(
    Dance(
      id: 'dance-1',
      title: 'The Short Wave',
      authorIds: const ['chor-1'],
      figures: [
        Figure(move: 'swing', params: const {'who': 'partners', 'beats': 16}),
      ],
      createdAt: now,
      updatedAt: now,
    ),
  );

  await db.close();

  // The legacy figures_json blob referencing the renamed `form_a_short_wave`.
  final legacyFigures = jsonEncode([
    {
      'schemaVersion': 1,
      'move': 'form_a_short_wave',
      'params': {
        'dir': 'rightDiagonal',
        'balance': true,
        'center': 'role1s',
        'centerHand': 'left',
        'sides': 'partners',
        'beats': 8,
      },
      'note': 'ladies in the centre',
      'progression': true,
    },
    {
      'schemaVersion': 1,
      'move': 'form_a_short_wave',
      'params': <String, Object?>{},
    },
    {
      'schemaVersion': 1,
      'move': 'meanwhile',
      'params': {
        'beats': 8,
        'figures': [
          {
            'schemaVersion': 1,
            'move': 'form_a_short_wave',
            'params': {'centerHand': 'left'},
          },
          {
            'schemaVersion': 1,
            'move': 'swing',
            'params': {'who': 'partners'},
          },
        ],
      },
    },
    {
      'schemaVersion': 1,
      'move': 'swing',
      'params': {'who': 'partners', 'beats': 16},
    },
    {
      'schemaVersion': 1,
      'move': 'some_removed_move',
      'params': {'beats': 4},
    },
  ]);

  final raw = sqlite3.sqlite3.open(fixturePath);
  raw.execute('UPDATE dances SET figures_json = ? WHERE id = ?', [
    legacyFigures,
    'dance-1',
  ]);
  raw.execute('PRAGMA user_version = 18');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v18.');
}
