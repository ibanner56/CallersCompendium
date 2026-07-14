import 'package:flutter/material.dart';

/// Palette "Hearth" — terracotta / pine / ochre. Full [ColorScheme]s (not a
/// single seed) so the high-contrast theme can reliably hit the 7:1 Perform
/// target defined in `docs/research/accessibility-baseline.md`. Hex values and
/// their WCAG contrast ratios are documented in
/// `docs/design/ux-modernization.md` §1a/§1b.
///
/// These are pure data (no widgets), consumed by [AppTheme].
class AppColorSchemes {
  const AppColorSchemes._();

  /// Light "Hearth" scheme (§1a).
  static const ColorScheme light = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF9C4A2F),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFDBCF),
    onPrimaryContainer: Color(0xFF3A0B00),
    secondary: Color(0xFF4E6B4F),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFD0E8CF),
    onSecondaryContainer: Color(0xFF0B2010),
    tertiary: Color(0xFF7A5900),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFFFDF9E),
    onTertiaryContainer: Color(0xFF261A00),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFFBF7F2),
    onSurface: Color(0xFF201A17),
    onSurfaceVariant: Color(0xFF52443C),
    surfaceContainerHighest: Color(0xFFF0E4DC),
    outline: Color(0xFF857066),
    outlineVariant: Color(0xFFD8C2B7),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF362F2B),
    onInverseSurface: Color(0xFFFBEDE6),
    inversePrimary: Color(0xFFFFB59B),
  );

  /// Dark "Hearth" scheme (§1a).
  static const ColorScheme dark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFFFB59B),
    onPrimary: Color(0xFF5A1B08),
    primaryContainer: Color(0xFF7C3218),
    onPrimaryContainer: Color(0xFFFFDBCF),
    secondary: Color(0xFFB4CCB1),
    onSecondary: Color(0xFF203622),
    secondaryContainer: Color(0xFF364E37),
    onSecondaryContainer: Color(0xFFD0E8CF),
    tertiary: Color(0xFFEFC048),
    onTertiary: Color(0xFF3F2E00),
    tertiaryContainer: Color(0xFF5B4300),
    onTertiaryContainer: Color(0xFFFFDF9E),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF1A120E),
    onSurface: Color(0xFFEDE0D9),
    onSurfaceVariant: Color(0xFFD7C3B8),
    surfaceContainerHighest: Color(0xFF3B302A),
    outline: Color(0xFFA08D82),
    outlineVariant: Color(0xFF52443C),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFEDE0D9),
    onInverseSurface: Color(0xFF362F2B),
    inversePrimary: Color(0xFF9C4A2F),
  );

  /// Shared dark-based high-contrast scheme (§1b), co-owned with Phase 5
  /// Perform mode. Outline-driven with a high-visibility focus color; every
  /// foreground/background pairing targets ≥7:1 (borders/focus ≥3:1).
  static const ColorScheme highContrast = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFFFD9C9),
    onPrimary: Color(0xFF000000),
    primaryContainer: Color(0xFFFFD9C9),
    onPrimaryContainer: Color(0xFF000000),
    secondary: Color(0xFFB2F1BD),
    onSecondary: Color(0xFF000000),
    secondaryContainer: Color(0xFFB2F1BD),
    onSecondaryContainer: Color(0xFF000000),
    tertiary: Color(0xFFFFD54A),
    onTertiary: Color(0xFF000000),
    tertiaryContainer: Color(0xFFFFD54A),
    onTertiaryContainer: Color(0xFF000000),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF000000),
    errorContainer: Color(0xFFFFB4AB),
    onErrorContainer: Color(0xFF000000),
    surface: Color(0xFF0A0705),
    onSurface: Color(0xFFFFF3EC),
    onSurfaceVariant: Color(0xFFFFF3EC),
    surfaceContainerHighest: Color(0xFF1F1712),
    outline: Color(0xFFFFF3EC),
    outlineVariant: Color(0xFFFFF3EC),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFFFF3EC),
    onInverseSurface: Color(0xFF0A0705),
    inversePrimary: Color(0xFF9C4A2F),
  );
}
