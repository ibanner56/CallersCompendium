import 'package:compendium_app/src/data/custom_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CustomTheme', () {
    test('rolesFromScheme captures every editable role key', () {
      final roles = CustomTheme.rolesFromScheme(const ColorScheme.light());
      expect(roles.keys.toSet(), equals(CustomThemeRoles.keys));
    });

    test('toScheme applies stored roles over the brightness base', () {
      final theme = CustomTheme(
        id: 'x',
        name: 'X',
        brightness: Brightness.dark,
        roles: {
          'primary': const Color(0xFF112233).toARGB32(),
          'surface': const Color(0xFF0A0A0A).toARGB32(),
        },
      );
      final scheme = theme.toScheme();
      expect(scheme.brightness, Brightness.dark);
      expect(scheme.primary, const Color(0xFF112233));
      expect(scheme.surface, const Color(0xFF0A0A0A));
    });

    test('withColor returns a copy with the role updated', () {
      const base = CustomTheme(
        id: 'x',
        name: 'X',
        brightness: Brightness.light,
        roles: {},
      );
      final updated = base.withColor('primary', const Color(0xFFABCDEF));
      expect(base.roles.containsKey('primary'), isFalse);
      expect(updated.color('primary'), const Color(0xFFABCDEF));
    });

    test('JSON round-trip preserves id, name, brightness, and all roles', () {
      final original = CustomTheme(
        id: 'custom-42',
        name: 'Rosé Test',
        brightness: Brightness.dark,
        roles: CustomTheme.rolesFromScheme(const ColorScheme.dark()),
      );
      final restored = CustomTheme.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.brightness, original.brightness);
      expect(restored.roles, equals(original.roles));
      expect(restored.toScheme().primary, original.toScheme().primary);
    });

    test('fromJson drops unknown role keys', () {
      final json = {
        'id': 'x',
        'name': 'X',
        'brightness': 'light',
        'roles': {'primary': 0xFF000000, 'bogusRole': 0xFFFFFFFF},
      };
      final theme = CustomTheme.fromJson(json);
      expect(theme.roles.containsKey('primary'), isTrue);
      expect(theme.roles.containsKey('bogusRole'), isFalse);
    });

    test('role descriptors and contrast pairs reference valid keys', () {
      for (final pair in CustomThemeRoles.allPairs) {
        expect(CustomThemeRoles.keys, contains(pair.foreground));
        expect(CustomThemeRoles.keys, contains(pair.background));
      }
    });
  });
}
