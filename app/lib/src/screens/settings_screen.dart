import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/backup_io.dart';
import '../data/import_io.dart';
import '../diagnostics/crash_log_io.dart';
import '../export/csv_export.dart';
import '../diagnostics/crash_log_store.dart';
import '../theme/app_spacing.dart';
import 'settings/about_section.dart';
import 'settings/appearance_section.dart';
import 'settings/defaults_section.dart';
import 'settings/diagnostics_section.dart';
import 'settings/dialect_section.dart';
import 'settings/experimental_section.dart';
import 'settings/general_section.dart';
import 'settings/program_section.dart';
import 'settings/regional_section.dart';
import 'settings/updates_section.dart';
import '../theme/app_breakpoints.dart';

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
    this.csvExportDelivery = const CsvExportDelivery(),
  });

  /// Delivers the dances CSV export from General ▸ Backup & restore (#2332);
  /// a test seam forwarded to [GeneralSection].
  final CsvExportDelivery csvExportDelivery;

  /// Test seam for delivering an exported backup file; defaults to
  /// [saveBackupToFile] (temp file + OS share sheet).
  final BackupSaver? backupSaver;

  /// Test seam for choosing a backup file to restore; defaults to
  /// [pickBackupFile] (native open-file dialog).
  final BackupPicker? backupPicker;

  /// Test seam for choosing an import file as canned text; when null the import
  /// screen opens the native open-file dialog ([pickImportAnyFile]). Injecting
  /// it skips extension-based source detection. Forwarded to
  /// [ImportReviewScreen].
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

  /// Narrowest the section sidebar gets in the side-by-side layout (logical
  /// px). Settings renders inside [AppShell], so the app's [NavigationRail]
  /// sits to the left of the sidebar; this keeps the two together near the
  /// old full-screen Settings footprint.
  static const double _sidebarMinWidth = 180;

  /// Widest the section sidebar gets, so a long label (or very large text)
  /// wraps between words, or falls back to the one-pane layout, rather than
  /// squeezing the open section at the narrowest side-by-side window.
  static const double _sidebarMaxWidth = 280;

  /// What a sidebar tile spends beside its label: the Material 3 [ListTile]'s
  /// 16 px start and 24 px end padding, the 24 px icon, and the 16 px gap
  /// between icon and label.
  static const double _sidebarTileChrome = 16 + 24 + 16 + 24;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// The selectable sections in Settings. Declaration order is sidebar order; add
/// a value (and its content in [_SettingsScreenState._content]) to add a page.
enum _SettingsSection {
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
    _SettingsSection.experimental => l10n.settingsExperimentalTitle,
    _SettingsSection.about => l10n.settingsAboutTitle,
  };
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// The section the side-by-side layout shows: General, the first in the
  /// sidebar, until another is chosen.
  _SettingsSection _section = _SettingsSection.general;

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
          csvExportDelivery: widget.csvExportDelivery,
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
      case _SettingsSection.experimental:
        return ExperimentalSection(backupSaver: widget.backupSaver);
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

  static final _whitespace = RegExp(r'\s+');

  /// The sidebar's width: enough for its longest label on one line, in the
  /// current language and text size, within
  /// [SettingsScreen._sidebarMinWidth]..[SettingsScreen._sidebarMaxWidth].
  /// A fixed width wrapped "Language & region" onto two lines.
  ///
  /// `null` when even the longest single *word* would not fit at the widest
  /// sidebar (very large text, or a long word in another language): a label
  /// may then wrap between words, but never inside one, so Settings shows its
  /// one-pane layout instead.
  double? _sidebarWidth(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    var widestLabel = 0.0;
    var widestWord = 0.0;
    for (final s in _SettingsSection.values) {
      final label = _sectionLabel(context, s);
      final labelWidth = measure(label);
      if (labelWidth > widestLabel) widestLabel = labelWidth;
      for (final word in label.split(_whitespace)) {
        if (word.isEmpty) continue;
        final wordWidth = measure(word);
        if (wordWidth > widestWord) widestWord = wordWidth;
      }
    }
    const chrome = SettingsScreen._sidebarTileChrome;
    if (widestWord + chrome > SettingsScreen._sidebarMaxWidth) return null;
    return (widestLabel + chrome).ceilToDouble().clamp(
      SettingsScreen._sidebarMinWidth,
      SettingsScreen._sidebarMaxWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Side by side from the split width of the *window*, as Collection and
        // Programs: between the rail and split widths every destination,
        // Settings included, shows one pane beside the rail.
        final sidebarWidth =
            AppBreakpoints.showsSplit(context, constraints.maxWidth)
            ? _sidebarWidth(context)
            : null;

        if (sidebarWidth != null) {
          return Scaffold(
            appBar: AppBar(
              title: Text(AppLocalizations.of(context).settingsTitle),
              automaticallyImplyLeading: false,
            ),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: sidebarWidth,
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
