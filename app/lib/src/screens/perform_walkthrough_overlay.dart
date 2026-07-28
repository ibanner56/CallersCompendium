import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// A toggleable, self-scrolling overlay panel that shows a dance's free-form
/// [Dance.walkthrough] on demand in Perform mode (issue #370).
///
/// Deliberately kept **separate from the auto-size performance card**: it is a
/// sibling overlay (rendered in a [Stack] above the card), never routed through
/// [PerformCard]'s `_FitToHeight` measurement, so surfacing the walkthrough can
/// never shrink or compete with the A1/B1 notation. It owns its own scroll view
/// and is height-capped to the lower portion of the viewport so the notation
/// stays visible behind it.
///
/// The walkthrough is dialect-aware free text rendered through
/// [FigureRenderer.renderFreeText] — the same escaping/rendering path as calling
/// notes — so there is no rich-markup / injection surface.
class PerformWalkthroughOverlay extends StatelessWidget {
  const PerformWalkthroughOverlay({
    super.key,
    required this.walkthrough,
    required this.renderer,
    required this.dialect,
    required this.onClose,
  });

  /// The dance's raw walkthrough text (may be empty — an empty state is shown).
  final String walkthrough;
  final FigureRenderer renderer;
  final Dialect dialect;

  /// Invoked when the caller dismisses the overlay (close button / scrim tap).
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final text = walkthrough.trim();

    return Stack(
      children: [
        // A transparent, tap-absorbing barrier so pointer events can't reach the
        // notation / edge navigation zones behind the panel while it is open
        // (it behaves like a modal), and an outside tap dismisses it. Kept
        // transparent so the notation stays fully visible behind the panel —
        // the overlay must never obscure or shrink it (#370).
        Positioned.fill(
          child: ModalBarrier(
            color: Colors.transparent,
            dismissible: true,
            onDismiss: onClose,
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            // Cap to the lower ~55% of the viewport so the notation behind stays
            // visible; the body scrolls within this bound for long walkthroughs.
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: Material(
              key: const ValueKey('perform-walkthrough-overlay'),
              elevation: 8,
              color: theme.colorScheme.surface,
              surfaceTintColor: theme.colorScheme.surfaceTint,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppSpacing.md),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.performWalkthrough,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('perform-walkthrough-close'),
                            tooltip: MaterialLocalizations.of(
                              context,
                            ).closeButtonTooltip,
                            icon: const Icon(Icons.close),
                            onPressed: onClose,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Text(
                            text.isEmpty
                                ? l10n.performWalkthroughEmpty
                                : renderer.renderFreeText(text, dialect),
                            style: theme.textTheme.titleMedium?.merge(
                              AppTypography.performBody,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
