import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Covers the app with a "Closing…" notice while [closing] is true.
///
/// Closing waits for drafts to be saved and, for a bounded time, for a sync
/// pass still on the network (FAIL-12). Without this the window sat there
/// looking hung, and further clicks on its close button did nothing visible.
/// The barrier stops taps and screen readers; [ExcludeFocus] stops the
/// keyboard, which a barrier does not: a text field that held focus when
/// closing began would otherwise keep taking keystrokes that could no longer be
/// saved (A11Y-6). Closing is not cancellable, so the app below stays excluded
/// for good. Excluding focus unfocuses without clearing text, so what was typed
/// before the overlay is still in its controller for the draft flush.
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
        final message = AppLocalizations.of(context).appClosingMessage;
        // One shape whether closing or not: the app below is neither remounted
        // nor handed loose constraints when the overlay appears, and
        // ExcludeFocus sees `excluding` change, which is what unfocuses a field
        // that already holds focus.
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            ExcludeFocus(excluding: isClosing, child: child!),
            if (isClosing) ...[
              ModalBarrier(
                dismissible: false,
                color: Theme.of(
                  context,
                ).colorScheme.scrim.withValues(alpha: 0.4),
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
                          SizedBox.square(
                            dimension: 24,
                            // The indeterminate spinner runs its own controller
                            // and ignores `disableAnimations`, so with Reduce
                            // motion on a still icon takes its place.
                            child: MediaQuery.disableAnimationsOf(context)
                                ? const Icon(Icons.hourglass_empty)
                                : const CircularProgressIndicator(
                                    strokeWidth: 3,
                                  ),
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
          ],
        );
      },
    );
  }
}
