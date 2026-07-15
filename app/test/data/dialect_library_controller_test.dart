import 'package:compendium_app/src/data/dialect_library_controller.dart';
import 'package:compendium_app/src/screens/settings_screen.dart'
    show kActiveDialectKey;
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

Future<(DialectLibraryController, SettingsRepository)> _controller() async {
  final repos = openTestRepositories();
  await repos.ensureMigrated();
  final controller = DialectLibraryController(repos.settings);
  await controller.load();
  return (controller, repos.settings);
}

Dialect _custom(String name) => Dialect(
  name: name,
  roles: const {'role1': RoleTerm('Jet'), 'role2': RoleTerm('Ruby')},
  discouragedTerms: const ['foo'],
);

void main() {
  group('DialectLibraryController', () {
    test('starts empty with the default active dialect', () async {
      final (c, _) = await _controller();
      expect(c.customDialects, isEmpty);
      expect(c.activeName, isNull);
      expect(c.active, Dialect.larksRobins);
      expect(c.all, containsAll(Dialect.presets));
    });

    test('upsert adds then replaces by name', () async {
      final (c, _) = await _controller();
      await c.upsert(_custom('Mine'));
      expect(c.customDialects, hasLength(1));
      await c.upsert(
        Dialect(name: 'Mine', roles: const {'role1': RoleTerm('Cat')}),
      );
      expect(c.customDialects, hasLength(1));
      expect(c.customByName('Mine')!.roles['role1']!.singular, 'Cat');
    });

    test('upsert rejects a shipped preset name', () async {
      final (c, _) = await _controller();
      expect(() => c.upsert(_custom('Larks/Robins')), throwsArgumentError);
      expect(c.customDialects, isEmpty);
    });

    test('load marks the library initialized so migration runs once', () async {
      final repos = openTestRepositories();
      await repos.ensureMigrated();
      final first = DialectLibraryController(repos.settings);
      await first.load();
      // Even with no legacy data, the library key is now present, so a second
      // load won't re-run migration / re-write settings.
      expect(await repos.settings.contains(kCustomDialectsKey), isTrue);
    });

    test('duplicate seeds from a preset under a unique name', () async {
      final (c, _) = await _controller();
      final a = await c.duplicate(name: 'Copy', from: Dialect.larksRobins);
      final b = await c.duplicate(name: 'Copy', from: Dialect.larksRobins);
      expect([a.name, b.name], ['Copy', 'Copy 2']);
      expect(a.roles, Dialect.larksRobins.roles);
      expect(c.activeName, isNull, reason: 'duplicate does not activate');
    });

    test('duplicate uniquifies against preset names too', () async {
      final (c, _) = await _controller();
      final d = await c.duplicate(name: 'Larks/Robins');
      expect(d.name, 'Larks/Robins 2');
    });

    test('setActive resolves custom over preset and persists', () async {
      final (c, settings) = await _controller();
      await c.upsert(_custom('Mine'));
      await c.setActive('Mine');
      expect(c.active.name, 'Mine');
      // Back-compat key kept in sync.
      final blob = await settings.get(kActiveDialectKey);
      expect((blob as Map)['name'], 'Mine');
    });

    test('rename updates the name and the active pointer', () async {
      final (c, _) = await _controller();
      await c.upsert(_custom('Mine'));
      await c.setActive('Mine');
      final newName = await c.rename('Mine', 'Yours');
      expect(newName, 'Yours');
      expect(c.customByName('Mine'), isNull);
      expect(c.customByName('Yours'), isNotNull);
      expect(c.activeName, 'Yours');
    });

    test('delete of the active dialect falls back to the default', () async {
      final (c, _) = await _controller();
      await c.upsert(_custom('Mine'));
      await c.setActive('Mine');
      await c.delete('Mine');
      expect(c.customDialects, isEmpty);
      expect(c.active, Dialect.larksRobins);
      expect(c.activeName, Dialect.larksRobins.name);
    });

    test('persists custom dialects and active across a reload', () async {
      final repos = openTestRepositories();
      await repos.ensureMigrated();
      final first = DialectLibraryController(repos.settings);
      await first.load();
      await first.upsert(_custom('Mine'));
      await first.setActive('Mine');

      final second = DialectLibraryController(repos.settings);
      await second.load();
      expect(second.customDialects, hasLength(1));
      expect(second.customByName('Mine'), _custom('Mine'));
      expect(second.active.name, 'Mine');
    });

    test(
      'migrates a legacy custom active-dialect blob into the library',
      () async {
        final repos = openTestRepositories();
        await repos.ensureMigrated();
        // Pre-library install: only the active dialect blob was stored.
        await repos.settings.set(kActiveDialectKey, _custom('Legacy').toJson());

        final c = DialectLibraryController(repos.settings);
        await c.load();
        expect(c.customByName('Legacy'), _custom('Legacy'));
        expect(c.active.name, 'Legacy');
      },
    );

    test('migrates a legacy preset active without adding a custom', () async {
      final repos = openTestRepositories();
      await repos.ensureMigrated();
      await repos.settings.set(
        kActiveDialectKey,
        Dialect.leadsFollows.toJson(),
      );

      final c = DialectLibraryController(repos.settings);
      await c.load();
      expect(c.customDialects, isEmpty);
      expect(c.active, Dialect.leadsFollows);
    });
  });
}
