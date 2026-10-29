import 'package:flutter/material.dart';

import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';

/// How loudly a [NoticeCard] speaks.
enum NoticeKind {
  /// Neutral information.
  info,

  /// A non-blocking warning: the user may carry on. Tertiary colours, as the
  /// editors' warning cards use.
  warning,

  /// Something failed or was refused.
  error,
}

/// An inline notice: a flat tinted container with an icon, an optional bold
/// title and a body. The one shape for boxed warnings and errors, so they read
/// alike across editors, the import review and settings.
///
/// Flat on purpose: a notice is part of the page, not a raised surface, so it
/// is a plain [Container] rather than a [Card].
///
/// The body inherits the notice's foreground colour and `bodyMedium` through
/// [DefaultTextStyle]; a `Text` that sets its own colour overrides it.
class NoticeCard extends StatelessWidget {
  const NoticeCard({
    super.key,
    required this.kind,
    required this.child,
    this.icon,
    this.title,
  });

  final NoticeKind kind;

  /// Overrides the icon the [kind] implies (an info, warning or error glyph).
  final IconData? icon;

  final String? title;
  final Widget child;

  static IconData _defaultIcon(NoticeKind kind) => switch (kind) {
    NoticeKind.info => Icons.info_outline,
    NoticeKind.warning => Icons.warning_amber_outlined,
    NoticeKind.error => Icons.error_outline,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, foreground) = switch (kind) {
      NoticeKind.info => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      NoticeKind.warning => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      NoticeKind.error => (scheme.errorContainer, scheme.onErrorContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppShapes.borderRadiusSmall,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? _defaultIcon(kind), size: 20, color: foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: DefaultTextStyle.merge(
              style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                      child: Text(
                        title!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: foreground,
                        ),
                      ),
                    ),
                  child,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
