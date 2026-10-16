import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/user_figures_scope.dart';
import '../editor/user_figure_draft.dart';
import 'figure_param_editors.dart';
import 'user_figure_argument_editor.dart';

/// Edits a dance editor row that uses one of the user's own figures (#1023):
/// one editor per parameter the figure declares, and, unless [showBeats] is
/// off (a meanwhile side, whose group owns the beats), its beats.
///
/// Every change reports the row's new params, with the line re-rendered from
/// the figure and its check written beside it, as a new map. When the
/// figure is gone, or no longer decodes, the row says so and keeps its line.
class UserFigureUseEditor extends StatelessWidget {
  const UserFigureUseEditor({
    super.key,
    required this.keyPrefix,
    required this.params,
    required this.onChanged,
    required this.dialect,
    this.showBeats = true,
    this.mixer = false,
  });

  /// Stem of each editor's key: `<keyPrefix>-<parameter key>`, and
  /// `<keyPrefix>-beats`.
  final String keyPrefix;
  final Map<String, Object?> params;
  final ValueChanged<Map<String, Object?>> onChanged;
  final Dialect dialect;
  final bool showBeats;
  final bool mixer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final userFigures = UserFiguresScope.catalogOf(context);
    final id = params[userFigureRefKey];
    final definition = id is String ? userFigures[id]?.definition : null;
    if (definition == null) {
      return Text(
        l10n.danceEditorUserFigureUnavailable,
        key: ValueKey('$keyPrefix-unavailable'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }
    final rawArgs = params[userFigureArgsKey];
    final args = rawArgs is Map
        ? rawArgs.cast<String, Object?>()
        : const <String, Object?>{};

    void report(Map<String, Object?> next) =>
        onChanged(refreshedUserFigureParams(next, userFigures));

    final beats = params['beats'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final param in definition.params)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: UserFigureArgumentEditor(
              keyPrefix: keyPrefix,
              param: param,
              value: args.containsKey(param.key)
                  ? args[param.key]
                  : param.defaultValue,
              dialect: dialect,
              mixer: mixer,
              // A choice with no default can be left unchosen, as it starts:
              // its wording leaves it out (#1023).
              allowNone:
                  param.kind == ParamKind.choice && param.defaultValue == null,
              noneLabel: AppLocalizations.of(context).danceEditorParamNotStated,
              onChanged: (value) => report({
                ...params,
                userFigureArgsKey: {...args, param.key: value},
              }),
            ),
          ),
        if (showBeats)
          FigureParamEditor(
            keyPrefix: keyPrefix,
            paramKey: 'beats',
            spec: ParamSpec(
              ParamKind.beats,
              defaultValue: definition.defaultBeats,
            ),
            value: beats is int ? beats : definition.defaultBeats,
            dialect: dialect,
            onChanged: (value) => report({...params, 'beats': value}),
          ),
      ],
    );
  }
}
