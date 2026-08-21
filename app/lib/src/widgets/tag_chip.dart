import 'package:flutter/material.dart';

import '../theme/set_list_accents.dart';

/// A tag chip, optionally tinted with the user's chosen colour (issue #786).
///
/// The colour paints **this chip and nothing else** — never the surrounding
/// row, its background, or a neighbouring chip. When [color] is `null` (the
/// "no colour assigned" state, and the state of every tag until the user picks
/// one) the chip is built with exactly the arguments it was built with before
/// this feature existed: no `backgroundColor`, no label or icon colour, so the
/// theme's default chip styling applies unchanged.
///
/// The tag's name and the label icon are always rendered, tinted or not, so
/// colour stays a **redundant** cue — `docs/design/ux.md`, "Cross-cutting UX
/// rules": *"No color-only meaning anywhere (chips/badges pair icon+text)"*.
/// Foreground is chosen by [readableForegroundOn], the same WCAG-AA helper the
/// formation chip uses, so a user's hue stays legible in the light, dark, and
/// high-contrast themes alike.
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.name,
    required this.color,
    this.onPressed,
    this.tooltip,
    this.dense = false,
  });

  final String name;

  /// Packed ARGB, or `null` for "no colour assigned".
  final int? color;

  /// When non-null the chip becomes an [ActionChip] (used to filter the
  /// Collection by this tag, issue #414); otherwise it is a plain [Chip].
  final VoidCallback? onPressed;
  final String? tooltip;

  /// Applies the compact density the Collection list rows use. Dance detail
  /// lays its chips out at the default density, and the two must keep their
  /// existing, differing chrome — this feature changes colour, not spacing.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final background = color == null ? null : Color(color!);
    final foreground = background == null
        ? null
        : readableForegroundOn(background);
    final avatar = Icon(Icons.label_outline, size: 16, color: foreground);
    final label = Text(
      name,
      style: foreground == null ? null : TextStyle(color: foreground),
    );
    final visualDensity = dense ? VisualDensity.compact : null;
    final tapTargetSize = dense ? MaterialTapTargetSize.shrinkWrap : null;
    if (onPressed case final onPressed?) {
      return ActionChip(
        avatar: avatar,
        label: label,
        tooltip: tooltip,
        backgroundColor: background,
        visualDensity: visualDensity,
        materialTapTargetSize: tapTargetSize,
        onPressed: onPressed,
      );
    }
    return Chip(
      avatar: avatar,
      label: label,
      backgroundColor: background,
      visualDensity: visualDensity,
      materialTapTargetSize: tapTargetSize,
    );
  }
}
