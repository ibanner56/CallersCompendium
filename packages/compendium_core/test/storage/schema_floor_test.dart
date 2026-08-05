// The schema floor (#828): a database below [kMinSupportedSchemaVersion] must
// be refused, loudly.
//
// This is the guard that makes retiring old schema versions safe. Deleting the
// `if (from < N)` steps for retired versions is only sound because nothing can
// reach `onUpgrade` with such a `from`. Without the floor check, a below-floor
// database would open, run *only* the surviving steps, and end up structurally
// wrong with no error raised at all — the columns and indices added by the
// retired steps would simply be missing, and the file would then be stamped at
// head, permanently mislabelled. Silently corrupting a user's collection is a
// far worse outcome than refusing to open the file, hence a hard failure.
//
// These tests build databases at the boundary versions directly with raw SQL
// rather than from a fixture, because the whole point is that no fixture below
// the floor exists any more.
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

import '../test_package_root.dart';

/// Writes a minimal database file stamped at [version].
///
/// Only `user_version` matters: `onUpgrade` inspects the stamped version before
/// touching any table, so the floor check is reached whatever the file holds.
String _databaseStampedAt(Directory dir, int version) {
  final path = p.join(dir.path, 'v$version.sqlite');
  final raw = sqlite3.sqlite3.open(path);
  raw.execute('PRAGMA user_version = $version');
  raw.close();
  return path;
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('compendium_core_floor_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('the floor is the schema version of the oldest supported release', () {
    // v0.1.0-beta.2 shipped schema v11 and is the oldest supported release.
    // beta.1 shipped v10, so a beta.1 database is deliberately below the floor.
    expect(kMinSupportedSchemaVersion, 11);
    expect(
      kMinSupportedSchemaVersion,
      lessThanOrEqualTo(kCompendiumSchemaVersion),
      reason: 'the floor can never exceed head',
    );
  });

  group('a database below the floor is refused', () {
    for (final version in const [1, 5, 10]) {
      test('v$version fails to open', () async {
        final db = CompendiumDatabase(
          NativeDatabase(File(_databaseStampedAt(dir, version))),
        );

        await expectLater(
          db.customSelect('SELECT 1').get(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('$version'),
                contains('$kMinSupportedSchemaVersion'),
                // The message has to tell the user what to do, not just assert
                // a number at them.
                contains('older build'),
              ),
            ),
          ),
        );

        await db.close();
      });
    }

    test('v10 is refused even though it is only one below the floor', () async {
      // The boundary is the interesting case: beta.1 shipped v10, so this is
      // the version a real (if unlikely) user could be on.
      final path = _databaseStampedAt(dir, kMinSupportedSchemaVersion - 1);
      final db = CompendiumDatabase(NativeDatabase(File(path)));

      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(isA<StateError>()),
      );
      await db.close();

      // Crucially, the refusal must not have stamped the file forward: a
      // half-migrated database mislabelled at head is exactly what the guard
      // exists to prevent.
      final raw = sqlite3.sqlite3.open(path);
      addTearDown(raw.close);
      expect(
        raw.select('PRAGMA user_version').first.columnAt(0),
        kMinSupportedSchemaVersion - 1,
        reason: 'a refused database must be left exactly as it was',
      );
    });
  });

  test('a database at the floor still opens and migrates to head', () async {
    // The other half of the guard: it must refuse what is below the floor
    // without refusing the floor itself. A guard off by one here would strand
    // every supported user, which is a worse failure than the one it prevents.
    //
    // This uses the real committed floor fixture rather than a stamped empty
    // file, because "it opened" is only meaningful for a database that actually
    // has the floor version's tables in it.
    final root = await packageRootPath();
    final source = File(
      p.join(
        root,
        'test',
        'storage',
        'fixtures',
        'v$kMinSupportedSchemaVersion.sqlite',
      ),
    );
    expect(
      source.existsSync(),
      isTrue,
      reason: 'the floor version must keep its fixture',
    );
    final path = p.join(dir.path, 'floor.sqlite');
    await source.copy(path);

    final db = CompendiumDatabase(NativeDatabase(File(path)));
    await expectLater(db.customSelect('SELECT 1').get(), completes);
    await db.close();

    final raw = sqlite3.sqlite3.open(path);
    addTearDown(raw.close);
    expect(
      raw.select('PRAGMA user_version').first.columnAt(0),
      kCompendiumSchemaVersion,
      reason: 'a floor database must migrate all the way to head',
    );
  });
}
