import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

/// Reads the derived `dance_figures.params_json` string for the figure at
/// [idx] of [danceId]. Used to assert the stored JSON has not drifted from the
/// source encoding (e.g. a key-order change on re-encode).
Future<String> _figureParamsJson(
  CompendiumDatabase db,
  String danceId,
  int idx,
) async {
  final row =
      await (db.select(db.danceFigures)
            ..where((t) => t.danceId.equals(danceId))
            ..where((t) => t.idx.equals(idx)))
          .getSingle();
  return row.paramsJson;
}

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
        // invalid-fixture: move is deliberately outside the taxonomy — losslessly round-trips a figure whose move is unknown (#358)
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

        // The canonical source of truth (figures_json) must round-trip the
        // move + params verbatim.
        final loaded = await dances.getById(dance.id);
        expect(loaded, dance, reason: 'whole dance round-trips by value');
        final reloadedUnknown = loaded!.figures[1];
        expect(reloadedUnknown.move, 'a_move_from_the_future');
        expect(reloadedUnknown.params, {
          'beats': 12,
          'flavor': 'spicy',
          'who': 'partners',
        });

        // The derived dance_figures.params_json string must also be
        // byte-for-byte identical to the encoded source params — comparing
        // decoded maps alone wouldn't catch JSON re-encoding drift (e.g. a
        // key-order change) that could break search/dedupe parity.
        const expectedJson = '{"beats":12,"flavor":"spicy","who":"partners"}';
        expect(await _figureParamsJson(db, dance.id, 1), expectedJson);

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
        // The update path must encode identically to create() — assert the
        // derived params_json string again so a divergent re-encode fails.
        expect(await _figureParamsJson(db, dance.id, 1), expectedJson);
      },
    );

    test('round-trips a customOrigin.importGap flag and defaults on '
        'legacy figures_json lacking the key', () async {
      final gap = customFigure(
        'kept verbatim',
        beats: 8,
        origin: CustomOrigin.importGap,
      );
      expect(gap.customOrigin, CustomOrigin.importGap);
      final dance = sampleDance(
        figures: [
          Figure(move: 'swing', params: const {'beats': 8}),
          gap,
        ],
      );
      await dances.create(dance);

      final loaded = await dances.getById(dance.id);
      expect(loaded, dance, reason: 'whole dance round-trips by value');
      expect(loaded!.figures[1].customOrigin, CustomOrigin.importGap);
      // A user-entered figure stays userEntered.
      expect(loaded.figures[0].customOrigin, CustomOrigin.userEntered);

      // Simulate a legacy row whose figures_json predates the discriminator:
      // it must read back as userEntered, never mislabeled as importGap.
      const legacyJson =
          '[{"schemaVersion":1,"move":"custom","params":{"text":"old"}}]';
      await db.customStatement(
        'UPDATE dances SET figures_json = ? WHERE id = ?',
        [legacyJson, dance.id],
      );
      final legacy = await dances.getById(dance.id);
      expect(legacy!.figures.single.customOrigin, CustomOrigin.userEntered);
    });

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
          sourceVersion: '2026-01-15',
        ),
      );
      await dances.create(dance);
      final loaded = await dances.getById(dance.id);
      expect(loaded!.provenance!.source, ProvenanceSource.callersbox);
      expect(loaded.provenance!.externalId, 'CB-123');
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

    test(
      'batched hydration matches single-row getById for every relation',
      () async {
        // Two authors, tags, a published source, custom-field defs, and a
        // related dance so the batched child loaders exercise authors, tags,
        // links, sources, custom fields, and provenance at once.
        await choreographers.upsert(Choreographer(id: 'c1', name: 'Alice'));
        await choreographers.upsert(Choreographer(id: 'c2', name: 'Bob'));
        await tags.upsert(Tag(id: 't1', name: 'chestnut'));
        await tags.upsert(Tag(id: 't2', name: 'smooth'));
        await PublishedSourceRepository(
          db,
        ).upsert(PublishedSource(id: 's1', title: 'Zesty Contras'));
        await customFieldDefs.upsert(
          CustomFieldDef(
            id: 'f-text',
            key: 'origin',
            label: 'Origin',
            type: CustomFieldType.text,
          ),
        );

        await dances.create(sampleDance(id: 'target', title: 'Aaa Related'));
        final rich = sampleDance(
          id: 'rich',
          title: 'Bbb Rich Dance',
          // authorIds reversed vs. choreographer id order to prove position
          // order (not id order) survives the batched load.
          authorIds: const ['c2', 'c1'],
          tagIds: const ['t2', 't1'],
          links: [
            DanceLink(id: 'l1', kind: LinkKind.video, url: 'https://v.example'),
            DanceLink(
              id: 'l2',
              kind: LinkKind.relatedDance,
              targetDanceId: 'target',
              label: 'similar',
            ),
          ],
          sourceCitations: [SourceCitation(sourceId: 's1', page: '7')],
          customFields: [
            CustomFieldValue(fieldId: 'f-text', value: 'New England'),
          ],
          provenance: Provenance(
            source: ProvenanceSource.contradb,
            externalId: 'CDB-9',
            importedAt: DateTime.utc(2026, 2, 1),
          ),
        );
        await dances.create(rich);

        final all = await dances.listAll();
        final fromList = all.firstWhere((d) => d.id == 'rich');
        final fromGet = await dances.getById('rich');
        // The batched list path must produce a value-identical Dance to the
        // per-row getById path (same fields, same child-collection ordering).
        expect(fromList, fromGet);
        expect(fromList, rich);
        expect(fromList.authorIds, ['c2', 'c1']);
        expect(fromList.tagIds, ['t2', 't1']);
        expect(fromList.links.map((l) => l.id), ['l1', 'l2']);
      },
    );

    test('batched load spans an id chunk boundary', () async {
      // More than one _idChunkSize (500) worth of dances, each with an author
      // and a tag, so the batched loaders must stitch results across chunks.
      await choreographers.upsert(Choreographer(id: 'c1', name: 'Alice'));
      await tags.upsert(Tag(id: 't1', name: 'chestnut'));
      const total = 1050;
      for (var i = 0; i < total; i++) {
        await dances.create(
          sampleDance(
            id: 'd${i.toString().padLeft(4, '0')}',
            title: 'Dance ${i.toString().padLeft(4, '0')}',
            authorIds: const ['c1'],
            tagIds: const ['t1'],
          ),
        );
      }
      final all = await dances.listAll();
      expect(all, hasLength(total));
      // Every dance keeps its author + tag regardless of which chunk it fell
      // in (a grouping/merge bug would drop children for later chunks).
      expect(all.every((d) => d.authorIds.length == 1), isTrue);
      expect(all.every((d) => d.tagIds.length == 1), isTrue);
    });

    test(
      'batches child hydration into a constant number of queries (no N+1)',
      () async {
        // The regression guard for the fix: parity tests alone would still pass
        // against the old per-row _toModel, so assert the query SHAPE too. A
        // single id-chunk (<= 500 dances) must issue exactly six child selects
        // total — one per relation table — not six per dance (the old N+1 sent
        // 6 * N).
        final counter = DanceChildSelectCounter();
        final countingDb = openCountingTestDatabase(counter);
        addTearDown(countingDb.close);
        final countingDances = DanceRepository(countingDb, contraTaxonomy);

        for (var i = 0; i < 25; i++) {
          await countingDances.create(
            sampleDance(id: 'd$i', title: 'Dance $i'),
          );
        }
        counter.reset();
        final loaded = await countingDances.listAll();
        expect(loaded, hasLength(25));
        expect(counter.count, 6);
      },
    );

    test('child-query count grows per id-chunk, not per dance', () async {
      // 501 dances => two id-chunks (500 + 1). Each of the six child loaders
      // runs once per chunk, so the total is 12 — O(chunks), still constant in
      // the dance count within a chunk, never the 6 * 501 an N+1 would produce.
      final counter = DanceChildSelectCounter();
      final countingDb = openCountingTestDatabase(counter);
      addTearDown(countingDb.close);
      final countingDances = DanceRepository(countingDb, contraTaxonomy);

      for (var i = 0; i < 501; i++) {
        await countingDances.create(
          sampleDance(id: 'd${i.toString().padLeft(4, '0')}', title: 'D $i'),
        );
      }
      counter.reset();
      final loaded = await countingDances.listAll();
      expect(loaded, hasLength(501));
      expect(counter.count, 12);
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

    test('purging the TARGET of a relatedDance link does not corrupt the owner '
        'dance load (#466)', () async {
      // Owner dance A links to target dance B via a relatedDance link. B is
      // soft-deleted and purged. A pre-fix purge SET NULL the link's
      // target_dance_id, leaving (relatedDance, targetDanceId=null) — which
      // DanceLink rejects — so loading ANY dance threw. The purge now deletes
      // the now-meaningless orphan link instead.
      await dances.create(
        sampleDance(id: 'b', title: 'Target', deletedAt: DateTime.utc(2026)),
      );
      await dances.create(
        sampleDance(
          id: 'a',
          title: 'Owner',
          links: [
            DanceLink(
              id: 'l1',
              kind: LinkKind.relatedDance,
              targetDanceId: 'b',
            ),
          ],
        ),
      );

      final purged = await dances.purgeDeleted(now: DateTime.utc(2026, 4, 1));
      expect(purged, 1);

      // getById(A) must not throw; its orphaned relatedDance link is gone.
      final owner = await dances.getById('a');
      expect(owner, isNotNull);
      expect(owner!.links, isEmpty);

      // listAll hydrates every dance's links in one loop — the path a single
      // corrupt link historically took down — so it must also succeed.
      final all = await dances.listAll();
      expect(all.map((d) => d.id), ['a']);
      expect(all.single.links, isEmpty);
    });

    test('purgeDeleted cleans references only for the dances it actually '
        'deletes (single-snapshot guarantee, #473 review)', () async {
      // Regression guard for the TOCTOU race fixed by moving the eligibility
      // SELECT inside the purge transaction and deleting by the exact selected
      // ids. The observable invariant: a dance that SURVIVES the purge must
      // never have its dance-only slots tombstoned or its incoming
      // relatedDance links deleted. We prove it by giving a still-retained
      // (soft-deleted but not-yet-past-cutoff) dance the identical reference
      // shapes as the purged one and asserting they are left completely
      // untouched — cleanup and deletion operate on one consistent set.
      final programs = ProgramRepository(db);
      // 'old' is past the cutoff (eligible); 'recent' is within retention.
      await dances.create(
        sampleDance(
          id: 'old',
          title: 'Old Dance',
          deletedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await dances.create(
        sampleDance(
          id: 'recent',
          title: 'Recent Dance',
          deletedAt: DateTime.utc(2026, 3, 20),
        ),
      );
      // A surviving owner links to BOTH — only the link to 'old' should go.
      await dances.create(
        sampleDance(
          id: 'owner',
          title: 'Owner',
          links: [
            DanceLink(
              id: 'l-old',
              kind: LinkKind.relatedDance,
              targetDanceId: 'old',
            ),
            DanceLink(
              id: 'l-recent',
              kind: LinkKind.relatedDance,
              targetDanceId: 'recent',
            ),
          ],
        ),
      );
      // Two dance-only slots — only the one referencing 'old' should tombstone.
      await programs.create(
        Program(
          id: 'p1',
          title: 'Set',
          slots: [
            ProgramSlot(id: 's-old', position: 0, danceId: 'old'),
            ProgramSlot(id: 's-recent', position: 1, danceId: 'recent'),
          ],
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );

      final purged = await dances.purgeDeleted(
        now: DateTime.utc(2026, 4, 1),
        retention: const Duration(days: 30),
      );

      // Exactly the eligible dance was removed; the retained one survives.
      expect(purged, 1);
      expect(await dances.getById('old', includeDeleted: true), isNull);
      expect(await dances.getById('recent', includeDeleted: true), isNotNull);

      // The surviving owner kept its link to the retained target and lost only
      // the link to the purged one.
      final owner = await dances.getById('owner');
      expect(owner, isNotNull);
      expect(owner!.links.map((l) => l.id), ['l-recent']);
      expect(owner.links.single.targetDanceId, 'recent');

      // Only the purged dance's slot was tombstoned; the retained dance's slot
      // is completely untouched (still linked, no spurious caption).
      final program = await programs.getById('p1');
      expect(program, isNotNull);
      final byId = {for (final s in program!.slots) s.id: s};
      expect(byId['s-old']!.danceId, isNull);
      expect(byId['s-old']!.text, 'Old Dance');
      expect(byId['s-recent']!.danceId, 'recent');
      expect(byId['s-recent']!.text, isNull);

      // Loads succeed and the database is referentially clean.
      expect(await dances.listAll(), isNotEmpty);
      final fkViolations = await db
          .customSelect('PRAGMA foreign_key_check')
          .get();
      expect(fkViolations, isEmpty);
    });

    test('loading tolerates a legacy orphaned relatedDance link rather than '
        'throwing (#466 belt-and-suspenders)', () async {
      // Simulate a link left corrupt by a build that predates the fix: a
      // relatedDance link whose target_dance_id is NULL. The mapper must skip
      // it so it cannot block loading its owner dance.
      await dances.create(sampleDance(id: 'a', title: 'Owner'));
      await db.customStatement(
        'INSERT INTO dance_links (id, dance_id, kind, target_dance_id) '
        'VALUES (?, ?, ?, NULL)',
        ['l-bad', 'a', LinkKind.relatedDance.name],
      );

      final owner = await dances.getById('a');
      expect(owner, isNotNull);
      expect(owner!.links, isEmpty);

      final all = await dances.listAll();
      expect(all.single.links, isEmpty);
    });
  });

  group('orphan reference GC after purge (#462)', () {
    late PublishedSourceRepository sources;

    setUp(() {
      sources = PublishedSourceRepository(db);
    });

    test('purging the only dance crediting a choreographer / citing a source '
        'GCs those now-orphaned rows', () async {
      await choreographers.upsert(Choreographer(id: 'c1', name: 'Solo Author'));
      await sources.upsert(PublishedSource(id: 's1', title: 'Solo Source'));
      await dances.create(
        sampleDance(
          id: 'only',
          authorIds: const ['c1'],
          sourceCitations: [SourceCitation(sourceId: 's1')],
          deletedAt: DateTime.utc(2026, 1, 1),
        ),
      );

      final purged = await dances.purgeDeleted(now: DateTime.utc(2026, 4, 1));

      expect(purged, 1);
      expect(await choreographers.getById('c1'), isNull);
      expect(await sources.getById('s1'), isNull);
    });

    test('a choreographer / source still referenced by a surviving dance is '
        'retained', () async {
      await choreographers.upsert(Choreographer(id: 'c1', name: 'Shared'));
      await sources.upsert(PublishedSource(id: 's1', title: 'Shared Source'));
      await dances.create(
        sampleDance(
          id: 'doomed',
          authorIds: const ['c1'],
          sourceCitations: [SourceCitation(sourceId: 's1')],
          deletedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      // A live dance keeps citing the same choreographer + source.
      await dances.create(
        sampleDance(
          id: 'survivor',
          authorIds: const ['c1'],
          sourceCitations: [SourceCitation(sourceId: 's1')],
        ),
      );

      final purged = await dances.purgeDeleted(now: DateTime.utc(2026, 4, 1));

      expect(purged, 1);
      expect(await choreographers.getById('c1'), isNotNull);
      expect(await sources.getById('s1'), isNotNull);
    });

    test('a choreographer / source referenced only by a soft-deleted-but-'
        'retained dance is NOT GCd', () async {
      await choreographers.upsert(Choreographer(id: 'c1', name: 'Held'));
      await sources.upsert(PublishedSource(id: 's1', title: 'Held Source'));
      await dances.create(
        sampleDance(
          id: 'doomed',
          authorIds: const ['c1'],
          sourceCitations: [SourceCitation(sourceId: 's1')],
          deletedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      // Soft-deleted recently — survives this purge, and its join rows persist,
      // so the shared choreographer/source must be kept.
      await dances.create(
        sampleDance(
          id: 'retained',
          authorIds: const ['c1'],
          sourceCitations: [SourceCitation(sourceId: 's1')],
          deletedAt: DateTime.utc(2026, 3, 25),
        ),
      );

      final purged = await dances.purgeDeleted(now: DateTime.utc(2026, 4, 1));

      expect(purged, 1);
      expect(await dances.getById('retained', includeDeleted: true), isNotNull);
      expect(await choreographers.getById('c1'), isNotNull);
      expect(await sources.getById('s1'), isNotNull);
    });

    test(
      'an unreferenced row this purge did not touch is left alone',
      () async {
        // A reusable choreographer/source that no purged dance referenced must
        // not be swept just because it happens to be unreferenced.
        await choreographers.upsert(
          Choreographer(id: 'keep', name: 'Traditional'),
        );
        await sources.upsert(
          PublishedSource(id: 'keep-src', title: 'Reusable'),
        );
        await choreographers.upsert(Choreographer(id: 'c1', name: 'Purged'));
        await dances.create(
          sampleDance(
            id: 'only',
            authorIds: const ['c1'],
            deletedAt: DateTime.utc(2026, 1, 1),
          ),
        );

        final purged = await dances.purgeDeleted(now: DateTime.utc(2026, 4, 1));

        expect(purged, 1);
        expect(await choreographers.getById('c1'), isNull);
        // Untouched reusable rows remain.
        expect(await choreographers.getById('keep'), isNotNull);
        expect(await sources.getById('keep-src'), isNotNull);
      },
    );

    test('hardDelete also GCs now-orphaned reference rows', () async {
      await choreographers.upsert(Choreographer(id: 'c1', name: 'Solo Author'));
      await sources.upsert(PublishedSource(id: 's1', title: 'Solo Source'));
      await choreographers.upsert(Choreographer(id: 'c2', name: 'Shared'));
      await dances.create(
        sampleDance(
          id: 'doomed',
          authorIds: const ['c1', 'c2'],
          sourceCitations: [SourceCitation(sourceId: 's1')],
        ),
      );
      // Survivor keeps c2 alive; c1 + s1 become orphans after hardDelete.
      await dances.create(sampleDance(id: 'survivor', authorIds: const ['c2']));

      await dances.hardDelete(const ['doomed']);

      expect(await dances.getById('doomed', includeDeleted: true), isNull);
      expect(await choreographers.getById('c1'), isNull);
      expect(await sources.getById('s1'), isNull);
      expect(await choreographers.getById('c2'), isNotNull);
    });

    test('hardDelete with gcOrphanedRefs: false leaves now-orphaned rows '
        '(import-undo rollback contract)', () async {
      await choreographers.upsert(Choreographer(id: 'c1', name: 'Solo Author'));
      await sources.upsert(PublishedSource(id: 's1', title: 'Solo Source'));
      await dances.create(
        sampleDance(
          id: 'only',
          authorIds: const ['c1'],
          sourceCitations: [SourceCitation(sourceId: 's1')],
        ),
      );

      await dances.hardDelete(const ['only'], gcOrphanedRefs: false);

      expect(await dances.getById('only', includeDeleted: true), isNull);
      // The reference rows survive the delete so a rollback can restore state.
      expect(await choreographers.getById('c1'), isNotNull);
      expect(await sources.getById('s1'), isNotNull);
    });
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

    test('excludes soft-deleted dances (#439)', () async {
      await dances.create(sampleDance(id: 'd1', title: 'Chase the Squirrel'));
      await dances.create(sampleDance(id: 'd2', title: 'Squirrel Stampede'));
      // Soft-delete leaves the dance_fts row intact, so the bare MATCH would
      // still surface the trashed dance without the deleted_at filter.
      await dances.softDelete('d1', at: DateTime.utc(2026, 1, 2));
      final hits = await dances.searchText('Squirrel');
      expect(hits, ['d2']);
      expect(hits, isNot(contains('d1')));
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

    Future<int> ftsRowCount(CompendiumDatabase database) async {
      final rows = await database
          .customSelect('SELECT COUNT(*) AS c FROM dance_fts')
          .get();
      return rows.single.read<int>('c');
    }

    test('reindexes every dance (incl. soft-deleted) and is idempotent', () async {
      await dances.create(sampleDance(id: 'd1', title: 'Chase the Squirrel'));
      await dances.create(sampleDance(id: 'd2', title: 'Rambling Montana'));
      await dances.create(sampleDance(id: 'd3', title: 'Squirrel Stampede'));
      // Soft-deleted dances stay in dance_fts (they are filtered at query time,
      // #439), so the rebuild must still index them.
      await dances.softDelete('d3', at: DateTime.utc(2026, 1, 2));

      await dances.rebuildAllDerived();
      expect(await ftsRowCount(db), 3);
      // A second rebuild must not duplicate rows or leave stale ones behind —
      // the bulk clear resets the whole index before re-inserting.
      await dances.rebuildAllDerived();
      expect(await ftsRowCount(db), 3);

      // Live dances remain searchable; the soft-deleted 'Squirrel Stampede' is
      // excluded by the query-time filter, not by being absent from the index.
      expect(await dances.searchText('Squirrel'), ['d1']);
    });

    test('reports monotonic progress ending at (total, total)', () async {
      for (var i = 0; i < 5; i++) {
        await dances.create(sampleDance(id: 'd$i', title: 'Dance $i'));
      }
      final events = <DerivedRebuildProgress>[];
      await dances.rebuildAllDerived(chunkSize: 2, onProgress: events.add);

      // Initial (0,5) + chunks of 2,2,1 => three chunk events = four total.
      expect(events.length, 4);
      expect(
        events.first,
        const DerivedRebuildProgress(completed: 0, total: 5),
      );
      expect(events.last, const DerivedRebuildProgress(completed: 5, total: 5));
      expect(events.last.fraction, 1.0);
      for (var i = 1; i < events.length; i++) {
        expect(
          events[i].completed,
          greaterThanOrEqualTo(events[i - 1].completed),
        );
        expect(events[i].total, 5);
      }
    });

    test(
      'multi-chunk rebuild produces the same derived rows as one pass',
      () async {
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
        await dances.create(
          sampleDance(
            id: 'd3',
            title: 'Shoulder Shake',
            figures: [Figure(move: 'balance')],
          ),
        );
        final events = <DerivedRebuildProgress>[];
        await dances.rebuildAllDerived(chunkSize: 1, onProgress: events.add);

        // One chunk per dance: initial event + three chunk events.
        expect(events.length, 4);
        expect(await dances.danceIdsWithFigure('do_si_do'), ['d1']);
        expect(await dances.danceIdsWithFigure('swing'), ['d2']);
        expect(await dances.danceIdsWithFigure('balance'), ['d3']);
        expect(await dances.searchText('Shoulder'), ['d3']);
      },
    );

    test('issues no per-dance FTS delete-by-scan (bulk clear only)', () async {
      final counter = FtsDeleteByDanceCounter();
      final countingDb = openCountingTestDatabase(counter);
      addTearDown(countingDb.close);
      final repo = DanceRepository(countingDb, contraTaxonomy);
      for (var i = 0; i < 4; i++) {
        await repo.create(sampleDance(id: 'd$i', title: 'Dance $i'));
      }
      // Each create() does one per-dance FTS delete; reset so we measure only
      // the rebuild's writes.
      counter.count = 0;
      await repo.rebuildAllDerived(chunkSize: 2);
      expect(
        counter.count,
        0,
        reason:
            'rebuild must clear dance_fts in one bulk DELETE, not per dance',
      );
    });

    test('rejects a non-positive chunkSize before touching the index '
        '(#440)', () async {
      // A non-positive chunkSize would leave the chunk loop unable to advance
      // and hang the rebuild, so it must fail fast with an ArgumentError even
      // in release builds (where asserts are stripped) — and before the bulk
      // clear runs, so an existing index is left intact.
      await dances.create(sampleDance(id: 'd1', title: 'Existing'));
      await dances.rebuildAllDerived();
      expect(await dances.searchText('Existing'), ['d1']);

      for (final bad in [0, -1, -250]) {
        await expectLater(
          () => dances.rebuildAllDerived(chunkSize: bad),
          throwsA(
            isA<ArgumentError>()
                .having((e) => e.name, 'name', 'chunkSize')
                .having((e) => e.invalidValue, 'invalidValue', bad),
          ),
        );
      }

      // The guard threw before clearing, so the previously built index is
      // untouched.
      expect(await dances.searchText('Existing'), ['d1']);
    });
  });
}
