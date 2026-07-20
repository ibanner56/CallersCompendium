import 'package:flutter/material.dart';

import '../theme/set_list_accents.dart';

/// Renders [child] inside a rounded highlight whose background is the user's
/// chosen per-formation [color] (issue #367), with an automatically-chosen
/// readable foreground (black/white, WCAG AA ≥4.5:1 via [readableForegroundOn])
/// applied to any text and icons in [child].
///
/// Used to color the **formation label** on the surfaces where it appears
/// (dance cards, dance detail, Perform header) and to preview the exact badge
/// in the settings picker. The label text itself is always present, so color
/// stays a redundant cue (`docs/design/ux.md` §4 "never colour alone").
class FormationColorBadge extends StatelessWidget {
  const FormationColorBadge({
    super.key,
    required this.color,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
  });

  final Color color;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final foreground = readableForegroundOn(color);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: padding,
        child: IconTheme.merge(
          data: IconThemeData(color: foreground),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: foreground),
            child: child,
          ),
        ),
      ),
    );
  }
}
