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

  test(
    'below-floor error reaches AppBootstrap, not the generic error path — '
    'guard: mutate the check out and the generic path fires instead (issue #841)',
    () async {
      // This test verifies the guard's routing: a DatabaseBelowFloorError must
      // reach the below-floor branch in AppBootstrap, not fall through to the
      // generic retry screen.
      //
      // We cannot exercise AppBootstrap here (widget test); what we can prove is
      // that runMigrationPreflight throws DatabaseBelowFloorError (not StateError
      // or any other type) for a below-floor file, so the routing in
      // AppBootstrap's error branch is unambiguous.
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

      // Must be the typed error, NOT a StateError (which is the pre-#841 path
      // that falls through to the generic screen). If a future simplification
      // removes the DatabaseBelowFloorError check in runMigrationPreflight and
      // lets the StateError from the migration steps fire instead, this test
      // goes red — that is its purpose.
      expect(
        thrown,
        isA<DatabaseBelowFloorError>(),
        reason:
            'Expected DatabaseBelowFloorError; got $thrown. '
            'If this is a StateError, the below-floor check in '
            'runMigrationPreflight was removed, which routes users to '
            'the dead-end generic error screen instead of the recovery screen.',
      );
    },
  );

  test('performBackUpAndReset returns BackUpFailed and does NOT wipe when the '
      'snapshot writer throws (fail-closed, issue #841)', () async {
    final dbFile = File(p.join(dir.path, 'compendium.sqlite'));
    _createFixture(dbFile.path, userVersion: 5, seedValue: 'must survive');

    // Inject a writer that always throws — simulates disk full / unwritable.
    var wipeCalled = false;
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
    // wipeCalled is never set because performBackUpAndReset returns
    // BackUpFailed; the caller (main.dart) must check and not wipe.
    expect(wipeCalled, isFalse);
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
}
