import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

/// Event rules in storage (#2340): the repository, the saved-search delete
/// guard they register, a program's applied rules, and the one query that
/// finds a program's dances a rule's search matches.
void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repos;
  final t0 = DateTime.utc(2026, 1, 2, 3, 4, 5);

  setUp(() {
    db = openTestDatabase();
    repos = CompendiumRepositories(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  SavedSearchSpec specFor(String text) => SavedSearchSpec.fromPanelState(
    CollectionPanelState(text: text),
    today: DateTime.utc(2026, 1, 1),
  ).value!;

  Future<EventRule> addRule(String savedSearchId, {String? name}) =>
      repos.eventRules.create(
        savedSearchId: savedSearchId,
        quantifier: EventRuleQuantifier.atMost,
        count: 1,
        scope: EventRuleScope.wholeProgram,
        name: name,
      );

  group('the repository', () {
    test('adds, edits, lists in order, deletes and restores', () async {
      final a = await addRule('s1', name: 'One petronella');
      final b = await repos.eventRules.create(
        savedSearchId: 's2',
        quantifier: EventRuleQuantifier.none,
        count: 5,
        scope: EventRuleScope.afterFirstBreak,
      );
      expect(b.count, 0, reason: '"none" keeps no count');
      expect(b.position, greaterThan(a.position));
      expect(
        [for (final r in await repos.eventRules.listAll()) r.id],
        [a.id, b.id],
      );

      await repos.eventRules.save(
        a.copyWith(count: 2, scope: EventRuleScope.neighbouring),
      );
      final edited = await repos.eventRules.get(a.id);
      expect(edited!.count, 2);
      expect(edited.scope, EventRuleScope.neighbouring);
      expect(edited.name, 'One petronella');

      await repos.eventRules.reorder([b.id, a.id]);
      expect(
        [for (final r in await repos.eventRules.listAll()) r.id],
        [b.id, a.id],
      );

      await repos.eventRules.delete(a.id);
      expect(await repos.eventRules.get(a.id), isNull);
      expect(
        (await repos.eventRules.listAll(includeDeleted: true)).length,
        2,
        reason: 'a delete is a tombstone that syncs',
      );
      await repos.eventRules.restore(a.id);
      expect((await repos.eventRules.get(a.id))!.count, 2);
    });

    test('refuses a rule it could not check', () async {
      expect(
        () => repos.eventRules.save(
          const EventRule(
            id: 'x',
            savedSearchId: 's',
            quantifierName: 'exactly',
            count: 1,
            scopeName: 'wholeProgram',
          ),
        ),
        throwsA(isA<EventRuleInvalid>()),
      );
      expect(
        () => repos.eventRules.create(
          savedSearchId: '',
          quantifier: EventRuleQuantifier.atMost,
          scope: EventRuleScope.wholeProgram,
        ),
        throwsA(isA<EventRuleInvalid>()),
      );
      expect(await repos.eventRules.listAll(), isEmpty);
    });

    test('a rule a newer build wrote reads as one it cannot check', () async {
      const newer = EventRule(
        id: 'n',
        savedSearchId: 's',
        quantifierName: 'exactly',
        count: 1,
        scopeName: 'dancesNtoM',
      );
      await repos.eventRules.writeFromSync(newer);
      final read = await repos.eventRules.get('n');
      expect(read, newer, reason: 'kept as stored, to publish it back');
      expect(read!.isReadable, isFalse);
    });
  });

  group('a saved search a rule uses', () {
    test('cannot be deleted; the refusal names each rule, and once no rule '
        'uses it the delete goes through', () async {
      final search = await repos.savedSearches.create(
        name: 'Petronella',
        spec: specFor('petronella'),
      );
      final named = await addRule(search.id, name: 'One petronella');
      final unnamed = await addRule(search.id);
      await addRule('another-search');

      await expectLater(
        repos.savedSearches.delete(search.id),
        throwsA(
          isA<SavedSearchInUse>().having(
            (e) => [for (final u in e.uses) (u.kind, u.id, u.label)],
            'uses',
            [
              (eventRuleUseKind, named.id, 'One petronella'),
              (eventRuleUseKind, unnamed.id, ''),
            ],
          ),
        ),
      );
      expect(await repos.savedSearches.get(search.id), isNotNull);

      // One rule changes to another search, the other is deleted (a rule in
      // the trash does not count).
      await repos.eventRules.save(named.copyWith(savedSearchId: 'other'));
      await repos.eventRules.delete(unnamed.id);
      await repos.savedSearches.delete(search.id);
      expect(await repos.savedSearches.get(search.id), isNull);
    });
  });

  group("a program's applied rules", () {
    Program program(String id, {List<String> rules = const []}) => Program(
      id: id,
      title: 'Saturday',
      slots: [ProgramSlot(id: '$id-s', position: 0, text: 'Waltz')],
      eventRuleIds: rules,
      createdAt: t0,
      updatedAt: t0,
    );

    test('round-trip through storage, in order', () async {
      await repos.programs.create(program('p', rules: ['r2', 'r1', 'r2']));
      final read = await repos.programs.getById('p');
      expect(read!.eventRuleIds, ['r2', 'r1']);
    });

    test('the Rules picker sets them on a stored program, stamping it, and '
        'leaves the rest of the program as it was', () async {
      await repos.programs.create(program('p'));
      final before = (await repos.programs.getById('p'))!;
      expect(
        await repos.programs.setEventRuleIds('p', ['r1', 'r2', 'r1']),
        isTrue,
      );
      final after = (await repos.programs.getById('p'))!;
      expect(after.eventRuleIds, ['r1', 'r2']);
      expect(after.updatedAt.isAfter(before.updatedAt), isTrue);
      expect(after.title, before.title);
      expect(after.slots, before.slots);
      // The same list again writes nothing; a missing program is refused.
      expect(await repos.programs.setEventRuleIds('p', ['r1', 'r2']), isFalse);
      expect(await repos.programs.setEventRuleIds('nope', ['r1']), isFalse);
    });

    test('the Rules picker ticks a rule on the list stored now, keeping one '
        'another writer applied since', () async {
      await repos.programs.create(program('p'));
      await repos.programs.setEventRuleIds('p', ['x']);
      final after = await repos.programs.updateEventRuleIds(
        'p',
        (stored) => toggleEventRuleId(stored, 'y', on: true, deleted: {}),
      );
      expect(after, ['x', 'y']);
      expect((await repos.programs.getById('p'))!.eventRuleIds, ['x', 'y']);
      // A refused tick writes nothing and answers the stored list.
      final stamp = (await repos.programs.getById('p'))!.updatedAt;
      expect(await repos.programs.updateEventRuleIds('p', (_) => null), [
        'x',
        'y',
      ]);
      expect((await repos.programs.getById('p'))!.updatedAt, stamp);
      expect(await repos.programs.updateEventRuleIds('nope', (s) => s), isNull);
    });

    test('a tick counts a rule not on this device yet toward the most, and '
        "makes room only from a deleted rule's id", () {
      final live = [for (var i = 0; i < maxProgramEventRules - 2; i++) 'r$i'];
      final full = ['not-here-yet', 'gone', ...live];
      expect(toggleEventRuleId(full, 'new', on: true, deleted: {'gone'}), [
        'not-here-yet',
        ...live,
        'new',
      ]);
      // Only the rule not here yet and the live ones left: full.
      expect(
        toggleEventRuleId(
          ['not-here-yet', ...live, 'new'],
          'past',
          on: true,
          deleted: {'gone'},
        ),
        isNull,
      );
      // Unticking, and ticking one already applied.
      expect(toggleEventRuleId(['a', 'b'], 'a', on: false, deleted: {}), ['b']);
      expect(toggleEventRuleId(['a'], 'a', on: true, deleted: {}), ['a']);
    });

    test('a save that keeps the stored rules keeps those set since its copy '
        'was read', () async {
      await repos.programs.create(program('p'));
      final copy = (await repos.programs.getById('p'))!;
      await repos.programs.setEventRuleIds('p', ['r1']);
      final saved = await repos.programs.updateAndReadBack(
        copy.copyWith(title: 'Sunday'),
        keepStoredEventRuleIds: true,
      );
      expect(saved.title, 'Sunday');
      expect(saved.eventRuleIds, ['r1']);
      // Without it, the copy's rules are written, as for any other field.
      final plain = await repos.programs.updateAndReadBack(copy);
      expect(plain.eventRuleIds, isEmpty);
    });

    test('creating a program applies none', () async {
      await addRule('s');
      await repos.programs.create(program('p'));
      expect((await repos.programs.getById('p'))!.eventRuleIds, isEmpty);
    });

    test('duplicating a program does not copy them', () async {
      final rule = await addRule('s');
      await repos.programs.create(program('p', rules: [rule.id]));
      var n = 0;
      final copy = await repos.programs.duplicate(
        id: 'p',
        newId: 'copy',
        newSlotId: () => 'copy-s${n++}',
        now: t0,
      );
      expect(copy.eventRuleIds, isEmpty);
      expect((await repos.programs.getById('copy'))!.eventRuleIds, isEmpty);
    });

    test('importing a shared program applies none', () {
      final archive = CompendiumArchive(
        exportedAt: t0,
        programs: [
          program('p', rules: ['r1']),
        ],
      );
      final result = buildArchivePrograms(
        archive,
        danceIdByOriginalId: const {},
        newId: () => 'imported',
        now: t0,
      );
      expect(result.programs.single.eventRuleIds, isEmpty);
    });
  });

  group('the dances a rule matches', () {
    Dance dance(String id, String title) =>
        Dance(id: id, title: title, figures: [], createdAt: t0, updatedAt: t0);

    test('include a dance in Recently deleted, among the ids asked', () async {
      await repos.dances.create(dance('d1', 'Petronella'));
      await repos.dances.create(dance('d2', 'Petronella Again'));
      await repos.dances.create(dance('d3', 'Hull\'s Victory'));
      await repos.dances.create(dance('d4', 'Petronella Elsewhere'));
      await repos.dances.softDelete('d2', at: t0);

      final matched = await repos.dances.matchingAmong(
        const FullTextFilter('petronella'),
        ['d1', 'd2', 'd3'],
      );
      expect(matched, {'d1', 'd2'});
    });
  });
}
