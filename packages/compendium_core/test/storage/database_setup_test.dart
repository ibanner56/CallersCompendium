import 'dart:async';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/storage/database.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

/// Device Sync runs its pass in a worker isolate that opens the app's database
/// file on a second connection, so both connections need
/// [applyCompendiumSqliteSetup]. These guards pin the two properties that make
/// that safe; sqlite's defaults (rollback journal, no busy timeout) fail both.
void main() {
  late Directory directory;
  late String path;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('compendium-db-setup');
    path = '${directory.path}/compendium.sqlite';
  });

  tearDown(() => directory.delete(recursive: true));

  test('enables WAL and a busy timeout on a file-backed connection', () async {
    final db = CompendiumDatabase(
      NativeDatabase(File(path), setup: applyCompendiumSqliteSetup),
    );
    addTearDown(db.close);

    final journalMode = await db
        .customSelect('PRAGMA journal_mode')
        .getSingle();
    expect(journalMode.data.values.single, 'wal');

    final busyTimeout = await db
        .customSelect('PRAGMA busy_timeout')
        .getSingle();
    expect(busyTimeout.data.values.single, compendiumSqliteBusyTimeoutMs);
  });

  test(
    'a second connection waits for an open write instead of failing',
    () async {
      // `holder` stands in for the sync worker: its own connection, on this
      // isolate. `writer` stands in for the app, whose connection drift owns on
      // a different isolate — the arrangement production actually has, and the
      // reason a blocking busy handler on one side cannot stall the other.
      final holder = CompendiumDatabase(
        NativeDatabase(File(path), setup: applyCompendiumSqliteSetup),
      );
      addTearDown(holder.close);
      await holder.customSelect('SELECT 1').get();
      final writer = CompendiumDatabase(
        NativeDatabase.createInBackground(
          File(path),
          setup: applyCompendiumSqliteSetup,
        ),
      );
      addTearDown(writer.close);
      await writer.customSelect('SELECT 1').get();

      final release = Completer<void>();
      final transactionOpen = Completer<void>();
      final transaction = holder.transaction(() async {
        await holder
            .into(holder.tags)
            .insert(TagsCompanion.insert(id: 'held', name: 'Held'));
        transactionOpen.complete();
        await release.future;
      });
      await transactionOpen.future;

      // A sanity check that the transaction really is open and uncommitted,
      // not a proof of WAL: a rollback-journal writer holds only RESERVED
      // until it commits, so this read would pass either way. The journal mode
      // itself is asserted directly in the test above.
      final counted = await writer
          .customSelect('SELECT COUNT(*) AS count FROM tags')
          .getSingle();
      expect(counted.data['count'], 0);

      // busy_timeout: a competing write waits rather than failing outright.
      // Without it this is exactly the "database is locked" failure an app
      // write hits when it lands during an inbound sync apply.
      var written = false;
      Object? writeError;
      final write = writer
          .into(writer.tags)
          .insert(TagsCompanion.insert(id: 'waiting', name: 'Waiting'))
          .then<void>((_) => written = true)
          .onError<Object>((error, _) => writeError = error);

      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(
        writeError,
        isNull,
        reason: 'the competing write must wait, not fail',
      );
      expect(written, isFalse);

      release.complete();
      await transaction;
      await write;

      expect(writeError, isNull);
      expect(written, isTrue);
      final total = await writer
          .customSelect('SELECT COUNT(*) AS count FROM tags')
          .getSingle();
      expect(total.data['count'], 2);
    },
  );
}
