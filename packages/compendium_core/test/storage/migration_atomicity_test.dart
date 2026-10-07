// A failed upgrade must leave the file exactly as it was.
//
// drift 2.34.3 runs `onUpgrade` with **no** transaction of its own and stamps
// `user_version` only after the whole open hook returns — after `onUpgrade`
// *and* after `beforeOpen`
// (`lib/src/runtime/executor/helpers/engines.dart`, `_runMigrations`;
// `lib/src/runtime/api/db_base.dart`, `beforeOpen`). Every step in
// `CompendiumDatabase.onUpgrade` therefore commits as it goes, so an exception
// — or a process death — after one step and before the stamp leaves a file
// whose `user_version` says "v37" but whose tables are already partly at v38.
// A step that is not idempotent (the since-retired v35 `program_slots` rebuild
// was the case that found this: re-entered, its `INSERT … SELECT
// planned_minutes` failed with `no such column`) then fails on every later
// open, and the collection never opens again; the pre-migration snapshot
// exists on disk but no app path restores it.
//
// `onUpgrade` closes that window two ways: every step runs inside one
// `transaction()`, and that transaction's own last statement stamps
// `user_version` itself, so the schema and the version commit or roll back
// together — closing the remaining window between this transaction's commit
// and drift's own (redundant) stamp, which still has the whole of
// `beforeOpen` to run first.
//
// The first test injects a throw right after the v38 step's first `addColumn`
// and asserts the rollback: the stamp is unchanged *and* the added column is
// gone, so a real reopen then migrates cleanly. (The v38 step is idempotent, so
// the reopen would survive a leaked column; the column assertion is what
// proves the rollback.)
//
// Mutation the first test catches: remove the `transaction()` wrap.
// `user_version` still reads 37 (drift never stamped it), but `programs` has
// already gained `pay_minor_units`.
//
// The second test lets the transaction commit and then throws from
// `beforeOpen`, before drift's own stamp would run, and asserts
// `user_version` already reads the new value.
//
// Mutation the second test catches: delete the explicit `PRAGMA user_version`
// stamp and rely on drift's own stamp again. `beforeOpen` throws before drift
// gets to run it, so `user_version` reads the OLD value even though every
// table is already at head — the exact symptom this PR fixes.
import 'package:compendium_core/src/storage/database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

import 'generated/schema.dart';

/// Throws after the `programs.pay_minor_units` column is added, i.e. after the
/// v38 step's first DDL has run and before drift would stamp `user_version`.
class _ThrowAfterPayColumnAdded extends Migrator {
  _ThrowAfterPayColumnAdded(super.database);

  /// `PRAGMA foreign_keys` as seen from inside `onUpgrade`, recorded so the
  /// claim in `database.dart` — that foreign keys are OFF for the whole of
  /// `onUpgrade`, which is what makes the pragma toggle inside `alterTable` a
  /// non-event under the enclosing transaction — is checked, not asserted.
  /// (No surviving step calls `alterTable`, so this samples at `addColumn`.)
  final foreignKeysSeen = <bool>[];

  @override
  Future<void> addColumn(
    TableInfo<Table, dynamic> table,
    GeneratedColumn column,
  ) async {
    foreignKeysSeen.add(
      (await database.customSelect('PRAGMA foreign_keys').getSingle())
          .read<bool>('foreign_keys'),
    );
    await super.addColumn(table, column);
    if (table.actualTableName == 'programs' &&
        column.name == 'pay_minor_units') {
      throw StateError('injected failure after the v38 addColumn');
    }
  }
}

class _FailingAfterV38Column extends CompendiumDatabase {
  _FailingAfterV38Column(super.executor);

  late final migrator = _ThrowAfterPayColumnAdded(this);

  @override
  Migrator createMigrator() => migrator;
}

/// Reuses the real `onCreate`/`onUpgrade` but replaces `beforeOpen` with a
/// throw, simulating a process death in the window between this PR's
/// in-transaction `user_version` stamp and drift's own (later, redundant)
/// stamp — which drift runs only after `beforeOpen` returns.
class _ThrowInBeforeOpen extends CompendiumDatabase {
  _ThrowInBeforeOpen(super.executor);

  @override
  MigrationStrategy get migration {
    final real = super.migration;
    return MigrationStrategy(
      onCreate: real.onCreate,
      onUpgrade: real.onUpgrade,
      beforeOpen: (details) async {
        throw StateError('simulated process death before drift\'s own stamp');
      },
    );
  }
}

void main() {
  test('a throw mid-upgrade rolls back every earlier step', () async {
    final raw = sqlite3.sqlite3.openInMemory();
    addTearDown(raw.close);

    final historical = GeneratedHelper().databaseForVersion(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      37,
    );
    await historical.customSelect('SELECT 1').get();
    await historical.close();
    expect(_userVersion(raw), 37);
    expect(_columnsOf(raw, 'programs'), isNot(contains('pay_minor_units')));

    final failing = _FailingAfterV38Column(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    await expectLater(
      failing.customSelect('SELECT 1').get(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('injected failure'),
        ),
      ),
    );
    try {
      await failing.close();
    } on Object {
      // A database whose open failed may refuse to close cleanly; the raw
      // connection is what the assertions below read.
    }

    expect(
      failing.migrator.foreignKeysSeen,
      [false],
      reason:
          'foreign keys must be OFF during onUpgrade (beforeOpen turns them ON '
          'afterwards); if this ever reads true, alterTable will try to toggle '
          'the pragma inside the migration transaction, where it is a no-op',
    );
    expect(
      _userVersion(raw),
      37,
      reason: 'drift stamps user_version only after onUpgrade returns',
    );
    expect(
      _columnsOf(raw, 'programs'),
      isNot(contains('pay_minor_units')),
      reason:
          'the v38 addColumn ran before the throw; without a transaction '
          'around the step body the column stays committed under a '
          'user_version that still says v37',
    );

    // The proof that the rollback matters: a real reopen now migrates.
    final reopened = CompendiumDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    addTearDown(reopened.close);
    await reopened.customSelect('SELECT 1').get();
    expect(_userVersion(raw), kCompendiumSchemaVersion);
    expect(
      _columnsOf(raw, 'programs'),
      containsAll(['pay_minor_units', 'pay_currency']),
    );
  });

  test("user_version already reads the new value if the process dies in "
      "beforeOpen, before drift's own stamp runs", () async {
    final raw = sqlite3.sqlite3.openInMemory();
    addTearDown(raw.close);

    final historical = GeneratedHelper().databaseForVersion(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      37,
    );
    await historical.customSelect('SELECT 1').get();
    await historical.close();
    expect(_userVersion(raw), 37);

    final failing = _ThrowInBeforeOpen(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    await expectLater(
      failing.customSelect('SELECT 1').get(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('simulated process death'),
        ),
      ),
    );
    try {
      await failing.close();
    } on Object {
      // As above: a database whose open failed may not close cleanly.
    }

    expect(
      _userVersion(raw),
      kCompendiumSchemaVersion,
      reason:
          "the migration transaction's own last statement already stamped "
          'user_version before beforeOpen ran, so the throw here — which '
          "pre-empts drift's own stamp — has nothing left to leave stale",
    );

    // The proof that this matters: a real reopen treats the file as
    // already at head, so it does not re-enter any onUpgrade step, and
    // beforeOpen's own repair completes normally.
    final reopened = CompendiumDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    addTearDown(reopened.close);
    await reopened.customSelect('SELECT 1').get();
    expect(_userVersion(raw), kCompendiumSchemaVersion);
  });
}

int _userVersion(sqlite3.Database raw) =>
    raw.select('PRAGMA user_version').first.columnAt(0) as int;

Set<String> _columnsOf(sqlite3.Database raw, String table) => {
  for (final row in raw.select("SELECT name FROM pragma_table_info('$table')"))
    row['name'] as String,
};
