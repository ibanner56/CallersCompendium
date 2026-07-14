import 'package:flutter/material.dart';

import 'app_shapes.dart';
import 'app_theme_extension.dart';
import 'app_typography.dart';
import 'color_schemes.dart';

/// Assembles the app's [ThemeData] from the design-system foundation:
/// palette "Hearth" [ColorScheme]s, the Fraunces/Atkinson [TextTheme],
/// adaptive density, a visible keyboard-focus color, and the semantic
/// [AppThemeExtension] (which carries the spacing/shape/status/focus-ring
/// tokens for widgets to read).
///
/// This replaces the two inline seed lines that previously lived in
/// `main.dart`. Deeper *default-theme* component theming (buttons, chips, the
/// shared `InputDecorationTheme`, nav sub-themes, and applying the shape tokens
/// to `CardTheme`/`DialogTheme` in light/dark) is intentionally deferred to a
/// later phase (UX-2); this foundation is non-regressive and drives color +
/// typography app-wide.
///
/// The **high-contrast** theme is the exception: because HC deliberately
/// defeats tonal/elevation cues, it is *outline-driven* (real borders) with a
/// high-visibility ≥3px focus ring (`#FFD54A`) per UX-1 (`ux-modernization.md`
/// §1b, §7). Those sub-themes are scoped to the HC build path only, so light
/// and dark are unaffected.
class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(AppColorSchemes.light);
  static ThemeData get dark => _build(AppColorSchemes.dark);
  static ThemeData get highContrast =>
      _build(AppColorSchemes.highContrast, highContrast: true);

  static ThemeData _build(ColorScheme scheme, {bool highContrast = false}) {
    final textTheme = AppTypography.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      decorationColor: scheme.onSurface,
    );

    final extension = AppThemeExtension.fromColorScheme(
      scheme,
      highContrast: highContrast,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      // Compact on desktop, comfortable on touch — chosen per platform.
      visualDensity: VisualDensity.adaptivePlatformDensity,
      // Keyboard focus must be visible on every interactive element
      // (accessibility-baseline). A tinted focus overlay makes traversal clear;
      // high-contrast uses a stronger, high-visibility tint of the focus ring.
      focusColor: highContrast
          ? extension.focusRing.withValues(alpha: 0.30)
          : scheme.primary.withValues(alpha: 0.14),
      // High-contrast is outline-driven (UX-1). These sub-themes give real
      // borders and a ≥3px focus ring; they are null for light/dark so those
      // themes keep the M3 tonal defaults until UX-2.
      cardTheme: highContrast ? _hcCardTheme(scheme) : null,
      dialogTheme: highContrast ? _hcDialogTheme(scheme) : null,
      inputDecorationTheme: highContrast ? _hcInputTheme(extension) : null,
      dividerTheme: highContrast
          ? DividerThemeData(color: scheme.outline, thickness: 1.5)
          : null,
      outlinedButtonTheme: highContrast
          ? OutlinedButtonThemeData(style: _hcButtonStyle(scheme, extension))
          : null,
      filledButtonTheme: highContrast
          ? FilledButtonThemeData(style: _hcButtonStyle(scheme, extension))
          : null,
      extensions: <ThemeExtension<dynamic>>[extension],
    );
  }

  // --- High-contrast, outline-driven sub-themes (UX-1) ---------------------

  static CardThemeData _hcCardTheme(ColorScheme scheme) => CardThemeData(
    // Tonal elevation is invisible at HC, so cards are defined by an outline.
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: AppShapes.borderRadiusMedium,
      side: BorderSide(color: scheme.outline, width: 1.5),
    ),
  );

  static DialogThemeData _hcDialogTheme(ColorScheme scheme) => DialogThemeData(
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.all(
        Radius.circular(AppShapes.radiusDialog),
      ),
      side: BorderSide(color: scheme.outline, width: 1.5),
    ),
  );

  static InputDecorationThemeData _hcInputTheme(AppThemeExtension ext) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: AppShapes.borderRadiusSmall,
      borderSide: BorderSide(color: color, width: width),
    );
    return InputDecorationThemeData(
      // Fields are always outlined at HC; focus swaps to a thick focus ring.
      border: border(ext.performOnSurface, 1.5),
      enabledBorder: border(ext.performOnSurface, 1.5),
      focusedBorder: border(ext.focusRing, ext.focusRingWidth),
      errorBorder: border(ext.statusBroken, 1.5),
      focusedErrorBorder: border(ext.focusRing, ext.focusRingWidth),
    );
  }

  static ButtonStyle _hcButtonStyle(ColorScheme scheme, AppThemeExtension ext) {
    return ButtonStyle(
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: AppShapes.borderRadiusSmall),
      ),
      // A real border always, thickening into the high-visibility focus ring
      // when focused so keyboard focus is unmistakable (≥3px, UX-1 AC).
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return BorderSide(color: ext.focusRing, width: ext.focusRingWidth);
        }
        return BorderSide(color: scheme.outline, width: 1.5);
      }),
    );
  }
}
