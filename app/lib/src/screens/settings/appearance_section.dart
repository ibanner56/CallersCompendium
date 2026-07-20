// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'package:flutter/material.dart';
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
    return ListView(
      children: [
        SectionHeader(title: 'Theme'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: _ThemeGallery(
            selected: themeSelected,
            onSelected: onThemeSelected,
          ),
        ),
        SectionHeader(title: 'Custom themes'),
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
        SectionHeader(title: 'Easter eggs'),
        SwitchListTile(
          key: const ValueKey('appearance-colour-dance-theme'),
          value: colourDanceTheme,
          onChanged: onColourDanceThemeChanged,
          title: const Text('Colour-named dances tint the theme'),
          subtitle: const Text(
            'A playful surprise: when you open a dance whose title names a '
            'colour — like Baby Rose or Blue Boy — its view is tinted that '
            'colour. Off by default, and it steps aside when a high-contrast '
            'theme is active so readability always wins.',
          ),
          isThreeLine: true,
        ),
        SectionHeader(title: 'Set lists'),
        SwitchListTile(
          key: const ValueKey('appearance-set-list-color-coding'),
          title: const Text('Colour-code set-list rows'),
          subtitle: const Text(
            'Tint each dance row by its formation family (contra, mixer, '
            'square, …). The formation is always shown as text too, so rows '
            'stay readable without colour.',
          ),
          value: setListColorCoding,
          onChanged: onSetListColorCodingChanged,
        ),
        SectionHeader(title: 'Formation colours'),
        ListTile(
          key: const ValueKey('appearance-formation-colours'),
          leading: const Icon(Icons.palette_outlined),
          title: const Text('Formation label colours'),
          subtitle: const Text(
            'Highlight individual formations in your own colours — e.g. '
            'Becket (CW) in yellow, Becket (CCW) in pink — on dance cards, '
            'dance detail, and the Perform header.',
          ),
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
                  _sample(scheme, fonts),
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
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Aa Preview',
            style: fonts.titleMedium?.copyWith(color: scheme.onSurface),
          ),
          // intentional: 2px optical inset, below the 4px AppSpacing grid
          const SizedBox(height: 2),
          Text(
            'Body text sample',
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
            padding: const EdgeInsets.only(top: AppSpacing.sm),
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
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sample(scheme, fonts),
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
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Aa Preview',
            style: fonts.titleMedium?.copyWith(color: scheme.onSurface),
          ),
          // intentional: 2px optical inset, below the 4px AppSpacing grid
          const SizedBox(height: 2),
          Text(
            'Body text sample',
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
        'A',
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
