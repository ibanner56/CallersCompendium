import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/app_theme_scope.dart';
import '../data/formation_colors_controller.dart';
import '../search/facet_labels.dart';
import '../theme/app_spacing.dart';
import '../theme/set_list_accents.dart';
import '../widgets/color_edit_dialog.dart';
import '../widgets/formation_color_badge.dart';
import '../widgets/section_header.dart';

/// Settings screen for the user's per-[FormationShape] label colors
/// (issue #367). Lists every formation shape with a live preview of how its
/// label highlight looks; tapping a row opens the shared [ColorEditDialog] to
/// set a custom color, and overridden shapes expose a reset action to revert to
/// the family default.
///
/// Only shapes the user explicitly overrides are highlighted across the app;
/// the family default shown here is just the picker's starting seed (and the
/// fallback), never applied app-wide on its own.
class FormationColorsScreen extends StatelessWidget {
  const FormationColorsScreen({super.key, required this.controller});

  final FormationColorsController controller;

  Future<void> _edit(BuildContext context, FormationShape shape) async {
    final l10n = AppLocalizations.of(context);
    final highContrast =
        (AppThemeScope.maybeOf(context)?.isHighContrast ?? false) ||
        MediaQuery.highContrastOf(context);
    // Seed the picker with the current override, else the family default so the
    // user starts from a sensible on-theme color rather than plain black.
    final seed =
        controller.overrideFor(shape) ??
        setListAccentForShape(shape, highContrast: highContrast) ??
        Theme.of(context).colorScheme.primary;
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => ColorEditDialog(
        title: formationShapeLabel(l10n, shape),
        initial: seed,
      ),
    );
    if (picked != null) await controller.setColor(shape, picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final highContrast =
        (AppThemeScope.maybeOf(context)?.isHighContrast ?? false) ||
        MediaQuery.highContrastOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsFormationColoursTitle)),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  0,
                ),
                child: Text(
                  l10n.settingsFormationColoursIntro,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              SectionHeader(title: l10n.settingsFormationColoursListHeader),
              for (final shape in FormationShape.values)
                _FormationColorTile(
                  shape: shape,
                  overrideColor: controller.overrideFor(shape),
                  familyDefault: setListAccentForShape(
                    shape,
                    highContrast: highContrast,
                  ),
                  onEdit: () => _edit(context, shape),
                  onReset: () => controller.clearColor(shape),
                ),
              const SizedBox(height: AppSpacing.lg),
            ],
          );
        },
      ),
    );
  }
}

class _FormationColorTile extends StatelessWidget {
  const _FormationColorTile({
    required this.shape,
    required this.overrideColor,
    required this.familyDefault,
    required this.onEdit,
    required this.onReset,
  });

  final FormationShape shape;
  final Color? overrideColor;
  final Color? familyDefault;
  final VoidCallback onEdit;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = formationShapeLabel(l10n, shape);
    final overridden = overrideColor != null;
    // Preview the exact badge for an override; for a not-yet-customised shape,
    // preview against the family seed so the user sees where it starts.
    final previewColor = overrideColor ?? familyDefault;
    return ListTile(
      key: ValueKey('formation-color-${shape.name}'),
      title: previewColor == null
          ? Text(label)
          : Align(
              alignment: Alignment.centerLeft,
              child: FormationColorBadge(
                color: previewColor,
                child: Text(label),
              ),
            ),
      subtitle: Text(
        overridden
            ? l10n.settingsFormationColoursCustom
            : l10n.settingsFormationColoursFamilyDefault,
      ),
      trailing: overridden
          ? IconButton(
              key: ValueKey('formation-color-reset-${shape.name}'),
              icon: const Icon(Icons.settings_backup_restore),
              tooltip: l10n.settingsFormationColoursResetTooltip(label),
              onPressed: onReset,
            )
          : const Icon(Icons.edit_outlined),
      onTap: onEdit,
    );
  }
}
