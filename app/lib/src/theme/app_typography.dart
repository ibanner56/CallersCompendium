import 'package:flutter/material.dart';

/// Typography for the design system (§1c). Two bundled, offline OFL families:
///
/// - [displayFamily] **Fraunces** — a warm optical-size serif used for display
///   and headline styles. Variable (opsz/wght); weight is requested via the
///   normal [TextStyle.fontWeight] pipeline.
/// - [bodyFamily] **Atkinson Hyperlegible** — designed by the Braille Institute
///   for low-vision legibility; used for titles, body, labels, and Perform.
///
/// Font families are registered in `app/pubspec.yaml`. Roboto stays bundled as
/// a documented fallback.
class AppTypography {
  const AppTypography._();

  static const String displayFamily = 'Fraunces';
  static const String bodyFamily = 'AtkinsonHyperlegible';

  /// Families to fall back to when a glyph is missing, in order.
  static const List<String> _fallback = <String>['Roboto'];

  /// The app [TextTheme]: Fraunces for display/headline, Atkinson for
  /// title/body/label. Sizes follow §1c. Colors are left null so the theme's
  /// [ColorScheme] drives them (keeps light/dark/high-contrast correct).
  static const TextTheme textTheme = TextTheme(
    displayLarge: TextStyle(
      fontFamily: displayFamily,
      fontFamilyFallback: _fallback,
      fontSize: 57,
      fontWeight: FontWeight.w600,
      height: 1.12,
    ),
    displayMedium: TextStyle(
      fontFamily: displayFamily,
      fontFamilyFallback: _fallback,
      fontSize: 45,
      fontWeight: FontWeight.w600,
      height: 1.16,
    ),
    displaySmall: TextStyle(
      fontFamily: displayFamily,
      fontFamilyFallback: _fallback,
      fontSize: 36,
      fontWeight: FontWeight.w600,
      height: 1.22,
    ),
    headlineLarge: TextStyle(
      fontFamily: displayFamily,
      fontFamilyFallback: _fallback,
      fontSize: 32,
      fontWeight: FontWeight.w500,
      height: 1.25,
    ),
    headlineMedium: TextStyle(
      fontFamily: displayFamily,
      fontFamilyFallback: _fallback,
      fontSize: 28,
      fontWeight: FontWeight.w500,
      height: 1.29,
    ),
    headlineSmall: TextStyle(
      fontFamily: displayFamily,
      fontFamilyFallback: _fallback,
      fontSize: 24,
      fontWeight: FontWeight.w500,
      height: 1.33,
    ),
    titleLarge: TextStyle(
      fontFamily: bodyFamily,
      fontFamilyFallback: _fallback,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.27,
    ),
    titleMedium: TextStyle(
      fontFamily: bodyFamily,
      fontFamilyFallback: _fallback,
      fontSize: 16,
      fontWeight: FontWeight.w700,
      height: 1.50,
      letterSpacing: 0.15,
    ),
    titleSmall: TextStyle(
      fontFamily: bodyFamily,
      fontFamilyFallback: _fallback,
      fontSize: 14,
      fontWeight: FontWeight.w700,
      height: 1.43,
      letterSpacing: 0.1,
    ),
    bodyLarge: TextStyle(
      fontFamily: bodyFamily,
      fontFamilyFallback: _fallback,
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.50,
      letterSpacing: 0.15,
    ),
    bodyMedium: TextStyle(
      fontFamily: bodyFamily,
      fontFamilyFallback: _fallback,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.43,
      letterSpacing: 0.25,
    ),
    bodySmall: TextStyle(
      fontFamily: bodyFamily,
      fontFamilyFallback: _fallback,
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.33,
      letterSpacing: 0.4,
    ),
    labelLarge: TextStyle(
      fontFamily: bodyFamily,
      fontFamilyFallback: _fallback,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.43,
      letterSpacing: 0.1,
    ),
    labelMedium: TextStyle(
      fontFamily: bodyFamily,
      fontFamilyFallback: _fallback,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      height: 1.33,
      letterSpacing: 0.5,
    ),
    labelSmall: TextStyle(
      fontFamily: bodyFamily,
      fontFamilyFallback: _fallback,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      height: 1.45,
      letterSpacing: 0.5,
    ),
  );
}
