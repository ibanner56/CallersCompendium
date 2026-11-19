import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_spacing.dart';

/// A centred "couldn't load this" message with a Retry button.
///
/// For a screen whose whole body failed to load: the message says what
/// happened and [onRetry] is the way forward, so a transient failure doesn't
/// mean leaving the screen and coming back. A failure that retrying cannot
/// fix (the thing is gone) passes a null [onRetry] and an [onBack] instead, so
/// there is a button to press. A caller with nowhere to go back to does not
/// use this widget for that case: a disabled Retry would imply a retry is
/// pending, so it shows the message alone.
class LoadErrorView extends StatelessWidget {
  const LoadErrorView({
    required this.message,
    required this.onRetry,
    this.body,
    this.icon,
    this.onBack,
    super.key,
  });

  /// What happened, as the heading line.
  final String message;

  /// Reloads the content. When null and [onBack] is null too, the Retry
  /// button is shown disabled (a retry already in flight).
  final VoidCallback? onRetry;

  /// Optional second line: why, or what the user can do.
  final String? body;

  /// Optional leading glyph, usually `Icons.error_outline` from [errorGlyph].
  final Widget? icon;

  /// Leaves the screen. Shown instead of Retry when [onRetry] is null, and
  /// beside it otherwise.
  final VoidCallback? onBack;

  /// The muted error glyph the load-error views lead with.
  static Widget errorGlyph(BuildContext context) => Icon(
    Icons.error_outline,
    size: 48,
    color: Theme.of(context).colorScheme.error,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      // Scrolls, so large text or a short pane never clips the buttons.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[icon!, const SizedBox(height: AppSpacing.md)],
            Text(message, textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(body!, textAlign: TextAlign.center),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (onRetry != null || onBack == null)
                  FilledButton(
                    key: const ValueKey('load-error-retry'),
                    onPressed: onRetry,
                    child: Text(l10n.commonRetry),
                  ),
                if (onBack != null)
                  OutlinedButton(
                    key: const ValueKey('load-error-back'),
                    onPressed: onBack,
                    child: Text(l10n.commonBack),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
