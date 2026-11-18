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
import 'settings/experimental_section.dart';
import 'settings/general_section.dart';
import 'settings/program_section.dart';
import 'settings/regional_section.dart';
import 'settings/settings_search.dart';
import 'settings/settings_section.dart';
import 'settings/updates_section.dart';

/// Re-exported so existing consumers (`main.dart`, the Perform screens, tests)
/// can keep importing the persistence keys from `settings_screen.dart`.
export 'settings/settings_keys.dart';
export 'settings/settings_section.dart' show SettingsSection;

/// Settings screen: a master–detail layout with a sidebar of sections and a
/// content pane. On wide viewports the sidebar and the selected section sit
/// side by side; on narrow viewports the sidebar is a list whose rows push the
/// section as its own page. Adding a settings page is just a new
/// [SettingsSection] value plus its content in [_SettingsScreenState._content].
///
/// A search bar above the panes finds a setting by name across every section
/// ([settingsSearchIndex]), since most settings are not on screen while another
/// section is open. Ctrl/Cmd-F focuses it from anywhere on the tab
/// ([SettingsCommands]).
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
    this.commands,
  });

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

  /// The shell's handle on this screen's commands (the settings search, which
  /// Ctrl/Cmd-F focuses), as `CollectionCommands` is for the Collection.
  final SettingsCommands? commands;

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

/// The Settings screen's own commands, for callers above it: the app shell runs
/// [focusSearch] for Ctrl/Cmd-F (PLAT-7).
///
/// Returns whether a mounted Settings screen took it, as [CollectionCommands]
/// does.
class SettingsCommands {
  _SettingsScreenState? _screen;

  /// Moves the keyboard focus to the settings search box and selects its text.
  bool focusSearch() => _screen?._focusSearch() ?? false;
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsSection _section = SettingsSection.appearance;

  /// The settings-search box's state. The field is always built (wide and
  /// narrow layouts alike) so Ctrl/Cmd-F can focus it without opening anything.
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.commands?._screen = this;
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.commands, widget.commands)) {
      if (oldWidget.commands?._screen == this) {
        oldWidget.commands?._screen = null;
      }
      widget.commands?._screen = this;
    }
  }

  @override
  void dispose() {
    if (widget.commands?._screen == this) widget.commands?._screen = null;
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Moves the keyboard focus to the settings search box and selects what is
  /// already there, as the Collection's search does (Ctrl/Cmd-F).
  bool _focusSearch() {
    _searchFocus.requestFocus();
    _search.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _search.text.length,
    );
    return true;
  }

  /// Shows the section that holds a search result: in place on the wide
  /// layout, as its own page on the narrow one, and clears the query so the
  /// normal navigation comes back.
  void _openResult(SettingsSearchEntry entry, {required bool sideBySide}) {
    setState(() {
      _search.clear();
      _section = entry.section;
    });
    if (!sideBySide) _openSection(entry.section);
  }

  /// Builds the content pane for [section]. Each section is its own widget that
  /// owns its async I/O and load-race guards; this shell only routes to them and
  /// threads the backup/import test seams into the General section.
  Widget _content(BuildContext context, SettingsSection section) {
    switch (section) {
      case SettingsSection.appearance:
        return const AppearanceSection();
      case SettingsSection.dialect:
        return const DialectSection();
      case SettingsSection.regional:
        return const RegionalSection();
      case SettingsSection.general:
        return GeneralSection(
          backupSaver: widget.backupSaver,
          backupPicker: widget.backupPicker,
          importPicker: widget.importPicker,
          urlFetcher: widget.urlFetcher,
        );
      case SettingsSection.defaults:
        return const DefaultsSection();
      case SettingsSection.program:
        return const ProgramSection();
      case SettingsSection.updates:
        return const UpdatesSection();
      case SettingsSection.diagnostics:
        return DiagnosticsSection(
          store: widget.crashLogStore,
          logSaver: widget.diagnosticsLogSaver,
          sensitiveTermsProvider: widget.sensitiveTermsProvider,
        );
      case SettingsSection.experimental:
        return ExperimentalSection(backupSaver: widget.backupSaver);
      case SettingsSection.about:
        return AboutSection(onOpenGuide: widget.onOpenGuide);
    }
  }

  void _openSection(SettingsSection section) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
          appBar: AppBar(
            title: Text(settingsSectionLabel(routeContext, section)),
          ),
          body: _content(routeContext, section),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide =
            constraints.maxWidth >= SettingsScreen.sideBySideBreakpoint;
        final query = _search.text.trim();
        // A row a section shows only in some states (an update that was found,
        // Custom Figures on) is not offered when it is not on screen: the
        // result would open a section without it.
        final results = query.isEmpty
            ? const <SettingsSearchEntry>[]
            : [
                for (final entry in searchSettings(l10n, query: query))
                  if (entry.isVisible(context)) entry,
              ];
        final searchBar = _SettingsSearchBar(
          controller: _search,
          focusNode: _searchFocus,
          onChanged: (_) => setState(() {}),
          onClear: () => setState(_search.clear),
        );
        final appBar = AppBar(
          title: Text(l10n.settingsTitle),
          automaticallyImplyLeading: false,
        );
        // While a query is typed, the results replace the navigation — either
        // pane on the wide layout, the section list on the narrow one — because
        // a match can live in any section.
        final Widget panes = query.isEmpty
            ? (sideBySide
                  ? Row(
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
                    )
                  : ListView(
                      children: [
                        for (final s in SettingsSection.values)
                          ListTile(
                            key: ValueKey('settings-nav-${s.name}'),
                            leading: Icon(s.icon),
                            title: Text(settingsSectionLabel(context, s)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openSection(s),
                          ),
                      ],
                    ))
            : _SettingsSearchResults(
                entries: results,
                query: query,
                onOpen: (entry) => _openResult(entry, sideBySide: sideBySide),
              );

        return Scaffold(
          appBar: appBar,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchBar,
              Expanded(child: panes),
            ],
          ),
        );
      },
    );
  }
}

/// The Settings search field, above the panes so it is present on both layouts
/// and Ctrl/Cmd-F has something to focus on every visit.
///
/// It sits at the top of the body rather than in the app bar's `bottom`: a text
/// field carries its own [Scrollable], and putting the field after the panes in
/// tree order would make it the last one, which is where test helpers (and
/// anything else scrolling "the content") look for the pane's list.
class _SettingsSearchBar extends StatelessWidget {
  const _SettingsSearchBar({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: TextField(
        key: const ValueKey('settings-search'),
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          // A label, not a hint: the hint vanishes once the field has text,
          // leaving the filled box with no on-screen name and screen readers
          // nothing stable to announce (WCAG 3.3.2, 4.1.2).
          labelText: l10n.settingsSearchLabel,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  key: const ValueKey('settings-search-clear'),
                  icon: const Icon(Icons.close),
                  tooltip: l10n.settingsSearchClear,
                  onPressed: onClear,
                ),
        ),
      ),
    );
  }
}

/// The settings whose names match the typed query, each naming the section
/// that holds it.
class _SettingsSearchResults extends StatelessWidget {
  const _SettingsSearchResults({
    required this.entries,
    required this.query,
    required this.onOpen,
  });

  final List<SettingsSearchEntry> entries;
  final String query;
  final ValueChanged<SettingsSearchEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            l10n.settingsSearchNoMatches(query),
            key: const ValueKey('settings-search-no-matches'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        return ListTile(
          key: ValueKey('settings-search-result-${entry.id}'),
          leading: Icon(entry.section.icon),
          title: Text(entry.label(l10n)),
          subtitle: Text(settingsSectionLabel(context, entry.section)),
          onTap: () => onOpen(entry),
        );
      },
    );
  }
}

/// The sidebar list of settings sections (side-by-side layout). Selection is
/// conveyed by the highlighted tile plus its filled icon — never color alone.
class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({required this.selected, required this.onSelect});

  final SettingsSection selected;
  final ValueChanged<SettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      children: [
        for (final s in SettingsSection.values)
          ListTile(
            key: ValueKey('settings-nav-${s.name}'),
            leading: Icon(s == selected ? s.selectedIcon : s.icon),
            title: Text(settingsSectionLabel(context, s)),
            selected: s == selected,
            onTap: () => onSelect(s),
          ),
      ],
    );
  }
}
