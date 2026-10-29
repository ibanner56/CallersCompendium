import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A centred "nothing here yet" panel: an icon, a title, a line of body copy
/// and, optionally, the one action that fills the list.
///
/// For the primary lists (Collection, Programs, Venues, Custom figures,
/// Recently deleted). Sub-lists inside Settings keep a one-line message
/// instead; this is too much for a small card.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    this.body,
    this.actions = const [],
    super.key,
  });

  /// Leading glyph; pass a [BrandMark] or [Icon], tinted by the caller.
  final Widget icon;
  final String title;
  final String? body;

  /// Buttons shown under the copy, wrapped when the pane is narrow.
  final List<Widget> actions;

  /// The muted, 64px [Icon] every empty state leads with.
  static Widget glyph(BuildContext context, IconData data) => Icon(
    data,
    size: 64,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (body != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(body!, textAlign: TextAlign.center),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
