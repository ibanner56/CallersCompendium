import 'dart:convert';

import 'package:compendium_app/src/data/backup_settings_schema.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/program_templates.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

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
  });
}
