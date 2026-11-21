import 'package:compendium_app/src/sync/sync_invalidation.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sync worker writes through its own connection, so the UI's watches
/// hear of an applied kind only through [markSyncAppliedTablesUpdated].
void main() {
  late CompendiumDatabase database;
  setUp(() => database = CompendiumDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  Future<Set<String>> invalidated(Set<SyncRecordKind> kinds) async {
    final updates = <String>{};
    final sub = database.tableUpdates().listen(
      (batch) => updates.addAll(batch.map((u) => u.table)),
    );
    markSyncAppliedTablesUpdated(database, kinds);
    await pumpEventQueue();
    await sub.cancel();
    return updates;
  }

  test('every kind invalidates something', () async {
    for (final kind in SyncRecordKind.values) {
      expect(await invalidated({kind}), isNotEmpty, reason: kind.name);
    }
  });

  test('an applied glossary entry refreshes what watches the user\'s own '
      'figures, and a note what watches notes (#709)', () async {
    expect(
      await invalidated({SyncRecordKind.glossaryEntry}),
      contains('user_glossary_entries'),
    );
    expect(
      await invalidated({SyncRecordKind.figureNote}),
      contains('figure_notes'),
    );
  });

  test('a glossary watch re-emits when a sync pass applied an entry', () async {
    final repos = CompendiumRepositories(database, contraTaxonomy);
    final emissions = <int>[];
    final sub = repos.userGlossary.watchAll().listen(
      (entries) => emissions.add(entries.length),
    );
    await pumpEventQueue();
    // A write the stream query manager is not told of, as the worker's is.
    await database.customStatement(
      "INSERT INTO user_glossary_entries (id, kind, name, definition, "
      "description, created_at) VALUES ('e1', 'compound', 'n', 'd', 'x', 0)",
    );
    await pumpEventQueue();
    expect(emissions, [0], reason: 'not told yet');
    markSyncAppliedTablesUpdated(database, {SyncRecordKind.glossaryEntry});
    await pumpEventQueue();
    expect(emissions, [0, 1]);
    await sub.cancel();
  });
}
