// Settings ▸ Experimental ▸ Suggestions (#2343).
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/persisted_preference.dart';
import '../../data/repositories_scope.dart';
import '../../data/suggestions_scope.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/collapsible_section.dart';
import '../../widgets/picker_suggestions.dart' show suggestionFactorTitle;
import '../../widgets/settings_dropdown_row.dart';

/// The Suggestions group of Settings ▸ Experimental: the toggle that adds
/// **Suggested** to the program builder's Sort menu, and the row into
/// [SuggestionSettingsScreen].
class SuggestionsSection extends StatelessWidget {
  const SuggestionsSection({super.key});

  Future<void> _onChanged(BuildContext context, bool value) async {
    SuggestionsEnabledScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await persistSetting(repos.settings, kSuggestionsEnabledKey, value);
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

  Future<void> _save(BuildContext context, SuggestionSettings settings) async {
    final notifier = SuggestionSettingsScope.notifierOf(context);
    if (notifier.value.isNewer || notifier.value.settings == settings) return;
    final repos = RepositoriesScope.of(context);
    final next = (settings: settings, isNewer: false);
    notifier.value = next;
    await persistSetting(
      repos.settings,
      kSuggestionSettingsKey,
      encodeSuggestionSettings(next),
    );
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
                        final messenger = ScaffoldMessenger.of(context);
                        await _save(context, settings.resetChoices());
                        messenger.showSnackBar(
                          SnackBar(content: Text(l10n.suggestionsResetDone)),
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
