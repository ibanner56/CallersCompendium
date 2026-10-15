import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../search/facet_labels.dart';
import 'figure_param_editors.dart';

/// The values [args] gives [definition]'s parameters, labelled as their
/// editors label them and comma-separated, in the order the parameters are
/// declared: "neighbors, right".
String compoundArgumentsText(
  AppLocalizations l10n,
  CompoundDefinition definition,
  Map<String, Object?> args,
  Dialect dialect,
) => [
  for (final param in definition.params)
    switch (args[param.key]) {
      final String value => figureParamChoiceLabel(
        l10n,
        ParamSpec(param.kind, defaultValue: null),
        dialect,
        value,
      ),
      true => l10n.commonYes,
      false => l10n.commonNo,
      null => l10n.danceEditorParamNotStated,
      final Object value => '$value',
    },
].join(', ');

final FigureRenderer _renderer = FigureRenderer(contraTaxonomy);

/// A stored compound shorthand ([CompoundShorthand.toJson]) as one line, from
/// the stored value alone, where its figure's definition is not at hand (the
/// sync conflict view): the figure's name and each value, readable and in the
/// dialect's words, in the order stored. Null when [value] is not one.
String? compoundShorthandValueText(
  AppLocalizations l10n,
  Object? value,
  Dialect dialect,
) {
  if (value case {
    'name': final String name,
    'args': final Map<Object?, Object?> args,
  }) {
    final shown = _renderer.renderFreeText(name, dialect);
    if (args.isEmpty) return shown;
    final values = [
      for (final v in args.values)
        switch (v) {
          ParamVocab.unspecified => l10n.danceEditorParamNotStated,
          // A dancer token in the dialect's words, single dancers included.
          final String text when ParamVocab.dancerSets.contains(text) =>
            FigureRenderer.displayToken(
              text,
              const ParamSpec(ParamKind.dancerSet, defaultValue: null),
              dialect,
            ),
          final String text => humanizeToken(
            _renderer.renderFreeText(text, dialect),
          ),
          true => l10n.commonYes,
          false => l10n.commonNo,
          _ => '$v',
        },
    ];
    return l10n.danceEditorCompoundSummary(shown, values.join(', '));
  }
  return null;
}

/// The editor for one argument of one of the user's compound figures (#709):
/// the parameter's kind's own editor, its choices narrowed to the values the
/// compound accepts ([allowedValues]).
///
/// Used by a compound placeholder row in the dance editor and by the compound
/// shorthand editor, so both offer the same values. A stored value the
/// compound no longer accepts, or a missing one, is never replaced by the
/// editor itself, and is never shown as a value it holds: a list shows nothing
/// selected and asks for a choice, and every other kind's editor has a line
/// beneath it asking for one. "Not stated" is shown only when it is the value.
class CompoundArgumentEditor extends StatelessWidget {
  const CompoundArgumentEditor({
    super.key,
    required this.keyPrefix,
    required this.definition,
    required this.param,
    required this.value,
    required this.onChanged,
    required this.dialect,
    this.mixer = false,
    this.taxonomy,
  });

  /// Stem of the editor's key: it is `<keyPrefix>-<param key>`.
  final String keyPrefix;
  final CompoundDefinition definition;
  final CompoundParam param;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final Dialect dialect;
  final bool mixer;

  /// Defaults to the shipped taxonomy.
  final Taxonomy? taxonomy;

  /// The kinds whose values are a list of strings the editor offers.
  static const Set<ParamKind> _listed = {
    ParamKind.dancerSet,
    ParamKind.dancerPair,
    ParamKind.handedness,
    ParamKind.shoulder,
    ParamKind.spinDirection,
    ParamKind.fraction,
    ParamKind.direction,
    ParamKind.choice,
  };

  @override
  Widget build(BuildContext context) {
    final allowed = allowedValues(
      definition,
      param.key,
      taxonomy ?? contraTaxonomy,
    );
    final listed = _listed.contains(param.kind);
    final editor = FigureParamEditor(
      keyPrefix: keyPrefix,
      paramKey: param.key,
      spec: ParamSpec(
        param.kind,
        defaultValue: null,
        choices: switch (param.kind) {
          _ when listed && allowed != null => [
            for (final v in allowed) ?(v is String ? v : null),
          ],
          // Listing the sentinel is how a rotation admits "not stated": its
          // stepper then shows that state, and offers Clear, rather than 1.
          ParamKind.rotation
              when allowed?.contains(ParamVocab.unspecified) ?? false =>
            const [ParamVocab.unspecified],
          _ => null,
        },
      ),
      dialect: dialect,
      mixer: mixer,
      value: value,
      // A value the compound no longer accepts stays as it is, not replaced
      // by opening the editor, so the caller keeps saying it can't be used
      // until the user chooses another.
      correctsValue: false,
      onChanged: onChanged,
    );
    // A list asks for a choice itself; every other kind's editor shows a
    // fallback (1, 0, off, empty) for a value it can't show, so say so here.
    final accepted = allowed == null
        ? value is String
        : allowed.contains(value);
    if (listed || accepted) return editor;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        editor,
        Text(
          AppLocalizations.of(context).danceEditorParamChooseValue,
          key: ValueKey('$keyPrefix-${param.key}-choose'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ],
    );
  }
}
