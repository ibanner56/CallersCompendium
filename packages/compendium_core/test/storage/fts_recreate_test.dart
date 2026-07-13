// Verifies the `beforeOpen` defensive guard in [CompendiumDatabase]: if the
// `dance_fts` virtual table is missing on open (e.g. a hand-rolled DB restored
// from a backup that predates FTS5), it is recreated so full-text search keeps
// working. Uses a file-backed database so the connection can be closed and
// reopened over the same store.
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('beforeOpen dance_fts recreation', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_fts_');
      dbPath = p.join(dir.path, 'test.sqlite');
    });

    tearDown(() => dir.delete(recursive: true));

    Future<bool> ftsExists(CompendiumDatabase db) async {
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name='dance_fts'",
          )
          .get();
      return rows.isNotEmpty;
    }

    test('recreates dance_fts when it is missing on open', () async {
      // First open: creates the schema (including dance_fts).
      var db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final dances = DanceRepository(db, contraTaxonomy);
      await dances.create(sampleDanceOrStub());
      expect(await ftsExists(db), isTrue);

      // Simulate the FTS table being absent (e.g. an older backup).
      await db.customStatement('DROP TABLE dance_fts');
      expect(await ftsExists(db), isFalse);
      await db.close();

      // Reopen: beforeOpen must recreate the missing FTS table.
      db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      // Force the connection to actually open and run beforeOpen.
      await db.customSelect('SELECT 1').get();
      expect(await ftsExists(db), isTrue);

      // And full-text search is functional again after a rebuild.
      final repo = DanceRepository(db, contraTaxonomy);
      await repo.rebuildAllDerived();
      expect(await repo.searchText('Squirrel'), isNotEmpty);
      await db.close();
    });
  });
}

Dance sampleDanceOrStub() => Dance(
  id: 'd1',
  title: 'Chase the Squirrel',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);
