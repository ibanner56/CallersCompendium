import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_spacing.dart';

/// A centred "couldn't load this" message with a Retry button.
///
/// For a screen whose whole body failed to load: the message says what
/// happened and [onRetry] is the way forward, so a transient failure doesn't
/// mean leaving the screen and coming back.
class LoadErrorView extends StatelessWidget {
  const LoadErrorView({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              key: const ValueKey('load-error-retry'),
              onPressed: onRetry,
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}
