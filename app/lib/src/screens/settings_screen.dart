import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/active_dialect_scope.dart';
import '../data/app_theme_scope.dart';
import '../data/custom_theme.dart';
import '../data/custom_themes_controller.dart';
import '../data/custom_themes_scope.dart';
import '../data/display_defaults.dart';
import '../data/repositories_scope.dart';
import '../data/require_performed_for_history_scope.dart';
import '../data/sort_ignore_articles_scope.dart';
import '../search/collection_query.dart';
import '../theme/color_schemes.dart';
import 'theme_editor_screen.dart';

/// Key used to persist and load the active dialect.
const String kActiveDialectKey = 'active_dialect';

/// Key used to persist and load the app theme selection.
const String kAppThemeKey = 'theme_mode';

/// Key used to persist the "Require mark-performed for calling history" General
/// setting (ROADMAP G.2). Stored as a bool; absent/unset means off (`false`),
/// so a dance's calling history shows every program that contains it.
const String kRequirePerformedForHistoryKey = 'require_performed_for_history';

/// Key used to persist and load the "auto-size Perform cards" preference
/// (ROADMAP G.1). Defaults to `true` (on) when unset.
const String kAutoSizePerformKey = 'auto_size_perform_cards';

/// Key used to persist the "Ignore leading articles when sorting" General
/// setting. Stored as a bool; absent/unset means on (`true`), so the dance
/// list alphabetizes titles with a leading article ("the"/"a"/"an") ignored.
const String kSortIgnoreArticlesKey = 'sort_ignore_articles';

/// Settings screen: a master–detail layout with a sidebar of sections and a
/// content pane. On wide viewports the sidebar and the selected section sit
/// side by side; on narrow viewports the sidebar is a list whose rows push the
/// section as its own page. Adding a settings page is just a new
/// [_SettingsSection] value plus its content in [_SettingsScreenState._content].
///
/// Changes take effect immediately (live update via the relevant scope).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

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
  defaults('Defaults', Icons.settings_suggest_outlined, Icons.settings_suggest);

  const _SettingsSection(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _SettingsScreenState extends State<SettingsScreen> {
  _SettingsSection _section = _SettingsSection.appearance;

  /// Auto-size Perform cards (ROADMAP G.1). Loaded from settings on first build;
  /// defaults on until loaded. `null` = not yet loaded.
  bool? _autoSizePerform;
  bool _autoSizeRequested = false;
  bool _autoSizeUserSet = false;

  /// Lazily loads the persisted auto-size preference the first time the General
  /// section is built (avoids reading settings in `initState`, where the
  /// [RepositoriesScope] context is available but this keeps the pattern with
  /// the scope-driven appearance/dialect reads).
  void _ensureAutoSizeLoaded(BuildContext context) {
    if (_autoSizeRequested) return;
    _autoSizeRequested = true;
    final repos = RepositoriesScope.of(context);
    repos.settings
        .get(kAutoSizePerformKey)
        .then((value) {
          // Don't overwrite a selection the user made before the read resolved.
          if (!mounted || _autoSizeUserSet) return;
          setState(() => _autoSizePerform = value is bool ? value : true);
        })
        .catchError((_) {
          if (!mounted || _autoSizeUserSet) return;
          setState(() => _autoSizePerform = true);
        });
  }

  Future<void> _onAutoSizeChanged(bool value) async {
    setState(() {
      _autoSizeUserSet = true;
      _autoSizePerform = value;
    });
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kAutoSizePerformKey, value);
  }

  /// Default Collection sort order (ROADMAP G.6a). `null` = not yet loaded;
  /// the view shows `title` (today's default) until the read resolves.
  CollectionSort? _defaultCollectionSort;

  /// Default dance-detail rendering (ROADMAP G.6b). `null` = not yet loaded;
  /// the view shows active-dialect (today's default) until the read resolves.
  DanceDetailRendering? _defaultDanceDetailRendering;
  bool _defaultsRequested = false;
  // Separate per-setting guards: a user changing one default before its read
  // resolves must not suppress seeding the *other* default from storage.
  bool _defaultSortUserSet = false;
  bool _defaultRenderingUserSet = false;

  /// Default caller/band for new programs (ROADMAP G.3). Free text seeded once
  /// from storage into these controllers; a late read must not clobber text the
  /// user typed first, so each has its own user-set guard.
  final TextEditingController _defaultProgramCaller = TextEditingController();
  final TextEditingController _defaultProgramBand = TextEditingController();
  bool _defaultCallerUserSet = false;
  bool _defaultBandUserSet = false;

  /// Lazily loads the persisted Display defaults the first time the Defaults
  /// section is built. Mirrors [_ensureAutoSizeLoaded]: a late read must not
  /// clobber a selection the user made before it resolved (per-setting guards).
  void _ensureDefaultsLoaded(BuildContext context) {
    if (_defaultsRequested) return;
    _defaultsRequested = true;
    final repos = RepositoriesScope.of(context);
    repos.settings
        .get(kDefaultCollectionSortKey)
        .then((stored) {
          if (!mounted || _defaultSortUserSet) return;
          setState(() {
            _defaultCollectionSort =
                collectionSortFromName(stored) ?? CollectionSort.title;
          });
        })
        .catchError((_) {
          if (!mounted || _defaultSortUserSet) return;
          setState(() => _defaultCollectionSort = CollectionSort.title);
        });
    repos.settings
        .get(kDefaultDanceDetailRenderingKey)
        .then((stored) {
          if (!mounted || _defaultRenderingUserSet) return;
          setState(() {
            _defaultDanceDetailRendering = danceDetailRenderingFromStored(
              stored,
            );
          });
        })
        .catchError((_) {
          if (!mounted || _defaultRenderingUserSet) return;
          setState(
            () => _defaultDanceDetailRendering =
                DanceDetailRendering.activeDialect,
          );
        });
    repos.settings
        .get(kDefaultProgramCallerKey)
        .then((stored) {
          if (!mounted || _defaultCallerUserSet) return;
          final value = stored is String ? stored.trim() : '';
          if (value.isNotEmpty) {
            _defaultProgramCaller.text = value;
          }
        })
        .catchError((_) {
          /* fall back to a blank caller field */
        });
    repos.settings
        .get(kDefaultProgramBandKey)
        .then((stored) {
          if (!mounted || _defaultBandUserSet) return;
          final value = stored is String ? stored.trim() : '';
          if (value.isNotEmpty) {
            _defaultProgramBand.text = value;
          }
        })
        .catchError((_) {
          /* fall back to a blank band field */
        });
  }

  Future<void> _onDefaultProgramCallerChanged(String value) async {
    _defaultCallerUserSet = true;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDefaultProgramCallerKey, value.trim());
  }

  Future<void> _onDefaultProgramBandChanged(String value) async {
    _defaultBandUserSet = true;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDefaultProgramBandKey, value.trim());
  }

  @override
  void dispose() {
    _defaultProgramCaller.dispose();
    _defaultProgramBand.dispose();
    super.dispose();
  }

  Future<void> _onDefaultCollectionSortChanged(CollectionSort value) async {
    setState(() {
      _defaultSortUserSet = true;
      _defaultCollectionSort = value;
    });
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDefaultCollectionSortKey, value.name);
  }

  Future<void> _onDefaultDanceDetailRenderingChanged(
    DanceDetailRendering value,
  ) async {
    setState(() {
      _defaultRenderingUserSet = true;
      _defaultDanceDetailRendering = value;
    });
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDefaultDanceDetailRenderingKey, value.name);
  }

  Future<void> _onDialectChanged(Dialect dialect) async {
    // Update the live notifier immediately so the selection feels instant; the
    // notifier drives every dependent (including a pushed detail route) to
    // rebuild, then persist in the background.
    ActiveDialectScope.notifierOf(context).value = dialect;
    // Fire-and-forget: store the full dialect (name + role terms + move
    // substitutions + discouraged terms) so a custom dialect survives restart.
    // If the app crashes between here and storage completing the write, the
    // in-memory notifier was already correct for this session.
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kActiveDialectKey, dialect.toJson());
  }

  Future<void> _onThemeChanged(AppThemeSelection selection) async {
    // Mirror the dialect pattern: update the live notifier instantly, then
    // persist in the background. Selecting a built-in theme also clears any
    // active custom theme (built-in wins the moment it's tapped).
    final customs = CustomThemesScope.controllerOf(context);
    AppThemeScope.notifierOf(context).value = selection;
    final repos = RepositoriesScope.of(context);
    await customs.setActive(null);
    await repos.settings.set(kAppThemeKey, selection.name);
  }

  Future<void> _onRequirePerformedForHistoryChanged(bool value) async {
    // Same instant-notifier-then-persist pattern as dialect/theme: flip the
    // live notifier so every dependent (including an open dance-detail screen)
    // rebuilds immediately, then persist in the background.
    RequirePerformedForHistoryScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kRequirePerformedForHistoryKey, value);
  }

  Future<void> _onSortIgnoreArticlesChanged(bool value) async {
    // Same instant-notifier-then-persist pattern: flip the live notifier so the
    // dance list re-sorts immediately, then persist in the background.
    SortIgnoreArticlesScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kSortIgnoreArticlesKey, value);
  }

  /// Builds the content pane for [section]. Selection and scope reads use
  /// [context] (in the side-by-side layout the screen itself; in the narrow
  /// layout the pushed detail route) via `.of(context)`, which registers that
  /// context as a dependent so the pane rebuilds live when the active dialect,
  /// built-in theme, or custom themes change.
  Widget _content(BuildContext context, _SettingsSection section) {
    switch (section) {
      case _SettingsSection.appearance:
        final themeSelected = AppThemeScope.of(context);
        final customThemes = CustomThemesScope.of(context);
        final platformDark =
            MediaQuery.platformBrightnessOf(context) == Brightness.dark;
        final seedScheme =
            customThemes.active?.toScheme() ??
            themeSelected.scheme ??
            (platformDark ? AppColorSchemes.dark : AppColorSchemes.light);
        return _AppearanceView(
          // When a custom theme is active, no built-in card is selected.
          themeSelected: customThemes.hasActive ? null : themeSelected,
          onThemeSelected: _onThemeChanged,
          customThemes: customThemes,
          seedScheme: seedScheme,
        );
      case _SettingsSection.dialect:
        return _DialectView(
          selected: ActiveDialectScope.of(context),
          onChanged: _onDialectChanged,
        );
      case _SettingsSection.general:
        _ensureAutoSizeLoaded(context);
        return _GeneralView(
          requirePerformedForHistory: RequirePerformedForHistoryScope.of(
            context,
          ),
          onRequirePerformedForHistoryChanged:
              _onRequirePerformedForHistoryChanged,
          sortIgnoreArticles: SortIgnoreArticlesScope.of(context),
          onSortIgnoreArticlesChanged: _onSortIgnoreArticlesChanged,
          autoSizePerform: _autoSizePerform ?? true,
          onAutoSizeChanged: _onAutoSizeChanged,
        );
      case _SettingsSection.defaults:
        _ensureDefaultsLoaded(context);
        return _DefaultsView(
          programCallerController: _defaultProgramCaller,
          onDefaultProgramCallerChanged: _onDefaultProgramCallerChanged,
          programBandController: _defaultProgramBand,
          onDefaultProgramBandChanged: _onDefaultProgramBandChanged,
          defaultCollectionSort: _defaultCollectionSort ?? CollectionSort.title,
          onDefaultCollectionSortChanged: _onDefaultCollectionSortChanged,
          defaultDanceDetailRendering:
              _defaultDanceDetailRendering ??
              DanceDetailRendering.activeDialect,
          onDefaultDanceDetailRenderingChanged:
              _onDefaultDanceDetailRenderingChanged,
        );
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
      padding: const EdgeInsets.symmetric(vertical: 8),
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

/// The Appearance section: the theme gallery plus locally-saved custom themes.
class _AppearanceView extends StatelessWidget {
  const _AppearanceView({
    required this.themeSelected,
    required this.onThemeSelected,
    required this.customThemes,
    required this.seedScheme,
  });

  final AppThemeSelection? themeSelected;
  final ValueChanged<AppThemeSelection> onThemeSelected;
  final CustomThemesController customThemes;
  final ColorScheme seedScheme;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _SectionHeader(title: 'Theme'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ThemeGallery(
            selected: themeSelected,
            onSelected: onThemeSelected,
          ),
        ),
        _SectionHeader(title: 'Custom themes'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: _CustomThemesSection(
            controller: customThemes,
            seedScheme: seedScheme,
          ),
        ),
      ],
    );
  }
}

/// The Dialect section: an editor for the active caller dialect.
///
/// Mirrors ContraDB's editable dialect (minus its baked gendered presets):
/// pick a role-neutral preset as a starting point, then customize the pieces a
/// dialect can set — role terms (gendered terms live here, not as presets),
/// per-move substitutions (with the `%S` handedness placeholder), and the
/// discouraged-terms list flagged by the entry editor. Any edit turns the
/// active dialect into a "Custom" dialect; storage stays canonical.
class _DialectView extends StatefulWidget {
  const _DialectView({required this.selected, required this.onChanged});

  final Dialect selected;
  final ValueChanged<Dialect> onChanged;

  @override
  State<_DialectView> createState() => _DialectViewState();
}

class _DialectViewState extends State<_DialectView> {
  /// The last dialect this view emitted, so [didUpdateWidget] can tell an
  /// echo of our own change (keep controllers/cursors) from an external change
  /// (resync the fields).
  Dialect? _emitted;

  final _role1Singular = TextEditingController();
  final _role1Plural = TextEditingController();
  final _role2Singular = TextEditingController();
  final _role2Plural = TextEditingController();
  final _discouragedInput = TextEditingController();

  /// One controller per move that currently has (or is being given) a
  /// substitution row, keyed by canonical move id.
  final Map<String, TextEditingController> _moveCtrls = {};

  /// One controller per dancer token that currently has (or is being given) a
  /// substitution row, keyed by canonical dancer token.
  final Map<String, TextEditingController> _dancerCtrls = {};

  List<String> _discouraged = const [];
  bool _showMoves = false;
  bool _showDancers = false;

  @override
  void initState() {
    super.initState();
    _syncFrom(widget.selected);
  }

  @override
  void didUpdateWidget(_DialectView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Resync only for an external change (not the echo of our own emit).
    if (widget.selected != oldWidget.selected && widget.selected != _emitted) {
      _syncFrom(widget.selected);
    }
  }

  void _syncFrom(Dialect d) {
    _role1Singular.text = d.roles['role1']?.singular ?? '';
    _role1Plural.text = d.roles['role1']?.plural ?? '';
    _role2Singular.text = d.roles['role2']?.singular ?? '';
    _role2Plural.text = d.roles['role2']?.plural ?? '';
    // Rebuild the move-substitution controllers to match the dialect.
    for (final c in _moveCtrls.values) {
      c.dispose();
    }
    _moveCtrls.clear();
    for (final entry in d.moves.entries) {
      _moveCtrls[entry.key] = TextEditingController(text: entry.value);
    }
    // Rebuild the dancer-substitution controllers to match the dialect.
    for (final c in _dancerCtrls.values) {
      c.dispose();
    }
    _dancerCtrls.clear();
    for (final entry in d.dancers.entries) {
      _dancerCtrls[entry.key] = TextEditingController(text: entry.value);
    }
    _discouraged = List.of(d.discouragedTerms);
  }

  @override
  void dispose() {
    _role1Singular.dispose();
    _role1Plural.dispose();
    _role2Singular.dispose();
    _role2Plural.dispose();
    _discouragedInput.dispose();
    for (final c in _moveCtrls.values) {
      c.dispose();
    }
    for (final c in _dancerCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Builds a [RoleTerm] from a singular/plural pair, or `null` when the
  /// singular is blank (the role is then dropped from the dialect).
  RoleTerm? _roleTerm(
    TextEditingController singular,
    TextEditingController plural,
  ) {
    final s = singular.text.trim();
    if (s.isEmpty) return null;
    final p = plural.text.trim();
    return RoleTerm(s, plural: p.isEmpty ? null : p);
  }

  /// Assembles the current editor state into a [Dialect] and emits it. If the
  /// result matches a shipped preset (by content), the preset's name is kept;
  /// otherwise it becomes a "Custom" dialect.
  void _emit() {
    final roles = <String, RoleTerm>{};
    final r1 = _roleTerm(_role1Singular, _role1Plural);
    final r2 = _roleTerm(_role2Singular, _role2Plural);
    if (r1 != null) roles['role1'] = r1;
    if (r2 != null) roles['role2'] = r2;

    final moves = <String, String>{};
    for (final entry in _moveCtrls.entries) {
      final v = entry.value.text.trim();
      if (v.isNotEmpty) moves[entry.key] = v;
    }

    final dancers = <String, String>{};
    for (final entry in _dancerCtrls.entries) {
      final v = entry.value.text.trim();
      if (v.isNotEmpty) dancers[entry.key] = v;
    }

    final built = Dialect(
      name: Dialect.customName,
      roles: roles,
      moves: moves,
      dancers: dancers,
      discouragedTerms: _discouraged,
    );
    final dialect = _presetMatching(built) ?? built;
    _emitted = dialect;
    widget.onChanged(dialect);
  }

  /// Returns the shipped preset whose content (roles/moves/discouraged terms)
  /// matches [d], ignoring the name; or `null` when none matches.
  static Dialect? _presetMatching(Dialect d) {
    for (final preset in Dialect.presets) {
      if (preset.copyWith(name: d.name) == d) return preset;
    }
    return null;
  }

  void _applyPreset(Dialect preset) {
    setState(() => _syncFrom(preset));
    _emitted = preset;
    widget.onChanged(preset);
  }

  void _addDiscouraged() {
    final term = _discouragedInput.text.trim().toLowerCase();
    if (term.isEmpty || _discouraged.contains(term)) {
      _discouragedInput.clear();
      return;
    }
    setState(() {
      _discouraged = [..._discouraged, term];
      _discouragedInput.clear();
    });
    _emit();
  }

  void _removeDiscouraged(String term) {
    setState(
      () => _discouraged = _discouraged.where((t) => t != term).toList(),
    );
    _emit();
  }

  void _restoreDiscouragedDefaults() {
    setState(() => _discouraged = List.of(Dialect.defaultDiscouragedTerms));
    _emit();
  }

  void _addMoveSubstitution(String moveId) {
    setState(() {
      _moveCtrls[moveId] = TextEditingController();
      _showMoves = true;
    });
    // No emit yet: an empty substitution is excluded until the user types.
  }

  void _removeMoveSubstitution(String moveId) {
    setState(() {
      _moveCtrls.remove(moveId)?.dispose();
    });
    _emit();
  }

  void _addDancerSubstitution(String token) {
    setState(() {
      _dancerCtrls[token] = TextEditingController();
      _showDancers = true;
    });
    // No emit yet: an empty substitution is excluded until the user types.
  }

  void _removeDancerSubstitution(String token) {
    setState(() {
      _dancerCtrls.remove(token)?.dispose();
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    // Working dialect assembled from the live editor state, for validation and
    // preset-selection display.
    final roles = <String, RoleTerm>{};
    final r1 = _roleTerm(_role1Singular, _role1Plural);
    final r2 = _roleTerm(_role2Singular, _role2Plural);
    if (r1 != null) roles['role1'] = r1;
    if (r2 != null) roles['role2'] = r2;
    final moves = <String, String>{
      for (final e in _moveCtrls.entries)
        if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
    };
    final dancers = <String, String>{
      for (final e in _dancerCtrls.entries)
        if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
    };
    final working = Dialect(
      name: Dialect.customName,
      roles: roles,
      moves: moves,
      dancers: dancers,
      discouragedTerms: _discouraged,
    );
    final matchingPreset = _presetMatching(working);
    final issues = working.validate();

    return ListView(
      children: [
        _SectionHeader(title: 'Preset'),
        RadioGroup<Dialect>(
          groupValue: matchingPreset,
          onChanged: (d) {
            if (d != null) _applyPreset(d);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final preset in Dialect.presets)
                RadioListTile<Dialect>(
                  key: ValueKey('dialect-${preset.name}'),
                  title: Text(preset.name),
                  subtitle: _dialectSubtitle(preset),
                  value: preset,
                ),
            ],
          ),
        ),
        if (matchingPreset == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'Custom dialect',
              key: const ValueKey('dialect-custom-indicator'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        _SectionHeader(title: 'Role terms'),
        _RoleTermsEditor(
          role1Singular: _role1Singular,
          role1Plural: _role1Plural,
          role2Singular: _role2Singular,
          role2Plural: _role2Plural,
          onChanged: _emit,
        ),
        if (issues.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              issues.map((i) => i.message).join('\n'),
              key: const ValueKey('dialect-validation-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        _SectionHeader(title: 'Move substitutions'),
        _MoveSubstitutionsEditor(
          controllers: _moveCtrls,
          expanded: _showMoves,
          onToggle: () => setState(() => _showMoves = !_showMoves),
          onEdited: _emit,
          onAdd: _addMoveSubstitution,
          onRemove: _removeMoveSubstitution,
        ),
        _SectionHeader(title: 'Dancer substitutions'),
        _DancerSubstitutionsEditor(
          controllers: _dancerCtrls,
          expanded: _showDancers,
          onToggle: () => setState(() => _showDancers = !_showDancers),
          onEdited: _emit,
          onAdd: _addDancerSubstitution,
          onRemove: _removeDancerSubstitution,
        ),
        _SectionHeader(title: 'Discouraged terms'),
        _DiscouragedTermsEditor(
          terms: _discouraged,
          input: _discouragedInput,
          onAdd: _addDiscouraged,
          onRemove: _removeDiscouraged,
          onRestoreDefaults: _restoreDiscouragedDefaults,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  static Text? _dialectSubtitle(Dialect preset) {
    if (preset.roles.isEmpty) return null;
    final terms = preset.roles.values.map((r) => r.plural).join(' / ');
    return Text(terms);
  }
}

/// Two-role editor: singular + plural for role1 and role2. Blank singular drops
/// the role (canonical). This is where a user enters gendered terms if wanted.
class _RoleTermsEditor extends StatelessWidget {
  const _RoleTermsEditor({
    required this.role1Singular,
    required this.role1Plural,
    required this.role2Singular,
    required this.role2Plural,
    required this.onChanged,
  });

  final TextEditingController role1Singular;
  final TextEditingController role1Plural;
  final TextEditingController role2Singular;
  final TextEditingController role2Plural;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _roleRow(
            context,
            label: 'Role 1',
            singularKey: 'dialect-role1-singular',
            pluralKey: 'dialect-role1-plural',
            singular: role1Singular,
            plural: role1Plural,
          ),
          const SizedBox(height: 12),
          _roleRow(
            context,
            label: 'Role 2',
            singularKey: 'dialect-role2-singular',
            pluralKey: 'dialect-role2-plural',
            singular: role2Singular,
            plural: role2Plural,
          ),
          const SizedBox(height: 4),
          Text(
            'Leave a role blank to use the canonical term. Plural is derived '
            'when omitted.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _roleRow(
    BuildContext context, {
    required String label,
    required String singularKey,
    required String pluralKey,
    required TextEditingController singular,
    required TextEditingController plural,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text(label),
          ),
        ),
        Expanded(
          child: TextField(
            key: ValueKey(singularKey),
            controller: singular,
            decoration: const InputDecoration(labelText: 'Singular'),
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            key: ValueKey(pluralKey),
            controller: plural,
            decoration: const InputDecoration(labelText: 'Plural'),
            onChanged: (_) => onChanged(),
          ),
        ),
      ],
    );
  }
}

/// Collapsible per-move substitution editor. Shows an editable/removable row
/// for each move that has a substitution, plus a dropdown to add one for any
/// other move. `%S` in a substitution injects the figure's handedness.
class _MoveSubstitutionsEditor extends StatelessWidget {
  const _MoveSubstitutionsEditor({
    required this.controllers,
    required this.expanded,
    required this.onToggle,
    required this.onEdited,
    required this.onAdd,
    required this.onRemove,
  });

  final Map<String, TextEditingController> controllers;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onEdited;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  static String _moveLabel(String id) =>
      contraTaxonomy.moves[id]?.displayName ?? id;

  @override
  Widget build(BuildContext context) {
    final overridden = controllers.keys.toList()
      ..sort(
        (a, b) =>
            _moveLabel(a).toLowerCase().compareTo(_moveLabel(b).toLowerCase()),
      );
    final available =
        [
          for (final m in contraTaxonomy.moves.values)
            if (m.id != customMoveId && !controllers.containsKey(m.id)) m.id,
        ]..sort(
          (a, b) => _moveLabel(
            a,
          ).toLowerCase().compareTo(_moveLabel(b).toLowerCase()),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('dialect-moves-toggle'),
              onPressed: onToggle,
              icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              label: Text(
                overridden.isEmpty
                    ? 'Add move substitutions'
                    : '${overridden.length} move substitution'
                          '${overridden.length == 1 ? '' : 's'}',
              ),
            ),
          ),
          if (expanded) ...[
            for (final id in overridden)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        _moveLabel(id),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        key: ValueKey('dialect-move-$id'),
                        controller: controllers[id],
                        decoration: const InputDecoration(
                          hintText: 'substitution (use %S for handedness)',
                        ),
                        onChanged: (_) => onEdited(),
                      ),
                    ),
                    IconButton(
                      key: ValueKey('dialect-move-delete-$id'),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove',
                      onPressed: () => onRemove(id),
                    ),
                  ],
                ),
              ),
            if (available.isNotEmpty)
              DropdownButton<String>(
                key: const ValueKey('dialect-add-move'),
                hint: const Text('Add a move…'),
                value: null,
                isExpanded: true,
                items: [
                  for (final id in available)
                    DropdownMenuItem<String>(
                      value: id,
                      child: Text(_moveLabel(id)),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) onAdd(id);
                },
              ),
          ],
        ],
      ),
    );
  }
}

/// Editable dancer-substitution list, parallel to [_MoveSubstitutionsEditor].
/// Enumerates the positional/relational dancer tokens (the role-driven
/// `role1s`/`role2s` are excluded — they flow through role-term substitution)
/// and lets the caller override each with preferred wording.
class _DancerSubstitutionsEditor extends StatelessWidget {
  const _DancerSubstitutionsEditor({
    required this.controllers,
    required this.expanded,
    required this.onToggle,
    required this.onEdited,
    required this.onAdd,
    required this.onRemove,
  });

  final Map<String, TextEditingController> controllers;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onEdited;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  /// The substitutable dancer tokens: the pair/group dancer sets minus the
  /// role-driven `role1s`/`role2s`, which are handled by role-term
  /// substitution rather than here.
  static final List<String> _substitutableTokens = [
    for (final t in ParamVocab.pairDancerSets)
      if (t != 'role1s' && t != 'role2s') t,
  ];

  /// Human-readable label for a camelCase dancer token
  /// (e.g. `nextNeighbors` -> `next neighbors`).
  static String _dancerLabel(String token) => token
      .replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ')
      .toLowerCase();

  @override
  Widget build(BuildContext context) {
    final overridden = controllers.keys.toList()
      ..sort(
        (a, b) => _dancerLabel(
          a,
        ).toLowerCase().compareTo(_dancerLabel(b).toLowerCase()),
      );
    final available =
        [
          for (final token in _substitutableTokens)
            if (!controllers.containsKey(token)) token,
        ]..sort(
          (a, b) => _dancerLabel(
            a,
          ).toLowerCase().compareTo(_dancerLabel(b).toLowerCase()),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('dialect-dancers-toggle'),
              onPressed: onToggle,
              icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              label: Text(
                overridden.isEmpty
                    ? 'Add dancer substitutions'
                    : '${overridden.length} dancer substitution'
                          '${overridden.length == 1 ? '' : 's'}',
              ),
            ),
          ),
          if (expanded) ...[
            for (final token in overridden)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        _dancerLabel(token),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        key: ValueKey('dialect-dancer-$token'),
                        controller: controllers[token],
                        decoration: const InputDecoration(
                          hintText: 'substitution',
                        ),
                        onChanged: (_) => onEdited(),
                      ),
                    ),
                    IconButton(
                      key: ValueKey('dialect-dancer-delete-$token'),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove',
                      onPressed: () => onRemove(token),
                    ),
                  ],
                ),
              ),
            if (available.isNotEmpty)
              DropdownButton<String>(
                key: const ValueKey('dialect-add-dancer'),
                hint: const Text('Add a dancer term…'),
                value: null,
                isExpanded: true,
                items: [
                  for (final token in available)
                    DropdownMenuItem<String>(
                      value: token,
                      child: Text(_dancerLabel(token)),
                    ),
                ],
                onChanged: (token) {
                  if (token != null) onAdd(token);
                },
              ),
          ],
        ],
      ),
    );
  }
}

/// Editable discouraged-terms list: chips with delete, an add field, and a
/// "restore defaults" action. Terms are user data (never blocked), lowercased.
class _DiscouragedTermsEditor extends StatelessWidget {
  const _DiscouragedTermsEditor({
    required this.terms,
    required this.input,
    required this.onAdd,
    required this.onRemove,
    required this.onRestoreDefaults,
  });

  final List<String> terms;
  final TextEditingController input;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;
  final VoidCallback onRestoreDefaults;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Terms the entry editor flags (struck through) — never blocked.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (terms.isEmpty)
            const Text('No discouraged terms.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final term in terms)
                  Chip(
                    key: ValueKey('dialect-discouraged-chip-$term'),
                    label: Text(term),
                    onDeleted: () => onRemove(term),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('dialect-discouraged-add'),
                  controller: input,
                  decoration: const InputDecoration(
                    labelText: 'Add a term',
                    isDense: true,
                  ),
                  onSubmitted: (_) => onAdd(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const ValueKey('dialect-discouraged-add-button'),
                icon: const Icon(Icons.add),
                tooltip: 'Add term',
                onPressed: onAdd,
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('dialect-discouraged-restore'),
              onPressed: onRestoreDefaults,
              child: const Text('Restore defaults'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The General section: app-wide preference switches (ROADMAP G).
///
/// Hosts the "Require mark-performed for calling history" toggle (ROADMAP G.2,
/// off by default) and the "Auto-size Perform cards" toggle (ROADMAP G.1, on by
/// default). New app-wide switches are added here as additional
/// [SwitchListTile]s.
class _GeneralView extends StatelessWidget {
  const _GeneralView({
    required this.requirePerformedForHistory,
    required this.onRequirePerformedForHistoryChanged,
    required this.sortIgnoreArticles,
    required this.onSortIgnoreArticlesChanged,
    required this.autoSizePerform,
    required this.onAutoSizeChanged,
  });

  final bool requirePerformedForHistory;
  final ValueChanged<bool> onRequirePerformedForHistoryChanged;
  final bool sortIgnoreArticles;
  final ValueChanged<bool> onSortIgnoreArticlesChanged;
  final bool autoSizePerform;
  final ValueChanged<bool> onAutoSizeChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _SectionHeader(title: 'Library'),
        SwitchListTile(
          key: const ValueKey('general-sort-ignore-articles'),
          value: sortIgnoreArticles,
          onChanged: onSortIgnoreArticlesChanged,
          title: const Text('Ignore leading articles when sorting'),
          subtitle: const Text(
            'When on, the dance list alphabetizes titles ignoring a leading '
            '“the”, “a”, or “an” — so “The Nice Combination” files under N. '
            'Turn off to sort by the literal title.',
          ),
          isThreeLine: true,
        ),
        _SectionHeader(title: 'Performance'),
        SwitchListTile(
          key: const ValueKey('settings-auto-size-perform'),
          title: const Text('Auto-size Perform cards'),
          subtitle: const Text(
            'Scale each card so the full dance or slot fits the screen without '
            'scrolling. Turn off to set the size yourself with A- / A+.',
          ),
          value: autoSizePerform,
          onChanged: onAutoSizeChanged,
        ),
        _SectionHeader(title: 'Calling history'),
        SwitchListTile(
          key: const ValueKey('general-require-performed-for-history'),
          value: requirePerformedForHistory,
          onChanged: onRequirePerformedForHistoryChanged,
          title: const Text('Require “mark performed” for calling history'),
          subtitle: const Text(
            'When on, a dance’s calling history lists only programs whose slot '
            'for that dance was marked performed. When off, a program appears '
            'as soon as it contains the dance.',
          ),
          isThreeLine: true,
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// The Defaults section: app-wide default values, grouped to mirror the
/// ROADMAP's "Defaults (settings pane)" structure. It now populates the
/// **Program defaults** subsection (ROADMAP G.3) and the **Display defaults**
/// subsection (ROADMAP G.6). A later PR adds the sibling **Dance-authoring
/// defaults** subsection (DD.1–DD.3, below Display defaults), introduced by its
/// own [_SectionHeader], so extending this is a drop-in, not a rewrite. No
/// empty subsection is stubbed until it is wired.
class _DefaultsView extends StatelessWidget {
  const _DefaultsView({
    required this.programCallerController,
    required this.onDefaultProgramCallerChanged,
    required this.programBandController,
    required this.onDefaultProgramBandChanged,
    required this.defaultCollectionSort,
    required this.onDefaultCollectionSortChanged,
    required this.defaultDanceDetailRendering,
    required this.onDefaultDanceDetailRenderingChanged,
  });

  final TextEditingController programCallerController;
  final ValueChanged<String> onDefaultProgramCallerChanged;
  final TextEditingController programBandController;
  final ValueChanged<String> onDefaultProgramBandChanged;
  final CollectionSort defaultCollectionSort;
  final ValueChanged<CollectionSort> onDefaultCollectionSortChanged;
  final DanceDetailRendering defaultDanceDetailRendering;
  final ValueChanged<DanceDetailRendering> onDefaultDanceDetailRenderingChanged;

  /// The Collection sort orders offered as a default. Excludes
  /// [CollectionSort.relevance], which is only meaningful for a bare full-text
  /// query and never a sensible saved default.
  static const List<CollectionSort> _sortOptions = [
    CollectionSort.title,
    CollectionSort.author,
    CollectionSort.recentlyAdded,
    CollectionSort.lastCalled,
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _SectionHeader(title: 'Program defaults'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            key: const ValueKey('defaults-program-caller'),
            controller: programCallerController,
            onChanged: onDefaultProgramCallerChanged,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Default caller',
              helperText: 'Prefilled into new programs; editable per program.',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            key: const ValueKey('defaults-program-band'),
            controller: programBandController,
            onChanged: onDefaultProgramBandChanged,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Default band',
              helperText: 'Prefilled into new programs; editable per program.',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        _SectionHeader(title: 'Display defaults'),
        ListTile(
          title: const Text('Collection sort order'),
          subtitle: const Text(
            'How the Collection is sorted when you open it. You can still '
            'change the sort while browsing.',
          ),
          trailing: DropdownButton<CollectionSort>(
            key: const ValueKey('defaults-collection-sort'),
            value: defaultCollectionSort,
            onChanged: (value) {
              if (value != null) onDefaultCollectionSortChanged(value);
            },
            items: [
              for (final sort in _sortOptions)
                DropdownMenuItem(value: sort, child: Text(sort.label)),
            ],
          ),
        ),
        SwitchListTile(
          key: const ValueKey('defaults-dance-detail-canonical'),
          value: defaultDanceDetailRendering == DanceDetailRendering.canonical,
          onChanged: (value) => onDefaultDanceDetailRenderingChanged(
            value
                ? DanceDetailRendering.canonical
                : DanceDetailRendering.activeDialect,
          ),
          title: const Text('Open dance details in canonical terms'),
          subtitle: const Text(
            'When on, a dance opens showing canonical role and move names '
            'instead of your active dialect. You can still switch views on the '
            'dance while it is open.',
          ),
          isThreeLine: true,
        ),
      ],
    );
  }
}

/// The UX-6 theme gallery (`docs/design/ux-modernization.md` §4A): a grouped
/// wrap of live preview cards that replaces the old four-item radio list.
///
/// Selection keeps single-choice (radio) semantics via [Semantics] on each
/// card ([inMutuallyExclusiveGroup] + [selected]); cards are keyboard-traversable
/// [InkWell]s with a visible focus/selection outline, and selection is *never*
/// conveyed by color alone — the chosen card also shows a check icon and label.
class _ThemeGallery extends StatelessWidget {
  const _ThemeGallery({required this.selected, required this.onSelected});

  /// The active built-in selection, or `null` when a custom theme is active
  /// (so no built-in card shows as selected).
  final AppThemeSelection? selected;
  final ValueChanged<AppThemeSelection> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = <Widget>[];
    for (final group in AppThemeGroup.values) {
      final options = AppThemeSelection.inGroup(group);
      if (options.isEmpty) continue;
      groups.add(
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Text(
            group.label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
      groups.add(
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final option in options)
              _ThemePreviewCard(
                key: ValueKey('theme-${option.name}'),
                option: option,
                selected: option == selected,
                onTap: () => onSelected(option),
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groups,
    );
  }
}

/// A single selectable palette swatch showing a miniature live sample: a
/// surface tile, a Fraunces heading + Atkinson body line, three accent chips,
/// and a focus-ring demo, all drawn in that palette's colors.
class _ThemePreviewCard extends StatelessWidget {
  const _ThemePreviewCard({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AppThemeSelection option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final appTheme = Theme.of(context);
    // "System" has no single scheme: preview it with the *default* Hearth
    // scheme for the current OS brightness (what selecting System actually
    // does), not whatever palette happens to be active right now.
    final scheme =
        option.scheme ??
        (MediaQuery.platformBrightnessOf(context) == Brightness.dark
            ? AppColorSchemes.dark
            : AppColorSchemes.light);
    final fonts = appTheme.textTheme;

    final borderColor = selected
        ? appTheme.colorScheme.primary
        : appTheme.colorScheme.outlineVariant;

    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: '${option.label}. ${option.description}',
      child: SizedBox(
        width: 220,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              decoration: BoxDecoration(
                color: appTheme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: borderColor,
                  width: selected ? 2.5 : 1,
                ),
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sample(scheme, fonts),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        selected ? Icons.check_circle : Icons.circle_outlined,
                        size: 18,
                        color: selected
                            ? appTheme.colorScheme.primary
                            : appTheme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          option.label,
                          style: fonts.labelLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (selected)
                        Text(
                          'Selected',
                          style: fonts.labelSmall?.copyWith(
                            color: appTheme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The miniature palette sample drawn in the palette's own colors.
  Widget _sample(ColorScheme scheme, TextTheme fonts) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Aa Preview',
            style: fonts.titleMedium?.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: 2),
          Text(
            'Body text sample',
            style: fonts.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _chip(scheme.primary, scheme.onPrimary),
              const SizedBox(width: 6),
              _chip(scheme.secondary, scheme.onSecondary),
              const SizedBox(width: 6),
              _chip(scheme.tertiary, scheme.onTertiary),
              const Spacer(),
              // Focus-ring demo: a control with the palette's focus outline.
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: scheme.primary, width: 2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(Color bg, Color fg) {
    return Container(
      width: 26,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'A',
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// The custom-themes area (`docs/design/ux-modernization.md` §4B): a "New
/// custom theme" action plus a card for each saved theme. Cards select (tap)
/// the theme, and an overflow menu offers edit / duplicate / delete. Custom
/// themes win over the built-in selection while active.
class _CustomThemesSection extends StatelessWidget {
  const _CustomThemesSection({
    required this.controller,
    required this.seedScheme,
  });

  final CustomThemesController controller;

  /// The scheme a brand-new theme is seeded from (the currently active theme),
  /// so "New custom theme" starts from what the user is looking at.
  final ColorScheme seedScheme;

  Future<void> _createNew(BuildContext context) async {
    final seed = CustomTheme(
      id: '',
      name: 'My theme',
      brightness: seedScheme.brightness,
      roles: CustomTheme.rolesFromScheme(seedScheme),
    );
    final edited = await Navigator.of(context).push<CustomTheme>(
      MaterialPageRoute(builder: (_) => ThemeEditorScreen(initial: seed)),
    );
    if (edited == null) return;
    final created = await controller.duplicate(
      name: edited.name,
      brightness: edited.brightness,
      roles: edited.roles,
    );
    await controller.setActive(created.id);
  }

  Future<void> _edit(BuildContext context, CustomTheme theme) async {
    final edited = await Navigator.of(context).push<CustomTheme>(
      MaterialPageRoute(builder: (_) => ThemeEditorScreen(initial: theme)),
    );
    if (edited != null) await controller.upsert(edited);
  }

  Future<void> _duplicate(CustomTheme theme) async {
    await controller.duplicate(
      name: '${theme.name} (copy)',
      brightness: theme.brightness,
      roles: theme.roles,
    );
  }

  Future<void> _confirmDelete(BuildContext context, CustomTheme theme) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete theme?'),
        content: Text('“${theme.name}” will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.delete(theme.id);
  }

  @override
  Widget build(BuildContext context) {
    final themes = controller.themes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('new-custom-theme'),
            onPressed: () async => _createNew(context),
            icon: const Icon(Icons.add),
            label: const Text('New custom theme'),
          ),
        ),
        if (themes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Copy the current theme and tune any color. Custom themes are '
              'saved on this device.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final theme in themes)
                  _CustomThemeCard(
                    key: ValueKey('custom-${theme.id}'),
                    theme: theme,
                    selected: controller.activeId == theme.id,
                    onTap: () async => controller.setActive(theme.id),
                    onEdit: () async => _edit(context, theme),
                    onDuplicate: () async => _duplicate(theme),
                    onDelete: () async => _confirmDelete(context, theme),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A selectable card for one saved custom theme: a mini live sample in its own
/// colors, a select affordance, and an overflow menu (edit / duplicate /
/// delete). Selection is never color-only — the chosen card shows a check icon
/// and a "Selected" label.
class _CustomThemeCard extends StatelessWidget {
  const _CustomThemeCard({
    super.key,
    required this.theme,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  final CustomTheme theme;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final appTheme = Theme.of(context);
    final scheme = theme.toScheme();
    final fonts = appTheme.textTheme;
    final borderColor = selected
        ? appTheme.colorScheme.primary
        : appTheme.colorScheme.outlineVariant;

    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: 'Custom theme ${theme.name}',
      child: SizedBox(
        width: 220,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              decoration: BoxDecoration(
                color: appTheme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: borderColor,
                  width: selected ? 2.5 : 1,
                ),
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sample(scheme, fonts),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        selected ? Icons.check_circle : Icons.circle_outlined,
                        size: 18,
                        color: selected
                            ? appTheme.colorScheme.primary
                            : appTheme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          theme.name,
                          style: fonts.labelLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      PopupMenuButton<String>(
                        key: ValueKey('custom-menu-${theme.id}'),
                        tooltip: 'Theme actions',
                        onSelected: (value) {
                          switch (value) {
                            case 'edit':
                              onEdit();
                            case 'duplicate':
                              onDuplicate();
                            case 'delete':
                              onDelete();
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(
                            value: 'duplicate',
                            child: Text('Duplicate'),
                          ),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sample(ColorScheme scheme, TextTheme fonts) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Aa Preview',
            style: fonts.titleMedium?.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: 2),
          Text(
            'Body text sample',
            style: fonts.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _chip(scheme.primary, scheme.onPrimary),
              const SizedBox(width: 6),
              _chip(scheme.secondary, scheme.onSecondary),
              const SizedBox(width: 6),
              _chip(scheme.tertiary, scheme.onTertiary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(Color bg, Color fg) {
    return Container(
      width: 26,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'A',
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
