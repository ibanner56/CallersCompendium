import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/active_dialect_scope.dart';
import '../../search/facet_labels.dart';
import '../../theme/app_spacing.dart';
import 'custom_figure_detail.dart' show compoundParamKindLabel;

/// Maps one of the user's own figures onto the shipped figure [target] that
/// now has its name (#1023, maintainer decision 5): which of the target's
/// parameters each of theirs becomes, and which of its values each of their
/// choices becomes. Pops with the [UserFigureSwitch] once every one is
/// chosen and the user taps Switch; the caller confirms and switches.
/// Nothing is written here.
///
/// A parameter or value whose name the target shares is chosen to start
/// with; the rest are left for the user. A parameter the target has nothing
/// of its kind for can't be mapped, and says so: the user can remove it from
/// their figure first, or rename theirs instead.
class UserFigureSwitchScreen extends StatefulWidget {
  const UserFigureSwitchScreen({
    super.key,
    required this.figure,
    required this.target,
  });

  final UserFigureDefinition figure;

  /// The shipped move or alias id.
  final String target;

  @override
  State<UserFigureSwitchScreen> createState() => _UserFigureSwitchScreenState();
}

class _UserFigureSwitchScreenState extends State<UserFigureSwitchScreen> {
  static final FigureRenderer _renderer = FigureRenderer(contraTaxonomy);

  final Map<String, String> _params = {};
  final Map<String, Map<String, String>> _choices = {};

  List<String> _targetsOf(UserFigureParam param) =>
      userFigureSwitchTargets(param, widget.target, contraTaxonomy);

  List<String> _valuesOf(String targetKey) =>
      userFigureSwitchValues(widget.target, targetKey, contraTaxonomy);

  @override
  void initState() {
    super.initState();
    for (final param in widget.figure.params) {
      if (_targetsOf(param).contains(param.key)) {
        _setParam(param, param.key);
      }
    }
  }

  /// Maps [param] to [targetKey], keeping each choice's value the target
  /// parameter also has, and starting a choice whose label is one of its
  /// values at that value.
  void _setParam(UserFigureParam param, String targetKey) {
    _params[param.key] = targetKey;
    if (param.kind != ParamKind.choice) return;
    final values = _valuesOf(targetKey);
    final before = _choices[param.key] ?? const {};
    _choices[param.key] = {
      for (final choice in param.choices)
        if (before[choice.id] case final value? when values.contains(value))
          choice.id: value
        else if (values.contains(normalizeGlossaryName(choice.label)))
          choice.id: normalizeGlossaryName(choice.label),
    };
  }

  UserFigureSwitch get _mapping => UserFigureSwitch(
    target: widget.target,
    params: _params,
    choices: _choices,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dialect = ActiveDialectScope.of(context);
    final targetName = _renderer.displayMoveName(widget.target, dialect);
    final targetParams =
        contraTaxonomy.resolve(widget.target)?.params ?? const {};
    final complete = userFigureSwitchProblems(
      widget.figure,
      _mapping,
      contraTaxonomy,
    ).isEmpty;

    String targetLabel(String key) {
      final name = figureParamKeyLabel(l10n, key, moveId: widget.target);
      final spec = targetParams[key];
      return spec == null
          ? name
          : l10n.compoundParamWithKind(
              name,
              compoundParamKindLabel(l10n, spec.kind),
            );
    }

    final children = <Widget>[
      Text(
        l10n.userFigureSwitchIntro(targetName),
        key: const ValueKey('user-figure-switch-intro'),
      ),
    ];
    for (final param in widget.figure.params) {
      final all = _targetsOf(param);
      // A target another of the user's parameters already has is left out:
      // two can't share one.
      final taken = {
        for (final MapEntry(:key, :value) in _params.entries)
          if (key != param.key) value,
      };
      final targets = [
        for (final key in all)
          if (!taken.contains(key)) key,
      ];
      final paramName = l10n.compoundParamWithKind(
        param.key,
        compoundParamKindLabel(l10n, param.kind),
      );
      children.add(const SizedBox(height: AppSpacing.lg));
      if (targets.isEmpty) {
        children.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_outlined,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  all.isEmpty
                      ? l10n.userFigureSwitchNoTarget(targetName, paramName)
                      : l10n.userFigureSwitchAllTaken(targetName, paramName),
                  key: ValueKey('user-figure-switch-none-${param.key}'),
                ),
              ),
            ],
          ),
        );
        continue;
      }
      children.add(
        DropdownButtonFormField<String>(
          key: ValueKey('user-figure-switch-param-${param.key}'),
          initialValue: _params[param.key],
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.userFigureSwitchParam(paramName),
          ),
          items: [
            for (final key in targets)
              DropdownMenuItem(value: key, child: Text(targetLabel(key))),
          ],
          onChanged: (key) {
            if (key != null) setState(() => _setParam(param, key));
          },
        ),
      );
      final mappedTo = _params[param.key];
      if (param.kind != ParamKind.choice || mappedTo == null) continue;
      final values = _valuesOf(mappedTo);
      final valueSpec = targetParams[mappedTo];
      for (final choice in param.choices) {
        children.add(
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: AppSpacing.lg,
              top: AppSpacing.sm,
            ),
            child: DropdownButtonFormField<String>(
              // Keyed by the target too: a new target starts the menu over.
              key: ValueKey(
                'user-figure-switch-choice-${param.key}-${choice.id}-$mappedTo',
              ),
              initialValue: _choices[param.key]?[choice.id],
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.userFigureSwitchChoice(
                  _renderer.renderFreeText(choice.label, dialect),
                ),
              ),
              items: [
                for (final value in values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(
                      valueSpec == null
                          ? value
                          : figureParamChoiceLabel(
                              l10n,
                              valueSpec,
                              dialect,
                              value,
                            ),
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => (_choices[param.key] ??= {})[choice.id] = value);
              },
            ),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.userFigureSwitchTitle(targetName)),
        actions: [
          TextButton(
            key: const ValueKey('user-figure-switch-save'),
            onPressed: complete
                ? () => Navigator.of(context).pop(_mapping)
                : null,
            child: Text(l10n.userFigureSwitchAction),
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('user-figure-switch'),
        padding: const EdgeInsets.all(AppSpacing.md),
        children: children,
      ),
    );
  }
}
