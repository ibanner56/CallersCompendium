import 'package:flutter/material.dart';

import '../theme/app_breakpoints.dart';

/// A screen's labelled floating button ("New dance", "Edit"), which folds to
/// its icon alone in a short window ([AppBreakpoints.isShort]): a phone in
/// landscape, where the extended button would cover the rows' trailing
/// buttons with only a few rows on screen.
///
/// Folded, the label moves into the tooltip, so the button keeps its name for
/// a screen reader and on long press; extended, the visible label is the name
/// and no tooltip repeats it.
FloatingActionButton adaptiveExtendedFab(
  BuildContext context, {
  required Key key,
  required Object heroTag,
  required VoidCallback? onPressed,
  required Widget icon,
  required String label,
}) {
  final short = AppBreakpoints.isShort(context);
  return FloatingActionButton.extended(
    key: key,
    heroTag: heroTag,
    onPressed: onPressed,
    isExtended: !short,
    tooltip: short ? label : null,
    icon: icon,
    label: Text(label),
  );
}
