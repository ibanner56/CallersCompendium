import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/theme/set_list_accents.dart';

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
}
