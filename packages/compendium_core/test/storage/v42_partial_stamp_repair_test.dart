// A test build stamped `user_version` 42 while v42 was unreleased, before
// later pieces joined it, so such a file lacks those columns, and no
// `onUpgrade` step adds them (it is already at 42). Loading the dances then
// threw a `_TypeError` on the NULL read from a missing non-null column. Only
// `beforeOpen` repairs it.
//
// Mutation this catches: drop the `_ensureV42Schema` call from `beforeOpen`.
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

const _danceColumns = [
  'alternate_titles',
  'barnes_reference',
  'square_kind',
  'repeat_order',
  'repeat_order_text',
  'new_partner',
  'new_partner_text',
  'singing',
];

const _programColumns = [
  'calendar_event_key',
  'start_minute',
  'end_minute',
  'lesson_minute',
  'arrival_minute',
  'calendar_event_fingerprint',
  'calendar_written_at',
  'calendar_flag',
];

void main() {
  test(
    'a file stamped v42 without its later v42 pieces is repaired on open',
    () async {
      final raw = sqlite3.sqlite3.openInMemory();
      addTearDown(raw.close);

      final fresh = CompendiumDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );
      await fresh.customSelect('SELECT 1').get();
      await fresh.close();

      for (final column in _danceColumns) {
        raw.execute('ALTER TABLE dances DROP COLUMN $column');
      }
      for (final column in _programColumns) {
        raw.execute('ALTER TABLE programs DROP COLUMN $column');
      }
      raw.execute('PRAGMA user_version = 42');

      final reopened = CompendiumDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );
      addTearDown(reopened.close);
      await reopened.customSelect('SELECT 1').get();

      Set<Object?> columnsOf(String table) => raw
          .select("SELECT name FROM pragma_table_info('$table')")
          .map((r) => r['name'])
          .toSet();
      expect(columnsOf('dances'), containsAll(_danceColumns));
      expect(columnsOf('programs'), containsAll(_programColumns));
    },
  );
}
