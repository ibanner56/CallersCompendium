// `beforeOpen`'s FTS repair must run on the open that migrates, too.
//
// drift runs `onUpgrade` and only then the `beforeOpen` callback
// (`lib/src/runtime/api/db_base.dart`), so by the time the repair looks at
// `sqlite_master` the schema is already at head. The repair used to return
// early whenever `versionBefore != kCompendiumSchemaVersion`, on the stated
// grounds that it would otherwise "schedule a duplicate rebuild marker while
// … still traversing the old schema" — which is not the order drift runs
// things in, and the presence check makes a duplicate marker impossible
// anyway. The cost of the early return: a v35+ file missing an FTS table
// migrated, failed once in the post-open sweeps, and healed on the *next*
// launch.
//
// Mutation this catches: restore the early return. The dropped table is then
// absent after the migrating open and no rebuild marker is set.
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

import 'generated/schema.dart';

void main() {
  test('a dropped FTS table is recreated on the open that migrates', () async {
    final raw = sqlite3.sqlite3.openInMemory();
    addTearDown(raw.close);

    // v35 is the floor snapshot. No surviving `onUpgrade` step creates an FTS
    // table, so a table missing here is missing when `beforeOpen` runs.
    final historical = GeneratedHelper().databaseForVersion(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      kMinSupportedSchemaVersion,
    );
    await historical.customSelect('SELECT 1').get();
    await historical.customStatement('DROP TABLE dance_substring_fts');
    await historical.close();
    expect(_ftsTables(raw), ['dance_fts']);

    final migrated = CompendiumDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    addTearDown(migrated.close);
    await migrated.customSelect('SELECT 1').get();

    expect(
      raw.select('PRAGMA user_version').first.columnAt(0),
      kCompendiumSchemaVersion,
    );
    expect(_ftsTables(raw), [
      'dance_fts',
      'dance_substring_fts',
    ], reason: 'beforeOpen must repair on a migrating open, not only at head');
    expect(
      await migrated
          .customSelect(
            'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get(),
      isNotEmpty,
      reason: 'a recreated index is empty until the derived rebuild runs',
    );
  });
}

List<String> _ftsTables(sqlite3.Database raw) => [
  for (final row in raw.select(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name IN ('dance_fts', 'dance_substring_fts') ORDER BY name",
  ))
    row['name'] as String,
];
