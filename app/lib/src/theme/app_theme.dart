import 'package:flutter/material.dart';

import 'app_theme_extension.dart';
import 'app_typography.dart';
import 'color_schemes.dart';

/// Assembles the app's [ThemeData] from the design-system foundation:
/// palette "Hearth" [ColorScheme]s, the Fraunces/Atkinson [TextTheme], shape
/// tokens, adaptive density, and the semantic [AppThemeExtension].
///
/// This replaces the two inline seed lines that previously lived in
/// `main.dart`. Deeper component theming (buttons, chips, the shared
/// `InputDecorationTheme`, nav sub-themes) is intentionally deferred to a later
/// phase (UX-2); this foundation is non-regressive and drives color +
/// typography app-wide.
class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(AppColorSchemes.light);
  static ThemeData get dark => _build(AppColorSchemes.dark);
  static ThemeData get highContrast => _build(AppColorSchemes.highContrast);

  static ThemeData _build(ColorScheme scheme) {
    final textTheme = AppTypography.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      decorationColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      // Compact on desktop, comfortable on touch — chosen per platform.
      visualDensity: VisualDensity.adaptivePlatformDensity,
      // Keyboard focus must be visible on every interactive element
      // (accessibility-baseline). A tinted focus overlay makes traversal clear.
      focusColor: scheme.primary.withValues(alpha: 0.14),
      extensions: <ThemeExtension<dynamic>>[
        AppThemeExtension.fromColorScheme(scheme),
      ],
    );
  }
}
