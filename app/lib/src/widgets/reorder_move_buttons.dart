import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

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
/// moves. [moveUpTooltip] and [moveDownTooltip] replace that wording where a
/// list says more, such as the program template editor's slots, which name
/// their position too.
class ReorderMoveButtons extends StatelessWidget {
  const ReorderMoveButtons({
    super.key,
    required this.keyPrefix,
    required this.name,
    required this.onMoveUp,
    required this.onMoveDown,
    this.moveUpTooltip,
    this.moveDownTooltip,
  });

  final String keyPrefix;
  final String name;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  /// The Move up button's tooltip and screen-reader label, in place of
  /// "Move [name] up".
  final String? moveUpTooltip;

  /// The Move down button's tooltip and screen-reader label, in place of
  /// "Move [name] down".
  final String? moveDownTooltip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: ValueKey('$keyPrefix-move-up'),
          tooltip: moveUpTooltip ?? l10n.commonMoveItemUp(name),
          icon: const Icon(Icons.arrow_upward),
          onPressed: onMoveUp,
        ),
        IconButton(
          key: ValueKey('$keyPrefix-move-down'),
          tooltip: moveDownTooltip ?? l10n.commonMoveItemDown(name),
          icon: const Icon(Icons.arrow_downward),
          onPressed: onMoveDown,
        ),
      ],
    );
  }
}

/// Tells a screen reader where an item landed after Move up / Move down.
///
/// The button keeps its focus but the row it belongs to has moved, so without
/// this a screen-reader user hears nothing and cannot tell the move worked.
/// [position] counts from 1. Call it only once the move has actually happened
/// (not for a move that was ignored or failed), and only when [context] is
/// still mounted.
void announceMoved(
  BuildContext context, {
  required String name,
  required int position,
  required int count,
}) {
  if (!context.mounted) return;
  SemanticsService.sendAnnouncement(
    View.of(context),
    AppLocalizations.of(context).commonMovedItemPosition(name, position, count),
    Directionality.of(context),
  );
}
