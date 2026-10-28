import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Covers the app with a "Closing…" notice while [closing] is true.
///
/// Closing waits for drafts to be saved and, for a bounded time, for a sync
/// pass still on the network (FAIL-12). Without this the window sat there
/// looking hung, and further clicks on its close button did nothing visible.
/// The barrier also stops edits that could no longer be saved.
class AppClosingOverlay extends StatelessWidget {
  const AppClosingOverlay({
    required this.closing,
    required this.child,
    super.key,
  });

  final ValueListenable<bool> closing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: closing,
      child: child,
      builder: (context, isClosing, child) {
        if (!isClosing) return child!;
        final message = AppLocalizations.of(context).appClosingMessage;
        return Stack(
          children: [
            child!,
            ModalBarrier(
              dismissible: false,
              color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.4),
            ),
            Center(
              child: Card(
                key: const ValueKey('app-closing-overlay'),
                child: Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        const SizedBox(width: 16),
                        Text(message),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
