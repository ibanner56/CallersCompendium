import 'dart:convert';

import 'package:compendium_app/src/data/backup_document.dart';
import 'package:compendium_app/src/data/backup_service.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// The caller's event rules in a backup (#2340): `app.eventRules`, its
/// conditional v3 envelope, the rules a program applies carried with the
/// program, and a restore that leaves the rules alone when the file does not
/// describe them.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  final created = DateTime.utc(2026, 10, 14, 9);

  Future<(CompendiumRepositories, EventRule)> seeded() async {
    final repos = openTestRepositories();
    final rule = await repos.eventRules.create(
      savedSearchId: 'search-1',
      quantifier: EventRuleQuantifier.atMost,
      count: 1,
      scope: EventRuleScope.neighbouring,
      nickname: 'No two Beckets',
    );
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Saturday',
        eventRuleIds: [rule.id],
        createdAt: created,
        updatedAt: created,
      ),
    );
    return (repos, rule);
  }

  String backupWith(Object? rules) => jsonEncode({
    'backupVersion': 3,
    'createdAt': '2026-10-15T00:00:00.000Z',
    'core': {'dances': <Object?>[]},
    'app': {'eventRules': rules},
  });

  Map<String, Object?> ruleJson(String id) => {
    'id': id,
    'savedSearchId': 's',
    'quantifier': 'none',
    'count': 0,
    'scope': 'wholeProgram',
    'position': 0,
  };

  test('rules and the rules a program applies round-trip through a replace '
      'restore', () async {
    final (source, rule) = await seeded();
    final json = await BackupService(source).exportToJson();

    final target = openTestRepositories();
    final outcome = await BackupService(target).restoreFromJson(json);

    expect(outcome.applied, isTrue);
    expect(await target.eventRules.listAll(), [rule]);
    expect((await target.programs.getById('p1'))!.eventRuleIds, [rule.id]);
  });

  test('a backup that cuts a deleted rule from a program keeps the other '
      'rules\' nicknames and order (#2341)', () async {
    final (source, first) = await seeded();
    final second = await source.eventRules.create(
      savedSearchId: 'search-2',
      quantifier: EventRuleQuantifier.atLeast,
      count: 2,
      scope: EventRuleScope.wholeProgram,
      nickname: 'Two contras',
    );
    final gone = await source.eventRules.create(
      savedSearchId: 'search-3',
      quantifier: EventRuleQuantifier.none,
      scope: EventRuleScope.wholeProgram,
    );
    await source.eventRules.reorder([second.id, first.id, gone.id]);
    await source.programs.setEventRuleIds('p1', [first.id, gone.id, second.id]);
    await source.eventRules.delete(gone.id);
    final kept = await source.eventRules.listAll();
    expect([for (final r in kept) r.id], [second.id, first.id]);

    final json = await BackupService(source).exportToJson();
    final target = openTestRepositories();
    await BackupService(target).restoreFromJson(json);

    expect((await target.programs.getById('p1'))!.eventRuleIds, [
      first.id,
      second.id,
    ], reason: 'the deleted rule is cut from the program');
    final restored = await target.eventRules.listAll();
    expect([for (final r in restored) r.id], [second.id, first.id]);
    expect(
      [for (final r in restored) r.nickname],
      ['Two contras', 'No two Beckets'],
    );
    expect(
      [for (final r in restored) r.position],
      [for (final r in kept) r.position],
    );
  });

  test('a rule a newer build wrote comes back as it was', () async {
    final repos = openTestRepositories();
    const future = EventRule(
      id: 'r-future',
      savedSearchId: 's',
      quantifierName: 'exactly',
      count: 2,
      scopeName: 'lastHour',
    );
    await repos.eventRules.writeFromSync(future);
    final json = await BackupService(repos).exportToJson();
    final target = openTestRepositories();
    await BackupService(target).restoreFromJson(json);
    expect(await target.eventRules.get('r-future'), future);
  });

  group('the envelope version', () {
    test('a backup without rules has no section and keeps v1', () async {
      final json = backupToJson(
        await BackupService(openTestRepositories()).buildDocument(),
      );
      expect(json['backupVersion'], backupSchemaVersionBase);
      expect((json['app']! as Map).containsKey('eventRules'), isFalse);
    });

    test('a backup with a rule is written as v3', () async {
      final (repos, _) = await seeded();
      final json = backupToJson(await BackupService(repos).buildDocument());
      expect(json['backupVersion'], backupSchemaVersionEventRules);
      expect((json['app']! as Map)['eventRules'], hasLength(1));
    });

    test('a deleted rule is not carried', () async {
      final (repos, rule) = await seeded();
      await repos.eventRules.delete(rule.id);
      expect((await BackupService(repos).buildDocument()).eventRules, isEmpty);
    });
  });

  group('restore', () {
    test('a backup made before event rules leaves live rules alone', () async {
      final (repos, rule) = await seeded();
      await BackupService(repos).restoreFromJson(
        jsonEncode({
          'backupVersion': 2,
          'createdAt': '2026-10-15T00:00:00.000Z',
          'core': {'dances': <Object?>[]},
          'app': {'settings': <String, Object?>{}},
        }),
      );
      expect(await repos.eventRules.listAll(), [rule]);
    });

    test(
      'a section replaces the rules, deleting softly those it lacks',
      () async {
        final (repos, rule) = await seeded();
        await BackupService(
          repos,
        ).restoreFromJson(backupWith([ruleJson('r2')]));
        expect(
          [for (final r in await repos.eventRules.listAll()) r.id],
          ['r2'],
        );
        final all = await repos.eventRules.listAll(includeDeleted: true);
        expect(all.map((r) => r.id), containsAll([rule.id, 'r2']));
      },
    );

    test('a rule that cannot be read keeps every live rule', () async {
      final (repos, rule) = await seeded();
      final outcome = await BackupService(repos).restoreFromJson(
        backupWith([
          ruleJson('r2'),
          {'id': 'bad'},
        ]),
      );
      expect(outcome.errors, isNotEmpty);
      expect([
        for (final r in await repos.eventRules.listAll()) r.id,
      ], unorderedEquals([rule.id, 'r2']));
    });

    test('a merge restore adds and deletes nothing', () async {
      final (repos, rule) = await seeded();
      await BackupService(
        repos,
      ).restoreFromJson(backupWith([ruleJson('r2')]), mode: RestoreMode.merge);
      expect([
        for (final r in await repos.eventRules.listAll()) r.id,
      ], unorderedEquals([rule.id, 'r2']));
    });

    test('a rule the restore skips stays on the programs that apply it, as '
        'a rule not on this device (#2529)', () async {
      final (source, kept) = await seeded();
      final payload = backupToJson(await BackupService(source).buildDocument());
      final program =
          ((payload['core']! as Map)['programs']! as List).single as Map;
      program['eventRuleIds'] = [kept.id, 'r-bad'];
      // Decodes, but the repository refuses it: the count is over the most.
      (payload['app']! as Map)['eventRules'] = [
        ...((payload['app']! as Map)['eventRules']! as List),
        {...ruleJson('r-bad'), 'count': maxEventRuleCount + 1},
      ];

      final target = openTestRepositories();
      final outcome = await BackupService(
        target,
      ).restoreFromJson(jsonEncode(payload));

      expect(outcome.applied, isTrue);
      expect(
        [
          for (final e in outcome.errors)
            if (e.entityType == 'eventRule') e.entityId,
        ],
        ['r-bad'],
        reason: 'the skip is reported',
      );
      expect(await target.eventRules.get('r-bad'), isNull);
      // Kept, not dropped: the id may name a rule a peer holds (a newer
      // build's bound), which sync can still deliver, and the Rules list
      // offers Remove for it.
      expect((await target.programs.getById('p1'))!.eventRuleIds, [
        kept.id,
        'r-bad',
      ]);
    });

    test('a merge restore keeps a program to the most rules (#2529)', () async {
      final (source, rule) = await seeded();
      final payload = backupToJson(await BackupService(source).buildDocument());
      final listed = [for (var i = 0; i < maxProgramEventRules + 6; i++) 'b$i'];
      (((payload['core']! as Map)['programs']! as List).single
              as Map)['eventRuleIds'] =
          listed;

      // The live program applies a rule the backup's copy does not.
      final target = openTestRepositories();
      await BackupService(target).restoreFromJson(
        encodeBackup(await BackupService(source).buildDocument()),
      );
      expect((await target.programs.getById('p1'))!.eventRuleIds, [rule.id]);

      final outcome = await BackupService(
        target,
      ).restoreFromJson(jsonEncode(payload), mode: RestoreMode.merge);

      expect(outcome.applied, isTrue);
      expect(
        (await target.programs.getById('p1'))!.eventRuleIds,
        listed.take(maxProgramEventRules).toList(),
        reason: 'the backup\'s list replaces the live one, cut to the most',
      );
    });

    test('a merge restore replaces a program\'s rules rather than joining '
        'them (#2529)', () async {
      final (source, rule) = await seeded();
      final target = openTestRepositories();
      await BackupService(target).restoreFromJson(
        encodeBackup(await BackupService(source).buildDocument()),
      );
      expect((await target.programs.getById('p1'))!.eventRuleIds, [rule.id]);

      final payload = backupToJson(await BackupService(source).buildDocument());
      (((payload['core']! as Map)['programs']! as List).single
          as Map)['eventRuleIds'] = [
        'b0',
      ];
      await BackupService(
        target,
      ).restoreFromJson(jsonEncode(payload), mode: RestoreMode.merge);

      expect((await target.programs.getById('p1'))!.eventRuleIds, ['b0']);
    });

    test('rules are bounded on decode', () {
      final read = decodeBackup(
        backupWith([
          for (var i = 0; i <= kMaxBackupEventRules; i++) ruleJson('r$i'),
        ]),
      );
      expect(read.document.eventRules, hasLength(kMaxBackupEventRules));
      expect(read.eventRulesComplete, isFalse);
    });
  });
}
