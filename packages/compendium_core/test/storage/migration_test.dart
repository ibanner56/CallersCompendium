// Migration-test scaffold, per the convention documented on
// [CompendiumDatabase]: every schema migration must ship a test that opens a
// fixture DB from the previous version and asserts the migration behaves.
//
// Only schema v1 exists today, so there is no "previous version" fixture
// yet. Instead this file exercises the one migration-adjacent code path that
// *does* exist at v1: the defensive `beforeOpen` check that recreates the
// `dance_fts` virtual table if it's missing from an otherwise-valid v1
// database (e.g. one restored from an external backup taken before the FTS5
// table existed, or corrupted by manual tampering).
//
// When schema v2 lands, add a fixture DB captured at v1 (a small `.sqlite`
// file checked into `test/storage/fixtures/`) and a test here that opens it
// through the real `MigrationStrategy.onUpgrade` path, asserting both the
// resulting schema and that pre-existing data survives intact.
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

void main() {
  test(
    'beforeOpen recreates dance_fts if missing from an existing v1 database',
    () async {
      final dir = await Directory.systemTemp.createTemp('compendium_core_');
      addTearDown(() => dir.delete(recursive: true));
      final dbPath = p.join(dir.path, 'test.sqlite');

      // 1. Create a normal v1 database (onCreate builds every table + FTS5).
      final first = CompendiumDatabase(NativeDatabase(File(dbPath)));
      await first.quickCheck();
      await first.close();

      // 2. Simulate a pre-FTS backup by dropping `dance_fts` directly via a
      // raw sqlite3 connection (bypassing drift, which never drops tables).
      final raw = sqlite3.sqlite3.open(dbPath);
      raw.execute('DROP TABLE dance_fts');
      final tables = raw
          .select("SELECT name FROM sqlite_master WHERE name='dance_fts'")
          .map((row) => row['name'])
          .toList();
      expect(tables, isEmpty);
      raw.close();

      // 3. Reopen through CompendiumDatabase: schemaVersion still matches
      // (no onUpgrade runs), but `beforeOpen`'s defensive check must notice
      // `dance_fts` is missing and recreate it.
      final second = CompendiumDatabase(NativeDatabase(File(dbPath)));
      await second.quickCheck();
      final rows = await second
          .customSelect("SELECT name FROM sqlite_master WHERE name='dance_fts'")
          .get();
      expect(rows, hasLength(1));
      await second.close();
    },
  );
}
