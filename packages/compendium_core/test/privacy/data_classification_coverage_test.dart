import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';

/// Coverage ratchet for the data-classification catalogue.
///
/// Walks the live schema and asserts every column has an entry in
/// [fieldClassifications]. A new column with no classification fails here, so
/// the catalogue cannot fall behind the schema the way a hand-maintained
/// markdown table would.
///
/// Precedent: `app/test/l10n/no_hardcoded_ui_strings_test.dart`, the i18n
/// ratchet — same shape (enumerate the real artefact, diff against a declared
/// set, fail with a paste-ready list), but reflecting over the database rather
/// than scanning source, so formatting cannot fool it.
///
/// Covers both halves of the schema:
/// - drift's typed tables, via `allTables`;
/// - raw virtual tables created in `database.dart` (`dance_fts`), which are
///   absent from `allTables` and would otherwise be invisible here. Their
///   columns are read back with `pragma_table_info` rather than hardcoded, so
///   adding a column to the FTS index is caught too.
void main() {
  late CompendiumDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  /// Tables that exist in SQLite but not as drift-typed tables. Declared, so a
  /// newly added untyped table fails the reconciliation test below instead of
  /// silently escaping classification.
  const untypedTables = {'dance_fts', 'dance_substring_fts'};

  Future<List<String>> columnsOf(String table) async {
    final rows = await db
        .customSelect("SELECT name FROM pragma_table_info('$table')")
        .get();
    return [for (final r in rows) r.read<String>('name')];
  }

  Future<Set<String>> schemaKeys() async {
    final keys = <String>{
      for (final table in db.allTables)
        for (final column in table.$columns)
          '${table.actualTableName}.${column.name}',
    };
    for (final table in untypedTables) {
      for (final column in await columnsOf(table)) {
        keys.add('$table.$column');
      }
    }
    return keys;
  }

  test('every schema column has a classification', () async {
    final missing =
        ((await schemaKeys())..removeAll(fieldClassifications.keys)).toList()
          ..sort();

    expect(
      missing,
      isEmpty,
      reason:
          'These columns have no entry in fieldClassifications. Add one to\n'
          'lib/src/privacy/field_registry.dart; see\n'
          'docs/dev/data-classification.md for how to choose:\n\n'
          '${missing.map((k) => "  '$k': ,").join('\n')}\n',
    );
  });

  test('no classification refers to a column that no longer exists', () async {
    final stale = fieldClassifications.keys.toSet()
      ..removeAll(await schemaKeys());

    expect(
      stale.toList()..sort(),
      isEmpty,
      reason:
          'These entries in fieldClassifications name columns that are not in '
          'the schema. A renamed or dropped column must be updated here too.',
    );
  });

  test('every SQLite table is drift-typed or declared untyped', () async {
    final typed = {for (final t in db.allTables) t.actualTableName};
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .get();

    // FTS5 creates shadow tables (`<name>_data`, `_idx`, `_docsize`,
    // `_config`) alongside each virtual table. They are storage internals
    // holding no user data of their own, and are excluded by prefix.
    bool isShadow(String name) =>
        untypedTables.any((v) => name.startsWith('${v}_'));

    final found = {
      for (final r in rows)
        if (!isShadow(r.read<String>('name'))) r.read<String>('name'),
    };

    expect(
      found.difference(typed.union(untypedTables)).toList()..sort(),
      isEmpty,
      reason:
          'A table exists in SQLite that is neither drift-typed nor declared '
          'in untypedTables. Declare it there so its columns are classified, '
          'or the catalogue has a blind spot.',
    );
  });
}
