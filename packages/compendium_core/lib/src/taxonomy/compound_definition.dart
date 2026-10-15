import '../model/figure.dart';
import '../serialization/figure_codec.dart';
import '../validation/validation.dart';
import 'param_change_rules.dart';
import 'param_opposites.dart';
import 'param_types.dart';
import 'taxonomy.dart';

/// Most template figures a compound may expand into.
const int maxCompoundFigures = 64;

/// Most parameters a compound may declare.
const int maxCompoundParams = 16;

/// Longest parameter key a compound may declare.
const int maxCompoundParamKeyLength = 64;

/// One parameter a user compound figure declares (#709): a key the user names,
/// of one of the parameter kinds the taxonomy's own figures use.
final class CompoundParam {
  const CompoundParam({required this.key, required this.kind});

  final String key;
  final ParamKind kind;

  Map<String, Object?> toJson() => {'key': key, 'kind': kind.name};

  @override
  bool operator ==(Object other) =>
      other is CompoundParam && other.key == key && other.kind == kind;

  @override
  int get hashCode => Object.hash(key, kind);
}

/// Where a compound slot takes its value from.
enum CompoundBindingSource {
  /// The declared parameter's own value.
  declared,

  /// The declared parameter's computed opposite ([ParamOpposites]): the
  /// "other hand" a user never declares but may use.
  opposite,
}

/// Fills [slotKey] of the template figure at [figureIndex] from the declared
/// parameter [paramKey], or from its opposite.
final class CompoundSlotBinding {
  const CompoundSlotBinding({
    required this.figureIndex,
    required this.slotKey,
    required this.paramKey,
    this.source = CompoundBindingSource.declared,
  });

  final int figureIndex;
  final String slotKey;
  final String paramKey;
  final CompoundBindingSource source;

  Map<String, Object?> toJson() => {
    'figure': figureIndex,
    'slot': slotKey,
    'param': paramKey,
    'source': source.name,
  };

  @override
  bool operator ==(Object other) =>
      other is CompoundSlotBinding &&
      other.figureIndex == figureIndex &&
      other.slotKey == slotKey &&
      other.paramKey == paramKey &&
      other.source == source;

  @override
  int get hashCode => Object.hash(figureIndex, slotKey, paramKey, source);
}

/// A user compound figure's expansion formula (#709): the ordered template
/// figures it expands into, the parameters it declares, and which template
/// slots each parameter fills.
///
/// Templates are bundled taxonomy figures with fixed values; a bound slot's
/// template value is replaced on expansion. A compound is a sequence of
/// plain figures: no `custom` figure, no meanwhile or modifier container, and
/// no compound inside a compound (maintainer, 2026-10-14).
final class CompoundDefinition {
  CompoundDefinition({
    required List<CompoundParam> params,
    required List<Figure> figures,
    required List<CompoundSlotBinding> bindings,
  }) : params = List.unmodifiable(params),
       figures = List.unmodifiable(figures),
       bindings = List.unmodifiable(bindings);

  final List<CompoundParam> params;
  final List<Figure> figures;
  final List<CompoundSlotBinding> bindings;

  CompoundParam? param(String key) {
    for (final p in params) {
      if (p.key == key) return p;
    }
    return null;
  }

  /// The beats the compound takes: the sum of its expanded figures' beats.
  /// Computed from an expansion, since a bound parameter (a balance) can move
  /// a part's beats.
  static int beatsOf(List<Figure> expanded, Taxonomy taxonomy) {
    var total = 0;
    for (final figure in expanded) {
      final beats = taxonomy.effectiveParams(figure)['beats'];
      if (beats is int) total += beats;
    }
    return total;
  }

  Map<String, Object?> toJson() => {
    'params': [for (final p in params) p.toJson()],
    'figures': [for (final f in figures) figureToJson(f)],
    'bindings': [for (final b in bindings) b.toJson()],
  };
}

/// Decodes a stored [CompoundDefinition], or returns null when [raw] is not
/// one this build can use: malformed, over a bound, or with any error-severity
/// issue from [validateCompound] (a template the taxonomy no longer accepts, a
/// binding to a slot that is gone). Never throws.
///
/// Templates are brought up to date with the taxonomy as they are read
/// ([Taxonomy.normalizeFigureV35]), as stored shorthands are: definitions
/// carry no taxonomy version stamp (maintainer, 2026-10-14).
CompoundDefinition? decodeCompoundDefinition(Object? raw, Taxonomy taxonomy) {
  try {
    if (raw is! Map) return null;
    final rawParams = raw['params'];
    final rawFigures = raw['figures'];
    final rawBindings = raw['bindings'];
    if (rawParams is! List || rawFigures is! List || rawBindings is! List) {
      return null;
    }
    if (rawParams.length > maxCompoundParams ||
        rawFigures.length > maxCompoundFigures ||
        rawBindings.length > _maxBindings) {
      return null;
    }
    final params = <CompoundParam>[];
    for (final p in rawParams) {
      if (p is! Map) return null;
      final key = p['key'];
      final kindName = p['kind'];
      if (key is! String || kindName is! String) return null;
      final kind = _kindNamed(kindName);
      if (kind == null) return null;
      params.add(CompoundParam(key: key, kind: kind));
    }
    final figures = <Figure>[];
    for (final f in rawFigures) {
      if (f is! Map) return null;
      final figure = figureFromJson(f.cast<String, Object?>());
      figures.add(taxonomy.normalizeFigureV35(figure));
    }
    final bindings = <CompoundSlotBinding>[];
    for (final b in rawBindings) {
      if (b is! Map) return null;
      final index = b['figure'];
      final slot = b['slot'];
      final param = b['param'];
      final sourceName = b['source'];
      if (index is! int ||
          slot is! String ||
          param is! String ||
          sourceName is! String) {
        return null;
      }
      final source = CompoundBindingSource.values
          .where((s) => s.name == sourceName)
          .firstOrNull;
      if (source == null) return null;
      bindings.add(
        CompoundSlotBinding(
          figureIndex: index,
          slotKey: slot,
          paramKey: param,
          source: source,
        ),
      );
    }
    final definition = CompoundDefinition(
      params: params,
      figures: figures,
      bindings: bindings,
    );
    final hasError = validateCompound(
      definition,
      taxonomy,
    ).any((issue) => issue.severity == ValidationSeverity.error);
    return hasError ? null : definition;
  } on Object {
    // A codec throw on hostile input is "not usable", never a crash.
    return null;
  }
}

/// One slot per template figure and parameter at most.
const int _maxBindings = maxCompoundFigures * 16;

ParamKind? _kindNamed(String name) {
  for (final kind in ParamKind.values) {
    if (kind.name == name) return kind;
  }
  return null;
}

/// The values [paramKey] may take in [definition]: those valid in every slot
/// it fills, and — where it fills a slot through its opposite — those whose
/// opposite that slot accepts, which excludes every value with no opposite.
///
/// A parameter that fills no slot takes its kind's whole vocabulary, with the
/// `unspecified` sentinel where the kind has one; a `choice` parameter has no
/// vocabulary of its own, so unbound it takes nothing. Null means any string:
/// a text parameter whose slots are all free text. An empty set means no
/// value fits, which [validateCompound] reports for a parameter in use; an
/// undeclared [paramKey] also gets the empty set.
Set<Object>? allowedValues(
  CompoundDefinition definition,
  String paramKey,
  Taxonomy taxonomy,
) {
  final param = definition.param(paramKey);
  if (param == null) return const {};
  Set<Object>? allowed;
  for (final binding in definition.bindings) {
    if (binding.paramKey != paramKey) continue;
    final spec = _slotSpec(definition, binding, taxonomy);
    if (spec == null) return const {};
    final slotDomain = paramDomain(spec);
    final Set<Object>? accepted;
    if (binding.source == CompoundBindingSource.declared) {
      accepted = slotDomain;
    } else {
      // Every value whose opposite the slot takes.
      final universe = _universe(param.kind, spec);
      accepted = {
        for (final value in universe ?? const <Object>{})
          if (ParamOpposites.of(param.kind, value) case final Object opposite
              when slotDomain == null || slotDomain.contains(opposite))
            value,
      };
    }
    if (accepted == null) continue; // free text constrains nothing
    allowed = allowed == null ? {...accepted} : allowed.intersection(accepted);
  }
  return allowed ?? _universe(param.kind, null);
}

/// Every value of [kind] a slot could hold: its shared vocabulary with the
/// `unspecified` sentinel, or [spec]'s own domain for a move-specific kind.
Set<Object>? _universe(ParamKind kind, ParamSpec? spec) {
  final wide = ParamSpec(
    kind,
    defaultValue: null,
    choices: switch (kind) {
      ParamKind.dancerSet || ParamKind.dancerPair => [
        ...ParamVocab.dancerSets,
        ParamVocab.unspecified,
      ],
      ParamKind.handedness ||
      ParamKind.shoulder => [...ParamVocab.sides, ParamVocab.unspecified],
      ParamKind.spinDirection => [...ParamVocab.spins, ParamVocab.unspecified],
      ParamKind.direction => [...ParamVocab.directions, ParamVocab.unspecified],
      ParamKind.fraction => [...ParamVocab.fractions],
      ParamKind.rotation => [ParamVocab.unspecified],
      ParamKind.choice => spec?.choices,
      _ => null,
    },
  );
  return paramDomain(wide);
}

ParamSpec? _slotSpec(
  CompoundDefinition definition,
  CompoundSlotBinding binding,
  Taxonomy taxonomy,
) {
  if (binding.figureIndex < 0 ||
      binding.figureIndex >= definition.figures.length) {
    return null;
  }
  final move = definition.figures[binding.figureIndex].move;
  return taxonomy.resolve(move)?.params[binding.slotKey];
}

/// The issue codes [validateCompound] reports.
abstract final class CompoundIssueCodes {
  /// The compound expands into nothing.
  static const empty = 'compound_empty';

  /// More figures, parameters or bindings than the bounds allow.
  static const tooLarge = 'compound_too_large';

  /// A declared parameter's key is empty, too long, or declared twice.
  static const badParamKey = 'compound_bad_param_key';

  /// A template is `custom`, a meanwhile or modifier container, or not a
  /// taxonomy move.
  static const badTemplate = 'compound_bad_template';

  /// A template figure the taxonomy reports an error for.
  static const invalidTemplate = 'compound_invalid_template';

  /// A binding names a figure or slot that does not exist, or a parameter the
  /// compound does not declare.
  static const danglingBinding = 'compound_dangling_binding';

  /// Two bindings fill the same slot.
  static const doubleBinding = 'compound_double_binding';

  /// A slot's `beats`: the parts' beats are the compound's, not an input.
  static const beatsBinding = 'compound_beats_binding';

  /// A parameter is bound to a slot of another kind.
  static const typeMismatch = 'compound_type_mismatch';

  /// A parameter's opposite is used, but its kind has none.
  static const noOpposite = 'compound_no_opposite';

  /// No value fits every slot a parameter fills.
  static const emptyDomain = 'compound_empty_domain';

  /// A declared parameter fills no slot. A warning: the user may save anyway.
  static const unusedParam = 'compound_unused_param';
}

/// Validates [definition] against [taxonomy].
///
/// Errors make it unusable. The one warning, [CompoundIssueCodes.unusedParam],
/// is the maintainer's rule that every declared parameter must be used, with
/// a choice to save anyway; an unused *opposite* is never reported, since it
/// is offered, not declared.
List<ValidationIssue> validateCompound(
  CompoundDefinition definition,
  Taxonomy taxonomy,
) {
  final issues = <ValidationIssue>[];
  void error(String code, String message, [Map<String, Object?>? data]) =>
      issues.add(
        ValidationIssue(
          severity: ValidationSeverity.error,
          code: code,
          message: message,
          data: data ?? const {},
        ),
      );

  if (definition.figures.isEmpty) {
    error(CompoundIssueCodes.empty, 'a compound expands into no figures');
  }
  if (definition.figures.length > maxCompoundFigures ||
      definition.params.length > maxCompoundParams ||
      definition.bindings.length > _maxBindings) {
    error(CompoundIssueCodes.tooLarge, 'a compound is over its bounds');
    return issues;
  }

  final keys = <String>{};
  for (final p in definition.params) {
    final key = p.key;
    if (key.trim().isEmpty ||
        key != key.trim() ||
        key.length > maxCompoundParamKeyLength ||
        !keys.add(key)) {
      error(
        CompoundIssueCodes.badParamKey,
        'parameter key "$key" is empty, too long or repeated',
        {'key': key},
      );
    }
  }

  for (var i = 0; i < definition.figures.length; i++) {
    final figure = definition.figures[i];
    final move = figure.move;
    if (move == customMove ||
        move == meanwhileMove ||
        move == modifierMove ||
        taxonomy.resolve(move) == null) {
      error(
        CompoundIssueCodes.badTemplate,
        'figure $i is not a plain taxonomy figure',
        {'figure': i},
      );
      continue;
    }
    for (final issue in taxonomy.validateFigure(figure)) {
      if (issue.severity != ValidationSeverity.error) continue;
      error(CompoundIssueCodes.invalidTemplate, 'figure $i: ${issue.message}', {
        'figure': i,
        'code': issue.code,
      });
    }
  }

  final filled = <(int, String)>{};
  final used = <String>{};
  for (final binding in definition.bindings) {
    final param = definition.param(binding.paramKey);
    final spec = _slotSpec(definition, binding, taxonomy);
    if (param == null || spec == null) {
      error(
        CompoundIssueCodes.danglingBinding,
        'binding to figure ${binding.figureIndex} slot "${binding.slotKey}" '
        'from "${binding.paramKey}" does not resolve',
        {'figure': binding.figureIndex, 'slot': binding.slotKey},
      );
      continue;
    }
    used.add(param.key);
    if (!filled.add((binding.figureIndex, binding.slotKey))) {
      error(
        CompoundIssueCodes.doubleBinding,
        'figure ${binding.figureIndex} slot "${binding.slotKey}" is bound twice',
        {'figure': binding.figureIndex, 'slot': binding.slotKey},
      );
    }
    if (binding.slotKey == 'beats') {
      error(
        CompoundIssueCodes.beatsBinding,
        'a part\'s beats cannot be bound',
        {'figure': binding.figureIndex},
      );
    }
    if (spec.kind != param.kind) {
      error(
        CompoundIssueCodes.typeMismatch,
        '"${param.key}" (${param.kind.name}) cannot fill a '
        '${spec.kind.name} slot',
        {
          'param': param.key,
          'figure': binding.figureIndex,
          'slot': binding.slotKey,
        },
      );
    }
    if (binding.source == CompoundBindingSource.opposite &&
        ParamOpposites.coverage(param.kind) == OppositeCoverage.none) {
      error(CompoundIssueCodes.noOpposite, '"${param.key}" has no opposite', {
        'param': param.key,
      });
    }
  }

  // Only once every binding resolves and matches its kind, so the overlap is
  // about values, not about a mistake already reported.
  if (issues.every((i) => i.severity != ValidationSeverity.error)) {
    for (final p in definition.params) {
      final allowed = allowedValues(definition, p.key, taxonomy);
      if (used.contains(p.key) && allowed != null && allowed.isEmpty) {
        error(
          CompoundIssueCodes.emptyDomain,
          'no value of "${p.key}" fits every slot it fills',
          {'param': p.key},
        );
      }
    }
  }

  for (final p in definition.params) {
    if (!used.contains(p.key)) {
      issues.add(
        ValidationIssue(
          severity: ValidationSeverity.warning,
          code: CompoundIssueCodes.unusedParam,
          message: 'declared parameter "${p.key}" fills no slot',
          data: {'param': p.key},
        ),
      );
    }
  }
  return issues;
}

/// Expands [definition] with [args] into bundled figures, or returns null when
/// it cannot: the definition has an error, a bound parameter has no argument,
/// an argument is outside [allowedValues], or an expanded figure fails the
/// taxonomy's validation. The caller falls back to a custom figure; this
/// never fabricates one.
///
/// Each template is copied, then each of its bound slots is set through
/// [applyParamChange], so a bound value carries the editor's follow-on rules
/// (a balance's ±4 beats, chain's hand, an inverse pair's reroute). A
/// figure's slots are set in the order its move declares them, never in the
/// order the bindings were stored, because one rule can overwrite another
/// slot: chain's `who` re-seeds `hand`, so a bound `hand` is set after it and
/// wins, whichever binding was saved first. The flags
/// are fixed — a template that states its beats is treated as owning them,
/// and the aggressive-beats preference is never consulted — so the same
/// compound expands to the same figures on every device. A template's own
/// note is kept; nothing records that a figure came from a compound
/// (maintainer, 2026-10-14).
List<Figure>? expandCompound(
  CompoundDefinition definition,
  Map<String, Object?> args,
  Taxonomy taxonomy,
) {
  if (validateCompound(
    definition,
    taxonomy,
  ).any((issue) => issue.severity == ValidationSeverity.error)) {
    return null;
  }
  final values = <String, Object?>{};
  for (final binding in definition.bindings) {
    final key = binding.paramKey;
    if (values.containsKey(key)) continue;
    if (!args.containsKey(key)) return null;
    final value = args[key];
    final allowed = allowedValues(definition, key, taxonomy);
    if (allowed == null ? value is! String : !allowed.contains(value)) {
      return null;
    }
    values[key] = value;
  }

  final expanded = <Figure>[];
  for (var i = 0; i < definition.figures.length; i++) {
    final template = definition.figures[i];
    var move = template.move;
    final params = Map<String, Object?>.of(template.params);
    final beatsTouched = template.params.containsKey('beats');
    // validateCompound has resolved every slot, so each is in the order.
    final slotOrder = taxonomy.resolve(template.move)!.params.keys.toList();
    final figureBindings =
        [
          for (final binding in definition.bindings)
            if (binding.figureIndex == i) binding,
        ]..sort(
          (a, b) => slotOrder
              .indexOf(a.slotKey)
              .compareTo(slotOrder.indexOf(b.slotKey)),
        );
    for (final binding in figureBindings) {
      final param = definition.param(binding.paramKey)!;
      final value = binding.source == CompoundBindingSource.declared
          ? values[param.key]
          : ParamOpposites.of(param.kind, values[param.key]);
      if (value == null) return null;
      move = applyParamChange(
        taxonomy,
        move: move,
        params: params,
        key: binding.slotKey,
        value: value,
        beatsTouched: beatsTouched,
        aggressiveBeats: false,
      );
    }
    final figure = Figure(move: move, params: params, note: template.note);
    if (taxonomy
        .validateFigure(figure)
        .any((issue) => issue.severity == ValidationSeverity.error)) {
      return null;
    }
    expanded.add(figure);
  }
  return expanded;
}
