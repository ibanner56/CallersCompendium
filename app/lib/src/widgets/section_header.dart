import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A lightweight section header used to group a screen's content into
/// labelled sections (§1d). The title uses `labelLarge` in the primary colour
/// with a `fromLTRB(md, md, md, xxs)` pad so it reads as a distinct heading and
/// sits close to the content it introduces.
///
/// Shared app-wide so every section header (Settings, the dance editor, …) has
/// one consistent style. Place it directly in a `ListView`/`Column` whose
/// content is padded horizontally by [AppSpacing.md] so the header aligns with
/// the fields it labels.
class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xxs,
      ),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
