import 'package:flutter/material.dart';

import 'app_shapes.dart';

/// Width (logical pixels) of the bar that marks the selected list row. The
/// same width as the set-list row accent (`program_slot_list_editor.dart`).
const double selectedRowBarWidth = 4;

/// The [ListTile.shape] for a split-pane list row (issue #2156): a
/// [SelectedRowBorder] in [ColorScheme.primary] when [selected], and null
/// otherwise so an unselected row keeps the theme's [ListTileThemeData.shape].
///
/// [ListTile.selected] alone paints no background in this theme; it only
/// recolours the row's text and icons, and a row that styles its own text (the
/// dance row) showed almost no change. The rows that use this also keep
/// [ListTile.selected], which supplies the `selected` semantics flag.
///
/// The cue is a bar, not a fill, because the gallery palettes tune their text
/// to only just clear 4.5:1 against `surface`: a `primary` tint of 12 % drops
/// `onSurfaceVariant` text to about 3.5:1 on many of them, and
/// `secondaryContainer` puts High contrast's `onSurface` text at 1.19:1. The
/// bar is non-text UI, and `primary` against `surface` is held to 3:1 for
/// every gallery palette by `test/theme/palette_contrast_test.dart`.
ShapeBorder? selectedRowShape(ColorScheme scheme, {required bool selected}) =>
    selected ? SelectedRowBorder(color: scheme.primary) : null;

/// The theme's rounded list-row shape with a [width] bar of [color] painted
/// down its leading edge (the right edge in a right-to-left layout), clipped to
/// the rounded corners.
///
/// Its [dimensions] are zero on purpose. [Ink] pads its child by its
/// decoration's shape dimensions, so a plain `Border(left: …)` here would push
/// the selected row's content [width] pixels across, and the row would shift
/// whenever it was selected. The bar instead paints over the row's existing
/// content padding.
@immutable
class SelectedRowBorder extends ShapeBorder {
  const SelectedRowBorder({
    required this.color,
    this.width = selectedRowBarWidth,
    this.borderRadius = AppShapes.borderRadiusMedium,
  });

  final Color color;
  final double width;
  final BorderRadius borderRadius;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  ShapeBorder scale(double t) => SelectedRowBorder(
    color: color,
    width: width * t,
    borderRadius: borderRadius * t,
  );

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(borderRadius.toRRect(rect));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final bar = textDirection == TextDirection.rtl
        ? Rect.fromLTRB(rect.right - width, rect.top, rect.right, rect.bottom)
        : Rect.fromLTRB(rect.left, rect.top, rect.left + width, rect.bottom);
    canvas
      ..save()
      ..clipRRect(borderRadius.toRRect(rect))
      ..drawRect(bar, Paint()..color = color)
      ..restore();
  }

  @override
  bool operator ==(Object other) =>
      other is SelectedRowBorder &&
      other.color == color &&
      other.width == width &&
      other.borderRadius == borderRadius;

  @override
  int get hashCode => Object.hash(color, width, borderRadius);
}
