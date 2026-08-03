// Migration tests, per the convention documented on [CompendiumDatabase]:
// every schema migration ships a test that opens a fixture DB captured at the
// previous version and asserts the migration behaves.
//
// The schema-v1 fixture (`fixtures/v1.sqlite`) is checked in and regenerated
// by `fixtures/generate_v1_fixture.dart` (see that file for the scripted
// procedure). It holds two dances whose figures span phrase sections, an
// author, a tag, and a custom-field value — captured before the v2
// `dance_figures.section` column and its indexes existed.
import 'dart:convert';
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
      expect(rows.single.data.values.first, db.schemaVersion);

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

    test('drift schema version is current after upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db.customSelect('PRAGMA user_version').get();
      expect(rows.single.data.values.first, db.schemaVersion);

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

    test('the migration schedules a rebuild for the v9 FTS reshape', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      await db.customSelect('SELECT 1').get(); // force onUpgrade
      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(
        marker,
        isNotEmpty,
        reason:
            'upgrading past v9 reshapes dance_fts and schedules a rebuild '
            '(the v3 program metadata itself does not feed derived indexes)',
      );
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

  group('v3 -> v4 upgrade', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_v4_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Copy the checked-in v3 fixture to a temp path (opening mutates it).
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v3.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    test('adds the CC-parity dance difficulty columns', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final danceCols = await db
          .customSelect('PRAGMA table_info(dances)')
          .get();
      expect(
        danceCols.map((r) => r.read<String>('name')),
        containsAll(['level', 'mixed_level']),
      );

      await db.close();
    });

    test('drift schema version is current after upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db.customSelect('PRAGMA user_version').get();
      expect(rows.single.data.values.first, db.schemaVersion);

      await db.close();
    });

    test(
      'preserves existing dance rows; level is NULL / mixedLevel is false',
      () async {
        final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
        final repos = CompendiumRepositories(db, contraTaxonomy);
        await repos.ensureMigrated();

        final dance = await repos.dances.getById('dance-1');
        expect(dance, isNotNull);
        expect(dance!.title, 'Petronella Reel');
        // New difficulty columns default on migrated rows.
        expect(dance.level, isNull);
        expect(dance.mixedLevel, isFalse);

        await db.close();
      },
    );

    test('the migration schedules a rebuild for the v9 FTS reshape', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      await db.customSelect('SELECT 1').get(); // force onUpgrade
      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(
        marker,
        isNotEmpty,
        reason:
            'upgrading past v9 reshapes dance_fts and schedules a rebuild '
            '(dance level is scalar metadata, not figure text)',
      );
      await db.close();
    });

    test('new fields round-trip after the migration', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final dance = (await repos.dances.getById('dance-1'))!;
      await repos.dances.update(
        dance.copyWith(
          level: DanceLevel.intermediate,
          mixedLevel: true,
          updatedAt: DateTime.utc(2026, 4, 1),
        ),
      );
      final reloaded = (await repos.dances.getById('dance-1'))!;
      expect(reloaded.level, DanceLevel.intermediate);
      expect(reloaded.mixedLevel, isTrue);

      // The clear-flag resets a set level back to NULL.
      await repos.dances.update(
        reloaded.copyWith(
          clearLevel: true,
          updatedAt: DateTime.utc(2026, 4, 2),
        ),
      );
      final cleared = (await repos.dances.getById('dance-1'))!;
      expect(cleared.level, isNull);
      expect(cleared.mixedLevel, isTrue);

      await db.close();
    });
  });

  group('v4 -> v5 upgrade', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_v5_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Copy the checked-in v4 fixture to a temp path (opening mutates it).
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v4.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    test('adds the CC-parity composed/revised date columns', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final danceCols = await db
          .customSelect('PRAGMA table_info(dances)')
          .get();
      expect(
        danceCols.map((r) => r.read<String>('name')),
        containsAll(['composed_on', 'revised_on']),
      );

      await db.close();
    });

    test('drift schema version is current after upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db.customSelect('PRAGMA user_version').get();
      expect(rows.single.data.values.first, db.schemaVersion);

      await db.close();
    });

    test(
      'preserves existing dance rows; composedOn / revisedOn are NULL',
      () async {
        final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
        final repos = CompendiumRepositories(db, contraTaxonomy);
        await repos.ensureMigrated();

        final dance = await repos.dances.getById('dance-1');
        expect(dance, isNotNull);
        expect(dance!.title, 'Petronella Reel');
        // Pre-existing v4 metadata survives the upgrade.
        expect(dance.level, DanceLevel.intermediate);
        // New date columns default to NULL on migrated rows.
        expect(dance.composedOn, isNull);
        expect(dance.revisedOn, isNull);

        await db.close();
      },
    );

    test('the migration schedules a rebuild for the v9 FTS reshape', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      await db.customSelect('SELECT 1').get(); // force onUpgrade
      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(
        marker,
        isNotEmpty,
        reason:
            'upgrading past v9 reshapes dance_fts and schedules a rebuild '
            '(composed/revised dates are scalar metadata, not figure text)',
      );
      await db.close();
    });

    test(
      'new date fields round-trip partial precisions after the migration',
      () async {
        final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
        final repos = CompendiumRepositories(db, contraTaxonomy);
        await repos.ensureMigrated();

        final dance = (await repos.dances.getById('dance-1'))!;
        // Year-only composed, full-precision revised.
        await repos.dances.update(
          dance.copyWith(
            composedOn: PartialDate(1989),
            revisedOn: PartialDate(2004, 3, 15),
            updatedAt: DateTime.utc(2026, 4, 1),
          ),
        );
        final reloaded = (await repos.dances.getById('dance-1'))!;
        expect(reloaded.composedOn, PartialDate(1989));
        expect(reloaded.composedOn!.precision, DatePrecision.year);
        expect(reloaded.revisedOn, PartialDate(2004, 3, 15));
        expect(reloaded.revisedOn!.precision, DatePrecision.day);

        // Year+month precision also round-trips.
        await repos.dances.update(
          reloaded.copyWith(
            composedOn: PartialDate(2010, 6),
            updatedAt: DateTime.utc(2026, 4, 2),
          ),
        );
        final month = (await repos.dances.getById('dance-1'))!;
        expect(month.composedOn, PartialDate(2010, 6));
        expect(month.composedOn!.precision, DatePrecision.month);

        // The clear-flags reset set dates back to NULL.
        await repos.dances.update(
          month.copyWith(
            clearComposedOn: true,
            clearRevisedOn: true,
            updatedAt: DateTime.utc(2026, 4, 3),
          ),
        );
        final cleared = (await repos.dances.getById('dance-1'))!;
        expect(cleared.composedOn, isNull);
        expect(cleared.revisedOn, isNull);

        await db.close();
      },
    );
  });

  group('v5 -> v6 upgrade', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_v6_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Copy the checked-in v5 fixture to a temp path (opening mutates it).
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v5.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    test('adds the CC-parity rating column', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final danceCols = await db
          .customSelect('PRAGMA table_info(dances)')
          .get();
      expect(danceCols.map((r) => r.read<String>('name')), contains('rating'));

      await db.close();
    });

    test('drift schema version is current after upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db.customSelect('PRAGMA user_version').get();
      expect(rows.single.data.values.first, db.schemaVersion);

      await db.close();
    });

    test('preserves existing dance rows; rating is NULL', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final dance = await repos.dances.getById('dance-1');
      expect(dance, isNotNull);
      expect(dance!.title, 'Petronella Reel');
      // Pre-existing v5 metadata survives the upgrade.
      expect(dance.level, DanceLevel.intermediate);
      expect(dance.composedOn, PartialDate(1989));
      // New rating column defaults to NULL on migrated rows.
      expect(dance.rating, isNull);

      await db.close();
    });

    test('the migration schedules a rebuild for the v9 FTS reshape', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      await db.customSelect('SELECT 1').get(); // force onUpgrade
      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(
        marker,
        isNotEmpty,
        reason:
            'upgrading past v9 reshapes dance_fts and schedules a rebuild '
            '(rating is scalar curation metadata, not figure text)',
      );
      await db.close();
    });

    test('rating round-trips (incl. clear) after the migration', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final dance = (await repos.dances.getById('dance-1'))!;
      await repos.dances.update(
        dance.copyWith(rating: 5, updatedAt: DateTime.utc(2026, 4, 1)),
      );
      expect((await repos.dances.getById('dance-1'))!.rating, 5);

      // The clear-flag resets a set rating back to NULL.
      await repos.dances.update(
        (await repos.dances.getById(
          'dance-1',
        ))!.copyWith(clearRating: true, updatedAt: DateTime.utc(2026, 4, 2)),
      );
      expect((await repos.dances.getById('dance-1'))!.rating, isNull);

      await db.close();
    });
  });

  group('v6 -> v7 upgrade', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_v7_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Copy the checked-in v6 fixture to a temp path (opening mutates it).
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v6.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    test('adds the CC-parity author contact columns', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final cols = await db
          .customSelect('PRAGMA table_info(choreographers)')
          .get();
      final names = cols.map((r) => r.read<String>('name')).toSet();
      expect(names, containsAll(['email', 'location', 'deceased']));

      await db.close();
    });

    test('drift schema version is current after upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db.customSelect('PRAGMA user_version').get();
      expect(rows.single.data.values.first, db.schemaVersion);

      await db.close();
    });

    test(
      'preserves existing choreographer rows; contact fields default',
      () async {
        final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
        final repos = CompendiumRepositories(db, contraTaxonomy);
        await repos.ensureMigrated();

        final chor = await repos.choreographers.getById('chor-1');
        expect(chor, isNotNull);
        expect(chor!.name, 'Cary Ravitz');
        // Pre-existing v6 metadata survives the upgrade.
        expect(chor.website, 'https://ravitz.us');
        // New contact columns default to NULL / false on migrated rows.
        expect(chor.email, isNull);
        expect(chor.location, isNull);
        expect(chor.deceased, isFalse);

        await db.close();
      },
    );

    test('the migration schedules a rebuild for the v9 FTS reshape', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      await db.customSelect('SELECT 1').get(); // force onUpgrade
      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(
        marker,
        isNotEmpty,
        reason:
            'upgrading past v9 reshapes dance_fts and schedules a rebuild '
            '(author contact is scalar metadata, not figure text)',
      );
      await db.close();
    });

    test(
      'contact fields round-trip (incl. clear) after the migration',
      () async {
        final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
        final repos = CompendiumRepositories(db, contraTaxonomy);
        await repos.ensureMigrated();

        final chor = (await repos.choreographers.getById('chor-1'))!;
        await repos.choreographers.upsert(
          chor.copyWith(
            email: 'cary@example.com',
            location: 'Lexington, KY',
            deceased: true,
          ),
        );
        final updated = (await repos.choreographers.getById('chor-1'))!;
        expect(updated.email, 'cary@example.com');
        expect(updated.location, 'Lexington, KY');
        expect(updated.deceased, isTrue);

        // The clear-flags reset the contact fields back to NULL.
        await repos.choreographers.upsert(
          updated.copyWith(clearEmail: true, clearLocation: true),
        );
        final cleared = (await repos.choreographers.getById('chor-1'))!;
        expect(cleared.email, isNull);
        expect(cleared.location, isNull);
        expect(cleared.deceased, isTrue);

        await db.close();
      },
    );
  });

  group('v7 -> v8 upgrade', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_v8_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Copy the checked-in v7 fixture to a temp path (opening mutates it).
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v7.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    test('creates the published_sources and dance_sources tables', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name IN ('published_sources', 'dance_sources')",
          )
          .get();
      final names = tables.map((r) => r.read<String>('name')).toSet();
      expect(names, containsAll(['published_sources', 'dance_sources']));

      await db.close();
    });

    test('drift schema version is current after upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db.customSelect('PRAGMA user_version').get();
      expect(rows.single.data.values.first, db.schemaVersion);

      await db.close();
    });

    test('preserves pre-existing rows across the upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final chor = await repos.choreographers.getById('chor-1');
      expect(chor, isNotNull);
      expect(chor!.name, 'Cary Ravitz');

      final dance = await repos.dances.getById('dance-1');
      expect(dance, isNotNull);
      expect(dance!.title, 'Petronella Reel');
      expect(dance.authorIds, ['chor-1']);
      // A migrated dance has no citations yet (fresh, empty tables).
      expect(dance.sourceCitations, isEmpty);

      await db.close();
    });

    test('the migration schedules a rebuild for the v9 FTS reshape', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      await db.customSelect('SELECT 1').get(); // force onUpgrade
      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(
        marker,
        isNotEmpty,
        reason:
            'upgrading past v9 reshapes dance_fts (adding the sources column) '
            'and schedules a rebuild so citations become searchable',
      );
      await db.close();
    });

    test('citations round-trip on the migrated database', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      await repos.publishedSources.upsert(
        PublishedSource(id: 's1', title: 'Zesty Contras', year: 1983),
      );
      final dance = (await repos.dances.getById('dance-1'))!;
      await repos.dances.update(
        dance.copyWith(
          sourceCitations: [SourceCitation(sourceId: 's1', page: '12')],
          updatedAt: DateTime.utc(2026, 2, 1),
        ),
      );
      final reloaded = (await repos.dances.getById('dance-1'))!;
      expect(reloaded.sourceCitations, hasLength(1));
      expect(reloaded.sourceCitations.single.sourceId, 's1');
      expect(reloaded.sourceCitations.single.page, '12');

      await db.close();
    });
  });

  group('v8 -> v9 upgrade', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_v9_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Copy the checked-in v8 fixture to a temp path (opening mutates it).
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v8.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    test('recreates dance_fts with the sources column', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final cols = await db.customSelect('PRAGMA table_info(dance_fts)').get();
      final names = cols.map((r) => r.read<String>('name')).toList();
      expect(names, contains('sources'));
      // The pre-v9 columns survive the recreation.
      expect(
        names,
        containsAll([
          'dance_id',
          'title',
          'authors',
          'hook',
          'notes',
          'figures_text',
          'custom_values',
        ]),
      );

      await db.close();
    });

    test('drift schema version is current after upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db.customSelect('PRAGMA user_version').get();
      expect(rows.single.data.values.first, db.schemaVersion);

      await db.close();
    });

    test('the migration schedules a derived rebuild', () async {
      // First open forces onUpgrade, which records the durable marker BEFORE
      // ensureMigrated() consumes it — the FTS shape changed, so a full
      // derived rebuild is owed to repopulate the new `sources` column.
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      await db.customSelect('SELECT 1').get(); // force onUpgrade
      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(
        marker,
        isNotEmpty,
        reason: 'the dance_fts shape changed, so a rebuild must be scheduled',
      );
      await db.close();
    });

    test('ensureMigrated performs the rebuild and clears the marker', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final cleared = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(cleared, isEmpty);

      await db.close();
    });

    test('preserves pre-existing rows across the upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final chor = await repos.choreographers.getById('chor-1');
      expect(chor?.name, 'Cary Ravitz');

      final dance = await repos.dances.getById('dance-1');
      expect(dance, isNotNull);
      expect(dance!.title, 'Petronella Reel');
      expect(dance.sourceCitations, hasLength(1));
      expect(dance.sourceCitations.single.sourceId, 'src-1');

      final source = await repos.publishedSources.getById('src-1');
      expect(source?.title, 'Zesty Contras');

      await db.close();
    });

    test(
      'after the rebuild a cited dance is findable by its source title',
      () async {
        final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
        final repos = CompendiumRepositories(db, contraTaxonomy);
        await repos.ensureMigrated();

        // The v8 fixture's FTS row did NOT index the source; the derived
        // rebuild repopulates the new `sources` column, so the cited dance is
        // now reachable both by a bare full-text search and the SourceFilter.
        expect(await repos.dances.search(const FullTextFilter('Zesty')), [
          'dance-1',
        ]);
        expect(await repos.dances.search(const SourceFilter('Zesty Contras')), [
          'dance-1',
        ]);

        await db.close();
      },
    );

    test(
      'rebuild marker survives a crash before back-fill (retried)',
      () async {
        // First open: onUpgrade recreates dance_fts (now empty) + sets the
        // durable marker, then the process "crashes" before ensureMigrated()
        // completes the rebuild.
        final crashed = CompendiumDatabase(NativeDatabase(File(dbPath)));
        await crashed.customSelect('SELECT 1').get(); // force onUpgrade
        final beforeBackfill = await crashed
            .customSelect('SELECT COUNT(*) AS n FROM dance_fts')
            .get();
        expect(
          beforeBackfill.single.read<int>('n'),
          0,
          reason: 'recreated dance_fts is empty until the rebuild runs',
        );
        await crashed.close();

        // Second open: schema is already v9 (no onUpgrade), but the durable
        // marker makes ensureMigrated() retry the back-fill.
        final reopened = CompendiumDatabase(NativeDatabase(File(dbPath)));
        final repos = CompendiumRepositories(reopened, contraTaxonomy);
        await repos.ensureMigrated();
        expect(await repos.dances.search(const SourceFilter('Zesty')), [
          'dance-1',
        ]);
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
  });

  group('v9 -> v10 upgrade', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_v10_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Copy the checked-in v9 fixture to a temp path (opening mutates it).
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v9.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    test('creates the program_provenance table', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name='program_provenance'",
          )
          .get();
      expect(tables, hasLength(1));

      await db.close();
    });

    test('drift schema version is current after upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db.customSelect('PRAGMA user_version').get();
      expect(rows.single.data.values.first, db.schemaVersion);

      await db.close();
    });

    test('pre-existing programs survive with null provenance', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final program = await repos.programs.getById('prog-1');
      expect(program, isNotNull);
      expect(program!.title, 'Spring Contra 2026');
      expect(program.slots, hasLength(2));
      // The migration is purely additive — no back-fill — so an existing
      // (user-created) program has no provenance and never dedupes.
      expect(program.provenance, isNull);
      expect(
        await repos.programs.externalIdToProgramId(
          ProvenanceSource.callersCompanion,
        ),
        isEmpty,
      );

      await db.close();
    });

    test('a CC program can be written and deduped after the upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      await repos.programs.create(
        Program(
          id: 'cc-prog',
          title: 'Imported Set',
          createdAt: DateTime.utc(2026, 2, 1),
          updatedAt: DateTime.utc(2026, 2, 1),
          provenance: Provenance(
            source: ProvenanceSource.callersCompanion,
            externalId: 'set-1',
            importedAt: DateTime.utc(2026, 2, 1),
            sourceVersion: 'cc-usr-1',
          ),
        ),
      );

      expect(
        await repos.programs.externalIdToProgramId(
          ProvenanceSource.callersCompanion,
        ),
        {'set-1': 'cc-prog'},
      );

      await db.close();
    });
  });

  group('v10 -> v11 upgrade', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_v11_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Copy the checked-in v10 fixture to a temp path (opening mutates it).
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v10.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    test('adds the programs.hide_alternates column', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final columns = await db
          .customSelect("PRAGMA table_info('programs')")
          .get();
      final names = [for (final row in columns) row.read<String>('name')];
      expect(names, contains('hide_alternates'));

      await db.close();
    });

    test('drift schema version is current after upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db.customSelect('PRAGMA user_version').get();
      expect(rows.single.data.values.first, db.schemaVersion);

      await db.close();
    });

    test('pre-existing programs default hideAlternates to false', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final program = await repos.programs.getById('prog-1');
      expect(program, isNotNull);
      expect(program!.title, 'Spring Contra 2026');
      expect(program.slots, hasLength(2));
      // The migration is purely additive with a false default — an existing
      // program keeps showing its alternates.
      expect(program.hideAlternates, isFalse);

      await db.close();
    });

    test('hideAlternates round-trips after the upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final program = await repos.programs.getById('prog-1');
      await repos.programs.update(
        program!.copyWith(
          hideAlternates: true,
          updatedAt: DateTime.utc(2026, 3),
        ),
      );

      final reloaded = await repos.programs.getById('prog-1');
      expect(reloaded!.hideAlternates, isTrue);
      // The stored slots are untouched — only the output view respects the flag.
      expect(reloaded.slots, hasLength(2));
      expect(reloaded.outputGrouped.single.alternates, isEmpty);

      await db.close();
    });
  });

  group('v11 -> v12 upgrade (issue #290 ocean-wave rewrite)', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_v12_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Copy the checked-in v11 fixture to a temp path (opening mutates it).
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v11.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    test('drift schema version is current after upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db.customSelect('PRAGMA user_version').get();
      expect(rows.single.data.values.first, db.schemaVersion);

      await db.close();
    });

    test('rewrites stored figures_json onto the split moves, carrying '
        'params minus passThru', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final dance = await repos.dances.getById('dance-1');
      expect(dance, isNotNull);
      final figures = dance!.figures;
      expect(figures, hasLength(5));

      // passThru:true (+ balance/center/centerHand/sides/beats) -> pass_the_ocean.
      expect(figures[0].move, 'pass_the_ocean');
      expect(figures[0].params.containsKey('passThru'), isFalse);
      expect(figures[0].params['balance'], true);
      expect(figures[0].params['center'], 'role2s');
      expect(figures[0].params['centerHand'], 'right');
      expect(figures[0].params['sides'], 'neighbors');
      expect(figures[0].params['beats'], 8);

      // passThru:false -> form_short_waves; other params intact.
      expect(figures[1].move, 'form_short_waves');
      expect(figures[1].params.containsKey('passThru'), isFalse);
      expect(figures[1].params['centerHand'], 'left');
      expect(figures[1].params['beats'], 4);

      // passThru:true with no other params -> pass_the_ocean, note/progression
      // preserved, empty params dropped.
      expect(figures[2].move, 'pass_the_ocean');
      expect(figures[2].params, isEmpty);
      expect(figures[2].note, 'scoop');
      expect(figures[2].progression, isTrue);

      // Control figure on a normal move: byte-identical.
      expect(figures[3].move, 'swing');
      expect(figures[3].params['who'], 'partners');
      expect(figures[3].params['beats'], 16);

      await db.close();
    });

    test(
      'rebuilt dance_figures + canonicalText reflect the new moves',
      () async {
        final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
        final repos = CompendiumRepositories(db, contraTaxonomy);
        await repos.ensureMigrated();

        final rows = await db
            .customSelect(
              'SELECT idx, move, canonical_text FROM dance_figures '
              "WHERE dance_id = 'dance-1' ORDER BY idx",
            )
            .get();
        final move = {
          for (final r in rows) r.read<int>('idx'): r.read<String>('move'),
        };
        final canonical = {
          for (final r in rows)
            r.read<int>('idx'): r.read<String?>('canonical_text'),
        };

        expect(move[0], 'pass_the_ocean');
        expect(canonical[0], 'pass the ocean');
        expect(move[1], 'form_short_waves');
        // Chained upgrade: v12 writes the (then-current) `form_a_short_wave`
        // id, which the v19 rename step then rewrites — so a long hop from
        // v11 lands on the NEW id and its new canonical text.
        expect(canonical[1], 'form short waves');
        expect(move[2], 'pass_the_ocean');
        expect(canonical[2], 'pass the ocean');
        expect(move[3], 'swing');

        await db.close();
      },
    );

    test('dance_fts is reindexed onto the new canonical text', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final row = await db
          .customSelect(
            "SELECT figures_text FROM dance_fts WHERE dance_id = 'dance-1'",
          )
          .getSingle();
      final figuresText = row.read<String>('figures_text');
      expect(figuresText, contains('pass the ocean'));
      expect(figuresText, contains('form short waves'));
      // The legacy phrasing must be gone from the index.
      expect(figuresText, isNot(contains('form an ocean wave')));

      // Full-text search resolves the dance under the NEW canonical phrase.
      expect(
        await repos.dances.search(const FullTextFilter('pass the ocean')),
        ['dance-1'],
      );

      await db.close();
    });

    test('an unmapped/unknown move falls through to the #358 safety net '
        'without data loss or a crash', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      // ensureMigrated must not throw even though `some_removed_move` is not in
      // the taxonomy — the rebuild renders it via the non-throwing raw-id path.
      await repos.ensureMigrated();

      final dance = await repos.dances.getById('dance-1');
      // The unknown-move figure is preserved verbatim (never dropped).
      expect(dance!.figures[4].move, 'some_removed_move');
      expect(dance.figures[4].params['beats'], 8);

      final rows = await db
          .customSelect(
            'SELECT canonical_text FROM dance_figures '
            "WHERE dance_id = 'dance-1' AND idx = 4",
          )
          .getSingle();
      // #358: an unknown move renders to its raw id rather than throwing.
      expect(rows.read<String?>('canonical_text'), 'some_removed_move');

      await db.close();
    });

    test('legacy figures present -> the upgrade schedules a rebuild', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      await db.customSelect('SELECT 1').get(); // force onUpgrade
      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(
        marker,
        isNotEmpty,
        reason: 'a form_an_ocean_wave rewrite must schedule a derived rebuild',
      );
      await db.close();
    });

    test('no legacy figures -> the upgrade does NOT schedule a rebuild', () async {
      // Rewrite the fixture (still at user_version 11) so it holds only a
      // non-ocean move, and stamp a sentinel into the derived table. v12's only
      // canonical-affecting change is the ocean-wave rewrite, so a DB that never
      // held the legacy move must upgrade without touching derived text.
      final raw = sqlite3.sqlite3.open(dbPath);
      raw.execute('UPDATE dances SET figures_json = ? WHERE id = ?', [
        '[{"schemaVersion":1,"move":"swing",'
            '"params":{"who":"partners","beats":16}}]',
        'dance-1',
      ]);
      raw.execute(
        "UPDATE dance_figures SET canonical_text = 'SENTINEL' "
        "WHERE dance_id = 'dance-1'",
      );
      expect(raw.select('PRAGMA user_version').first.values.first, 11);
      raw.close();

      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      // The rebuild marker was never written, so it is absent.
      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(marker, isEmpty, reason: 'no rewrite => no rebuild scheduled');

      // Proof no rebuild ran: the sentinel derived row survived untouched (a
      // rebuild would have regenerated canonical_text from figures_json).
      final rows = await db
          .customSelect(
            'SELECT canonical_text FROM dance_figures '
            "WHERE dance_id = 'dance-1'",
          )
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String?>('canonical_text'), 'SENTINEL');

      // The upgrade still completed to the current schema.
      final version = await db.customSelect('PRAGMA user_version').get();
      expect(version.single.data.values.first, db.schemaVersion);

      await db.close();
    });
  });

  group('v12 -> v13 upgrade (dance_links dance_id index)', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_v13_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Copy the checked-in v12 fixture to a temp path (opening mutates it).
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v12.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    test('the v12 fixture starts WITHOUT the dance_links index', () async {
      // Guards the migration's premise: the fixture is a genuine pre-v13 DB, so
      // the assertions below prove `onUpgrade` created the index (not the
      // fixture generator).
      final raw = sqlite3.sqlite3.open(dbPath);
      final before = raw
          .select(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND name='dance_links_dance_id'",
          )
          .toList();
      expect(before, isEmpty, reason: 'fixture must predate the v13 index');
      expect(raw.select('PRAGMA user_version').first.values.first, 12);
      raw.close();
    });

    test('creates the dance_links_dance_id index and bumps the schema '
        'version', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND name='dance_links_dance_id'",
          )
          .get();
      expect(
        indexes.map((r) => r.read<String>('name')),
        contains('dance_links_dance_id'),
      );

      // The index is actually usable: a dance_id lookup plans as an index seek,
      // not a full scan (the whole point of the migration).
      final plan = await db
          .customSelect(
            'EXPLAIN QUERY PLAN '
            "SELECT * FROM dance_links WHERE dance_id = 'dance-1'",
          )
          .get();
      final planText = plan
          .map((r) => r.data.values.map((v) => '$v').join(' '))
          .join(' | ');
      expect(
        planText,
        contains('USING INDEX dance_links_dance_id'),
        reason: 'dance_id lookups must seek by index after v13',
      );

      final version = await db.customSelect('PRAGMA user_version').get();
      expect(version.single.data.values.first, db.schemaVersion);

      await db.close();
    });

    test(
      'preserves dance_links rows and hydrates links through listAll',
      () async {
        final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
        final repos = CompendiumRepositories(db, contraTaxonomy);
        await repos.ensureMigrated();

        // The seeded link survived the migration byte-for-byte.
        final links = await db
            .customSelect(
              'SELECT id, dance_id, kind, url, label FROM dance_links '
              'ORDER BY id',
            )
            .get();
        expect(links, hasLength(1));
        expect(links.single.read<String>('id'), 'link-1');
        expect(links.single.read<String>('dance_id'), 'dance-1');
        expect(links.single.read<String>('url'), contains('ocean-motion'));

        // And it hydrates through the batched listAll link loader.
        final dances = await repos.dances.listAll();
        final withLink = dances.firstWhere((d) => d.id == 'dance-1');
        final withoutLink = dances.firstWhere((d) => d.id == 'dance-2');
        expect(withLink.links, hasLength(1));
        expect(withLink.links.single.id, 'link-1');
        expect(withLink.links.single.kind, LinkKind.video);
        expect(withoutLink.links, isEmpty);

        // The migrated database is referentially intact: no dangling FKs.
        final fkViolations = await db
            .customSelect('PRAGMA foreign_key_check')
            .get();
        expect(
          fkViolations,
          isEmpty,
          reason: 'the v13 migration must not leave any dangling foreign keys',
        );

        await db.close();
      },
    );

    test('is a pure index migration — schedules no derived rebuild', () async {
      // Stamp a sentinel into the derived table; a spurious rebuild would wipe
      // it. v13 touches no figure text, so the derived rows must survive.
      final raw = sqlite3.sqlite3.open(dbPath);
      raw.execute(
        "UPDATE dance_figures SET canonical_text = 'SENTINEL' "
        "WHERE dance_id = 'dance-1'",
      );
      expect(raw.select('PRAGMA user_version').first.values.first, 12);
      raw.close();

      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(
        marker,
        isEmpty,
        reason: 'an index-only migration rebuilds nothing',
      );

      final rows = await db
          .customSelect(
            'SELECT canonical_text FROM dance_figures '
            "WHERE dance_id = 'dance-1'",
          )
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String?>('canonical_text'), 'SENTINEL');

      await db.close();
    });
  });

  group('v13 -> v14 upgrade (venue entity)', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_v14_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Copy the checked-in v13 fixture to a temp path (opening mutates it).
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v13.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    test('drift schema version is current after upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db.customSelect('PRAGMA user_version').get();
      expect(rows.single.data.values.first, db.schemaVersion);
      expect(db.schemaVersion, 21);

      await db.close();
    });

    test('creates the venues table', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='venues'",
          )
          .get();
      expect(rows, hasLength(1));

      // The new table is usable end-to-end through its repository.
      await repos.venues.upsert(Venue(id: 'v1', name: 'Guiding Star Grange'));
      expect((await repos.venues.getById('v1'))!.name, 'Guiding Star Grange');

      await db.close();
    });

    test(
      'adds the programs.venue_id column, defaulting existing rows to null',
      () async {
        final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
        final repos = CompendiumRepositories(db, contraTaxonomy);
        await repos.ensureMigrated();

        final cols = await db.customSelect('PRAGMA table_info(programs)').get();
        final names = cols.map((r) => r.read<String>('name')).toList();
        expect(names, contains('venue_id'));

        // The pre-existing program carries a null venueId (no silent dangling ref).
        final program = await repos.programs.getById('prog-1');
        expect(program, isNotNull);
        expect(program!.venueId, isNull);

        await db.close();
      },
    );

    test('a program can be linked to a venue after the upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      await repos.venues.upsert(Venue(id: 'v1', name: 'Guiding Star Grange'));
      final program = await repos.programs.getById('prog-1');
      await repos.programs.update(program!.copyWith(venueId: 'v1'));

      final reloaded = await repos.programs.getById('prog-1');
      expect(reloaded!.venueId, 'v1');

      await db.close();
    });

    test('creates the programs.venue_id lookup index', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND tbl_name='programs'",
          )
          .get();
      final names = indexes.map((r) => r.read<String>('name')).toSet();
      expect(names, contains('programs_venue_id'));

      await db.close();
    });
  });

  group('v14 -> v15 upgrade (dance walkthrough, issue #370)', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_v15_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Copy the checked-in v14 fixture to a temp path (opening mutates it).
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v14.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    test('drift schema version is current after upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db.customSelect('PRAGMA user_version').get();
      expect(rows.single.data.values.first, db.schemaVersion);
      expect(db.schemaVersion, 21);

      await db.close();
    });

    test(
      'adds the dances.walkthrough column, defaulting existing rows to empty',
      () async {
        final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
        final repos = CompendiumRepositories(db, contraTaxonomy);
        await repos.ensureMigrated();

        final cols = await db.customSelect('PRAGMA table_info(dances)').get();
        final names = cols.map((r) => r.read<String>('name')).toList();
        expect(names, contains('walkthrough'));

        // The pre-existing dance loads with an empty walkthrough, and the
        // neighbouring free-text column is left untouched by the migration.
        final dance = await repos.dances.getById('dance-1');
        expect(dance, isNotNull);
        expect(dance!.walkthrough, '');
        expect(dance.callingNotes, 'No balances in this dance.');

        await db.close();
      },
    );

    test(
      'a walkthrough can be written and round-trips after the upgrade',
      () async {
        final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
        final repos = CompendiumRepositories(db, contraTaxonomy);
        await repos.ensureMigrated();

        final dance = await repos.dances.getById('dance-1');
        const walkthrough =
            'A1: Neighbours balance and swing. A2: Ladies chain across, '
            'then star left three-quarters. B1: Partners balance and swing.';
        await repos.dances.update(dance!.copyWith(walkthrough: walkthrough));

        final reloaded = await repos.dances.getById('dance-1');
        expect(reloaded!.walkthrough, walkthrough);

        await db.close();
      },
    );
  });

  group('v15 -> v16 upgrade (program_slots dance_id index, issue #627)', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_v16_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Copy the checked-in v15 fixture to a temp path (opening mutates it).
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v15.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    test('the v15 fixture starts WITHOUT the program_slots index', () async {
      // Guards the migration's premise: the fixture is a genuine pre-v16 DB,
      // so the assertions below prove `onUpgrade` created the index (not the
      // fixture generator).
      final raw = sqlite3.sqlite3.open(dbPath);
      final before = raw
          .select(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND name='program_slots_dance_id'",
          )
          .toList();
      expect(before, isEmpty, reason: 'fixture must predate the v16 index');
      expect(raw.select('PRAGMA user_version').first.values.first, 15);
      raw.close();
    });

    test('creates the program_slots_dance_id index and bumps the schema '
        'version', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND name='program_slots_dance_id'",
          )
          .get();
      expect(
        indexes.map((r) => r.read<String>('name')),
        contains('program_slots_dance_id'),
      );

      // The index is actually usable: a dance_id lookup plans as an index
      // seek, not a full scan (the whole point of the migration).
      final plan = await db
          .customSelect(
            'EXPLAIN QUERY PLAN '
            "SELECT * FROM program_slots WHERE dance_id = 'dance-1'",
          )
          .get();
      final planText = plan
          .map((r) => r.data.values.map((v) => '$v').join(' '))
          .join(' | ');
      expect(
        planText,
        contains('USING INDEX program_slots_dance_id'),
        reason: 'dance_id lookups must seek by index after v16',
      );

      final version = await db.customSelect('PRAGMA user_version').get();
      expect(version.single.data.values.first, db.schemaVersion);
      expect(db.schemaVersion, 21);

      await db.close();
    });

    test(
      'preserves program_slots rows and hydrates slots through listAll',
      () async {
        final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
        final repos = CompendiumRepositories(db, contraTaxonomy);
        await repos.ensureMigrated();

        // The seeded slot survived the migration byte-for-byte.
        final slots = await db
            .customSelect(
              'SELECT id, program_id, dance_id FROM program_slots '
              'ORDER BY id',
            )
            .get();
        expect(slots, hasLength(1));
        expect(slots.single.read<String>('id'), 'slot-1');
        expect(slots.single.read<String>('dance_id'), 'dance-1');

        // And it hydrates through the program repository.
        final program = await repos.programs.getById('prog-1');
        expect(program, isNotNull);
        expect(program!.slots.single.danceId, 'dance-1');

        // The migrated database is referentially intact: no dangling FKs.
        final fkViolations = await db
            .customSelect('PRAGMA foreign_key_check')
            .get();
        expect(
          fkViolations,
          isEmpty,
          reason: 'the v16 migration must not leave any dangling foreign keys',
        );

        await db.close();
      },
    );

    test('is a pure index migration — schedules no derived rebuild', () async {
      // Stamp a sentinel into the derived table; a spurious rebuild would wipe
      // it. v16 touches no figure text, so the derived rows must survive.
      final raw = sqlite3.sqlite3.open(dbPath);
      raw.execute(
        "UPDATE dance_figures SET canonical_text = 'SENTINEL' "
        "WHERE dance_id = 'dance-1'",
      );
      expect(raw.select('PRAGMA user_version').first.values.first, 15);
      raw.close();

      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(
        marker,
        isEmpty,
        reason: 'an index-only migration rebuilds nothing',
      );

      final rows = await db
          .customSelect(
            'SELECT canonical_text FROM dance_figures '
            "WHERE dance_id = 'dance-1'",
          )
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String?>('canonical_text'), 'SENTINEL');

      await db.close();
    });
  });

  group('v16 -> current upgrade (prose is NOT canonicalized, issue #613)', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp(
        'compendium_core_mig_v16_current_',
      );
      dbPath = p.join(dir.path, 'test.sqlite');
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v16.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    test('the v16 fixture starts at v16 with VERBATIM dialect prose', () async {
      final raw = sqlite3.sqlite3.open(dbPath);
      expect(raw.select('PRAGMA user_version').first.values.first, 16);
      final row = raw
          .select(
            "SELECT hook, calling_notes, walkthrough FROM dances "
            "WHERE id = 'dance-1'",
          )
          .first;
      expect(row['hook'], 'Larks and Robins balance the ring.');
      expect(
        row['calling_notes'],
        'Robins chain across, then Larks turn back.',
      );
      expect(row['walkthrough'], contains('Larks allemande left'));
      raw.close();
    });

    test('leaves hand-typed prose BYTE-IDENTICAL across the upgrade', () async {
      // v17 originally canonicalized these columns. It was reverted before
      // release because the substitution's always-on synonym set contains
      // ordinary English and proper nouns, so it corrupted dance titles, tune
      // names and people's names in long-form prose. Prose is now stored
      // exactly as the caller typed it, in every dialect.
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final version = await db.customSelect('PRAGMA user_version').get();
      expect(version.single.data.values.first, db.schemaVersion);

      final dance = await repos.dances.getById('dance-1');
      expect(dance, isNotNull);
      expect(dance!.hook, 'Larks and Robins balance the ring.');
      expect(dance.callingNotes, 'Robins chain across, then Larks turn back.');
      expect(dance.walkthrough, contains('Larks allemande left'));
      // No canonical role token was written into the caller's prose.
      expect(dance.hook, isNot(contains('role1')));
      expect(dance.hook, isNot(contains('role2')));

      await db.close();
    });

    test('leaves dance titles untouched', () async {
      // Titles are never routed through canonicalization on any path (editor,
      // import or migration). Pinned so the #613 class of bug cannot reach
      // them: "Lady of the Lake" must never become "role2 of the Lake".
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      expect((await repos.dances.getById('dance-1'))!.title, 'Ocean Motion');
      expect((await repos.dances.getById('dance-2'))!.title, 'Plain Sailing');

      await db.close();
    });

    test('prose with no role terms is untouched too', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final dance = await repos.dances.getById('dance-2');
      expect(dance!.hook, 'Balance and swing your partner.');
      expect(
        dance.walkthrough,
        'A1: Long lines forward and back. Star right once around.',
      );

      await db.close();
    });

    test('full-text search over prose behaves as it did before #613', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      // Ordinary prose is indexed and searchable verbatim.
      final byPlainProse = await repos.dances.search(
        const FullTextFilter('chain'),
      );
      expect(byPlainProse, contains('dance-1'));
      expect(
        await repos.dances.search(const FullTextFilter('balance')),
        contains('dance-1'),
      );

      // KNOWN LIMITATION, restored deliberately: the search path canonicalizes
      // the QUERY ('Robins' -> 'role2s') but prose is now stored verbatim, so a
      // role term typed into prose is not full-text matchable. This is the
      // pre-#613 behaviour — #613 never touched the search path (it changed
      // only the editor, the detail screen and the migration), so reverting it
      // restores this gap rather than introducing one. Tracked separately; the
      // fix is to match the query against both forms, not to rewrite the
      // caller's prose.
      expect(
        await repos.dances.search(
          const FullTextFilter('Robins'),
          dialect: Dialect.larksRobins,
        ),
        isEmpty,
      );

      // The index holds exactly what the caller typed.
      final fts = await db
          .customSelect("SELECT hook FROM dance_fts WHERE dance_id = 'dance-1'")
          .get();
      expect(fts.single.data['hook'], 'Larks and Robins balance the ring.');

      await db.close();
    });
  });

  test(
    'a fresh database has the program_slots.dance_id lookup index',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'compendium_core_slotidx_',
      );
      addTearDown(() => dir.delete(recursive: true));
      final dbPath = p.join(dir.path, 'test.sqlite');

      // onCreate builds every table; assert the raw program_slots dance_id
      // lookup index is among them so fresh installs match a migrated database.
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      await db.quickCheck();

      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND tbl_name='program_slots'",
          )
          .get();
      final names = indexes.map((r) => r.read<String>('name')).toSet();
      expect(names, contains('program_slots_dance_id'));

      await db.close();
    },
  );

  test('a fresh database has the programs.venue_id lookup index', () async {
    final dir = await Directory.systemTemp.createTemp(
      'compendium_core_venidx_',
    );
    addTearDown(() => dir.delete(recursive: true));
    final dbPath = p.join(dir.path, 'test.sqlite');

    // onCreate builds every table; assert the raw venue lookup index is among
    // them so fresh installs match a migrated database.
    final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
    await db.quickCheck();

    final indexes = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='index' "
          "AND tbl_name='programs'",
        )
        .get();
    final names = indexes.map((r) => r.read<String>('name')).toSet();
    expect(names, contains('programs_venue_id'));

    await db.close();
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

  test('refuses to migrate a database stamped by a newer schema version '
      '(downgrade belt-and-suspenders)', () async {
    final dir = await Directory.systemTemp.createTemp('compendium_core_');
    addTearDown(() => dir.delete(recursive: true));
    final dbPath = p.join(dir.path, 'test.sqlite');

    // 1. Create a normal current-version database.
    final first = CompendiumDatabase(NativeDatabase(File(dbPath)));
    await first.quickCheck();
    await first.close();

    // 2. Stamp its user_version to a *future* version, as if a newer build
    // wrote it. drift is forward-only with no onDowngrade; it still invokes
    // onUpgrade whenever the stored version differs, so without the guard it
    // would silently stamp the version back down.
    final raw = sqlite3.sqlite3.open(dbPath);
    raw.execute('PRAGMA user_version = ${kCompendiumSchemaVersion + 1}');
    raw.close();

    // 3. Reopening must refuse: onUpgrade(from > to) throws, propagating out
    // of the first query rather than migrating down.
    final second = CompendiumDatabase(NativeDatabase(File(dbPath)));
    addTearDown(() async {
      try {
        await second.close();
      } on Object {
        // A failed open can leave close() unhappy; ignore during teardown.
      }
    });
    await expectLater(
      second.customSelect('SELECT 1').get(),
      throwsA(isA<StateError>()),
    );
  });

  group('purge-corruption repair (#429/#466)', () {
    test(
      'ensureMigrated removes legacy corrupt rows once and marks it done',
      () async {
        final db = CompendiumDatabase(NativeDatabase.memory());
        final repos = CompendiumRepositories(db, contraTaxonomy);
        addTearDown(db.close);

        // A healthy dance + a program whose slot references it, plus a VALID
        // owner->target relatedDance link (both dances present) that the
        // destructive repair sweep must PRESERVE.
        await repos.dances.create(
          Dance(
            id: 'd-target',
            title: 'Target Dance',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );
        await repos.dances.create(
          Dance(
            id: 'd-ok',
            title: 'Good Dance',
            links: [
              DanceLink(
                id: 'l-good',
                kind: LinkKind.relatedDance,
                targetDanceId: 'd-target',
              ),
            ],
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );
        await repos.programs.create(
          Program(
            id: 'p1',
            title: 'Set',
            slots: [ProgramSlot(id: 's-ok', position: 0, danceId: 'd-ok')],
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );

        // Inject the two row shapes a pre-fix hard purge would have left: a
        // (danceId, text)-both-null slot (#429) and a relatedDance link whose
        // target was SET NULL (#466). Written raw so they bypass the domain
        // guards, exactly like a legacy on-disk database.
        await db.customStatement(
          'INSERT INTO program_slots (id, program_id, position, dance_id, '
          'text, is_alt) VALUES (?, ?, ?, NULL, NULL, 0)',
          ['s-bad', 'p1', 1],
        );
        await db.customStatement(
          'INSERT INTO dance_links (id, dance_id, kind, target_dance_id) '
          'VALUES (?, ?, ?, NULL)',
          ['l-bad', 'd-ok', LinkKind.relatedDance.name],
        );

        await repos.ensureMigrated();

        // The corrupt rows are gone; the healthy rows — including the VALID
        // relatedDance link — survive untouched (the sweep is not over-eager).
        final slots = await db
            .customSelect('SELECT id FROM program_slots ORDER BY id')
            .get();
        expect(slots.map((r) => r.read<String>('id')), ['s-ok']);
        final links = await db
            .customSelect('SELECT id FROM dance_links ORDER BY id')
            .get();
        expect(links.map((r) => r.read<String>('id')), ['l-good']);

        // Loads succeed after the repair, and the valid link still hydrates.
        final programs = await repos.programs.listAll();
        expect(programs.single.slots.single.danceId, 'd-ok');
        final loadedDances = await repos.dances.listAll();
        expect(loadedDances, hasLength(2));
        final owner = loadedDances.firstWhere((d) => d.id == 'd-ok');
        expect(owner.links.single.id, 'l-good');
        expect(owner.links.single.targetDanceId, 'd-target');

        // The database is referentially clean and its FTS index is a perfect
        // 1:1 mirror of `dances`. We compare the ORDERED id multisets (not just
        // row counts): dance_fts.dance_id is an unconstrained FTS column, so a
        // count-only check would pass even if one dance were missing while
        // another had a duplicate row. Comparing sorted id lists catches
        // missing, orphaned, and duplicated FTS rows alike.
        final fkViolations = await db
            .customSelect('PRAGMA foreign_key_check')
            .get();
        expect(fkViolations, isEmpty, reason: 'no dangling FKs after repair');
        final ftsIds =
            (await db
                    .customSelect(
                      'SELECT dance_id FROM dance_fts ORDER BY dance_id',
                    )
                    .get())
                .map((r) => r.read<String>('dance_id'))
                .toList();
        final danceIds =
            (await db.customSelect('SELECT id FROM dances ORDER BY id').get())
                .map((r) => r.read<String>('id'))
                .toList();
        expect(
          ftsIds,
          danceIds,
          reason: 'dance_fts must be an exact 1:1 mirror of dances',
        );

        // The one-shot marker is durably recorded.
        final marker = await db
            .customSelect(
              'SELECT value_json FROM settings WHERE key = ?',
              variables: [Variable.withString(purgeCorruptionRepairDoneKey)],
            )
            .get();
        expect(marker, hasLength(1));
      },
    );

    test('skips the repair when the done-marker is already set', () async {
      final db = CompendiumDatabase(NativeDatabase.memory());
      final repos = CompendiumRepositories(db, contraTaxonomy);
      addTearDown(db.close);

      // Pre-stamp the marker (this first statement also triggers onCreate), so
      // a later corrupt row must be left alone — the sweep runs at most once.
      await db.customStatement(
        'INSERT OR REPLACE INTO settings (key, value_json) VALUES (?, ?)',
        [purgeCorruptionRepairDoneKey, 'true'],
      );
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Set',
          slots: [ProgramSlot(id: 's-ok', position: 0, text: 'Waltz')],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      await db.customStatement(
        'INSERT INTO program_slots (id, program_id, position, dance_id, text, '
        'is_alt) VALUES (?, ?, ?, NULL, NULL, 0)',
        ['s-bad', 'p1', 1],
      );

      await repos.ensureMigrated();

      final slots = await db
          .customSelect('SELECT id FROM program_slots ORDER BY id')
          .get();
      expect(slots.map((r) => r.read<String>('id')), ['s-bad', 's-ok']);
    });
  });

  group('v17 -> v18 upgrade (issue #295 allemande_orbit -> meanwhile)', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_v18_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Copy the checked-in v17 fixture to a temp path (opening mutates it).
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v17.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    test('drift schema version is current after upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db.customSelect('PRAGMA user_version').get();
      expect(rows.single.data.values.first, db.schemaVersion);

      await db.close();
    });

    test('rewrites stored allemande_orbit figures onto meanwhile[allemande, '
        'orbit], deriving direction + orbiting pair', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final dance = await repos.dances.getById('dance-1');
      expect(dance, isNotNull);
      final figures = dance!.figures;
      expect(figures, hasLength(5));

      // [0] fully-specified + note/progression -> meanwhile carrying beats 8,
      // note, and progression; sub-figures built from the fused params.
      expect(figures[0].isMeanwhile, isTrue);
      expect(figures[0].beats, 8);
      expect(figures[0].note, 'scoop');
      expect(figures[0].progression, isTrue);
      final s0 = figures[0].subFigures;
      expect(s0.map((f) => f.move), ['allemande', 'orbit']);
      expect(s0[0].params['who'], 'ones');
      expect(s0[0].params['hand'], 'left');
      expect(s0[0].params['turn'], 1.5);
      expect(s0[0].params.containsKey('beats'), isFalse);
      expect(s0[1].params['who'], 'twos'); // invert(ones)
      expect(s0[1].params['turn'], 'clockwise'); // opposite of left
      expect(s0[1].params['amount'], 0.5);

      // [1] hand:right -> orbit direction counterclockwise, orbiting pair
      // role2s (invert of role1s); absent inner/outer filled from fused
      // defaults (1.5 / 0.5).
      expect(figures[1].isMeanwhile, isTrue);
      final s1 = figures[1].subFigures;
      expect(s1[0].params['who'], 'role1s');
      expect(s1[0].params['hand'], 'right');
      expect(s1[0].params['turn'], 1.5);
      expect(s1[1].params['who'], 'role2s');
      expect(s1[1].params['turn'], 'counterclockwise');
      expect(s1[1].params['amount'], 0.5);

      // [2] params-less -> all fused defaults apply.
      expect(figures[2].isMeanwhile, isTrue);
      expect(figures[2].beats, 8);
      final s2 = figures[2].subFigures;
      expect(s2[0].params['who'], 'ones');
      expect(s2[0].params['hand'], 'left');
      expect(s2[0].params['turn'], 1.5);
      expect(s2[1].params['who'], 'twos');
      expect(s2[1].params['turn'], 'clockwise');
      expect(s2[1].params['amount'], 0.5);

      // [3] control swing: byte-identical.
      expect(figures[3].move, 'swing');
      expect(figures[3].params['who'], 'partners');
      expect(figures[3].params['beats'], 16);

      // [4] wildcard hand: unmappable direction -> left byte-identical (the
      // fused move is retained and rides the #358 unknown-move path).
      expect(figures[4].isMeanwhile, isFalse);
      expect(figures[4].move, 'allemande_orbit');
      expect(figures[4].params['hand'], '*');

      await db.close();
    });

    test('rebuilt dance_figures + FTS reflect the new orbit figures', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      // The derived-rebuild marker is cleared once the rebuild completes.
      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(
        marker.isEmpty || marker.single.data['value_json'] != 'true',
        isTrue,
        reason: 'the derived rebuild must clear its marker',
      );

      // The rewritten container's canonical text carries the orbit side, so a
      // full-text search on "orbit" finds the dance.
      final hits = await repos.dances.search(const FullTextFilter('orbit'));
      expect(hits, contains('dance-1'));

      await db.close();
    });
  });

  group('v18 -> v19 upgrade (issue #295 form_a_short_wave rename)', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_v19_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Copy the checked-in v18 fixture to a temp path (opening mutates it).
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v18.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    test('drift schema version is current after upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db.customSelect('PRAGMA user_version').get();
      expect(rows.single.data.values.first, db.schemaVersion);

      await db.close();
    });

    test('renames stored form_a_short_wave figures, preserving everything '
        'else byte-for-byte', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final dance = await repos.dances.getById('dance-1');
      expect(dance, isNotNull);
      final figures = dance!.figures;
      expect(figures, hasLength(5));

      // [0] fully-specified: only the move id changes.
      expect(figures[0].move, 'form_short_waves');
      expect(figures[0].params['dir'], 'rightDiagonal');
      expect(figures[0].params['balance'], isTrue);
      expect(figures[0].params['center'], 'role1s');
      expect(figures[0].params['centerHand'], 'left');
      expect(figures[0].params['sides'], 'partners');
      expect(figures[0].params['beats'], 8);
      expect(figures[0].note, 'ladies in the centre');
      expect(figures[0].progression, isTrue);

      // [1] params-less: renamed without inventing params.
      expect(figures[1].move, 'form_short_waves');
      expect(figures[1].params.keys, isNot(contains('center')));

      // [2] the NESTED side of a meanwhile container is renamed too.
      expect(figures[2].isMeanwhile, isTrue);
      final sides = figures[2].subFigures;
      expect(sides.map((f) => f.move), ['form_short_waves', 'swing']);
      expect(sides[0].params['centerHand'], 'left');

      // [3] control swing: byte-identical.
      expect(figures[3].move, 'swing');
      expect(figures[3].params['who'], 'partners');
      expect(figures[3].params['beats'], 16);

      // [4] an unknown move id is untouched and rides the #358 fallback.
      expect(figures[4].move, 'some_removed_move');
      expect(figures[4].params['beats'], 4);

      await db.close();
    });

    test('the old move id is gone from every stored blob', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db
          .customSelect('SELECT figures_json FROM dances')
          .get();
      for (final row in rows) {
        expect(
          row.read<String>('figures_json'),
          isNot(contains('form_a_short_wave')),
        );
      }

      await db.close();
    });

    test('rebuilt dance_figures + FTS reflect the renamed move', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      // The derived-rebuild marker is cleared once the rebuild completes.
      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(
        marker.isEmpty || marker.single.data['value_json'] != 'true',
        isTrue,
        reason: 'the derived rebuild must clear its marker',
      );

      // The renamed move's canonical text is "form short waves", so a
      // full-text search on it finds the dance.
      final hits = await repos.dances.search(
        const FullTextFilter('short waves'),
      );
      expect(hits, contains('dance-1'));

      await db.close();
    });
  });

  group('v19 -> v20 upgrade (gate merge: gate + rotation_gate -> gate)', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_v20_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Copy the checked-in v19 fixture to a temp path (opening mutates it).
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v19.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    test('drift schema version is current after upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db.customSelect('PRAGMA user_version').get();
      expect(rows.single.data.values.first, db.schemaVersion);

      await db.close();
    });

    test('rewrites both legacy gate shapes onto the merged move, mapping '
        "rotation_gate's who to `pair` and never to `who`", () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final dance = await repos.dances.getById('dance-1');
      expect(dance, isNotNull);
      final figures = dance!.figures;
      expect(figures, hasLength(6));

      // [0] fully-specified rotation_gate + note/progression. The TCB subject
      // MUST land on `pair` — writing it to `who` would reinterpret it as
      // ContraDB's "the side that backs up".
      expect(figures[0].move, 'gate');
      expect(figures[0].params['pair'], 'nextNeighbors');
      expect(figures[0].params.containsKey('who'), isFalse);
      expect(figures[0].params['direction'], 'counterclockwise');
      expect(figures[0].params['turn'], 0.5);
      expect(figures[0].params['beats'], 4);
      expect(figures[0].note, 'ones forward');
      expect(figures[0].progression, isTrue);

      // [1] params-less rotation_gate: the RETIRED move's defaults are
      // materialized, because the merged move defaults every slot to
      // `unspecified`.
      expect(figures[1].move, 'gate');
      expect(figures[1].params['pair'], 'neighbors');
      expect(figures[1].params['direction'], 'counterclockwise');
      expect(figures[1].params['turn'], 0.5);

      // [2] fully-specified legacy ContraDB gate: same slots, same meaning —
      // left byte-identical (`face` was already the ENDING facing).
      expect(figures[2].move, 'gate');
      expect(figures[2].params['who'], 'ones');
      expect(figures[2].params['whom'], 'neighbors');
      expect(figures[2].params['face'], 'down');
      expect(figures[2].params['beats'], 8);
      expect(figures[2].params.containsKey('pair'), isFalse);

      // [3] beats-only legacy gate: the retired move's defaults materialize.
      expect(figures[3].move, 'gate');
      expect(figures[3].params['who'], 'ones');
      expect(figures[3].params['whom'], 'neighbors');
      expect(figures[3].params['face'], 'up');
      expect(figures[3].params['beats'], 8);

      // [4] meanwhile container: the migration recurses into `params.figures`
      // and preserves the container's shared beats and the untouched side.
      expect(figures[4].isMeanwhile, isTrue);
      expect(figures[4].beats, 4);
      final sides = figures[4].subFigures;
      expect(sides.map((f) => f.move), ['gate', 'swing']);
      expect(sides[0].params['pair'], 'partners');
      expect(sides[0].params['direction'], 'clockwise');
      expect(sides[0].params['turn'], 0.25);
      expect(sides[1].params['who'], 'neighbors');

      // [5] control swing: byte-identical.
      expect(figures[5].move, 'swing');
      expect(figures[5].params['who'], 'partners');
      expect(figures[5].params['beats'], 16);

      await db.close();
    });

    test('beat totals survive the rewrite exactly', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final dance = (await repos.dances.getById('dance-1'))!;
      // 4 (rotation_gate) + 8 (default) + 8 + 8 + 4 (meanwhile) + 16 (swing).
      expect(
        dance.figures
            .map((f) => contraTaxonomy.effectiveParams(f)['beats'])
            .toList(),
        [4, 8, 8, 8, 4, 16],
      );

      await db.close();
    });

    // The failure mode a version collision would cause: a user who lands at a
    // stored `user_version` at or above the guard never runs the step, so their
    // stored figures keep pointing at move ids the taxonomy no longer has and
    // fall silently through the #358 unknown-move path. `from < 20` must fire
    // for EVERY entry point below 20, whichever earlier steps ran first.
    //
    // Schema 17..20 are structurally identical (all three steps are data
    // rewrites that add no column or table), so stamping the fixture down is a
    // faithful simulation of a user arriving from that version — including the
    // concurrent schema-19 wave-move rename, which this fixture holds no
    // figures for and which therefore no-ops over it.
    for (final from in [17, 18, 19]) {
      test(
        'the gate rewrite still runs for a database arriving from v$from',
        () async {
          final raw = sqlite3.sqlite3.open(dbPath);
          raw.execute('PRAGMA user_version = $from');
          raw.close();

          final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
          final repos = CompendiumRepositories(db, contraTaxonomy);
          await repos.ensureMigrated();

          final version = await db.customSelect('PRAGMA user_version').get();
          expect(version.single.data.values.first, 21, reason: 'from v$from');

          final figures = (await repos.dances.getById('dance-1'))!.figures;
          // Both legacy shapes landed on the merged move, with the TCB subject
          // on `pair` — not on `who`.
          expect(figures[0].move, 'gate', reason: 'from v$from');
          expect(
            figures[0].params['pair'],
            'nextNeighbors',
            reason: 'from v$from',
          );
          expect(figures[2].move, 'gate', reason: 'from v$from');
          expect(figures[2].params['who'], 'ones', reason: 'from v$from');
          // Nothing anywhere still references the retired move id.
          final moves = await db
              .customSelect(
                "SELECT DISTINCT move FROM dance_figures WHERE dance_id = 'dance-1'",
              )
              .get();
          expect(
            moves.map((r) => r.data['move']).toSet(),
            isNot(contains('rotation_gate')),
            reason: 'from v$from',
          );
          // Beat totals are untouched by however many steps ran.
          expect(
            figures
                .map((f) => contraTaxonomy.effectiveParams(f)['beats'])
                .toList(),
            [4, 8, 8, 8, 4, 16],
            reason: 'from v$from',
          );

          await db.close();
        },
      );
    }

    test('rebuilt dance_figures + FTS reflect the merged move', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      // The derived-rebuild marker is cleared once the rebuild completes.
      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(
        marker.isEmpty || marker.single.data['value_json'] != 'true',
        isTrue,
        reason: 'the derived rebuild must clear its marker',
      );

      // Every rewritten figure indexes under the single merged move id, so the
      // retired `rotation_gate` id is gone from the derived index.
      final moves = await db
          .customSelect(
            "SELECT DISTINCT move FROM dance_figures WHERE dance_id = 'dance-1'",
          )
          .get();
      final moveIds = moves.map((r) => r.data['move']).toSet();
      expect(moveIds, contains('gate'));
      expect(moveIds, isNot(contains('rotation_gate')));

      // The concrete consequence, through the API that actually reads those
      // columns: `danceIdsWithFigure` queries `move` + `params_json`, so if the
      // migration skipped its derived rebuild, structured search would still
      // match the RETIRED id and miss every migrated figure. This is why the
      // rebuild is owed even though `dance_figures` also carries canonical text
      // — a migration that changed only the move id would owe one too.
      expect(
        await repos.dances.danceIdsWithFigure('gate'),
        contains('dance-1'),
      );
      expect(await repos.dances.danceIdsWithFigure('rotation_gate'), isEmpty);
      // The TCB subject is searchable in its NEW slot, and not in the old one.
      expect(
        await repos.dances.danceIdsWithFigure(
          'gate',
          paramKey: 'pair',
          paramJsonValue: '"nextNeighbors"',
        ),
        contains('dance-1'),
      );

      final hits = await repos.dances.search(const FullTextFilter('gate'));
      expect(hits, contains('dance-1'));

      await db.close();
    });
  });

  group('v20 -> v21 upgrade (drop raw_payload columns and the snapshots '
      'table)', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_v21_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Copy the checked-in v20 fixture to a temp path (opening mutates it).
      final fixture = File(
        p.join(
          Directory.current.path,
          'test',
          'storage',
          'fixtures',
          'v20.sqlite',
        ),
      );
      await fixture.copy(dbPath);
    });

    tearDown(() => dir.delete(recursive: true));

    Future<List<String>> columnsOf(CompendiumDatabase db, String table) async {
      final rows = await db
          .customSelect("SELECT name FROM pragma_table_info('$table')")
          .get();
      return [for (final r in rows) r.read<String>('name')];
    }

    test('drift schema version is current after upgrade', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final rows = await db.customSelect('PRAGMA user_version').get();
      expect(rows.single.data.values.first, db.schemaVersion);

      await db.close();
    });

    test('drops raw_payload from both provenance tables', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      expect(await columnsOf(db, 'provenance'), isNot(contains('raw_payload')));
      expect(
        await columnsOf(db, 'program_provenance'),
        isNot(contains('raw_payload')),
      );

      await db.close();
    });

    test('preserves every sibling provenance column and its value', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      // The rebuild copies surviving columns across by name. A botched column
      // list would silently null one of these rather than fail loudly, so
      // every one is asserted by value, not merely by presence.
      final prov = await db
          .customSelect(
            'SELECT * FROM provenance WHERE dance_id = ?',
            variables: [Variable<String>('dance-1')],
          )
          .getSingle();
      expect(prov.read<String>('source'), 'contradb');
      expect(prov.read<String>('external_id'), '2443');
      expect(prov.read<String>('permission'), 'CC BY-NC-SA 3.0');
      expect(prov.read<String>('license'), 'CC BY-NC-SA 3.0');
      expect(prov.read<String>('source_version'), 'contradb-2026-01');
      // `imported_at` is a sibling column too, and the only non-text one — a
      // rebuild that mis-copied or nulled the timestamp would otherwise pass
      // every assertion above. Stored as unix seconds (2026-01-01T00:00:00Z).
      expect(prov.read<int>('imported_at'), 1767225600);

      final progProv = await db
          .customSelect(
            'SELECT * FROM program_provenance WHERE program_id = ?',
            variables: [Variable<String>('program-1')],
          )
          .getSingle();
      expect(progProv.read<String>('source'), 'callersCompanion');
      expect(progProv.read<String>('external_id'), 'set-42');
      expect(progProv.read<String>('permission'), 'personal use');
      expect(progProv.read<String>('license'), 'unlicensed');
      expect(progProv.read<String>('source_version'), 'cc-usr-1');
      expect(progProv.read<int>('imported_at'), 1767225600);

      await db.close();
    });

    test(
      'the rebuilt provenance row still loads through the repository',
      () async {
        final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
        final repos = CompendiumRepositories(db, contraTaxonomy);
        await repos.ensureMigrated();

        // A table rebuild that lost the primary key or the FK would still pass
        // the column assertions above; loading the dance exercises both.
        final dance = await repos.dances.getById('dance-1');
        expect(dance, isNotNull);
        expect(dance!.provenance, isNotNull);
        expect(dance.provenance!.externalId, '2443');
        expect(dance.provenance!.source, ProvenanceSource.contradb);
        expect(dance.provenance!.importedAt, DateTime.utc(2026));

        await db.close();
      },
    );

    test('drops the snapshots table', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name = 'snapshots'",
          )
          .get();
      expect(tables, isEmpty);

      await db.close();
    });

    test('leaves tags.color intact', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      // #782 covered both the snapshots table and tags.color; only the former
      // was dropped, because tag colour-coding is still wanted (#786). This
      // pins that decision: a future cleanup that takes the colour with it
      // fails here rather than silently discarding user data.
      expect(await columnsOf(db, 'tags'), contains('color'));
      final tag = await db
          .customSelect(
            'SELECT color FROM tags WHERE id = ?',
            variables: [Variable<String>('tag-1')],
          )
          .getSingle();
      expect(tag.read<int>('color'), 0xFF2196F3);

      await db.close();
    });

    test(
      'a restored pre-v21 archive keeps its dance and drops the payload',
      () async {
        final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
        final repos = CompendiumRepositories(db, contraTaxonomy);
        await repos.ensureMigrated();

        // Archives written before v21 carry a `rawPayload` key inside each
        // dance's provenance. Rather than hand-rolling that JSON (which risks
        // testing a shape the encoder never produced), encode a real archive
        // through the live encoder and inject the legacy key back into it.
        final encoded = encodeArchive(
          CompendiumArchive(
            exportedAt: DateTime.utc(2026),
            dances: [
              Dance(
                id: 'legacy-1',
                title: 'Legacy Import',
                figures: [
                  Figure(
                    move: 'swing',
                    params: const {'who': 'partners', 'beats': 16},
                  ),
                ],
                createdAt: DateTime.utc(2026),
                updatedAt: DateTime.utc(2026),
                provenance: Provenance(
                  source: ProvenanceSource.contradb,
                  externalId: '999',
                  importedAt: DateTime.utc(2026),
                ),
              ),
            ],
          ),
        );

        final asMap = jsonDecode(encoded) as Map<String, Object?>;
        final danceList = asMap['dances']! as List<Object?>;
        final provenance =
            (danceList.single as Map<String, Object?>)['provenance']!
                as Map<String, Object?>;
        provenance['rawPayload'] = '<html>dropped in v21</html>';
        expect(
          provenance.containsKey('rawPayload'),
          isTrue,
          reason:
              'the legacy key must actually be present, or this test is '
              'asserting nothing',
        );

        // `decodeArchive` ignores unknown keys, so the dance restores intact and
        // the payload is simply not read back — no special-casing, no failure.
        final restored = decodeArchive(jsonEncode(asMap));

        expect(restored.errors, isEmpty);
        expect(restored.archive.dances, hasLength(1));
        expect(restored.archive.dances.single.provenance!.externalId, '999');

        await db.close();
      },
    );
  });
}

/// A [CompendiumRepositories] whose derived-index rebuild throws on its first
/// invocation and succeeds thereafter — used to prove [ensureMigrated] retries
/// after a transient failure rather than caching it.
class _FailingOnceRepositories extends CompendiumRepositories {
  _FailingOnceRepositories(super.db, super.taxonomy);

  int rebuildAttempts = 0;

  @override
  Future<void> runDerivedRebuild({
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    rebuildAttempts++;
    if (rebuildAttempts == 1) {
      throw StateError('injected rebuild failure');
    }
    await super.runDerivedRebuild(onProgress: onProgress);
  }
}
