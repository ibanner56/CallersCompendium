import 'dart:io';

import 'package:compendium_app/src/data/migration_guard.dart';
import 'package:compendium_core/compendium_core.dart'
    show kCompendiumSchemaVersion;
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
    'fails open when the snapshot cannot be written, so migration proceeds',
    () async {
      final dbFile = File(p.join(dir.path, 'compendium.sqlite'));
      final older = kCompendiumSchemaVersion - 1;
      _createFixture(dbFile.path, userVersion: older, seedValue: 'survive');

      // Block snapshot creation: put a *file* where the snapshot dir's parent
      // must be, so Directory.create(recursive: true) throws.
      final blocker = File(p.join(dir.path, 'blocker'));
      await blocker.writeAsString('not a directory');
      final unwritableDir = Directory(p.join(blocker.path, 'db_backups'));

      // Fail-open: the snapshot failure is swallowed and the preflight returns
      // normally (so drift still migrates), unlike the fail-closed downgrade
      // guard which must throw.
      await expectLater(
        runMigrationPreflight(
          dbFile: dbFile,
          snapshotDir: unwritableDir,
          runningSchemaVersion: kCompendiumSchemaVersion,
        ),
        completes,
      );

      // No snapshot was written, and the original file is left for drift.
      expect(unwritableDir.existsSync(), isFalse);
      expect(readUserVersion(dbFile.path), older);
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
}
