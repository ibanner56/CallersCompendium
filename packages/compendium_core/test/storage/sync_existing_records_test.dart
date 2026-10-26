// `existingRecords` tells a record a hard delete took from one that is only
// edited or tombstoned. The coordinator reads it under the write lock before
// marking a publication built outside it, and redoes the build under the lock
// for any record it reports gone, so a kind read against the wrong key column
// would not lose data: it would make every pass that publishes that kind
// rebuild under the lock. Each kind with a key of its own is pinned here.
import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

final _stamp = DateTime.utc(2026, 7, 15, 12);

void main() {
  late CompendiumRepositories repositories;
  late CompendiumSyncStorage storage;

  setUp(() {
    final db = openTestDatabase();
    addTearDown(db.close);
    repositories = CompendiumRepositories(db, contraTaxonomy);
    storage = CompendiumSyncStorage(repositories);
  });

  test('reports live and tombstoned rows, and not hard-deleted ones', () async {
    await repositories.dances.create(sampleDance(id: 'live'));
    await repositories.dances.create(sampleDance(id: 'tombstoned'));
    await repositories.dances.softDelete('tombstoned', at: _stamp);
    await repositories.dances.create(sampleDance(id: 'erased'));
    await repositories.dances.hardDelete(['erased']);

    const live = (kind: SyncRecordKind.dance, recordId: 'live');
    const tombstoned = (kind: SyncRecordKind.dance, recordId: 'tombstoned');
    const erased = (kind: SyncRecordKind.dance, recordId: 'erased');
    const never = (kind: SyncRecordKind.dance, recordId: 'never');

    expect(await storage.existingRecords({live, tombstoned, erased, never}), {
      live,
      tombstoned,
    });
  });

  test('reads each kind by its own key', () async {
    // ignore: unused_result
    await repositories.tags.upsert(
      Tag(id: 't1', name: 'One'),
      at: _stamp,
    );
    await repositories.settings.set('custom_dialects', ['x'], at: _stamp);
    await repositories.figureNotes.set('swing', 'Notes.', at: _stamp);

    const tag = (kind: SyncRecordKind.tag, recordId: 't1');
    const setting = (kind: SyncRecordKind.setting, recordId: 'custom_dialects');
    const note = (kind: SyncRecordKind.figureNote, recordId: 'swing');
    // The same ids under another kind name a different table.
    const notATag = (kind: SyncRecordKind.tag, recordId: 'swing');
    const notADance = (kind: SyncRecordKind.dance, recordId: 't1');

    expect(
      await storage.existingRecords({tag, setting, note, notATag, notADance}),
      {tag, setting, note},
    );
  });
}
