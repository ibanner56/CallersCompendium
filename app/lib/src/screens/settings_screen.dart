import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/active_dialect_scope.dart';
import '../data/app_theme_scope.dart';
import '../data/confirm_before_delete_scope.dart';
import '../data/custom_theme.dart';
import '../data/custom_themes_controller.dart';
import '../data/custom_themes_scope.dart';
import '../data/date_format_scope.dart';
import '../data/dialect_library_controller.dart';
import '../data/dialect_library_scope.dart';
import '../data/display_defaults.dart';
import '../data/first_day_of_week_scope.dart';
import '../data/reduce_motion_scope.dart';
import '../data/regional_formats.dart';
import '../data/repositories_scope.dart';
import '../data/require_performed_for_history_scope.dart';
import '../data/soft_delete_retention.dart';
import '../data/sort_ignore_articles_scope.dart';
import '../data/verbose_figure_rendering_scope.dart';
import '../models/dance_list_entry.dart' show formationShapeLabel;
import '../search/collection_query.dart';
import '../search/facet_labels.dart';
import '../theme/color_schemes.dart';
import '../widgets/figure_list_editor.dart';
import '../widgets/figure_param_editors.dart';
import '../widgets/move_autocomplete.dart';
import 'dialect_editor_screen.dart';
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
  regional('Language & region', Icons.translate_outlined, Icons.translate),
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

  /// Soft-delete retention window (ROADMAP G.4), as the stored `int` day count
  /// (`0` = never auto-purge). `null` = not yet loaded; the view shows the
  /// 30-day default until the read resolves.
  int? _softDeleteRetentionDays;
  bool _softDeleteRetentionRequested = false;
  bool _softDeleteRetentionUserSet = false;

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

  /// Lazily loads the persisted soft-delete retention window (ROADMAP G.4) the
  /// first time the General section is built. Mirrors [_ensureAutoSizeLoaded]: a
  /// late read must not clobber a selection the user made before it resolved.
  void _ensureSoftDeleteRetentionLoaded(BuildContext context) {
    if (_softDeleteRetentionRequested) return;
    _softDeleteRetentionRequested = true;
    final repos = RepositoriesScope.of(context);
    repos.settings
        .get(kSoftDeleteRetentionKey)
        .then((stored) {
          if (!mounted || _softDeleteRetentionUserSet) return;
          setState(
            () => _softDeleteRetentionDays = _retentionSelectionFromStored(
              stored,
            ),
          );
        })
        .catchError((_) {
          if (!mounted || _softDeleteRetentionUserSet) return;
          setState(
            () => _softDeleteRetentionDays = kSoftDeleteRetentionDefaultDays,
          );
        });
  }

  /// Maps a persisted retention value to the `int` the dropdown selects (one of
  /// [kSoftDeleteRetentionDayOptions] or [kSoftDeleteRetentionNever]). Reuses
  /// the shared resolver, then snaps any unrecognized day count to the 30-day
  /// default so the dropdown always has a valid selection.
  int _retentionSelectionFromStored(Object? stored) {
    final resolved = softDeleteRetentionFromStored(stored);
    if (resolved == null) return kSoftDeleteRetentionNever;
    final days = resolved.inDays;
    return kSoftDeleteRetentionDayOptions.contains(days)
        ? days
        : kSoftDeleteRetentionDefaultDays;
  }

  Future<void> _onSoftDeleteRetentionChanged(int value) async {
    setState(() {
      _softDeleteRetentionUserSet = true;
      _softDeleteRetentionDays = value;
    });
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kSoftDeleteRetentionKey, value);
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

  /// Dance-authoring defaults for NEW dances (ROADMAP DD.1). `null` = not yet
  /// loaded; the view shows today's hardcoded default until the read resolves.
  /// Each has its own user-set guard so a late read can't clobber an in-view
  /// change and one control's change can't suppress seeding the others.
  DanceForm? _defaultDanceForm;
  FormationShape? _defaultDanceFormationShape;
  Progression? _defaultDanceProgression;
  final TextEditingController _defaultDancePhrase = TextEditingController();
  bool _defaultDanceFormUserSet = false;
  bool _defaultDanceFormationShapeUserSet = false;
  bool _defaultDanceProgressionUserSet = false;
  bool _defaultDancePhraseUserSet = false;

  /// Default starting-figures template for NEW dances (ROADMAP DD.2). Held as a
  /// live [FigureDraft] list driving the embedded [FigureListEditor]. Pre-seeded
  /// synchronously with the default `stand_still × 8` so the first frame shows a
  /// sensible template; [_ensureDefaultsLoaded] replaces it with the saved
  /// template unless the user has already edited it (guard below).
  final List<FigureDraft> _defaultDanceFigureDrafts = [
    for (final figure in defaultNewDanceFigureTemplate())
      FigureDraft.fromFigure(figure),
  ];
  bool _defaultDanceFiguresUserSet = false;

  /// Per-move insert-time parameter overrides (ROADMAP DD.3), keyed by move id
  /// then param key, holding only the params the user overrode (diffs vs the
  /// taxonomy defaults). `_ensureDefaultsLoaded` seeds it from storage unless
  /// the user has already edited it (guard below).
  Map<String, Map<String, Object?>> _defaultMoveParamOverrides = {};

  /// Move ids currently shown in the Move-defaults editor, in view order. Seeded
  /// from the loaded override keys, plus any move the user just added (which has
  /// no diffs yet and therefore persists nothing until a param is changed). Lets
  /// a freshly-added move stay visible before its first override is recorded.
  final List<String> _moveDefaultsShown = [];
  bool _defaultMoveParamOverridesUserSet = false;

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
    repos.settings
        .get(kDefaultDanceFormKey)
        .then((stored) {
          if (!mounted || _defaultDanceFormUserSet) return;
          setState(() => _defaultDanceForm = danceFormFromStored(stored));
        })
        .catchError((_) {
          if (!mounted || _defaultDanceFormUserSet) return;
          setState(() => _defaultDanceForm = DanceForm.contra);
        });
    repos.settings
        .get(kDefaultDanceFormationShapeKey)
        .then((stored) {
          if (!mounted || _defaultDanceFormationShapeUserSet) return;
          setState(
            () =>
                _defaultDanceFormationShape = formationShapeFromStored(stored),
          );
        })
        .catchError((_) {
          if (!mounted || _defaultDanceFormationShapeUserSet) return;
          setState(
            () => _defaultDanceFormationShape = FormationShape.dupleImproper,
          );
        });
    repos.settings
        .get(kDefaultDanceProgressionKey)
        .then((stored) {
          if (!mounted || _defaultDanceProgressionUserSet) return;
          setState(
            () => _defaultDanceProgression = progressionFromStored(stored),
          );
        })
        .catchError((_) {
          if (!mounted || _defaultDanceProgressionUserSet) return;
          setState(() => _defaultDanceProgression = Progression.single);
        });
    repos.settings
        .get(kDefaultDancePhraseStructureKey)
        .then((stored) {
          if (!mounted || _defaultDancePhraseUserSet) return;
          final raw = dancePhraseStructureRawFromStored(stored);
          if (raw.isNotEmpty) {
            _defaultDancePhrase.text = raw;
          }
        })
        .catchError((_) {
          /* fall back to a blank (standard) phrase field */
        });
    repos.settings
        .get(kDefaultDanceFiguresTemplateKey)
        .then((stored) {
          if (!mounted || _defaultDanceFiguresUserSet) return;
          setState(() {
            _defaultDanceFigureDrafts
              ..clear()
              ..addAll(
                danceFiguresTemplateFromStored(
                  stored,
                ).map(FigureDraft.fromFigure),
              );
          });
        })
        .catchError((_) {
          /* keep the pre-seeded default `stand_still × 8` template */
        });
    repos.settings
        .get(kDefaultMoveParamOverridesKey)
        .then((stored) {
          if (!mounted || _defaultMoveParamOverridesUserSet) return;
          setState(() {
            _defaultMoveParamOverrides = moveParamOverridesFromStored(stored);
            // Merge (don't clear): a move the user added before this read
            // resolves isn't persisted yet, so clearing would make it vanish.
            for (final moveId in _defaultMoveParamOverrides.keys) {
              if (!_moveDefaultsShown.contains(moveId)) {
                _moveDefaultsShown.add(moveId);
              }
            }
          });
        })
        .catchError((_) {
          /* keep the empty override map (pure taxonomy defaults) */
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

  Future<void> _onDefaultDanceFormChanged(DanceForm value) async {
    setState(() {
      _defaultDanceFormUserSet = true;
      _defaultDanceForm = value;
    });
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDefaultDanceFormKey, value.name);
  }

  Future<void> _onDefaultDanceFormationShapeChanged(
    FormationShape value,
  ) async {
    setState(() {
      _defaultDanceFormationShapeUserSet = true;
      _defaultDanceFormationShape = value;
    });
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDefaultDanceFormationShapeKey, value.name);
  }

  Future<void> _onDefaultDanceProgressionChanged(Progression value) async {
    setState(() {
      _defaultDanceProgressionUserSet = true;
      _defaultDanceProgression = value;
    });
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDefaultDanceProgressionKey, value.name);
  }

  Future<void> _onDefaultDancePhraseChanged(String value) async {
    _defaultDancePhraseUserSet = true;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDefaultDancePhraseStructureKey, value.trim());
  }

  /// Persists the current starting-figures template as a `figures_json` string
  /// (ROADMAP DD.2). Marks the setting user-set so a late storage read can't
  /// clobber the in-progress edit. Blank/moveless drafts are filtered out, so
  /// an all-blank template serializes to `'[]'` (an intentional empty template).
  Future<void> _persistDanceFiguresTemplate() async {
    _defaultDanceFiguresUserSet = true;
    final figures = [
      for (final draft in _defaultDanceFigureDrafts) ?draft.toFigure(),
    ];
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(
      kDefaultDanceFiguresTemplateKey,
      encodeFigures(figures),
    );
  }

  /// Persists the current per-move param overrides as a JSON string (ROADMAP
  /// DD.3), dropping empty inner maps. Marks the setting user-set so a late
  /// storage read can't clobber the in-progress edit.
  Future<void> _persistMoveParamOverrides() async {
    _defaultMoveParamOverridesUserSet = true;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(
      kDefaultMoveParamOverridesKey,
      encodeMoveParamOverrides(_defaultMoveParamOverrides),
    );
  }

  /// Adds a move to the Move-defaults editor (ROADMAP DD.3). The move starts
  /// with no diffs (nothing persisted yet); it becomes visible so the user can
  /// tweak its params. A no-op if the move is already shown.
  void _onAddMoveDefault(String moveId) {
    if (_moveDefaultsShown.contains(moveId)) return;
    setState(() => _moveDefaultsShown.add(moveId));
  }

  /// Removes a move's overrides entirely (ROADMAP DD.3) and hides it, then
  /// persists.
  void _onRemoveMoveDefault(String moveId) {
    setState(() {
      _moveDefaultsShown.remove(moveId);
      _defaultMoveParamOverrides.remove(moveId);
    });
    _persistMoveParamOverrides();
  }

  /// Records a per-move param override (ROADMAP DD.3). Diff-based: if [value]
  /// equals the taxonomy default for that param, the key is dropped (falling
  /// back to the taxonomy default); otherwise it is recorded. Persists on
  /// change. The move stays shown even when its last diff is dropped.
  void _onMoveParamOverrideChanged(
    String moveId,
    String paramKey,
    Object? value,
  ) {
    final taxonomyDefault = contraTaxonomy.effectiveParams(
      Figure(move: moveId),
    )[paramKey];
    setState(() {
      final inner = _defaultMoveParamOverrides.putIfAbsent(
        moveId,
        () => <String, Object?>{},
      );
      if (value == taxonomyDefault) {
        inner.remove(paramKey);
        if (inner.isEmpty) _defaultMoveParamOverrides.remove(moveId);
      } else {
        inner[paramKey] = value;
      }
    });
    _persistMoveParamOverrides();
  }

  @override
  void dispose() {
    _defaultProgramCaller.dispose();
    _defaultProgramBand.dispose();
    _defaultDancePhrase.dispose();
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

  Future<void> _onReduceMotionChanged(bool value) async {
    // Same instant-notifier-then-persist pattern (ROADMAP G.7): flip the live
    // notifier so animation-gated widgets rebuild immediately, then persist.
    ReduceMotionScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kReduceMotionKey, value);
  }

  Future<void> _onVerboseFigureRenderingChanged(bool value) async {
    VerboseFigureRenderingScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kVerboseFigureRenderingKey, value);
  }

  Future<void> _onConfirmBeforeDeleteChanged(bool value) async {
    ConfirmBeforeDeleteScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kConfirmBeforeDeleteKey, value);
  }

  Future<void> _onDateFormatChanged(DateFormatPref value) async {
    // Instant-notifier-then-persist (ROADMAP G.8): flip the live notifier so
    // on-screen event dates re-render immediately, then persist the token.
    DateFormatScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDateFormatKey, value.token);
  }

  Future<void> _onFirstDayOfWeekChanged(FirstDayOfWeekPref value) async {
    FirstDayOfWeekScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kFirstDayOfWeekKey, value.token);
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
        return _DialectLibrarySection(
          controller: DialectLibraryScope.of(context),
        );
      case _SettingsSection.regional:
        return _RegionalView(
          dateFormat: DateFormatScope.of(context),
          onDateFormatChanged: _onDateFormatChanged,
          firstDayOfWeek: FirstDayOfWeekScope.of(context),
          onFirstDayOfWeekChanged: _onFirstDayOfWeekChanged,
        );
      case _SettingsSection.general:
        _ensureAutoSizeLoaded(context);
        _ensureSoftDeleteRetentionLoaded(context);
        return _GeneralView(
          requirePerformedForHistory: RequirePerformedForHistoryScope.of(
            context,
          ),
          onRequirePerformedForHistoryChanged:
              _onRequirePerformedForHistoryChanged,
          sortIgnoreArticles: SortIgnoreArticlesScope.of(context),
          onSortIgnoreArticlesChanged: _onSortIgnoreArticlesChanged,
          reduceMotion: ReduceMotionScope.of(context),
          onReduceMotionChanged: _onReduceMotionChanged,
          verboseFigureRendering: VerboseFigureRenderingScope.of(context),
          onVerboseFigureRenderingChanged: _onVerboseFigureRenderingChanged,
          confirmBeforeDelete: ConfirmBeforeDeleteScope.of(context),
          onConfirmBeforeDeleteChanged: _onConfirmBeforeDeleteChanged,
          autoSizePerform: _autoSizePerform ?? true,
          onAutoSizeChanged: _onAutoSizeChanged,
          softDeleteRetentionDays:
              _softDeleteRetentionDays ?? kSoftDeleteRetentionDefaultDays,
          onSoftDeleteRetentionChanged: _onSoftDeleteRetentionChanged,
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
          defaultDanceForm: _defaultDanceForm ?? DanceForm.contra,
          onDefaultDanceFormChanged: _onDefaultDanceFormChanged,
          defaultDanceFormationShape:
              _defaultDanceFormationShape ?? FormationShape.dupleImproper,
          onDefaultDanceFormationShapeChanged:
              _onDefaultDanceFormationShapeChanged,
          defaultDanceProgression:
              _defaultDanceProgression ?? Progression.single,
          onDefaultDanceProgressionChanged: _onDefaultDanceProgressionChanged,
          dancePhraseController: _defaultDancePhrase,
          onDefaultDancePhraseChanged: _onDefaultDancePhraseChanged,
          danceFigureTemplateDrafts: _defaultDanceFigureDrafts,
          onDanceFigureTemplateChanged: () {
            setState(() {});
            _persistDanceFiguresTemplate();
          },
          onDanceFigureTemplateAdd: () {
            setState(() => _defaultDanceFigureDrafts.add(FigureDraft()));
            _persistDanceFiguresTemplate();
          },
          onDanceFigureTemplateDelete: (draft) {
            setState(() => _defaultDanceFigureDrafts.remove(draft));
            _persistDanceFiguresTemplate();
          },
          onDanceFigureTemplateDuplicate: (draft) {
            setState(() {
              final index = _defaultDanceFigureDrafts.indexOf(draft);
              if (index == -1) return;
              _defaultDanceFigureDrafts.insert(
                index + 1,
                FigureDraft(
                  move: draft.move,
                  params: Map<String, Object?>.of(draft.params),
                  note: draft.note,
                  progression: draft.progression,
                  schemaVersion: draft.schemaVersion,
                ),
              );
            });
            _persistDanceFiguresTemplate();
          },
          onDanceFigureTemplateReorder: (oldIndex, newIndex) {
            setState(() {
              final draft = _defaultDanceFigureDrafts.removeAt(oldIndex);
              _defaultDanceFigureDrafts.insert(newIndex, draft);
            });
            _persistDanceFiguresTemplate();
          },
          moveParamOverrides: _defaultMoveParamOverrides,
          shownMoveDefaults: _moveDefaultsShown,
          onAddMoveDefault: _onAddMoveDefault,
          onRemoveMoveDefault: _onRemoveMoveDefault,
          onMoveParamOverrideChanged: _onMoveParamOverrideChanged,
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

/// The Dialect section: a manager for the user's dialect **library**
/// (`docs/design/ux.md` §6). Lists the shipped presets (read-only) followed by
/// the user's custom dialects, with a single active selection (radio
/// semantics), per-custom actions (edit terms / rename / delete), and buttons
/// to create a new dialect or duplicate one from any preset/custom.
///
/// Presets can't be edited in place (a custom dialect may not reuse a preset
/// name); "Edit terms" on a preset offers to duplicate it for customizing.
/// Mirrors `_CustomThemesSection`'s list + dialog CRUD idiom. Live preview,
/// collision validation, and dance-card/perform quick-switch are a later PR.
class _DialectLibrarySection extends StatelessWidget {
  const _DialectLibrarySection({required this.controller});

  final DialectLibraryController controller;

  Future<void> _editCustom(BuildContext context, Dialect dialect) async {
    final edited = await Navigator.of(context).push<Dialect>(
      MaterialPageRoute(builder: (_) => DialectEditorScreen(initial: dialect)),
    );
    if (edited != null) await controller.upsert(edited);
  }

  Future<void> _createNew(BuildContext context) async {
    final name = await _promptName(
      context,
      title: 'New dialect',
      confirmLabel: 'Create',
      initial: 'My dialect',
    );
    if (name == null || !context.mounted) return;
    // Seed a blank dialect and open the editor; only persist on save so a
    // canceled "New dialect" leaves nothing behind.
    final edited = await Navigator.of(context).push<Dialect>(
      MaterialPageRoute(
        builder: (_) => DialectEditorScreen(initial: Dialect(name: name)),
      ),
    );
    if (edited == null) return;
    await controller.duplicate(name: edited.name, from: edited);
  }

  Future<void> _duplicateFrom(BuildContext context) async {
    final source = await showDialog<Dialect>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Duplicate from…'),
        children: [
          for (final d in controller.all)
            SimpleDialogOption(
              key: ValueKey('dialect-duplicate-source-${d.name}'),
              onPressed: () => Navigator.of(ctx).pop(d),
              child: Text(d.name),
            ),
        ],
      ),
    );
    if (source == null) return;
    await controller.duplicate(name: '${source.name} (copy)', from: source);
  }

  Future<void> _duplicateToCustomize(
    BuildContext context,
    Dialect preset,
  ) async {
    final copy = await controller.duplicate(
      name: '${preset.name} (copy)',
      from: preset,
    );
    if (!context.mounted) return;
    await _editCustom(context, copy);
  }

  Future<void> _rename(BuildContext context, Dialect dialect) async {
    final name = await _promptName(
      context,
      title: 'Rename dialect',
      confirmLabel: 'Rename',
      initial: dialect.name,
    );
    if (name == null || name == dialect.name) return;
    await controller.rename(dialect.name, name);
  }

  Future<void> _confirmDelete(BuildContext context, Dialect dialect) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete dialect?'),
        content: Text('“${dialect.name}” will be permanently removed.'),
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
    if (confirmed == true) await controller.delete(dialect.name);
  }

  /// Prompts for a dialect name via a single-field dialog, returning the
  /// trimmed value or `null` if canceled/blank.
  Future<String?> _promptName(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required String initial,
  }) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _DialectNameDialog(
        title: title,
        confirmLabel: confirmLabel,
        initial: initial,
      ),
    );
    if (name == null || name.isEmpty) return null;
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final all = controller.all;
    // The resolved active dialect's name — falls back to the app default, so a
    // preset row is selected by default when nothing has been chosen.
    final activeName = controller.active.name;
    return ListView(
      children: [
        _SectionHeader(title: 'Dialects'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('new-dialect'),
                onPressed: () async => _createNew(context),
                icon: const Icon(Icons.add),
                label: const Text('New dialect'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('duplicate-dialect'),
                onPressed: () async => _duplicateFrom(context),
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Duplicate from…'),
              ),
            ],
          ),
        ),
        RadioGroup<String>(
          groupValue: activeName,
          onChanged: (name) {
            if (name != null) controller.setActive(name);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final dialect in all)
                _DialectRow(
                  key: ValueKey('dialect-tile-${dialect.name}'),
                  dialect: dialect,
                  isPreset: controller.isPreset(dialect.name),
                  onEdit: () async => _editCustom(context, dialect),
                  onRename: () async => _rename(context, dialect),
                  onDelete: () async => _confirmDelete(context, dialect),
                  onDuplicateToCustomize: () async =>
                      _duplicateToCustomize(context, dialect),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// One row in the dialect library: a radio to make the dialect active, its
/// name (presets carry a read-only badge), and an actions menu — edit terms /
/// rename / delete for a custom dialect, or "Duplicate to customize" for a
/// read-only preset.
class _DialectRow extends StatelessWidget {
  const _DialectRow({
    super.key,
    required this.dialect,
    required this.isPreset,
    required this.onEdit,
    required this.onRename,
    required this.onDelete,
    required this.onDuplicateToCustomize,
  });

  final Dialect dialect;
  final bool isPreset;
  final VoidCallback onEdit;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onDuplicateToCustomize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RadioListTile<String>(
      value: dialect.name,
      title: Row(
        children: [
          Flexible(child: Text(dialect.name)),
          if (isPreset) ...[const SizedBox(width: 8), _presetBadge(theme)],
        ],
      ),
      subtitle: _dialectSubtitle(dialect),
      secondary: PopupMenuButton<String>(
        key: ValueKey('dialect-menu-${dialect.name}'),
        tooltip: 'Dialect actions',
        onSelected: (value) {
          switch (value) {
            case 'edit':
              onEdit();
            case 'duplicate-customize':
              onDuplicateToCustomize();
            case 'rename':
              onRename();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (_) => isPreset
            ? const [
                PopupMenuItem(
                  value: 'duplicate-customize',
                  child: Text('Duplicate to customize'),
                ),
              ]
            : const [
                PopupMenuItem(value: 'edit', child: Text('Edit terms')),
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
      ),
    );
  }

  Widget _presetBadge(ThemeData theme) {
    return Container(
      key: ValueKey('dialect-preset-badge-${dialect.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Preset',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }

  static Text? _dialectSubtitle(Dialect dialect) {
    if (dialect.roles.isEmpty) return null;
    final terms = dialect.roles.values.map((r) => r.plural).join(' / ');
    return Text(terms);
  }
}

/// A single-field name prompt for creating/renaming a dialect. Owns its
/// [TextEditingController] so it is disposed only after the dialog's exit
/// transition completes (disposing it eagerly in the caller triggers a
/// use-after-dispose during the pop animation).
class _DialectNameDialog extends StatefulWidget {
  const _DialectNameDialog({
    required this.title,
    required this.confirmLabel,
    required this.initial,
  });

  final String title;
  final String confirmLabel;
  final String initial;

  @override
  State<_DialectNameDialog> createState() => _DialectNameDialogState();
}

class _DialectNameDialogState extends State<_DialectNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('dialect-name-field'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('dialect-name-confirm'),
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// The Language & region section (ROADMAP G.8): regional-format preferences and
/// a home for a future UI-language selector.
///
/// Ships the cheap regional pieces — how program event dates render and which
/// day the week starts on — plus an explicit disabled "App language" placeholder
/// row signaling that full UI localization is a future item (not yet available).
class _RegionalView extends StatelessWidget {
  const _RegionalView({
    required this.dateFormat,
    required this.onDateFormatChanged,
    required this.firstDayOfWeek,
    required this.onFirstDayOfWeekChanged,
  });

  final DateFormatPref dateFormat;
  final ValueChanged<DateFormatPref> onDateFormatChanged;
  final FirstDayOfWeekPref firstDayOfWeek;
  final ValueChanged<FirstDayOfWeekPref> onFirstDayOfWeekChanged;

  static String _dateFormatLabel(DateFormatPref pref) {
    switch (pref) {
      case DateFormatPref.system:
        return 'System default';
      case DateFormatPref.ymd:
        return 'Year-month-day (2026-07-15)';
      case DateFormatPref.dmy:
        return 'Day/month/year (15/07/2026)';
      case DateFormatPref.mdy:
        return 'Month/day/year (07/15/2026)';
    }
  }

  static String _firstDayLabel(FirstDayOfWeekPref pref) {
    switch (pref) {
      case FirstDayOfWeekPref.system:
        return 'System default';
      case FirstDayOfWeekPref.sunday:
        return 'Sunday';
      case FirstDayOfWeekPref.monday:
        return 'Monday';
    }
  }

  @override
  Widget build(BuildContext context) {
    // A live example of how today's date renders in the chosen format, shown as
    // the date-format control's subtitle so the choice is concrete.
    final example = formatEventDate(
      DateTime.now(),
      dateFormat,
      MaterialLocalizations.of(context),
    );
    return ListView(
      children: [
        _SectionHeader(title: 'Formats'),
        ListTile(
          title: const Text('Date format'),
          subtitle: Text('How program event dates appear. Example: $example'),
          isThreeLine: true,
          trailing: DropdownButton<DateFormatPref>(
            key: const ValueKey('regional-date-format'),
            value: dateFormat,
            onChanged: (value) {
              if (value != null) onDateFormatChanged(value);
            },
            items: [
              for (final pref in DateFormatPref.values)
                DropdownMenuItem(
                  value: pref,
                  child: Text(_dateFormatLabel(pref)),
                ),
            ],
          ),
        ),
        ListTile(
          title: const Text('First day of week'),
          subtitle: const Text(
            'The day the week starts on in the app’s date pickers.',
          ),
          trailing: DropdownButton<FirstDayOfWeekPref>(
            key: const ValueKey('regional-first-day-of-week'),
            value: firstDayOfWeek,
            onChanged: (value) {
              if (value != null) onFirstDayOfWeekChanged(value);
            },
            items: [
              for (final pref in FirstDayOfWeekPref.values)
                DropdownMenuItem(
                  value: pref,
                  child: Text(_firstDayLabel(pref)),
                ),
            ],
          ),
        ),
        _SectionHeader(title: 'Language'),
        const ListTile(
          key: ValueKey('regional-language-placeholder'),
          enabled: false,
          title: Text('App language'),
          subtitle: Text(
            'Choose the language of the app’s interface. Full localization is '
            'not available yet.',
          ),
          isThreeLine: true,
          trailing: Text('Coming soon'),
        ),
      ],
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
    required this.reduceMotion,
    required this.onReduceMotionChanged,
    required this.verboseFigureRendering,
    required this.onVerboseFigureRenderingChanged,
    required this.confirmBeforeDelete,
    required this.onConfirmBeforeDeleteChanged,
    required this.autoSizePerform,
    required this.onAutoSizeChanged,
    required this.softDeleteRetentionDays,
    required this.onSoftDeleteRetentionChanged,
  });

  final bool requirePerformedForHistory;
  final ValueChanged<bool> onRequirePerformedForHistoryChanged;
  final bool sortIgnoreArticles;
  final ValueChanged<bool> onSortIgnoreArticlesChanged;
  final bool reduceMotion;
  final ValueChanged<bool> onReduceMotionChanged;
  final bool verboseFigureRendering;
  final ValueChanged<bool> onVerboseFigureRenderingChanged;
  final bool confirmBeforeDelete;
  final ValueChanged<bool> onConfirmBeforeDeleteChanged;
  final bool autoSizePerform;
  final ValueChanged<bool> onAutoSizeChanged;

  /// Current soft-delete retention window as the stored `int` day count
  /// (`0` = never auto-purge — see [kSoftDeleteRetentionNever]).
  final int softDeleteRetentionDays;
  final ValueChanged<int> onSoftDeleteRetentionChanged;

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
        _SectionHeader(title: 'Accessibility'),
        SwitchListTile(
          key: const ValueKey('general-reduce-motion'),
          value: reduceMotion,
          onChanged: onReduceMotionChanged,
          title: const Text('Reduce motion'),
          subtitle: const Text(
            'Dampen or skip non-essential animations, such as animated '
            'scrolling when moving between search results or figures.',
          ),
          isThreeLine: true,
        ),
        SwitchListTile(
          key: const ValueKey('general-verbose-figures'),
          value: verboseFigureRendering,
          onChanged: onVerboseFigureRenderingChanged,
          title: const Text('Always show verbose figure text'),
          subtitle: const Text(
            'Show the full spoken-style figure wording on screen in the dance '
            'view, not only to screen readers. Turn off for the terse notation.',
          ),
          isThreeLine: true,
        ),
        SwitchListTile(
          key: const ValueKey('general-confirm-before-delete'),
          value: confirmBeforeDelete,
          onChanged: onConfirmBeforeDeleteChanged,
          title: const Text('Confirm before delete'),
          subtitle: const Text(
            'Ask for confirmation before deleting a dance or program. Deletes '
            'can still be undone; this just adds an explicit prompt first.',
          ),
          isThreeLine: true,
        ),
        _SectionHeader(title: 'Deleted items'),
        ListTile(
          title: const Text('Keep deleted dances for'),
          subtitle: const Text(
            'Deleted dances are kept for this long before being permanently '
            'removed on app launch. Never keeps them until you purge manually.',
          ),
          isThreeLine: true,
          trailing: DropdownButton<int>(
            key: const ValueKey('general-soft-delete-retention'),
            value: softDeleteRetentionDays,
            onChanged: (value) {
              if (value != null) onSoftDeleteRetentionChanged(value);
            },
            items: [
              for (final days in kSoftDeleteRetentionDayOptions)
                DropdownMenuItem(value: days, child: Text('$days days')),
              const DropdownMenuItem(
                value: kSoftDeleteRetentionNever,
                child: Text('Never'),
              ),
            ],
          ),
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
    required this.defaultDanceForm,
    required this.onDefaultDanceFormChanged,
    required this.defaultDanceFormationShape,
    required this.onDefaultDanceFormationShapeChanged,
    required this.defaultDanceProgression,
    required this.onDefaultDanceProgressionChanged,
    required this.dancePhraseController,
    required this.onDefaultDancePhraseChanged,
    required this.danceFigureTemplateDrafts,
    required this.onDanceFigureTemplateChanged,
    required this.onDanceFigureTemplateAdd,
    required this.onDanceFigureTemplateDelete,
    required this.onDanceFigureTemplateDuplicate,
    required this.onDanceFigureTemplateReorder,
    required this.moveParamOverrides,
    required this.shownMoveDefaults,
    required this.onAddMoveDefault,
    required this.onRemoveMoveDefault,
    required this.onMoveParamOverrideChanged,
  });

  final TextEditingController programCallerController;
  final ValueChanged<String> onDefaultProgramCallerChanged;
  final TextEditingController programBandController;
  final ValueChanged<String> onDefaultProgramBandChanged;
  final CollectionSort defaultCollectionSort;
  final ValueChanged<CollectionSort> onDefaultCollectionSortChanged;
  final DanceDetailRendering defaultDanceDetailRendering;
  final ValueChanged<DanceDetailRendering> onDefaultDanceDetailRenderingChanged;
  final DanceForm defaultDanceForm;
  final ValueChanged<DanceForm> onDefaultDanceFormChanged;
  final FormationShape defaultDanceFormationShape;
  final ValueChanged<FormationShape> onDefaultDanceFormationShapeChanged;
  final Progression defaultDanceProgression;
  final ValueChanged<Progression> onDefaultDanceProgressionChanged;
  final TextEditingController dancePhraseController;
  final ValueChanged<String> onDefaultDancePhraseChanged;

  /// The live draft list backing the starting-figures template editor (ROADMAP
  /// DD.2), plus callbacks mirroring the dance editor's [FigureListEditor]
  /// wiring. Owned by [_SettingsScreenState]; mutated in the callbacks.
  final List<FigureDraft> danceFigureTemplateDrafts;
  final VoidCallback onDanceFigureTemplateChanged;
  final VoidCallback onDanceFigureTemplateAdd;
  final ValueChanged<FigureDraft> onDanceFigureTemplateDelete;
  final ValueChanged<FigureDraft> onDanceFigureTemplateDuplicate;
  final void Function(int oldIndex, int newIndex) onDanceFigureTemplateReorder;

  /// The per-move param overrides (ROADMAP DD.3), keyed by move id then param
  /// key. Owned by [_SettingsScreenState]; read-only here.
  final Map<String, Map<String, Object?>> moveParamOverrides;

  /// Move ids currently shown in the Move-defaults editor, in view order.
  final List<String> shownMoveDefaults;

  /// Adds a move to the Move-defaults editor (no diffs yet).
  final ValueChanged<String> onAddMoveDefault;

  /// Removes a move's overrides entirely and hides it.
  final ValueChanged<String> onRemoveMoveDefault;

  /// Records a per-move param change; the screen diffs it against the taxonomy
  /// default (equal ⇒ dropped, else recorded) and persists.
  final void Function(String moveId, String paramKey, Object? value)
  onMoveParamOverrideChanged;

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
        _SectionHeader(title: 'Dance-authoring defaults'),
        ListTile(
          title: const Text('Form'),
          subtitle: const Text(
            'The dance form a new dance starts as. You can still change it per '
            'dance.',
          ),
          trailing: DropdownButton<DanceForm>(
            key: const ValueKey('defaults-dance-form'),
            value: defaultDanceForm,
            onChanged: (value) {
              if (value != null) onDefaultDanceFormChanged(value);
            },
            items: [
              for (final form in DanceForm.values)
                DropdownMenuItem(
                  value: form,
                  child: Text(danceFormLabel(form)),
                ),
            ],
          ),
        ),
        ListTile(
          title: const Text('Formation'),
          subtitle: const Text(
            'The formation a new dance starts in. You can still change it per '
            'dance.',
          ),
          trailing: DropdownButton<FormationShape>(
            key: const ValueKey('defaults-dance-formation'),
            value: defaultDanceFormationShape,
            onChanged: (value) {
              if (value != null) onDefaultDanceFormationShapeChanged(value);
            },
            items: [
              for (final shape in FormationShape.values)
                DropdownMenuItem(
                  value: shape,
                  child: Text(formationShapeLabel(shape)),
                ),
            ],
          ),
        ),
        ListTile(
          title: const Text('Progression'),
          subtitle: const Text(
            'The progression a new dance starts with. You can still change it '
            'per dance.',
          ),
          trailing: DropdownButton<Progression>(
            key: const ValueKey('defaults-dance-progression'),
            value: defaultDanceProgression,
            onChanged: (value) {
              if (value != null) onDefaultDanceProgressionChanged(value);
            },
            items: [
              for (final progression in Progression.values)
                DropdownMenuItem(
                  value: progression,
                  child: Text(progressionLabel(progression)),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            key: const ValueKey('defaults-dance-phrase'),
            controller: dancePhraseController,
            onChanged: onDefaultDancePhraseChanged,
            decoration: const InputDecoration(
              labelText: 'Default phrase structure',
              helperText:
                  'Seeded into new dances. Blank = standard 4×16 (A1 A2 B1 B2); '
                  'else e.g. 6*8*2.',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Starting figures',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'The figures a new dance starts with. Defaults to a single '
                'stand still (8 beats); clear it for a blank new dance. Editable '
                'per dance.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FigureListEditor(
            drafts: danceFigureTemplateDrafts,
            taxonomy: contraTaxonomy,
            phraseStructure: PhraseStructure.standard,
            dialect: ActiveDialectScope.of(context),
            onChanged: onDanceFigureTemplateChanged,
            onAdd: onDanceFigureTemplateAdd,
            onDelete: onDanceFigureTemplateDelete,
            onDuplicate: onDanceFigureTemplateDuplicate,
            onReorder: onDanceFigureTemplateReorder,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Move defaults',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Preferred parameter values applied when you insert a move '
                'while entering a dance. These override that move\'s built-in '
                'defaults; you can still change any parameter on the figure '
                'afterward. Unset moves and parameters use the built-in '
                'defaults.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _MoveDefaultsEditor(
            overrides: moveParamOverrides,
            shownMoveIds: shownMoveDefaults,
            onAddMoveDefault: onAddMoveDefault,
            onRemoveMoveDefault: onRemoveMoveDefault,
            onMoveParamOverrideChanged: onMoveParamOverrideChanged,
          ),
        ),
      ],
    );
  }
}

/// The Move-defaults editor (ROADMAP DD.3): a list of configured per-move
/// parameter overrides, each with its move name, a remove control, and the
/// move's parameters rendered via [FigureParamEditor] (seeded from the current
/// override else the taxonomy default). An "Add move default" affordance opens
/// a [MoveAutocomplete] picker. Recording/dropping diffs and persistence are
/// handled by the owning [_SettingsScreenState] via the callbacks; this widget
/// only renders and reports edits (the add-move dialog is its only local UI
/// state, shown transiently via [showDialog]).
class _MoveDefaultsEditor extends StatelessWidget {
  const _MoveDefaultsEditor({
    required this.overrides,
    required this.shownMoveIds,
    required this.onAddMoveDefault,
    required this.onRemoveMoveDefault,
    required this.onMoveParamOverrideChanged,
  });

  final Map<String, Map<String, Object?>> overrides;
  final List<String> shownMoveIds;
  final ValueChanged<String> onAddMoveDefault;
  final ValueChanged<String> onRemoveMoveDefault;
  final void Function(String moveId, String paramKey, Object? value)
  onMoveParamOverrideChanged;

  @override
  Widget build(BuildContext context) {
    final dialect = ActiveDialectScope.of(context);
    final renderer = FigureRenderer(contraTaxonomy);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final moveId in shownMoveIds)
          _buildMoveCard(context, moveId, dialect, renderer),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: OutlinedButton.icon(
              key: const ValueKey('move-defaults-add'),
              icon: const Icon(Icons.add),
              label: const Text('Add move default'),
              onPressed: () => _openAddMoveDialog(context, dialect),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMoveCard(
    BuildContext context,
    String moveId,
    Dialect dialect,
    FigureRenderer renderer,
  ) {
    final def = contraTaxonomy.resolve(moveId);
    final displayName = def == null
        ? moveId
        : renderer.displayMoveName(moveId, dialect);
    // Effective params include the taxonomy defaults; overlay any saved
    // override so the editor shows the value the user will actually get.
    final effective = def == null
        ? const <String, Object?>{}
        : contraTaxonomy.effectiveParams(Figure(move: moveId));
    final moveOverrides = overrides[moveId] ?? const <String, Object?>{};
    return Card(
      key: ValueKey('move-default-card-$moveId'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    displayName,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: ValueKey('move-default-remove-$moveId'),
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onRemoveMoveDefault(moveId),
                ),
              ],
            ),
            if (def == null)
              Text(
                'This move is no longer in the taxonomy.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else if (def.params.isEmpty)
              Text(
                'This move has no parameters to default.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final entry in def.params.entries)
                    FigureParamEditor(
                      key: ValueKey('move-default-$moveId-${entry.key}'),
                      keyPrefix: 'move-default-$moveId',
                      paramKey: entry.key,
                      spec: entry.value,
                      value: moveOverrides.containsKey(entry.key)
                          ? moveOverrides[entry.key]
                          : effective[entry.key],
                      onChanged: (v) =>
                          onMoveParamOverrideChanged(moveId, entry.key, v),
                      dialect: dialect,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddMoveDialog(BuildContext context, Dialect dialect) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add move default'),
          content: SizedBox(
            width: 320,
            child: MoveAutocomplete(
              key: const ValueKey('move-defaults-add-picker'),
              fieldKey: 'move-defaults-add-picker',
              taxonomy: contraTaxonomy,
              dialect: dialect,
              initialText: '',
              includeAliases: false,
              autofocus: true,
              onSelected: (option) {
                onAddMoveDefault(option.id);
                Navigator.of(dialogContext).pop();
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
}

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
