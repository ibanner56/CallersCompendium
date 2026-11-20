import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A centred "nothing here yet" panel: an icon, a title, a line of body copy
/// and, optionally, the one action that fills the list.
///
/// Every list that can be empty uses this, so the glyph, the heading
/// semantics and the one action look and read the same everywhere. Put the way
/// to add the first item in [body] ("Choose New venue to add one.") and the
/// button that does it in [actions].
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    this.body,
    this.actions = const [],
    this.inline = false,
    super.key,
  });

  /// Lay the panel out in place, without centring it in a scroll view of its
  /// own, for use as one child of a list that has other content around it (an
  /// intro line, a second section). A scroll view cannot sit in a list's
  /// unbounded height.
  final bool inline;

  /// Leading glyph; pass a [BrandMark] or [Icon], tinted by the caller.
  final Widget icon;
  final String title;
  final String? body;

  /// Buttons shown under the copy, wrapped when the pane is narrow.
  final List<Widget> actions;

  /// The muted, 64px [Icon] most empty states lead with (the Programs list
  /// leads with a [BrandMark] instead).
  static Widget glyph(BuildContext context, IconData data) => Icon(
    data,
    size: 64,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(height: AppSpacing.md),
        Semantics(
          header: true,
          child: Text(
            title,
            // The display face, as for screen titles.
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
        ),
        if (body != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            body!,
            textAlign: TextAlign.center,
            // A text role (onSurfaceVariant clears 4.5:1), not a hairline one.
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
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
    );
    if (inline) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(child: column),
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: column,
      ),
    );
  }
}
