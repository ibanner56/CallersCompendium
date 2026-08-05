// Schema *shape* verification (issue #828).
//
// `migration_test.dart` covers migration **data semantics** — sentinels
// survive, rebuild markers are set, `group_idx` is repopulated from
// `figures_json`. Nothing there asserts that a database which arrived at head
// by migration is structurally the same as one created fresh at head, and
// divergence between the two paths is a quiet bug class.
//
// This suite closes that gap: for every historical schema version, it builds a
// database at that version from a *generated* drift schema dump
// (`drift_schemas/`, see the README there), runs the real
// `CompendiumDatabase.migration` over it, and compares the resulting structure
// against a freshly created head database.
//
// ## Why the comparison is PRAGMA-derived rather than SQL-text
//
// The two paths legitimately produce different DDL *text* for the same
// structure, so comparing `sqlite_master.sql` would report differences that
// are not differences:
//
//   * `m.addColumn` issues `ALTER TABLE … ADD COLUMN`, and SQLite appends the
//     new column to the stored `CREATE TABLE` text. A migrated table therefore
//     lists columns in migration order, while a fresh one lists them in
//     declaration order.
//   * The four raw lookup indices are created by this repo with
//     `IF NOT EXISTS` (they are applied from both `onCreate` and an upgrade
//     step), but a database instantiated from a generated schema snapshot
//     creates them without it — drift's schema writer does not round-trip that
//     clause.
//
// Asking SQLite itself for the structure via `PRAGMA table_info` /
// `index_list` / `index_info` / `foreign_key_list` sidesteps both: SQLite has
// already parsed the DDL, so the comparison is over structure, not syntax.
// This schema declares no CHECK constraints, which are the one thing those
// pragmas would not surface.
//
// ## Why this covers what drift's own `SchemaVerifier` would not
//
// Five entities here are created by raw `customStatement` DDL rather than
// being drift-managed: the `dance_fts` FTS5 virtual table and the four lookup
// indices. They are maintained by hand in two places (`onCreate` and an
// upgrade step), which makes them the *likeliest* to diverge, yet a schema
// dumped from Dart source would not contain them at all. Taking the dumps from
// the committed fixture databases keeps them in scope, and the comparison
// below treats them exactly like any other entity.
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

import 'generated/schema.dart';

/// Rows of a raw query, as plain maps.
Future<List<Map<String, Object?>>> _rows(
  DatabaseConnectionUser db,
  String sql,
) async {
  final result = await db.customSelect(sql).get();
  return [for (final row in result) row.data];
}

/// Collapses DDL whitespace and identifier quoting so that two spellings of
/// the same statement compare equal.
///
/// Only used for virtual tables, whose module arguments (`fts5(… UNINDEXED …)`)
/// are opaque to `PRAGMA table_info` and so have to be compared as text.
String _normalizeDdl(String sql) {
  var out = sql.replaceAll(RegExp(r'["`\[\]]'), '');
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  out = out.replaceAll(RegExp(r'\s*([(),])\s*'), r'$1');
  return out;
}

/// A structural description of every schema entity, keyed by entity.
///
/// Values are deliberately human-readable: a failure prints the two
/// descriptions, so the difference should be legible without a debugger.
Future<Map<String, String>> _describeSchema(DatabaseConnectionUser db) async {
  final description = <String, String>{};

  final entities = await _rows(
    db,
    "SELECT type, name, sql FROM sqlite_master "
    "WHERE name NOT LIKE 'sqlite\\_%' ESCAPE '\\' ORDER BY name",
  );

  for (final entity in entities) {
    final name = entity['name'] as String;
    final type = entity['type'] as String;
    final sql = entity['sql'] as String?;

    if (type != 'table') {
      // Indices are described structurally below, alongside their table.
      // Anything else (a trigger or view, none of which this schema declares
      // today) is compared as normalized text so it cannot slip through
      // unverified if one is added later.
      if (type != 'index') {
        description['$type:$name'] = _normalizeDdl(sql ?? '');
      }
      continue;
    }

    final isVirtual =
        sql != null &&
        RegExp(
          r'^\s*create\s+virtual\s+table',
          caseSensitive: false,
        ).hasMatch(sql);

    final columns = await _rows(db, 'PRAGMA table_info($name)');
    // Sorted by column name: `ALTER TABLE … ADD COLUMN` appends, so ordinal
    // position legitimately differs between the migrated and fresh paths.
    final columnDescriptions = [
      for (final column in columns)
        '${column['name']} '
            'type=${column['type']} '
            'notnull=${column['notnull']} '
            'default=${column['dflt_value']} '
            'pk=${column['pk']}',
    ]..sort();
    description['table:$name'] = columnDescriptions.join('; ');

    if (isVirtual) {
      // `PRAGMA table_info` reports a virtual table's columns but not its
      // module or its module arguments, so those are compared as text.
      description['virtual:$name'] = _normalizeDdl(sql);
      // Virtual tables have no queryable indices or foreign keys.
      continue;
    }

    final indices = await _rows(db, 'PRAGMA index_list($name)');
    for (final index in indices) {
      final indexName = index['name'] as String;
      final indexColumns = await _rows(db, 'PRAGMA index_info($indexName)');
      final columnNames = [
        for (final column in indexColumns) '${column['name']}',
      ];
      description['index:$indexName'] =
          'on=$name '
          'unique=${index['unique']} '
          'origin=${index['origin']} '
          'partial=${index['partial']} '
          'columns=${columnNames.join(',')}';
    }

    final foreignKeys = await _rows(db, 'PRAGMA foreign_key_list($name)');
    final foreignKeyDescriptions = [
      for (final fk in foreignKeys)
        '${fk['from']} -> ${fk['table']}.${fk['to']} '
            'on_update=${fk['on_update']} on_delete=${fk['on_delete']}',
    ]..sort();
    if (foreignKeyDescriptions.isNotEmpty) {
      description['fk:$name'] = foreignKeyDescriptions.join('; ');
    }
  }

  return description;
}

/// Opens an empty in-memory database for a migration run.
sqlite3.Database _emptyDatabase() => sqlite3.sqlite3.openInMemory();

void main() {
  group('drift schema dumps', () {
    test('cover exactly the supported versions, floor to head', () {
      expect(
        GeneratedHelper.versions,
        [
          for (
            var v = kMinSupportedSchemaVersion;
            v <= kCompendiumSchemaVersion;
            v++
          )
            v,
        ],
        reason:
            'every supported schema version needs a dump in drift_schemas/, '
            'and no retired one may linger — see the README there for how to '
            'add one when bumping kCompendiumSchemaVersion, and how to retire '
            'one when raising kMinSupportedSchemaVersion',
      );
    });
  });

  group('migrating to head yields the fresh head schema', () {
    late Map<String, String> freshSchema;

    setUpAll(() async {
      final raw = sqlite3.sqlite3.openInMemory();
      final fresh = CompendiumDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );
      // Opening runs `onCreate` (and `beforeOpen`), establishing head.
      await fresh.customSelect('SELECT 1').get();
      freshSchema = await _describeSchema(fresh);
      await fresh.close();
      raw.close();
    });

    for (
      var version = kMinSupportedSchemaVersion;
      version < kCompendiumSchemaVersion;
      version++
    ) {
      final startVersion = version;

      test('from v$startVersion', () async {
        final raw = _emptyDatabase();

        // Instantiate the historical schema from its generated snapshot.
        final atVersion = GeneratedHelper().databaseForVersion(
          NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
          startVersion,
        );
        await atVersion.customSelect('SELECT 1').get();
        await atVersion.close();

        expect(
          _userVersionOf(raw),
          startVersion,
          reason: 'the snapshot database should be stamped at its own version',
        );

        // Now run the real migration over it, all the way to head.
        //
        // The target is always head, never an intermediate version. Drift's
        // own `SchemaVerifier.migrateAndValidate(db, n)` opens the database
        // through a delegate that *reports* `schemaVersion == n`, which is the
        // same untruth that #803 recorded: because every `onUpgrade` step here
        // keys on `from` alone and none consult `to`, the later steps still run
        // and drift then stamps `user_version = n` — a database claiming not to
        // have a column it demonstrably has. Migrating to head is the only
        // target for which that cannot happen.
        final migrated = CompendiumDatabase(
          NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
        );
        await migrated.customSelect('SELECT 1').get();

        expect(
          _userVersionOf(raw),
          kCompendiumSchemaVersion,
          reason: 'the migration should have stamped the database at head',
        );

        final migratedSchema = await _describeSchema(migrated);
        await migrated.close();
        raw.close();

        // Compare the entity sets first: a missing or extra table/index is the
        // headline failure and should say exactly which one, rather than
        // printing two hundred-entry sets and leaving the reader to diff them.
        final freshNames = freshSchema.keys.toSet();
        final migratedNames = migratedSchema.keys.toSet();
        expect(
          (freshNames.difference(migratedNames).toList()..sort()),
          isEmpty,
          reason:
              'migrating from v$startVersion did not produce these entities, '
              'which a freshly created head database has',
        );
        expect(
          (migratedNames.difference(freshNames).toList()..sort()),
          isEmpty,
          reason:
              'migrating from v$startVersion produced these extra entities, '
              'which a freshly created head database does not have',
        );

        for (final entry in freshSchema.entries) {
          expect(
            migratedSchema[entry.key],
            entry.value,
            reason:
                '${entry.key} differs after migrating from v$startVersion '
                '(left: migrated, right: freshly created at head)',
          );
        }
      });
    }
  });
}

int _userVersionOf(sqlite3.Database raw) =>
    raw.select('PRAGMA user_version').first.columnAt(0) as int;
