// The core "refuse to migrate down" guard in `CompendiumDatabase.migration`
// (UPGRADE-4).
//
// drift is forward-only: it calls `onUpgrade` whenever the stored version
// differs from the running one, *including* a file written by a newer build.
// None of the `if (from < N)` steps fire for such a file, so without the guard
// drift stamps `user_version` down to this build's version and leaves the
// newer build's tables in place under code that does not know them.
//
// The app's migration preflight refuses such a file first, and has its own
// test (`app/test/data/migration_guard_test.dart`). This guard is the backstop
// for every open that skips the preflight — the sync isolate opens its own
// `CompendiumDatabase` on the same file (`app/lib/src/sync/sync_isolate.dart`)
// — and until this test nothing failed when it was disabled.
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

/// The file's `user_version` and its full DDL, read without drift.
({int version, List<String> ddl}) _readState(String path) {
  final raw = sqlite3.sqlite3.open(path);
  try {
    return (
      version: raw.select('PRAGMA user_version').single.values.single! as int,
      ddl: [
        for (final row in raw.select(
          'SELECT type, name, sql FROM sqlite_master ORDER BY type, name',
        ))
          '${row['type']} ${row['name']}: ${row['sql']}',
      ],
    );
  } finally {
    raw.close();
  }
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('compendium_core_downgrade_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('a file written by a newer build is refused, with its version and DDL '
      'unchanged', () async {
    final path = p.join(dir.path, 'newer.sqlite');

    // A real library at head, then what a newer build would leave behind: a
    // higher version stamp and a table this build has never heard of.
    final head = CompendiumDatabase(NativeDatabase(File(path)));
    await head.customSelect('SELECT 1').get();
    await head.close();
    final newer = kCompendiumSchemaVersion + 1;
    final raw = sqlite3.sqlite3.open(path);
    raw.execute('CREATE TABLE added_by_a_newer_build (id TEXT PRIMARY KEY)');
    raw.execute('PRAGMA user_version = $newer');
    raw.close();
    final before = _readState(path);
    expect(before.version, newer);

    final db = CompendiumDatabase(NativeDatabase(File(path)));
    await expectLater(
      db.customSelect('SELECT 1').get(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('Refusing to migrate the database down'),
            contains('$newer'),
            contains('$kCompendiumSchemaVersion'),
          ),
        ),
      ),
    );
    await db.close();

    final after = _readState(path);
    expect(
      after.version,
      newer,
      reason: 'the file must not be stamped down to this build',
    );
    expect(after.ddl, before.ddl, reason: 'the open must change no schema');
  });
}
