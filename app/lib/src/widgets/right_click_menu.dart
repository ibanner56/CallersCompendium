import 'package:flutter/material.dart';

/// Opens a list row's ⋮ menu when the row is right-clicked (PLAT-7), so a
/// pointer user gets the same actions, in the same menu, as the button.
///
/// [menuKey] is the key of the row's [PopupMenuButton]. A right-click looks for
/// that button under [child] and opens it, anchored where the button is. A row
/// built without the button (a picker row, or a row in selection mode) has
/// nothing to find, and a right-click does nothing.
///
/// Right-click on a row and right-click on selectable text never meet: a row
/// is never inside a `SelectionArea`, and a selectable pane never wraps a list
/// (`docs/design/selectable-text.md` §6, maintainer decision N5-4).
class RightClickMenu extends StatelessWidget {
  const RightClickMenu({super.key, required this.menuKey, required this.child});

  final Key menuKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onSecondaryTap: () => _findMenu(context)?.showButtonMenu(),
    child: child,
  );

  /// The row's ⋮ button, found by [menuKey]. Searched only on a right-click, so
  /// a row pays nothing for it while it is being built or scrolled.
  PopupMenuButtonState<Object?>? _findMenu(BuildContext context) {
    PopupMenuButtonState<Object?>? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget.key == menuKey &&
          element is StatefulElement &&
          element.state is PopupMenuButtonState) {
        found = element.state as PopupMenuButtonState<Object?>;
        return;
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    return found;
  }
}
