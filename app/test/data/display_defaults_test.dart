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

  group('dance figures template (DD.2)', () {
    test('the default template is a single stand_still x8', () {
      final template = defaultNewDanceFigureTemplate();
      expect(template, hasLength(1));
      expect(template.single.move, 'stand_still');
      expect(template.single.params['beats'], 8);
    });

    test('round-trips a real encodeFigures string', () {
      final figures = [
        Figure(move: 'balance', params: const {'who': 'neighbors', 'beats': 4}),
        Figure(move: 'swing', params: const {'who': 'neighbors', 'beats': 12}),
      ];
      final restored = danceFiguresTemplateFromStored(encodeFigures(figures));
      expect(restored, hasLength(2));
      expect(restored[0].move, 'balance');
      expect(restored[0].params['beats'], 4);
      expect(restored[1].move, 'swing');
      expect(restored[1].params['beats'], 12);
    });

    test('decodes "[]" to an intentional empty template', () {
      expect(danceFiguresTemplateFromStored('[]'), isEmpty);
    });

    test('falls back to the default for null, non-string, empty, garbage', () {
      for (final stored in [null, 7, '', 'not json', '{"move":"x"}']) {
        final template = danceFiguresTemplateFromStored(stored);
        expect(template, hasLength(1));
        expect(template.single.move, 'stand_still');
        expect(template.single.params['beats'], 8);
      }
    });
  });
}
