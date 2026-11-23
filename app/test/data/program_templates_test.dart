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
        ('a newer version', 'a', raw({...good, 'version': 2})),
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
}
