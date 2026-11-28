// Settings ▸ Experimental ▸ Suggestions (#2343).
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/persisted_preference.dart';
import '../../data/repositories_scope.dart';
import '../../data/suggestions_scope.dart';
import '../../theme/app_spacing.dart';
import '../../utils/undo_snack_bar.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/collapsible_section.dart';
import '../../widgets/picker_suggestions.dart' show suggestionFactorTitle;
import '../../widgets/settings_dropdown_row.dart';

/// The Suggestions group of Settings ▸ Experimental: the toggle that adds
/// **Suggested** to the program builder's Sort menu; while it is on, **Use in
/// Perform's Swap this dance** (#2348); and the row into
/// [SuggestionSettingsScreen].
class SuggestionsSection extends StatelessWidget {
  const SuggestionsSection({super.key});

  Future<void> _onChanged(BuildContext context, bool value) async {
    SuggestionsEnabledScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await persistSetting(repos.settings, kSuggestionsEnabledKey, value);
  }

  Future<void> _onInPerformSwapChanged(BuildContext context, bool value) async {
    SuggestionsInPerformSwapScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await persistSetting(repos.settings, kSuggestionsInPerformSwapKey, value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final enabled = SuggestionsEnabledScope.of(context);
    return CollapsibleSection(
      sectionKey: const ValueKey('suggestions-section'),
      title: l10n.settingsSuggestionsHeader,
      expanded: enabled,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            key: const ValueKey('experimental-suggestions-enabled'),
            secondary: const Icon(Icons.auto_awesome_outlined),
            value: enabled,
            onChanged: (value) => _onChanged(context, value),
            title: Text(l10n.settingsSuggestionsEnabledTitle),
            subtitle: Text(l10n.settingsSuggestionsEnabledSubtitle),
            isThreeLine: true,
          ),
          // Shown only while Suggestions is on: off, it would change nothing.
          if (enabled)
            SwitchListTile(
              key: const ValueKey('experimental-suggestions-in-perform-swap'),
              secondary: const Icon(Icons.swap_horiz),
              value: SuggestionsInPerformSwapScope.of(context),
              onChanged: (value) => _onInPerformSwapChanged(context, value),
              title: Text(l10n.settingsSuggestionsInPerformSwapTitle),
              subtitle: Text(l10n.settingsSuggestionsInPerformSwapSubtitle),
              isThreeLine: true,
            ),
          ListTile(
            key: const ValueKey('experimental-suggestions-open'),
            leading: const Icon(Icons.tune),
            title: Text(l10n.settingsSuggestionsEditorTitle),
            subtitle: Text(l10n.settingsSuggestionsEditorSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SuggestionSettingsScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// **What suggestions look for**: one row per factor with Off / A little /
/// A lot, the curve's shape and the venue window, and Reset to defaults. No
/// numbers are shown.
///
/// A value saved by a newer build ([SuggestionSettingsRead.isNewer]) is shown
/// as the defaults, read-only, with a notice: an edit here would overwrite
/// choices this build cannot read.
class SuggestionSettingsScreen extends StatelessWidget {
  const SuggestionSettingsScreen({super.key});

  /// Saves [settings], unless a newer build's value is held or nothing
  /// changes; whether it saved. Undo passes the root navigator's context,
  /// which stays mounted after this screen closes and sits below the app's
  /// scopes.
  static Future<bool> _save(
    BuildContext context,
    SuggestionSettings settings,
  ) async {
    final notifier = SuggestionSettingsScope.notifierOf(context);
    if (notifier.value.isNewer || notifier.value.settings == settings) {
      return false;
    }
    final repos = RepositoriesScope.of(context);
    final next = (settings: settings, isNewer: false);
    notifier.value = next;
    await persistSetting(
      repos.settings,
      kSuggestionSettingsKey,
      encodeSuggestionSettings(next),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final read = SuggestionSettingsScope.of(context);
    final settings = read.settings;
    final editable = !read.isNewer;

    Widget weight(SuggestionFactor factor) {
      final title = suggestionFactorTitle(l10n, factor);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Semantics(
          label: l10n.suggestionWeightSemantic(title),
          container: true,
          child: SegmentedButton<SuggestionWeight>(
            key: ValueKey('suggestion-weight-${factor.name}'),
            expandedInsets: EdgeInsets.zero,
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: SuggestionWeight.off,
                label: Text(l10n.suggestionWeightOff),
              ),
              ButtonSegment(
                value: SuggestionWeight.aLittle,
                label: Text(l10n.suggestionWeightALittle),
              ),
              ButtonSegment(
                value: SuggestionWeight.aLot,
                label: Text(l10n.suggestionWeightALot),
              ),
            ],
            selected: {settings.weightOf(factor)},
            onSelectionChanged: editable
                ? (selection) => _save(
                    context,
                    settings.withWeight(factor, selection.first),
                  )
                : null,
          ),
        ),
      );
    }

    Widget factorHeader(SuggestionFactor factor, String help) => ListTile(
      title: Text(suggestionFactorTitle(l10n, factor)),
      subtitle: Text(help),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsSuggestionsEditorTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        children: [
          if (!editable)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Card(
                key: const ValueKey('suggestion-settings-newer'),
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(l10n.suggestionsNewerVersion),
                ),
              ),
            ),
          factorHeader(
            SuggestionFactor.matrixVariety,
            l10n.suggestionFactorMatrixVarietyHelp,
          ),
          weight(SuggestionFactor.matrixVariety),
          const SizedBox(height: AppSpacing.md),
          factorHeader(
            SuggestionFactor.formationBalance,
            l10n.suggestionFactorFormationBalanceHelp,
          ),
          weight(SuggestionFactor.formationBalance),
          const SizedBox(height: AppSpacing.md),
          factorHeader(
            SuggestionFactor.difficultyCurve,
            l10n.suggestionFactorDifficultyCurveHelp,
          ),
          weight(SuggestionFactor.difficultyCurve),
          SettingsDropdownRow(
            title: Text(l10n.suggestionCurveShapeLabel),
            dropdownBuilder: (expanded) =>
                AppDropdownField<DifficultyCurveShape>(
                  key: const ValueKey('suggestion-curve-shape'),
                  compact: true,
                  fillWidth: expanded,
                  value: settings.curveShape,
                  onChanged: editable
                      ? (shape) {
                          _save(context, settings.copyWith(curveShape: shape));
                        }
                      : null,
                  entries: [
                    AppDropdownEntry(
                      value: DifficultyCurveShape.buildThenEase,
                      label: l10n.suggestionCurveBuildThenEase,
                    ),
                    AppDropdownEntry(
                      value: DifficultyCurveShape.even,
                      label: l10n.suggestionCurveEven,
                    ),
                    AppDropdownEntry(
                      value: DifficultyCurveShape.off,
                      label: l10n.suggestionWeightOff,
                    ),
                  ],
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          factorHeader(
            SuggestionFactor.venueRecency,
            l10n.suggestionFactorVenueRecencyHelp,
          ),
          weight(SuggestionFactor.venueRecency),
          SettingsDropdownRow(
            title: Text(l10n.collectionFacetWithin),
            dropdownBuilder: (expanded) => AppDropdownField<VenueRecencyWindow>(
              key: const ValueKey('suggestion-venue-window'),
              compact: true,
              fillWidth: expanded,
              value: settings.venueWindow,
              onChanged: editable
                  ? (window) {
                      _save(context, settings.copyWith(venueWindow: window));
                    }
                  : null,
              entries: [
                for (final window in VenueRecencyWindow.values)
                  AppDropdownEntry(
                    value: window,
                    label: l10n.collectionFacetWithinMonths(window.months),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: const ValueKey('suggestion-settings-reset'),
                icon: const Icon(Icons.restart_alt),
                label: Text(l10n.suggestionsResetDefaults),
                onPressed: editable && !settings.hasDefaultChoices
                    ? () async {
                        // Reset can be undone, so it acts at once and offers
                        // Undo rather than asking first (ux.md, "Undo
                        // everywhere, destructive confirms only where undo is
                        // impossible").
                        final messenger = ScaffoldMessenger.of(context);
                        // Undo can run after this screen has closed.
                        final rootContext = Navigator.of(
                          context,
                          rootNavigator: true,
                        ).context;
                        final accessibleNavigation =
                            MediaQuery.accessibleNavigationOf(context);
                        // The library the reset was made in: after a restore or
                        // a reset to a clean install, Undo must not write the
                        // old choices into the new one.
                        final library = RepositoriesScope.of(context);
                        final before = settings;
                        // Nothing written (a newer build's value arrived):
                        // nothing to announce or undo.
                        if (!await _save(context, before.resetChoices())) {
                          return;
                        }
                        showUndoSnackBar(
                          messenger,
                          message: l10n.suggestionsResetDone,
                          undoLabel: l10n.commonUndo,
                          undoFailedMessage: l10n.commonUndoFailed,
                          accessibleNavigation: accessibleNavigation,
                          actionKey: const ValueKey(
                            'suggestion-settings-reset-undo',
                          ),
                          onUndo: () async {
                            // Puts back only the six choices, onto what is
                            // held now, so a peer's kept parts that synced in
                            // meanwhile survive. A choice made since the reset,
                            // here or on another device, is not overwritten:
                            // Undo reports that it failed instead.
                            if (!rootContext.mounted ||
                                !identical(
                                  RepositoriesScope.of(rootContext),
                                  library,
                                )) {
                              throw StateError('the library has changed');
                            }
                            final current = SuggestionSettingsScope.notifierOf(
                              rootContext,
                            ).value;
                            if (current.isNewer ||
                                !current.settings.hasDefaultChoices) {
                              throw StateError(
                                'suggestion choices changed since the reset',
                              );
                            }
                            await _save(
                              rootContext,
                              current.settings.copyWith(
                                matrixVariety: before.matrixVariety,
                                formationBalance: before.formationBalance,
                                difficultyCurve: before.difficultyCurve,
                                curveShape: before.curveShape,
                                venueRecency: before.venueRecency,
                                venueWindow: before.venueWindow,
                              ),
                            );
                          },
                        );
                      }
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
