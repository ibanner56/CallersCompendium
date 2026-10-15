import 'package:meta/meta.dart';

import '../model/figure.dart' show customMoveId;
import 'contra_figure_definitions.dart';
import 'move_def.dart';
import 'taxonomy.dart';

export 'contra_figure_definitions.dart' show contraFigureDefinitions;

/// Shipped, read-only glossary text for one bundled figure (issue #695).
///
/// Both strings are plain text written with the canonical role tokens
/// (`role1`, `role1s`, `role2`, `role2s`), so the same dialect rendering that
/// shows dance notes turns them into the user's role terms at display time.
/// Nothing here is stored or synced: it ships with the app.
@immutable
final class FigureDefinition {
  const FigureDefinition({required this.definition, required this.description});

  /// One sentence saying what the figure is.
  final String definition;

  /// A short paragraph for a caller: how it is danced, with whom, its usual
  /// length, and what its parameters change.
  final String description;
}

/// One figure in the shipped glossary: a taxonomy move or alias, never stored.
@immutable
final class FigureGlossaryEntry {
  const FigureGlossaryEntry({
    required this.id,
    required this.canonicalName,
    required this.targetMoveId,
    required this.searchKeywords,
    required this.params,
    this.definition,
  });

  /// The move or alias id (a [Figure.move] value).
  final String id;

  /// The taxonomy's English display name, before any dialect substitution.
  final String canonicalName;

  /// The canonical move this entry resolves to: [id] itself for a move, the
  /// alias's target for an alias.
  final String targetMoveId;

  /// Other names the figure is searched by, legacy names included.
  final List<String> searchKeywords;

  /// The parameters a caller can set on this figure, in canonical order. An
  /// alias omits the parameters it pins.
  final List<String> params;

  /// The shipped definition, or `null` when the definitions map passed to
  /// [figureGlossaryEntries] has none for [id].
  final FigureDefinition? definition;

  /// Whether this entry is an alias of another figure.
  bool get isAlias => targetMoveId != id;
}

/// The shipped glossary's figure entries for [taxonomy], in taxonomy order:
/// every move, then every alias. The free-text `custom` move is not a figure
/// a glossary can define, so it is left out.
List<FigureGlossaryEntry> figureGlossaryEntries(
  Taxonomy taxonomy, {
  Map<String, FigureDefinition> definitions = contraFigureDefinitions,
}) => [
  for (final MoveDef move in taxonomy.moves.values)
    if (move.id != customMoveId)
      FigureGlossaryEntry(
        id: move.id,
        canonicalName: move.displayName,
        targetMoveId: move.id,
        searchKeywords: move.searchKeywords,
        params: move.params.keys.toList(growable: false),
        definition: definitions[move.id],
      ),
  for (final MoveAlias alias in taxonomy.aliases.values)
    FigureGlossaryEntry(
      id: alias.id,
      canonicalName: alias.displayName,
      targetMoveId: alias.targetMove,
      searchKeywords: alias.searchKeywords,
      params: [
        for (final key in taxonomy.moves[alias.targetMove]!.params.keys)
          if (!alias.pinnedParams.containsKey(key)) key,
      ],
      definition: definitions[alias.id],
    ),
];
