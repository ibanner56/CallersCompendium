import 'package:flutter/material.dart';

/// Palette "Blue Hour" — cool daylight/petrol canvas with warm lantern-amber
/// accents (evolved from the original warm "Hearth"). Full [ColorScheme]s (not
/// a single seed) so the high-contrast theme can reliably hit the 7:1 Perform
/// target defined in `docs/research/accessibility-baseline.md`. Hex values and
/// their WCAG contrast ratios are documented in
/// `docs/design/ux-modernization.md` §1a/§1b.
///
/// These are pure data (no widgets), consumed by [AppTheme].
class AppColorSchemes {
  const AppColorSchemes._();

  /// Light "Blue Hour" scheme (§1a). Cool daylight canvas paired with the same
  /// warm lantern-amber accent family as the dark scheme, so toggling light↔dark
  /// keeps one identity. Every meaningful pair clears WCAG AA.
  static const ColorScheme light = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF9A5312),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFDCC2),
    onPrimaryContainer: Color(0xFF331200),
    secondary: Color(0xFF8C4A43),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFFFDAD3),
    onSecondaryContainer: Color(0xFF3A0906),
    tertiary: Color(0xFF6E5A16),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFF5E7A8),
    onTertiaryContainer: Color(0xFF221B00),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFF4F6FA),
    onSurface: Color(0xFF1A222C),
    onSurfaceVariant: Color(0xFF48515C),
    surfaceContainerHighest: Color(0xFFE3E8EF),
    outline: Color(0xFF727C87),
    outlineVariant: Color(0xFFC7CDD6),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF2F3742),
    onInverseSurface: Color(0xFFF0F2F6),
    inversePrimary: Color(0xFFFFB784),
  );

  /// Dark "Blue Hour" scheme (§1a). Deep petrol-indigo canvas with warm
  /// lantern-amber accents: cool surface makes the warm primary/secondary
  /// glow in a dark hall, while every meaningful pair clears WCAG AA (most
  /// clear the 7:1 Perform target too).
  static const ColorScheme dark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFFFB784),
    onPrimary: Color(0xFF4A2400),
    primaryContainer: Color(0xFF6B3D12),
    onPrimaryContainer: Color(0xFFFFDCC2),
    secondary: Color(0xFFE4A9A0),
    onSecondary: Color(0xFF45201C),
    secondaryContainer: Color(0xFF5E332E),
    onSecondaryContainer: Color(0xFFFFDAD3),
    tertiary: Color(0xFFD8C98A),
    onTertiary: Color(0xFF382F09),
    tertiaryContainer: Color(0xFF4F461F),
    onTertiaryContainer: Color(0xFFF5E7A8),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF121A24),
    onSurface: Color(0xFFE7ECF1),
    onSurfaceVariant: Color(0xFFB4C1CE),
    surfaceContainerHighest: Color(0xFF253241),
    outline: Color(0xFF7B8896),
    outlineVariant: Color(0xFF384654),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE7ECF1),
    onInverseSurface: Color(0xFF1B242E),
    inversePrimary: Color(0xFF8A5000),
  );

  /// "Soft Dark" — a dimmed sibling of [dark] (§1a). Same warm lantern-amber
  /// identity and content colors, but on a lighter, softer petrol-slate canvas
  /// (`#1E2A38` vs the standard `#121A24`) for callers who find the deep canvas
  /// too stark in a lit room — the same relationship GitHub Dark has to its
  /// dimmed variant. Every meaningful pair still clears WCAG AA.
  static const ColorScheme softDark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFFFB784),
    onPrimary: Color(0xFF4A2400),
    primaryContainer: Color(0xFF6B3D12),
    onPrimaryContainer: Color(0xFFFFDCC2),
    secondary: Color(0xFFE4A9A0),
    onSecondary: Color(0xFF45201C),
    secondaryContainer: Color(0xFF5E332E),
    onSecondaryContainer: Color(0xFFFFDAD3),
    tertiary: Color(0xFFD8C98A),
    onTertiary: Color(0xFF382F09),
    tertiaryContainer: Color(0xFF4F461F),
    onTertiaryContainer: Color(0xFFF5E7A8),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF1E2A38),
    onSurface: Color(0xFFE7ECF1),
    onSurfaceVariant: Color(0xFFB4C1CE),
    surfaceContainerHighest: Color(0xFF303D4C),
    outline: Color(0xFF7B8896),
    outlineVariant: Color(0xFF43515F),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE7ECF1),
    onInverseSurface: Color(0xFF263341),
    inversePrimary: Color(0xFF8A5000),
  );

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
