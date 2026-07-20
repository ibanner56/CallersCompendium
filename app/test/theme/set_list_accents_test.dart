import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/theme/set_list_accents.dart';
import 'package:compendium_app/src/theme/wcag.dart';

void main() {
  group('formationFamilyOf', () {
    test('maps every FormationShape to a family', () {
      for (final shape in FormationShape.values) {
        // Total switch: this simply must not throw for any value.
        expect(formationFamilyOf(shape), isA<FormationFamily>());
      }
    });

    test('groups shapes into the expected families', () {
      expect(
        formationFamilyOf(FormationShape.dupleImproper),
        FormationFamily.contraLongways,
      );
      expect(
        formationFamilyOf(FormationShape.becketCw),
        FormationFamily.contraLongways,
      );
      expect(
        formationFamilyOf(FormationShape.tripleMinor),
        FormationFamily.triple,
      );
      expect(formationFamilyOf(FormationShape.triplet), FormationFamily.triple);
      expect(
        formationFamilyOf(FormationShape.scatterMixer),
        FormationFamily.mixer,
      );
      expect(
        formationFamilyOf(FormationShape.circleMixer),
        FormationFamily.sicilianCircle,
      );
      expect(
        formationFamilyOf(FormationShape.sicilianCircle),
        FormationFamily.sicilianCircle,
      );
      expect(
        formationFamilyOf(FormationShape.fourFaceFour),
        FormationFamily.bigSetSquare,
      );
      expect(
        formationFamilyOf(FormationShape.grid),
        FormationFamily.bigSetSquare,
      );
      expect(formationFamilyOf(FormationShape.other), FormationFamily.other);
    });
  });

  group('setListAccent palette', () {
    test('resolves a colour for every family in both themes', () {
      for (final family in FormationFamily.values) {
        expect(
          setListAccent(family, highContrast: false),
          isNotNull,
          reason: 'light accent missing for $family',
        );
        expect(
          setListAccent(family, highContrast: true),
          isNotNull,
          reason: 'high-contrast accent missing for $family',
        );
      }
    });

    test('families are mutually distinguishable within a theme', () {
      for (final highContrast in [false, true]) {
        final colours = FormationFamily.values
            .map((f) => setListAccent(f, highContrast: highContrast))
            .toList();
        expect(
          colours.toSet().length,
          colours.length,
          reason: 'duplicate accent colours (highContrast=$highContrast)',
        );
      }
    });

    test('high-contrast palette differs from the light palette', () {
      for (final family in FormationFamily.values) {
        expect(
          setListAccent(family, highContrast: true),
          isNot(setListAccent(family, highContrast: false)),
          reason: 'high-contrast accent equals light accent for $family',
        );
      }
    });

    test('setListAccentForShape resolves via the family mapping', () {
      expect(
        setListAccentForShape(
          FormationShape.dupleImproper,
          highContrast: false,
        ),
        setListAccent(FormationFamily.contraLongways, highContrast: false),
      );
    });
  });

  group('resolveFormationLabelColor', () {
    test('a per-shape override beats the family default', () {
      const override = Color(0xFFFFEB3B);
      expect(
        resolveFormationLabelColor(
          FormationShape.becketCw,
          overrides: const {FormationShape.becketCw: override},
          highContrast: false,
        ),
        override,
      );
    });

    test('falls back to the family default when there is no override', () {
      expect(
        resolveFormationLabelColor(
          FormationShape.becketCw,
          overrides: const {},
          highContrast: false,
        ),
        setListAccentForShape(FormationShape.becketCw, highContrast: false),
      );
    });

    test('two same-family shapes can resolve to different colours', () {
      // Becket CW and CCW share a family (so the same default), but per-shape
      // overrides let them differ — the core of issue #367.
      const cw = Color(0xFFFFEB3B); // yellow
      const ccw = Color(0xFFFF80AB); // pink
      const overrides = {
        FormationShape.becketCw: cw,
        FormationShape.becketCcw: ccw,
      };
      expect(
        formationFamilyOf(FormationShape.becketCw),
        formationFamilyOf(FormationShape.becketCcw),
      );
      expect(
        resolveFormationLabelColor(
          FormationShape.becketCw,
          overrides: overrides,
          highContrast: false,
        ),
        cw,
      );
      expect(
        resolveFormationLabelColor(
          FormationShape.becketCcw,
          overrides: overrides,
          highContrast: false,
        ),
        ccw,
      );
    });
  });

  group('readableForegroundOn', () {
    test('a light background gets a dark (black) foreground', () {
      final fg = readableForegroundOn(const Color(0xFFFFEB3B)); // light yellow
      expect(fg, const Color(0xFF000000));
      expect(Wcag.meetsAA(fg, const Color(0xFFFFEB3B)), isTrue);
    });

    test('a dark background gets a light (white) foreground', () {
      final fg = readableForegroundOn(const Color(0xFF1A237E)); // deep indigo
      expect(fg, const Color(0xFFFFFFFF));
      expect(Wcag.meetsAA(fg, const Color(0xFF1A237E)), isTrue);
    });
  });
}
