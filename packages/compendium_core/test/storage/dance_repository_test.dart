import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;
  late ChoreographerRepository choreographers;
  late TagRepository tags;
  late CustomFieldDefRepository customFieldDefs;

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
    choreographers = ChoreographerRepository(db);
    tags = TagRepository(db);
    customFieldDefs = CustomFieldDefRepository(db);
  });

  tearDown(() => db.close());

  group('create / getById', () {
    test('round-trips a minimal dance', () async {
      final dance = sampleDance();
      await dances.create(dance);
      final loaded = await dances.getById(dance.id);
      expect(loaded, dance);
    });

    test(
      'losslessly round-trips a figure whose move is unknown (#358)',
      () async {
        // A dance authored in a newer version / carrying a since-removed move.
        // Its move + params must survive save + reload byte-for-byte, never
        // coerced or discarded on load or save.
        final unknown = Figure(
          move: 'a_move_from_the_future',
          params: const {'beats': 12, 'flavor': 'spicy', 'who': 'partners'},
        );
        final dance = sampleDance(
          figures: [
            Figure(move: 'swing', params: const {'beats': 8}),
            unknown,
          ],
        );
        await dances.create(dance);

        final loaded = await dances.getById(dance.id);
        expect(loaded, dance, reason: 'whole dance round-trips by value');
        final reloadedUnknown = loaded!.figures[1];
        expect(reloadedUnknown.move, 'a_move_from_the_future');
        expect(reloadedUnknown.params, {
          'beats': 12,
          'flavor': 'spicy',
          'who': 'partners',
        });

        // Re-saving the reloaded dance preserves it again (no drift on update).
        await dances.update(
          loaded.copyWith(updatedAt: DateTime.utc(2026, 3, 1)),
        );
        final resaved = await dances.getById(dance.id);
        expect(resaved!.figures[1].move, 'a_move_from_the_future');
        expect(resaved.figures[1].params, {
          'beats': 12,
          'flavor': 'spicy',
          'who': 'partners',
        });
      },
    );

    test('round-trips a rating and its cleared (NULL) state', () async {
      final rated = sampleDance().copyWith(rating: 5);
      await dances.create(rated);
      expect((await dances.getById(rated.id))!.rating, 5);

      // Clearing the rating persists as NULL.
      await dances.update(
        rated.copyWith(clearRating: true, updatedAt: DateTime.utc(2026, 2, 1)),
      );
      expect((await dances.getById(rated.id))!.rating, isNull);
    });

    test('round-trips authors in position order', () async {
      await choreographers.upsert(Choreographer(id: 'c1', name: 'Alice'));
      await choreographers.upsert(Choreographer(id: 'c2', name: 'Bob'));
      final dance = sampleDance(authorIds: ['c2', 'c1']);
      await dances.create(dance);
      final loaded = await dances.getById(dance.id);
      expect(loaded!.authorIds, ['c2', 'c1']);
    });

    test('round-trips tags', () async {
      await tags.upsert(Tag(id: 't1', name: 'chestnut'));
      final dance = sampleDance(tagIds: ['t1']);
      await dances.create(dance);
      final loaded = await dances.getById(dance.id);
      expect(loaded!.tagIds, ['t1']);
    });

    test('round-trips links (source, video, related dance)', () async {
      final other = sampleDance(id: 'dance-2', title: 'Related Dance');
      await dances.create(other);
      final dance = sampleDance(
        links: [
          DanceLink(id: 'l1', kind: LinkKind.source, url: 'https://x.example'),
          DanceLink(
            id: 'l2',
            kind: LinkKind.relatedDance,
            targetDanceId: 'dance-2',
            label: 'similar figure',
          ),
        ],
      );
      await dances.create(dance);
      final loaded = await dances.getById(dance.id);
      expect(loaded!.links, hasLength(2));
      expect(loaded.links.first.url, 'https://x.example');
      expect(loaded.links.last.targetDanceId, 'dance-2');
    });

    test('round-trips source citations in position order', () async {
      await PublishedSourceRepository(
        db,
      ).upsert(PublishedSource(id: 's1', title: 'Zesty Contras'));
      await PublishedSourceRepository(
        db,
      ).upsert(PublishedSource(id: 's2', title: 'Give-and-Take'));
      final dance = sampleDance(
        sourceCitations: [
          SourceCitation(sourceId: 's2', page: '12-14', number: 'A1'),
          SourceCitation(sourceId: 's1'),
        ],
      );
      await dances.create(dance);
      final loaded = await dances.getById(dance.id);
      expect(loaded!.sourceCitations, hasLength(2));
      expect(loaded.sourceCitations.first.sourceId, 's2');
      expect(loaded.sourceCitations.first.page, '12-14');
      expect(loaded.sourceCitations.first.number, 'A1');
      expect(loaded.sourceCitations.last.sourceId, 's1');
      expect(loaded.sourceCitations.last.page, isNull);
      expect(loaded.sourceCitations.last.number, isNull);
    });

    test('deleting a dance cascades its source citations', () async {
      final sources = PublishedSourceRepository(db);
      await sources.upsert(PublishedSource(id: 's1', title: 'Zesty Contras'));
      final dance = sampleDance(
        sourceCitations: [SourceCitation(sourceId: 's1', page: '12')],
      );
      await dances.create(dance);
      // Hard-purge the dance so the FK cascade fires.
      await dances.softDelete(dance.id, at: DateTime.utc(2026, 2, 1));
      await dances.purgeDeleted(
        now: DateTime.utc(2026, 3, 5),
        retention: Duration.zero,
      );
      // The join row is gone (the source itself is now deletable).
      await sources.delete('s1');
      expect(await sources.getById('s1'), isNull);
    });

    test('round-trips provenance', () async {
      final dance = sampleDance(
        provenance: Provenance(
          source: ProvenanceSource.callersbox,
          externalId: 'CB-123',
          importedAt: DateTime.utc(2026, 2, 1),
          permission: 'full',
          license: 'CC-BY',
          rawPayload: '{"raw":true}',
          sourceVersion: '2026-01-15',
        ),
      );
      await dances.create(dance);
      final loaded = await dances.getById(dance.id);
      expect(loaded!.provenance!.source, ProvenanceSource.callersbox);
      expect(loaded.provenance!.externalId, 'CB-123');
      expect(loaded.provenance!.rawPayload, '{"raw":true}');
    });

    test('round-trips text/number/boolean/choice custom fields', () async {
      await customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f-text',
          key: 'origin',
          label: 'Origin',
          type: CustomFieldType.text,
        ),
      );
      await customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f-num',
          key: 'popularity',
          label: 'Popularity',
          type: CustomFieldType.number,
        ),
      );
      await customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f-bool',
          key: 'is_chestnut',
          label: 'Chestnut?',
          type: CustomFieldType.boolean,
        ),
      );
      await customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f-choice',
          key: 'difficulty',
          label: 'Difficulty',
          type: CustomFieldType.choice,
          choices: ['easy', 'medium', 'hard'],
        ),
      );
      final dance = sampleDance(
        customFields: [
          CustomFieldValue(fieldId: 'f-text', value: 'New England'),
          CustomFieldValue(fieldId: 'f-num', value: 4.5),
          CustomFieldValue(fieldId: 'f-bool', value: true),
          CustomFieldValue(fieldId: 'f-choice', value: 'medium'),
        ],
      );
      await dances.create(dance);
      final loaded = await dances.getById(dance.id);
      final byField = {
        for (final v in loaded!.customFields) v.fieldId: v.value,
      };
      expect(byField['f-text'], 'New England');
      expect(byField['f-num'], 4.5);
      expect(byField['f-bool'], true);
      expect(byField['f-choice'], 'medium');
    });

    test('rejects a custom field value for an unknown field id', () async {
      final dance = sampleDance(
        customFields: [CustomFieldValue(fieldId: 'missing', value: 'x')],
      );
      await expectLater(dances.create(dance), throwsA(isA<StateError>()));
    });

    test('returns null for a missing id', () async {
      expect(await dances.getById('nope'), isNull);
    });

    test('excludes soft-deleted dances by default', () async {
      final dance = sampleDance(deletedAt: DateTime.utc(2026, 1, 2));
      await dances.create(dance);
      expect(await dances.getById(dance.id), isNull);
      expect(await dances.getById(dance.id, includeDeleted: true), dance);
    });
  });

  group('update', () {
    test('replaces figures, tags, and links wholesale', () async {
      await tags.upsert(Tag(id: 't1', name: 'chestnut'));
      await tags.upsert(Tag(id: 't2', name: 'workshop'));
      final dance = sampleDance(tagIds: ['t1']);
      await dances.create(dance);

      final updated = dance.copyWith(
        tagIds: ['t2'],
        figures: [Figure(move: 'do_si_do')],
        updatedAt: DateTime.utc(2026, 3, 1),
      );
      await dances.update(updated);

      final loaded = await dances.getById(dance.id);
      expect(loaded!.tagIds, ['t2']);
      expect(loaded.figures, [Figure(move: 'do_si_do')]);
    });
  });

  group('listAll', () {
    test('orders by title and excludes soft-deleted by default', () async {
      await dances.create(sampleDance(id: 'd2', title: 'Zesty Zephyr'));
      await dances.create(sampleDance(id: 'd1', title: 'Airplane'));
      await dances.create(
        sampleDance(
          id: 'd3',
          title: 'Deleted Dance',
          deletedAt: DateTime.utc(2026, 1, 2),
        ),
      );
      final all = await dances.listAll();
      expect(all.map((d) => d.title), ['Airplane', 'Zesty Zephyr']);
      final withDeleted = await dances.listAll(includeDeleted: true);
      expect(withDeleted, hasLength(3));
    });
  });

  group('hasAny', () {
    test('reports emptiness and presence, honoring includeDeleted', () async {
      expect(await dances.hasAny(), isFalse);
      expect(await dances.hasAny(includeDeleted: true), isFalse);

      await dances.create(sampleDance(id: 'd1', title: 'Airplane'));
      expect(await dances.hasAny(), isTrue);

      await dances.softDelete('d1', at: DateTime.utc(2026, 1, 2));
      // Only a soft-deleted dance remains: absent by default, present when
      // deleted rows are included.
      expect(await dances.hasAny(), isFalse);
      expect(await dances.hasAny(includeDeleted: true), isTrue);
    });
  });

  group('listIdsAndTitles', () {
    test(
      'returns id+title pairs ordered by title, excluding soft-deleted',
      () async {
        await dances.create(sampleDance(id: 'd2', title: 'Zesty Zephyr'));
        await dances.create(sampleDance(id: 'd1', title: 'Airplane'));
        await dances.create(
          sampleDance(
            id: 'd3',
            title: 'Deleted Dance',
            deletedAt: DateTime.utc(2026, 1, 2),
          ),
        );

        final pairs = await dances.listIdsAndTitles();
        expect(pairs, [
          (id: 'd1', title: 'Airplane'),
          (id: 'd2', title: 'Zesty Zephyr'),
        ]);

        final withDeleted = await dances.listIdsAndTitles(includeDeleted: true);
        expect(withDeleted.map((p) => p.title), [
          'Airplane',
          'Deleted Dance',
          'Zesty Zephyr',
        ]);
      },
    );
  });

  group('listIdsTitlesAndForms', () {
    test(
      'returns id+title+form records ordered by title, excluding soft-deleted',
      () async {
        await dances.create(
          sampleDance(
            id: 'd2',
            title: 'Zesty Zephyr',
          ).copyWith(form: DanceForm.square),
        );
        await dances.create(
          sampleDance(
            id: 'd1',
            title: 'Airplane',
          ).copyWith(form: DanceForm.ecd),
        );
        await dances.create(
          sampleDance(
            id: 'd3',
            title: 'Deleted Dance',
            deletedAt: DateTime.utc(2026, 1, 2),
          ),
        );

        final records = await dances.listIdsTitlesAndForms();
        expect(records, [
          (id: 'd1', title: 'Airplane', form: DanceForm.ecd),
          (id: 'd2', title: 'Zesty Zephyr', form: DanceForm.square),
        ]);

        final withDeleted = await dances.listIdsTitlesAndForms(
          includeDeleted: true,
        );
        expect(withDeleted.map((r) => r.title), [
          'Airplane',
          'Deleted Dance',
          'Zesty Zephyr',
        ]);
      },
    );

    test('breaks equal-title ties deterministically by id', () async {
      await dances.create(sampleDance(id: 'd2', title: 'Same Dance'));
      await dances.create(sampleDance(id: 'd1', title: 'Same Dance'));
      final records = await dances.listIdsTitlesAndForms();
      expect(records.map((r) => r.id), ['d1', 'd2']);
    });
  });

  group('soft delete / restore / purge', () {
    test('soft delete then restore clears deletedAt', () async {
      final dance = sampleDance();
      await dances.create(dance);
      await dances.softDelete(dance.id, at: DateTime.utc(2026, 1, 5));
      expect(
        (await dances.getById(dance.id, includeDeleted: true))!.isDeleted,
        isTrue,
      );
      await dances.restore(dance.id, at: DateTime.utc(2026, 1, 6));
      expect(await dances.getById(dance.id), isNotNull);
    });

    test(
      'purgeDeleted removes dances past retention, keeps recent ones',
      () async {
        await dances.create(
          sampleDance(id: 'old', deletedAt: DateTime.utc(2026, 1, 1)),
        );
        await dances.create(
          sampleDance(id: 'recent', deletedAt: DateTime.utc(2026, 3, 20)),
        );
        final purged = await dances.purgeDeleted(
          now: DateTime.utc(2026, 4, 1),
          retention: const Duration(days: 30),
        );
        expect(purged, 1);
        expect(await dances.getById('old', includeDeleted: true), isNull);
        expect(await dances.getById('recent', includeDeleted: true), isNotNull);
      },
    );

    test(
      'purging a dance nulls a referencing program slot (no dangling FK)',
      () async {
        final programs = ProgramRepository(db);
        await dances.create(
          sampleDance(id: 'old', deletedAt: DateTime.utc(2026, 1, 1)),
        );
        await programs.create(
          Program(
            id: 'p1',
            title: 'Evening set',
            slots: [
              ProgramSlot(
                id: 's1',
                position: 0,
                danceId: 'old',
                text: 'The Old Dance',
              ),
            ],
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

        final purged = await dances.purgeDeleted(
          now: DateTime.utc(2026, 4, 1),
          retention: const Duration(days: 30),
        );

        expect(purged, 1);
        final program = await programs.getById('p1');
        expect(program, isNotNull);
        // The slot survives, its dance link is nulled, and the text tombstone
        // is preserved.
        expect(program!.slots.single.danceId, isNull);
        expect(program.slots.single.text, 'The Old Dance');
      },
    );
  });

  group('duplicate', () {
    test('creates an independent copy with fresh identity', () async {
      final dance = sampleDance();
      await dances.create(dance);
      final copy = await dances.duplicate(
        id: dance.id,
        newId: 'dance-1-copy',
        now: DateTime.utc(2026, 5, 1),
      );
      expect(copy.id, 'dance-1-copy');
      expect(copy.title, dance.title);
      expect(copy.provenance, isNull);

      final original = await dances.getById(dance.id);
      final loadedCopy = await dances.getById('dance-1-copy');
      expect(original, dance);
      expect(loadedCopy, copy);
    });

    test('duplicates a dance that has links without a PK collision', () async {
      final dance = sampleDance(
        id: 'with-links',
        links: [
          DanceLink(id: 'link-1', kind: LinkKind.video, url: 'https://v'),
          DanceLink(id: 'link-2', kind: LinkKind.source, url: 'https://s'),
        ],
      );
      await dances.create(dance);

      // Regression: Dance.duplicate used to reuse the source link ids, which
      // violated the DanceLinks primary key when the copy was persisted.
      final copy = await dances.duplicate(
        id: 'with-links',
        newId: 'with-links-copy',
        now: DateTime.utc(2026, 5, 1),
      );

      final loadedCopy = await dances.getById('with-links-copy');
      expect(loadedCopy, isNotNull);
      expect(loadedCopy!.links.length, 2);
      // Fresh link ids on the copy …
      final copyIds = copy.links.map((l) => l.id).toSet();
      expect(copyIds, isNot(contains('link-1')));
      expect(copyIds, isNot(contains('link-2')));
      // … and the original's links are untouched.
      final original = await dances.getById('with-links');
      expect(original!.links.map((l) => l.id).toSet(), {'link-1', 'link-2'});
    });
  });

  group('full-text search', () {
    test('finds a dance by title token', () async {
      await dances.create(sampleDance(id: 'd1', title: 'Chase the Squirrel'));
      await dances.create(sampleDance(id: 'd2', title: 'Rambling Montana'));
      expect(await dances.searchText('Squirrel'), ['d1']);
    });

    test('finds a dance by canonical figure text', () async {
      await dances.create(
        sampleDance(
          id: 'd1',
          figures: [Figure(move: 'shoulder_round')],
        ),
      );
      await dances.create(
        sampleDance(
          id: 'd2',
          figures: [Figure(move: 'swing')],
        ),
      );
      final hits = await dances.searchText('shoulder');
      expect(hits, contains('d1'));
      expect(hits, isNot(contains('d2')));
    });

    test('search index is rebuilt on update (no stale hits)', () async {
      final dance = sampleDance(id: 'd1', title: 'Old Title');
      await dances.create(dance);
      expect(await dances.searchText('Old'), ['d1']);
      await dances.update(dance.copyWith(title: 'New Title'));
      expect(await dances.searchText('Old'), isEmpty);
      expect(await dances.searchText('New'), ['d1']);
    });
  });

  group('structural search', () {
    test('finds dances containing a figure move', () async {
      await dances.create(
        sampleDance(
          id: 'd1',
          figures: [Figure(move: 'do_si_do')],
        ),
      );
      await dances.create(
        sampleDance(
          id: 'd2',
          figures: [Figure(move: 'swing')],
        ),
      );
      expect(await dances.danceIdsWithFigure('do_si_do'), ['d1']);
    });

    test('filters further by an exact param value', () async {
      await dances.create(
        sampleDance(
          id: 'd1',
          figures: [
            Figure(move: 'swing', params: const {'who': 'partners'}),
          ],
        ),
      );
      await dances.create(
        sampleDance(
          id: 'd2',
          figures: [
            Figure(move: 'swing', params: const {'who': 'neighbors'}),
          ],
        ),
      );
      final hits = await dances.danceIdsWithFigure(
        'swing',
        paramKey: 'who',
        paramJsonValue: '"neighbors"',
      );
      expect(hits, ['d2']);
    });

    test('excludes soft-deleted dances', () async {
      await dances.create(
        sampleDance(
          id: 'd1',
          figures: [Figure(move: 'swing')],
          deletedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      expect(await dances.danceIdsWithFigure('swing'), isEmpty);
    });
  });

  group('rebuildAllDerived', () {
    test('recomputes derived tables identically from figures_json', () async {
      await dances.create(
        sampleDance(
          id: 'd1',
          figures: [Figure(move: 'do_si_do')],
        ),
      );
      final before = await dances.danceIdsWithFigure('do_si_do');
      await dances.rebuildAllDerived();
      final after = await dances.danceIdsWithFigure('do_si_do');
      expect(after, before);
      expect(await dances.searchText('dosido'), isEmpty); // sanity: no dupes
    });
  });
}
