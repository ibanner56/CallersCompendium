import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('danceDetailRenderingFromStored', () {
    test('round-trips every rendering via .name', () {
      for (final rendering in DanceDetailRendering.values) {
        expect(danceDetailRenderingFromStored(rendering.name), rendering);
      }
    });

    test(
      'falls back to activeDialect for null, non-strings, unknown names',
      () {
        expect(
          danceDetailRenderingFromStored(null),
          DanceDetailRendering.activeDialect,
        );
        expect(
          danceDetailRenderingFromStored(7),
          DanceDetailRendering.activeDialect,
        );
        expect(
          danceDetailRenderingFromStored('nope'),
          DanceDetailRendering.activeDialect,
        );
      },
    );
  });

  group('program defaults keys (G.3)', () {
    test('use their stable stored key strings', () {
      expect(kDefaultProgramCallerKey, 'default_program_caller');
      expect(kDefaultProgramBandKey, 'default_program_band');
    });
  });

  group('dance-authoring defaults keys (DD.1)', () {
    test('use their stable stored key strings', () {
      expect(kDefaultDanceFormKey, 'default_dance_form');
      expect(kDefaultDanceFormationShapeKey, 'default_dance_formation_shape');
      expect(kDefaultDanceProgressionKey, 'default_dance_progression');
      expect(kDefaultDancePhraseStructureKey, 'default_dance_phrase_structure');
    });
  });

  group('danceFormFromStored', () {
    test('round-trips every form via .name', () {
      for (final form in DanceForm.values) {
        expect(danceFormFromStored(form.name), form);
      }
    });

    test('falls back to contra for null, non-strings, unknown names', () {
      expect(danceFormFromStored(null), DanceForm.contra);
      expect(danceFormFromStored(7), DanceForm.contra);
      expect(danceFormFromStored('nope'), DanceForm.contra);
    });
  });

  group('formationShapeFromStored', () {
    test('round-trips every shape via .name', () {
      for (final shape in FormationShape.values) {
        expect(formationShapeFromStored(shape.name), shape);
      }
    });

    test(
      'falls back to dupleImproper for null, non-strings, unknown names',
      () {
        expect(formationShapeFromStored(null), FormationShape.dupleImproper);
        expect(formationShapeFromStored(7), FormationShape.dupleImproper);
        expect(formationShapeFromStored('nope'), FormationShape.dupleImproper);
      },
    );
  });

  group('progressionFromStored', () {
    test('round-trips every progression via .name', () {
      for (final progression in Progression.values) {
        expect(progressionFromStored(progression.name), progression);
      }
    });

    test('falls back to single for null, non-strings, unknown names', () {
      expect(progressionFromStored(null), Progression.single);
      expect(progressionFromStored(7), Progression.single);
      expect(progressionFromStored('nope'), Progression.single);
    });
  });

  group('dancePhraseStructureRawFromStored', () {
    test('returns the stored raw string verbatim', () {
      expect(dancePhraseStructureRawFromStored('6*8*2'), '6*8*2');
      expect(dancePhraseStructureRawFromStored(''), '');
      // A stored raw string round-trips through the core parser.
      expect(PhraseStructure.parse('6*8*2').raw, '6*8*2');
    });

    test('falls back to standard ("") for null and non-strings', () {
      expect(dancePhraseStructureRawFromStored(null), '');
      expect(dancePhraseStructureRawFromStored(7), '');
      // '' parses to the standard 4×16 structure.
      expect(PhraseStructure.parse(''), PhraseStructure.standard);
    });
  });
}
