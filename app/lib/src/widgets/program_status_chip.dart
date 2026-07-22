import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../search/facet_labels.dart';
import '../theme/app_theme_extension.dart';
import 'program_status_labels.dart';

/// Icon + text label for a [ProgramStatus]. Pairs an icon with text so status
/// is never conveyed by color alone (`docs/research/accessibility-baseline.md`,
/// `docs/design/ux.md` cross-cutting rule).
({IconData icon, String label}) programStatusPresentation(
  ProgramStatus status,
  AppLocalizations l10n,
) => switch (status) {
  ProgramStatus.draft => (
    icon: Icons.edit_note_outlined,
    label: programStatusLabel(l10n, status),
  ),
  ProgramStatus.finalized => (
    icon: Icons.check_circle_outline,
    label: programStatusLabel(l10n, status),
  ),
  ProgramStatus.performed => (
    icon: Icons.event_available_outlined,
    label: programStatusLabel(l10n, status),
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

/// Icon + text label for a [DanceStatus]. Mirrors [programStatusPresentation]
/// so dance and program status are built the same way. `active` renders no chip
/// in the UI, but is mapped here for exhaustiveness.
({IconData icon, String label}) danceStatusPresentation(DanceStatus status) =>
    switch (status) {
      DanceStatus.active => (
        icon: Icons.check_circle_outline,
        label: danceStatusLabel(DanceStatus.active),
      ),
      DanceStatus.deprecated => (
        icon: Icons.history_toggle_off,
        label: danceStatusLabel(DanceStatus.deprecated),
      ),
      DanceStatus.broken => (
        icon: Icons.report_problem_outlined,
        label: danceStatusLabel(DanceStatus.broken),
      ),
    };

/// The §2 semantic color for a [DanceStatus], read from [AppThemeExtension]
/// (`statusDeprecated` / `statusBroken`) so it tracks light / dark /
/// high-contrast. Color is only ever additive — the icon + text label already
/// carry the meaning. These are the tokens built for dance status that the
/// previous plain-`Chip` rendering never used.
Color danceStatusColor(DanceStatus status, ThemeData theme) {
  final ext = theme.extension<AppThemeExtension>();
  final fallback = theme.colorScheme.onSurfaceVariant;
  return switch (status) {
    DanceStatus.active => fallback,
    DanceStatus.deprecated => ext?.statusDeprecated ?? fallback,
    DanceStatus.broken => ext?.statusBroken ?? fallback,
  };
}

/// Shared status-chip construction (icon + text) tinted with a semantic
/// [color] using the §2 treatment: a 10% [color] fill, a 50% [color] border,
/// and a [color]-tinted icon. The label text uses the theme's `onSurface` so it
/// always clears WCAG AA (≥4.5:1) against the tinted fill in every bundled
/// theme, including high-contrast. Both [ProgramStatusChip] and
/// [DanceStatusChip] delegate here so program and dance status render
/// identically.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(color: theme.colorScheme.onSurface)),
      backgroundColor: color.withValues(alpha: 0.10),
      side: BorderSide(color: color.withValues(alpha: 0.5)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// Compact status chip for a program (icon + text), tinted with the §2 status
/// color for the active theme.
class ProgramStatusChip extends StatelessWidget {
  const ProgramStatusChip({super.key, required this.status});

  final ProgramStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = programStatusPresentation(status, AppLocalizations.of(context));
    return StatusChip(
      icon: p.icon,
      label: p.label,
      color: programStatusColor(status, theme),
    );
  }
}

/// Compact status chip for a dance's non-active [DanceStatus] (Deprecated /
/// Broken). Shares [StatusChip] with [ProgramStatusChip] so dance status finally
/// uses the `statusDeprecated` / `statusBroken` tokens instead of a plain chip.
class DanceStatusChip extends StatelessWidget {
  const DanceStatusChip({super.key, required this.status})
    : assert(
        status != DanceStatus.active,
        'DanceStatusChip is only for non-active statuses; active renders no '
        'chip in the UI.',
      );

  final DanceStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = danceStatusPresentation(status);
    return StatusChip(
      icon: p.icon,
      label: p.label,
      color: danceStatusColor(status, theme),
    );
  }
}
