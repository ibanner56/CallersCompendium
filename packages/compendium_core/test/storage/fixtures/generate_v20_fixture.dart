// Regenerates `test/storage/fixtures/v20.sqlite` — the schema-v20 database that
// `migration_test.dart` opens through the real `onUpgrade` (v20 -> v21) path:
// the first *structural removal* migration in this schema's history (issues
// #781, #782). v21 drops `provenance.raw_payload`,
// `program_provenance.raw_payload`, and the whole `snapshots` table.
//
// Run from the package root:
//
//     dart run test/storage/fixtures/generate_v20_fixture.dart
//
// Strategy: every other generator here seeds at the *current* schema and then
// strips forward, which works because no previous migration removed anything.
// This one cannot — once v21 lands, `createAll()` no longer creates the very
// columns the fixture must contain. So it seeds realistic rows through the
// repositories at the current schema, then re-adds what v21 removed with raw
// SQL: `ALTER TABLE … ADD COLUMN` puts the two `raw_payload` columns back, a
// `CREATE TABLE` restores `snapshots`, and `user_version` is reset to 20.
//
// **Scope of that reconstruction, precisely:** it undoes v21 and nothing else.
// It is therefore correct only while the current schema is v21. If a later
// migration structurally changes any table (a new column on `dances`, say),
// re-running this emits a hybrid — that table in its newer shape, stamped
// `user_version = 20` — and the migration under test would then run against a
// schema it never saw in the field. Every other generator in this directory
// shares that limitation for the same reason (see `generate_v19_fixture.dart`,
// which is explicit that it relies on v18/v19/v20 being structurally
// identical); none of them is unconditionally re-runnable, and this one is not
// either. The checked-in `v20.sqlite` is the artefact of record. Re-running is
// for regenerating it on a tree still at v21; past that, this file needs the
// same care any of its siblings would.
//
// The fixture is deliberately loaded on every axis the migration touches, and
// on the ones it must NOT touch:
//
//   * `provenance.raw_payload` populated with a realistic verbatim payload —
//     the column being dropped, with data in it;
//   * `program_provenance` given a row *with* a `raw_payload`, written by raw
//     SQL because no app path ever populates that column (that absence is half
//     of #781). The migration must handle a populated column regardless;
//   * sibling provenance columns (`source`, `external_id`, `imported_at`,
//     `permission`, `license`, `source_version`) populated on both tables — a
//     table rebuild that drops one column must preserve every other, and this
//     is the assertion that catches a botched column list;
//   * two `snapshots` rows — the table being dropped;
//   * `tags.color` populated. This one is a control: #782 was filed against
//     both `snapshots` and `tags.color`, and only `snapshots` is being
//     dropped. A rebuild that took `tags` with it, or dropped the colour while
//     rebuilding, would be caught here.
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
    'v20.sqlite',
  );
  final file = File(fixturePath);
  if (file.existsSync()) file.deleteSync();

  final db = CompendiumDatabase(NativeDatabase(file));
  final repos = CompendiumRepositories(db, contraTaxonomy);

  final now = DateTime.utc(2026, 1, 1);

  await repos.choreographers.upsert(
    Choreographer(id: 'chor-1', name: 'Cary Ravitz'),
  );

  // A tag WITH a colour — the control that must survive v21 untouched.
  await repos.tags.upsert(Tag(id: 'tag-1', name: 'Easy', color: 0xFF2196F3));

  // A dance carrying full provenance, including the payload being dropped.
  await repos.dances.create(
    Dance(
      id: 'dance-1',
      title: 'Right Where We Belong',
      authorIds: const ['chor-1'],
      tagIds: const ['tag-1'],
      figures: [
        Figure(move: 'swing', params: const {'who': 'partners', 'beats': 16}),
      ],
      createdAt: now,
      updatedAt: now,
      provenance: Provenance(
        source: ProvenanceSource.contradb,
        externalId: '2443',
        importedAt: now,
        permission: 'CC BY-NC-SA 3.0',
        license: 'CC BY-NC-SA 3.0',
        sourceVersion: 'contradb-2026-01',
      ),
    ),
  );

  await repos.programs.create(
    Program(
      id: 'program-1',
      title: 'Winter Contra',
      createdAt: now,
      updatedAt: now,
      slots: const [],
    ),
  );

  await db.close();

  final raw = sqlite3.sqlite3.open(fixturePath);

  // Reconstruct the v20 shape: put back the two columns and the table that v21
  // drops. `ADD COLUMN` is supported by every SQLite version we target.
  raw.execute('ALTER TABLE provenance ADD COLUMN raw_payload TEXT');
  raw.execute('ALTER TABLE program_provenance ADD COLUMN raw_payload TEXT');
  raw.execute(
    'CREATE TABLE snapshots ('
    'source TEXT NOT NULL PRIMARY KEY, '
    'snapshot_date INTEGER NOT NULL, '
    'manifest_json TEXT NOT NULL, '
    'imported_at INTEGER NOT NULL)',
  );

  raw.execute('UPDATE provenance SET raw_payload = ? WHERE dance_id = ?', [
    '<html><body>verbatim source page</body></html>',
    'dance-1',
  ]);

  // `program_provenance.raw_payload` has no writer anywhere in the app (#781),
  // so its row is seeded directly. The migration must still carry every sibling
  // column across the rebuild.
  raw.execute(
    'INSERT INTO program_provenance '
    '(program_id, source, external_id, imported_at, permission, license, '
    ' raw_payload, source_version) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [
      'program-1',
      'callersCompanion',
      'set-42',
      now.millisecondsSinceEpoch ~/ 1000,
      'personal use',
      'unlicensed',
      '{"rowId":"set-42","columns":{"Caller":"Anon"}}',
      'cc-usr-1',
    ],
  );

  // Two `snapshots` rows — the table being dropped. `SnapshotRepository.upsert`
  // has no call sites (#782), so these are seeded directly too.
  raw.execute(
    'INSERT INTO snapshots (source, snapshot_date, manifest_json, imported_at) '
    'VALUES (?, ?, ?, ?)',
    [
      'callersbox',
      now.millisecondsSinceEpoch ~/ 1000,
      '{"count":11500}',
      now.millisecondsSinceEpoch ~/ 1000,
    ],
  );
  raw.execute(
    'INSERT INTO snapshots (source, snapshot_date, manifest_json, imported_at) '
    'VALUES (?, ?, ?, ?)',
    [
      'contradb',
      now.millisecondsSinceEpoch ~/ 1000,
      '{"count":3200}',
      now.millisecondsSinceEpoch ~/ 1000,
    ],
  );

  raw.execute('PRAGMA user_version = 20');
  raw.close();

  stdout.writeln('Wrote $fixturePath at schema v20.');
}
