import 'package:flutter/material.dart';

/// A borderless expandable section whose title is set in the section-header
/// style (uppercase `labelLarge`, primary colour), for grouping a long screen
/// into sections the user can fold away.
class CollapsibleSection extends StatelessWidget {
  const CollapsibleSection({
    required this.sectionKey,
    required this.title,
    required this.expanded,
    required this.child,
    this.onExpansionChanged,
    super.key,
  });

  /// Key for the underlying [ExpansionTile], which is what tests tap.
  final Key sectionKey;
  final String title;

  /// Whether the section starts open. Read once, when the tile is first built.
  final bool expanded;
  final ValueChanged<bool>? onExpansionChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      key: sectionKey,
      shape: const Border(),
      collapsedShape: const Border(),
      initiallyExpanded: expanded,
      onExpansionChanged: onExpansionChanged,
      title: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
      children: [child],
    );
  }
}
