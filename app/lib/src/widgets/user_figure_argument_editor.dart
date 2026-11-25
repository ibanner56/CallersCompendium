import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/touch_density.dart';
import 'app_dropdown_field.dart';
import '../search/facet_labels.dart';
import 'figure_param_editors.dart';

/// Edits one argument of a figure of your own (#1023): the value one of its
/// declared parameters takes, in a dance or as the parameter's default.
///
/// A choice offers its labels, in the active dialect, and stores its stable
/// id; free text has an editor of its own. With [allowNone] (a default),
/// every other kind is a list of its values headed by [noneLabel], null, and
/// labelled [label], so "no default" is an ordinary state, never one the
/// field reads as needing a value. Without it (a dance's argument), a flag is
/// a switch and every other kind is the dance editor's [FigureParamEditor].
class UserFigureArgumentEditor extends StatelessWidget {
  const UserFigureArgumentEditor({
    super.key,
    required this.keyPrefix,
    required this.param,
    required this.form,
    required this.value,
    required this.onChanged,
    required this.dialect,
    this.label,
    this.allowNone = false,
    this.noneLabel,
    this.mixer = false,
  });

  /// Stem of the editor's key: it is `<keyPrefix>-<param key>`.
  final String keyPrefix;
  final UserFigureParam param;

  /// The figure's form ([DanceForm.name]): the groups of dancers a dancer set
  /// offers are its form's ([userFigureDancerChoices]).
  final String form;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final Dialect dialect;

  /// The field's label; the parameter's key when null.
  final String? label;
  final bool allowNone;
  final String? noneLabel;
  final bool mixer;

  static final FigureRenderer _renderer = FigureRenderer(contraTaxonomy);

  /// How [value] reads in the list: a flag's wording or its key, a dancer in
  /// the dialect, any other value humanized.
  String _valueLabel(AppLocalizations l10n, Object? value) => switch (value) {
    true =>
      param.label == null
          ? param.key
          : _renderer.renderFreeText(param.label!, dialect),
    false => l10n.userFigureEditorFlagOff,
    final String token => figureParamChoiceLabel(
      l10n,
      param.bareSpecIn(form),
      dialect,
      token,
    ),
    _ => '$value',
  };

  /// [spec] without the "not stated" value, so a dance's argument offers no
  /// Clear button that would store it (#2294): English's groups of dancers
  /// include it, contra's never did, and a use of a figure of your own states
  /// its group or leaves it to the figure's default. The value is still one
  /// the figure accepts; the picker just never writes it.
  static ParamSpec _withoutNotStated(ParamSpec spec) {
    final choices = spec.choices;
    if (choices == null || !choices.contains(ParamVocab.unspecified)) {
      return spec;
    }
    return ParamSpec(
      spec.kind,
      defaultValue: spec.defaultValue,
      choices: [
        for (final c in choices)
          if (c != ParamVocab.unspecified) c,
      ],
    );
  }

  String get _key => '$keyPrefix-${param.key}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fieldLabel = label ?? param.key;
    switch (param.kind) {
      case ParamKind.choice:
        final ids = {for (final c in param.choices) c.id};
        return AppDropdownField<String?>(
          key: ValueKey(_key),
          // A choice since removed shows as nothing chosen, not as another.
          value: ids.contains(value) ? value as String? : null,
          // Choices the user wrote: a list that grows.
          filterable: true,
          decoration: InputDecoration(
            labelText: fieldLabel,
            border: const OutlineInputBorder(),
            isDense: denseControls(context),
          ),
          entries: [
            if (allowNone)
              AppDropdownEntry<String?>(
                value: null,
                label: noneLabel ?? l10n.userFigureEditorNoDefault,
              ),
            for (final choice in param.choices)
              AppDropdownEntry<String?>(
                value: choice.id,
                label: _renderer.renderFreeText(choice.label, dialect),
              ),
          ],
          onChanged: onChanged,
        );
      case ParamKind.text:
        return _TextArgument(
          key: ValueKey(_key),
          label: fieldLabel,
          value: value is String ? value as String : '',
          onChanged: (text) => onChanged(text.isEmpty ? null : text),
        );
      case _ when allowNone:
        final domain = paramDomain(param.bareSpecIn(form));
        // "Not stated" is a value a parameter may hold but never one a picker
        // offers (#741, as [figureParamSelectableChoices] does for text
        // domains; this domain also holds numbers): "no default" already says
        // it, and an English figure's groups include it.
        final values = [
          for (final v in domain ?? const <Object>{})
            if (v != ParamVocab.unspecified) v,
        ];
        return AppDropdownField<Object?>(
          key: ValueKey(_key),
          value: values.contains(value) ? value : null,
          // Numbers and beats run to dozens of entries: typing one is quicker.
          filterable: values.length + 1 >= appDropdownFilterFrom,
          decoration: InputDecoration(
            labelText: fieldLabel,
            border: const OutlineInputBorder(),
            isDense: denseControls(context),
          ),
          entries: [
            AppDropdownEntry<Object?>(
              value: null,
              label: noneLabel ?? l10n.userFigureEditorNoDefault,
            ),
            for (final v in values)
              AppDropdownEntry<Object?>(value: v, label: _valueLabel(l10n, v)),
          ],
          onChanged: onChanged,
        );
      case ParamKind.flag:
        return SwitchListTile(
          key: ValueKey(_key),
          contentPadding: EdgeInsets.zero,
          title: Text(
            param.label == null
                ? fieldLabel
                : _renderer.renderFreeText(param.label!, dialect),
          ),
          value: value == true,
          onChanged: onChanged,
        );
      default:
        return FigureParamEditor(
          keyPrefix: keyPrefix,
          paramKey: param.key,
          spec: param.kind == ParamKind.fraction
              ? ParamSpec(
                  param.kind,
                  defaultValue: null,
                  choices: [
                    for (final v in ParamVocab.fractions)
                      if (offersFractionChoice(v, value)) v,
                  ],
                )
              : _withoutNotStated(param.bareSpecIn(form)),
          value: value,
          onChanged: onChanged,
          dialect: dialect,
          mixer: mixer,
          correctsValue: false,
        );
    }
  }
}

/// A free-text argument: its own controller, so typing is never reset by a
/// rebuild from the value it reports.
class _TextArgument extends StatefulWidget {
  const _TextArgument({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_TextArgument> createState() => _TextArgumentState();
}

class _TextArgumentState extends State<_TextArgument> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(_TextArgument oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    maxLength: maxUserFigureTextArgLength,
    decoration: InputDecoration(
      labelText: widget.label,
      border: const OutlineInputBorder(),
      isDense: true,
    ),
    onChanged: widget.onChanged,
  );
}
