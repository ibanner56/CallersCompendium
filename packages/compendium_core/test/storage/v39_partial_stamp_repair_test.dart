// A development build stamped `user_version` 39 before the v39 step created
// everything it now does, so such a file lacks `peer_manifests` and the
// published-manifest columns, and `onUpgrade`'s v39 step never runs for it
// (it is already at 39). Every sync pass then died on "no such table:
// peer_manifests". Only `beforeOpen` repairs it, on the migrating open that
// also takes it to the current schema.
//
// Mutation this catches: drop the `_ensureV39Schema` call from `beforeOpen`.
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

void main() {
  test('a file stamped v39 without its v39 pieces is repaired on open', () async {
    final raw = sqlite3.sqlite3.openInMemory();
    addTearDown(raw.close);

    final fresh = CompendiumDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    await fresh.customSelect('SELECT 1').get();
    await fresh.close();

    raw.execute('DROP TABLE peer_manifests');
    raw.execute(
      'ALTER TABLE baseline_state DROP COLUMN published_manifest_hash',
    );
    raw.execute('ALTER TABLE baseline_state DROP COLUMN published_verified_at');
    // What a pre-release build stamped: v39, so without anything a later
    // schema added either. The reopen then upgrades it as well as repairing it.
    raw.execute('DROP TABLE user_glossary_entries');
    raw.execute('DROP TABLE figure_notes');
    raw.execute('PRAGMA user_version = 39');

    final reopened = CompendiumDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    addTearDown(reopened.close);
    await reopened.customSelect('SELECT 1').get();

    final tables = raw
        .select("SELECT name FROM sqlite_master WHERE name = 'peer_manifests'")
        .length;
    final columns = raw
        .select("SELECT name FROM pragma_table_info('baseline_state')")
        .map((r) => r['name'])
        .toSet();
    expect(tables, 1);
    expect(
      columns,
      containsAll(['published_manifest_hash', 'published_verified_at']),
    );
    expect(
      raw.select('PRAGMA user_version').first.columnAt(0),
      kCompendiumSchemaVersion,
    );
    expect(
      raw
          .select(
            "SELECT name FROM sqlite_master WHERE name IN "
            "('user_glossary_entries', 'figure_notes')",
          )
          .length,
      2,
    );
  });
}
