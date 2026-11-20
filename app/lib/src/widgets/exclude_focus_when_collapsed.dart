import 'package:flutter/material.dart';

/// Keeps keyboard focus out of an [ExpansionTile]'s children while it is
/// collapsed.
///
/// A tile built with `maintainState: true` keeps its children in the tree when
/// it is collapsed, so form fields keep their state. They stay *focusable*
/// too: Tab walks into controls that are not on screen, and the keyboard focus
/// ring has nothing visible to draw on. Wrap the children in this and they join
/// the focus order only while the tile is open.
///
/// [controller] must be the one the tile was given; its `isExpanded` is the tile's
/// own state, so there is nothing to keep in step.
class ExcludeFocusWhenCollapsed extends StatelessWidget {
  const ExcludeFocusWhenCollapsed({
    super.key,
    required this.controller,
    required this.child,
  });

  final ExpansibleController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, child) =>
        ExcludeFocus(excluding: !controller.isExpanded, child: child!),
    child: child,
  );
}
