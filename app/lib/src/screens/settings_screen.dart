import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/backup_io.dart';
import '../data/import_io.dart';
import '../diagnostics/crash_log_io.dart';
import '../diagnostics/crash_log_store.dart';
import '../theme/app_spacing.dart';
import 'settings/about_section.dart';
import 'settings/appearance_section.dart';
import 'settings/defaults_section.dart';
import 'settings/diagnostics_section.dart';
import 'settings/dialect_section.dart';
import 'settings/general_section.dart';
import 'settings/program_section.dart';
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
    this.crashLogStore,
    this.diagnosticsLogSaver,
    this.sensitiveTermsProvider,
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

  /// Test seam for the Diagnostics section's crash-log store; defaults to the
  /// app-support store (issue #458).
  final CrashLogStore? crashLogStore;

  /// Test seam for delivering an exported diagnostics log; defaults to
  /// [saveDiagnosticsLog].
  final LogSaver? diagnosticsLogSaver;

  /// Test seam for the Diagnostics scrubbed-export redaction terms; defaults to
  /// gathering them from the ambient repositories.
  final SensitiveTermsProvider? sensitiveTermsProvider;

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
  general(Icons.tune_outlined, Icons.tune),
  program(Icons.grid_view_outlined, Icons.grid_view),
  appearance(Icons.palette_outlined, Icons.palette),
  dialect(Icons.groups_outlined, Icons.groups),
  regional(Icons.translate_outlined, Icons.translate),
  defaults(Icons.settings_suggest_outlined, Icons.settings_suggest),
  updates(Icons.system_update_alt_outlined, Icons.system_update_alt),
  diagnostics(Icons.bug_report_outlined, Icons.bug_report),
  about(Icons.info_outline, Icons.info);

  const _SettingsSection(this.icon, this.selectedIcon);

  final IconData icon;
  final IconData selectedIcon;
}

/// The localized sidebar/app-bar label for [section].
///
/// Every section title is sourced from the ARB (`AppLocalizations`) so the
/// section navigation renders in the selected UI language.
String _sectionLabel(BuildContext context, _SettingsSection section) {
  final l10n = AppLocalizations.of(context);
  return switch (section) {
    _SettingsSection.general => l10n.settingsGeneralTitle,
    _SettingsSection.program => l10n.settingsProgramTitle,
    _SettingsSection.appearance => l10n.settingsAppearanceTitle,
    _SettingsSection.dialect => l10n.settingsDialectTitle,
    _SettingsSection.regional => l10n.settingsLanguageRegionTitle,
    _SettingsSection.defaults => l10n.settingsDefaultsTitle,
    _SettingsSection.updates => l10n.settingsUpdatesTitle,
    _SettingsSection.diagnostics => l10n.settingsDiagnosticsTitle,
    _SettingsSection.about => l10n.settingsAboutTitle,
  };
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
      case _SettingsSection.program:
        return const ProgramSection();
      case _SettingsSection.updates:
        return const UpdatesSection();
      case _SettingsSection.diagnostics:
        return DiagnosticsSection(
          store: widget.crashLogStore,
          logSaver: widget.diagnosticsLogSaver,
          sensitiveTermsProvider: widget.sensitiveTermsProvider,
        );
      case _SettingsSection.about:
        return AboutSection(onOpenGuide: widget.onOpenGuide);
    }
  }

  void _openSection(_SettingsSection section) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
          appBar: AppBar(title: Text(_sectionLabel(routeContext, section))),
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
              title: Text(AppLocalizations.of(context).settingsTitle),
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
            title: Text(AppLocalizations.of(context).settingsTitle),
            automaticallyImplyLeading: false,
          ),
          body: ListView(
            children: [
              for (final s in _SettingsSection.values)
                ListTile(
                  key: ValueKey('settings-nav-${s.name}'),
                  leading: Icon(s.icon),
                  title: Text(_sectionLabel(context, s)),
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
            title: Text(_sectionLabel(context, s)),
            selected: s == selected,
            onTap: () => onSelect(s),
          ),
      ],
    );
  }
}
