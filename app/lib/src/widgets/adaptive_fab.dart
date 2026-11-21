import 'package:flutter/material.dart';

import '../theme/app_breakpoints.dart';

/// A screen's labelled floating button ("New dance", "Edit"), which folds to
/// its icon alone in a short window ([AppBreakpoints.isShort]): a phone in
/// landscape, where the extended button would cover the rows' trailing
/// buttons with only a few rows on screen.
///
/// Folded, the label moves into the tooltip, so the button keeps its name for
/// a screen reader and on long press; extended, the visible label is the name
/// and no tooltip repeats it. [semanticLabel], when given, is the name a
/// screen reader speaks instead of [label] (and the folded tooltip): for a
/// short visible label that needs a fuller spoken one. It should contain
/// [label], so speech input can still find the button by what it shows.
FloatingActionButton adaptiveExtendedFab(
  BuildContext context, {
  required Key key,
  required Object heroTag,
  required VoidCallback? onPressed,
  required Widget icon,
  required String label,
  String? semanticLabel,
}) {
  final short = AppBreakpoints.isShort(context);
  return FloatingActionButton.extended(
    key: key,
    heroTag: heroTag,
    onPressed: onPressed,
    isExtended: !short,
    tooltip: short ? (semanticLabel ?? label) : null,
    icon: icon,
    label: Text(label, semanticsLabel: semanticLabel),
  );
}
