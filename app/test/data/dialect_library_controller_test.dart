import 'package:compendium_app/src/data/dialect_library_controller.dart';
import 'package:compendium_app/src/data/program_dialect.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
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
  moveWordingBranches: const {
    'promenade': {
      'ordinary': '{who} {move} {direction} {destination}',
      'singleFile': '{prefix} {move} {direction} {destination}',
    },
  },
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
      expect(
        second.customByName('Mine')!.moveWordingBranches,
        _custom('Mine').moveWordingBranches,
      );
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

    group('rename carries to programs', () {
      final t0 = DateTime.utc(2026, 1, 1);
      final t1 = DateTime.utc(2026, 6, 1);

      Program program(String id, String? dialect, {DateTime? deletedAt}) =>
          Program(
            id: id,
            title: id,
            createdAt: t0,
            updatedAt: t0,
            deletedAt: deletedAt,
            dialectName: dialect,
          );

      test('live and trashed programs follow, others do not', () async {
        final repos = openTestRepositories();
        await repos.ensureMigrated();
        final c = DialectLibraryController(
          repos.settings,
          programs: repos.programs,
          clock: () => t1,
        );
        await c.load();
        await c.upsert(_custom('Mine'));
        await repos.programs.create(program('live', 'Mine'));
        await repos.programs.create(program('trashed', 'Mine', deletedAt: t0));
        await repos.programs.create(program('other', 'Else'));

        final name = await c.rename('Mine', 'Yours');

        expect(name, 'Yours');
        expect((await repos.programs.getById('live'))!.dialectName, 'Yours');
        expect(
          (await repos.programs.getById(
            'trashed',
            includeDeleted: true,
          ))!.dialectName,
          'Yours',
        );
        expect((await repos.programs.getById('other'))!.dialectName, 'Else');
        expect((await repos.programs.getById('live'))!.updatedAt, t1);
      });

      test('carries the uniquified name, not the requested one', () async {
        final repos = openTestRepositories();
        await repos.ensureMigrated();
        final c = DialectLibraryController(
          repos.settings,
          programs: repos.programs,
          clock: () => t1,
        );
        await c.load();
        await c.upsert(_custom('Mine'));
        await c.upsert(_custom('Taken'));
        await repos.programs.create(program('p', 'Mine'));

        final name = await c.rename('Mine', 'Taken');

        expect(name, 'Taken 2');
        expect((await repos.programs.getById('p'))!.dialectName, 'Taken 2');
      });

      test('delete still leaves programs on the old name', () async {
        final repos = openTestRepositories();
        await repos.ensureMigrated();
        final c = DialectLibraryController(
          repos.settings,
          programs: repos.programs,
        );
        await c.load();
        await c.upsert(_custom('Mine'));
        await repos.programs.create(program('p', 'Mine'));
        await c.delete('Mine');
        expect((await repos.programs.getById('p'))!.dialectName, 'Mine');
        expect(resolveProgramDialect('Mine', c), isNull);
      });

      // Dialects sync as the `custom_dialects` setting; programs sync as
      // records. Device B receives them independently and in either order; both
      // must end resolving the new name.
      for (final settingsFirst in [true, false]) {
        test('converges on a second device '
            '(${settingsFirst ? 'setting' : 'program'} first)', () async {
          driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
          final a = openTestRepositories();
          final b = openTestRepositories();
          await a.ensureMigrated();
          await b.ensureMigrated();
          final ca = DialectLibraryController(
            a.settings,
            programs: a.programs,
            clock: () => t1,
          );
          await ca.load();
          await ca.upsert(_custom('Mine'));
          await a.programs.create(program('p', 'Mine'));
          // B starts in sync with A's pre-rename state.
          await b.settings.set(
            kCustomDialectsKey,
            await a.settings.get(kCustomDialectsKey),
          );
          await b.programs.writeFromSync((await a.programs.getById('p'))!);

          await ca.rename('Mine', 'Yours');

          Future<void> deliverSetting() async => b.settings.set(
            kCustomDialectsKey,
            await a.settings.get(kCustomDialectsKey),
          );
          Future<void> deliverProgram() async =>
              b.programs.writeFromSync((await a.programs.getById('p'))!);
          if (settingsFirst) {
            await deliverSetting();
            await deliverProgram();
          } else {
            await deliverProgram();
            await deliverSetting();
          }

          final cb = DialectLibraryController(b.settings);
          await cb.load();
          final onB = await b.programs.getById('p');
          expect(onB!.dialectName, 'Yours');
          expect(resolveProgramDialect(onB.dialectName, cb)?.name, 'Yours');
        });
      }
    });
  });
}
