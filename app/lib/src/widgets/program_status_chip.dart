import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme_extension.dart';

/// Icon + text label for a [ProgramStatus]. Pairs an icon with text so status
/// is never conveyed by color alone (`docs/research/accessibility-baseline.md`,
/// `docs/design/ux.md` cross-cutting rule).
({IconData icon, String label}) programStatusPresentation(
  ProgramStatus status,
) => switch (status) {
  ProgramStatus.draft => (icon: Icons.edit_note_outlined, label: 'Draft'),
  ProgramStatus.finalized => (
    icon: Icons.check_circle_outline,
    label: 'Finalized',
  ),
  ProgramStatus.performed => (
    icon: Icons.event_available_outlined,
    label: 'Performed',
  ),
};

/// The §2 semantic color for a [ProgramStatus], read from [AppThemeExtension]
/// so it tracks light / dark / high-contrast. Color is only ever additive here
/// — the icon + text label already carry the meaning.
Color programStatusColor(ProgramStatus status, ThemeData theme) {
  final ext = theme.extension<AppThemeExtension>();
  final fallback = theme.colorScheme.onSurfaceVariant;
  return switch (status) {
    ProgramStatus.draft => ext?.statusDraft ?? fallback,
    ProgramStatus.finalized => ext?.statusFinalized ?? fallback,
    ProgramStatus.performed => ext?.statusPerformed ?? fallback,
  };
}

/// Compact status chip for a program (icon + text), tinted with the §2 status
/// color for the active theme.
class ProgramStatusChip extends StatelessWidget {
  const ProgramStatusChip({super.key, required this.status});

  final ProgramStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = programStatusPresentation(status);
    final color = programStatusColor(status, theme);
    return Chip(
      avatar: Icon(p.icon, size: 16, color: color),
      label: Text(p.label),
      backgroundColor: color.withValues(alpha: 0.10),
      side: BorderSide(color: color.withValues(alpha: 0.5)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
