import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
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
      ParamSpec(param.kind, defaultValue: null),
      dialect,
      token,
    ),
    _ => '$value',
  };

  String get _key => '$keyPrefix-${param.key}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fieldLabel = label ?? param.key;
    switch (param.kind) {
      case ParamKind.choice:
        final ids = {for (final c in param.choices) c.id};
        return DropdownButtonFormField<String?>(
          key: ValueKey(_key),
          // A choice since removed shows as nothing chosen, not as another.
          initialValue: ids.contains(value) ? value as String? : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: fieldLabel,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            if (allowNone)
              DropdownMenuItem<String?>(
                value: null,
                child: Text(noneLabel ?? l10n.userFigureEditorNoDefault),
              ),
            for (final choice in param.choices)
              DropdownMenuItem<String?>(
                value: choice.id,
                child: Text(_renderer.renderFreeText(choice.label, dialect)),
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
        final domain = paramDomain(ParamSpec(param.kind, defaultValue: null));
        final values = [...?domain];
        return DropdownButtonFormField<Object?>(
          key: ValueKey(_key),
          initialValue: values.contains(value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: fieldLabel,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            DropdownMenuItem<Object?>(
              value: null,
              child: Text(noneLabel ?? l10n.userFigureEditorNoDefault),
            ),
            for (final v in values)
              DropdownMenuItem<Object?>(
                value: v,
                child: Text(_valueLabel(l10n, v)),
              ),
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
          spec: ParamSpec(param.kind, defaultValue: null),
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
