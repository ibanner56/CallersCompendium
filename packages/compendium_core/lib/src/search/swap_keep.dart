/// The **Keep** items of Perform's swap sheet (#2346), seeded from the dance
/// being swapped, and the Collection panel state they stand for.
///
/// Every item is a criterion relative to the dance being swapped, built here
/// as the Filters and Advanced panels' own state ([FacetSelections] and
/// Advanced rows), so the picker's **More filters** shows the same criteria,
/// editable (docs/design/search.md, "The filter AST"):
///
/// - **Same formation**: the Formation facet with this dance's shape
///   ([FormationFilter]).
/// - **This level or easier**: the Level facet with every level at or below
///   this dance's on the difficulty scale. The facet matches levels by
///   equality, so a dance with no level matches none of them, as
///   `LevelFilter`'s `lte` would not.
/// - **Same type**: the Type facet with this dance's form ([FormFilter]),
///   offered only in a program that mixes types.
/// - **Figures to keep**: an Advanced "has figure" row for each kept figure
///   (`FigureFilter(FigureLeaf(move))`), refined by **In the same phrase**
///   (the leaf's `section`) and **With what comes before it** (a "then" row,
///   [ThenFilter], whose first figure is the one before it in this dance,
///   read as a loop).
///
/// **Not already in tonight's program** is not a panel criterion: it leaves
/// out dances by id, which the host does.
///
/// English (ECD) dances get the items that work for them: type, level, and
/// figures without refinements. **Same formation** is left out because an
/// English formation's proper or improper is not part of its shape, so a
/// shape match would offer an improper dance for a proper one; the two
/// refinements are left out because English phrase structures vary and an
/// English sequence's steps are placed in a phrase differently. Both wait
/// for a follow-up.
library;

import 'package:meta/meta.dart';

import '../analysis/perform_swap_defaults.dart';
import '../model/dance.dart';
import '../model/difficulty_level.dart';
import '../model/enums.dart';
import '../model/figure.dart';
import '../model/figure_source.dart';
import '../model/formation.dart' show FormationShape;
import '../model/phrase_structure.dart';
import 'builder_nodes.dart';
import 'collection_facet_ids.dart';
import 'collection_panel_state.dart';

/// One figure the caller can keep: a leaf of the dance's transcription, in
/// phrase order.
@immutable
class SwapKeepFigure {
  const SwapKeepFigure({
    required this.index,
    required this.figure,
    this.section,
    this.beforeMove,
  });

  /// Position among the dance's [SwapKeepSeed.figures]; the key a
  /// [SwapKeepChoices] keeps it by.
  final int index;

  /// The figure as transcribed. Only its move is kept: "does it still need a
  /// hey?" asks for the move, whoever dances it.
  final Figure figure;

  String get move => figure.move;

  /// The phrase it starts in (`A1`), or null when **In the same phrase** is
  /// not offered for it.
  final String? section;

  /// The move of the figure just before it in the dance (the last figure
  /// for the first), or null when **With what comes before it** is not
  /// offered for it: an English dance, a dance of one figure, or a figure
  /// that follows several danced at once.
  final String? beforeMove;
}

/// What the dance being swapped offers to keep. Built by [SwapKeepSeed.of].
@immutable
class SwapKeepSeed {
  const SwapKeepSeed({
    this.formation,
    this.levelIds = const {},
    this.form,
    this.figures = const [],
  });

  /// Nothing to keep: the slot's dance could not be read.
  static const SwapKeepSeed empty = SwapKeepSeed();

  /// Builds the seed for [dance]. [levels] is the difficulty scale (any
  /// order; positions decide). [programMixesTypes] is whether the program
  /// holds dances of more than one form, the only case **Same type** is
  /// offered. [hiddenFacets] are the Filters sections the user has hidden
  /// ([CollectionFacetIds]); a Keep item whose section is hidden is not
  /// offered, since its criterion would sit in a panel the user cannot see.
  factory SwapKeepSeed.of(
    Dance dance, {
    required List<DifficultyLevel> levels,
    required bool programMixesTypes,
    Set<String> hiddenFacets = const {},
  }) {
    final english = dance.form == DanceForm.ecd;
    final levelId = dance.difficultyLevelId;
    final own =
        levelId == null || hiddenFacets.contains(CollectionFacetIds.level)
        ? null
        : levels.where((level) => level.id == levelId).firstOrNull;
    return SwapKeepSeed(
      formation: english || hiddenFacets.contains(CollectionFacetIds.formation)
          ? null
          : dance.formation.shape,
      levelIds: own == null
          ? const {}
          : {
              for (final level in levels)
                if (level.position <= own.position) level.id,
            },
      form: programMixesTypes && !hiddenFacets.contains(CollectionFacetIds.form)
          ? dance.form
          : null,
      figures: _figures(dance, refine: !english),
    );
  }

  /// The shape **Same formation** keeps, or null when it is not offered.
  final FormationShape? formation;

  /// The levels **This level or easier** keeps, or empty when it is not
  /// offered (the dance has no level, or one not on the scale).
  final Set<String> levelIds;

  /// The form **Same type** keeps, or null when it is not offered.
  final DanceForm? form;

  /// The figures to keep, in phrase order.
  final List<SwapKeepFigure> figures;

  /// The dance's figures as the search index groups them: a top-level figure
  /// is one group, a top-level sequence one group per step, and every leaf of
  /// a group is one figure to keep, in the section its group starts in.
  static List<SwapKeepFigure> _figures(Dance dance, {required bool refine}) {
    final decoded = switch (dance.figuresSource) {
      DecodedFigures(:final figures) => figures,
      UnreadableFigures() => const <Figure>[],
    };
    if (decoded.isEmpty) return const [];
    final sectioned = dance.sectionedFigures;
    final groups = <({List<Figure> leaves, String section})>[];
    for (var i = 0; i < decoded.length; i++) {
      final figure = decoded[i];
      final steps = figure.subFigures;
      if (figure.isSequence && steps.isNotEmpty) {
        var beat = sectioned[i].startBeat;
        for (final step in steps) {
          groups.add((
            leaves: _leaves(step),
            section: labelForFigure(beat, step.beats, dance.phraseStructure),
          ));
          beat += step.beats;
        }
      } else {
        groups.add((leaves: _leaves(figure), section: sectioned[i].label));
      }
    }
    final result = <SwapKeepFigure>[];
    for (var g = 0; g < groups.length; g++) {
      final previous = groups[(g - 1 + groups.length) % groups.length];
      final before =
          refine &&
              groups.length > 1 &&
              previous.leaves.length == 1 &&
              _keepable(previous.leaves.single)
          ? previous.leaves.single.move
          : null;
      for (final leaf in groups[g].leaves) {
        if (!_keepable(leaf)) continue;
        result.add(
          SwapKeepFigure(
            index: result.length,
            figure: leaf,
            section: refine ? groups[g].section : null,
            beforeMove: before,
          ),
        );
      }
    }
    return List.unmodifiable(result);
  }

  /// Whether [figure] names a move a search can ask for: not blank, and not
  /// a free-text figure ([customMove]), whose move says nothing about it.
  static bool _keepable(Figure figure) =>
      figure.move.trim().isNotEmpty && figure.move != customMove;

  static List<Figure> _leaves(Figure figure) {
    if (!figure.isContainer || figure.subFigures.isEmpty) return [figure];
    return [for (final child in figure.subFigures) ..._leaves(child)];
  }
}

/// How a kept figure is refined.
@immutable
class SwapFigureKeep {
  const SwapFigureKeep({this.samePhrase = false, this.withBefore = false});

  /// **In the same phrase**.
  final bool samePhrase;

  /// **With what comes before it**.
  final bool withBefore;

  SwapFigureKeep copyWith({bool? samePhrase, bool? withBefore}) =>
      SwapFigureKeep(
        samePhrase: samePhrase ?? this.samePhrase,
        withBefore: withBefore ?? this.withBefore,
      );

  @override
  bool operator ==(Object other) =>
      other is SwapFigureKeep &&
      other.samePhrase == samePhrase &&
      other.withBefore == withBefore;

  @override
  int get hashCode => Object.hash(samePhrase, withBefore);
}

/// Which **Keep** items are on. An item the seed does not offer is ignored
/// whatever its value here.
@immutable
class SwapKeepChoices {
  const SwapKeepChoices({
    this.formation = true,
    this.levelOrEasier = true,
    this.sameType = true,
    this.notInProgram = true,
    this.figures = const {},
  });

  /// The choices the sheet opens with: the seeded items as [defaults] say,
  /// and no figure kept.
  factory SwapKeepChoices.fromDefaults(PerformSwapDefaults defaults) =>
      SwapKeepChoices(
        formation: defaults.formation,
        levelOrEasier: defaults.levelOrEasier,
        sameType: defaults.sameType,
        notInProgram: defaults.notInProgram,
      );

  final bool formation;
  final bool levelOrEasier;
  final bool sameType;
  final bool notInProgram;

  /// The kept figures by [SwapKeepFigure.index], with their refinements. A
  /// figure absent here is not kept.
  final Map<int, SwapFigureKeep> figures;

  SwapKeepChoices copyWith({
    bool? formation,
    bool? levelOrEasier,
    bool? sameType,
    bool? notInProgram,
    Map<int, SwapFigureKeep>? figures,
  }) => SwapKeepChoices(
    formation: formation ?? this.formation,
    levelOrEasier: levelOrEasier ?? this.levelOrEasier,
    sameType: sameType ?? this.sameType,
    notInProgram: notInProgram ?? this.notInProgram,
    figures: figures ?? this.figures,
  );

  /// These choices with figure [index] kept as [keep], or not kept when
  /// [keep] is null.
  SwapKeepChoices withFigure(int index, SwapFigureKeep? keep) {
    final next = {...figures};
    if (keep == null) {
      next.remove(index);
    } else {
      next[index] = keep;
    }
    return copyWith(figures: Map.unmodifiable(next));
  }
}

/// The Filters and Advanced panel state the [choices] on [seed] stand for. A
/// fresh state each call: the picker edits the one it is given.
CollectionPanelState swapKeepPanelState(
  SwapKeepSeed seed,
  SwapKeepChoices choices,
) {
  final state = CollectionPanelState();
  final facets = state.facets;
  if (choices.formation && seed.formation != null) {
    facets.formations.add(seed.formation!);
  }
  if (choices.levelOrEasier) facets.levels.addAll(seed.levelIds);
  if (choices.sameType && seed.form != null) facets.forms.add(seed.form!);
  for (final figure in seed.figures) {
    final keep = choices.figures[figure.index];
    if (keep == null) continue;
    final kept = BuilderFigure(
      move: figure.move,
      section: keep.samePhrase ? figure.section : null,
    );
    final before = figure.beforeMove;
    state.advanced.children.add(
      keep.withBefore && before != null
          ? BuilderThen(
              before: BuilderFigure(move: before),
              after: kept,
            )
          : kept,
    );
  }
  return state;
}
