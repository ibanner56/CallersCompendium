import 'package:compendium_app/src/data/formation_colors_controller.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

Future<FormationColorsController> _controller(
  CompendiumRepositories repos,
) async {
  await repos.ensureMigrated();
  final controller = FormationColorsController(repos.settings);
  await controller.load();
  return controller;
}

void main() {
  group('formationColorOverridesFromStored (OWASP input hygiene)', () {
    test('non-Map / null input yields an empty map', () {
      expect(formationColorOverridesFromStored(null), isEmpty);
      expect(formationColorOverridesFromStored('nope'), isEmpty);
      expect(formationColorOverridesFromStored(42), isEmpty);
      expect(formationColorOverridesFromStored(<Object?>['a', 'b']), isEmpty);
    });

    test('keeps only exact FormationShape.name keys, ignoring unknown', () {
      final parsed = formationColorOverridesFromStored({
        'becketCw': 0xFFFFEB3B,
        'becketCW': 0xFF000000, // wrong case ⇒ unknown ⇒ ignored
        'not_a_shape': 0xFF123456,
        'removedShape': 0xFF654321,
      });
      expect(parsed.keys, [FormationShape.becketCw]);
    });

    test('rejects non-int, fractional, negative, and oversized values', () {
      final parsed = formationColorOverridesFromStored({
        'becketCw': 'red', // non-numeric
        'becketCcw': 1.5, // fractional
        'dupleProper': -1, // negative
        'dupleImproper': 0x1FFFFFFFF, // > 32-bit
      });
      expect(parsed, isEmpty);
    });

    test('forces full opacity so a 0-alpha value can never be invisible', () {
      final parsed = formationColorOverridesFromStored({
        'becketCw': 0x00FFEB3B, // stored transparent
      });
      expect(parsed[FormationShape.becketCw]!.toARGB32(), 0xFFFFEB3B);
    });

    test('a partial/mixed map keeps only the valid entries, never throws', () {
      final parsed = formationColorOverridesFromStored({
        'becketCw': 0xFFFFEB3B, // valid
        'becketCcw': 'pink', // invalid
        123: 0xFF00FF00, // non-string key
      });
      expect(parsed, {FormationShape.becketCw: const Color(0xFFFFEB3B)});
    });

    test('round-trips through encode → store → decode', () {
      const overrides = {
        FormationShape.becketCw: Color(0xFFFFEB3B),
        FormationShape.becketCcw: Color(0xFFFF80AB),
      };
      final encoded = encodeFormationColorOverrides(overrides);
      expect(formationColorOverridesFromStored(encoded), overrides);
    });
  });

  group('FormationColorsController', () {
    test('starts empty', () async {
      final repos = openTestRepositories();
      final c = await _controller(repos);
      expect(c.overrides, isEmpty);
      expect(c.overrideFor(FormationShape.becketCw), isNull);
    });

    test('setColor persists (forced opaque) and reloads', () async {
      final repos = openTestRepositories();
      final c = await _controller(repos);
      await c.setColor(FormationShape.becketCw, const Color(0x00FFEB3B));
      expect(c.overrideFor(FormationShape.becketCw), const Color(0xFFFFEB3B));

      // A fresh controller over the same store sees the persisted override.
      final reloaded = FormationColorsController(repos.settings);
      await reloaded.load();
      expect(
        reloaded.overrideFor(FormationShape.becketCw),
        const Color(0xFFFFEB3B),
      );
    });

    test('clearColor removes the override and reverts to default', () async {
      final repos = openTestRepositories();
      final c = await _controller(repos);
      await c.setColor(FormationShape.becketCcw, const Color(0xFFFF80AB));
      await c.clearColor(FormationShape.becketCcw);
      expect(c.overrideFor(FormationShape.becketCcw), isNull);

      final reloaded = FormationColorsController(repos.settings);
      await reloaded.load();
      expect(reloaded.overrideFor(FormationShape.becketCcw), isNull);
    });

    test('load degrades to empty on a corrupt stored payload', () async {
      final repos = openTestRepositories();
      await repos.ensureMigrated();
      await repos.settings.set(kFormationColorOverridesKey, 'garbage');
      final c = FormationColorsController(repos.settings);
      await c.load();
      expect(c.overrides, isEmpty);
    });
  });
}
