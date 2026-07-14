// Migration tests, per the convention documented on [CompendiumDatabase]:
// every schema migration ships a test that opens a fixture DB captured at the
// previous version and asserts the migration behaves.
//
// The schema-v1 fixture (`fixtures/v1.sqlite`) is checked in and regenerated
// by `fixtures/generate_v1_fixture.dart` (see that file for the scripted
// procedure). It holds two dances whose figures span phrase sections, an
// author, a tag, and a custom-field value — captured before the v2
// `dance_figures.section` column and its indexes existed.
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

void main() {
  group('v1 -> v2 upgrade', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Copy the checked-in v1 fixture to a temp path (opening mutates it).
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v1.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    test('adds the section column and the v2 indexes', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final cols = await db
          .customSelect('PRAGMA table_info(dance_figures)')
          .get();
      expect(cols.map((r) => r.read<String>('name')), contains('section'));

      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND name LIKE 'dance_figures%'",
          )
          .get();
      final names = indexes.map((r) => r.read<String>('name')).toSet();
      expect(names, contains('dance_figures_move_section'));
      // No explicit (dance_id, idx) index: the composite PK's implicit index
      // already serves the `Then` self-join.
      expect(names, isNot(contains('dance_figures_dance_idx')));

      await db.close();
    });

    test('drift schema version is current after upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db.customSelect('PRAGMA user_version').get();
      // A v1 fixture migrates through every step to the current schema.
      expect(rows.single.data.values.first, 3);

      await db.close();
    });

    test('back-fills section labels for existing figures', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db
          .customSelect(
            'SELECT idx, move, section FROM dance_figures '
            "WHERE dance_id = 'dance-1' ORDER BY idx",
          )
          .get();
      final byIdx = {
        for (final r in rows) r.read<int>('idx'): r.read<String?>('section'),
      };
      // Beats are 16 each under the standard 4x16 structure.
      expect(byIdx[0], 'A1'); // beat 0
      expect(byIdx[1], 'A2'); // beat 16
      expect(byIdx[2], 'B1'); // beat 32
      expect(byIdx[3], 'B2'); // beat 48

      await db.close();
    });

    test('section-aware search works against the migrated fixture', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      expect(
        await repos.dances.search(FigureFilter.leaf('balance', section: 'B1')),
        ['dance-1'],
      );

      await db.close();
    });

    test(
      'rebuild marker survives a crash before back-fill (retried)',
      () async {
        // First open: onUpgrade runs (DDL + durable marker) but the process
        // "crashes" before ensureMigrated() completes the rebuild.
        final crashed = CompendiumDatabase(NativeDatabase(File(dbPath)));
        await crashed.customSelect('SELECT 1').get(); // force onUpgrade
        final marker = await crashed
            .customSelect(
              'SELECT value_json FROM settings WHERE key = ?',
              variables: [Variable.withString(derivedRebuildRequiredKey)],
            )
            .get();
        expect(marker, isNotEmpty, reason: 'onUpgrade must record the marker');
        final beforeBackfill = await crashed
            .customSelect(
              "SELECT section FROM dance_figures WHERE dance_id = 'dance-1' "
              'AND idx = 0',
            )
            .get();
        expect(beforeBackfill.single.read<String?>('section'), isNull);
        await crashed.close();

        // Second open: schema is already v2 (no onUpgrade), but the durable
        // marker makes ensureMigrated() retry the back-fill.
        final reopened = CompendiumDatabase(NativeDatabase(File(dbPath)));
        final repos = CompendiumRepositories(reopened, contraTaxonomy);
        await repos.ensureMigrated();
        final after = await reopened
            .customSelect(
              "SELECT section FROM dance_figures WHERE dance_id = 'dance-1' "
              'AND idx = 2',
            )
            .get();
        expect(after.single.read<String?>('section'), 'B1');
        // Marker cleared after a successful rebuild.
        final cleared = await reopened
            .customSelect(
              'SELECT value_json FROM settings WHERE key = ?',
              variables: [Variable.withString(derivedRebuildRequiredKey)],
            )
            .get();
        expect(cleared, isEmpty);
        await reopened.close();
      },
    );

    test('pre-existing non-derived data survives the migration', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final d1 = await repos.dances.getById('dance-1');
      expect(d1, isNotNull);
      expect(d1!.title, 'Petronella Reel');
      expect(d1.authorIds, ['auth-1']);
      expect(
        d1.customFields.single,
        CustomFieldValue(fieldId: 'cf-1', value: 'New England'),
      );

      final author = await repos.choreographers.getById('auth-1');
      expect(author?.name, 'Alice');

      await db.close();
    });

    test('ensureMigrated retries after a failed rebuild', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = _FailingOnceRepositories(db, contraTaxonomy);

      // First attempt: onUpgrade sets the durable marker, then the rebuild
      // throws. The failure must propagate and NOT be cached.
      await expectLater(repos.ensureMigrated(), throwsA(isA<StateError>()));
      expect(repos.rebuildAttempts, 1);

      // Marker still set, section still null (rebuild didn't complete).
      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(marker, isNotEmpty);

      // Second attempt: the memo was cleared, so it retries and now succeeds.
      await repos.ensureMigrated();
      expect(repos.rebuildAttempts, 2);
      final after = await db
          .customSelect(
            "SELECT section FROM dance_figures WHERE dance_id = 'dance-1' "
            'AND idx = 2',
          )
          .get();
      expect(after.single.read<String?>('section'), 'B1');
      final cleared = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(cleared, isEmpty);

      await db.close();
    });
  });

  group('v2 -> v3 upgrade', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_v3_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Copy the checked-in v2 fixture to a temp path (opening mutates it).
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v2.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    test('adds the CC-parity program/slot columns', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final programCols = await db
          .customSelect('PRAGMA table_info(programs)')
          .get();
      expect(
        programCols.map((r) => r.read<String>('name')),
        containsAll(['band', 'caller', 'dancer_level']),
      );
      final slotCols = await db
          .customSelect('PRAGMA table_info(program_slots)')
          .get();
      expect(
        slotCols.map((r) => r.read<String>('name')),
        containsAll(['guest_caller', 'planned_minutes']),
      );

      await db.close();
    });

    test('drift schema version is 3 after upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db.customSelect('PRAGMA user_version').get();
      expect(rows.single.data.values.first, 3);

      await db.close();
    });

    test(
      'preserves existing program/slot rows; new columns default to NULL',
      () async {
        final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
        final repos = CompendiumRepositories(db, contraTaxonomy);
        await repos.ensureMigrated();

        final program = await repos.programs.getById('prog-1');
        expect(program, isNotNull);
        expect(program!.title, 'Spring Dance 2026');
        expect(program.venue, 'Grange Hall');
        expect(program.notes, 'A lovely night');
        // New program-level columns default to NULL on migrated rows.
        expect(program.band, isNull);
        expect(program.caller, isNull);
        expect(program.dancerLevel, isNull);

        expect(program.slots.map((s) => s.id), ['slot-1', 'slot-2']);
        expect(program.slots.first.danceId, 'dance-1');
        expect(program.slots.last.isAlt, isTrue);
        // New per-slot columns default to NULL on migrated rows.
        expect(program.slots.every((s) => s.guestCaller == null), isTrue);
        expect(program.slots.every((s) => s.plannedMinutes == null), isTrue);

        await db.close();
      },
    );

    test('the migration does not schedule a derived rebuild', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      await db.customSelect('SELECT 1').get(); // force onUpgrade
      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(marker, isEmpty, reason: 'programs do not feed derived indexes');
      await db.close();
    });

    test('new fields round-trip after the migration', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final program = (await repos.programs.getById('prog-1'))!;
      await repos.programs.update(
        program.copyWith(
          band: 'The Fiddleheads',
          caller: 'Alice',
          dancerLevel: 'intermediate',
          slots: [
            program.slots.first.copyWith(
              guestCaller: 'Bob',
              plannedMinutes: 12,
            ),
            program.slots.last,
          ],
          updatedAt: DateTime.utc(2026, 4, 1),
        ),
      );
      final reloaded = (await repos.programs.getById('prog-1'))!;
      expect(reloaded.band, 'The Fiddleheads');
      expect(reloaded.caller, 'Alice');
      expect(reloaded.dancerLevel, 'intermediate');
      expect(reloaded.slots.first.guestCaller, 'Bob');
      expect(reloaded.slots.first.plannedMinutes, 12);

      await db.close();
    });
  });

  test(
    'beforeOpen recreates dance_fts if missing from an existing database',
    () async {
      final dir = await Directory.systemTemp.createTemp('compendium_core_');
      addTearDown(() => dir.delete(recursive: true));
      final dbPath = p.join(dir.path, 'test.sqlite');

      // 1. Create a normal current-version database (onCreate builds every
      // table + FTS5).
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

/// A [CompendiumRepositories] whose derived-index rebuild throws on its first
/// invocation and succeeds thereafter — used to prove [ensureMigrated] retries
/// after a transient failure rather than caching it.
class _FailingOnceRepositories extends CompendiumRepositories {
  _FailingOnceRepositories(super.db, super.taxonomy);

  int rebuildAttempts = 0;

  @override
  Future<void> runDerivedRebuild() async {
    rebuildAttempts++;
    if (rebuildAttempts == 1) {
      throw StateError('injected rebuild failure');
    }
    await super.runDerivedRebuild();
  }
}
