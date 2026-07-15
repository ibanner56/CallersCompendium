import 'package:compendium_app/src/data/custom_theme.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

Future<CustomThemesController> _controller() async {
  final repos = openTestRepositories();
  await repos.ensureMigrated();
  final controller = CustomThemesController(repos.settings);
  await controller.load();
  return controller;
}

CustomTheme _sample(String name, Brightness brightness) => CustomTheme(
  id: '',
  name: name,
  brightness: brightness,
  roles: CustomTheme.rolesFromScheme(
    brightness == Brightness.dark
        ? const ColorScheme.dark()
        : const ColorScheme.light(),
  ),
);

void main() {
  group('CustomThemesController', () {
    test('starts empty with no active theme', () async {
      final c = await _controller();
      expect(c.themes, isEmpty);
      expect(c.activeId, isNull);
      expect(c.hasActive, isFalse);
    });

    test(
      'duplicate adds a theme with a fresh id but does not activate',
      () async {
        final c = await _controller();
        final s = _sample('Mine', Brightness.light);
        final created = await c.duplicate(
          name: s.name,
          brightness: s.brightness,
          roles: s.roles,
        );
        expect(created.id, isNotEmpty);
        expect(c.themes, hasLength(1));
        expect(c.activeId, isNull);
      },
    );

    test('duplicate gives copies a distinct, unique name', () async {
      final c = await _controller();
      final s = _sample('Mine', Brightness.light);
      await c.duplicate(name: 'Mine', brightness: s.brightness, roles: s.roles);
      await c.duplicate(name: 'Mine', brightness: s.brightness, roles: s.roles);
      final names = c.themes.map((t) => t.name).toList();
      expect(names, ['Mine', 'Mine 2']);
    });

    test('setActive makes a custom theme win; null reverts', () async {
      final c = await _controller();
      final s = _sample('Mine', Brightness.dark);
      final created = await c.duplicate(
        name: s.name,
        brightness: s.brightness,
        roles: s.roles,
      );
      await c.setActive(created.id);
      expect(c.hasActive, isTrue);
      expect(c.active?.id, created.id);
      await c.setActive(null);
      expect(c.hasActive, isFalse);
    });

    test('setActive ignores unknown ids', () async {
      final c = await _controller();
      await c.setActive('does-not-exist');
      expect(c.activeId, isNull);
    });

    test('deleting the active theme reverts to built-in', () async {
      final c = await _controller();
      final s = _sample('Mine', Brightness.light);
      final created = await c.duplicate(
        name: s.name,
        brightness: s.brightness,
        roles: s.roles,
      );
      await c.setActive(created.id);
      await c.delete(created.id);
      expect(c.themes, isEmpty);
      expect(c.hasActive, isFalse);
    });

    test('upsert replaces an existing theme by id', () async {
      final c = await _controller();
      final s = _sample('Mine', Brightness.light);
      final created = await c.duplicate(
        name: s.name,
        brightness: s.brightness,
        roles: s.roles,
      );
      await c.upsert(created.copyWith(name: 'Renamed'));
      expect(c.themes, hasLength(1));
      expect(c.themes.single.name, 'Renamed');
    });

    test('themes and active id persist across a reload', () async {
      final repos = openTestRepositories();
      await repos.ensureMigrated();
      final first = CustomThemesController(repos.settings);
      await first.load();
      final s = _sample('Persisted', Brightness.dark);
      final created = await first.duplicate(
        name: s.name,
        brightness: s.brightness,
        roles: s.roles,
      );
      await first.setActive(created.id);

      final second = CustomThemesController(repos.settings);
      await second.load();
      expect(second.themes, hasLength(1));
      expect(second.themes.single.name, 'Persisted');
      expect(second.hasActive, isTrue);
      expect(second.active?.id, created.id);
    });
  });
}
