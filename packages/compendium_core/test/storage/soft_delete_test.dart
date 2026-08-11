// Behaviour tests for the schema-v25 soft-delete conversion (issue #898).
//
// `migration_test.dart` covers what the *migration* writes; this file covers
// what the repositories do afterwards: that six entity-level deletes tombstone
// rather than erase, that a tombstoned row disappears from every read that
// could surface it, that the join rows a hard delete used to cascade away are
// deliberately kept and filtered instead, and that reviving a record advances
// `existence_at` so a peer holding the tombstone cannot win.
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repos;

  final t0 = DateTime.utc(2026, 5, 1, 12);

  setUp(() {
    db = openTestDatabase();
    repos = CompendiumRepositories(db, contraTaxonomy);
  });
  tearDown(() => db.close());

  /// Raw row count, bypassing the repositories' live filters — the only way to
  /// tell "tombstoned" from "gone".
  Future<int> rawCount(String table, String keyColumn, String key) async {
    final rows = await db
        .customSelect(
          "SELECT COUNT(*) AS n FROM $table WHERE $keyColumn = ?",
          variables: [Variable.withString(key)],
        )
        .get();
    return rows.single.read<int>('n');
  }

  Future<int?> rawStamp(
    String table,
    String column,
    String keyColumn,
    String key,
  ) async {
    final rows = await db
        .customSelect(
          "SELECT $column AS v FROM $table WHERE $keyColumn = ?",
          variables: [Variable.withString(key)],
        )
        .get();
    return rows.single.data['v'] as int?;
  }

  group('the six converted deletes tombstone rather than erase', () {
    test(
      'a deleted tag is still on disk, and invisible to every read',
      () async {
        await repos.tags.upsert(
          Tag(id: 't1', name: 'Easy'),
          at: t0,
        );
        await repos.tags.delete('t1', at: t0.add(const Duration(minutes: 1)));

        expect(
          await rawCount('tags', 'id', 't1'),
          1,
          reason: 'the row must survive — a peer has to learn of the deletion',
        );
        expect(await rawStamp('tags', 'deleted_at', 'id', 't1'), isNotNull);
        expect(await repos.tags.getById('t1'), isNull);
        expect(await repos.tags.listAll(), isEmpty);
      },
    );

    test('a removed setting is tombstoned, and reads as absent', () async {
      await repos.settings.set('pref', 'value', at: t0);
      await repos.settings.remove(
        'pref',
        at: t0.add(const Duration(minutes: 1)),
      );

      expect(await rawCount('settings', 'key', 'pref'), 1);
      expect(
        await rawStamp('settings', 'deleted_at', 'key', 'pref'),
        isNotNull,
      );
      expect(await repos.settings.get('pref'), isNull);
      expect(await repos.settings.contains('pref'), isFalse);
      expect(await repos.settings.all(), isNot(contains('pref')));
    });

    test(
      'choreographer, source, custom field and venue all tombstone',
      () async {
        await repos.choreographers.upsert(
          Choreographer(id: 'c1', name: 'Author'),
          at: t0,
        );
        await repos.publishedSources.upsert(
          PublishedSource(id: 's1', title: 'Book'),
          at: t0,
        );
        await repos.customFieldDefs.upsert(
          CustomFieldDef(
            id: 'f1',
            key: 'k',
            label: 'L',
            type: CustomFieldType.text,
          ),
          at: t0,
        );
        await repos.venues.upsert(
          Venue(id: 'v1', name: 'Hall'),
          at: t0,
        );

        final at = t0.add(const Duration(minutes: 1));
        await repos.choreographers.delete('c1', at: at);
        await repos.publishedSources.delete('s1', at: at);
        await repos.customFieldDefs.delete('f1', at: at);
        await repos.venues.delete('v1', at: at);

        for (final (table, id) in const [
          ('choreographers', 'c1'),
          ('published_sources', 's1'),
          ('custom_field_defs', 'f1'),
          ('venues', 'v1'),
        ]) {
          expect(await rawCount(table, 'id', id), 1, reason: table);
          expect(
            await rawStamp(table, 'deleted_at', 'id', id),
            isNotNull,
            reason: table,
          );
        }
        expect(await repos.choreographers.listAll(), isEmpty);
        expect(await repos.publishedSources.listAll(), isEmpty);
        expect(await repos.customFieldDefs.listAll(), isEmpty);
        expect(await repos.venues.listAll(), isEmpty);
        expect(await repos.venues.listAllIds(), isEmpty);
      },
    );

    test(
      'a tombstoning delete stamps existence_at, deleted_at and updated_at',
      () async {
        await repos.tags.upsert(
          Tag(id: 't1', name: 'Easy'),
          at: t0,
        );
        final at = t0.add(const Duration(minutes: 1));
        await repos.tags.delete('t1', at: at);

        final stamp = unixSeconds(at);
        expect(await rawStamp('tags', 'deleted_at', 'id', 't1'), stamp);
        expect(await rawStamp('tags', 'updated_at', 'id', 't1'), stamp);
        expect(await rawStamp('tags', 'existence_at', 'id', 't1'), stamp);
      },
    );

    test('a permanently removed setting leaves no row at all', () async {
      // Device-scoped scratch has no peer to inform, so a tombstone is pure
      // cost. The editor autosave drafts are the reachable case: cleared on
      // every save and every discard, each tombstone retaining the whole draft
      // blob, with no retention sweep to reclaim it.
      await repos.settings.set('editor_draft:d1', 'a big draft blob', at: t0);
      await repos.settings.remove('editor_draft:d1', permanent: true);

      expect(
        await rawCount('settings', 'key', 'editor_draft:d1'),
        0,
        reason: 'a discarded draft must not be retained as a tombstone',
      );
    });

    test('repeated draft cycles do not accumulate rows', () async {
      // The growth is proportional to how much the user works, so assert the
      // shape rather than a single case: fifty edit/clear cycles must leave the
      // table exactly as empty as one.
      for (var i = 0; i < 50; i++) {
        await repos.settings.set('editor_draft:d$i', 'draft $i', at: t0);
        await repos.settings.remove('editor_draft:d$i', permanent: true);
      }
      final rows = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM settings WHERE key LIKE 'editor_draft:%'",
          )
          .get();
      expect(rows.single.read<int>('n'), 0);
    });

    test('an ordinary preference removal still tombstones', () async {
      // The other half: `permanent` must stay opt-in, so a preference the user
      // actually cleared is still something a peer can learn about.
      await repos.settings.set('theme_mode', 'dark', at: t0);
      await repos.settings.remove('theme_mode', at: t0);
      expect(await rawCount('settings', 'key', 'theme_mode'), 1);
      expect(
        await rawStamp('settings', 'deleted_at', 'key', 'theme_mode'),
        isNotNull,
      );
    });

    test('deleting an unknown id is a no-op, as it was before', () async {
      await repos.tags.delete('nope', at: t0);
      await repos.settings.remove('nope', at: t0);
      expect(await rawCount('tags', 'id', 'nope'), 0);
    });
  });

  group('the referential guards are kept', () {
    test('a credited choreographer still cannot be deleted', () async {
      await repos.choreographers.upsert(
        Choreographer(id: 'c1', name: 'Author'),
        at: t0,
      );
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'D',
          figures: [],
          authorIds: ['c1'],
          createdAt: t0,
          updatedAt: t0,
        ),
      );
      await expectLater(
        repos.choreographers.delete('c1', at: t0),
        throwsA(isA<StateError>()),
      );
      // And the failed guard left no half-applied tombstone behind.
      expect(
        await rawStamp('choreographers', 'deleted_at', 'id', 'c1'),
        isNull,
      );
      expect(await repos.choreographers.getById('c1'), isNotNull);
    });

    test('a referenced venue still cannot be deleted', () async {
      await repos.venues.upsert(
        Venue(id: 'v1', name: 'Hall'),
        at: t0,
      );
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'P',
          venueId: 'v1',
          createdAt: t0,
          updatedAt: t0,
        ),
      );
      await expectLater(
        repos.venues.delete('v1', at: t0),
        throwsA(isA<StateError>()),
      );
      expect(await rawStamp('venues', 'deleted_at', 'id', 'v1'), isNull);
    });
  });

  group('permanent delete (import undo) still erases', () {
    test(
      'permanent: true removes the row entirely, leaving no tombstone',
      () async {
        await repos.choreographers.upsert(
          Choreographer(id: 'c1', name: 'Author'),
          at: t0,
        );
        await repos.choreographers.delete('c1', at: t0, permanent: true);
        expect(
          await rawCount('choreographers', 'id', 'c1'),
          0,
          reason: 'a rollback must leave nothing for a peer to learn from',
        );
      },
    );

    test('permanent: true still honours the guard', () async {
      await repos.venues.upsert(
        Venue(id: 'v1', name: 'Hall'),
        at: t0,
      );
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'P',
          venueId: 'v1',
          createdAt: t0,
          updatedAt: t0,
        ),
      );
      await expectLater(
        repos.venues.delete('v1', at: t0, permanent: true),
        throwsA(isA<StateError>()),
      );
      expect(await rawCount('venues', 'id', 'v1'), 1);
    });

    test('VenueRepository.hardDelete stays a hard delete', () async {
      await repos.venues.upsert(
        Venue(id: 'v1', name: 'Hall'),
        at: t0,
      );
      await repos.venues.hardDelete(['v1']);
      expect(await rawCount('venues', 'id', 'v1'), 0);
    });
  });

  group('reads that join through a soft-deletable parent', () {
    /// Builds a dance carrying a tag, an author, a citation and a custom value,
    /// so each join can be checked independently.
    Future<void> seedDanceWithEverything() async {
      await repos.tags.upsert(
        Tag(id: 't1', name: 'Easy'),
        at: t0,
      );
      await repos.choreographers.upsert(
        Choreographer(id: 'c1', name: 'Author'),
        at: t0,
      );
      await repos.publishedSources.upsert(
        PublishedSource(id: 's1', title: 'Book'),
        at: t0,
      );
      await repos.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f1',
          key: 'k',
          label: 'L',
          type: CustomFieldType.text,
        ),
        at: t0,
      );
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'D',
          figures: [],
          tagIds: ['t1'],
          authorIds: ['c1'],
          sourceCitations: [SourceCitation(sourceId: 's1')],
          customFields: [CustomFieldValue(fieldId: 'f1', value: 'x')],
          createdAt: t0,
          updatedAt: t0,
        ),
      );
    }

    test('a soft-deleted tag stops surfacing on its dances', () async {
      // Tags are the reachable case: TagRepository has no referential guard, so
      // a tag can be deleted while `dance_tags` rows still point at it. Hard
      // delete used to clear them by FK cascade; a tombstone fires no cascade.
      await seedDanceWithEverything();
      expect((await repos.dances.getById('d1'))!.tagIds, ['t1']);

      await repos.tags.delete('t1', at: t0.add(const Duration(minutes: 1)));

      expect(
        (await repos.dances.getById('d1'))!.tagIds,
        isEmpty,
        reason: 'a deleted tag must not still surface on the dance',
      );
      expect((await repos.dances.listAll()).single.tagIds, isEmpty);

      // The join row is deliberately still there, so a revived tag comes back
      // with its dances rather than silently losing every association.
      final joins = await db
          .customSelect('SELECT COUNT(*) AS n FROM dance_tags')
          .get();
      expect(
        joins.single.read<int>('n'),
        1,
        reason:
            'dance_tags must be kept, not cleared, so a revival restores it',
      );
    });

    test('a tag search stops matching once the tag is deleted', () async {
      await seedDanceWithEverything();
      expect(await repos.dances.search(TagFilter('t1')), hasLength(1));
      await repos.tags.delete('t1', at: t0.add(const Duration(minutes: 1)));
      expect(
        await repos.dances.search(TagFilter('t1')),
        isEmpty,
        reason: 'TagFilter must join through tags and drop the tombstone',
      );
    });

    test('reviving the tag under its OWN id brings its dances back', () async {
      await seedDanceWithEverything();
      await repos.tags.delete('t1', at: t0.add(const Duration(minutes: 1)));
      await repos.tags.upsert(
        Tag(id: 't1', name: 'Easy'),
        at: t0.add(const Duration(minutes: 2)),
      );
      expect((await repos.dances.getById('d1'))!.tagIds, ['t1']);
      expect(await repos.dances.search(TagFilter('t1')), hasLength(1));
    });

    test(
      'author, source and custom-field joins filter tombstones too',
      () async {
        // These three are referentially guarded, so the tombstone-with-live-join
        // state is not reachable through the repositories. Write it directly to
        // prove the filter is real rather than merely unreached — if a guard is
        // ever relaxed, the read stays correct.
        await seedDanceWithEverything();
        final stamp = unixSeconds(t0.add(const Duration(minutes: 1)));
        for (final (table, id) in const [
          ('choreographers', 'c1'),
          ('published_sources', 's1'),
          ('custom_field_defs', 'f1'),
        ]) {
          await db.customStatement(
            'UPDATE $table SET deleted_at = ? WHERE id = ?',
            [stamp, id],
          );
        }

        final dance = (await repos.dances.getById('d1'))!;
        expect(
          dance.authorIds,
          isEmpty,
          reason: 'dance_authors -> choreographers',
        );
        expect(
          dance.sourceCitations,
          isEmpty,
          reason: 'dance_sources -> published_sources',
        );
        expect(
          dance.customFields,
          isEmpty,
          reason: 'custom_field_values -> custom_field_defs',
        );
        expect(await repos.dances.search(AuthorFilter('c1')), isEmpty);
        expect(await repos.dances.search(SourceIdFilter('s1')), isEmpty);
        expect(await repos.dances.search(SourceFilter('Book')), isEmpty);
      },
    );

    test('a program cannot newly link to a tombstoned venue', () async {
      await repos.venues.upsert(
        Venue(id: 'v1', name: 'Hall'),
        at: t0,
      );
      await repos.venues.delete('v1', at: t0.add(const Duration(minutes: 1)));
      await expectLater(
        repos.programs.create(
          Program(
            id: 'p1',
            title: 'P',
            venueId: 'v1',
            createdAt: t0,
            updatedAt: t0,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('revival stamps existence_at', () {
    test('a NEW tag reusing a deleted name starts empty, as before v25', () async {
      // Adoption is not revival. The user is creating a new tag that happens to
      // want a name a tombstone still holds; before v25 the hard delete had
      // cascaded the join rows away and they got an empty tag. Keeping the old
      // associations would mean deleting a tag from every dance and then
      // re-creating it silently re-tagged all of them.
      await repos.tags.upsert(
        Tag(id: 't1', name: 'Easy'),
        at: t0,
      );
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'D',
          figures: [],
          tagIds: ['t1'],
          createdAt: t0,
          updatedAt: t0,
        ),
      );
      await repos.tags.delete('t1', at: t0.add(const Duration(minutes: 1)));

      final id = await repos.tags.upsert(
        Tag(id: 't2', name: 'Easy'),
        at: t0.add(const Duration(minutes: 2)),
      );
      expect((await repos.dances.getById('d1'))!.tagIds, isEmpty);
      expect(await repos.dances.search(TagFilter(id)), isEmpty);
      expect((await repos.tags.listAll()).single.name, 'Easy');
    });

    test(
      're-creating a tag under the same UNIQUE name works, and is visible',
      () async {
        // Without the tombstone clear this silently fails: drift emits an
        // untargeted ON CONFLICT DO UPDATE, so the new tag lands on the
        // tombstoned row, keeps its deleted_at, and never appears.
        await repos.tags.upsert(
          Tag(id: 't1', name: 'Easy'),
          at: t0,
        );
        await repos.tags.delete('t1', at: t0.add(const Duration(minutes: 1)));

        await repos.tags.upsert(
          Tag(id: 't2', name: 'Easy'),
          at: t0.add(const Duration(minutes: 2)),
        );
        final all = await repos.tags.listAll();
        expect(all, hasLength(1));
        expect(all.single.name, 'Easy');
      },
    );

    test('a RENAME onto a tombstoned name does not adopt it', () async {
      // A rename is a creation-shaped write carrying an existing id. Adopting
      // there writes the new name onto the *other* row and leaves the row being
      // renamed alone, so the user asks to rename "Hard" to "Easy" and gets two
      // tags instead — with the deleted one resurrected. Silently duplicating
      // is worse than failing, so this must raise UNIQUE, exactly as renaming
      // onto a *live* name always has.
      await repos.tags.upsert(
        Tag(id: 'T9', name: 'Easy'),
        at: t0,
      );
      await repos.tags.delete('T9', at: t0);
      await repos.tags.upsert(
        Tag(id: 'T1', name: 'Hard'),
        at: t0,
      );

      await expectLater(
        repos.tags.upsert(
          Tag(id: 'T1', name: 'Easy'),
          at: t0,
        ),
        throwsA(anything),
        reason: 'renaming onto a tombstoned name must fail, not adopt',
      );

      final live = await repos.tags.listAll();
      expect(
        [for (final t in live) '${t.id}/${t.name}'],
        ['T1/Hard'],
        reason:
            'the rename failed, so the collection is unchanged: no duplicate, '
            'and the tombstoned tag stays dead',
      );
    });

    test(
      'renaming onto a LIVE name fails the same way (unchanged by v25)',
      () async {
        // The control: this behaviour predates the migration, and the case above
        // must match it rather than inventing a third outcome.
        await repos.tags.upsert(
          Tag(id: 'T9', name: 'Easy'),
          at: t0,
        );
        await repos.tags.upsert(
          Tag(id: 'T1', name: 'Hard'),
          at: t0,
        );
        await expectLater(
          repos.tags.upsert(
            Tag(id: 'T1', name: 'Easy'),
            at: t0,
          ),
          throwsA(anything),
        );
      },
    );

    test(
      'creation still adopts, so the two cases stay distinguishable',
      () async {
        // Guards against "fixing" the rename case by disabling adoption outright.
        await repos.tags.upsert(
          Tag(id: 'T9', name: 'Easy'),
          at: t0,
        );
        await repos.tags.delete('T9', at: t0);
        final id = await repos.tags.upsert(
          Tag(id: 'T-new', name: 'Easy'),
          at: t0,
        );
        expect(id, 'T9', reason: 'a genuinely new id must still adopt');
        expect((await repos.tags.listAll()).single.name, 'Easy');
      },
    );

    test('a revival advances existence_at past the tombstone', () async {
      await repos.tags.upsert(
        Tag(id: 't1', name: 'Easy'),
        at: t0,
      );
      final deletedAt = t0.add(const Duration(minutes: 1));
      await repos.tags.delete('t1', at: deletedAt);
      final tombstone = await rawStamp('tags', 'existence_at', 'id', 't1');

      await repos.tags.upsert(
        Tag(id: 't1', name: 'Easy'),
        at: t0.add(const Duration(minutes: 2)),
      );
      final revived = await rawStamp('tags', 'existence_at', 'id', 't1');
      expect(
        revived,
        greaterThan(tombstone!),
        reason:
            'a revival that ties with the tombstone loses: equal existence_at '
            'resolves in favour of the tombstone',
      );
      expect(await rawStamp('tags', 'deleted_at', 'id', 't1'), isNull);
    });

    test('a revival wins even when the clock has not moved', () async {
      // The causal `+ 1 tick` is the whole point: delete and undo inside one
      // second is an ordinary user action, and a bare clock read would stamp
      // the revival equal to the tombstone.
      await repos.tags.upsert(
        Tag(id: 't1', name: 'Easy'),
        at: t0,
      );
      await repos.tags.delete('t1', at: t0);
      final tombstone = await rawStamp('tags', 'existence_at', 'id', 't1');

      await repos.tags.upsert(
        Tag(id: 't1', name: 'Easy'),
        at: t0,
      );
      expect(
        await rawStamp('tags', 'existence_at', 'id', 't1'),
        greaterThan(tombstone!),
      );
    });

    test('an ordinary edit does NOT move existence_at', () async {
      // Invariant: only an existence transition may move it. Advancing it on
      // every save would make each edit read as a deletion-or-revival to a
      // peer — the exact conflation the third column exists to prevent.
      await repos.tags.upsert(
        Tag(id: 't1', name: 'Easy'),
        at: t0,
      );
      final created = await rawStamp('tags', 'existence_at', 'id', 't1');

      await repos.tags.upsert(
        Tag(id: 't1', name: 'Renamed'),
        at: t0.add(const Duration(hours: 1)),
      );
      expect(await rawStamp('tags', 'existence_at', 'id', 't1'), created);
      // ...while updated_at, which answers a different question, does move.
      expect(
        await rawStamp('tags', 'updated_at', 'id', 't1'),
        unixSeconds(t0.add(const Duration(hours: 1))),
      );
    });

    test('creation seeds existence_at from the plain clock', () async {
      await repos.tags.upsert(
        Tag(id: 't1', name: 'Easy'),
        at: t0,
      );
      expect(
        await rawStamp('tags', 'existence_at', 'id', 't1'),
        unixSeconds(t0),
      );
    });

    test('re-setting a removed setting makes it visible again', () async {
      await repos.settings.set('pref', 'a', at: t0);
      await repos.settings.remove(
        'pref',
        at: t0.add(const Duration(minutes: 1)),
      );
      await repos.settings.set(
        'pref',
        'b',
        at: t0.add(const Duration(minutes: 2)),
      );
      expect(await repos.settings.get('pref'), 'b');
      expect(await repos.settings.contains('pref'), isTrue);
    });
  });

  group('creation seeds existence_at', () {
    test('a new dance carries a stamp, seeded from created_at', () async {
      // Not from updated_at: seeding from the content stamp would make an
      // imported record's edit history read as existence transitions.
      final created = t0.subtract(const Duration(days: 30));
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'D',
          figures: [],
          createdAt: created,
          updatedAt: t0,
        ),
      );
      expect(
        await rawStamp('dances', 'existence_at', 'id', 'd1'),
        unixSeconds(created),
      );
    });

    test('a restored tombstoned dance is seeded from its deleted_at', () async {
      // The archive-restore shape: the record already existed elsewhere, and
      // its existence last changed when it was deleted.
      final created = t0.subtract(const Duration(days: 30));
      final deleted = t0.subtract(const Duration(days: 2));
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'D',
          figures: [],
          createdAt: created,
          updatedAt: t0,
          deletedAt: deleted,
        ),
      );
      expect(
        await rawStamp('dances', 'existence_at', 'id', 'd1'),
        unixSeconds(deleted),
      );
    });

    test('a later edit does not re-seed or move the stamp', () async {
      final created = t0.subtract(const Duration(days: 30));
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'D',
          figures: [],
          createdAt: created,
          updatedAt: t0,
        ),
      );
      await repos.dances.update(
        Dance(
          id: 'd1',
          title: 'Renamed',
          figures: [],
          createdAt: created,
          updatedAt: t0.add(const Duration(days: 1)),
        ),
      );
      expect(
        await rawStamp('dances', 'existence_at', 'id', 'd1'),
        unixSeconds(created),
        reason: 'an ordinary edit is not an existence transition',
      );
    });

    test('a new program is seeded too', () async {
      final created = t0.subtract(const Duration(days: 5));
      await repos.programs.create(
        Program(id: 'p1', title: 'P', createdAt: created, updatedAt: t0),
      );
      expect(
        await rawStamp('programs', 'existence_at', 'id', 'p1'),
        unixSeconds(created),
      );
    });
  });

  group('the Undo-snackbar case: delete and restore in the same second', () {
    // THE defect the one-second tick exists to fix, and the reason the
    // specification's literal `+ 1ms` could not be implemented here. Deleting a
    // dance and hitting Undo is a single wall-clock second's worth of
    // interaction, so this is an ordinary path rather than an edge case. If the
    // restore's `existence_at` merely *ties* with the tombstone's, §6.4
    // resolves the tie in favour of the tombstone and the undo silently loses
    // once sync exists.
    //
    // Both timestamps below are literally the same instant, so nothing about
    // this test depends on the clock advancing between the two calls.
    test(
      'a dance restored in the delete second strictly outranks the tombstone',
      () async {
        await repos.dances.create(
          Dance(
            id: 'd1',
            title: 'D',
            figures: [],
            createdAt: t0,
            updatedAt: t0,
          ),
        );
        await repos.dances.softDelete('d1', at: t0);
        final tombstone = await rawStamp('dances', 'existence_at', 'id', 'd1');

        await repos.dances.restore('d1', at: t0);
        final restored = await rawStamp('dances', 'existence_at', 'id', 'd1');

        expect(
          restored,
          greaterThan(tombstone!),
          reason:
              'the restore must strictly outrank the tombstone it supersedes; a '
              'tie resolves to the tombstone and the undo loses',
        );
        expect(await repos.dances.getById('d1'), isNotNull);
        expect(await rawStamp('dances', 'deleted_at', 'id', 'd1'), isNull);
      },
    );

    test(
      'a program restored in the delete second strictly outranks it too',
      () async {
        await repos.programs.create(
          Program(id: 'p1', title: 'P', createdAt: t0, updatedAt: t0),
        );
        await repos.programs.softDelete('p1', at: t0);
        final tombstone = await rawStamp(
          'programs',
          'existence_at',
          'id',
          'p1',
        );

        await repos.programs.restore('p1', at: t0);
        expect(
          await rawStamp('programs', 'existence_at', 'id', 'p1'),
          greaterThan(tombstone!),
        );
        expect(await repos.programs.getById('p1'), isNotNull);
      },
    );

    test(
      'and the symmetric case: re-deleting in that second outranks the restore',
      () async {
        // The invariant is symmetric — a deletion must outrank the revival it
        // supersedes just as a revival outranks the deletion. Delete, undo, then
        // change your mind again, all inside one second.
        await repos.dances.create(
          Dance(
            id: 'd1',
            title: 'D',
            figures: [],
            createdAt: t0,
            updatedAt: t0,
          ),
        );
        await repos.dances.softDelete('d1', at: t0);
        await repos.dances.restore('d1', at: t0);
        final restored = await rawStamp('dances', 'existence_at', 'id', 'd1');

        await repos.dances.softDelete('d1', at: t0);
        expect(
          await rawStamp('dances', 'existence_at', 'id', 'd1'),
          greaterThan(restored!),
        );
        expect(await repos.dances.getById('d1'), isNull);
      },
    );

    test(
      'every transition in a same-second burst strictly increases',
      () async {
        // Generalises the two above: N transitions inside one wall-clock second
        // must produce N strictly increasing stamps, because the clock
        // contributes nothing and only the causal bump orders them.
        await repos.dances.create(
          Dance(
            id: 'd1',
            title: 'D',
            figures: [],
            createdAt: t0,
            updatedAt: t0,
          ),
        );
        final stamps = <int>[];
        for (var i = 0; i < 6; i++) {
          if (i.isEven) {
            await repos.dances.softDelete('d1', at: t0);
          } else {
            await repos.dances.restore('d1', at: t0);
          }
          stamps.add((await rawStamp('dances', 'existence_at', 'id', 'd1'))!);
        }
        for (var i = 1; i < stamps.length; i++) {
          expect(
            stamps[i],
            greaterThan(stamps[i - 1]),
            reason: 'transition $i must outrank transition ${i - 1}: $stamps',
          );
        }
      },
    );
  });

  group('dance and program transitions stamp existence_at', () {
    test('softDelete then restore advances existence_at each time', () async {
      await repos.dances.create(
        Dance(id: 'd1', title: 'D', figures: [], createdAt: t0, updatedAt: t0),
      );
      final seeded = await rawStamp('dances', 'existence_at', 'id', 'd1');
      await repos.dances.softDelete('d1', at: t0);
      final deleted = await rawStamp('dances', 'existence_at', 'id', 'd1');
      expect(
        deleted,
        greaterThan(seeded!),
        reason:
            'creation seeded the stamp at t0, so a delete at t0 must still '
            'supersede it rather than tie',
      );

      await repos.dances.restore('d1', at: t0);
      final restored = await rawStamp('dances', 'existence_at', 'id', 'd1');
      expect(
        restored,
        greaterThan(deleted!),
        reason: 'a restore in the same second must still outrank the tombstone',
      );
      expect(await rawStamp('dances', 'deleted_at', 'id', 'd1'), isNull);
      expect(await repos.dances.getById('d1'), isNotNull);
    });

    test('program softDelete/restore behaves the same way', () async {
      await repos.programs.create(
        Program(id: 'p1', title: 'P', createdAt: t0, updatedAt: t0),
      );
      await repos.programs.softDelete('p1', at: t0);
      final deleted = await rawStamp('programs', 'existence_at', 'id', 'p1');
      await repos.programs.restore('p1', at: t0);
      expect(
        await rawStamp('programs', 'existence_at', 'id', 'p1'),
        greaterThan(deleted!),
      );
      expect(await repos.programs.getById('p1'), isNotNull);
    });
  });
}
