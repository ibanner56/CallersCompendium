import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/app_theme_labels_l10n.dart';
import '../data/app_theme_scope.dart';
import '../data/custom_theme.dart';
import '../data/custom_themes_controller.dart';
import '../data/custom_themes_scope.dart';
import '../data/persisted_preference.dart';
import '../data/reduce_motion_scope.dart';
import '../data/repositories_scope.dart';
import '../data/theme_search.dart';
import '../theme/app_motion.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/color_schemes.dart';
import '../utils/confirm_delete.dart';
import '../utils/undo_snack_bar.dart';
import '../widgets/adaptive_fab.dart';
import '../widgets/hardware_keyboard_presence.dart';
import 'settings/settings_keys.dart';
import 'theme_editor_screen.dart';

/// The Theme screen, reached from Settings ▸ Appearance ▸ Theme (issue #2228):
/// the gallery of built-in themes and the user's saved custom themes, with a
/// search box above and a floating "Custom theme" button that starts a new one.
///
/// With the search box empty, the themes are grouped under the gallery's
/// section headings (System, Default, Light, Dark — `AppThemeSelection.inGroup`
/// orders each), then the saved custom themes under their own heading, which
/// is left out while there are none. A search drops the headings and shows
/// the matching cards in one run, in the same order. A theme is found by its
/// name, its section, its brightness, or its keywords — the color and
/// character words in `AppThemeSelection.keywords` (see `theme_search.dart`
/// for how a query matches).
///
/// Selecting a built-in theme also clears the active custom theme: built-in
/// wins the moment it is tapped, and a custom theme wins while it is active.
class ThemeScreen extends StatefulWidget {
  const ThemeScreen({super.key});

  @override
  State<ThemeScreen> createState() => _ThemeScreenState();
}

class _ThemeScreenState extends State<ThemeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _listController = ScrollController();
  String _query = '';

  /// The custom theme last made with "Custom theme", and the key its card
  /// carries so [_reveal] can find it (kept until another theme is made).
  String? _revealId;
  final GlobalKey _revealKey = GlobalKey();

  @override
  void dispose() {
    _searchController.dispose();
    _listController.dispose();
    super.dispose();
  }

  Future<void> _onThemeSelected(AppThemeSelection selection) async {
    // Mirror the dialect pattern: update the live notifier instantly, then
    // persist in the background.
    final customs = CustomThemesScope.controllerOf(context);
    AppThemeScope.notifierOf(context).value = selection;
    final repos = RepositoriesScope.of(context);
    await customs.setActive(null);
    await persistSetting(repos.settings, kAppThemeKey, selection.name);
  }

  /// The scheme a brand-new custom theme is seeded from: the theme the user
  /// is looking at now, so "Custom theme" starts from something familiar.
  ColorScheme _seedScheme() {
    final customs = CustomThemesScope.of(context);
    final platformDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return customs.active?.toScheme() ??
        AppThemeScope.of(context).scheme ??
        (platformDark ? AppColorSchemes.dark : AppColorSchemes.light);
  }

  Future<void> _createNew() async {
    final l10n = AppLocalizations.of(context);
    final controller = CustomThemesScope.controllerOf(context);
    final seedScheme = _seedScheme();
    final seed = CustomTheme(
      id: '',
      name: l10n.settingsAppearanceNewThemeDefaultName,
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
    if (!mounted) return;
    // A new theme joins the end of the list, below every built-in card, and
    // starts as a copy of the theme already in use, so nothing on screen would
    // change: bring its card into view. A search it does not match is cleared
    // first, or the card would not be there to show.
    setState(() {
      _revealId = created.id;
      if (!_customEntry(l10n, created).matches(_query)) {
        _searchController.clear();
        _query = '';
      }
    });
    _reveal(ReduceMotionScope.of(context));
  }

  /// Scrolls the card keyed by [_revealKey] into view once it is built. The
  /// list builds lazily, so a card far below the fold may not exist yet: then
  /// jump to the end of the list, where new themes go, and look again on the
  /// next frame.
  void _reveal(bool reduceMotion, {int attempts = 3}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final card = _revealKey.currentContext;
      if (card != null && card.mounted) {
        Scrollable.ensureVisible(
          card,
          duration: reduceMotion ? Duration.zero : AppMotion.short,
          alignment: 0.5,
        );
        return;
      }
      if (attempts == 0 || !_listController.hasClients) return;
      _listController.jumpTo(_listController.position.maxScrollExtent);
      _reveal(reduceMotion, attempts: attempts - 1);
    });
  }

  Future<void> _edit(
    CustomThemesController controller,
    CustomTheme theme,
  ) async {
    final edited = await Navigator.of(context).push<CustomTheme>(
      MaterialPageRoute(builder: (_) => ThemeEditorScreen(initial: theme)),
    );
    if (edited != null) await controller.upsert(edited);
  }

  Future<void> _duplicate(
    CustomThemesController controller,
    CustomTheme theme,
    String duplicateName,
  ) async {
    await controller.duplicate(
      name: duplicateName,
      brightness: theme.brightness,
      roles: theme.roles,
    );
  }

  /// Deletes the custom [theme] at once and offers Undo, asking first only
  /// when "Confirm before delete" is on (see `confirm_delete.dart`).
  Future<void> _confirmDelete(
    CustomThemesController controller,
    CustomTheme theme,
  ) async {
    if (!await confirmDeleteIfEnabled(context, itemLabel: theme.name)) return;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    // Read after the confirmation, so Undo puts back what was removed.
    final removed = controller.byId(theme.id);
    if (removed == null) return;
    final index = controller.themes.indexOf(removed);
    final wasActive = controller.activeId == removed.id;
    // Choosing a built-in theme also leaves no custom theme active, so the
    // controller alone cannot tell it from no choice: Undo makes the theme
    // active again only if the built-in selection has not changed since,
    // even if it has changed back. (Tapping the built-in theme already
    // selected changes nothing, so it does not count.) The listener goes when
    // Undo runs or the prompt closes; a prompt cleared from the queue before
    // it ever showed never closes, and then leaves this listener behind.
    final selection = AppThemeScope.notifierOf(context);
    var chosenSince = false;
    void onChosen() => chosenSince = true;
    selection.addListener(onChosen);
    var deleted = false;
    try {
      await controller.delete(removed.id);
      deleted = true;
    } finally {
      // A failed delete offers no Undo, so nothing will remove it later.
      if (!deleted) selection.removeListener(onChosen);
    }
    if (messenger == null) {
      selection.removeListener(onChosen);
      return;
    }
    final prompt = showUndoSnackBar(
      messenger,
      actionKey: const ValueKey('custom-theme-delete-undo'),
      message: l10n.commonDeletedSnack(removed.name),
      undoLabel: l10n.commonUndo,
      undoFailedMessage: l10n.commonUndoFailed,
      accessibleNavigation: accessibleNavigation,
      onUndo: () {
        selection.removeListener(onChosen);
        return controller.restoreDeleted(
          removed,
          index: index,
          wasActive: wasActive && !chosenSince,
        );
      },
    );
    unawaited(prompt.closed.then((_) => selection.removeListener(onChosen)));
  }

  /// The heading word for a palette of [brightness] ("Light" / "Dark"), which
  /// a search matches so "dark" finds the dark Default themes too.
  String _brightnessWord(AppLocalizations l10n, Brightness brightness) =>
      appThemeGroupLabel(
        l10n,
        brightness == Brightness.dark
            ? AppThemeGroup.dark
            : AppThemeGroup.light,
      );

  ThemeSearchEntry _builtInEntry(
    AppLocalizations l10n,
    AppThemeSelection option,
  ) => ThemeSearchEntry(
    // The English name too: brand palettes are proper nouns, and a caller
    // using the app in another language may still type "Light".
    names: [appThemeLabel(l10n, option), option.label],
    terms: [
      appThemeGroupLabel(l10n, option.group),
      if (option.scheme case final scheme?)
        _brightnessWord(l10n, scheme.brightness),
      for (final keyword in option.keywords)
        ...appThemeKeywordTerms(l10n, keyword),
    ],
  );

  ThemeSearchEntry _customEntry(AppLocalizations l10n, CustomTheme theme) =>
      ThemeSearchEntry(
        names: [theme.name],
        terms: [
          l10n.settingsAppearanceCustomThemesHeader,
          _brightnessWord(l10n, theme.brightness),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAppearanceThemeHeader)),
      floatingActionButton: adaptiveExtendedFab(
        context,
        key: const ValueKey('new-custom-theme'),
        heroTag: 'new-custom-theme',
        onPressed: _createNew,
        icon: const Icon(Icons.add),
        label: l10n.themeScreenNewCustomTheme,
        // "Custom theme" alone reads like the saved cards ("Custom theme
        // Plum"); the spoken name says the button makes one.
        semanticLabel: l10n.themeScreenNewCustomThemeSemantic,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            // Focused on arrival where a hardware keyboard is likely (desktop, or
            // a tablet once its keyboard has been used), so a caller can type
            // straight away; on a phone the on-screen keyboard would cover the
            // gallery, so the field waits for a tap there.
            child: HardwareKeyboardPresence.builder(
              builder: (context, keyboard) => TextField(
                key: const ValueKey('theme-search'),
                autofocus: keyboard,
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l10n.themeScreenSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          key: const ValueKey('theme-search-clear'),
                          tooltip: l10n.themeScreenClearSearchTooltip,
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
          ),
          Expanded(child: _buildList(context)),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final customs = CustomThemesScope.of(context);
    // When a custom theme is active, no built-in card is selected.
    final selected = customs.hasActive ? null : AppThemeScope.of(context);

    Widget builtInCard(AppThemeSelection option, double width) =>
        _ThemePreviewCard(
          key: ValueKey('theme-${option.name}'),
          option: option,
          width: width,
          selected: option == selected,
          onTap: () => _onThemeSelected(option),
        );

    Widget customCard(CustomTheme theme, double width) {
      final card = _CustomThemeCard(
        key: ValueKey('custom-${theme.id}'),
        width: width,
        theme: theme,
        selected: customs.activeId == theme.id,
        onTap: () async => customs.setActive(theme.id),
        onEdit: () async => _edit(customs, theme),
        onDuplicate: () async => _duplicate(
          customs,
          theme,
          l10n.commonDuplicateTitleSuffix(theme.name),
        ),
        onDelete: () async => _confirmDelete(customs, theme),
      );
      return theme.id == _revealId
          ? KeyedSubtree(key: _revealKey, child: card)
          : card;
    }

    final children = <Widget>[];
    if (themeQueryIsEmpty(_query)) {
      for (final group in AppThemeGroup.values) {
        final options = AppThemeSelection.inGroup(group);
        if (options.isEmpty) continue;
        children
          ..add(
            _GroupHeading(
              key: ValueKey('theme-group-${group.name}'),
              label: appThemeGroupLabel(l10n, group),
            ),
          )
          ..add(
            _CardWrap(
              builtIns: options,
              customs: const [],
              builtInCard: builtInCard,
              customCard: customCard,
            ),
          );
      }
      if (customs.themes.isNotEmpty) {
        children
          ..add(
            _GroupHeading(
              key: const ValueKey('theme-group-custom'),
              label: l10n.settingsAppearanceCustomThemesHeader,
            ),
          )
          ..add(
            _CardWrap(
              builtIns: const [],
              customs: customs.themes,
              builtInCard: builtInCard,
              customCard: customCard,
            ),
          );
      }
    } else {
      final builtIns = [
        for (final group in AppThemeGroup.values)
          for (final option in AppThemeSelection.inGroup(group))
            if (_builtInEntry(l10n, option).matches(_query)) option,
      ];
      final matchingCustoms = [
        for (final theme in customs.themes)
          if (_customEntry(l10n, theme).matches(_query)) theme,
      ];
      if (builtIns.isEmpty && matchingCustoms.isEmpty) {
        return Center(
          key: const ValueKey('theme-no-matches'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            // A live region, like the result count, so a screen reader says
            // there are none rather than going quiet.
            child: Semantics(
              liveRegion: true,
              child: Text(
                l10n.themeScreenNoMatches,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      }
      children
        ..add(
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            // A live region, so a screen reader announces how many themes
            // match as the search changes (as the Programs list's count does).
            child: Semantics(
              liveRegion: true,
              child: Text(
                l10n.themeScreenResultCount(
                  builtIns.length + matchingCustoms.length,
                ),
                key: const ValueKey('theme-result-count'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        )
        ..add(
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: _CardWrap(
              key: const ValueKey('theme-search-results'),
              builtIns: builtIns,
              customs: matchingCustoms,
              builtInCard: builtInCard,
              customCard: customCard,
            ),
          ),
        );
    }

    return ListView(
      key: const ValueKey('theme-list'),
      controller: _listController,
      // Lets the last card scroll clear of the floating Custom theme button.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.fabClearance,
      ),
      children: children,
    );
  }
}

/// A gallery section heading ("Light", "Custom themes"), marked as a header
/// for screen readers so they can jump between sections.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// One wrapping run of theme cards: [builtIns] first, then [customs], each
/// sized by [themeCardWidth] for the width available.
class _CardWrap extends StatelessWidget {
  const _CardWrap({
    super.key,
    required this.builtIns,
    required this.customs,
    required this.builtInCard,
    required this.customCard,
  });

  final List<AppThemeSelection> builtIns;
  final List<CustomTheme> customs;
  final Widget Function(AppThemeSelection option, double width) builtInCard;
  final Widget Function(CustomTheme theme, double width) customCard;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final builtInWidth = themeCardWidth(constraints.maxWidth, textScale);
        // A custom card carries its actions menu beside the name, so it never
        // shares a phone row.
        final customWidth = themeCardWidth(
          constraints.maxWidth,
          textScale,
          allowTwoColumns: false,
        );
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final option in builtIns) builtInCard(option, builtInWidth),
            for (final theme in customs) customCard(theme, customWidth),
          ],
        );
      },
    );
  }
}

/// Narrowest sample width that fits the focus-ring demo beside the three chips
/// (3 x 26 + 2 x 8 + 22 = 116 points, plus a gap before the demo).
const double _focusDemoMinWidth = 124;

/// Narrowest card that still holds the swatch's three chips (94 points) inside
/// the card's padding. 150 keeps two columns on a 360-point phone, where each
/// column is 158.
const double _minTwoColumnCardWidth = 150;

/// Width of one theme card in a gallery row [available] points wide.
///
/// Wide panes keep the fixed 220-point cards in a wrapping row. Narrower panes
/// (a phone) use two equal columns, or a single full-width column when two
/// would be too tight for the card's own contents: below [_minTwoColumnCardWidth] a card, or
/// at larger text sizes, where the label and "Selected" badge need the room.
double themeCardWidth(
  double available,
  double textScale, {
  bool allowTwoColumns = true,
}) {
  const fixed = 220.0;
  const gap = 12.0;
  if (available >= 2 * fixed + gap) return fixed;
  final half = ((available - gap) / 2).floorToDouble();
  if (allowTwoColumns && textScale <= 1.3 && half >= _minTwoColumnCardWidth) {
    return half;
  }
  return available;
}

/// A single selectable palette swatch showing a miniature live sample: a
/// surface tile, a Fraunces heading + Atkinson body line, three accent chips,
/// and a focus-ring demo, all drawn in that palette's colors.
///
/// Selection keeps single-choice (radio) semantics via [Semantics]
/// ([inMutuallyExclusiveGroup] + [selected]); the card is a keyboard-traversable
/// [InkWell] with a visible focus/selection outline, and selection is *never*
/// conveyed by color alone — the chosen card also shows a check icon and label.
class _ThemePreviewCard extends StatelessWidget {
  const _ThemePreviewCard({
    super.key,
    required this.option,
    required this.width,
    required this.selected,
    required this.onTap,
  });

  final AppThemeSelection option;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
      label:
          '${appThemeLabel(l10n, option)}. '
          '${appThemeDescription(l10n, option)}',
      child: SizedBox(
        width: width,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppShapes.radiusLarge),
            child: Ink(
              decoration: BoxDecoration(
                color: appTheme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppShapes.radiusLarge),
                border: Border.all(
                  color: borderColor,
                  width: selected ? 2.5 : 1,
                ),
              ),
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sample(context, scheme, fonts),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Icon(
                        selected ? Icons.check_circle : Icons.circle_outlined,
                        size: 18,
                        color: selected
                            ? appTheme.colorScheme.primary
                            : appTheme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          appThemeLabel(l10n, option),
                          style: fonts.labelLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (selected)
                        Text(
                          l10n.settingsAppearanceSelectedBadge,
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
  Widget _sample(BuildContext context, ColorScheme scheme, TextTheme fonts) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppShapes.radiusMedium),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.settingsAppearancePreviewHeading,
            style: fonts.titleMedium?.copyWith(color: scheme.onSurface),
          ),
          // intentional: 2px optical inset, below the 4px AppSpacing grid
          const SizedBox(height: 2),
          Text(
            l10n.settingsAppearancePreviewBody,
            style: fonts.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                _chip(context, scheme.primary, scheme.onPrimary),
                const SizedBox(width: AppSpacing.xs),
                _chip(context, scheme.secondary, scheme.onSecondary),
                const SizedBox(width: AppSpacing.xs),
                _chip(context, scheme.tertiary, scheme.onTertiary),
                // Focus-ring demo: a control with the palette's focus outline.
                // Dropped when the card is too narrow to hold it beside the
                // three chips (two phone columns).
                if (constraints.maxWidth >= _focusDemoMinWidth) ...[
                  const Spacer(),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(
                        AppShapes.radiusSmall,
                      ),
                      border: Border.all(color: scheme.primary, width: 2),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, Color bg, Color fg) {
    return Container(
      width: 26,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppShapes.radiusSmall),
      ),
      child: Text(
        'A', // i18n-ignore: single-glyph font specimen, not translatable
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }
}

/// A selectable card for one saved custom theme: a mini live sample in its own
/// colors, a select affordance, and an overflow menu (edit / duplicate /
/// delete). Selection is never color-only: the chosen card shows a filled check
/// icon and a thicker outline. (Unlike a built-in card it has no "Selected"
/// label; the actions menu takes that place.)
class _CustomThemeCard extends StatelessWidget {
  const _CustomThemeCard({
    super.key,
    required this.width,
    required this.theme,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  final double width;
  final CustomTheme theme;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
      label: l10n.settingsAppearanceCustomThemeSemantic(theme.name),
      child: SizedBox(
        width: width,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppShapes.radiusLarge),
            child: Ink(
              decoration: BoxDecoration(
                color: appTheme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppShapes.radiusLarge),
                border: Border.all(
                  color: borderColor,
                  width: selected ? 2.5 : 1,
                ),
              ),
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sample(context, scheme, fonts),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Icon(
                        selected ? Icons.check_circle : Icons.circle_outlined,
                        size: 18,
                        color: selected
                            ? appTheme.colorScheme.primary
                            : appTheme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          theme.name,
                          style: fonts.labelLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      PopupMenuButton<String>(
                        key: ValueKey('custom-menu-${theme.id}'),
                        tooltip: l10n.settingsAppearanceThemeActionsTooltip,
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
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text(l10n.commonEdit),
                          ),
                          PopupMenuItem(
                            value: 'duplicate',
                            child: Text(l10n.commonDuplicate),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(l10n.commonDelete),
                          ),
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

  Widget _sample(BuildContext context, ColorScheme scheme, TextTheme fonts) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppShapes.radiusMedium),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.settingsAppearancePreviewHeading,
            style: fonts.titleMedium?.copyWith(color: scheme.onSurface),
          ),
          // intentional: 2px optical inset, below the 4px AppSpacing grid
          const SizedBox(height: 2),
          Text(
            l10n.settingsAppearancePreviewBody,
            style: fonts.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              _chip(context, scheme.primary, scheme.onPrimary),
              const SizedBox(width: AppSpacing.xs),
              _chip(context, scheme.secondary, scheme.onSecondary),
              const SizedBox(width: AppSpacing.xs),
              _chip(context, scheme.tertiary, scheme.onTertiary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, Color bg, Color fg) {
    return Container(
      width: 26,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppShapes.radiusSmall),
      ),
      child: Text(
        'A', // i18n-ignore: single-glyph font specimen, not translatable
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }
}
