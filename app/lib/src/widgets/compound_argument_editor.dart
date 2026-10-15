import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';

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

/// The editor for one argument of one of the user's compound figures (#709):
/// the parameter's kind's own editor, its choices narrowed to the values the
/// compound accepts ([allowedValues]).
///
/// Used by a compound placeholder row in the dance editor and by the compound
/// shorthand editor, so both offer the same values.
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
    return FigureParamEditor(
      keyPrefix: keyPrefix,
      paramKey: param.key,
      spec: ParamSpec(
        param.kind,
        defaultValue: null,
        choices: _listed.contains(param.kind) && allowed != null
            ? [for (final v in allowed) ?(v is String ? v : null)]
            : null,
      ),
      dialect: dialect,
      mixer: mixer,
      value: value,
      onChanged: onChanged,
    );
  }
}
