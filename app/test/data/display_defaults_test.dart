import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/search/collection_query.dart';
import 'package:compendium_app/src/search/program_sort.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

void main() {
  group('danceDetailRenderingFromStored', () {
    test('round-trips every rendering via .name', () {
      for (final rendering in DanceDetailRendering.values) {
        expect(danceDetailRenderingFromStored(rendering.name), rendering);
      }
    });

    group('canonical figure text gate initialization', () {
      test(
        'initializes absent gate and resets a legacy canonical child',
        () async {
          final repos = openTestRepositories();
          await repos.settings.set(
            kDefaultDanceDetailRenderingKey,
            DanceDetailRendering.canonical.name,
          );

          await initializeCanonicalFigureTextGate(repos.settings);

          expect(await repos.settings.get(kCanonicalFigureTextKey), isFalse);
          expect(
            await repos.settings.get(kDefaultDanceDetailRenderingKey),
            DanceDetailRendering.activeDialect.name,
          );
        },
      );

      test('does not reset the child when the gate is already false', () async {
        final repos = openTestRepositories();
        await repos.settings.set(kCanonicalFigureTextKey, false);
        await repos.settings.set(
          kDefaultDanceDetailRenderingKey,
          DanceDetailRendering.canonical.name,
        );

        await initializeCanonicalFigureTextGate(repos.settings);

        expect(
          await repos.settings.get(kDefaultDanceDetailRenderingKey),
          DanceDetailRendering.canonical.name,
        );
      });

      test('preserves canonical child when the gate is enabled', () async {
        final repos = openTestRepositories();
        await repos.settings.set(kCanonicalFigureTextKey, true);
        await repos.settings.set(
          kDefaultDanceDetailRenderingKey,
          DanceDetailRendering.canonical.name,
        );

        await initializeCanonicalFigureTextGate(repos.settings);

        expect(
          await repos.settings.get(kDefaultDanceDetailRenderingKey),
          DanceDetailRendering.canonical.name,
        );
      });

      test(
        'malformed present gate is not treated as first initialization',
        () async {
          final repos = openTestRepositories();
          await repos.settings.set(kCanonicalFigureTextKey, 'invalid');
          await repos.settings.set(
            kDefaultDanceDetailRenderingKey,
            DanceDetailRendering.canonical.name,
          );

          await initializeCanonicalFigureTextGate(repos.settings);

          expect(await repos.settings.get(kCanonicalFigureTextKey), 'invalid');
          expect(
            await repos.settings.get(kDefaultDanceDetailRenderingKey),
            DanceDetailRendering.canonical.name,
          );
        },
      );
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

  group('sort default keys (issue #895)', () {
    test('use their stable stored key strings', () {
      expect(kDefaultProgramSortKey, 'default_program_sort');
      expect(kLastUsedCollectionSortKey, 'last_used_collection_sort');
      expect(
        kLastUsedCollectionSortDirectionKey,
        'last_used_collection_sort_direction',
      );
      expect(kLastUsedProgramSortKey, 'last_used_program_sort');
      expect(
        kLastUsedProgramSortDirectionKey,
        'last_used_program_sort_direction',
      );
      expect(kLastUsedSortSentinel, 'last_used');
    });
  });

  group('SortDefaultSetting equality (issue #895)', () {
    test('two concrete settings are equal iff their sort matches', () {
      expect(
        const SortDefaultSetting.concrete(CollectionSort.title),
        const SortDefaultSetting.concrete(CollectionSort.title),
      );
      expect(
        const SortDefaultSetting.concrete(CollectionSort.title),
        isNot(const SortDefaultSetting.concrete(CollectionSort.author)),
      );
    });

    test('every "Last used" entry is equal regardless of its fallback sort — '
        'required for DropdownButton to highlight the right item by ==', () {
      expect(
        const SortDefaultSetting.lastUsed(CollectionSort.title),
        const SortDefaultSetting.lastUsed(CollectionSort.author),
      );
      expect(
        const SortDefaultSetting.lastUsed(CollectionSort.title).hashCode,
        const SortDefaultSetting.lastUsed(CollectionSort.author).hashCode,
      );
    });

    test('a concrete setting is never equal to a "Last used" one', () {
      expect(
        const SortDefaultSetting.concrete(CollectionSort.title),
        isNot(const SortDefaultSetting.lastUsed(CollectionSort.title)),
      );
    });

    test('a CollectionSort setting and a same-named ProgramSort setting are '
        'distinct types and never equal', () {
      expect(
        // ignore: unrelated_type_equality_checks
        const SortDefaultSetting.concrete(CollectionSort.title) ==
            const SortDefaultSetting.concrete(ProgramSort.title),
        isFalse,
      );
    });
  });

  group(
    'sortDefaultSettingFromStored / encodeSortDefaultSetting (issue #895)',
    () {
      test(
        'the sentinel resolves to lastUsed regardless of the resolver/fallback',
        () {
          final mode = sortDefaultSettingFromStored(
            kLastUsedSortSentinel,
            collectionSortFromName,
            CollectionSort.title,
          );
          expect(mode.isLastUsed, isTrue);
        },
      );

      test(
        'round-trips every non-relevance CollectionSort via encode/decode',
        () {
          for (final sort in CollectionSort.values) {
            if (sort == CollectionSort.relevance) continue;
            final mode = SortDefaultSetting.concrete(sort);
            final decoded = sortDefaultSettingFromStored(
              encodeSortDefaultSetting(mode),
              collectionSortFromName,
              CollectionSort.title,
            );
            expect(decoded.isLastUsed, isFalse);
            expect(decoded.sort, sort);
          }
        },
      );

      test('round-trips every ProgramSort via encode/decode', () {
        for (final sort in ProgramSort.values) {
          final mode = SortDefaultSetting.concrete(sort);
          final decoded = sortDefaultSettingFromStored(
            encodeSortDefaultSetting(mode),
            programSortFromName,
            ProgramSort.title,
          );
          expect(decoded.isLastUsed, isFalse);
          expect(decoded.sort, sort);
        }
      });

      test('encodes lastUsed to the sentinel, never a sort name', () {
        expect(
          encodeSortDefaultSetting(
            const SortDefaultSetting.lastUsed(CollectionSort.title),
          ),
          kLastUsedSortSentinel,
        );
      });

      test('falls back to the historical default for null, non-strings, and '
          'unknown names — never throws', () {
        for (final stored in [null, 3, 'not-a-sort']) {
          final mode = sortDefaultSettingFromStored(
            stored,
            collectionSortFromName,
            CollectionSort.title,
          );
          expect(mode.isLastUsed, isFalse);
          expect(mode.sort, CollectionSort.title);
        }
      });

      test('a stored CollectionSort.relevance is never resolved as a concrete '
          'default (the resolver it delegates to excludes it)', () {
        final mode = sortDefaultSettingFromStored(
          CollectionSort.relevance.name,
          collectionSortFromName,
          CollectionSort.title,
        );
        expect(mode.isLastUsed, isFalse);
        expect(mode.sort, CollectionSort.title);
      });
    },
  );

  group('sortDirectionFromName (issue #895)', () {
    test('round-trips every direction via .name', () {
      for (final direction in SortDirection.values) {
        expect(sortDirectionFromName(direction.name), direction);
      }
    });

    test('returns null for null, non-strings, and unknown names', () {
      expect(sortDirectionFromName(null), isNull);
      expect(sortDirectionFromName(3), isNull);
      expect(sortDirectionFromName('sideways'), isNull);
    });
  });
}
