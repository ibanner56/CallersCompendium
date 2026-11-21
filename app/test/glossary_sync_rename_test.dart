import 'package:compendium_app/src/glossary/custom_figures.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two devices each made a figure of their own with the same name, and one
/// of them edited theirs later (#709). Whichever device reads them, the one
/// flagged for rename is the later-*created* one: an edit cannot change it,
/// which holds only while sync carries `created_at` unchanged.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  CompendiumRepositories device() => CompendiumRepositories(
    CompendiumDatabase(NativeDatabase.memory()),
    contraTaxonomy,
  );

  UserGlossaryEntry figure(String id, DateTime createdAt) => UserGlossaryEntry(
    id: id,
    kindName: UserGlossaryEntryKind.compound.name,
    name: 'Grand spiral',
    definition: 'A spiral.',
    description: 'All the way round.',
    payload: const {
      'params': <Object?>[],
      'figures': <Object?>[],
      'bindings': <Object?>[],
    },
    createdAt: createdAt,
  );

  Future<SyncMergeCandidate> published(
    CompendiumRepositories repos,
    String id,
  ) async => (await CompendiumSyncStorage(
    repos,
  ).snapshot()).local[(kind: SyncRecordKind.glossaryEntry, recordId: id)]!;

  test('the later-created of two same-named entries arriving from peers is '
      'the one flagged, though the earlier one was edited last', () async {
    final first = DateTime.utc(2026, 9, 1);
    final second = DateTime.utc(2026, 9, 2);
    final edit = DateTime.utc(2026, 9, 3);

    final older = device();
    final newer = device();
    final reader = device();
    addTearDown(() async {
      for (final repos in [older, newer, reader]) {
        await repos.db.close();
      }
    });

    await older.userGlossary.upsert(figure('older', first), at: first);
    await newer.userGlossary.upsert(figure('newer', second), at: second);
    await older.userGlossary.upsert(
      figure('older', first).copyWith(definition: 'Edited after the other.'),
      at: edit,
    );

    final result = await const SyncApplyEngine().apply(
      candidates: [
        SyncMergeCandidate(blob: (await published(newer, 'newer')).blob),
        SyncMergeCandidate(blob: (await published(older, 'older')).blob),
      ],
      storage: CompendiumSyncStorage(reader),
    );
    expect(result.reports, isEmpty);

    final items = resolveCustomGlossary(
      await reader.userGlossary.listAll(),
      taxonomy: contraTaxonomy,
    );
    final flagged = {
      for (final item in items)
        if (item.renameNeeded) item.entry.id,
    };
    expect(flagged, {'newer'});
  });
}
