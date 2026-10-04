import 'dart:io';

import 'package:compendium_app/src/data/migration_guard.dart';
import 'package:compendium_core/compendium_core.dart'
    show kCompendiumSchemaVersion, kMinSupportedSchemaVersion;
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
      );
      expect(snapshotDir.existsSync(), isFalse);

      // Empty/uninitialized file (user_version 0 — drift will onCreate it).
      final empty = File(p.join(dir.path, 'empty.sqlite'));
      await empty.writeAsBytes(const []);
      await runMigrationPreflight(
        dbFile: empty,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
      );
      expect(snapshotDir.existsSync(), isFalse);

      // Already at the running version.
      final match = File(p.join(dir.path, 'match.sqlite'));
      _createFixture(match.path, userVersion: kCompendiumSchemaVersion);
      await runMigrationPreflight(
        dbFile: match,
        snapshotDir: snapshotDir,
        runningSchemaVersion: kCompendiumSchemaVersion,
      );
      expect(snapshotDir.existsSync(), isFalse);
    },
  );

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

    test('moves the sidecars that survive the checkpoint', () async {
      _createFixture(legacy.path, userVersion: 7, seedValue: 'first');
      // A connection left open keeps the -wal/-shm in place through the move.
      final live = sql.sqlite3.open(legacy.path)
        ..execute('PRAGMA journal_mode = WAL')
        ..execute("INSERT INTO t (v) VALUES ('second')");
      addTearDown(live.close);
      expect(File('${legacy.path}-wal').existsSync(), isTrue);
      expect(File('${legacy.path}-shm').existsSync(), isTrue);

      await relocateLegacyDatabase(target: target, legacy: [legacy]);

      // The checkpoint folded the WAL into the main file before the copy.
      expect(File('${target.path}-wal').existsSync(), isTrue);
      expect(File('${target.path}-wal').lengthSync(), 0);
      expect(File('${target.path}-shm').existsSync(), isTrue);
      expect(File('${legacy.path}-wal').existsSync(), isFalse);
      expect(File('${legacy.path}-shm').existsSync(), isFalse);
      expect(legacy.existsSync(), isFalse);
      final db = sql.sqlite3.open(target.path);
      expect(db.select('SELECT v FROM t ORDER BY id').map((r) => r['v']), [
        'first',
        'second',
      ]);
      db.close();
    });

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
      expect(target.existsSync(), isFalse);
      expect(target.parent.existsSync(), isFalse);
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
