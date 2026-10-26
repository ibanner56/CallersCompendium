// The inbound apply's derived-index step (#1920). An apply batch used to end
// with a full `rebuildAllDerived()` inside its `BEGIN IMMEDIATE` transaction,
// whatever it applied: every app write waited on a rewrite of the whole
// search index, even for one setting. It now reindexes only the dances the
// batch can have changed. These tests pin both halves of that: a batch
// rewrites only those dances' rows, and what it leaves equals what a full
// rebuild of the same state writes — the equivalence a missed input breaks.
import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

final _local = DateTime.utc(2026, 10, 1, 9);
final _trashed = DateTime.utc(2026, 10, 1, 10);
final _peer = DateTime.utc(2026, 10, 2, 12);

const _derivedTables = ['dance_fts', 'dance_substring_fts', 'dance_figures'];

/// Records every statement that writes a derived table, and which dances
/// the FTS inserts among them were for.
final class _DerivedWrites extends QueryInterceptor {
  final statements = <String>[];
  final ftsInsertedFor = <String>{};

  void reset() {
    statements.clear();
    ftsInsertedFor.clear();
  }

  void _record(String statement, List<Object?> args) {
    final lower = statement.toLowerCase().trimLeft();
    if (lower.startsWith('select')) return;
    if (!_derivedTables.any(lower.contains)) return;
    statements.add(statement);
    if (lower.startsWith('insert into dance_fts')) {
      ftsInsertedFor.add(args.first! as String);
    }
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement, args);
    return super.runCustom(executor, statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement, args);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement, args);
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement, args);
    return super.runDelete(executor, statement, args);
  }
}

Map<String, Object?> _zoomPayload(String template) => {
  'form': 'contra',
  'template': template,
  'defaultBeats': 8,
  'params': [
    {'key': 'who', 'kind': 'dancerSet', 'default': 'neighbors'},
    {'key': 'hand', 'kind': 'handedness'},
  ],
};

void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repositories;
  late CompendiumSyncStorage storage;
  late _DerivedWrites writes;

  SyncRecordBlob blob(
    SyncRecordKind kind,
    Object entity, {
    DateTime? deletedAt,
  }) => syncRecordBlobForEntity(
    kind,
    entity,
    updatedAt: deletedAt ?? _peer,
    existenceAt: _peer,
    deletedAt: deletedAt,
    allowedCustomFieldIds: const {'cf-tempo'},
  )!;

  SyncRecordBlob setting() => SyncSettingsRecord(
    key: 'custom_dialects',
    value: null,
    updatedAt: _peer,
    deletedAt: null,
    existenceAt: _peer,
  ).toBlob()!;

  SyncRecordBlob zoom(String template) => blob(
    SyncRecordKind.glossaryEntry,
    StoredUserGlossaryEntry(
      id: 'zoom-id',
      kind: UserGlossaryEntryKind.customFigure.name,
      name: 'zoom',
      definition: 'A zoom.',
      description: 'Fast.',
      payloadJson: jsonEncode(_zoomPayload(template)),
      createdAt: _local,
    ),
  );

  Dance dance(
    String id, {
    String? title,
    List<String> authorIds = const [],
    List<SourceCitation> sourceCitations = const [],
    List<CustomFieldValue> customFields = const [],
    List<Figure>? figures,
    DateTime? updatedAt,
  }) => sampleDance(
    id: id,
    title: title ?? 'Dance $id',
    authorIds: authorIds,
    sourceCitations: sourceCitations,
    customFields: customFields,
    figures: figures,
    createdAt: _local,
    updatedAt: updatedAt ?? _local,
  );

  /// Every row of the three derived tables, in a stable order.
  Future<Map<String, List<Map<String, Object?>>>> derivedState() async => {
    for (final (table, order) in const [
      ('dance_figures', 'dance_id, idx'),
      ('dance_fts', 'dance_id'),
      ('dance_substring_fts', 'dance_id'),
    ])
      table: [
        for (final row
            in await db
                .customSelect('SELECT * FROM $table ORDER BY $order')
                .get())
          row.data,
      ],
  };

  /// Asserts the derived tables hold exactly what a full rebuild writes.
  Future<void> expectEquivalentToFullRebuild() async {
    final afterApply = await derivedState();
    await repositories.dances.rebuildAllDerived();
    expect(afterApply, await derivedState());
  }

  Future<SyncApplyResult> applyInbound(Iterable<SyncRecordBlob> blobs) async {
    writes.reset();
    final result = await const SyncApplyEngine().apply(
      candidates: [for (final b in blobs) SyncMergeCandidate(blob: b)],
      storage: storage,
    );
    expect(result.reports, isEmpty);
    expect(result.applied, hasLength(blobs.length));
    return result;
  }

  setUp(() async {
    writes = _DerivedWrites();
    db = CompendiumDatabase(NativeDatabase.memory().interceptWith(writes));
    repositories = CompendiumRepositories(db, contraTaxonomy);
    storage = CompendiumSyncStorage(repositories);

    // A library in which every derived-row input is cited by exactly one
    // dance, and one dance cites none of them.
    // ignore: unused_result
    await repositories.choreographers.upsert(
      Choreographer(id: 'c1', name: 'Mary Oldname'),
      at: _local,
    );
    await repositories.publishedSources.upsert(
      PublishedSource(id: 'src1', title: 'Old Book', author: 'An Editor'),
      at: _local,
    );
    // ignore: unused_result
    await repositories.customFieldDefs.upsert(
      CustomFieldDef(
        id: 'cf-tempo',
        key: 'tempo',
        label: 'Tempo',
        type: CustomFieldType.text,
      ),
      at: _local,
    );
    await repositories.userGlossary.upsert(
      UserGlossaryEntry(
        id: 'zoom-id',
        kindName: UserGlossaryEntryKind.customFigure.name,
        name: 'zoom',
        definition: 'A zoom.',
        description: 'Fast.',
        payload: _zoomPayload('{who} zoom {hand}'),
        createdAt: _local,
      ),
      at: _local,
    );
    await repositories.dances.create(dance('d-author', authorIds: ['c1']));
    await repositories.dances.create(
      dance('d-source', sourceCitations: [SourceCitation(sourceId: 'src1')]),
    );
    await repositories.dances.create(
      dance(
        'd-field',
        customFields: [CustomFieldValue(fieldId: 'cf-tempo', value: 'brisk')],
      ),
    );
    await repositories.dances.create(
      dance(
        'd-figure',
        figures: [
          userFigureUseFigure(
            id: 'zoom-id',
            args: const {'hand': 'right'},
            text: 'neighbors zoom right',
          ),
        ],
      ),
    );
    await repositories.dances.create(dance('d-plain'));
    await repositories.ensureMigrated();
  });

  tearDown(() => db.close());

  group('a batch that changes no derived input', () {
    for (final (name, blobs) in <(String, List<SyncRecordBlob> Function())>[
      ('a setting', () => [setting()]),
      (
        'a program',
        () => [
          blob(
            SyncRecordKind.program,
            Program(
              id: 'p1',
              title: 'Saturday',
              slots: [ProgramSlot(id: 's1', position: 0, text: 'Break')],
              createdAt: _peer,
              updatedAt: _peer,
            ),
          ),
        ],
      ),
      (
        'a tag, a venue, a difficulty level and a figure note',
        () => [
          blob(SyncRecordKind.tag, Tag(id: 't1', name: 'Easy')),
          blob(SyncRecordKind.venue, Venue(id: 'v1', name: 'The Hall')),
          blob(
            SyncRecordKind.difficultyLevel,
            DifficultyLevel(id: 'dl1', label: 'Fiendish', position: 9),
          ),
          blob(
            SyncRecordKind.figureNote,
            const FigureNote(figureId: 'swing', notes: 'Smooth.'),
          ),
        ],
      ),
    ]) {
      test('writes no derived row: $name', () async {
        await applyInbound(blobs());
        expect(writes.statements, isEmpty);
        await expectEquivalentToFullRebuild();
      });
    }
  });

  group('a batch that changes a derived input reindexes exactly the dances '
      'that read it', () {
    test('a choreographer rename', () async {
      await applyInbound([
        blob(
          SyncRecordKind.choreographer,
          Choreographer(id: 'c1', name: 'Mary Newname'),
        ),
      ]);
      expect(writes.ftsInsertedFor, {'d-author'});
      expect(await repositories.dances.searchText('Newname'), ['d-author']);
      expect(await repositories.dances.searchText('Oldname'), isEmpty);
      await expectEquivalentToFullRebuild();
    });

    test('a published source rename', () async {
      await applyInbound([
        blob(
          SyncRecordKind.publishedSource,
          PublishedSource(id: 'src1', title: 'New Book', author: 'An Editor'),
        ),
      ]);
      expect(writes.ftsInsertedFor, {'d-source'});
      expect(await repositories.dances.searchText('New Book'), ['d-source']);
      await expectEquivalentToFullRebuild();
    });

    test('an edit to a figure of your own (a glossaryEntry)', () async {
      // Figures of your own do sync, as glossary entries, so an apply can
      // change how their uses are indexed.
      await applyInbound([zoom('{who} whirl {hand}')]);
      expect(writes.ftsInsertedFor, {'d-figure'});
      expect(await repositories.dances.searchText('whirl'), ['d-figure']);
      expect(await repositories.dances.searchText('zoom'), isEmpty);
      await expectEquivalentToFullRebuild();
    });

    test('a custom-field definition tombstone stops its values being '
        'searchable, in the Trash too (#898)', () async {
      // Nothing live cites the definition once the dance is in the Trash,
      // so the peer's tombstone applies rather than waiting.
      await repositories.dances.softDelete('d-field', at: _trashed);
      await applyInbound([
        blob(
          SyncRecordKind.customFieldDef,
          CustomFieldDef(
            id: 'cf-tempo',
            key: 'tempo',
            label: 'Tempo',
            type: CustomFieldType.text,
          ),
          deletedAt: _peer,
        ),
      ]);
      expect(writes.ftsInsertedFor, {'d-field'});
      final row = await db
          .customSelect(
            "SELECT custom_values FROM dance_fts WHERE dance_id = 'd-field'",
          )
          .getSingle();
      expect(row.read<String>('custom_values'), isEmpty);
      await expectEquivalentToFullRebuild();
    });

    test('a dance edit, a tombstone and a restore', () async {
      await repositories.dances.softDelete('d-source', at: _trashed);
      await applyInbound([
        blob(SyncRecordKind.dance, dance('d-plain', title: 'Renamed Reel')),
        blob(
          SyncRecordKind.dance,
          dance('d-author', authorIds: ['c1']),
          deletedAt: _peer,
        ),
        blob(
          SyncRecordKind.dance,
          dance(
            'd-source',
            sourceCitations: [SourceCitation(sourceId: 'src1')],
            updatedAt: _peer,
          ),
        ),
      ]);
      expect(writes.ftsInsertedFor, {'d-plain', 'd-author', 'd-source'});
      expect(await repositories.dances.searchText('Renamed'), ['d-plain']);
      expect(await repositories.dances.searchText('Old Book'), [
        'd-source',
      ], reason: 'the restored dance is searchable again');
      // A dance in the Trash keeps its rows, filtered at query time (#439),
      // exactly as a full rebuild leaves it.
      expect(await repositories.dances.searchText('Oldname'), isEmpty);
      await expectEquivalentToFullRebuild();
    });
  });

  test('a mixed batch leaves the derived tables equal to a full rebuild of '
      'the same state', () async {
    await repositories.dances.softDelete('d-field', at: _trashed);
    await applyInbound([
      setting(),
      blob(SyncRecordKind.tag, Tag(id: 't1', name: 'Easy')),
      blob(
        SyncRecordKind.choreographer,
        Choreographer(id: 'c1', name: 'Mary Newname'),
      ),
      blob(
        SyncRecordKind.choreographer,
        Choreographer(id: 'c2', name: 'Second Caller'),
      ),
      blob(
        SyncRecordKind.publishedSource,
        PublishedSource(id: 'src1', title: 'New Book'),
      ),
      blob(
        SyncRecordKind.customFieldDef,
        CustomFieldDef(
          id: 'cf-tempo',
          key: 'tempo',
          label: 'Tempo',
          type: CustomFieldType.text,
        ),
        deletedAt: _peer,
      ),
      zoom('{who} whirl {hand}'),
      blob(
        SyncRecordKind.dance,
        dance('d-new', authorIds: ['c1', 'c2'], title: 'Fresh Jig'),
      ),
      blob(
        SyncRecordKind.dance,
        dance('d-plain', title: 'Renamed Reel'),
        deletedAt: _peer,
      ),
    ]);
    expect(writes.ftsInsertedFor, {
      'd-author',
      'd-source',
      'd-field',
      'd-figure',
      'd-new',
      'd-plain',
    });
    await expectEquivalentToFullRebuild();
  });

  test('a tombstone the snapshot releases outside a batch reindexes the '
      'dances that read it', () async {
    // The peer deletes the choreographer while a live dance credits it, so
    // the deletion waits (§6.8). Trashing the dance here releases it at the
    // next snapshot — a write no apply batch names.
    await applyInbound([
      blob(
        SyncRecordKind.choreographer,
        Choreographer(id: 'c1', name: 'Mary Oldname'),
        deletedAt: _peer,
      ),
    ]);
    await repositories.dances.softDelete('d-author', at: _trashed);
    writes.reset();
    await storage.snapshot();
    final released = await db
        .customSelect("SELECT deleted_at FROM choreographers WHERE id = 'c1'")
        .getSingle();
    expect(
      released.data['deleted_at'],
      isNotNull,
      reason: 'the snapshot applied the waiting deletion',
    );
    expect(writes.ftsInsertedFor, {'d-author'});
    await expectEquivalentToFullRebuild();
  });
}
