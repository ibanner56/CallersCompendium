import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

/// The batch edits over level, rating and tunes pass `rebuildDerived: false`
/// (see `DanceRepository._updateMany`): none of them feeds a `dance_fts` column
/// or a `dance_figures` row, so the delete-and-reinsert would only rewrite the
/// same bytes. These tests pin both halves of that claim — the rows are
/// unchanged, and no FTS delete ran — and that a custom-field batch, whose
/// values *are* an FTS column, still rebuilds.
void main() {
  late FtsDeleteByDanceCounter ftsDeletes;
  late CompendiumDatabase db;
  late DanceRepository dances;

  final now = DateTime.utc(2026, 6, 1);

  setUp(() {
    ftsDeletes = FtsDeleteByDanceCounter();
    db = openCountingTestDatabase(ftsDeletes);
    dances = DanceRepository(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  Future<List<Map<String, Object?>>> snapshot(String table) async {
    final rows = await db
        .customSelect('SELECT rowid AS _rowid, * FROM $table ORDER BY rowid')
        .get();
    return [for (final row in rows) row.data];
  }

  Future<Map<String, List<Map<String, Object?>>>> derivedRows() async => {
    for (final table in const [
      'dance_fts',
      'dance_substring_fts',
      'dance_figures',
    ])
      table: await snapshot(table),
  };

  Future<void> seed() async {
    await dances.create(
      sampleDance(id: 'a', title: 'Alpha').copyWith(tunes: ['Reel A']),
    );
    await dances.create(sampleDance(id: 'b', title: 'Bravo'));
    ftsDeletes.count = 0;
  }

  Future<void> expectDerivedRowsUntouched(Future<int> Function() op) async {
    await seed();
    final before = await derivedRows();
    expect(before['dance_fts'], isNotEmpty);
    expect(before['dance_figures'], isNotEmpty);

    final changed = await op();

    expect(changed, greaterThan(0), reason: 'the op must actually write');
    expect(await derivedRows(), before);
    expect(ftsDeletes.count, 0);
  }

  test('setLevelForMany leaves the derived rows alone', () async {
    await expectDerivedRowsUntouched(
      () => dances.setLevelForMany(
        ['a', 'b'],
        difficultyLevelId: DifficultyLevel.advancedId,
        now: now,
      ),
    );
  });

  test('setRatingForMany leaves the derived rows alone', () async {
    await expectDerivedRowsUntouched(
      () => dances.setRatingForMany(['a', 'b'], rating: 4, now: now),
    );
  });

  test('addTunesForMany leaves the derived rows alone', () async {
    await expectDerivedRowsUntouched(
      () => dances.addTunesForMany(['a', 'b'], tunes: ['Jig B'], now: now),
    );
  });

  test('clearTunesForMany leaves the derived rows alone', () async {
    await expectDerivedRowsUntouched(
      () => dances.clearTunesForMany(['a'], now: now),
    );
  });

  test('a custom-field batch still rebuilds the derived rows', () async {
    final def = CustomFieldDef(
      id: 'f-text',
      key: 'origin',
      label: 'Origin',
      type: CustomFieldType.text,
    );
    // ignore: unused_result
    await CustomFieldDefRepository(db).upsert(def);
    await seed();

    final changed = await dances.upsertCustomFieldForMany(
      ['a', 'b'],
      def: def,
      value: 'Zanzibar',
      now: now,
    );

    expect(changed, 2);
    expect(ftsDeletes.count, 2);
    final fts = await db
        .customSelect(
          "SELECT dance_id FROM dance_fts WHERE dance_fts MATCH 'Zanzibar'",
        )
        .get();
    expect(fts.map((r) => r.read<String>('dance_id')).toSet(), {'a', 'b'});

    ftsDeletes.count = 0;
    expect(
      await dances.clearCustomFieldForMany(['a'], fieldId: 'f-text', now: now),
      1,
    );
    expect(ftsDeletes.count, 1);
  });

  test('a batch over a dance with every relation keeps them all', () async {
    final choreographers = ChoreographerRepository(db);
    // ignore: unused_result
    await choreographers.upsert(Choreographer(id: 'c1', name: 'Alice'));
    // ignore: unused_result
    await choreographers.upsert(Choreographer(id: 'c2', name: 'Bob'));
    // ignore: unused_result
    await TagRepository(db).upsert(Tag(id: 't1', name: 'chestnut'));
    await PublishedSourceRepository(
      db,
    ).upsert(PublishedSource(id: 's1', title: 'Zesty Contras'));
    final def = CustomFieldDef(
      id: 'f-text',
      key: 'origin',
      label: 'Origin',
      type: CustomFieldType.text,
    );
    // ignore: unused_result
    await CustomFieldDefRepository(db).upsert(def);
    await dances.create(sampleDance(id: 'other', title: 'Other'));
    final full = sampleDance(
      id: 'full',
      title: 'Full',
      authorIds: ['c2', 'c1'],
      tagIds: ['t1'],
      links: [
        DanceLink(id: 'l1', kind: LinkKind.source, url: 'https://x.example'),
        DanceLink(
          id: 'l2',
          kind: LinkKind.relatedDance,
          targetDanceId: 'other',
          label: 'similar',
          transitive: true,
        ),
      ],
      sourceCitations: [
        SourceCitation(sourceId: 's1', page: '12', number: 'A1'),
      ],
      customFields: [CustomFieldValue(fieldId: 'f-text', value: 'Maine')],
      provenance: Provenance(
        source: ProvenanceSource.callersbox,
        externalId: 'CB-123',
        importedAt: DateTime.utc(2026, 2, 1),
        permission: 'full',
        license: 'CC-BY',
        sourceVersion: '2026-01-15',
      ),
    );
    await dances.create(full);
    final before = (await dances.getById('full'))!;

    expect(
      await dances.setLevelForMany(
        ['full'],
        difficultyLevelId: DifficultyLevel.beginnerId,
        now: now,
      ),
      1,
    );
    expect(await dances.setRatingForMany(['full'], rating: 3, now: now), 1);
    expect(
      await dances.addTunesForMany(['full'], tunes: ['Reel A'], now: now),
      1,
    );

    final after = (await dances.getById('full'))!;
    expect(after.authorIds, before.authorIds);
    expect(after.tagIds, before.tagIds);
    expect(
      after.links.map(
        (l) => (l.id, l.kind, l.url, l.targetDanceId, l.label, l.transitive),
      ),
      before.links.map(
        (l) => (l.id, l.kind, l.url, l.targetDanceId, l.label, l.transitive),
      ),
    );
    expect(
      after.sourceCitations.map((c) => (c.sourceId, c.page, c.number)),
      before.sourceCitations.map((c) => (c.sourceId, c.page, c.number)),
    );
    expect(
      after.customFields.map((f) => (f.fieldId, f.value)),
      before.customFields.map((f) => (f.fieldId, f.value)),
    );
    expect(after.provenance!.externalId, before.provenance!.externalId);
    expect(after.provenance!.license, before.provenance!.license);
    expect(after.provenance!.permission, before.provenance!.permission);
    expect(after.provenance!.sourceVersion, before.provenance!.sourceVersion);
    expect(after.difficultyLevelId, DifficultyLevel.beginnerId);
    expect(after.rating, 3);
  });

  test('a repeated, unknown or soft-deleted id is handled as before', () async {
    await seed();
    await dances.softDelete('b', at: now);

    final changed = await dances.setRatingForMany(
      ['a', 'a', 'b', 'nope'],
      rating: 2,
      now: now,
    );

    expect(changed, 1);
    expect((await dances.getById('a'))!.rating, 2);
    expect((await dances.getById('b', includeDeleted: true))!.rating, isNull);
  });
}
