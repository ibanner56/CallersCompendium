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

      // passThru:false -> form_a_short_wave; other params intact.
      expect(figures[1].move, 'form_a_short_wave');
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
        expect(move[1], 'form_a_short_wave');
        expect(canonical[1], 'form a wave');
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
      expect(figuresText, contains('form a wave'));
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

        // A healthy dance + a program whose slot references it.
        await repos.dances.create(
          Dance(
            id: 'd-ok',
            title: 'Good Dance',
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

        // The corrupt rows are gone; the healthy rows survive untouched.
        final slots = await db
            .customSelect('SELECT id FROM program_slots ORDER BY id')
            .get();
        expect(slots.map((r) => r.read<String>('id')), ['s-ok']);
        final links = await db.customSelect('SELECT id FROM dance_links').get();
        expect(links, isEmpty);

        // Loads succeed after the repair.
        final programs = await repos.programs.listAll();
        expect(programs.single.slots.single.danceId, 'd-ok');
        expect(await repos.dances.listAll(), hasLength(1));

        // The database is referentially clean and its FTS index is complete.
        final fkViolations = await db
            .customSelect('PRAGMA foreign_key_check')
            .get();
        expect(fkViolations, isEmpty, reason: 'no dangling FKs after repair');
        final ftsCount =
            (await db
                    .customSelect('SELECT COUNT(*) AS c FROM dance_fts')
                    .getSingle())
                .read<int>('c');
        final danceCount =
            (await db
                    .customSelect('SELECT COUNT(*) AS c FROM dances')
                    .getSingle())
                .read<int>('c');
        expect(
          ftsCount,
          danceCount,
          reason: 'every dance must have exactly one dance_fts row',
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
