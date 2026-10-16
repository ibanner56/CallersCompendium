import 'package:meta/meta.dart';

import '../dialect/renderer.dart';
import '../model/figure.dart';
import '../validation/validation.dart';
import 'glossary_names.dart';
import 'param_types.dart';
import 'taxonomy.dart';
import 'user_figure_definition.dart';
import 'user_figure_use.dart';

/// The shipped move or alias named [name] (#1023, maintainer decision 5): the
/// figure a later version of the app brought that now has the name of one of
/// the user's own. Names compare as glossary names do
/// ([normalizeGlossaryName]), against a move's or alias's display name or id,
/// as [glossaryNameCollisions] reports [GlossaryNameSource.shippedFigure].
/// Moves are tried before aliases, each in id order, so the answer never
/// depends on the taxonomy's map order. Null when none has it; a search
/// keyword is not a name.
String? shippedFigureNamed(String name, Taxonomy taxonomy) {
  final wanted = normalizeGlossaryName(name);
  if (wanted.isEmpty) return null;
  bool same(String other) => normalizeGlossaryName(other) == wanted;
  final moves = taxonomy.moves.values.toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  for (final move in moves) {
    if (move.id == customMoveId) continue;
    if (same(move.displayName) || same(move.id)) return move.id;
  }
  final aliases = taxonomy.aliases.values.toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  for (final alias in aliases) {
    if (same(alias.displayName) || same(alias.id)) return alias.id;
  }
  return null;
}

/// How the uses of one of the user's figures become uses of the shipped
/// figure [target] (#1023, maintainer decision 5: "switch"): which of the
/// target's parameters each of the user's takes ([params], by key), and which
/// of the target's values each of a choice's values becomes ([choices], by
/// parameter key, then choice id).
///
/// Built by the mapping editor for one switch and never stored.
@immutable
final class UserFigureSwitch {
  UserFigureSwitch({
    required this.target,
    Map<String, String> params = const {},
    Map<String, Map<String, String>> choices = const {},
  }) : params = Map.unmodifiable(params),
       choices = Map.unmodifiable({
         for (final MapEntry(:key, :value) in choices.entries)
           key: Map<String, String>.unmodifiable(value),
       });

  /// The shipped move or alias id the uses become.
  final String target;

  /// The target's parameter each of the user's parameters maps to.
  final Map<String, String> params;

  /// For each of the user's choice parameters, the target's value each of its
  /// choice ids maps to.
  final Map<String, Map<String, String>> choices;
}

/// The parameters of [target] that [param] can map to in a switch
/// ([UserFigureSwitch]), in the move's order: those of the same kind, but a
/// choice maps to a parameter with a list of values of its own, whatever its
/// kind, value by value. The target's beats are never one: a use's beats are
/// carried apart. Empty when [target] is not a move or alias here.
List<String> userFigureSwitchTargets(
  UserFigureParam param,
  String target,
  Taxonomy taxonomy,
) {
  final def = taxonomy.resolve(target);
  if (def == null) return const [];
  return [
    for (final MapEntry(:key, value: spec) in def.params.entries)
      if (spec.kind != ParamKind.beats &&
          (param.kind == ParamKind.choice
              ? spec.choices != null
              : spec.kind == param.kind))
        key,
  ];
}

/// The values a choice of the user's can map to in [target]'s parameter
/// [targetKey]: that parameter's own list, but "not stated", which is never
/// a value to pick. Empty when it has none.
List<String> userFigureSwitchValues(
  String target,
  String targetKey,
  Taxonomy taxonomy,
) => [
  for (final value
      in taxonomy.resolve(target)?.params[targetKey]?.choices ??
          const <String>[])
    if (value != ParamVocab.unspecified) value,
];

/// What is missing or wrong in [mapping] for switching the uses of
/// [definition] to its target, one line per problem, for the caller to test
/// for emptiness: complete only when the target is a shipped move or alias,
/// and every one of the figure's parameters maps to a different parameter of
/// it that can take it ([userFigureSwitchTargets]), and every value of each
/// choice maps to a value that parameter has ([userFigureSwitchValues]).
/// Maintainer decision 5: a switch maps *every* parameter and *every* choice
/// value before it can be saved.
List<String> userFigureSwitchProblems(
  UserFigureDefinition definition,
  UserFigureSwitch mapping,
  Taxonomy taxonomy,
) {
  if (taxonomy.resolve(mapping.target) == null ||
      mapping.target == customMoveId) {
    return ['no shipped figure "${mapping.target}"'];
  }
  final problems = <String>[];
  final taken = <String>{};
  for (final param in definition.params) {
    final to = mapping.params[param.key];
    if (to == null) {
      problems.add('"${param.key}" is not mapped');
      continue;
    }
    if (!userFigureSwitchTargets(
      param,
      mapping.target,
      taxonomy,
    ).contains(to)) {
      problems.add('"${param.key}" cannot map to "$to"');
      continue;
    }
    if (!taken.add(to)) {
      problems.add('"$to" is mapped twice');
      continue;
    }
    if (param.kind != ParamKind.choice) continue;
    final values = userFigureSwitchValues(mapping.target, to, taxonomy);
    final byChoice = mapping.choices[param.key] ?? const {};
    for (final choice in param.choices) {
      final value = byChoice[choice.id];
      if (value == null) {
        problems.add('"${param.key}" choice "${choice.id}" is not mapped');
      } else if (!values.contains(value)) {
        problems.add(
          '"${param.key}" choice "${choice.id}" cannot map to "$value"',
        );
      }
    }
  }
  return problems;
}

/// [figures] with each use of the user's figure [id] (#1023), inside
/// containers too, switched to the shipped figure [mapping] names
/// (maintainer decision 5), [mapping] being complete for [definition]
/// ([userFigureSwitchProblems]). The same list when nothing uses it.
///
/// An attached use becomes a figure of the target: each argument (or the
/// parameter's default, where the use states none) under the target
/// parameter it maps to, a choice's as the value its choice maps to, and its
/// note and progression kept. A parameter with no value is left to the
/// target's own default. Its beats are kept: stated only where the target
/// would count it differently, so a dance's timing never changes.
///
/// A use that can't become one is frozen as plain text, as deleting the
/// figure freezes it ([freezeUserFigureUsesIn]), with the line it renders to
/// through [renderer] now, or its stored line: a detached use, which is plain
/// text already (plan C2); a use whose argument is no longer one of the
/// figure's values, or is one the target refuses; and a result the taxonomy
/// would refuse.
List<Figure> switchUserFigureUsesIn(
  List<Figure> figures,
  String id,
  UserFigureDefinition definition,
  UserFigureSwitch mapping,
  Taxonomy taxonomy,
  FigureRenderer renderer,
) => mapFigureLeaves(figures, (figure) {
  final use = userFigureUseOf(figure);
  if (use == null || use.id != id) return figure;
  Figure freeze() => detachUserFigureUse(
    figure,
    text: use.attached ? renderer.renderUserFigureCanonical(figure) : null,
  );
  if (!use.attached) return freeze();
  final target = taxonomy.resolve(mapping.target);
  if (target == null) return freeze();
  final params = <String, Object?>{};
  for (final param in definition.params) {
    final to = mapping.params[param.key];
    if (to == null) return freeze();
    final value = use.args[param.key] ?? param.defaultValue;
    if (value == null) continue;
    if (!param.spec.validate(value)) return freeze();
    final Object? mapped;
    if (param.kind == ParamKind.choice) {
      mapped = (mapping.choices[param.key] ?? const {})[value];
    } else {
      mapped = value;
    }
    if (mapped == null) return freeze();
    if (target.params[to]?.validate(mapped) != true) return freeze();
    params[to] = mapped;
  }
  final beats = switch (figure.params['beats']) {
    final int stated => stated,
    _ => definition.defaultBeats,
  };
  final unstated = Figure(
    move: mapping.target,
    params: params,
    note: figure.note,
    progression: figure.progression,
  );
  final switched = taxonomy.effectiveParams(unstated)['beats'] == beats
      ? unstated
      : unstated.copyWith(params: {...params, 'beats': beats});
  final refused = taxonomy
      .validateFigure(switched)
      .any((issue) => issue.severity == ValidationSeverity.error);
  return refused ? freeze() : switched;
});
