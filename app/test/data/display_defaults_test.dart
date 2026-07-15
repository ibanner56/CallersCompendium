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
    test('the default template is eight stand_still figures', () {
      final template = defaultNewDanceFigureTemplate();
      expect(template, hasLength(8));
      for (final figure in template) {
        expect(figure.move, 'stand_still');
        expect(figure.params['beats'], 8);
      }
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
        expect(template, hasLength(8));
        for (final figure in template) {
          expect(figure.move, 'stand_still');
          expect(figure.params['beats'], 8);
        }
      }
    });
  });

  group('move param overrides (DD.3)', () {
    test('key uses its stable stored string', () {
      expect(kDefaultMoveParamOverridesKey, 'default_move_param_overrides');
    });

    test('encode/decode round-trips a realistic diff map', () {
      final map = <String, Map<String, Object?>>{
        'circle': {'turn': 'right', 'places': 3},
        'hey': {'length': 'half'},
        'swing': {'beats': 16},
      };
      final restored = moveParamOverridesFromStored(
        encodeMoveParamOverrides(map),
      );
      expect(restored, map);
    });

    test('null / empty / non-string / garbage decode to an empty map', () {
      for (final stored in [null, '', 7, 'not json', '[1,2,3]', '"str"']) {
        expect(moveParamOverridesFromStored(stored), isEmpty);
      }
    });

    test('drops top-level entries whose value is not a JSON object', () {
      final restored = moveParamOverridesFromStored(
        '{"circle":{"turn":"right"},"bad":5,"also_bad":[1]}',
      );
      expect(restored.keys, ['circle']);
      expect(restored['circle'], {'turn': 'right'});
    });

    test('treats an empty inner map as absent (drops it on decode)', () {
      final restored = moveParamOverridesFromStored(
        '{"circle":{},"swing":{"beats":16}}',
      );
      expect(restored.keys, ['swing']);
    });

    test('drops empty inner maps on encode', () {
      final encoded = encodeMoveParamOverrides({
        'circle': {},
        'swing': {'beats': 16},
      });
      expect(moveParamOverridesFromStored(encoded), {
        'swing': {'beats': 16},
      });
    });

    test('returns mutable maps callers can edit in place', () {
      final restored = moveParamOverridesFromStored(
        '{"circle":{"turn":"right"}}',
      );
      restored['circle']!['places'] = 3;
      restored['swing'] = {'beats': 16};
      expect(restored['circle'], {'turn': 'right', 'places': 3});
    });
  });
}
