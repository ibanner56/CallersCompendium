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

  group('watchLiveDanceCounts', () {
    test('counts live dances per entry, and follows a dance into the trash '
        'and back', () async {
      await tag(a, 'Flowy');
      await tag(b, 'Bouncey');
      await tag(c, 'Unused');
      await dance('one', tags: [a, b]);
      await dance('two', tags: [a]);
      await dance('trashed', tags: [a]);
      await repos.dances.softDelete('trashed', at: t0);

      final seen = <Map<String, int>>[];
      final sub = edits
          .watchLiveDanceCounts(ReferenceKind.tag)
          .listen(seen.add);
      await pumpEventQueue();
      // Unused entries are absent, not zero; the trashed dance is not counted.
      expect(seen.last, {a: 2, b: 1});
      expect(await edits.liveDanceCount(ReferenceKind.tag, a), 2);

      await repos.dances.softDelete('two', at: t0);
      await pumpEventQueue();
      expect(seen.last, {a: 1, b: 1});

      await repos.dances.restore('trashed', at: DateTime.now().toUtc());
      await pumpEventQueue();
      expect(seen.last, {a: 2, b: 1});
      await sub.cancel();
    });

    test('counts authors and sources through their own join tables', () async {
      // ignore: unused_result
      await repos.choreographers.upsert(Choreographer(id: a, name: 'Gene'));
      await repos.publishedSources.upsert(
        PublishedSource(id: b, title: 'Zesty Contras'),
      );
      await dance(
        'one',
        authors: [a],
        sources: [SourceCitation(sourceId: b)],
      );

      expect(await edits.watchLiveDanceCounts(ReferenceKind.author).first, {
        a: 1,
      });
      expect(await edits.watchLiveDanceCounts(ReferenceKind.source).first, {
        b: 1,
      });
    });
  });

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

  group('review guards', () {
    test('Undo after the dance was reordered keeps every author', () async {
      for (final (id, name) in [(a, 'Ann'), (b, 'Anne'), (c, 'Cy')]) {
        final _ = await repos.choreographers.upsert(
          Choreographer(id: id, name: name),
          at: t0,
        );
      }
      await dance('d', authors: [b, c]);
      final undo = await edits.merge(
        ReferenceKind.author,
        intoId: b,
        otherIds: [a],
      );
      // The user moves the merged author after Cy before pressing Undo.
      final merged = (await repos.dances.getById('d'))!;
      expect(merged.authorIds, [a, c]);
      await repos.dances.update(
        merged.copyWith(authorIds: [c, a], updatedAt: DateTime.now().toUtc()),
        localUserEdit: true,
      );

      await edits.undo(undo);

      expect((await repos.dances.getById('d'))!.authorIds, [c, b]);
    });

    test('Undo is refused, writing nothing, when a live entry has taken the '
        'old name since', () async {
      await tag(a, 'Foo');
      final undo = await edits.rename(ReferenceKind.tag, a, 'Bar');
      await tag(b, 'Foo');

      await expectLater(
        edits.undo(undo),
        throwsA(isA<ReferenceUndoConflictException>()),
      );
      expect((await tagRow(a)).name, 'Bar');
    });

    test('a merge and its Undo in the same second never reuse a stamp for a '
        'different body', () async {
      await tag(a, 'Flowing');
      await tag(b, 'Flowy');
      final at = DateTime.utc(2026, 10, 2);
      final undo = await edits.merge(
        ReferenceKind.tag,
        intoId: b,
        otherIds: [a],
        at: at,
      );
      final tombstone = await tagRow(b);
      await edits.undo(undo, at: at);

      final revived = await tagRow(b);
      expect(revived.deletedAt, isNull);
      expect(revived.updatedAt!.isAfter(tombstone.updatedAt!), isTrue);
    });

    test('a merge is refused, writing nothing, when a live entry outside it '
        'holds the name', () async {
      await tag(a, 'x');
      await tag(b, 'y');
      await tag(c, 'Flowy');

      await expectLater(
        edits.merge(ReferenceKind.tag, intoId: a, otherIds: [b], name: 'flowy'),
        throwsA(
          isA<ReferenceNameTakenException>().having(
            (e) => e.liveIds,
            'liveIds',
            [c],
          ),
        ),
      );
      expect(await aliases(), isEmpty);
      expect((await tagRow(b)).deletedAt, isNull);
    });
  });

  group('a case variant that was there before the edit', () {
    test('does not block its Undo', () async {
      await tag(a, 'Foo');
      await tag(c, 'foo');
      final undo = await edits.rename(ReferenceKind.tag, a, 'Qux');

      await edits.undo(undo);

      expect((await tagRow(a)).name, 'Foo');
      expect((await tagRow(c)).name, 'foo');
    });

    test(
      'does not refuse a merge that keeps a name it already matched',
      () async {
        await tag(a, 'Foo');
        await tag(b, 'Bar');
        await tag(c, 'foo');

        await edits.merge(ReferenceKind.tag, intoId: a, otherIds: [b]);

        expect(await repos.tags.listAll(), [
          Tag(id: a, name: 'Foo'),
          Tag(id: c, name: 'foo'),
        ]);
      },
    );
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

  group('source merge (T3)', () {
    Future<void> source(String id, String title, {String? author}) =>
        repos.publishedSources.upsert(
          PublishedSource(id: id, title: title, author: author),
          at: t0,
        );

    Future<Map<String, (String?, String?)>> citations(String danceId) async => {
      for (final row in await (db.select(
        db.danceSources,
      )..where((t) => t.danceId.equals(danceId))).get())
        row.sourceId: (row.page, row.number),
    };

    test("a dance citing both keeps one citation, with the loser's page "
        'filling an empty page and its own number kept', () async {
      await source(a, 'Zesty Contras');
      await source(b, 'Zesty Contras (2nd ed.)');
      await dance(
        'both',
        sources: [
          SourceCitation(sourceId: a, number: '12'),
          SourceCitation(sourceId: b, page: '34', number: '99'),
        ],
      );

      await edits.merge(ReferenceKind.source, intoId: a, otherIds: [b]);

      expect(await citations('both'), {a: ('34', '12')});
    });

    test(
      'Undo puts the loser citation back and empties the filled page',
      () async {
        await source(a, 'Zesty Contras');
        await source(b, 'Zesty Contras (2nd ed.)');
        await dance(
          'both',
          sources: [
            SourceCitation(sourceId: a, number: '12'),
            SourceCitation(sourceId: b, page: '34'),
          ],
        );

        await edits.undo(
          await edits.merge(ReferenceKind.source, intoId: b, otherIds: [a]),
        );

        expect(await citations('both'), {a: (null, '12'), b: ('34', null)});
      },
    );

    test("Undo leaves a page edited since the merge as it is", () async {
      await source(a, 'Zesty Contras');
      await source(b, 'Zesty Contras (2nd ed.)');
      await dance(
        'both',
        sources: [
          SourceCitation(sourceId: a),
          SourceCitation(sourceId: b, page: '34'),
        ],
      );
      final undo = await edits.merge(
        ReferenceKind.source,
        intoId: a,
        otherIds: [b],
      );
      await (db.update(db.danceSources)
            ..where((t) => t.danceId.equals('both') & t.sourceId.equals(a)))
          .write(const DanceSourcesCompanion(page: Value('35')));

      await edits.undo(undo);

      expect((await citations('both'))[a], ('35', null));
    });
    test('Undo of a merge of two losers that each filled a locator empties '
        'both', () async {
      await source(a, 'Zesty Contras');
      await source(b, 'Zesty Contras (2nd ed.)');
      await source(c, 'Zesty');
      await dance(
        'all',
        sources: [
          SourceCitation(sourceId: a),
          SourceCitation(sourceId: b, page: '34'),
          SourceCitation(sourceId: c, number: '7'),
        ],
      );
      final undo = await edits.merge(
        ReferenceKind.source,
        intoId: a,
        otherIds: [b, c],
      );
      expect(await citations('all'), {a: ('34', '7')});

      await edits.undo(undo);

      expect(await citations('all'), {
        a: (null, null),
        b: ('34', null),
        c: (null, '7'),
      });
    });
  });

  group('deleteUnused (T3)', () {
    Future<void> author(String id, String name) async {
      final _ = await repos.choreographers.upsert(
        Choreographer(id: id, name: name),
        at: t0,
      );
    }

    test(
      'refuses, writing nothing, while a live dance credits the author',
      () async {
        await author(a, 'Gene Hubert');
        await dance('live', authors: [a]);

        await expectLater(
          edits.deleteUnused(ReferenceKind.author, a),
          throwsStateError,
        );
        expect(await repos.choreographers.getById(a), isNotNull);
      },
    );

    test('deletes an author only trashed dances credit, bumping them, and '
        'Undo revives it', () async {
      await author(a, 'Gene Hubert');
      await dance('trashed', authors: [a]);
      await repos.dances.softDelete('trashed', at: t0);
      final before = await (db.select(
        db.dances,
      )..where((t) => t.id.equals('trashed'))).getSingle();

      final undo = await edits.deleteUnused(ReferenceKind.author, a);

      expect(await repos.choreographers.getById(a), isNull);
      final after = await (db.select(
        db.dances,
      )..where((t) => t.id.equals('trashed'))).getSingle();
      expect(after.updatedAt.isAfter(before.updatedAt), isTrue);

      await edits.undo(undo);
      expect((await repos.choreographers.getById(a))!.name, 'Gene Hubert');
    });

    test('is not for tags', () {
      expect(
        () => edits.deleteUnused(ReferenceKind.tag, a),
        throwsArgumentError,
      );
    });
  });

  group('authorMergeConflicts (T3)', () {
    test('an empty email takes the other\'s and is not listed; a conflicting '
        'one is listed, and the merge drops exactly what is listed', () async {
      final into = Choreographer(
        id: b,
        name: 'Gene Hubert',
        website: 'gene.example',
      );
      final other = Choreographer(
        id: a,
        name: 'Gene Hurbert',
        website: 'other.example',
        email: 'gene@example.com',
        location: 'Portland, OR',
      );

      expect(authorMergeConflicts(into, [other]), [
        ReferenceMergeConflict(
          ReferenceDetailField.website,
          'gene.example',
          'other.example',
        ),
      ]);

      final _ = await repos.choreographers.upsert(into, at: t0);
      final _ = await repos.choreographers.upsert(other, at: t0);
      await edits.merge(ReferenceKind.author, intoId: b, otherIds: [a]);
      final merged = (await repos.choreographers.getById(a))!;
      expect(merged.website, 'gene.example');
      expect(merged.email, 'gene@example.com');
      expect(merged.location, 'Portland, OR');
    });

    test('lists a value each loser drops, once, in id order', () {
      final into = Choreographer(id: c, name: 'X', notes: 'kept');
      expect(
        authorMergeConflicts(into, [
          Choreographer(id: b, name: 'Y', notes: 'second'),
          Choreographer(id: a, name: 'Z', notes: 'first', email: 'z@x.org'),
          Choreographer(
            id: '00000000-0000-4000-8000-00000000000d',
            name: 'W',
            notes: 'first',
          ),
        ]),
        [
          ReferenceMergeConflict(ReferenceDetailField.notes, 'kept', 'first'),
          ReferenceMergeConflict(ReferenceDetailField.notes, 'kept', 'second'),
        ],
      );
    });

    test('sources compare author, year, URL and notes', () {
      expect(
        sourceMergeConflicts(
          PublishedSource(id: a, title: 'Zesty', year: 1998),
          [PublishedSource(id: b, title: 'Zesty 2', year: 2004, url: 'u')],
        ),
        [ReferenceMergeConflict(ReferenceDetailField.year, '1998', '2004')],
      );
    });
  });
}
