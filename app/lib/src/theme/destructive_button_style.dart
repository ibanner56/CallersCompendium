import 'package:flutter/material.dart';

/// The style for the confirm button of a dialog whose action deletes, wipes,
/// resets, replaces or discards the user's data: a [FilledButton] in the theme's `error` /
/// `onError` pair.
///
/// One shared style, so every such confirm reads as dangerous in the same way
/// and none looks like an ordinary primary action. Colour is additive only —
/// the label must still name the action ("Delete", "Replace all data").
/// Every bundled theme is tested to keep `onError` on `error` at AA: the gallery
/// palettes in `test/theme/palette_contrast_test.dart`, the default light,
/// dark and high-contrast themes in
/// `test/theme/destructive_button_style_test.dart`.
///
/// A style rather than a widget, so the button stays a plain [FilledButton]
/// for everything that looks one up by type.
ButtonStyle destructiveFilledButtonStyle(ColorScheme scheme) =>
    FilledButton.styleFrom(
      backgroundColor: scheme.error,
      foregroundColor: scheme.onError,
    );

/// The style for a [TextButton] that takes a destructive action while a safer
/// choice beside it is the filled primary: the theme's `error` colour as the
/// label, with no fill (D-1 for the "Discard changes?" dialog).
///
/// The label must still name the action; colour is additive only.
ButtonStyle destructiveTextButtonStyle(ColorScheme scheme) =>
    TextButton.styleFrom(foregroundColor: scheme.error);
