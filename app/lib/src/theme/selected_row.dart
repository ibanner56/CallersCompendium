import 'package:flutter/material.dart';

/// Width (logical pixels) of the bar that marks the selected list row. The
/// same width as the set-list row accent (`program_slot_list_editor.dart`).
const double selectedRowBarWidth = 4;

/// The [ListTile.shape] for a split-pane list row (issue #2156): a
/// [selectedRowBarWidth] bar down the row's left edge in
/// [ColorScheme.primary] when [selected], and null otherwise so an unselected
/// row keeps the theme's rounded [ListTileThemeData.shape].
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
ShapeBorder? selectedRowShape(ColorScheme scheme, {required bool selected}) {
  if (!selected) return null;
  return Border(
    left: BorderSide(color: scheme.primary, width: selectedRowBarWidth),
  );
}
