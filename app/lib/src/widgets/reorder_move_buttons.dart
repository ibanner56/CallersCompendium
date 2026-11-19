import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Move-up / move-down buttons for one item of a reorderable list.
///
/// Dragging is not the only way to reorder (WCAG 2.5.7 Dragging Movements,
/// 2.1.1 Keyboard): these are the same actions the program slot list offers,
/// at the full touch-target size. Pass `null` for [onMoveUp] on the first item
/// and [onMoveDown] on the last so the button disables rather than doing
/// nothing.
///
/// Keys are `<keyPrefix>-move-up` and `<keyPrefix>-move-down`; [name] is the
/// item's own label, so the tooltip and screen-reader label say which item
/// moves.
class ReorderMoveButtons extends StatelessWidget {
  const ReorderMoveButtons({
    super.key,
    required this.keyPrefix,
    required this.name,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final String keyPrefix;
  final String name;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: ValueKey('$keyPrefix-move-up'),
          tooltip: l10n.commonMoveItemUp(name),
          icon: const Icon(Icons.arrow_upward),
          onPressed: onMoveUp,
        ),
        IconButton(
          key: ValueKey('$keyPrefix-move-down'),
          tooltip: l10n.commonMoveItemDown(name),
          icon: const Icon(Icons.arrow_downward),
          onPressed: onMoveDown,
        ),
      ],
    );
  }
}
