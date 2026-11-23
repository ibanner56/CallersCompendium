import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

/// A merge of tags, authors or sources rewrites the saved searches that name a
/// loser, atomically and undoably, and a saved search a merge could not
/// rewrite is still read as the survivor while the alias exists (#2325).
void main() {
  // Ids sort in this order, so the smaller-UUID rule is easy to read.
  const a = '00000000-0000-4000-8000-00000000000a';
  const b = '00000000-0000-4000-8000-00000000000b';
  const c = '00000000-0000-4000-8000-00000000000c';
  final t0 = DateTime.utc(2026, 10, 1);
  final today = DateTime.utc(2026, 11, 23);

  late CompendiumDatabase db;
  late CompendiumRepositories repos;

  setUp(() {
    db = openTestDatabase();
    repos = CompendiumRepositories(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  Future<void> tag(String id, String name) async {
    // ignore: unused_result
    await repos.tags.upsert(
      Tag(id: id, name: name),
      at: t0,
    );
  }

  Future<void> author(String id, String name) async {
    final _ = await repos.choreographers.upsert(
      Choreographer(id: id, name: name),
      at: t0,
    );
  }

  Future<void> source(String id, String title) async {
    final _ = await repos.publishedSources.upsert(
      PublishedSource(id: id, title: title),
      at: t0,
    );
  }

  SavedSearchSpec spec(CollectionPanelState state) =>
      SavedSearchSpec.fromPanelState(state, today: today).value!;

  Future<String> save(
    String id,
    String name,
    CollectionPanelState state,
  ) async {
    await repos.savedSearches.save(
      SavedSearch(id: id, name: name, spec: spec(state)),
      at: t0,
    );
    return id;
  }

  Future<Object?> stored(String id) => repos.settings.get('saved_search:$id');

  /// The tag ids a stored search names in its Tags facet and Advanced rows.
  Future<(List<String>, List<String>)> tagsOf(String id) async {
    final json = (await stored(id)) as Map;
    final facets = json['facets'] as Map?;
    final tags = [...?(facets?['tagIds'] as List?)?.cast<String>()];
    final rows = <String>[];
    void walk(Object? node) {
      if (node is Map) {
        if (node['t'] == 'tag' && node['tagId'] is String) {
          rows.add(node['tagId'] as String);
        }
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    walk(json['advanced']);
    return (tags, rows);
  }

  Future<void> expectTags(
    String id,
    List<String> facet,
    List<String> rows,
  ) async {
    final (inFacet, inRows) = await tagsOf(id);
    expect(inFacet, facet);
    expect(inRows, rows);
  }

  CollectionPanelState withTags(
    List<String> ids, {
    List<String> rows = const [],
  }) {
    final state = CollectionPanelState();
    state.facets.tagIds.addAll(ids);
    state.advanced.children.addAll([
      for (final id in rows) BuilderTag(tagId: id),
    ]);
    return state;
  }

  group('merge rewrites saved searches', () {
    test('a tag the Filters and Advanced rows name moves to the survivor, '
        'and one that names none is not written', () async {
      await tag(a, 'Flowing');
      await tag(b, 'Flowy');
      await save('uses-loser', 'Flow', withTags([b], rows: [b]));
      await save('other', 'Other', withTags([c]));
      final otherBefore = await stored('other');

      await repos.references.merge(
        ReferenceKind.tag,
        intoId: a,
        otherIds: [b],
        at: t0.add(const Duration(days: 1)),
      );

      await expectTags('uses-loser', [a], [a]);
      expect(await stored('other'), otherBefore);
      expect(
        await repos.savedSearches.get('uses-loser'),
        isNotNull,
        reason: 'still readable',
      );
      expect(
        (await repos.savedSearches.get('uses-loser'))!.name,
        'Flow',
        reason: 'the name is carried over',
      );
    });

    test('the id written is the survivor — the smallest id — not the entry '
        'the user merged into', () async {
      await tag(a, 'Flowing');
      await tag(b, 'Flowy');
      await save('s', 'S', withTags([b]));

      // "Merge Flowing into Flowy": the survivor is still the smaller id, a.
      await repos.references.merge(ReferenceKind.tag, intoId: b, otherIds: [a]);

      expect((await tagsOf('s')).$1, [a]);
    });

    test(
      'several losers collapse to one sorted id, with no duplicate',
      () async {
        await tag(a, 'One');
        await tag(b, 'Two');
        await tag(c, 'Three');
        await save('s', 'S', withTags([a, b, c]));

        await repos.references.merge(
          ReferenceKind.tag,
          intoId: a,
          otherIds: [b, c],
        );

        expect((await tagsOf('s')).$1, [a]);
      },
    );

    test('authors and sources are rewritten in their own lists, and a tag '
        'merge leaves them alone', () async {
      await author(a, 'Ann');
      await author(b, 'Anne');
      await source(a, 'Book');
      await source(b, 'Book 2');
      await tag(a, 'T1');
      await tag(b, 'T2');
      final state = CollectionPanelState();
      state.facets
        ..authorIds.add(b)
        ..sourceIds.add(b)
        ..tagIds.add(b);
      await save('s', 'S', state);

      Future<Map<String, Object?>> facets() async =>
          (((await stored('s')) as Map)['facets'] as Map)
              .cast<String, Object?>();

      await repos.references.merge(ReferenceKind.tag, intoId: a, otherIds: [b]);
      var f = await facets();
      expect(f['tagIds'], [a]);
      expect(f['authorIds'], [b], reason: 'same id string, another kind');
      expect(f['sourceIds'], [b]);

      await repos.references.merge(
        ReferenceKind.author,
        intoId: a,
        otherIds: [b],
      );
      f = await facets();
      expect(f['authorIds'], [a]);
      expect(f['sourceIds'], [b]);

      await repos.references.merge(
        ReferenceKind.source,
        intoId: a,
        otherIds: [b],
      );
      expect((await facets())['sourceIds'], [a]);
    });

    test('a saved search this build cannot read is left byte for byte, and '
        'the merge still succeeds', () async {
      await tag(a, 'Flowing');
      await tag(b, 'Flowy');
      final newer = {
        'v': 99,
        'name': 'From the future',
        'facets': {
          'tagIds': [b],
        },
      };
      await repos.settings.set('saved_search:future', newer, at: t0);
      await save('ok', 'Readable', withTags([b]));

      await repos.references.merge(ReferenceKind.tag, intoId: a, otherIds: [b]);

      expect(await stored('future'), newer);
      expect((await tagsOf('ok')).$1, [a]);
    });

    test('a merge that is refused writes no saved search', () async {
      await tag(a, 'Flowing');
      await tag(b, 'Flowy');
      await tag(c, 'Merged name');
      await save('s', 'S', withTags([b]));
      final before = await stored('s');

      // "Merged name" is held by a live tag outside the merge.
      await expectLater(
        repos.references.merge(
          ReferenceKind.tag,
          intoId: a,
          otherIds: [b],
          name: 'Merged name',
        ),
        throwsA(isA<ReferenceNameTakenException>()),
      );

      expect(await stored('s'), before);
    });

    test('deleting a tag rewrites nothing; the search names a tag that is '
        'gone and is reported as such', () async {
      await tag(a, 'Flowing');
      await save('s', 'S', withTags([a]));
      final before = await stored('s');

      await repos.references.deleteTag(a);

      expect(await stored('s'), before);
      final read = (await repos.savedSearches.get('s'))!;
      final result = resolveSavedSearch(
        read.spec,
        SavedSearchContext(
          today: today,
          taxonomy: contraTaxonomy,
          aliases: await repos.syncLocal.aliasMaps(),
        ),
      );
      expect((result as UnresolvableSavedSearch).missing, [
        const MissingReference(MissingReferenceKind.tag, a),
      ]);
    });
  });

  group('Undo of a merge', () {
    test('puts each saved search back to naming the losers', () async {
      await tag(a, 'Flowing');
      await tag(b, 'Flowy');
      await save('s', 'S', withTags([b], rows: [b]));
      final before = await stored('s');

      final undo = await repos.references.merge(
        ReferenceKind.tag,
        intoId: a,
        otherIds: [b],
      );
      await expectTags('s', [a], [a]);
      await repos.references.undo(undo);

      expect(await stored('s'), before);
    });

    test('does not overwrite a saved search edited since the merge', () async {
      await tag(a, 'Flowing');
      await tag(b, 'Flowy');
      await save('s', 'S', withTags([b]));
      final undo = await repos.references.merge(
        ReferenceKind.tag,
        intoId: a,
        otherIds: [b],
      );
      // The user then renames it.
      final merged = (await repos.savedSearches.get('s'))!;
      await repos.savedSearches.save(
        SavedSearch(id: 's', name: 'Renamed', spec: merged.spec),
      );
      final edited = await stored('s');

      await repos.references.undo(undo);

      expect(await stored('s'), edited);
      expect((await tagsOf('s')).$1, [a]);
    });

    test(
      'does not bring back a saved search deleted since the merge',
      () async {
        await tag(a, 'Flowing');
        await tag(b, 'Flowy');
        await save('s', 'S', withTags([b]));
        final undo = await repos.references.merge(
          ReferenceKind.tag,
          intoId: a,
          otherIds: [b],
        );
        await repos.savedSearches.delete('s');

        await repos.references.undo(undo);

        expect(await repos.savedSearches.get('s'), isNull);
        expect(await stored('s'), isNull);
      },
    );
  });

  group('alias-aware evaluation', () {
    Future<ResolvedSavedSearch> resolve(
      String id,
      Set<String> liveTags,
    ) async => resolveSavedSearch(
      (await repos.savedSearches.get(id))!.spec,
      SavedSearchContext(
        today: today,
        taxonomy: contraTaxonomy,
        tagIds: liveTags,
        aliases: await repos.syncLocal.aliasMaps(),
      ),
    );

    test('aliasMaps groups the alias rows by kind from one read', () async {
      await tag(a, 'Flowing');
      await tag(b, 'Flowy');
      await repos.references.merge(ReferenceKind.tag, intoId: a, otherIds: [b]);

      expect(await repos.syncLocal.aliasMaps(), {
        SyncRecordKind.tag: {b: a},
      });
    });

    test('a value from a peer that still names the loser is read as the '
        'survivor while the alias exists, and is reported once it is '
        'retired', () async {
      await tag(a, 'Flowing');
      await tag(b, 'Flowy');
      await repos.references.merge(ReferenceKind.tag, intoId: a, otherIds: [b]);
      // A peer that had not yet seen the merge syncs a search naming b.
      await save('late', 'Late', withTags([b]));

      expect(await resolve('late', {a}), isA<ResolvedFilter>());

      // No peer manifest lists b any more: the alias is retired (§6.6).
      await repos.syncLocal.retireAliases(peerAddresses: {});
      expect(await repos.syncLocal.aliasMaps(), isEmpty);
      final after = await resolve('late', {a});
      expect(after, isA<UnresolvableSavedSearch>());
      expect((after as UnresolvableSavedSearch).missing, [
        const MissingReference(MissingReferenceKind.tag, b),
      ]);
    });
  });
}
