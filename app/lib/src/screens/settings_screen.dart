import 'package:flutter/material.dart';

import '../data/backup_io.dart';
import '../data/import_io.dart';
import '../theme/app_spacing.dart';
import 'settings/about_section.dart';
import 'settings/appearance_section.dart';
import 'settings/defaults_section.dart';
import 'settings/dialect_section.dart';
import 'settings/general_section.dart';
import 'settings/regional_section.dart';
import 'settings/updates_section.dart';

/// Re-exported so existing consumers (`main.dart`, the Perform screens, tests)
/// can keep importing the persistence keys from `settings_screen.dart`.
export 'settings/settings_keys.dart';

/// Settings screen: a master–detail layout with a sidebar of sections and a
/// content pane. On wide viewports the sidebar and the selected section sit
/// side by side; on narrow viewports the sidebar is a list whose rows push the
/// section as its own page. Adding a settings page is just a new
/// [_SettingsSection] value plus its content in [_SettingsScreenState._content].
///
/// Changes take effect immediately (live update via the relevant scope).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.backupSaver,
    this.backupPicker,
    this.importPicker,
    this.urlFetcher,
    this.onOpenGuide,
  });

  /// Test seam for delivering an exported backup file; defaults to
  /// [saveBackupToFile] (temp file + OS share sheet).
  final BackupSaver? backupSaver;

  /// Test seam for choosing a backup file to restore; defaults to
  /// [pickBackupFile] (native open-file dialog).
  final BackupPicker? backupPicker;

  /// Test seam for choosing an import file; defaults to [pickImportFile]
  /// (native open-file dialog). Forwarded to [ImportReviewScreen].
  final ImportPicker? importPicker;

  /// Test seam for fetching an import URL; defaults to [fetchImportUrl] (real
  /// HTTP GET). Forwarded to [ImportReviewScreen].
  final UrlFetcher? urlFetcher;

  /// Selects the shell's User Guide destination instead of the About section
  /// pushing a full-screen guide route. Supplied by [AppShell]; when `null`
  /// (e.g. Settings shown standalone in a test) the About tile falls back to
  /// pushing the guide.
  final VoidCallback? onOpenGuide;

  /// Viewport width (logical px) at/above which the sidebar and content sit
  /// side by side instead of the sidebar pushing a detail page.
  static const double sideBySideBreakpoint = 720;

  /// Width (logical px) of the section sidebar in the side-by-side layout.
  ///
  /// Settings now renders inside [AppShell], so the app's Material 3
  /// [NavigationRail] (default `minWidth` 80) sits to the left of this sidebar.
  /// Trimmed from the pre-embed 260 by ~that rail width so the combined left
  /// chrome matches the old full-screen Settings footprint. "Appearance" (the
  /// longest section label) still fits without truncation at this width.
  static const double _sideBySideSidebarWidth = 180;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// The selectable sections in Settings. Declaration order is sidebar order; add
/// a value (and its content in [_SettingsScreenState._content]) to add a page.
enum _SettingsSection {
  general('General', Icons.tune_outlined, Icons.tune),
  appearance('Appearance', Icons.palette_outlined, Icons.palette),
  dialect('Dialect', Icons.groups_outlined, Icons.groups),
  regional('Language & region', Icons.translate_outlined, Icons.translate),
  defaults('Defaults', Icons.settings_suggest_outlined, Icons.settings_suggest),
  updates('Updates', Icons.system_update_alt_outlined, Icons.system_update_alt),
  about('About', Icons.info_outline, Icons.info);

  const _SettingsSection(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _SettingsScreenState extends State<SettingsScreen> {
  _SettingsSection _section = _SettingsSection.appearance;

  /// Builds the content pane for [section]. Each section is its own widget that
  /// owns its async I/O and load-race guards; this shell only routes to them and
  /// threads the backup/import test seams into the General section.
  Widget _content(BuildContext context, _SettingsSection section) {
    switch (section) {
      case _SettingsSection.appearance:
        return const AppearanceSection();
      case _SettingsSection.dialect:
        return const DialectSection();
      case _SettingsSection.regional:
        return const RegionalSection();
      case _SettingsSection.general:
        return GeneralSection(
          backupSaver: widget.backupSaver,
          backupPicker: widget.backupPicker,
          importPicker: widget.importPicker,
          urlFetcher: widget.urlFetcher,
        );
      case _SettingsSection.defaults:
        return const DefaultsSection();
      case _SettingsSection.updates:
        return const UpdatesSection();
      case _SettingsSection.about:
        return AboutSection(onOpenGuide: widget.onOpenGuide);
    }
  }

  void _openSection(_SettingsSection section) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
          appBar: AppBar(title: Text(section.label)),
          body: _content(routeContext, section),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide =
            constraints.maxWidth >= SettingsScreen.sideBySideBreakpoint;

        if (sideBySide) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Settings'),
              automaticallyImplyLeading: false,
            ),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: SettingsScreen._sideBySideSidebarWidth,
                  child: _SettingsSidebar(
                    selected: _section,
                    onSelect: (s) => setState(() => _section = s),
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: _content(context, _section)),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
            automaticallyImplyLeading: false,
          ),
          body: ListView(
            children: [
              for (final s in _SettingsSection.values)
                ListTile(
                  key: ValueKey('settings-nav-${s.name}'),
                  leading: Icon(s.icon),
                  title: Text(s.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openSection(s),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The sidebar list of settings sections (side-by-side layout). Selection is
/// conveyed by the highlighted tile plus its filled icon — never color alone.
class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({required this.selected, required this.onSelect});

  final _SettingsSection selected;
  final ValueChanged<_SettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      children: [
        for (final s in _SettingsSection.values)
          ListTile(
            key: ValueKey('settings-nav-${s.name}'),
            leading: Icon(s == selected ? s.selectedIcon : s.icon),
            title: Text(s.label),
            selected: s == selected,
            onTap: () => onSelect(s),
          ),
      ],
    );
  }
}
