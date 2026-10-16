import 'dart:math';

import '../dialect/renderer.dart';
import '../validation/validation.dart';
import 'param_types.dart';
import 'taxonomy.dart';
import 'user_figure_definition.dart';

/// A new figure of the user's own, copied from the shipped move [moveId]
/// (#1023, maintainer decision 6): an independent definition seeded from the
/// move, which the user edits and saves as their own. The move itself is
/// never changed, and the copy keeps no link to it beyond
/// [UserFigureDefinition.copiedFrom], which is for display. Null when
/// [moveId] is not a move or alias here.
///
/// What the copy takes from the move:
/// - **Parameters**, in the move's order, up to [maxUserFigureParams]: every
///   one its wording uses but its beats, with its kind and default (a
///   parameter the wording never uses would do nothing in the copy). A
///   choice's values (but "not stated", which is never one to pick, and a
///   "none" that is its default, which the move words as nothing) get
///   choice ids of the user's own shape, labelled by [choiceLabel] (the
///   value itself without one), and its default is carried across. A flag is
///   labelled by [paramLabel] (its key without one). A default the user's
///   parameter could not hold is left out; a parameter its rules refuse
///   (a key a figure of the user's may not have) is dropped.
/// - **Default beats**, from the move's beats default, within a figure's
///   bounds; 8 without one.
/// - **Wording**: the move's own display wording when every slot it uses is
///   one of the copy's, else its plain render template when that holds, else
///   just `{move}`.
///
/// An alias is copied as the move it names, starting from the values it pins
/// where the move's parameters can hold them (a "pull by neighbors" copy has
/// neighbors as its default).
///
/// The result always validates ([validateUserFigure] reports no error), so
/// the editor can open on it.
UserFigureDefinition? userFigureSeedFromMove(
  Taxonomy taxonomy,
  String moveId, {
  String Function(String paramKey, String value)? choiceLabel,
  String Function(String paramKey)? paramLabel,
  Random? random,
}) {
  final def = taxonomy.resolve(moveId);
  if (def == null) return null;

  // An alias starts from the values it pins (a "pull by neighbors" copy from
  // neighbors), where its move's parameter can hold them.
  final pinned = taxonomy.aliases[moveId]?.pinnedParams ?? const {};
  final params = <UserFigureParam>[];
  for (final MapEntry(:key, value: moveSpec) in def.params.entries) {
    if (moveSpec.kind == ParamKind.beats) continue;
    if (params.length == maxUserFigureParams) break;
    final pin = pinned[key];
    final spec = pin != null && moveSpec.validate(pin)
        ? ParamSpec(
            moveSpec.kind,
            defaultValue: pin,
            choices: moveSpec.choices,
            allowManualClear: moveSpec.allowManualClear,
          )
        : moveSpec;
    params.add(_seedParam(key, spec, choiceLabel, paramLabel, random));
  }

  final rawBeats = def.params['beats']?.defaultValue;
  final defaultBeats = rawBeats is int
      ? rawBeats.clamp(0, maxUserFigureDefaultBeats)
      : 8;

  // Drop what a figure of the user's can't have, then pick the first wording
  // that fits what is left.
  var kept = params;
  for (var pass = 0; pass < 2; pass++) {
    final refused = {
      for (final issue in validateUserFigure(
        UserFigureDefinition(
          template: '{$userFigureMoveSlot}',
          defaultBeats: defaultBeats,
          params: kept,
        ),
      ))
        if (issue.severity == ValidationSeverity.error)
          if (issue.data['param'] case final String key) key,
    };
    if (refused.isEmpty) break;
    kept = [
      for (final p in kept)
        if (!refused.contains(p.key)) p,
    ];
  }

  final renderer = FigureRenderer(taxonomy);
  final probe = UserFigureDefinition(
    template: '{$userFigureMoveSlot}',
    defaultBeats: defaultBeats,
    params: kept,
  );
  bool fits(String? template) =>
      template != null &&
      FigureRenderer.isValidMoveWordingTemplate(template) &&
      probe.slots.containsAll(userFigureTemplateSlots(template));
  final template = [
    renderer.moveWordingTemplate(def.id),
    def.renderTemplate,
  ].firstWhere(fits, orElse: () => '{$userFigureMoveSlot}')!;

  // A parameter the wording never uses would do nothing in the copy (the
  // move words some of its own in code, not in its template), and the editor
  // would ask about each one before saving: only those it uses are kept.
  final used = userFigureTemplateSlots(template);
  final seed = UserFigureDefinition(
    template: template,
    defaultBeats: defaultBeats,
    params: [
      for (final p in kept)
        if (used.contains(p.key) ||
            used.contains(userFigureOppositeSlot(p.key)))
          p,
    ],
    copiedFrom: def.id,
  );
  assert(
    !validateUserFigure(
      seed,
    ).any((issue) => issue.severity == ValidationSeverity.error),
    'a seed from "$moveId" does not validate',
  );
  return seed;
}

/// The choice value a move words as nothing (a swing's `prefix: none`).
const String _noneValue = 'none';

UserFigureParam _seedParam(
  String key,
  ParamSpec spec,
  String Function(String paramKey, String value)? choiceLabel,
  String Function(String paramKey)? paramLabel,
  Random? random,
) {
  switch (spec.kind) {
    case ParamKind.choice:
      final taken = <String>{};
      final idByValue = <String, String>{};
      final choices = <UserFigureChoice>[];
      final labels = <String>{};
      for (final value in spec.choices ?? const <String>[]) {
        // "Not stated" is the taxonomy's own sentinel, never a value to pick.
        // "None" as the default is the move saying nothing until a value is
        // chosen (a swing's prefix): a figure of the user's says that by
        // having no value, which its wording leaves out. As any other value
        // (a slice with no return) it is a real choice, and is kept.
        if (value == ParamVocab.unspecified) continue;
        if (value == _noneValue && spec.defaultValue == _noneValue) continue;
        if (choices.length == maxUserFigureChoices) break;
        final label = choiceLabel?.call(key, value) ?? value;
        // Labels must differ; a second value labelled alike is left out.
        if (!labels.add(label)) continue;
        final id = newUserFigureChoiceId(taken, random: random);
        taken.add(id);
        idByValue[value] = id;
        choices.add(UserFigureChoice(id: id, label: label));
      }
      return UserFigureParam(
        key: key,
        kind: spec.kind,
        choices: choices,
        defaultValue: idByValue[spec.defaultValue],
      );
    case ParamKind.flag:
      return UserFigureParam(
        key: key,
        kind: spec.kind,
        label: paramLabel?.call(key) ?? key,
        defaultValue: spec.defaultValue is bool ? spec.defaultValue : null,
      );
    default:
      final candidate = UserFigureParam(
        key: key,
        kind: spec.kind,
        defaultValue: spec.defaultValue,
      );
      final holds =
          spec.defaultValue != null &&
          candidate.spec.validate(spec.defaultValue);
      return holds ? candidate : UserFigureParam(key: key, kind: spec.kind);
  }
}
