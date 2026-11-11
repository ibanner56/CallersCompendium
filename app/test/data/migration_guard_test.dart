import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:compendium_app/src/data/migration_guard.dart';
import 'package:compendium_app/src/data/app_database.dart' show kDatabaseName;
import 'package:compendium_app/src/data/single_instance_guard.dart'
    show InstanceLockHandle, InstanceLockPrimitive;
import 'package:compendium_core/compendium_core.dart'
    show
        CompendiumDatabase,
        CompendiumRepositories,
        SettingsRepository,
        applyCompendiumSqliteSetup,
        chainHandBackfillDoneKey,
        purgeCorruptionRepairDoneKey,
        contraTaxonomy,
        kCompendiumSchemaVersion,
        kMinSupportedSchemaVersion;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

/// Creates a SQLite fixture at [path] stamped with [userVersion], optionally
/// seeding a row so copy-fidelity can be asserted.
void _createFixture(
  String path, {
  required int userVersion,
  String? seedValue,
}) {
  final db = sql.sqlite3.open(path);
  try {
    db.execute('CREATE TABLE IF NOT EXISTS t (id INTEGER PRIMARY KEY, v TEXT)');
    if (seedValue != null) {
      db.execute('INSERT INTO t (v) VALUES (?)', [seedValue]);
    }
    db.execute('PRAGMA user_version = $userVersion');
  } finally {
    db.close();
  }
}

/// A relocation lock some other process holds for as long as the test runs.
class _HeldElsewhere implements InstanceLockPrimitive {
  int attempts = 0;

  @override
  Future<InstanceLockHandle?> tryAcquire(File lockFile) async {
    attempts++;
    return null;
  }
}

/// Grants the relocation lock, after running [whileWaiting]: what another
/// process did while this one waited for the lock.
class _GrantedAfter implements InstanceLockPrimitive {
  _GrantedAfter(this.whileWaiting);

  final void Function() whileWaiting;

  @override
  Future<InstanceLockHandle?> tryAcquire(File lockFile) async {
    whileWaiting();
    return _NoopHandle();
  }
}

class _NoopHandle implements InstanceLockHandle {
  @override
  Future<void> release() async {}
}

void main() {
  late Directory dir;
  late Directory snapshotDir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mig_guard_');
    snapshotDir = Directory(p.join(dir.path, kDatabaseBackupsDirName));
  });
  tearDown(() => dir.delete(recursive: true));

  test(
    'refuses to open a DB stamped by a newer build, leaving it untouched',
    () async {
      final dbFile = File(p.join(dir.path, 'compendium.sqlite'));
      final newer = kCompendiumSchemaVersion + 1;
      _createFixture(dbFile.path, userVersion: newer, seedValue: 'keep me');

      await expectLater(
        runMigrationPreflight(
          dbFile: dbFile,
          snapshotDir: snapshotDir,
          runningSchemaVersion: kCompendiumSchemaVersion,
          repairMarkers: const {},
        ),
        throwsA(isA<DatabaseDowngradeError>()),
      );

      // The file is neither migrated nor corrupted: version and data survive.
      expect(readUserVersion(dbFile.path), newer);
      final db = sql.sqlite3.open(dbFile.path);
      expect(db.select('SELECT v FROM t').single['v'], 'keep me');
      db.close();
      // A refused downgrade never snapshots.
      expect(snapshotDir.existsSync(), isFalse);
    },
  );

  test('snapshots the DB before a pending upgrade migration', () async {
    final dbFile = File(p.join(dir.path, 'compendium.sqlite'));
    final older = kCompendiumSchemaVersion - 1;
    _createFixture(dbFile.path, userVersion: older, seedValue: 'pre-migrate');

    await runMigrationPreflight(
      dbFile: dbFile,
      snapshotDir: snapshotDir,
      runningSchemaVersion: kCompendiumSchemaVersion,
      repairMarkers: const {},
    );

    final snapshots = snapshotDir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).endsWith('.sqlite.bak'))
        .toList();
    expect(snapshots, hasLength(1));
    final snap = snapshots.single;
    expect(p.basename(snap.path), startsWith('compendium.pre-v$older-'));

    // The snapshot captures the exact pre-migration state.
    expect(readUserVersion(snap.path), older);
    final sdb = sql.sqlite3.open(snap.path);
    expect(sdb.select('SELECT v FROM t').single['v'], 'pre-migrate');
    sdb.close();

    // The original file is left as-is for drift to migrate in place.
    expect(readUserVersion(dbFile.path), older);
  });

  test('retains only the newest N pre-migration snapshots', () async {
    final dbFile = File(p.join(dir.path, 'compendium.sqlite'));
    _createFixture(dbFile.path, userVersion: kCompendiumSchemaVersion - 1);

    const retain = 3;
    var tick = DateTime.utc(2026, 1, 1);
    for (var i = 0; i < retain + 2; i++) {
      await runMigrationPreflight(
        dbFile: dbFile,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: const {},
        retain: retain,
        now: () => tick = tick.add(const Duration(seconds: 1)),
      );
    }

    final snapshots = snapshotDir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).endsWith('.sqlite.bak'))
        .toList();
    expect(snapshots, hasLength(retain));
  });

  test('disambiguates snapshots that resolve to the same timestamp', () async {
    final dbFile = File(p.join(dir.path, 'compendium.sqlite'));
    final older = kCompendiumSchemaVersion - 1;
    _createFixture(dbFile.path, userVersion: older);

    // Pin the clock so both runs would otherwise produce an identical name.
    final fixed = DateTime.utc(2026, 6, 1, 12, 30, 0);
    for (var i = 0; i < 2; i++) {
      await runMigrationPreflight(
        dbFile: dbFile,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: const {},
        now: () => fixed,
      );
    }

    final names = snapshotDir
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .where((n) => n.endsWith('.sqlite.bak'))
        .toSet();
    // Both snapshots are retained under distinct names (no silent overwrite).
    expect(names, hasLength(2));
  });

  test('a checkpoint result counts as complete only when every WAL frame is '
      'in the main file', () {
    // Finished, or not a WAL database.
    expect(
      checkpointLeftMainFileComplete(busy: 0, log: 3, checkpointed: 3),
      isTrue,
    );
    expect(
      checkpointLeftMainFileComplete(busy: 0, log: -1, checkpointed: -1),
      isTrue,
    );
    // Only the WAL's reset was blocked: every frame was copied back.
    expect(
      checkpointLeftMainFileComplete(busy: 1, log: 3, checkpointed: 3),
      isTrue,
    );
    // A reader behind the newest commit stopped it short.
    expect(
      checkpointLeftMainFileComplete(busy: 1, log: 3, checkpointed: 2),
      isFalse,
    );
    // It could not run at all: nothing is known to be copied.
    expect(
      checkpointLeftMainFileComplete(busy: 1, log: -1, checkpointed: -1),
      isFalse,
    );
  });

  group('a reader that pins the WAL during the snapshot', () {
    // A WAL-mode file whose newest commit lives only in the `-wal`, behind a
    // read transaction another connection opened before that commit. The
    // checkpoint cannot fold that commit in while the reader holds its older
    // snapshot, so a plain copy of the main file would silently miss it.
    late File dbFile;
    late sql.Database reader;
    late sql.Database writer;

    setUp(() {
      dbFile = File(p.join(dir.path, 'compendium.sqlite'));
      _createFixture(
        dbFile.path,
        userVersion: kCompendiumSchemaVersion - 1,
        seedValue: 'checkpointed',
      );
      writer = sql.sqlite3.open(dbFile.path)
        ..execute('PRAGMA journal_mode = WAL')
        // Keep the commit below in the WAL: no automatic checkpoint.
        ..execute('PRAGMA wal_autocheckpoint = 0');
      reader = sql.sqlite3.open(dbFile.path)
        ..execute('BEGIN')
        ..select('SELECT count(*) FROM t');
      writer.execute('INSERT INTO t (v) VALUES (?)', ['only in the WAL']);
    });
    tearDown(() {
      if (reader.autocommit == false) reader.execute('ROLLBACK');
      reader.close();
      writer.close();
    });

    List<String> rowsIn(String path) {
      final db = sql.sqlite3.open(path);
      try {
        return [
          for (final row in db.select('SELECT v FROM t ORDER BY id'))
            row['v'] as String,
        ];
      } finally {
        db.close();
      }
    }

    test('refuses the copy rather than take an incomplete one', () async {
      SnapshotFailure? seen;
      Object? thrown;
      try {
        await runMigrationPreflight(
          dbFile: dbFile,
          snapshotDir: snapshotDir,
          runningSchemaVersion: kCompendiumSchemaVersion,
          repairMarkers: const {},
          onSnapshotFailure: (failure) async {
            seen = failure;
            return false;
          },
        );
      } on MigrationSnapshotAborted catch (error) {
        thrown = error;
      }

      final copies = snapshotDir.existsSync()
          ? snapshotDir.listSync().whereType<File>().toList()
          : const <File>[];
      // Whatever happened, no copy that lacks the WAL-only commit survives…
      for (final copy in copies) {
        expect(rowsIn(copy.path), ['checkpointed', 'only in the WAL']);
      }
      // …and with the reader still holding its snapshot, the preflight goes
      // to the user through the #442 path instead of copying.
      expect(copies, isEmpty);
      expect(thrown, isA<MigrationSnapshotAborted>());
      expect(seen?.error, isA<FileSystemException>());
    });

    test('takes the copy when the reader already sees every commit', () async {
      // A reader at the newest snapshot still blocks TRUNCATE's reset of the
      // WAL (busy = 1), but every frame is in the main file by then.
      reader
        ..execute('ROLLBACK')
        ..execute('BEGIN')
        ..select('SELECT count(*) FROM t');

      await runMigrationPreflight(
        dbFile: dbFile,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: const {},
      );

      final copy = snapshotDir.listSync().whereType<File>().single;
      expect(rowsIn(copy.path), ['checkpointed', 'only in the WAL']);
    });

    test('waits briefly for a reader that lets go', () async {
      // Well inside the retry window, and after the first attempt.
      final release = Future<void>.delayed(
        const Duration(milliseconds: 250),
        () => reader.execute('ROLLBACK'),
      );

      await runMigrationPreflight(
        dbFile: dbFile,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: const {},
      );
      await release;

      final copy = snapshotDir.listSync().whereType<File>().single;
      expect(rowsIn(copy.path), ['checkpointed', 'only in the WAL']);
    });

    test('takes a complete copy once the reader lets go', () async {
      reader.execute('ROLLBACK');

      await runMigrationPreflight(
        dbFile: dbFile,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: const {},
      );

      final copy = snapshotDir.listSync().whereType<File>().single;
      expect(rowsIn(copy.path), ['checkpointed', 'only in the WAL']);
    });
  });

  test(
    'consults the decision callback on snapshot failure and proceeds only on '
    'explicit consent (issue #442 fail-closed)',
    () async {
      final dbFile = File(p.join(dir.path, 'compendium.sqlite'));
      final older = kCompendiumSchemaVersion - 1;
      _createFixture(dbFile.path, userVersion: older, seedValue: 'survive');

      // Block snapshot creation: put a *file* where the snapshot dir's parent
      // must be, so Directory.create(recursive: true) throws.
      final blocker = File(p.join(dir.path, 'blocker'));
      await blocker.writeAsString('not a directory');
      final unwritableDir = Directory(p.join(blocker.path, 'db_backups'));

      SnapshotFailure? seen;
      await expectLater(
        runMigrationPreflight(
          dbFile: dbFile,
          snapshotDir: unwritableDir,
          runningSchemaVersion: kCompendiumSchemaVersion,
          repairMarkers: const {},
          onSnapshotFailure: (failure) async {
            seen = failure;
            return true; // user explicitly opts to proceed without a backup
          },
        ),
        completes,
      );

      // The migration was gated on the callback (not auto-proceeded): the
      // callback was consulted with an accurate description of the failure.
      expect(seen, isNotNull);
      expect(seen!.fromVersion, older);
      expect(seen!.toVersion, kCompendiumSchemaVersion);
      expect(seen!.error, isA<FileSystemException>());

      // Consent given → the preflight returns (so drift still migrates) and the
      // original file is left untouched for drift.
      expect(unwritableDir.existsSync(), isFalse);
      expect(readUserVersion(dbFile.path), older);
    },
  );

  test(
    'aborts (fail-closed) when the user declines, before any schema change',
    () async {
      final dbFile = File(p.join(dir.path, 'compendium.sqlite'));
      final older = kCompendiumSchemaVersion - 1;
      _createFixture(dbFile.path, userVersion: older, seedValue: 'survive');

      final blocker = File(p.join(dir.path, 'blocker'));
      await blocker.writeAsString('not a directory');
      final unwritableDir = Directory(p.join(blocker.path, 'db_backups'));

      var asked = false;
      await expectLater(
        runMigrationPreflight(
          dbFile: dbFile,
          snapshotDir: unwritableDir,
          runningSchemaVersion: kCompendiumSchemaVersion,
          repairMarkers: const {},
          onSnapshotFailure: (failure) async {
            asked = true;
            return false; // user chooses Quit
          },
        ),
        throwsA(isA<MigrationSnapshotAborted>()),
      );

      // The user was asked, and declining stopped the preflight before any
      // migration: no snapshot, and the file's version is unchanged.
      expect(asked, isTrue);
      expect(unwritableDir.existsSync(), isFalse);
      expect(readUserVersion(dbFile.path), older);
    },
  );

  test(
    'fails closed with no decision callback, rather than silently proceeding',
    () async {
      final dbFile = File(p.join(dir.path, 'compendium.sqlite'));
      final older = kCompendiumSchemaVersion - 1;
      _createFixture(dbFile.path, userVersion: older, seedValue: 'survive');

      final blocker = File(p.join(dir.path, 'blocker'));
      await blocker.writeAsString('not a directory');
      final unwritableDir = Directory(p.join(blocker.path, 'db_backups'));

      // No onSnapshotFailure seam → the safest default is to abort, not assume
      // consent (the pre-#442 behavior silently proceeded here).
      await expectLater(
        runMigrationPreflight(
          dbFile: dbFile,
          snapshotDir: unwritableDir,
          runningSchemaVersion: kCompendiumSchemaVersion,
          repairMarkers: const {},
        ),
        throwsA(isA<MigrationSnapshotAborted>()),
      );

      expect(unwritableDir.existsSync(), isFalse);
      expect(readUserVersion(dbFile.path), older);
    },
  );

  test(
    'does not consult the decision callback when the snapshot succeeds',
    () async {
      final dbFile = File(p.join(dir.path, 'compendium.sqlite'));
      final older = kCompendiumSchemaVersion - 1;
      _createFixture(dbFile.path, userVersion: older, seedValue: 'pre-migrate');

      var asked = false;
      await runMigrationPreflight(
        dbFile: dbFile,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: const {},
        onSnapshotFailure: (failure) async {
          asked = true;
          return false;
        },
      );

      // Success path is unchanged: a snapshot is written and the consent seam
      // is never touched (no prompt).
      expect(asked, isFalse);
      final snapshots = snapshotDir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).endsWith('.sqlite.bak'))
          .toList();
      expect(snapshots, hasLength(1));
    },
  );

  test(
    'is a no-op for a missing file, empty file, or matching version',
    () async {
      // Missing file (fresh install).
      await runMigrationPreflight(
        dbFile: File(p.join(dir.path, 'nope.sqlite')),
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: const {},
      );
      expect(snapshotDir.existsSync(), isFalse);

      // Empty/uninitialized file (user_version 0 — drift will onCreate it).
      final empty = File(p.join(dir.path, 'empty.sqlite'));
      await empty.writeAsBytes(const []);
      await runMigrationPreflight(
        dbFile: empty,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: const {},
      );
      expect(snapshotDir.existsSync(), isFalse);

      // Already at the running version.
      final match = File(p.join(dir.path, 'match.sqlite'));
      _createFixture(match.path, userVersion: kCompendiumSchemaVersion);
      await runMigrationPreflight(
        dbFile: match,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: const {},
      );
      expect(snapshotDir.existsSync(), isFalse);
    },
  );

  group('a one-time repair still owed at the running version (UPGRADE-1)', () {
    // What this build's sweeps expect to find, read from an unopened facade as
    // `main.dart` does.
    late Map<String, String?> repairMarkers;
    late CompendiumDatabase probe;

    setUp(() {
      probe = CompendiumDatabase(NativeDatabase.memory());
      repairMarkers = CompendiumRepositories(
        probe,
        contraTaxonomy,
      ).oneTimeRepairMarkers;
    });
    tearDown(() => probe.close());

    /// A real library at the running schema version, fully migrated, then
    /// optionally missing [owing]'s marker — the state a PATCH release that
    /// ships a new sweep meets on its first launch.
    Future<File> createLibrary({String? owing}) async {
      final file = File(p.join(dir.path, 'compendium.sqlite'));
      final db = CompendiumDatabase(
        NativeDatabase(file, setup: applyCompendiumSqliteSetup),
      );
      try {
        await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();
        if (owing != null) {
          await db.customStatement('DELETE FROM settings WHERE key = ?', [
            owing,
          ]);
        }
      } finally {
        await db.close();
      }
      expect(readUserVersion(file.path), kCompendiumSchemaVersion);
      return file;
    }

    bool hasMarker(String path, String key) {
      final db = sql.sqlite3.open(path);
      try {
        return db.select('SELECT 1 FROM settings WHERE key = ?', [
          key,
        ]).isNotEmpty;
      } finally {
        db.close();
      }
    }

    List<File> snapshots() => snapshotDir.existsSync()
        ? snapshotDir
              .listSync()
              .whereType<File>()
              .where((f) => p.basename(f.path).endsWith('.sqlite.bak'))
              .toList()
        : const [];

    test('snapshots the file before the repair runs', () async {
      final dbFile = await createLibrary(owing: chainHandBackfillDoneKey);

      await runMigrationPreflight(
        dbFile: dbFile,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: repairMarkers,
      );

      final snap = snapshots().single;
      expect(
        p.basename(snap.path),
        startsWith('compendium.pre-v$kCompendiumSchemaVersion-'),
      );
      // The snapshot is the pre-repair state…
      expect(hasMarker(snap.path, chainHandBackfillDoneKey), isFalse);

      // …and the repair still runs after it, as `_startupSequence` does next.
      final db = CompendiumDatabase(
        NativeDatabase(dbFile, setup: applyCompendiumSqliteSetup),
      );
      await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();
      await db.close();
      expect(hasMarker(dbFile.path, chainHandBackfillDoneKey), isTrue);

      // Once repaired, the next launch takes no further snapshot.
      await runMigrationPreflight(
        dbFile: dbFile,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: repairMarkers,
      );
      expect(snapshots(), hasLength(1));
    });

    test('a tombstoned marker is owed, as the sweep reads it', () async {
      final dbFile = await createLibrary();
      final db = CompendiumDatabase(
        NativeDatabase(dbFile, setup: applyCompendiumSqliteSetup),
      );
      // `remove` tombstones: the row stays, with `deleted_at` set.
      await SettingsRepository(db).remove(purgeCorruptionRepairDoneKey);
      await db.close();
      expect(hasMarker(dbFile.path, purgeCorruptionRepairDoneKey), isTrue);

      await runMigrationPreflight(
        dbFile: dbFile,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: repairMarkers,
      );

      expect(snapshots(), hasLength(1));
    });

    test('takes no snapshot of a fully repaired file', () async {
      final dbFile = await createLibrary();

      await runMigrationPreflight(
        dbFile: dbFile,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: repairMarkers,
      );

      expect(snapshotDir.existsSync(), isFalse);
    });

    List<File> pinned() => [
      for (final f in snapshots())
        if (p.basename(f.path).endsWith('.pinned.sqlite.bak')) f,
    ];

    /// What one failing launch leaves behind: a sweep that committed before a
    /// later one threw. Stands in for the repair's partial progress.
    void commitPartOfTheRepair(File dbFile, int attempt) {
      final db = sql.sqlite3.open(dbFile.path);
      try {
        db.execute("INSERT INTO settings (key, value_json) VALUES (?, '1')", [
          '__test_partial_sweep_$attempt',
        ]);
      } finally {
        db.close();
      }
    }

    bool hasPartialSweep(File copy) {
      final db = sql.sqlite3.open(copy.path);
      try {
        return db
            .select(
              "SELECT 1 FROM settings WHERE key LIKE '__test_partial_sweep_%'",
            )
            .isNotEmpty;
      } finally {
        db.close();
      }
    }

    test('a repair that keeps failing keeps the copy from before its first '
        'attempt', () async {
      final dbFile = await createLibrary(owing: chainHandBackfillDoneKey);
      const retain = 3;
      var tick = DateTime.utc(2026, 11, 11);

      // More failed launches than the rotation holds.
      for (var attempt = 0; attempt < retain + 3; attempt++) {
        await runMigrationPreflight(
          dbFile: dbFile,
          snapshotDir: snapshotDir,
          runningSchemaVersion: kCompendiumSchemaVersion,
          repairMarkers: repairMarkers,
          retain: retain,
          now: () => tick = tick.add(const Duration(seconds: 1)),
        );
        commitPartOfTheRepair(dbFile, attempt);
      }

      // The first copy is still there, pinned, and is the clean one…
      final first = pinned().single;
      expect(p.basename(first.path), contains('20261111T000001'));
      expect(hasPartialSweep(first), isFalse);
      expect(hasMarker(first.path, chainHandBackfillDoneKey), isFalse);
      // …beside a rotation still pruned to [retain], of later copies.
      final ordinary = [
        for (final f in snapshots())
          if (f.path != first.path) f,
      ];
      expect(ordinary, hasLength(retain));
      expect(ordinary.every(hasPartialSweep), isTrue);
    });

    Future<void> repairSucceeds(File dbFile) async {
      final db = CompendiumDatabase(
        NativeDatabase(dbFile, setup: applyCompendiumSqliteSetup),
      );
      await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();
      await db.close();
    }

    test('the pin is released once the repair succeeds', () async {
      final dbFile = await createLibrary(owing: chainHandBackfillDoneKey);
      const retain = 2;
      var tick = DateTime.utc(2026, 11, 11);
      Future<void> launch() => runMigrationPreflight(
        dbFile: dbFile,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: repairMarkers,
        retain: retain,
        now: () => tick = tick.add(const Duration(seconds: 1)),
      );

      // A pinned copy, then a full rotation of later failed attempts.
      for (var attempt = 0; attempt <= retain; attempt++) {
        await launch();
        commitPartOfTheRepair(dbFile, attempt);
      }
      final pinnedName = p.basename(pinned().single.path);
      expect(snapshots(), hasLength(retain + 1));

      await repairSucceeds(dbFile);

      // The next launch owes nothing: no new copy and no pin left. The
      // released copy counts as the newest, so the rotation is pruned back to
      // [retain] by dropping the oldest *later* attempt, and the clean copy
      // survives the moment its repair first completes.
      await launch();
      expect(pinned(), isEmpty);
      expect(snapshots(), hasLength(retain));
      final released = snapshots().singleWhere(
        (f) =>
            p.basename(f.path) ==
            pinnedName.replaceFirst('.pinned.sqlite.bak', '.sqlite.bak'),
      );
      expect(hasPartialSweep(released), isFalse);
    });

    test('a copy cut short by a crash is never taken for a pin', () async {
      final dbFile = await createLibrary(owing: chainHandBackfillDoneKey);
      snapshotDir.createSync();
      // What a force-quit during the copy leaves behind.
      final leftover = File(
        p.join(
          snapshotDir.path,
          'compendium.pre-v$kCompendiumSchemaVersion-x.pinned.sqlite.bak'
          '.partial',
        ),
      )..writeAsBytesSync(const [1, 2, 3]);

      await runMigrationPreflight(
        dbFile: dbFile,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: repairMarkers,
      );

      // This launch's copy is the pin, complete, and the leftover is gone.
      expect(leftover.existsSync(), isFalse);
      final pin = pinned().single;
      expect(hasMarker(pin.path, chainHandBackfillDoneKey), isFalse);
      expect(
        snapshotDir.listSync().map((e) => p.basename(e.path)),
        everyElement(isNot(endsWith('.partial'))),
      );
    });

    test('released while the repair is fresh, a pin is moved into the '
        'rotation, not deleted', () async {
      final dbFile = await createLibrary(owing: chainHandBackfillDoneKey);
      await runMigrationPreflight(
        dbFile: dbFile,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: repairMarkers,
      );
      final pinnedName = p.basename(pinned().single.path);
      await repairSucceeds(dbFile);

      await releaseRepairSnapshotPin(snapshotDir: snapshotDir);

      expect(pinned(), isEmpty);
      expect(snapshots().map((f) => p.basename(f.path)), [
        pinnedName.replaceFirst('.pinned.sqlite.bak', '.sqlite.bak'),
      ]);
    });

    test('a later build owing a new repair pins its own first copy, once the '
        'app released the last pin', () async {
      const retain = 2;
      var tick = DateTime.utc(2026, 11, 11);
      Future<void> launch(File dbFile) => runMigrationPreflight(
        dbFile: dbFile,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: repairMarkers,
        retain: retain,
        now: () => tick = tick.add(const Duration(seconds: 1)),
      );

      // Build A: owes one repair, pins, and the repair succeeds in the same
      // session, where the app releases the pin.
      var dbFile = await createLibrary(owing: chainHandBackfillDoneKey);
      await launch(dbFile);
      await repairSucceeds(dbFile);
      await releaseRepairSnapshotPin(snapshotDir: snapshotDir, retain: retain);

      // Build B, next launch: owes a different repair, which keeps failing.
      dbFile = await createLibrary(owing: purgeCorruptionRepairDoneKey);
      for (var attempt = 0; attempt < retain + 2; attempt++) {
        await launch(dbFile);
        commitPartOfTheRepair(dbFile, attempt);
      }

      // B's first copy is the one pinned: clean of B's partial sweeps and
      // still lacking B's marker.
      final first = pinned().single;
      expect(p.basename(first.path), contains('20261111T000002'));
      expect(hasPartialSweep(first), isFalse);
      expect(hasMarker(first.path, purgeCorruptionRepairDoneKey), isFalse);
    });

    test('a schema bump that owes a repair pins its copy; one that owes none '
        'is retained as before', () async {
      const retain = 2;
      var tick = DateTime.utc(2026, 11, 11);
      final dbFile = File(p.join(dir.path, 'compendium.sqlite'));
      // No `settings` table: every marker reads as owed.
      _createFixture(dbFile.path, userVersion: kCompendiumSchemaVersion - 1);

      for (var i = 0; i < retain + 2; i++) {
        await runMigrationPreflight(
          dbFile: dbFile,
          snapshotDir: snapshotDir,
          runningSchemaVersion: kCompendiumSchemaVersion,
          repairMarkers: const {},
          retain: retain,
          now: () => tick = tick.add(const Duration(seconds: 1)),
        );
      }
      // Nothing owed: the ordinary rotation, unchanged.
      expect(pinned(), isEmpty);
      expect(snapshots(), hasLength(retain));

      for (var i = 0; i < retain + 2; i++) {
        await runMigrationPreflight(
          dbFile: dbFile,
          snapshotDir: snapshotDir,
          runningSchemaVersion: kCompendiumSchemaVersion,
          repairMarkers: repairMarkers,
          retain: retain,
          now: () => tick = tick.add(const Duration(seconds: 1)),
        );
      }
      // Owed: exactly one pinned copy, the first, beside [retain] others.
      expect(pinned(), hasLength(1));
      expect(snapshots(), hasLength(retain + 1));
      expect(p.basename(pinned().single.path), contains('20261111T000005'));
    });

    test('a snapshot that cannot be written still gates the repair on the '
        "user's decision", () async {
      final dbFile = await createLibrary(owing: chainHandBackfillDoneKey);
      final blocker = File(p.join(dir.path, 'blocker'));
      await blocker.writeAsString('not a directory');
      final unwritableDir = Directory(p.join(blocker.path, 'db_backups'));

      SnapshotFailure? seen;
      await expectLater(
        runMigrationPreflight(
          dbFile: dbFile,
          snapshotDir: unwritableDir,
          runningSchemaVersion: kCompendiumSchemaVersion,
          repairMarkers: repairMarkers,
          onSnapshotFailure: (failure) async {
            seen = failure;
            return false; // the user chooses Quit
          },
        ),
        throwsA(isA<MigrationSnapshotAborted>()),
      );

      // Asked, with the file's own version on both sides: no schema change is
      // pending, only the repair.
      expect(seen?.fromVersion, kCompendiumSchemaVersion);
      expect(seen?.toVersion, kCompendiumSchemaVersion);
      // The preflight threw, so `_startupSequence` never reaches
      // `ensureMigrated`, and the repair is still owed.
      expect(hasMarker(dbFile.path, chainHandBackfillDoneKey), isFalse);

      // With no seam to ask, it fails closed as the schema path does.
      await expectLater(
        runMigrationPreflight(
          dbFile: dbFile,
          snapshotDir: unwritableDir,
          runningSchemaVersion: kCompendiumSchemaVersion,
          repairMarkers: repairMarkers,
        ),
        throwsA(isA<MigrationSnapshotAborted>()),
      );
    });
  });

  test('refuses a DB stamped below the supported floor, leaving it untouched '
      '(issue #841)', () async {
    final dbFile = File(p.join(dir.path, 'compendium.sqlite'));
    // Use a version below the floor, guaranteed to be there because
    // kMinSupportedSchemaVersion is the floor.
    final belowFloor = kMinSupportedSchemaVersion - 1;
    _createFixture(dbFile.path, userVersion: belowFloor, seedValue: 'keep');

    await expectLater(
      runMigrationPreflight(
        dbFile: dbFile,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: const {},
      ),
      throwsA(isA<DatabaseBelowFloorError>()),
    );

    // The thrown error carries the correct version fields.
    DatabaseBelowFloorError? thrown;
    try {
      await runMigrationPreflight(
        dbFile: dbFile,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: const {},
      );
    } on DatabaseBelowFloorError catch (e) {
      thrown = e;
    }
    expect(thrown, isNotNull);
    expect(thrown!.fileVersion, belowFloor);
    expect(thrown.minSupportedVersion, kMinSupportedSchemaVersion);
    expect(thrown.bridgeTag, isNotEmpty);

    // The file is untouched: below-floor databases are never snapshotted or
    // migrated.
    expect(readUserVersion(dbFile.path), belowFloor);
    final db = sql.sqlite3.open(dbFile.path);
    expect(db.select('SELECT v FROM t').single['v'], 'keep');
    db.close();
    expect(snapshotDir.existsSync(), isFalse);
  });

  test('runMigrationPreflight throws the typed error AppBootstrap routes on, '
      'not a generic one (issue #841)', () async {
    // This asserts the *type* only. Routing — that a DatabaseBelowFloorError
    // reaches the below-floor recovery screen rather than the generic Retry
    // screen — is a widget concern, covered by
    // `app/test/widgets/app_bootstrap_test.dart` ("a below-floor error shows
    // the recovery screen and no Retry"), which pumps AppBootstrap with this
    // error and asserts the recovery headline and the absence of Retry.
    final dbFile = File(p.join(dir.path, 'compendium.sqlite'));
    final belowFloor = kMinSupportedSchemaVersion - 1;
    _createFixture(dbFile.path, userVersion: belowFloor);

    Object? thrown;
    try {
      await runMigrationPreflight(
        dbFile: dbFile,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
        repairMarkers: const {},
      );
    } catch (e) {
      thrown = e;
    }

    // Must be the typed error, NOT null. If a future simplification removes
    // the DatabaseBelowFloorError check in runMigrationPreflight, the preflight
    // completes normally (no migration steps fire — the file is below-floor,
    // so there is no applicable migration), thrown stays null, and this expect
    // goes red. The symptom is a silent no-op: the user proceeds into a
    // bootstrap that cannot work.
    expect(
      thrown,
      isA<DatabaseBelowFloorError>(),
      reason:
          'Expected DatabaseBelowFloorError; got $thrown. '
          'If this is null, the below-floor check in runMigrationPreflight '
          'was removed — the preflight completed silently, routing users to '
          'a bootstrap path that cannot open the database.',
    );
  });

  test('performBackUpAndReset returns BackUpFailed and does NOT wipe when the '
      'snapshot writer throws (fail-closed, issue #841)', () async {
    final dbFile = File(p.join(dir.path, 'compendium.sqlite'));
    _createFixture(dbFile.path, userVersion: 5, seedValue: 'must survive');

    // Inject a writer that always throws — simulates disk full / unwritable.
    final result = await performBackUpAndReset(
      dbFile: dbFile,
      snapshotDir: snapshotDir,
      fileVersion: 5,
      appVersion: '0.0.0-test',
      platform: 'test',
      snapshotWriter:
          ({
            required dbFile,
            required snapshotDir,
            required fromVersion,
            required timestamp,
          }) async =>
              throw const FileSystemException('no space', '', OSError('', 28)),
    );

    // The result must be BackUpFailed, not BackUpReady.
    expect(result, isA<BackUpFailed>());
    expect((result as BackUpFailed).cause, SnapshotFailureCause.diskFull);

    // The database file is untouched — version and data survive.
    expect(readUserVersion(dbFile.path), 5);
    final db = sql.sqlite3.open(dbFile.path);
    expect(db.select('SELECT v FROM t').single['v'], 'must survive');
    db.close();

    // No snapshot directory was created (writer threw before creating it).
    expect(snapshotDir.existsSync(), isFalse);
    // performBackUpAndReset never wipes; the caller (main.dart) checks for
    // BackUpFailed and must not wipe either. The file assertions above are
    // the guard for the first half; the second is main.dart's to keep.
  });

  test('performBackUpAndReset returns BackUpReady when the snapshot succeeds, '
      'without wiping anything (caller is responsible for the wipe)', () async {
    final dbFile = File(p.join(dir.path, 'compendium.sqlite'));
    _createFixture(dbFile.path, userVersion: 5, seedValue: 'pre-reset');

    final result = await performBackUpAndReset(
      dbFile: dbFile,
      snapshotDir: snapshotDir,
      fileVersion: 5,
      appVersion: '0.0.0-test',
      platform: 'test',
    );

    expect(result, isA<BackUpReady>());
    final ready = result as BackUpReady;
    expect(ready.snapshotFile.existsSync(), isTrue);
    expect(readUserVersion(ready.snapshotFile.path), 5);

    // performBackUpAndReset never wipes; the original file is intact.
    expect(dbFile.existsSync(), isTrue);
    expect(readUserVersion(dbFile.path), 5);
  });

  test('performReset returns ResetFailed and does NOT delete the file when '
      'the deleter throws (fail-closed, issue #841)', () async {
    final dbFile = File(p.join(dir.path, 'compendium.sqlite'));
    _createFixture(dbFile.path, userVersion: 5, seedValue: 'must survive');

    // Inject a deleter that always throws — simulates a locked file.
    final result = await performReset(
      dbFile: dbFile,
      dbDeleter: (_) async =>
          throw const FileSystemException('locked', '', OSError('', 13)),
    );

    // The result must be ResetFailed.
    expect(result, isA<ResetFailed>());

    // The database file is untouched — version and data survive.
    expect(dbFile.existsSync(), isTrue);
    expect(readUserVersion(dbFile.path), 5);
    final db = sql.sqlite3.open(dbFile.path);
    expect(db.select('SELECT v FROM t').single['v'], 'must survive');
    db.close();
  });

  test('performReset returns ResetComplete and deletes the file when the '
      'deleter succeeds', () async {
    final dbFile = File(p.join(dir.path, 'compendium.sqlite'));
    _createFixture(dbFile.path, userVersion: 5);

    final result = await performReset(dbFile: dbFile);

    expect(result, isA<ResetComplete>());
    expect(dbFile.existsSync(), isFalse);
  });

  // Invariant guard: kBelowFloorBridgeTags must contain an entry for every
  // floor raise, including the current one. If this fails after a floor raise,
  // the recovery screen will show stale bridge guidance.
  test(
    'kBelowFloorBridgeTags has an entry whose floor == '
    'kMinSupportedSchemaVersion (floor-raise checklist guard, issue #841)',
    () {
      final floors = kBelowFloorBridgeTags.map((e) => e.floor).toSet();
      expect(
        floors,
        contains(kMinSupportedSchemaVersion),
        reason:
            'No bridge-tag entry for the current floor '
            '($kMinSupportedSchemaVersion). Add one to kBelowFloorBridgeTags '
            'as part of the floor-raise checklist.',
      );
    },
  );

  group('relocateLegacyDatabase', () {
    late File legacy;
    late File target;
    late Directory legacyBackups;
    late Directory targetBackups;

    setUp(() {
      final legacyDir = Directory(p.join(dir.path, 'Documents'))..createSync();
      final targetDir = Directory(p.join(dir.path, 'AppData'));
      legacy = File(p.join(legacyDir.path, 'compendium.sqlite'));
      target = File(p.join(targetDir.path, 'compendium.sqlite'));
      legacyBackups = Directory(
        p.join(legacyDir.path, kDatabaseBackupsDirName),
      );
      targetBackups = Directory(
        p.join(targetDir.path, kDatabaseBackupsDirName),
      );
    });

    String seeded(File file) {
      final db = sql.sqlite3.open(file.path);
      try {
        return db.select('SELECT v FROM t ORDER BY id LIMIT 1').single['v']
            as String;
      } finally {
        db.close();
      }
    }

    test('moves the database, its sidecars and the snapshots once', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'my library');
      // An open WAL connection holds un-checkpointed rows in the sidecar.
      final live = sql.sqlite3.open(legacy.path)
        ..execute('PRAGMA journal_mode = WAL')
        ..execute("INSERT INTO t (v) VALUES ('in the wal')");
      expect(File('${legacy.path}-wal').existsSync(), isTrue);
      live.close();
      File('${legacy.path}-shm').writeAsBytesSync(const [9]);
      legacyBackups.createSync();
      File(
        p.join(legacyBackups.path, 'compendium.pre-v6-x.sqlite.bak'),
      ).writeAsBytesSync(const [1, 2, 3]);
      // A copy pinned for an outstanding repair moves with the rest.
      File(
        p.join(legacyBackups.path, 'compendium.pre-v6-y.pinned.sqlite.bak'),
      ).writeAsBytesSync(const [4, 5]);
      File(p.join(legacyBackups.path, 'notes.txt')).writeAsStringSync('mine');

      final moved = await relocateLegacyDatabase(
        target: target,
        legacy: [legacy],
      );

      expect(moved, isTrue);
      expect(readUserVersion(target.path), 7);
      final db = sql.sqlite3.open(target.path);
      expect(db.select('SELECT v FROM t ORDER BY id').map((r) => r['v']), [
        'my library',
        'in the wal',
      ]);
      db.close();
      expect(legacy.existsSync(), isFalse);
      expect(File('${legacy.path}-wal').existsSync(), isFalse);
      expect(File('${legacy.path}-shm').existsSync(), isFalse);
      expect(
        File(
          p.join(targetBackups.path, 'compendium.pre-v6-x.sqlite.bak'),
        ).readAsBytesSync(),
        const [1, 2, 3],
      );
      expect(
        File(
          p.join(targetBackups.path, 'compendium.pre-v6-y.pinned.sqlite.bak'),
        ).readAsBytesSync(),
        const [4, 5],
      );
      // Only our own snapshots move: a stranger's file in Documents stays.
      expect(
        File(p.join(legacyBackups.path, 'notes.txt')).existsSync(),
        isTrue,
      );
      expect(
        target.parent.listSync(recursive: true).map((e) => e.path),
        isNot(contains(endsWith('.relocating'))),
      );

      // A second launch is a no-op.
      expect(
        await relocateLegacyDatabase(target: target, legacy: [legacy]),
        isFalse,
      );
      expect(seeded(target), 'my library');
    });

    test('refuses to move a database another connection holds open, even an '
        'idle one (dbloc-2)', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'first');
      // An older build left running on the legacy file: open, WAL, idle (no
      // read transaction), so the checkpoint alone does not report busy.
      final live = sql.sqlite3.open(legacy.path)
        ..execute('PRAGMA journal_mode = WAL')
        ..execute("INSERT INTO t (v) VALUES ('second')");
      addTearDown(live.close);

      await expectLater(
        relocateLegacyDatabase(target: target, legacy: [legacy]),
        throwsA(
          isA<DatabaseRelocationBlocked>().having(
            (e) => e.reason,
            'reason',
            DatabaseRelocationFailure.moveFailed,
          ),
        ),
      );

      expect(legacy.existsSync(), isTrue);
      expect(target.existsSync(), isFalse);
      // The other connection still works on the file it had open.
      live.execute("INSERT INTO t (v) VALUES ('third')");
      expect(live.select('SELECT v FROM t ORDER BY id').map((r) => r['v']), [
        'first',
        'second',
        'third',
      ]);
      expect(live.select('PRAGMA journal_mode').single.values.single, 'wal');
    });

    test('a connection opened after the in-use check cannot write to the old '
        'file while it is copied and deleted (dbloc-2)', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'library');
      sql.sqlite3.open(legacy.path)
        ..execute('PRAGMA journal_mode = WAL')
        ..close();
      final attempts = <String>[];

      final moved = await relocateLegacyDatabase(
        target: target,
        legacy: [legacy],
        afterRename: (renamed) async {
          if (renamed.path != target.path) return;
          // An older build opening the old file after the probe, mid-move.
          final late = sql.sqlite3.open(legacy.path);
          try {
            late.execute("INSERT INTO t (v) VALUES ('lost?')");
            attempts.add('wrote');
          } on sql.SqliteException {
            attempts.add('refused');
          } finally {
            late.close();
          }
        },
      );

      expect(moved, isTrue);
      expect(attempts, ['refused']);
      final db = sql.sqlite3.open(target.path);
      addTearDown(db.close);
      expect(db.select('SELECT v FROM t').map((r) => r['v']), ['library']);
    });

    test(
      'another process cannot write to the old file while it is copied and '
      'deleted (dbloc-2)',
      () async {
        _createFixture(legacy.path, userVersion: 7, seedValue: 'library');
        sql.sqlite3.open(legacy.path)
          ..execute('PRAGMA journal_mode = WAL')
          ..close();
        final outcomes = <String>[];
        Future<void> tryWrite() async {
          final result = await Process.run('python3', [
            '-c',
            'import sqlite3, sys\n'
                'c = sqlite3.connect(sys.argv[1], timeout=0)\n'
                'try:\n'
                '    c.execute("INSERT INTO t (v) VALUES (\'lost?\')")\n'
                '    c.commit()\n'
                '    print("wrote")\n'
                'except sqlite3.OperationalError:\n'
                '    print("refused")\n',
            legacy.path,
          ]);
          outcomes.add('${result.stdout}'.trim());
        }

        final moved = await relocateLegacyDatabase(
          target: target,
          legacy: [legacy],
          // Mid-copy is covered by the same lock; after the rename the main
          // file has been read and copied through this process's own handle,
          // so this also proves closing that handle did not drop the lock.
          afterRename: (renamed) async {
            if (renamed.path == target.path) await tryWrite();
          },
        );

        expect(moved, isTrue);
        expect(outcomes, ['refused']);
        final db = sql.sqlite3.open(target.path);
        addTearDown(db.close);
        expect(db.select('SELECT v FROM t').map((r) => r['v']), ['library']);
      },
      // python3's sqlite3 takes POSIX fcntl locks like this process's SQLite.
      skip: Platform.isWindows,
    );

    test('a move that gives up leaves the old file in WAL mode; a moved copy '
        'is put back in WAL mode by the app\'s own setup', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'x');
      sql.sqlite3.open(legacy.path)
        ..execute('PRAGMA journal_mode = WAL')
        ..close();
      String mode(File file) {
        final db = sql.sqlite3.open(file.path);
        try {
          return '${db.select('PRAGMA journal_mode').single.values.single}';
        } finally {
          db.close();
        }
      }

      await expectLater(
        relocateLegacyDatabase(
          target: target,
          legacy: [legacy],
          deleter: (file) async => throw const FileSystemException('locked'),
        ),
        throwsA(isA<DatabaseRelocationBlocked>()),
      );
      expect(mode(legacy), 'wal');
      expect(target.existsSync(), isFalse);

      expect(
        await relocateLegacyDatabase(target: target, legacy: [legacy]),
        isTrue,
      );
      // Moved while held in rollback-journal mode; drift's setup (as every
      // open in the app runs it) switches it back.
      final db = sql.sqlite3.open(target.path);
      addTearDown(db.close);
      applyCompendiumSqliteSetup(db);
      expect(db.select('PRAGMA journal_mode').single.values.single, 'wal');
      expect(seeded(target), 'x');
    });

    test('a second relocation started while the first is mid-move waits for '
        'it instead of interleaving (dbloc-1)', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'my library');
      final firstRenamed = Completer<void>();
      final letFirstFinish = Completer<void>();
      final order = <String>[];

      final first = relocateLegacyDatabase(
        target: target,
        legacy: [legacy],
        afterRename: (renamed) async {
          if (renamed.path != target.path) return;
          // Paused after its rename and before deleting the legacy file: the
          // window in which both copies exist.
          firstRenamed.complete();
          await letFirstFinish.future;
        },
      ).whenComplete(() => order.add('first'));
      await firstRenamed.future;

      final second = relocateLegacyDatabase(
        target: target,
        legacy: [legacy],
      ).whenComplete(() => order.add('second'));
      final secondOutcome = second.then<Object?>(
        (moved) => moved,
        onError: (Object error) => error,
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(order, isEmpty, reason: 'the second attempt must wait');

      letFirstFinish.complete();
      expect(await first, isTrue);
      // It re-checks once it holds the lock: the first already moved it.
      expect(await secondOutcome, isFalse);
      expect(order, ['first', 'second']);
      expect(legacy.existsSync(), isFalse);
      expect(seeded(target), 'my library');
    });

    test('fails closed, touching nothing, while another process holds the '
        'relocation lock', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'keep me');
      final lock = _HeldElsewhere();

      await expectLater(
        relocateLegacyDatabase(
          target: target,
          legacy: [legacy],
          lockPrimitive: lock,
          lockTimeout: const Duration(milliseconds: 300),
        ),
        throwsA(
          isA<DatabaseRelocationBlocked>().having(
            (e) => e.reason,
            'reason',
            DatabaseRelocationFailure.moveFailed,
          ),
        ),
      );

      expect(lock.attempts, greaterThan(1), reason: 'it retries until timeout');
      expect(seeded(legacy), 'keep me');
      expect(target.existsSync(), isFalse);
    });

    test('re-checks the preconditions once the lock is held', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'moved by B');

      final moved = await relocateLegacyDatabase(
        target: target,
        legacy: [legacy],
        // Another process finished the whole move while this one waited.
        lockPrimitive: _GrantedAfter(() {
          target.parent.createSync(recursive: true);
          legacy.renameSync(target.path);
        }),
      );

      expect(moved, isFalse);
      expect(legacy.existsSync(), isFalse);
      expect(seeded(target), 'moved by B');
    });

    test(
      'waits on the real OS lock held by another process',
      () async {
        _createFixture(legacy.path, userVersion: 7, seedValue: 'keep me');
        target.parent.createSync(recursive: true);
        final lockPath = p.join(target.parent.path, kRelocationLockFileName);
        final holder = await Process.start('python3', [
          '-c',
          'import fcntl, sys\n'
              'f = open(sys.argv[1], "w")\n'
              'fcntl.lockf(f, fcntl.LOCK_EX)\n'
              'print("locked", flush=True)\n'
              'sys.stdin.readline()\n',
          lockPath,
        ]);
        addTearDown(holder.kill);
        final lines = holder.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter());
        expect(await lines.first, 'locked');

        await expectLater(
          relocateLegacyDatabase(
            target: target,
            legacy: [legacy],
            lockTimeout: const Duration(milliseconds: 500),
          ),
          throwsA(isA<DatabaseRelocationBlocked>()),
        );
        expect(seeded(legacy), 'keep me');
        expect(target.existsSync(), isFalse);

        holder.stdin.writeln();
        await holder.exitCode;
        expect(
          await relocateLegacyDatabase(target: target, legacy: [legacy]),
          isTrue,
        );
      },
      // A POSIX fcntl lock taken by a python3 child; Windows LockFileEx is not
      // reachable from python's stdlib the same way.
      skip: Platform.isWindows,
    );

    test('a delete failure never discards the new copy once the legacy '
        'database is gone (dbloc-1)', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'only copy');

      await expectLater(
        relocateLegacyDatabase(
          target: target,
          legacy: [legacy],
          // Something else removed the legacy database, then our delete fails.
          deleter: (file) async {
            if (file.path == legacy.path) {
              await file.delete();
              throw const FileSystemException('already gone');
            }
            await file.delete();
          },
        ),
        throwsA(isA<DatabaseRelocationBlocked>()),
      );

      expect(legacy.existsSync(), isFalse);
      expect(target.existsSync(), isTrue);
      expect(seeded(target), 'only copy');
    });

    test('a failure after the rename never discards the new copy once the '
        'legacy database is gone (dbloc-1)', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'only copy');

      await expectLater(
        relocateLegacyDatabase(
          target: target,
          legacy: [legacy],
          afterRename: (renamed) async {
            legacy.deleteSync();
            throw const FileSystemException('later rename failed');
          },
        ),
        throwsA(isA<DatabaseRelocationBlocked>()),
      );

      expect(legacy.existsSync(), isFalse);
      expect(target.existsSync(), isTrue);
      expect(seeded(target), 'only copy');
      // The hold is open during the renames, and SQLite never shares delete
      // access on Windows, so nothing can remove the legacy database there.
    }, skip: Platform.isWindows);

    test('fails closed without copying or deleting when a reader holds the '
        'WAL (busy checkpoint)', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'first');
      final writer = sql.sqlite3.open(legacy.path)
        ..execute('PRAGMA journal_mode = WAL');
      addTearDown(writer.close);
      // A read transaction pins a snapshot, so later commits cannot be fully
      // checkpointed: wal_checkpoint(TRUNCATE) returns busy = 1 (no throw).
      final reader = sql.sqlite3.open(legacy.path)
        ..execute('BEGIN')
        ..select('SELECT * FROM t');
      addTearDown(reader.close);
      writer.execute("INSERT INTO t (v) VALUES ('committed after the reader')");
      final walLength = File('${legacy.path}-wal').lengthSync();
      expect(walLength, greaterThan(0));

      await expectLater(
        relocateLegacyDatabase(target: target, legacy: [legacy]),
        throwsA(
          isA<DatabaseRelocationBlocked>().having(
            (e) => e.reason,
            'reason',
            DatabaseRelocationFailure.moveFailed,
          ),
        ),
      );

      expect(legacy.existsSync(), isTrue);
      expect(File('${legacy.path}-wal').lengthSync(), walLength);
      // Only the relocation lock file was created at the new location.
      expect(target.parent.listSync().map((e) => p.basename(e.path)), [
        kRelocationLockFileName,
      ]);
    });

    test('reports a distinct reason when only legacy locations conflict, and '
        'when a stray target sidecar exists', () async {
      final other = File(p.join(dir.path, 'Roaming', 'compendium.sqlite'))
        ..parent.createSync();
      _createFixture(legacy.path, userVersion: 7, seedValue: 'documents');
      _createFixture(other.path, userVersion: 7, seedValue: 'roaming');
      await expectLater(
        relocateLegacyDatabase(target: target, legacy: [legacy, other]),
        throwsA(
          isA<DatabaseRelocationBlocked>().having(
            (e) => e.reason,
            'reason',
            DatabaseRelocationFailure.multipleLegacy,
          ),
        ),
      );

      other.deleteSync();
      target.parent.createSync(recursive: true);
      File('${target.path}-wal').writeAsBytesSync(const [1]);
      await expectLater(
        relocateLegacyDatabase(target: target, legacy: [legacy]),
        throwsA(
          isA<DatabaseRelocationBlocked>().having(
            (e) => e.reason,
            'reason',
            DatabaseRelocationFailure.bothExist,
          ),
        ),
      );
      expect(seeded(legacy), 'documents');
      expect(File('${target.path}-wal').readAsBytesSync(), const [1]);
    });

    test('a delete failure part-way restores the deleted source files and '
        'removes the target copy', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'keep me');
      legacyBackups.createSync();
      final snapshot = File(
        p.join(legacyBackups.path, 'compendium.pre-v6-x.sqlite.bak'),
      )..writeAsBytesSync(const [1, 2, 3]);
      File('${legacy.path}-shm').writeAsBytesSync(const [9]);
      final deleteAttempts = <String>[];

      await expectLater(
        relocateLegacyDatabase(
          target: target,
          legacy: [legacy],
          // Snapshots and the sidecar are deleted first, the database last:
          // fail on the database, after the others are already gone.
          deleter: (file) async {
            deleteAttempts.add(p.basename(file.path));
            if (file.path == legacy.path) {
              throw const FileSystemException('locked');
            }
            await file.delete();
          },
        ),
        throwsA(
          isA<DatabaseRelocationBlocked>().having(
            (e) => e.reason,
            'reason',
            DatabaseRelocationFailure.moveFailed,
          ),
        ),
      );

      expect(deleteAttempts.last, 'compendium.sqlite');
      expect(deleteAttempts.length, greaterThan(1));
      expect(snapshot.readAsBytesSync(), const [1, 2, 3]);
      expect(File('${legacy.path}-shm').readAsBytesSync(), const [9]);
      expect(seeded(legacy), 'keep me');
      expect(target.existsSync(), isFalse);
      expect(File('${target.path}-shm').existsSync(), isFalse);
      expect(
        targetBackups.existsSync()
            ? targetBackups.listSync()
            : <FileSystemEntity>[],
        isEmpty,
      );
    });

    test('leaves a breadcrumb at the old path that an older build cannot '
        'open as a new, empty library (dbloc-4)', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'my library');

      expect(
        await relocateLegacyDatabase(target: target, legacy: [legacy]),
        isTrue,
      );

      // A folder now holds the old file name, with a note for the user.
      expect(
        FileSystemEntity.typeSync(legacy.path),
        FileSystemEntityType.directory,
      );
      final note = File(p.join(legacy.path, kRelocationBreadcrumbNoteName));
      expect(note.readAsStringSync(), contains(target.parent.path));

      // Every shipped build (v0.1.0 to v0.5.4) runs its preflight only when
      // `File(path).exists()`, which is false for a folder...
      expect(await File(legacy.path).exists(), isFalse);
      // ...then opens the path through drift_flutter 0.3.1, the version every
      // release pinned, exactly as their `openAppDatabase` does. SQLite cannot
      // open a folder, so the first query fails instead of creating a library.
      final older = CompendiumDatabase(
        driftDatabase(
          name: kDatabaseName,
          native: DriftNativeOptions(
            databasePath: () async => legacy.path,
            setup: applyCompendiumSqliteSetup,
            tempDirectoryPath: () async => dir.path,
          ),
        ),
      );
      await expectLater(
        older.customSelect('SELECT 1').get(),
        throwsA(anything),
      );
      try {
        await older.close();
      } on Object {
        // The connection never opened.
      }
      expect(
        FileSystemEntity.typeSync(legacy.path),
        FileSystemEntityType.directory,
      );
      expect(
        legacy.parent.listSync().map((e) => p.basename(e.path)),
        isNot(contains(startsWith('compendium.sqlite-'))),
      );
      expect(seeded(target), 'my library');
    });

    test('leaves a breadcrumb at every earlier location whose folder exists, '
        'and none where the folder is missing', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'x');
      final roaming = File(p.join(dir.path, 'Roaming', 'compendium.sqlite'))
        ..parent.createSync();
      final absent = File(p.join(dir.path, 'Missing', 'compendium.sqlite'));

      await relocateLegacyDatabase(
        target: target,
        legacy: [legacy, roaming, absent],
      );

      expect(
        FileSystemEntity.typeSync(roaming.path),
        FileSystemEntityType.directory,
      );
      expect(absent.parent.existsSync(), isFalse);
    });

    test('the breadcrumb at the old path is part of the move: if it cannot be '
        'made, the move rolls back', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'keep me');

      await expectLater(
        relocateLegacyDatabase(
          target: target,
          legacy: [legacy],
          // Something takes the freed path before the breadcrumb is made.
          deleter: (file) async {
            await file.delete();
            if (file.path == legacy.path) file.writeAsStringSync('squatter');
          },
        ),
        throwsA(
          isA<DatabaseRelocationBlocked>().having(
            (e) => e.reason,
            'reason',
            DatabaseRelocationFailure.moveFailed,
          ),
        ),
      );

      expect(seeded(legacy), 'keep me');
      expect(target.existsSync(), isFalse);
    });

    test('a stray sidecar at the new location is not listed as a library '
        'copy', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'documents');
      target.parent.createSync(recursive: true);
      File('${target.path}-wal').writeAsBytesSync(const [1]);

      final blocked =
          await relocateLegacyDatabase(
            target: target,
            legacy: [legacy],
            documentsDirectory: legacy.parent,
          ).then<DatabaseRelocationBlocked?>(
            (_) => null,
            onError: (Object e) => e as DatabaseRelocationBlocked,
          );

      expect(blocked?.reason, DatabaseRelocationFailure.bothExist);
      expect(blocked!.copies.map((c) => c.location), [
        DatabaseCopyLocation.documents,
      ]);
    });

    test('a breadcrumb is not a legacy database on the next launch', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'x');
      await relocateLegacyDatabase(target: target, legacy: [legacy]);

      expect(
        await relocateLegacyDatabase(
          target: target,
          legacy: [legacy],
          documentsDirectory: legacy.parent,
        ),
        isFalse,
      );
      expect(seeded(target), 'x');
    });

    test('refuses to go on as if there were no library while Documents is '
        'unreachable and the new location is empty (dbloc-5)', () async {
      final offline = Directory(p.join(dir.path, 'OfflineShare'));
      final unreachable = File(p.join(offline.path, 'compendium.sqlite'));

      await expectLater(
        relocateLegacyDatabase(
          target: target,
          legacy: [unreachable],
          documentsDirectory: offline,
        ),
        throwsA(
          isA<DatabaseRelocationBlocked>().having(
            (e) => e.reason,
            'reason',
            DatabaseRelocationFailure.legacyUnreachable,
          ),
        ),
      );
      expect(target.parent.existsSync(), isFalse);
    });

    test('an unreachable Documents does not block once the new location holds '
        'the library', () async {
      target.parent.createSync(recursive: true);
      _createFixture(target.path, userVersion: 7, seedValue: 'here');
      final offline = Directory(p.join(dir.path, 'OfflineShare'));

      expect(
        await relocateLegacyDatabase(
          target: target,
          legacy: [File(p.join(offline.path, 'compendium.sqlite'))],
          documentsDirectory: offline,
        ),
        isFalse,
      );
      expect(seeded(target), 'here');
    });

    test('reports each conflicting copy with its location, size and last '
        'change (dbloc-6)', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'documents');
      target.parent.createSync(recursive: true);
      _createFixture(target.path, userVersion: 7, seedValue: 'new');
      File('${target.path}-wal').writeAsBytesSync(List.filled(100, 0));
      final older = DateTime(2026, 3, 1, 9, 30);
      final newer = DateTime(2026, 9, 1, 18);
      legacy.setLastModifiedSync(newer);
      target.setLastModifiedSync(older);
      File('${target.path}-wal').setLastModifiedSync(older);

      final blocked =
          await relocateLegacyDatabase(
            target: target,
            legacy: [legacy],
            documentsDirectory: legacy.parent,
          ).then<DatabaseRelocationBlocked?>(
            (_) => null,
            onError: (Object e) => e as DatabaseRelocationBlocked,
          );

      expect(blocked?.reason, DatabaseRelocationFailure.bothExist);
      expect(
        blocked!.copies
            .map((c) => (c.location, c.bytes, c.modified.toLocal()))
            .toList(),
        [
          (DatabaseCopyLocation.newLocation, target.lengthSync() + 100, older),
          (DatabaseCopyLocation.documents, legacy.lengthSync(), newer),
        ],
      );

      // Two earlier locations and nothing new: both are described.
      target.deleteSync();
      File('${target.path}-wal').deleteSync();
      final roaming = File(p.join(dir.path, 'Roaming', 'compendium.sqlite'))
        ..parent.createSync();
      _createFixture(roaming.path, userVersion: 7, seedValue: 'roaming');
      final multiple =
          await relocateLegacyDatabase(
            target: target,
            legacy: [legacy, roaming],
            documentsDirectory: legacy.parent,
          ).then<DatabaseRelocationBlocked?>(
            (_) => null,
            onError: (Object e) => e as DatabaseRelocationBlocked,
          );
      expect(multiple?.reason, DatabaseRelocationFailure.multipleLegacy);
      expect(multiple!.copies.map((c) => (c.location, c.bytes)), [
        (DatabaseCopyLocation.documents, legacy.lengthSync()),
        (DatabaseCopyLocation.earlierAppFolder, roaming.lengthSync()),
      ]);
    });

    test('removes the emptied legacy db_backups folder', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'x');
      legacyBackups.createSync();
      File(
        p.join(legacyBackups.path, 'compendium.pre-v6-x.sqlite.bak'),
      ).writeAsBytesSync(const [1]);

      await relocateLegacyDatabase(target: target, legacy: [legacy]);

      expect(legacyBackups.existsSync(), isFalse);
    });

    test('does nothing when no legacy database exists', () async {
      expect(
        await relocateLegacyDatabase(target: target, legacy: [legacy]),
        isFalse,
      );
      expect(target.parent.existsSync(), isFalse);
    });

    test('leaves both untouched when the new location already has a '
        'database', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'old');
      target.parent.createSync(recursive: true);
      _createFixture(target.path, userVersion: 8, seedValue: 'new');
      final legacyBytes = legacy.readAsBytesSync();
      final targetBytes = target.readAsBytesSync();

      await expectLater(
        relocateLegacyDatabase(target: target, legacy: [legacy]),
        throwsA(
          isA<DatabaseRelocationBlocked>().having(
            (e) => e.reason,
            'reason',
            DatabaseRelocationFailure.bothExist,
          ),
        ),
      );

      expect(legacy.readAsBytesSync(), legacyBytes);
      expect(target.readAsBytesSync(), targetBytes);
    });

    test('leaves both untouched when two legacy locations hold a '
        'database', () async {
      final other = File(p.join(dir.path, 'Roaming', 'compendium.sqlite'))
        ..parent.createSync();
      _createFixture(legacy.path, userVersion: 7, seedValue: 'documents');
      _createFixture(other.path, userVersion: 7, seedValue: 'roaming');

      await expectLater(
        relocateLegacyDatabase(target: target, legacy: [legacy, other]),
        throwsA(isA<DatabaseRelocationBlocked>()),
      );

      expect(seeded(legacy), 'documents');
      expect(seeded(other), 'roaming');
      expect(target.existsSync(), isFalse);
    });

    test('deletes nothing and leaves nothing behind when the move '
        'fails', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'keep me');
      legacyBackups.createSync();
      File(
        p.join(legacyBackups.path, 'compendium.pre-v6-x.sqlite.bak'),
      ).writeAsBytesSync(const [1]);
      // The target directory cannot be created: its parent is a regular file.
      final blocker = File(p.join(dir.path, 'blocker'))..writeAsStringSync('');
      final blockedTarget = File(
        p.join(blocker.path, 'AppData', 'compendium.sqlite'),
      );

      await expectLater(
        relocateLegacyDatabase(target: blockedTarget, legacy: [legacy]),
        throwsA(
          isA<DatabaseRelocationBlocked>().having(
            (e) => e.reason,
            'reason',
            DatabaseRelocationFailure.moveFailed,
          ),
        ),
      );

      expect(seeded(legacy), 'keep me');
      expect(
        File(
          p.join(legacyBackups.path, 'compendium.pre-v6-x.sqlite.bak'),
        ).existsSync(),
        isTrue,
      );
    });

    test('a failure part-way removes the partial copy so the next launch '
        'can retry cleanly', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'keep me');
      legacyBackups.createSync();
      File(
        p.join(legacyBackups.path, 'compendium.pre-v6-x.sqlite.bak'),
      ).writeAsBytesSync(const [1]);
      // The database file copies fine; the snapshot destination cannot be
      // created because a regular file squats on the db_backups name.
      target.parent.createSync(recursive: true);
      File(targetBackups.path).writeAsStringSync('squatter');

      await expectLater(
        relocateLegacyDatabase(target: target, legacy: [legacy]),
        throwsA(isA<DatabaseRelocationBlocked>()),
      );

      expect(seeded(legacy), 'keep me');
      expect(target.existsSync(), isFalse);
      expect(
        target.parent.listSync().map((e) => p.basename(e.path)),
        isNot(contains('compendium.sqlite.relocating')),
      );
    });
  });
}
