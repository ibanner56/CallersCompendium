import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/storage/database.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:test/test.dart';

import 'test_database.dart';

/// Rename, merge and delete for tags, authors and sources
/// (`docs/design/tags-and-people.md`, T1).
void main() {
  // Ids sort in this order, so the smaller-UUID rule is easy to read.
  const a = '00000000-0000-4000-8000-00000000000a';
  const b = '00000000-0000-4000-8000-00000000000b';
  const c = '00000000-0000-4000-8000-00000000000c';
  final t0 = DateTime.utc(2026, 10, 1);

  late CompendiumDatabase db;
  late CompendiumRepositories repos;
  late ReferenceEditRepository edits;

  setUp(() {
    db = openTestDatabase();
    repos = CompendiumRepositories(db, contraTaxonomy);
    edits = repos.references;
  });

  tearDown(() => db.close());

  Future<void> tag(String id, String name, {int? color}) async {
    // ignore: unused_result
    await repos.tags.upsert(
      Tag(id: id, name: name, color: color),
      at: t0,
    );
  }

  Future<void> dance(
    String id, {
    List<String> tags = const [],
    List<String> authors = const [],
    List<SourceCitation> sources = const [],
  }) => repos.dances.create(
    Dance(
      id: id,
      title: 'Dance $id',
      tagIds: tags,
      authorIds: authors,
      sourceCitations: sources,
      createdAt: t0,
      updatedAt: t0,
    ),
  );

  Future<TagRow> tagRow(String id) =>
      (db.select(db.tags)..where((t) => t.id.equals(id))).getSingle();

  Future<Set<(String, String)>> tagJoins() async => {
    for (final row in await db.select(db.danceTags).get())
      (row.danceId, row.tagId),
  };

  Future<Map<String, String>> aliases() async => {
    for (final row in await repos.syncLocal.listAliases())
      row.losingId: row.survivingId,
  };

  Future<String> ftsColumn(String danceId, String column) async {
    final row = await db
        .customSelect(
          'SELECT $column AS v FROM dance_fts WHERE dance_id = ?',
          variables: [Variable<String>(danceId)],
        )
        .getSingle();
    return row.read<String>('v');
  }

  group('rename', () {
    test('writes the new name', () async {
      await tag(a, 'Flowing');
      await edits.rename(ReferenceKind.tag, a, 'Flowy');
      expect((await tagRow(a)).name, 'Flowy');
    });

    test(
      'a case-only rename is a plain rename when nothing else matches',
      () async {
        await tag(a, 'flowy');
        await edits.rename(ReferenceKind.tag, a, 'Flowy');
        expect((await tagRow(a)).name, 'Flowy');
      },
    );

    test('refuses, writing nothing, when live entries hold the name, and '
        'names every one of them', () async {
      await tag(a, 'Flowing');
      // Both hold "flowy" as the app matches names; `idByName` would return
      // only one of them.
      await tag(b, 'flowy');
      await tag(c, 'FLOWY');
      final error = await edits
          .rename(ReferenceKind.tag, a, 'Flowy')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<ReferenceNameTakenException>());
      expect((error! as ReferenceNameTakenException).liveIds, [b, c]);
      expect((await tagRow(a)).name, 'Flowing');
    });

    test('onto a name a tombstone holds frees the tombstone and does not '
        'revive it', () async {
      await tag(a, 'Flowing');
      await tag(b, 'Flowy');
      await repos.tags.delete(b, at: t0);
      final before = await tagRow(b);

      await edits.rename(ReferenceKind.tag, a, 'Flowy');

      expect((await tagRow(a)).name, 'Flowy');
      final freed = await tagRow(b);
      expect(freed.deletedAt, isNotNull, reason: 'the tombstone stays dead');
      expect(freed.existenceAt, before.existenceAt);
      expect(freed.name, 'Flowy_00000000');
    });

    test('Undo writes the old name back', () async {
      await tag(a, 'Flowing');
      final undo = await edits.rename(ReferenceKind.tag, a, 'Flowy');
      await edits.undo(undo);
      expect((await tagRow(a)).name, 'Flowing');
    });

    test(
      'of a source refreshes the search text of the dances citing it',
      () async {
        await repos.publishedSources.upsert(
          PublishedSource(id: a, title: 'Zesty Contras'),
          at: t0,
        );
        await dance('d1', sources: [SourceCitation(sourceId: a)]);
        await edits.rename(ReferenceKind.source, a, 'Zesty Contras II');
        expect(await ftsColumn('d1', 'sources'), 'Zesty Contras II');
      },
    );
  });

  test('editing a source in place refreshes the search text of the dances '
      'citing it', () async {
    await repos.publishedSources.upsert(
      PublishedSource(id: a, title: 'Zesty Contras', author: 'Ann'),
      at: t0,
    );
    await repos.publishedSources.upsert(
      PublishedSource(id: b, title: 'Other'),
      at: t0,
    );
    await dance(
      'd1',
      sources: [
        SourceCitation(sourceId: b),
        SourceCitation(sourceId: a),
      ],
    );
    await repos.publishedSources.upsert(
      PublishedSource(id: a, title: 'Zesty Contras', author: 'Bea'),
      localUserEdit: true,
    );
    // What a full rebuild indexes: each title, then its author.
    expect(await ftsColumn('d1', 'sources'), 'Other Zesty Contras Bea');
  });

  group('merge', () {
    test('keeps the smaller id whichever entry the user merged into, with '
        "that entry's name and colour", () async {
      await tag(a, 'Flowing', color: 0xFF00FF00);
      await tag(b, 'Flowy', color: 0xFFFF0000);
      // "Merge 'Flowing' into 'Flowy'".
      await edits.merge(ReferenceKind.tag, intoId: b, otherIds: [a]);

      final survivor = await tagRow(a);
      expect(survivor.deletedAt, isNull);
      expect(survivor.name, 'Flowy');
      expect(survivor.color, 0xFFFF0000);
      final loser = await tagRow(b);
      expect(loser.deletedAt, isNotNull);
      expect(loser.name, 'Flowy_00000000');
      expect(await aliases(), {b: a});
    });

    test(
      'takes a colour from a loser when the chosen entry has none',
      () async {
        await tag(a, 'Flowing', color: 0xFF00FF00);
        await tag(b, 'Flowy');
        await edits.merge(ReferenceKind.tag, intoId: b, otherIds: [a]);
        expect((await tagRow(a)).color, 0xFF00FF00);
      },
    );

    test('moves joins from live and trashed dances, keeping one where a dance '
        'had both, and bumps each dance', () async {
      await tag(a, 'Flowing');
      await tag(b, 'Flowy');
      await dance('both', tags: [a, b]);
      await dance('loser', tags: [b]);
      await dance('trashed', tags: [b]);
      await repos.dances.softDelete('trashed', at: t0);
      final before = {
        for (final row in await db.select(db.dances).get()) row.id: row,
      };

      await edits.merge(ReferenceKind.tag, intoId: a, otherIds: [b]);

      expect(await tagJoins(), {('both', a), ('loser', a), ('trashed', a)});
      for (final row in await db.select(db.dances).get()) {
        expect(
          row.updatedAt.isAfter(before[row.id]!.updatedAt),
          isTrue,
          reason: '${row.id} was not bumped',
        );
      }
    });

    test('a rename that found two live matches and a tombstone leaves one '
        'entry, with the colour of the match chosen', () async {
      await tag(a, 'flowy', color: 0xFF0000FF);
      await tag(b, 'Flowing');
      await tag(c, 'Flowy', color: 0xFFFF0000);
      const d = '00000000-0000-4000-8000-00000000000d';
      await tag(d, 'FLOWY');
      await repos.tags.delete(d, at: t0);

      await edits.merge(
        ReferenceKind.tag,
        intoId: c,
        otherIds: [a, b],
        name: 'Flowy',
      );

      final live = await repos.tags.listAll();
      expect(live, [Tag(id: a, name: 'Flowy', color: 0xFFFF0000)]);
      expect((await tagRow(d)).deletedAt, isNotNull);
      expect(await aliases(), {b: a, c: a});
    });

    test("fills an author's empty details from the loser, and keeps "
        'deceased if either is', () async {
      final _ = await repos.choreographers.upsert(
        Choreographer(id: a, name: 'Gene Hubert', website: 'gene.example'),
        at: t0,
      );
      final _ = await repos.choreographers.upsert(
        Choreographer(
          id: b,
          name: 'Gene Hurbert',
          website: 'other.example',
          email: 'gene@example.com',
          deceased: true,
        ),
        at: t0,
      );
      await dance('d1', authors: [b]);

      await edits.merge(ReferenceKind.author, intoId: a, otherIds: [b]);

      final survivor = await repos.choreographers.getById(a);
      expect(survivor!.name, 'Gene Hubert');
      expect(survivor.website, 'gene.example', reason: "the survivor's wins");
      expect(survivor.email, 'gene@example.com');
      expect(survivor.deceased, isTrue);
      expect(await ftsColumn('d1', 'authors'), 'Gene Hubert');
    });
  });

  group('Undo of a merge', () {
    test('restores both entries, their joins and positions, and bumps the '
        'dances again', () async {
      final _ = await repos.choreographers.upsert(
        Choreographer(id: a, name: 'Ann'),
        at: t0,
      );
      final _ = await repos.choreographers.upsert(
        Choreographer(id: b, name: 'Anne'),
        at: t0,
      );
      final _ = await repos.choreographers.upsert(
        Choreographer(id: c, name: 'Cy'),
        at: t0,
      );
      await dance('both', authors: [c, b, a]);
      await dance('one', authors: [c, b]);
      final authorsBefore = await db.select(db.danceAuthors).get();

      final undo = await edits.merge(
        ReferenceKind.author,
        intoId: b,
        otherIds: [a],
      );
      final merged = {
        for (final row in await db.select(db.dances).get())
          row.id: row.updatedAt,
      };
      await edits.undo(undo);

      expect((await repos.choreographers.getById(a))!.name, 'Ann');
      expect((await repos.choreographers.getById(b))!.name, 'Anne');
      expect(
        (await db.select(db.danceAuthors).get()).toSet(),
        authorsBefore.toSet(),
      );
      expect(await aliases(), isEmpty);
      for (final row in await db.select(db.dances).get()) {
        expect(row.updatedAt.isAfter(merged[row.id]!), isTrue);
      }
      expect(await ftsColumn('one', 'authors'), 'Cy Anne');
    });

    test("restores the alias chain the loser's merge collapsed", () async {
      await tag(a, 'Flowing');
      await tag(b, 'Flowy');
      // An earlier reconciliation merged `c` into `b`.
      await repos.syncLocal.upsertAlias(
        kind: SyncRecordKind.tag,
        losingId: c,
        survivingId: b,
      );
      final undo = await edits.merge(
        ReferenceKind.tag,
        intoId: b,
        otherIds: [a],
      );
      expect(await aliases(), {b: a, c: a});

      await edits.undo(undo);

      expect(await aliases(), {c: b});
    });

    test("restores the loser's retained sync fields and keeps the survivor's "
        'publication marker', () async {
      await tag(a, 'Flowing');
      await tag(b, 'Flowy');
      await repos.syncLocal.markPublished(
        kind: SyncRecordKind.tag,
        recordId: b,
      );
      await db
          .into(db.retainedSyncFields)
          .insert(
            RetainedSyncFieldsCompanion.insert(
              kind: SyncRecordKind.tag,
              recordId: b,
              payload: '{"future":1}',
            ),
          );
      final undo = await edits.merge(
        ReferenceKind.tag,
        intoId: b,
        otherIds: [a],
      );
      await edits.undo(undo);

      final retained = await db.select(db.retainedSyncFields).get();
      expect([for (final row in retained) row.recordId], [b]);
      expect(
        await repos.syncLocal.isPublished(
          kind: SyncRecordKind.tag,
          recordId: a,
        ),
        isTrue,
      );
    });
  });

  group('deleteTag', () {
    test('takes the tag off live and trashed dances, counting live ones, '
        'and a tag re-created under the name does not get them back', () async {
      await tag(a, 'Bouncey');
      await dance('live', tags: [a]);
      await dance('trashed', tags: [a]);
      await repos.dances.softDelete('trashed', at: t0);

      final undo = await edits.deleteTag(a);

      expect(undo.liveDanceCount, 1);
      expect(await tagJoins(), isEmpty);
      expect((await tagRow(a)).deletedAt, isNotNull);

      final id = await repos.tags.upsertStaged(
        Tag(id: b, name: 'Bouncey'),
        localUserEdit: true,
      );
      expect((await tagRow(id)).deletedAt, isNull);
      await repos.dances.restore('trashed', at: DateTime.now().toUtc());
      expect(await tagJoins(), isEmpty);
    });

    test('Undo puts the tag and its joins back', () async {
      await tag(a, 'Bouncey');
      await dance('live', tags: [a]);
      await dance('trashed', tags: [a]);
      await repos.dances.softDelete('trashed', at: t0);

      await edits.undo(await edits.deleteTag(a));

      expect((await tagRow(a)).deletedAt, isNull);
      expect(await tagJoins(), {('live', a), ('trashed', a)});
    });
  });
}
