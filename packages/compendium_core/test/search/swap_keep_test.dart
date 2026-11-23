import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

import 'filter_describe.dart';

/// The **Keep** seed of Perform's swap sheet (#2346): each item, built from
/// the dance being swapped, becomes the Filters/Advanced panel state the
/// picker searches with. Each test names the one piece of the builder it
/// would catch being dropped.
void main() {
  final stamp = DateTime.utc(2026, 1, 1);

  Figure fig(String move, int beats) =>
      testFigure(move: move, params: {'beats': beats});

  // A standard 64-beat contra: A1 0–15, A2 16–31, B1 32–47, B2 48–63.
  // B1 opens with a balance-and-swing sequence, as many transcriptions keep it.
  final contraFigures = [
    fig('do_si_do', 8), // 0  A1
    fig('swing', 8), //    1  A1
    fig('circle', 8), //   2  A2
    fig('hey', 8), //      3  A2
    Figure.sequence(
      figures: [fig('balance', 4), fig('swing', 12)],
      beats: 16,
    ), //                  4 balance B1, 5 swing B1
    fig('long_lines', 8), // 6 B2
    fig('allemande', 8), //  7 B2
  ];

  Dance dance({
    DanceForm form = DanceForm.contra,
    FormationShape shape = FormationShape.becketCw,
    String? level,
    List<Figure>? figures,
  }) => Dance(
    id: 'd',
    title: 'Swapped',
    form: form,
    formation: Formation(shape),
    figures: figures ?? contraFigures,
    difficultyLevelId: level,
    createdAt: stamp,
    updatedAt: stamp,
  );

  final levels = [
    DifficultyLevel.advanced,
    DifficultyLevel.beginner,
    DifficultyLevel.intermediate,
  ];

  SwapKeepSeed seedOf(Dance d, {bool mixed = false}) =>
      SwapKeepSeed.of(d, levels: levels, programMixesTypes: mixed);

  String filterOf(SwapKeepSeed seed, SwapKeepChoices choices) {
    final state = swapKeepPanelState(seed, choices);
    return describeFilter(
      buildCollectionFilter(
        ftsText: state.text,
        facets: state.facets,
        defs: const [],
        byPhrase: state.byPhrase,
        advancedRoot: state.advanced,
      ),
    );
  }

  int indexOf(SwapKeepSeed seed, String move, {int nth = 0}) =>
      seed.figures.where((f) => f.move == move).elementAt(nth).index;

  group('contra', () {
    test('Same formation keeps the dance\'s shape', () {
      final seed = seedOf(dance());
      expect(seed.formation, FormationShape.becketCw);
      final state = swapKeepPanelState(seed, const SwapKeepChoices());
      expect(state.facets.formations, {FormationShape.becketCw});
      expect(
        filterOf(seed, const SwapKeepChoices(levelOrEasier: false)),
        'formation(becketCw)',
      );
      expect(
        swapKeepPanelState(
          seed,
          const SwapKeepChoices(formation: false),
        ).facets.formations,
        isEmpty,
      );
    });

    test('This level or easier keeps every level at or below the dance\'s, '
        'by position', () {
      final seed = seedOf(dance(level: DifficultyLevel.intermediateId));
      expect(seed.levelIds, {
        DifficultyLevel.beginnerId,
        DifficultyLevel.intermediateId,
      });
      final state = swapKeepPanelState(seed, const SwapKeepChoices());
      expect(state.facets.levels, {
        DifficultyLevel.beginnerId,
        DifficultyLevel.intermediateId,
      });
      expect(
        filterOf(seed, const SwapKeepChoices(formation: false)),
        'or(level(${DifficultyLevel.beginnerId}|eq), '
        'level(${DifficultyLevel.intermediateId}|eq))',
      );
    });

    test('a dance without a level adds no level item', () {
      final seed = seedOf(dance());
      expect(seed.levelIds, isEmpty);
      expect(
        swapKeepPanelState(seed, const SwapKeepChoices()).facets.levels,
        isEmpty,
      );
    });

    test('a level not on the scale adds no level item', () {
      final seed = seedOf(dance(level: 'difficulty-gone'));
      expect(seed.levelIds, isEmpty);
    });

    test('Same type is offered only in a program that mixes types', () {
      final plain = seedOf(dance());
      expect(plain.form, isNull);
      expect(
        swapKeepPanelState(plain, const SwapKeepChoices()).facets.forms,
        isEmpty,
      );
      final mixed = seedOf(dance(), mixed: true);
      expect(mixed.form, DanceForm.contra);
      expect(swapKeepPanelState(mixed, const SwapKeepChoices()).facets.forms, {
        DanceForm.contra,
      });
      expect(
        filterOf(mixed, const SwapKeepChoices(formation: false)),
        'form(contra)',
      );
    });

    test('figures are offered in phrase order, one per leaf, sequence steps '
        'included', () {
      final seed = seedOf(dance());
      expect(
        [for (final f in seed.figures) f.move],
        [
          'do_si_do',
          'swing',
          'circle',
          'hey',
          'balance',
          'swing',
          'long_lines',
          'allemande',
        ],
      );
      expect(
        [for (final f in seed.figures) f.section],
        ['A1', 'A1', 'A2', 'A2', 'B1', 'B1', 'B2', 'B2'],
      );
      // No figure is kept until the caller taps one.
      expect(filterOf(seed, const SwapKeepChoices(formation: false)), 'and()');
    });

    test('a kept figure asks for its move anywhere', () {
      final seed = seedOf(dance());
      final choices = const SwapKeepChoices(
        formation: false,
      ).withFigure(indexOf(seed, 'hey'), const SwapFigureKeep());
      expect(filterOf(seed, choices), 'figure(leaf(hey|null|))');
    });

    test('In the same phrase sets the leaf\'s section', () {
      final seed = seedOf(dance());
      final choices = const SwapKeepChoices(formation: false).withFigure(
        indexOf(seed, 'hey'),
        const SwapFigureKeep(samePhrase: true),
      );
      expect(filterOf(seed, choices), 'figure(leaf(hey|A2|))');
    });

    test('With what comes before it is a then row after the figure before '
        'it', () {
      final seed = seedOf(dance());
      final choices = const SwapKeepChoices(formation: false).withFigure(
        indexOf(seed, 'hey'),
        const SwapFigureKeep(withBefore: true),
      );
      expect(
        filterOf(seed, choices),
        'then(leaf(circle|null|) -> leaf(hey|null|))',
      );
    });

    test('both refinements together: the figure before it, then this one in '
        'its phrase; a sequence step follows the step before it', () {
      final seed = seedOf(dance());
      final choices = const SwapKeepChoices(formation: false).withFigure(
        indexOf(seed, 'swing', nth: 1),
        const SwapFigureKeep(samePhrase: true, withBefore: true),
      );
      expect(
        filterOf(seed, choices),
        'then(leaf(balance|null|) -> leaf(swing|B1|))',
      );
    });

    test('the first figure follows the last, as the dance loops', () {
      final seed = seedOf(dance());
      expect(seed.figures.first.beforeMove, 'allemande');
    });

    test('a dance of one figure offers no figure before it', () {
      final seed = seedOf(dance(figures: [fig('circle', 64)]));
      expect(seed.figures.single.beforeMove, isNull);
    });

    test('a refinement a figure does not offer is ignored', () {
      final seed = seedOf(dance(figures: [fig('circle', 64)]));
      final choices = const SwapKeepChoices(
        formation: false,
      ).withFigure(0, const SwapFigureKeep(withBefore: true));
      expect(filterOf(seed, choices), 'figure(leaf(circle|null|))');
    });

    test('a figure no longer kept leaves the search', () {
      final seed = seedOf(dance());
      final index = indexOf(seed, 'hey');
      final choices = const SwapKeepChoices(
        formation: false,
      ).withFigure(index, const SwapFigureKeep()).withFigure(index, null);
      expect(filterOf(seed, choices), 'and()');
    });

    test('the defaults choose which seeded items start on', () {
      final choices = SwapKeepChoices.fromDefaults(
        PerformSwapDefaults.defaults
            .withItem(PerformSwapKeepItem.formation, false)
            .withItem(PerformSwapKeepItem.notInProgram, false),
      );
      expect(choices.formation, isFalse);
      expect(choices.levelOrEasier, isTrue);
      expect(choices.sameType, isTrue);
      expect(choices.notInProgram, isFalse);
      expect(choices.figures, isEmpty);
    });

    test('each call builds a fresh state, so a picker editing one cannot '
        'change the next', () {
      final seed = seedOf(dance());
      final first = swapKeepPanelState(seed, const SwapKeepChoices());
      first.facets.formations.clear();
      expect(
        swapKeepPanelState(seed, const SwapKeepChoices()).facets.formations,
        {FormationShape.becketCw},
      );
    });
  });

  group('square', () {
    test('a square keeps its figures\' refinements, as contra\'s', () {
      final seed = seedOf(
        dance(
          form: DanceForm.square,
          shape: FormationShape.square,
          figures: [fig('circle', 8), fig('swing', 8)],
        ),
      );
      expect(seed.formation, FormationShape.square);
      expect(seed.figures.last.beforeMove, 'circle');
      expect(seed.figures.last.section, isNotNull);
    });
  });

  group('English (ECD)', () {
    final english = dance(
      form: DanceForm.ecd,
      shape: FormationShape.dupleMinor,
      level: DifficultyLevel.beginnerId,
      figures: [
        fig('ecd_forward_and_back', 8),
        fig('ecd_circle', 8),
        fig('ecd_forward_and_back', 8),
      ],
    );

    test('offers type, level and figures, but not Same formation', () {
      final seed = seedOf(english, mixed: true);
      expect(seed.formation, isNull);
      expect(seed.form, DanceForm.ecd);
      expect(seed.levelIds, {DifficultyLevel.beginnerId});
      expect(seed.figures, hasLength(3));
      expect(
        filterOf(seed, const SwapKeepChoices()),
        'and(form(ecd), level(${DifficultyLevel.beginnerId}|eq))',
      );
    });

    test('offers no refinement on its figures', () {
      final seed = seedOf(english);
      for (final figure in seed.figures) {
        expect(figure.section, isNull, reason: figure.move);
        expect(figure.beforeMove, isNull, reason: figure.move);
      }
      final choices = const SwapKeepChoices().withFigure(
        1,
        const SwapFigureKeep(samePhrase: true, withBefore: true),
      );
      expect(
        filterOf(seed, choices),
        'and(level(${DifficultyLevel.beginnerId}|eq), '
        'figure(leaf(ecd_circle|null|)))',
      );
    });
  });

  test('an unreadable transcription offers no figure', () {
    final d = Dance(
      id: 'u',
      title: 'Unreadable',
      form: DanceForm.contra,
      formation: const Formation(FormationShape.dupleImproper),
      figuresSource: const UnreadableFigures('{bad'),
      createdAt: stamp,
      updatedAt: stamp,
    );
    expect(seedOf(d).figures, isEmpty);
    expect(seedOf(d).formation, FormationShape.dupleImproper);
  });

  test('a hidden Filters section offers no Keep item and writes no '
      'criterion', () {
    final d = dance(level: DifficultyLevel.intermediateId);
    for (final (hidden, check) in <(String, bool Function(SwapKeepSeed))>[
      (CollectionFacetIds.formation, (s) => s.formation == null),
      (CollectionFacetIds.level, (s) => s.levelIds.isEmpty),
      (CollectionFacetIds.form, (s) => s.form == null),
    ]) {
      final seed = SwapKeepSeed.of(
        d,
        levels: levels,
        programMixesTypes: true,
        hiddenFacets: {hidden},
      );
      expect(check(seed), isTrue, reason: hidden);
      final facets = swapKeepPanelState(seed, const SwapKeepChoices()).facets;
      expect(
        [
          if (facets.formations.isNotEmpty) CollectionFacetIds.formation,
          if (facets.levels.isNotEmpty) CollectionFacetIds.level,
          if (facets.forms.isNotEmpty) CollectionFacetIds.form,
        ],
        isNot(contains(hidden)),
        reason: hidden,
      );
    }
    // Another section hidden leaves all three.
    final other = SwapKeepSeed.of(
      d,
      levels: levels,
      programMixesTypes: true,
      hiddenFacets: {CollectionFacetIds.tunes},
    );
    expect(other.formation, isNotNull);
    expect(other.levelIds, isNotEmpty);
    expect(other.form, isNotNull);
  });

  test('a free-text figure is neither kept nor the figure before one', () {
    final freeText = testFigure(
      move: customMove,
      params: {'text': 'everyone wave', 'beats': 8},
    );
    final seed = seedOf(
      dance(
        figures: [
          fig('circle', 16),
          freeText,
          fig('hey', 8),
          fig('swing', 16),
          fig('long_lines', 16),
        ],
      ),
    );
    expect(
      [for (final f in seed.figures) f.move],
      ['circle', 'hey', 'swing', 'long_lines'],
    );
    final hey = seed.figures.firstWhere((f) => f.move == 'hey');
    expect(hey.beforeMove, isNull, reason: 'the figure before is free text');
    final swing = seed.figures.firstWhere((f) => f.move == 'swing');
    expect(swing.beforeMove, 'hey');
  });

  test('the empty seed offers nothing', () {
    expect(filterOf(SwapKeepSeed.empty, const SwapKeepChoices()), 'and()');
  });
}
