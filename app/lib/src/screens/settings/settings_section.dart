import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// The selectable sections in Settings. Declaration order is sidebar order; add
/// a value (and its content in `SettingsScreen`'s `_content`) to add a page.
///
/// Public because the settings search indexes a row by its section
/// (`settings_search.dart`), and the shell reaches the search through
/// `SettingsCommands`.
enum SettingsSection {
  general(Icons.tune_outlined, Icons.tune),
  program(Icons.event_note_outlined, Icons.event_note),
  appearance(Icons.palette_outlined, Icons.palette),
  dialect(Icons.groups_outlined, Icons.groups),
  regional(Icons.translate_outlined, Icons.translate),
  defaults(Icons.settings_suggest_outlined, Icons.settings_suggest),
  updates(Icons.update_outlined, Icons.update),
  diagnostics(Icons.bug_report_outlined, Icons.bug_report),
  experimental(Icons.psychology_outlined, Icons.psychology),
  about(Icons.info_outline, Icons.info);

  const SettingsSection(this.icon, this.selectedIcon);

  final IconData icon;
  final IconData selectedIcon;
}

/// The localized sidebar/app-bar label for [section].
///
/// Every section title is sourced from the ARB (`AppLocalizations`) so the
/// section navigation renders in the selected UI language.
String settingsSectionLabel(BuildContext context, SettingsSection section) =>
    settingsSectionLabelOf(AppLocalizations.of(context), section);

/// [settingsSectionLabel] without a `BuildContext`, for the search index and
/// its tests.
String settingsSectionLabelOf(AppLocalizations l10n, SettingsSection section) =>
    switch (section) {
      SettingsSection.general => l10n.settingsGeneralTitle,
      SettingsSection.program => l10n.settingsProgramTitle,
      SettingsSection.appearance => l10n.settingsAppearanceTitle,
      SettingsSection.dialect => l10n.settingsDialectTitle,
      SettingsSection.regional => l10n.settingsLanguageRegionTitle,
      SettingsSection.defaults => l10n.settingsDefaultsTitle,
      SettingsSection.updates => l10n.settingsUpdatesTitle,
      SettingsSection.diagnostics => l10n.settingsDiagnosticsTitle,
      SettingsSection.experimental => l10n.settingsExperimentalTitle,
      SettingsSection.about => l10n.settingsAboutTitle,
    };
