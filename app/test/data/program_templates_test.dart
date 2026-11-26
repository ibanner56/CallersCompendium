import 'dart:convert';

import 'package:compendium_app/src/data/backup_settings_schema.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/event_rules_scope.dart';
import 'package:compendium_app/src/data/program_templates.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/saved_searches.dart';
import '../support/test_repositories.dart';

/// Records every settings key written, so a test can say which keys an edit
/// touched.
class _RecordingSettings extends SettingsRepository {
  _RecordingSettings(super.db);

  final List<String> writes = [];

  @override
  Future<void> set(String key, Object? value, {DateTime? at}) {
    writes.add(key);
    return super.set(key, value, at: at);
  }

  @override
  Future<void> remove(String key, {DateTime? at, bool permanent = false}) {
    writes.add(key);
    return super.remove(key, at: at, permanent: permanent);
  }
}

void main() {
  group('template codec', () {
    test('a long name is cut to the limit, never inside a surrogate pair', () {
      final name = '${'a' * (kMaxProgramTemplateNameLength - 1)}\u{1F3BB}';
      final decoded = tryDecodeProgramTemplate(
        't',
        encodeProgramTemplate(ProgramTemplate(id: 't', name: name)),
      )!;
      expect(decoded.name, 'a' * (kMaxProgramTemplateNameLength - 1));
    });

    test('a template round-trips its name and slots in order', () {
      const template = ProgramTemplate(
        id: 'family',
        name: 'Family dance',
        entries: [
          ProgramTemplateEntry(danceId: 'd1'),
          ProgramTemplateEntry(danceId: 'd2', text: 'Guest caller'),
          ProgramTemplateEntry(text: Program.breakSlotText),
          ProgramTemplateEntry(text: 'Waltz'),
        ],
      );
      final decoded = tryDecodeProgramTemplate(
        'family',
        encodeProgramTemplate(template),
      );
      expect(decoded, isNotNull);
      expect(decoded!.id, 'family');
      expect(decoded.name, 'Family dance');
      expect(decoded.entries, template.entries);
    });

    test('the value is versioned and holds only name and slots', () {
      final value =
          jsonDecode(
                encodeProgramTemplate(
                  const ProgramTemplate(id: 'a', name: 'A'),
                ),
              )
              as Map;
      expect(value.keys.toSet(), {'version', 'name', 'slots'});
      expect(value['version'], 1);
    });

    test('decoding rejects anything that is not exactly a v1 template', () {
      String raw(Map<String, Object?> value) => jsonEncode(value);
      final good = {'version': 1, 'name': 'A', 'slots': <Object>[]};
      expect(tryDecodeProgramTemplate('a', raw(good)), isNotNull);
      for (final (label, id, stored) in <(String, String, Object?)>[
        ('not a string', 'a', good),
        ('not JSON', 'a', '{'),
        ('a newer version', 'a', raw({...good, 'version': 3})),
        ('an unknown field', 'a', raw({...good, 'rules': <Object>[]})),
        ('a non-string name', 'a', raw({...good, 'name': 3})),
        (
          'a bad slot',
          'a',
          raw({
            ...good,
            'slots': [<String, Object?>{}],
          }),
        ),
        ('an id with a colon', 'a:b', raw(good)),
        ('an empty id', '', raw(good)),
      ]) {
        expect(tryDecodeProgramTemplate(id, stored), isNull, reason: label);
      }
    });

    test('order and default decoders accept only ids', () {
      expect(tryDecodeProgramTemplateOrder(['a', 'b']), ['a', 'b']);
      expect(tryDecodeProgramTemplateOrder(['a', 'a']), isNull);
      expect(tryDecodeProgramTemplateOrder(['a', 3]), isNull);
      expect(tryDecodeProgramTemplateOrder('a'), isNull);
      expect(tryDecodeProgramTemplateDefault('a'), 'a');
      expect(
        tryDecodeProgramTemplateDefault(kProgramTemplateBlankDefault),
        kProgramTemplateBlankDefault,
      );
      expect(tryDecodeProgramTemplateDefault('a:b'), isNull);
      expect(tryDecodeProgramTemplateDefault(null), isNull);
    });
  });

  group('backup validation', () {
    test('each template key is checked by its prefix', () {
      final good = encodeProgramTemplate(
        const ProgramTemplate(
          id: 'x',
          name: 'X',
          entries: [ProgramTemplateEntry(danceId: 'd1')],
        ),
      );
      expect(validateBackupSettingValue(programTemplateKey('x'), good), isTrue);
      expect(
        validateBackupSettingValue(programTemplateKey('x'), 'garbage'),
        isFalse,
      );
      expect(
        validateBackupSettingValue('${kProgramTemplateKeyPrefix}bad:id', good),
        isFalse,
      );
    });

    test('the order and default keys are validated', () {
      expect(validateBackupSettingValue(kProgramTemplateOrderKey, ['a']), true);
      expect(validateBackupSettingValue(kProgramTemplateOrderKey, 'a'), false);
      expect(validateBackupSettingValue(kProgramTemplateDefaultKey, 'a'), true);
      expect(validateBackupSettingValue(kProgramTemplateDefaultKey, 3), false);
    });
  });

  group('migration from the Starting program', () {
    const legacy = [
      ProgramTemplateEntry(danceId: 'd1'),
      ProgramTemplateEntry(text: Program.breakSlotText),
      ProgramTemplateEntry(danceId: 'd2', text: 'Mixer'),
    ];

    Future<_RecordingSettings> withLegacy(
      List<ProgramTemplateEntry> entries,
    ) async {
      final db = openWidgetTestDatabase();
      addTearDown(db.close);
      final settings = _RecordingSettings(db);
      await settings.set(
        kDefaultStartingProgramKey,
        encodeStartingProgramTemplate(entries),
      );
      settings.writes.clear();
      return settings;
    }

    test('a non-empty Starting program shows as the first template, in '
        'order, and the default, without writing anything', () async {
      final settings = await withLegacy(legacy);

      final templates = await loadProgramTemplates(settings);

      expect(templates.templates, hasLength(1));
      final only = templates.templates.single;
      expect(only.id, kMigratedStartingProgramTemplateId);
      // Stored unnamed, shown localized, so every device writes one value.
      expect(only.name, isEmpty);
      expect(only.entries, legacy);
      expect(templates.defaultId, only.id);
      expect(settings.writes, isEmpty);
      expect(await defaultProgramTemplateEntries(settings), legacy);
    });

    test('the first change writes the copy, the default and the order, and '
        'the result reads the same', () async {
      final settings = await withLegacy(legacy);

      await saveProgramTemplate(
        settings,
        const ProgramTemplate(id: 'family', name: 'Family'),
      );

      expect(settings.writes, [
        programTemplateKey(kMigratedStartingProgramTemplateId),
        kProgramTemplateDefaultKey,
        kProgramTemplateOrderKey,
        programTemplateKey('family'),
      ]);
      final templates = await loadProgramTemplates(settings);
      expect(
        templates.byId(kMigratedStartingProgramTemplateId)!.entries,
        legacy,
      );
      expect(templates.defaultId, kMigratedStartingProgramTemplateId);
      expect(templates.templates.first.id, kMigratedStartingProgramTemplateId);
      // The legacy key stays, so an older build keeps its starting program.
      expect(await settings.contains(kDefaultStartingProgramKey), isTrue);
    });

    test('an empty Starting program yields no template and writes nothing, '
        'so a later one still shows', () async {
      final settings = await withLegacy(const []);

      final templates = await loadProgramTemplates(settings);
      expect(templates.templates, isEmpty);
      expect(templates.defaultId, isNull);
      await materializeProgramTemplates(settings);
      expect(settings.writes, isEmpty);

      // A peer on an older build syncs in a Starting program afterwards.
      await settings.set(
        kDefaultStartingProgramKey,
        encodeStartingProgramTemplate(const [
          ProgramTemplateEntry(danceId: 'd1'),
        ]),
      );
      final later = await loadProgramTemplates(settings);
      expect(
        [for (final t in later.templates) t.id],
        [kMigratedStartingProgramTemplateId],
      );
    });

    test('copying it twice changes nothing', () async {
      final settings = await withLegacy(legacy);
      await materializeProgramTemplates(settings);
      final after = await settings.all();
      settings.writes.clear();

      await materializeProgramTemplates(settings);

      expect(settings.writes, isEmpty);
      expect(await settings.all(), after);
    });

    test('a template the user deleted is not brought back', () async {
      final settings = await withLegacy(legacy);
      await deleteProgramTemplate(settings, kMigratedStartingProgramTemplateId);

      final templates = await loadProgramTemplates(settings);
      expect(templates.templates, isEmpty);
      expect(templates.defaultId, isNull);
    });
  });

  group('the implicit default', () {
    test('the first template becomes the default when none is set', () async {
      final repos = openTestRepositories();
      await saveProgramTemplate(
        repos.settings,
        const ProgramTemplate(id: 'a', name: 'A'),
      );
      await saveProgramTemplateDefaultIfUnset(repos.settings, 'a');
      expect((await loadProgramTemplates(repos.settings)).defaultId, 'a');
    });

    test('an explicit Blank program is kept', () async {
      final repos = openTestRepositories();
      await saveProgramTemplateDefault(repos.settings, null);
      await saveProgramTemplate(
        repos.settings,
        const ProgramTemplate(id: 'a', name: 'A'),
      );
      await saveProgramTemplateDefaultIfUnset(repos.settings, 'a');
      expect((await loadProgramTemplates(repos.settings)).defaultId, isNull);
    });

    test('a default naming a deleted template is replaced, as after deleting '
        'the migrated Starting program', () async {
      final repos = openTestRepositories();
      await repos.settings.set(
        kDefaultStartingProgramKey,
        encodeStartingProgramTemplate(const [
          ProgramTemplateEntry(danceId: 'd1'),
        ]),
      );
      await deleteProgramTemplate(
        repos.settings,
        kMigratedStartingProgramTemplateId,
      );
      await saveProgramTemplate(
        repos.settings,
        const ProgramTemplate(id: 'fam', name: 'Family'),
      );
      await saveProgramTemplateDefaultIfUnset(repos.settings, 'fam');

      final templates = await loadProgramTemplates(repos.settings);
      expect([for (final t in templates.templates) t.id], ['fam']);
      expect(templates.defaultId, 'fam');
    });

    test('a live default is kept', () async {
      final repos = openTestRepositories();
      await saveProgramTemplate(
        repos.settings,
        const ProgramTemplate(id: 'a', name: 'A'),
      );
      await saveProgramTemplate(
        repos.settings,
        const ProgramTemplate(id: 'b', name: 'B'),
      );
      await saveProgramTemplateDefault(repos.settings, 'a');
      await saveProgramTemplateDefaultIfUnset(repos.settings, 'b');
      expect((await loadProgramTemplates(repos.settings)).defaultId, 'a');
    });
  });

  test('the order key keeps at most the cap of ids', () async {
    final repos = openTestRepositories();
    await saveProgramTemplateOrder(repos.settings, [
      for (var i = 0; i <= kMaxProgramTemplateOrderLength; i++) 't$i',
    ]);
    final stored = tryDecodeProgramTemplateOrder(
      await repos.settings.get(kProgramTemplateOrderKey),
    );
    expect(stored, hasLength(kMaxProgramTemplateOrderLength));
    expect(stored!.first, 't0');
  });

  group('loading', () {
    test(
      'templates follow the order key, then unlisted ones by name',
      () async {
        final repos = openTestRepositories();
        for (final (id, name) in [
          ('a', 'Zeta'),
          ('b', 'Beta'),
          ('c', 'alpha'),
          ('d', 'Delta'),
        ]) {
          await saveProgramTemplate(
            repos.settings,
            ProgramTemplate(id: id, name: name),
          );
        }
        await saveProgramTemplateOrder(repos.settings, ['d', 'gone', 'a']);
        final templates = await loadProgramTemplates(repos.settings);
        expect(
          [for (final t in templates.templates) t.id],
          ['d', 'a', 'c', 'b'],
        );
      },
    );

    test(
      'a default naming a missing template reads as Blank program',
      () async {
        final repos = openTestRepositories();
        await saveProgramTemplateOrder(repos.settings, const []);
        await saveProgramTemplateDefault(repos.settings, 'gone');
        final templates = await loadProgramTemplates(repos.settings);
        expect(templates.defaultId, isNull);
        expect(templates.defaultTemplate, isNull);
      },
    );

    test('defaultFirst puts the default ahead of the others', () {
      const templates = ProgramTemplates(
        templates: [
          ProgramTemplate(id: 'a', name: 'A'),
          ProgramTemplate(id: 'b', name: 'B'),
          ProgramTemplate(id: 'c', name: 'C'),
        ],
        defaultId: 'b',
      );
      expect([for (final t in templates.defaultFirst) t.id], ['b', 'a', 'c']);
    });
  });

  group('the default template for programs created elsewhere', () {
    test("returns the chosen default's slots", () async {
      final repos = openTestRepositories();
      await saveProgramTemplate(
        repos.settings,
        const ProgramTemplate(
          id: 'family',
          name: 'Family',
          entries: [ProgramTemplateEntry(danceId: 'd1')],
        ),
      );
      await saveProgramTemplate(
        repos.settings,
        const ProgramTemplate(
          id: 'contra',
          name: 'Contra',
          entries: [
            ProgramTemplateEntry(danceId: 'd2'),
            ProgramTemplateEntry(text: Program.breakSlotText),
          ],
        ),
      );
      await saveProgramTemplateOrder(repos.settings, ['family', 'contra']);
      await saveProgramTemplateDefault(repos.settings, 'contra');

      expect(await defaultProgramTemplateEntries(repos.settings), const [
        ProgramTemplateEntry(danceId: 'd2'),
        ProgramTemplateEntry(text: Program.breakSlotText),
      ]);
    });

    test('returns none for Blank program', () async {
      final repos = openTestRepositories();
      await saveProgramTemplate(
        repos.settings,
        const ProgramTemplate(
          id: 'family',
          name: 'Family',
          entries: [ProgramTemplateEntry(danceId: 'd1')],
        ),
      );
      await saveProgramTemplateOrder(repos.settings, ['family']);
      await saveProgramTemplateDefault(repos.settings, null);

      expect(await defaultProgramTemplateEntries(repos.settings), isEmpty);
    });
  });

  group('storage', () {
    test('editing one template writes only that template\'s key', () async {
      final db = openWidgetTestDatabase();
      addTearDown(db.close);
      final settings = _RecordingSettings(db);
      const a = ProgramTemplate(id: 'a', name: 'A');
      const b = ProgramTemplate(id: 'b', name: 'B');
      await saveProgramTemplate(settings, a);
      await saveProgramTemplate(settings, b);
      await saveProgramTemplateOrder(settings, ['a', 'b']);
      settings.writes.clear();

      await saveProgramTemplate(
        settings,
        a.copyWith(entries: const [ProgramTemplateEntry(text: 'Waltz')]),
      );

      expect(settings.writes, [programTemplateKey('a')]);
    });

    test(
      'a deleted template comes back in place, as the default, on Undo',
      () async {
        final repos = openTestRepositories();
        const a = ProgramTemplate(id: 'a', name: 'A');
        const b = ProgramTemplate(id: 'b', name: 'B');
        await saveProgramTemplate(repos.settings, a);
        await saveProgramTemplate(repos.settings, b);
        await saveProgramTemplateOrder(repos.settings, ['a', 'b']);
        await saveProgramTemplateDefault(repos.settings, 'a');

        await deleteProgramTemplate(repos.settings, 'a');
        var templates = await loadProgramTemplates(repos.settings);
        expect([for (final t in templates.templates) t.id], ['b']);
        expect(templates.defaultId, isNull);
        expect(await repos.settings.contains(programTemplateKey('a')), isFalse);

        await saveProgramTemplate(repos.settings, a);
        templates = await loadProgramTemplates(repos.settings);
        expect([for (final t in templates.templates) t.id], ['a', 'b']);
        expect(templates.defaultId, 'a');
      },
    );
  });

  group('slots from a template', () {
    test('every slot gets a fresh id and position, and a missing dance is '
        'skipped', () {
      final slots = programSlotsFromTemplate(const [
        ProgramTemplateEntry(danceId: 'd1', text: 'Note'),
        ProgramTemplateEntry(danceId: 'gone'),
        ProgramTemplateEntry(text: Program.breakSlotText),
      ], danceExists: (id) => id == 'd1');
      expect([for (final s in slots) s.danceId], ['d1', null]);
      expect([for (final s in slots) s.text], ['Note', Program.breakSlotText]);
      expect([for (final s in slots) s.position], [0, 1]);
      expect(slots.map((s) => s.id).toSet(), hasLength(2));
    });

    test('a choice resolves to the default, a named template, or blank', () {
      const templates = ProgramTemplates(
        templates: [
          ProgramTemplate(
            id: 'a',
            name: 'A',
            entries: [ProgramTemplateEntry(text: 'from A')],
          ),
          ProgramTemplate(
            id: 'b',
            name: 'B',
            entries: [ProgramTemplateEntry(text: 'from B')],
          ),
        ],
        defaultId: 'b',
      );
      String? first(ProgramTemplateChoice choice) {
        final entries = programTemplateEntriesFor(templates, choice);
        return entries.isEmpty ? null : entries.first.text;
      }

      expect(first(const ProgramTemplateChoice.useDefault()), 'from B');
      expect(first(const ProgramTemplateChoice.template('a')), 'from A');
      expect(first(const ProgramTemplateChoice.blank()), isNull);
      expect(first(const ProgramTemplateChoice.template('gone')), isNull);
    });
  });

  group('slot rules (#2338)', () {
    const rule = ProgramTemplateEntry.rule(
      savedSearchId: 'search-1',
      label: 'Easy improper opener',
    );

    test('a template without a rule is written exactly as before, as v1', () {
      // Byte for byte what #2337 wrote, so a template of dances and text
      // keeps its value (and its sync hash), and every build still reads it.
      const template = ProgramTemplate(
        id: 'contra',
        name: 'Contra night',
        entries: [
          ProgramTemplateEntry(danceId: 'd1', text: 'Guest caller'),
          ProgramTemplateEntry(text: Program.breakSlotText),
          ProgramTemplateEntry(text: 'Waltz'),
        ],
      );
      expect(
        encodeProgramTemplate(template),
        '{"version":1,"name":"Contra night","slots":['
        '{"danceId":"d1","text":"Guest caller"},'
        '{"text":"Break"},{"text":"Waltz"}]}',
      );
    });

    test('a rule labelled Break is refused on read and written as the break '
        'it would read as', () {
      String value(String label) => jsonEncode({
        'version': 2,
        'name': 'Contra night',
        'slots': [
          {'savedSearchId': 'search-1', 'label': label},
        ],
      });
      expect(tryDecodeProgramTemplate('a', value('Waltz opener')), isNotNull);
      for (final label in ['Break', ' break ', 'BREAK']) {
        expect(
          tryDecodeProgramTemplate('a', value(label)),
          isNull,
          reason: label,
        );
      }
      expect(
        encodeProgramTemplate(
          const ProgramTemplate(
            id: 'contra',
            name: 'Contra night',
            entries: [
              ProgramTemplateEntry.rule(
                savedSearchId: 'search-1',
                label: 'Break',
              ),
            ],
          ),
        ),
        '{"version":1,"name":"Contra night","slots":[{"text":"Break"}]}',
      );
    });

    test('a rule is written as its saved search and label, in a v2 value, '
        'and reads back', () {
      const template = ProgramTemplate(
        id: 'contra',
        name: 'Contra night',
        entries: [
          ProgramTemplateEntry(danceId: 'd1'),
          rule,
        ],
      );
      final stored = encodeProgramTemplate(template);
      final value = jsonDecode(stored) as Map;
      expect(value['version'], 2);
      expect(value['slots'], [
        {'danceId': 'd1'},
        {'savedSearchId': 'search-1', 'label': 'Easy improper opener'},
      ]);
      final decoded = tryDecodeProgramTemplate('contra', stored)!;
      expect(decoded.entries, template.entries);
      expect(decoded.entries.last.isRule, isTrue);
      expect(decoded.entries.last.savedSearchId, 'search-1');
      expect(decoded.entries.last.text, 'Easy improper opener');
    });

    test('backup validation accepts a template with a rule and refuses a '
        'malformed one', () {
      final good = encodeProgramTemplate(
        const ProgramTemplate(id: 'x', name: 'X', entries: [rule]),
      );
      expect(validateBackupSettingValue(programTemplateKey('x'), good), isTrue);
      String raw(int version, Map<String, Object?> slot) => jsonEncode({
        'version': version,
        'name': 'X',
        'slots': [slot],
      });
      for (final (label, stored) in <(String, String)>[
        ('a rule in a v1 value', raw(1, {'savedSearchId': 's', 'label': 'L'})),
        ('a rule with no label', raw(2, {'savedSearchId': 's'})),
        (
          'a rule with a blank id',
          raw(2, {'savedSearchId': ' ', 'label': 'L'}),
        ),
        (
          'a rule that also names a dance',
          raw(2, {'savedSearchId': 's', 'label': 'L', 'danceId': 'd'}),
        ),
        (
          'a label that is not text',
          raw(2, {'savedSearchId': 's', 'label': 3}),
        ),
      ]) {
        expect(
          validateBackupSettingValue(programTemplateKey('x'), stored),
          isFalse,
          reason: label,
        );
      }
    });

    test('the legacy Starting program never holds a rule', () {
      expect(
        tryDecodeStartingProgramTemplate(
          jsonEncode({
            'version': 1,
            'slots': [
              {'savedSearchId': 's', 'label': 'L'},
            ],
          }),
        ),
        isNull,
      );
    });

    test('a rule becomes a placeholder: its label as text and its saved '
        'search remembered; other entries are as before', () {
      final slots = programSlotsFromTemplate(const [
        ProgramTemplateEntry(danceId: 'd1'),
        rule,
        ProgramTemplateEntry(text: 'Waltz'),
      ], danceExists: (_) => true);
      expect([for (final s in slots) s.danceId], ['d1', null, null]);
      expect(
        [for (final s in slots) s.text],
        [null, 'Easy improper opener', 'Waltz'],
      );
      expect(
        [for (final s in slots) s.placeholderSearchId],
        [null, 'search-1', null],
      );
    });

    test('deleting a saved search a slot rule uses is refused, naming the '
        'rule and its template', () async {
      final repos = openTestRepositories();
      registerProgramTemplateSavedSearchUses(repos);
      final used = await repos.savedSearches.create(
        name: 'Easy improper',
        spec: SavedSearchSpec.fromPanelState(
          CollectionPanelState(text: 'swing'),
          today: DateTime.utc(2026, 11, 22),
        ).value!,
      );
      final unused = await repos.savedSearches.create(
        name: 'Mixers',
        spec: SavedSearchSpec.fromPanelState(
          CollectionPanelState(text: 'swing'),
          today: DateTime.utc(2026, 11, 22),
        ).value!,
      );
      await saveProgramTemplate(
        repos.settings,
        ProgramTemplate(
          id: 'contra',
          name: 'Contra night',
          entries: [
            ProgramTemplateEntry.rule(
              savedSearchId: used.id,
              label: 'Easy improper opener',
            ),
          ],
        ),
      );
      await expectLater(
        repos.savedSearches.delete(used.id),
        throwsA(
          isA<SavedSearchInUse>().having(
            (e) => [for (final u in e.uses) (u.kind, u.label, u.detail)],
            'uses',
            [
              (
                kProgramTemplateSlotRuleUse,
                'Easy improper opener',
                'Contra night',
              ),
            ],
          ),
        ),
      );
      expect(await repos.savedSearches.get(used.id), isNotNull);
      await repos.savedSearches.delete(unused.id);
      expect(await repos.savedSearches.get(unused.id), isNull);
    });

    group('the editor\'s save only starts using a stored saved search '
        '(#2529)', () {
      ProgramTemplate withRules(List<String> searchIds, {String name = 'T'}) =>
          ProgramTemplate(
            id: 't',
            name: name,
            entries: [
              for (final id in searchIds)
                ProgramTemplateEntry.rule(savedSearchId: id, label: 'Slot $id'),
            ],
          );

      Future<ProgramTemplate?> stored(SettingsRepository settings) async =>
          tryDecodeProgramTemplate(
            't',
            await settings.get(programTemplateKey('t')),
          );

      test('a new slot rule naming a search that is not stored is refused, '
          'writing nothing', () async {
        final repos = openTestRepositories();
        await storeSavedSearches(repos.settings, ['kept']);
        await saveProgramTemplate(
          repos.settings,
          withRules(['kept']),
          checkSlotRules: SlotRuleSearchCheck.added,
        );
        await expectLater(
          saveProgramTemplate(
            repos.settings,
            withRules(['kept', 'gone']),
            checkSlotRules: SlotRuleSearchCheck.added,
          ),
          throwsA(isA<SavedSearchGone>().having((e) => e.id, 'id', 'gone')),
        );
        expect(
          [
            for (final e in (await stored(repos.settings))!.entries)
              e.savedSearchId,
          ],
          ['kept'],
        );
      });

      test('a slot rule the stored template already has is not checked, so '
          'a template whose search was deleted since can be renamed', () async {
        final repos = openTestRepositories();
        await storeSavedSearches(repos.settings, ['s']);
        await saveProgramTemplate(
          repos.settings,
          withRules(['s']),
          checkSlotRules: SlotRuleSearchCheck.added,
        );
        await repos.savedSearches.delete('s');
        await saveProgramTemplate(
          repos.settings,
          withRules(['s'], name: 'Renamed'),
          checkSlotRules: SlotRuleSearchCheck.added,
        );
        expect((await stored(repos.settings))!.name, 'Renamed');
      });

      test(
        'with no stored copy (deleted elsewhere while its editor was '
        'open) nothing is checked and the template is written back',
        () async {
          final repos = openTestRepositories();
          await saveProgramTemplate(
            repos.settings,
            withRules(['gone'], name: 'Renamed'),
            checkSlotRules: SlotRuleSearchCheck.added,
          );
          expect((await stored(repos.settings))!.name, 'Renamed');
        },
      );

      test('a copy checks every slot rule, even one the template it is under '
          'already names', () async {
        final repos = openTestRepositories();
        await saveProgramTemplate(repos.settings, withRules(['gone']));
        await expectLater(
          saveProgramTemplate(
            repos.settings,
            withRules(['gone'], name: 'Copy'),
            checkSlotRules: SlotRuleSearchCheck.all,
          ),
          throwsA(isA<SavedSearchGone>().having((e) => e.id, 'id', 'gone')),
        );
        expect((await stored(repos.settings))!.name, 'T');

        await storeSavedSearches(repos.settings, ['gone']);
        await saveProgramTemplate(
          repos.settings,
          withRules(['gone'], name: 'Copy'),
          checkSlotRules: SlotRuleSearchCheck.all,
        );
        expect((await stored(repos.settings))!.name, 'Copy');
      });

      test('without the check (an Undo) the slots are written as '
          'they are', () async {
        final repos = openTestRepositories();
        await saveProgramTemplate(repos.settings, withRules(['gone']));
        expect(
          [
            for (final e in (await stored(repos.settings))!.entries)
              e.savedSearchId,
          ],
          ['gone'],
        );
      });
    });
  });

  group('undoing the slot rules a refused save named (#2529)', () {
    const waltz = ProgramTemplateEntry(text: 'Waltz');
    const unsaved = ProgramTemplateEntry(text: 'Added meanwhile');
    final kept = ProgramTemplateEntry.rule(savedSearchId: 'a', label: 'Kept');
    final before = ProgramTemplateEntry.rule(savedSearchId: 'a', label: 'Was');
    final edited = ProgramTemplateEntry.rule(
      savedSearchId: 'gone',
      label: 'Is',
    );
    final added = ProgramTemplateEntry.rule(
      savedSearchId: 'gone',
      label: 'New',
    );

    test('an edit goes back to the rule it changed, in its place; an added '
        'rule goes; every other entry stays, an unsaved one included', () {
      final editedFrom =
          Map<ProgramTemplateEntry, ProgramTemplateEntry>.identity()
            ..[edited] = before;
      expect(
        undoSlotRulesNaming(
          [waltz, edited, kept, added, unsaved],
          'gone',
          storedSearchIds: {'a'},
          editedFrom: editedFrom,
        ),
        [waltz, before, kept, unsaved],
      );
    });

    test('nothing to undo when no entry names the search, or the stored copy '
        'already does', () {
      final none = Map<ProgramTemplateEntry, ProgramTemplateEntry>.identity();
      expect(
        undoSlotRulesNaming(
          [waltz, kept],
          'gone',
          storedSearchIds: {'a'},
          editedFrom: none,
        ),
        isNull,
      );
      expect(
        undoSlotRulesNaming(
          [waltz, added],
          'gone',
          storedSearchIds: {'gone'},
          editedFrom: none,
        ),
        isNull,
      );
    });
  });

  group('event rules on a template (#2342)', () {
    Future<EventRule> rule(
      CompendiumRepositories repos,
      String nickname,
    ) async {
      await storeSavedSearches(repos.settings, ['search-1']);
      return repos.eventRules.create(
        savedSearchId: 'search-1',
        quantifier: EventRuleQuantifier.atMost,
        count: 1,
        scope: EventRuleScope.wholeProgram,
        nickname: nickname,
      );
    }

    test('a template without event rules is written exactly as before, as v1 '
        'or v2', () {
      expect(
        encodeProgramTemplate(
          const ProgramTemplate(
            id: 'contra',
            name: 'Contra night',
            entries: [ProgramTemplateEntry(text: 'Waltz')],
          ),
        ),
        '{"version":1,"name":"Contra night","slots":[{"text":"Waltz"}]}',
      );
      expect(
        encodeProgramTemplate(
          const ProgramTemplate(
            id: 'contra',
            name: 'Contra night',
            entries: [
              ProgramTemplateEntry.rule(savedSearchId: 's', label: 'Opener'),
            ],
          ),
        ),
        '{"version":2,"name":"Contra night","slots":['
        '{"savedSearchId":"s","label":"Opener"}]}',
      );
    });

    test('event rules are written last, in a v3 value, and read back with '
        'the slots and their slot rules', () {
      const template = ProgramTemplate(
        id: 'family',
        name: 'Family dance',
        entries: [
          ProgramTemplateEntry(text: 'Waltz'),
          ProgramTemplateEntry.rule(savedSearchId: 's', label: 'Opener'),
        ],
        eventRuleIds: ['r2', 'r1'],
      );
      final stored = encodeProgramTemplate(template);
      expect(
        stored,
        '{"version":3,"name":"Family dance","slots":[{"text":"Waltz"},'
        '{"savedSearchId":"s","label":"Opener"}],"eventRuleIds":["r2","r1"]}',
      );
      final decoded = tryDecodeProgramTemplate('family', stored)!;
      expect(decoded.name, 'Family dance');
      expect(decoded.entries, template.entries);
      expect(decoded.eventRuleIds, ['r2', 'r1']);
      expect(
        jsonDecode(
          encodeProgramTemplate(
            const ProgramTemplate(id: 'x', name: 'X', eventRuleIds: ['r1']),
          ),
        ),
        {
          'version': 3,
          'name': 'X',
          'slots': <Object?>[],
          'eventRuleIds': ['r1'],
        },
        reason: 'event rules alone are a v3 value',
      );
    });

    test('the ids are written as a program keeps them: each once, none '
        'blank or over the length, at most the most a program may apply', () {
      final long = 'x' * (kMaxProgramTemplateEventRuleIdLength + 1);
      final many = [for (var i = 0; i < maxProgramEventRules + 5; i++) 'r$i'];
      ProgramTemplate decodeBack(List<String> ids) => tryDecodeProgramTemplate(
        't',
        encodeProgramTemplate(
          ProgramTemplate(id: 't', name: 'T', eventRuleIds: ids),
        ),
      )!;
      expect(decodeBack(['a', 'b', 'a', '', ' ', long, 'c']).eventRuleIds, [
        'a',
        'b',
        'c',
      ]);
      expect(decodeBack(many).eventRuleIds, many.take(maxProgramEventRules));
      expect(
        (jsonDecode(
              encodeProgramTemplate(
                const ProgramTemplate(
                  id: 't',
                  name: 'T',
                  eventRuleIds: ['', ' '],
                ),
              ),
            )
            as Map)['version'],
        1,
        reason: 'no id left: no field, and the version it had before',
      );
    });

    test('copyWith keeps the event rules unless it is given new ones', () {
      const template = ProgramTemplate(
        id: 't',
        name: 'T',
        eventRuleIds: ['r1'],
      );
      expect(template.copyWith(name: 'U').eventRuleIds, ['r1']);
      expect(template.copyWith(entries: const []).eventRuleIds, ['r1']);
      expect(template.copyWith(eventRuleIds: const []).eventRuleIds, isEmpty);
    });

    test('decoding and backup validation accept exactly what is written, '
        'and refuse a malformed eventRuleIds', () {
      final good = encodeProgramTemplate(
        const ProgramTemplate(id: 'x', name: 'X', eventRuleIds: ['r1', 'r2']),
      );
      expect(validateBackupSettingValue(programTemplateKey('x'), good), isTrue);
      expect(tryDecodeProgramTemplate('x', good)!.eventRuleIds, ['r1', 'r2']);
      String raw(int version, Object? ids) => jsonEncode({
        'version': version,
        'name': 'X',
        'slots': <Object?>[],
        'eventRuleIds': ids,
      });
      for (final (label, stored) in <(String, String)>[
        ('event rules in a v1 value', raw(1, ['r1'])),
        ('event rules in a v2 value', raw(2, ['r1'])),
        (
          'a v3 value without the field',
          jsonEncode({'version': 3, 'name': 'X', 'slots': <Object?>[]}),
        ),
        ('an empty list', raw(3, <Object?>[])),
        ('not a list', raw(3, 'r1')),
        ('an id that is not text', raw(3, [1])),
        ('a blank id', raw(3, [' '])),
        ('a repeated id', raw(3, ['r1', 'r1'])),
        (
          'an id over the length',
          raw(3, ['x' * (kMaxProgramTemplateEventRuleIdLength + 1)]),
        ),
        (
          'more ids than a program may apply',
          raw(3, [for (var i = 0; i <= maxProgramEventRules; i++) 'r$i']),
        ),
        ('a version this build does not know', raw(4, ['r1'])),
        (
          'an unknown field beside it',
          jsonEncode({
            'version': 3,
            'name': 'X',
            'slots': <Object?>[],
            'eventRuleIds': ['r1'],
            'later': true,
          }),
        ),
      ]) {
        expect(tryDecodeProgramTemplate('x', stored), isNull, reason: label);
        expect(
          validateBackupSettingValue(programTemplateKey('x'), stored),
          isFalse,
          reason: label,
        );
      }
    });

    test('a value from a newer build is not shown, and no write here '
        'rewrites it, so none of its fields is dropped', () async {
      final repos = openTestRepositories();
      final newer = jsonEncode({
        'version': 4,
        'name': 'From a newer build',
        'slots': <Object?>[],
        'eventRuleIds': ['r1'],
        'later': {'kept': true},
      });
      await repos.settings.set(programTemplateKey('newer'), newer);
      await saveProgramTemplate(
        repos.settings,
        const ProgramTemplate(id: 'mine', name: 'Mine'),
      );
      await saveProgramTemplateOrder(repos.settings, const ['mine', 'newer']);
      await saveProgramTemplateDefaultIfUnset(repos.settings, 'mine');
      final loaded = await loadProgramTemplates(repos.settings);
      expect([for (final t in loaded.templates) t.id], ['mine']);
      expect(await repos.settings.get(programTemplateKey('newer')), newer);
    });

    test("a new program takes the live rules, in the template's order, only "
        'while Event rules is on', () async {
      final repos = openTestRepositories();
      final a = await rule(repos, 'a');
      final b = await rule(repos, 'b');
      final template = ProgramTemplate(
        id: 't',
        name: 'T',
        eventRuleIds: [b.id, 'not-here-yet', a.id],
      );
      expect(
        await newProgramEventRuleIds(repos, template),
        isEmpty,
        reason: 'Event rules is off by default',
      );
      await repos.settings.set(kEventRulesEnabledKey, true);
      expect(await newProgramEventRuleIds(repos, template), [b.id, a.id]);
      expect(await newProgramEventRuleIds(repos, null), isEmpty);
      await repos.settings.set(kEventRulesEnabledKey, false);
      expect(await newProgramEventRuleIds(repos, template), isEmpty);
    });

    test('a deleted rule is skipped and kept on the template; an Undo of its '
        'delete brings it back', () async {
      final repos = openTestRepositories();
      await repos.settings.set(kEventRulesEnabledKey, true);
      final a = await rule(repos, 'a');
      final b = await rule(repos, 'b');
      await saveProgramTemplate(
        repos.settings,
        ProgramTemplate(id: 't', name: 'T', eventRuleIds: [a.id, b.id]),
      );
      Future<ProgramTemplate> stored() async =>
          (await loadProgramTemplates(repos.settings)).byId('t')!;

      await repos.eventRules.delete(a.id);
      expect(await newProgramEventRuleIds(repos, await stored()), [b.id]);
      expect((await stored()).eventRuleIds, [a.id, b.id]);

      await repos.eventRules.restore(a.id);
      expect(await newProgramEventRuleIds(repos, await stored()), [a.id, b.id]);
    });

    test('the Default template gives programs made elsewhere its rules, and '
        'Blank program none', () async {
      final repos = openTestRepositories();
      await repos.settings.set(kEventRulesEnabledKey, true);
      final a = await rule(repos, 'a');
      await saveProgramTemplate(
        repos.settings,
        ProgramTemplate(id: 't', name: 'T', eventRuleIds: [a.id]),
      );
      await saveProgramTemplateOrder(repos.settings, const ['t']);
      await saveProgramTemplateDefault(repos.settings, 't');
      expect(
        await newProgramEventRuleIds(
          repos,
          await defaultProgramTemplate(repos.settings),
        ),
        [a.id],
      );
      await saveProgramTemplateDefault(repos.settings, null);
      expect(await defaultProgramTemplate(repos.settings), isNull);
    });
  });
}
