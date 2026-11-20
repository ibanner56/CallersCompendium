// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'settings_keys.dart';
import '../../data/app_theme_labels_l10n.dart';
import '../../data/app_theme_scope.dart';
import '../../data/colour_dance_theme_scope.dart';
import '../../data/custom_themes_scope.dart';
import '../../data/formation_colors_scope.dart';
import '../../data/persisted_preference.dart';
import '../../data/repositories_scope.dart';
import '../../data/set_list_color_coding_scope.dart';
import '../../widgets/section_header.dart';
import '../formation_colors_screen.dart';
import '../tag_manager_screen.dart';
import '../theme_screen.dart';

/// The Appearance settings section. The theme itself is chosen on its own
/// Theme screen (`theme_screen.dart`, issue #2228), which this section opens
/// from a row naming the active theme; the rest are the section's own toggles
/// and entries.
class AppearanceSection extends StatefulWidget {
  const AppearanceSection({super.key});

  @override
  State<AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<AppearanceSection> {
  Future<void> _onColourDanceThemeChanged(bool value) async {
    // Drive the live scope (loaded from settings at startup and kept current on
    // restore) so the switch reflects the real state and open dance views
    // re-tint instantly; then persist. Reading the scope in [build] means this
    // rebuilds whenever the setting changes elsewhere.
    ColourDanceThemeScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await persistSetting(repos.settings, kColourDanceThemeKey, value);
  }

  /// Persists the "colour-code set-list rows" toggle (issue #270): flip the
  /// live scope notifier immediately, then write through in the background —
  /// the same optimistic pattern as the other Appearance/General toggles.
  Future<void> _onSetListColorCodingChanged(bool value) async {
    final repos = RepositoriesScope.of(context);
    SetListColorCodingScope.notifierOf(context).value = value;
    await persistSetting(repos.settings, kSetListColorCodingKey, value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // A custom theme wins while it is active, so it is the one to name.
    final activeThemeName =
        CustomThemesScope.of(context).active?.name ??
        appThemeLabel(l10n, AppThemeScope.of(context));
    return _AppearanceView(
      activeThemeName: activeThemeName,
      colourDanceTheme: ColourDanceThemeScope.of(context),
      onColourDanceThemeChanged: _onColourDanceThemeChanged,
      setListColorCoding: SetListColorCodingScope.of(context),
      onSetListColorCodingChanged: _onSetListColorCodingChanged,
    );
  }
}

/// The Appearance section: a row into the Theme screen, then the toggles.
class _AppearanceView extends StatelessWidget {
  const _AppearanceView({
    required this.activeThemeName,
    required this.colourDanceTheme,
    required this.onColourDanceThemeChanged,
    required this.setListColorCoding,
    required this.onSetListColorCodingChanged,
  });

  /// The name of the theme in use: a saved custom theme's, else the
  /// built-in selection's.
  final String activeThemeName;
  final bool colourDanceTheme;
  final ValueChanged<bool> onColourDanceThemeChanged;
  final bool setListColorCoding;
  final ValueChanged<bool> onSetListColorCodingChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      children: [
        SectionHeader(title: l10n.settingsAppearanceThemeHeader),
        ListTile(
          key: const ValueKey('appearance-theme'),
          leading: const Icon(Icons.color_lens_outlined),
          title: Text(activeThemeName),
          subtitle: Text(l10n.settingsAppearanceThemeSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const ThemeScreen())),
        ),
        SectionHeader(title: l10n.settingsAppearanceEasterEggsHeader),
        SwitchListTile(
          key: const ValueKey('appearance-colour-dance-theme'),
          value: colourDanceTheme,
          onChanged: onColourDanceThemeChanged,
          title: Text(l10n.settingsAppearanceColourDanceTitle),
          subtitle: Text(l10n.settingsAppearanceColourDanceSubtitle),
          isThreeLine: true,
        ),
        SectionHeader(title: l10n.settingsAppearanceSetListsHeader),
        SwitchListTile(
          key: const ValueKey('appearance-set-list-color-coding'),
          title: Text(l10n.settingsAppearanceSetListColorTitle),
          subtitle: Text(l10n.settingsAppearanceSetListColorSubtitle),
          value: setListColorCoding,
          onChanged: onSetListColorCodingChanged,
        ),
        SectionHeader(title: l10n.settingsAppearanceFormationColoursHeader),
        ListTile(
          key: const ValueKey('appearance-formation-colours'),
          leading: const Icon(Icons.palette_outlined),
          title: Text(l10n.settingsAppearanceFormationColoursTitle),
          subtitle: Text(l10n.settingsAppearanceFormationColoursSubtitle),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => FormationColorsScreen(
                controller: FormationColorsScope.controllerOf(context),
              ),
            ),
          ),
        ),
        SectionHeader(title: l10n.settingsAppearanceTagColoursHeader),
        // Colours live in the Tags manager now; this entry opens it, so users
        // find colours where they left them (D-N2-3).
        ListTile(
          key: const ValueKey('appearance-tag-colours'),
          leading: const Icon(Icons.label_outline),
          title: Text(l10n.settingsAppearanceTagColoursTitle),
          subtitle: Text(l10n.settingsAppearanceTagColoursSubtitle),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const TagManagerScreen()),
          ),
        ),
      ],
    );
  }
}
