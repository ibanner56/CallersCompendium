// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'settings_keys.dart';
import '../../data/app_theme_scope.dart';
import '../../data/colour_dance_theme_scope.dart';
import '../../data/custom_theme.dart';
import '../../data/custom_themes_controller.dart';
import '../../data/custom_themes_scope.dart';
import '../../data/formation_colors_scope.dart';
import '../../data/repositories_scope.dart';
import '../../data/set_list_color_coding_scope.dart';
import '../../theme/app_spacing.dart';
import '../../theme/color_schemes.dart';
import '../../widgets/section_header.dart';
import '../formation_colors_screen.dart';
import '../tag_colors_screen.dart';
import '../theme_editor_screen.dart';

/// The Appearance settings section: owns the theme write and reads the live
/// theme / custom-theme scopes.
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
    await repos.settings.set(kColourDanceThemeKey, value);
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

  /// Persists the "colour-code set-list rows" toggle (issue #270): flip the
  /// live scope notifier immediately, then write through in the background —
  /// the same optimistic pattern as the other Appearance/General toggles.
  Future<void> _onSetListColorCodingChanged(bool value) async {
    final repos = RepositoriesScope.of(context);
    SetListColorCodingScope.notifierOf(context).value = value;
    await repos.settings.set(kSetListColorCodingKey, value);
  }

  @override
  Widget build(BuildContext context) {
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
      colourDanceTheme: ColourDanceThemeScope.of(context),
      onColourDanceThemeChanged: _onColourDanceThemeChanged,
      setListColorCoding: SetListColorCodingScope.of(context),
      onSetListColorCodingChanged: _onSetListColorCodingChanged,
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
    required this.colourDanceTheme,
    required this.onColourDanceThemeChanged,
    required this.setListColorCoding,
    required this.onSetListColorCodingChanged,
  });

  final AppThemeSelection? themeSelected;
  final ValueChanged<AppThemeSelection> onThemeSelected;
  final CustomThemesController customThemes;
  final ColorScheme seedScheme;
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: _ThemeGallery(
            selected: themeSelected,
            onSelected: onThemeSelected,
          ),
        ),
        SectionHeader(title: l10n.settingsAppearanceCustomThemesHeader),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          child: _CustomThemesSection(
            controller: customThemes,
            seedScheme: seedScheme,
          ),
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
        ListTile(
          key: const ValueKey('appearance-tag-colours'),
          leading: const Icon(Icons.label_outline),
          title: Text(l10n.settingsAppearanceTagColoursTitle),
          subtitle: Text(l10n.settingsAppearanceTagColoursSubtitle),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const TagColorsScreen()),
          ),
        ),
      ],
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
          padding: const EdgeInsets.only(
            top: AppSpacing.sm,
            bottom: AppSpacing.xs,
          ),
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
                          option.label,
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
        borderRadius: BorderRadius.circular(10),
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
              _chip(scheme.primary, scheme.onPrimary),
              const SizedBox(width: AppSpacing.xs),
              _chip(scheme.secondary, scheme.onSecondary),
              const SizedBox(width: AppSpacing.xs),
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
        'A', // i18n-ignore: single-glyph font specimen, not translatable
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
    final l10n = AppLocalizations.of(context);
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
  }

  Future<void> _edit(BuildContext context, CustomTheme theme) async {
    final edited = await Navigator.of(context).push<CustomTheme>(
      MaterialPageRoute(builder: (_) => ThemeEditorScreen(initial: theme)),
    );
    if (edited != null) await controller.upsert(edited);
  }

  Future<void> _duplicate(CustomTheme theme, String duplicateName) async {
    await controller.duplicate(
      name: duplicateName,
      brightness: theme.brightness,
      roles: theme.roles,
    );
  }

  Future<void> _confirmDelete(BuildContext context, CustomTheme theme) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsAppearanceDeleteThemeTitle),
        content: Text(l10n.settingsAppearanceDeleteThemeBody(theme.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.delete(theme.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
            label: Text(l10n.settingsAppearanceNewThemeButton),
          ),
        ),
        if (themes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              l10n.settingsAppearanceCustomThemesEmpty,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
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
                    onDuplicate: () async => _duplicate(
                      theme,
                      l10n.commonDuplicateTitleSuffix(theme.name),
                    ),
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
        borderRadius: BorderRadius.circular(10),
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
              _chip(scheme.primary, scheme.onPrimary),
              const SizedBox(width: AppSpacing.xs),
              _chip(scheme.secondary, scheme.onSecondary),
              const SizedBox(width: AppSpacing.xs),
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
        'A', // i18n-ignore: single-glyph font specimen, not translatable
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
