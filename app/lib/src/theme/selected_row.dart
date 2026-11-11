import 'package:flutter/material.dart';

/// Width (logical pixels) of the bar that marks the selected list row. The
/// same width as the set-list row accent (`program_slot_list_editor.dart`).
const double selectedRowBarWidth = 4;

/// The [ListTile.shape] for a selected list row (issue #2156): a
/// [SelectedRowBorder] in [ColorScheme.primary] around the shape an
/// unselected row would take (the [ListTileTheme] in scope), and null when
/// not [selected], so an unselected row is left exactly as before.
///
/// The split-pane lists use it to mark the row open in the detail pane; the
/// Collection list also passes `selected` for the rows ticked in batch
/// selection mode, so there the bar marks those instead.
///
/// [ListTile.selected] alone paints no background in this theme; it only
/// recolours the row's text and icons, and a row that styles its own text (the
/// dance row) showed almost no change. The rows that use this also keep
/// [ListTile.selected], which supplies the `selected` semantics flag.
///
/// The cue is a bar, not a fill, because the gallery palettes tune their text
/// to only just clear 4.5:1 against `surface`: a 12 % `primary` tint takes
/// `onSurfaceVariant` text below 4.5:1 on 21 of the 31 gallery palettes (as
/// low as 3.54:1), and `secondaryContainer` puts High contrast's `onSurface`
/// text at 1.19:1. The bar is non-text UI, and `primary` against `surface` is
/// held to 3:1 for every gallery palette by
/// `test/theme/palette_contrast_test.dart`.
ShapeBorder? selectedRowShape(BuildContext context, {required bool selected}) {
  if (!selected) return null;
  return SelectedRowBorder(
    color: Theme.of(context).colorScheme.primary,
    // ListTile's own fallback when neither the tile nor its theme sets one.
    base: ListTileTheme.of(context).shape ?? const Border(),
  );
}

/// [base] with a [width] bar of [color] painted down its leading edge (the
/// right edge in a right-to-left layout), clipped to [base]'s outline.
///
/// It takes [base]'s outline, dimensions and painting unchanged, so the
/// selected row's ink, hover and focus shapes and its layout match its
/// neighbours'. Nothing about the bar takes layout space: [Ink] pads its child
/// by its decoration's shape dimensions, so a plain `Border(left: …)` here
/// would push the selected row's content [width] pixels across, and the row
/// would shift whenever it was selected. The bar instead paints over the
/// row's existing content padding.
@immutable
class SelectedRowBorder extends ShapeBorder {
  const SelectedRowBorder({
    required this.color,
    required this.base,
    this.width = selectedRowBarWidth,
  });

  final Color color;
  final ShapeBorder base;
  final double width;

  @override
  EdgeInsetsGeometry get dimensions => base.dimensions;

  @override
  ShapeBorder scale(double t) =>
      SelectedRowBorder(color: color, base: base.scale(t), width: width * t);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      base.getOuterPath(rect, textDirection: textDirection);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      base.getInnerPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final bar = textDirection == TextDirection.rtl
        ? Rect.fromLTRB(rect.right - width, rect.top, rect.right, rect.bottom)
        : Rect.fromLTRB(rect.left, rect.top, rect.left + width, rect.bottom);
    canvas
      ..save()
      ..clipPath(getOuterPath(rect, textDirection: textDirection))
      ..drawRect(bar, Paint()..color = color)
      ..restore();
    base.paint(canvas, rect, textDirection: textDirection);
  }

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is SelectedRowBorder &&
      other.color == color &&
      other.base == base &&
      other.width == width;

  @override
  int get hashCode => Object.hash(color, base, width);

  @override
  String toString() => 'SelectedRowBorder($color, $width, $base)';
}
