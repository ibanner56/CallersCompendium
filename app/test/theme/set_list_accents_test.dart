import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compendium_app/src/theme/palette_schemes.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

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
        formationFamilyOf(FormationShape.progressedImproper),
        FormationFamily.contraLongways,
      );
      expect(
        formationFamilyOf(FormationShape.reverseProgressionImproper),
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
          setListAccent(family, brightPalette: false),
          isNotNull,
          reason: 'light accent missing for $family',
        );
        expect(
          setListAccent(family, brightPalette: true),
          isNotNull,
          reason: 'bright accent missing for $family',
        );
      }
    });

    test('families are mutually distinguishable within a theme', () {
      for (final bright in [false, true]) {
        final colours = FormationFamily.values
            .map((f) => setListAccent(f, brightPalette: bright))
            .toList();
        expect(
          colours.toSet().length,
          colours.length,
          reason: 'duplicate accent colours (bright=$bright)',
        );
      }
    });

    test('bright palette differs from the light palette', () {
      for (final family in FormationFamily.values) {
        expect(
          setListAccent(family, brightPalette: true),
          isNot(setListAccent(family, brightPalette: false)),
          reason: 'bright accent equals light accent for $family',
        );
      }
    });

    test('setListAccentForShape resolves via the family mapping', () {
      expect(
        setListAccentForShape(
          FormationShape.dupleImproper,
          brightPalette: false,
        ),
        setListAccent(FormationFamily.contraLongways, brightPalette: false),
      );
    });
  });

  group('setListAccentForShapeAndMixer (issue #732)', () {
    test(
      'mixer=false delegates to formationFamilyOf — duple improper is contra',
      () {
        expect(
          setListAccentForShapeAndMixer(
            FormationShape.dupleImproper,
            false,
            brightPalette: false,
          ),
          setListAccent(FormationFamily.contraLongways, brightPalette: false),
        );
      },
    );

    test('mixer=true overrides formation — duple improper gets mixer accent, '
        'not contra teal', () {
      expect(
        setListAccentForShapeAndMixer(
          FormationShape.dupleImproper,
          true,
          brightPalette: false,
        ),
        setListAccent(FormationFamily.mixer, brightPalette: false),
      );
    });

    test(
      'mixer=true on circleMixer — gets mixer pink, not sicilianCircle green '
      '(circleMixer maps to sicilianCircle by shape alone)',
      () {
        // Regression: circleMixer → sicilianCircle by formationFamilyOf, but
        // a mixer-flagged circle mixer must still resolve to mixer pink.
        expect(
          formationFamilyOf(FormationShape.circleMixer),
          FormationFamily.sicilianCircle, // confirm the shape-only mapping
        );
        expect(
          setListAccentForShapeAndMixer(
            FormationShape.circleMixer,
            true,
            brightPalette: false,
          ),
          setListAccent(FormationFamily.mixer, brightPalette: false),
        );
      },
    );

    test('non-mixer Sicilian Circle keeps sicilianCircle green', () {
      // The negative pair: the 589 non-mixer Sicilian Circles must NOT get
      // mixer pink (that was the whole maintainer ruling).
      expect(
        setListAccentForShapeAndMixer(
          FormationShape.sicilianCircle,
          false,
          brightPalette: false,
        ),
        setListAccent(FormationFamily.sicilianCircle, brightPalette: false),
      );
      expect(
        setListAccentForShapeAndMixer(
          FormationShape.sicilianCircle,
          false,
          brightPalette: false,
        ),
        isNot(setListAccent(FormationFamily.mixer, brightPalette: false)),
      );
    });

    test('formationFamilyOf totality still holds after new functions', () {
      for (final shape in FormationShape.values) {
        expect(
          setListAccentForShapeAndMixer(shape, false, brightPalette: false),
          setListAccentForShape(shape, brightPalette: false),
        );
      }
    });
  });

  group('resolveFormationLabelColor', () {
    test('a per-shape override beats the family default', () {
      const override = Color(0xFFFFEB3B);
      expect(
        resolveFormationLabelColor(
          FormationShape.becketCw,
          overrides: const {FormationShape.becketCw: override},
          brightPalette: false,
        ),
        override,
      );
    });

    test('falls back to the family default when there is no override', () {
      expect(
        resolveFormationLabelColor(
          FormationShape.becketCw,
          overrides: const {},
          brightPalette: false,
        ),
        setListAccentForShape(FormationShape.becketCw, brightPalette: false),
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
          brightPalette: false,
        ),
        cw,
      );
      expect(
        resolveFormationLabelColor(
          FormationShape.becketCcw,
          overrides: overrides,
          brightPalette: false,
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

  group('setListAccentForRow (PRES-12)', () {
    const pink = Color(0xFFE91E63);

    test('the user colour beats the family tint for a non-mixer', () {
      expect(
        setListAccentForRow(
          FormationShape.becketCcw,
          false,
          userColor: pink,
          brightPalette: false,
        ),
        pink,
      );
    });

    test('an uncoloured shape keeps the family tint, per theme', () {
      for (final hc in [false, true]) {
        expect(
          setListAccentForRow(
            FormationShape.becketCcw,
            false,
            userColor: null,
            brightPalette: hc,
          ),
          setListAccent(FormationFamily.contraLongways, brightPalette: hc),
        );
      }
    });

    test('the mixer accent always wins over a user colour', () {
      for (final hc in [false, true]) {
        expect(
          setListAccentForRow(
            FormationShape.dupleImproper,
            true,
            userColor: pink,
            brightPalette: hc,
          ),
          setListAccent(FormationFamily.mixer, brightPalette: hc),
        );
      }
    });

    test(
      'the user colour is not swapped for a palette under high contrast',
      () {
        expect(
          setListAccentForRow(
            FormationShape.becketCcw,
            false,
            userColor: pink,
            brightPalette: true,
          ),
          pink,
        );
      },
    );
  });

  // Dark themes, not only high contrast, take the bright palette.
  group('setListAccentsBright', () {
    Future<bool> brightUnder(WidgetTester tester, ThemeData theme) async {
      late bool bright;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              bright = setListAccentsBright(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return bright;
    }

    testWidgets('light theme keeps the light palette', (tester) async {
      expect(await brightUnder(tester, AppTheme.light), isFalse);
    });

    testWidgets('dark theme takes the bright palette', (tester) async {
      expect(await brightUnder(tester, AppTheme.dark), isTrue);
    });

    testWidgets('a dark gallery palette takes the bright palette', (
      tester,
    ) async {
      expect(
        await brightUnder(tester, AppTheme.fromScheme(GalleryPalettes.nord)),
        isTrue,
      );
    });
  });
}
