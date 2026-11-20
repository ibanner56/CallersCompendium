import 'package:flutter/material.dart';

/// Keeps keyboard focus out of an [ExpansionTile]'s children while it is
/// collapsed.
///
/// A tile built with `maintainState: true` keeps its children in the tree when
/// it is collapsed, so form fields keep their state. They stay *focusable*
/// too: Tab walks into controls that are not on screen, and the keyboard focus
/// ring has nothing visible to draw on. Build the children here and they join
/// the focus order only while the tile is open.
///
/// [controller] must be the one the tile was given; its `isExpanded` is the tile's
/// own state, so there is nothing to keep in step.
///
/// The children come from [builder], not a prebuilt widget, and are built again
/// each time the tile opens or closes. That is deliberate: some widgets read
/// their focus node's *effective* `canRequestFocus` when they build and keep
/// what they read (a [DropdownMenu] hands it to its text field, which writes it
/// onto the node). Built while collapsed they read `false`, and a prebuilt child
/// would never be built again, leaving a field that cannot take focus after the
/// tile opens.
class ExcludeFocusWhenCollapsed extends StatelessWidget {
  const ExcludeFocusWhenCollapsed({
    super.key,
    required this.controller,
    required this.builder,
  });

  final ExpansibleController controller;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => ExcludeFocus(
      excluding: !controller.isExpanded,
      child: Builder(builder: builder),
    ),
  );
}
