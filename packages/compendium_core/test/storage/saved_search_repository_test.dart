import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  late CompendiumDatabase db;
  late SettingsRepository settings;
  late SavedSearchRepository repo;
  final today = DateTime.utc(2026, 11, 22);

  setUp(() {
    db = openTestDatabase();
    settings = SettingsRepository(db);
    repo = SavedSearchRepository(settings);
  });

  tearDown(() => db.close());

  SavedSearchSpec specFor(String text) => SavedSearchSpec.fromPanelState(
    CollectionPanelState(text: text),
    today: today,
  ).value!;

  Future<List<String>> names() async => [
    for (final s in await repo.list()) s.search?.name ?? '<unreadable>',
  ];

  test('each saved search is its own settings value', () async {
    final a = await repo.create(name: 'Easy mixers', spec: specFor('a'));
    final b = await repo.create(name: 'Becket', spec: specFor('b'));
    expect(a.id, isNot(b.id));
    expect(await settings.keysWithPrefix(savedSearchKeyPrefix), hasLength(2));
    expect(await settings.contains('saved_search:${a.id}'), isTrue);
    expect(await settings.contains('saved_search:${b.id}'), isTrue);
    // Listed by name, whatever order they were added in.
    expect(await names(), ['Becket', 'Easy mixers']);
    expect((await repo.get(a.id))!.name, 'Easy mixers');
    expect(await repo.get('missing'), isNull);
  });

  test('a stored value is exactly what the codec writes', () async {
    final s = await repo.create(
      name: '  Spaced  ',
      spec: specFor('petronella'),
    );
    expect(s.name, 'Spaced', reason: 'the name is trimmed');
    final stored = await settings.get('saved_search:${s.id}');
    expect(stored, s.toJson());
    expect(SavedSearch.decode(s.id, stored).value!.name, 'Spaced');
  });

  test('save updates in place and never changes the id', () async {
    final s = await repo.create(name: 'Old', spec: specFor('a'));
    await repo.save(SavedSearch(id: s.id, name: 'New', spec: specFor('b')));
    expect(await names(), ['New']);
    expect((await repo.get(s.id))!.spec.toJson()['text'], 'b');
  });

  test('save refuses what the format cannot read, writing nothing', () async {
    final s = await repo.create(name: 'Good', spec: specFor('a'));
    expect(
      () => repo.save(SavedSearch(id: s.id, name: '   ', spec: specFor('a'))),
      throwsArgumentError,
    );
    expect((await repo.get(s.id))!.name, 'Good');
  });

  group('a value is checked as the store will keep it', () {
    test('a name of only invisible characters is refused, not stored '
        'unreadable', () async {
      // U+200B survives trim() but not the store's normalization, which would
      // leave an empty name that the codec cannot read.
      await expectLater(
        repo.create(name: '\u200B\u200B', spec: specFor('a')),
        throwsArgumentError,
      );
      expect(await repo.list(), isEmpty);
      expect(
        SavedSearch.decode(
          'x',
          SavedSearch(id: 'x', name: '\u200B', spec: specFor('a')).toJson(),
        ).isOk,
        isTrue,
        reason:
            'readable as written, which is why the check must follow '
            'normalization',
      );
    });

    test(
      'keys that differ only by an invisible character are refused',
      () async {
        final panel = CollectionPanelState(text: 'a');
        panel.byPhrase.match['A1'] = ['swing'];
        panel.byPhrase.match['A1\u200B'] = ['star'];
        final spec = SavedSearchSpec.fromPanelState(panel, today: today).value!;
        await expectLater(
          repo.create(name: 'Collides', spec: spec),
          throwsArgumentError,
        );
        expect(await repo.list(), isEmpty);
      },
    );

    test('an empty id is refused', () async {
      await expectLater(
        repo.save(SavedSearch(id: ' ', name: 'No id', spec: specFor('a'))),
        throwsArgumentError,
      );
    });
  });

  group('delete', () {
    test('tombstones the key, and a later save of the same id revives it '
        '(Undo)', () async {
      final s = await repo.create(name: 'Gone', spec: specFor('a'));
      await repo.delete(s.id);
      expect(await names(), isEmpty);
      expect(await repo.get(s.id), isNull);
      // A tombstone, not an erased row: a peer has to learn of the deletion.
      final rows = await db.select(db.settings).get();
      final row = rows.singleWhere((r) => r.key == 'saved_search:${s.id}');
      expect(row.deletedAt, isNotNull);

      await repo.save(s);
      expect(await names(), ['Gone']);
      final revived = (await db.select(db.settings).get()).singleWhere(
        (r) => r.key == 'saved_search:${s.id}',
      );
      expect(revived.deletedAt, isNull);
    });

    test('is allowed when nothing is registered', () async {
      final s = await repo.create(name: 'Free', spec: specFor('a'));
      await repo.delete(s.id);
      expect(await names(), isEmpty);
    });

    test('is refused while a dependent uses it, listing each user, and '
        'writes nothing', () async {
      final used = await repo.create(name: 'Used', spec: specFor('a'));
      final free = await repo.create(name: 'Free', spec: specFor('b'));
      repo.usage
        ..register(
          'event rules',
          (id) async => id == used.id
              ? [
                  const SavedSearchUse(
                    kind: 'event rule',
                    label: 'Contra night',
                  ),
                ]
              : [],
        )
        ..register(
          'slot rules',
          (id) async => id == used.id
              ? [const SavedSearchUse(kind: 'slot rule', label: 'Slot 3')]
              : [],
        );

      await expectLater(
        repo.delete(used.id),
        throwsA(
          isA<SavedSearchInUse>().having((e) => e.id, 'id', used.id).having(
            (e) => [for (final u in e.uses) '${u.kind}: ${u.label}'],
            'uses',
            ['event rule: Contra night', 'slot rule: Slot 3'],
          ),
        ),
      );
      expect(await names(), ['Free', 'Used'], reason: 'nothing was written');

      // An unused one still deletes, and so does the used one once the
      // dependents let go.
      await repo.delete(free.id);
      repo.usage.unregister('event rules');
      repo.usage.unregister('slot rules');
      await repo.delete(used.id);
      expect(await names(), isEmpty);
    });

    test('a rule cannot start using it between the use check and the '
        'removal (#2529)', () async {
      final repos = CompendiumRepositories(db, contraTaxonomy);
      final s = await repos.savedSearches.create(
        name: 'Raced',
        spec: specFor('a'),
      );
      // Another writer (a sync pass, the rule editor) that adds a rule only
      // while the search is live, started in the window after the event
      // rules' lookup has answered "no uses". It runs outside the delete's
      // zone, as a real one would.
      Future<void>? racer;
      repos.savedSearches.usage.register('racer', (id) async {
        racer ??= Zone.root.run(
          () => db.transaction(() async {
            if (await repos.savedSearches.get(id) == null) return;
            await repos.eventRules.create(
              savedSearchId: id,
              quantifier: EventRuleQuantifier.none,
              scope: EventRuleScope.wholeProgram,
            );
          }),
        );
        return const [];
      });

      var deleted = true;
      try {
        await repos.savedSearches.delete(s.id);
      } on SavedSearchInUse {
        deleted = false;
      }
      await racer;

      expect(racer, isNotNull, reason: 'the racer ran');
      final users = await repos.eventRules.usesOfSavedSearch(s.id);
      expect(
        deleted && users.isNotEmpty,
        isFalse,
        reason:
            'deleted: $deleted, live rules using it: ${users.length}; the '
            'delete and the rule must not both succeed',
      );
    });
  });

  group('what is stored but cannot be read', () {
    test(
      'is listed as needing attention, last, never skipped or thrown on',
      () async {
        final ok = await repo.create(name: 'Fine', spec: specFor('a'));
        await settings.set('saved_search:bad1', {'v': 2, 'name': 'Newer'});
        await settings.set('saved_search:bad2', 'not an object');
        final listed = await repo.list();
        expect(listed.map((s) => s.savedSearchId), [ok.id, 'bad1', 'bad2']);
        expect(listed.first.search, isNotNull);
        expect(listed[1].search, isNull);
        expect(listed[1].problem, isNotEmpty);
        expect(await repo.get('bad1'), isNull);
      },
    );

    test(
      'a stray key with no id is listed as unreadable, not skipped',
      () async {
        await settings.set('saved_search:', {'v': 1});
        final listed = await repo.list();
        expect(listed, hasLength(1));
        expect(listed.single.search, isNull);
        expect(listed.single.savedSearchId, '');
      },
    );

    test('an unreadable one can still be deleted', () async {
      await settings.set('saved_search:bad', {'v': 2});
      await repo.delete('bad');
      expect(await repo.list(), isEmpty);
    });
  });

  group('the count limit', () {
    test('create refuses the 129th this device would add', () async {
      for (var i = 0; i < savedSearchMaxCount; i++) {
        await settings.set(
          'saved_search:s$i',
          SavedSearch(id: 's$i', name: 'n$i', spec: specFor('a')).toJson(),
        );
      }
      await expectLater(
        repo.create(name: 'One too many', spec: specFor('a')),
        throwsA(isA<SavedSearchLimitReached>()),
      );
      // Reading is never limited: a peer may hold more.
      await settings.set(
        'saved_search:extra',
        SavedSearch(id: 'extra', name: 'extra', spec: specFor('a')).toJson(),
      );
      expect(await repo.list(), hasLength(savedSearchMaxCount + 1));
    });
  });

  test('Repositories exposes the repository over its own settings', () async {
    final repos = CompendiumRepositories(db, contraTaxonomy);
    final s = await repos.savedSearches.create(
      name: 'Via repositories',
      spec: specFor('a'),
    );
    expect(await repos.settings.contains('saved_search:${s.id}'), isTrue);
    expect(identical(repos.savedSearches, repos.savedSearches), isTrue);
  });
}
